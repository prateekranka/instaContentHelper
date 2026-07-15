import { weekDates } from "./generation.ts";
import type {
  GeneratedDailyCard,
  GeneratedDayOutput,
  GeneratedWeekOutput,
} from "./generation.ts";

export type DayGenerationStatus =
  | "pending"
  | "running"
  | "completed"
  | "failed";
export type GenerationOverallStatus =
  | "running"
  | "completed"
  | "partial"
  | "failed";
export type QueuedDayJobStatus =
  | "queued"
  | "generating"
  | "generated"
  | "failed"
  | "retrying"
  | "cancelled"
  | "ready_to_persist";

export type DayGenerationState = {
  scheduled_date: string;
  status: DayGenerationStatus;
  attempts: number;
  daily_card_id?: string;
  started_at?: string;
  completed_at?: string;
  // Last proof-of-life write from the worker that owns this running day.
  // Staleness is measured against this (falling back to started_at) so a
  // live worker awaiting a slow provider is never declared stale.
  heartbeat_at?: string;
  error_code?: string;
  output?: GeneratedDayOutput;
};

export type PerDayGenerationSnapshot = {
  kind: "per_day_generation_v1" | "parallel_week_generation_v1";
  week_start_date: string;
  weekly_plan_id?: string;
  strategy_created?: boolean;
  strategy_summary?: string;
  source_summary?: string;
  warnings?: string[];
  assumptions?: string[];
  days: DayGenerationState[];
  updated_at: string;
};

export type DayGenerationStatusResponse = {
  scheduled_date: string;
  day_index: number;
  status: DayGenerationStatus;
  error_code: string | null;
  daily_card_id: string | null;
  drafted: boolean;
  saved: boolean;
  attempt_count: number;
  started_at: string | null;
  completed_at: string | null;
  retry_action?: "regenerate_day";
};

export type QueuedDayJobRecord = {
  id: string;
  generation_run_id: string;
  weekly_plan_id: string;
  workspace_id: string;
  creator_id: string;
  scheduled_date: string;
  day_index: number;
  status: QueuedDayJobStatus;
  attempt_count?: number | null;
  daily_card_id?: string | null;
  error_code?: string | null;
  error_message?: string | null;
  started_at?: string | null;
  completed_at?: string | null;
  heartbeat_at?: string | null;
  lease_token?: string | null;
  worker_boot_id?: string | null;
  staged_output?: Record<string, unknown> | null;
};

export type QueuedDayStatusResponse = {
  scheduled_date: string;
  day_index: number;
  status: QueuedDayJobStatus;
  error_code: string | null;
  daily_card_id: string | null;
  drafted: boolean;
  saved: boolean;
  attempt_count: number;
  started_at: string | null;
  completed_at: string | null;
  retry_action?: "retry_day";
};

export type WeekGenerationStatusSummary = {
  overall_status: GenerationOverallStatus;
  strategy_created: boolean;
  drafted_day_count: number;
  saved_day_count: number;
  failed_day_count: number;
  completed_day_count: number;
  total_day_count: number;
  current_day: string | null;
  day_statuses: DayGenerationStatusResponse[];
};

export function initialPerDayGenerationSnapshot(
  weekStartDate: string,
): PerDayGenerationSnapshot {
  return {
    kind: "per_day_generation_v1",
    week_start_date: weekStartDate,
    days: weekDates(weekStartDate).map((scheduledDate) => ({
      scheduled_date: scheduledDate,
      status: "pending",
      attempts: 0,
    })),
    updated_at: new Date().toISOString(),
  };
}

export function initialParallelWeekGenerationSnapshot(
  weekStartDate: string,
  weeklyPlanID: string,
  strategy: GeneratedWeekOutput,
): PerDayGenerationSnapshot {
  return {
    ...initialPerDayGenerationSnapshot(weekStartDate),
    kind: "parallel_week_generation_v1",
    weekly_plan_id: weeklyPlanID,
    strategy_created: true,
    strategy_summary: strategy.strategy_summary,
    source_summary: strategy.source_summary,
    warnings: strategy.warnings,
    assumptions: strategy.assumptions,
  };
}

export function normalizePerDayGenerationSnapshot(
  value: unknown,
  weekStartDate: string,
): PerDayGenerationSnapshot {
  const initial = initialPerDayGenerationSnapshot(weekStartDate);
  if (
    !isRecord(value) ||
    (value.kind !== "per_day_generation_v1" &&
      value.kind !== "parallel_week_generation_v1")
  ) {
    return initial;
  }

  const rows = Array.isArray(value.days) ? value.days : [];
  const byDate = new Map<string, Record<string, unknown>>(
    rows.filter(isRecord).flatMap((day) => {
      const scheduledDate = stringValue(day.scheduled_date);
      return scheduledDate ? [[scheduledDate, day]] : [];
    }),
  );

  return {
    kind: value.kind,
    week_start_date: weekStartDate,
    weekly_plan_id: stringValue(value.weekly_plan_id),
    strategy_created: value.strategy_created === true,
    strategy_summary: stringValue(value.strategy_summary),
    source_summary: stringValue(value.source_summary),
    warnings: stringArray(value.warnings),
    assumptions: stringArray(value.assumptions),
    days: initial.days.map((day) =>
      normalizeDayGenerationState(byDate.get(day.scheduled_date), day)
    ),
    updated_at: stringValue(value.updated_at) ?? initial.updated_at,
  };
}

function normalizeDayGenerationState(
  value: Record<string, unknown> | undefined,
  fallback: DayGenerationState,
): DayGenerationState {
  if (!value) {
    return fallback;
  }
  const status = normalizeDayGenerationStatus(value.status) ??
    fallback.status;
  const output = isRecord(value.output)
    ? value.output as unknown as GeneratedDayOutput
    : undefined;
  const dailyCardID = stringValue(value.daily_card_id);
  return {
    scheduled_date: fallback.scheduled_date,
    status: status === "completed" && !output && !dailyCardID
      ? "pending"
      : status,
    attempts: numberValue(value.attempts) ?? fallback.attempts,
    daily_card_id: dailyCardID,
    started_at: stringValue(value.started_at),
    completed_at: stringValue(value.completed_at),
    heartbeat_at: stringValue(value.heartbeat_at),
    error_code: stringValue(value.error_code),
    output,
  };
}

export function weekGenerationStatusSummary(
  progress: PerDayGenerationSnapshot,
  storedRunStatus: string,
  isTerminalDayGenerationState: (day: DayGenerationState) => boolean,
): WeekGenerationStatusSummary {
  const dayStatuses = progress.days.map((day, index) =>
    dayGenerationStatusResponse(day, index)
  );
  const draftedDayCount = dayStatuses.filter((day) => day.drafted).length;
  const savedDayCount = dayStatuses.filter((day) => day.saved).length;
  const failedDayCount =
    dayStatuses.filter((day) => day.status === "failed").length;
  const currentDay = dayStatuses.find((day) => day.status === "running")
    ?.scheduled_date ?? null;
  const hasUsableDays = draftedDayCount > 0 || savedDayCount > 0;
  const allTerminal = dayStatuses.length > 0 &&
    progress.days.every(isTerminalDayGenerationState);

  let overallStatus: GenerationOverallStatus = "running";
  if (
    draftedDayCount === dayStatuses.length && dayStatuses.length > 0 &&
    failedDayCount === 0
  ) {
    overallStatus = "completed";
  } else if (allTerminal || storedRunStatus === "failed") {
    overallStatus = hasUsableDays ? "partial" : "failed";
  }

  return {
    overall_status: overallStatus,
    strategy_created: progress.strategy_created === true,
    drafted_day_count: draftedDayCount,
    saved_day_count: savedDayCount,
    failed_day_count: failedDayCount,
    completed_day_count: draftedDayCount,
    total_day_count: dayStatuses.length,
    current_day: currentDay,
    day_statuses: dayStatuses,
  };
}

export function queuedDayJobStatusSummary(
  jobs: QueuedDayJobRecord[],
): Omit<WeekGenerationStatusSummary, "day_statuses"> & {
  day_statuses: QueuedDayStatusResponse[];
} {
  const dayStatuses = jobs.map(queuedDayJobStatusResponse);
  const savedDayCount = dayStatuses.filter((day) => day.saved).length;
  const failedDayCount =
    dayStatuses.filter((day) => day.status === "failed").length;
  const completedDayCount =
    dayStatuses.filter((day) => day.status === "generated").length;
  const cancelledDayCount =
    dayStatuses.filter((day) => day.status === "cancelled").length;
  const runningDay = dayStatuses.find((day) => day.status === "generating");
  const totalDayCount = dayStatuses.length;
  const terminalDayCount = completedDayCount + failedDayCount +
    cancelledDayCount;
  const hasActiveWork = dayStatuses.some((day) =>
    day.status === "queued" || day.status === "generating" ||
    day.status === "retrying"
  );

  let overallStatus: GenerationOverallStatus = "running";
  if (totalDayCount > 0 && completedDayCount === totalDayCount) {
    overallStatus = "completed";
  } else if (totalDayCount > 0 && terminalDayCount === totalDayCount) {
    overallStatus = completedDayCount > 0 ? "partial" : "failed";
  } else if (!hasActiveWork && failedDayCount > 0) {
    overallStatus = completedDayCount > 0 ? "partial" : "failed";
  }

  return {
    overall_status: overallStatus,
    strategy_created: true,
    drafted_day_count: completedDayCount,
    saved_day_count: savedDayCount,
    failed_day_count: failedDayCount,
    completed_day_count: completedDayCount,
    total_day_count: totalDayCount,
    current_day: runningDay?.scheduled_date ?? null,
    day_statuses: dayStatuses,
  };
}

export function queuedDayJobStatusResponse(
  job: QueuedDayJobRecord,
): QueuedDayStatusResponse {
  const saved = Boolean(job.daily_card_id);
  const publicStatus = job.status === "ready_to_persist"
    ? "generating"
    : job.status;
  return {
    scheduled_date: job.scheduled_date,
    day_index: job.day_index,
    status: publicStatus,
    error_code: job.error_code ?? null,
    daily_card_id: job.daily_card_id ?? null,
    drafted: job.status === "generated" || saved,
    saved,
    attempt_count: job.attempt_count ?? 0,
    started_at: job.started_at ?? null,
    completed_at: job.completed_at ?? null,
    retry_action: job.status === "failed" ? "retry_day" : undefined,
  };
}

export function dayGenerationStatusResponse(
  day: DayGenerationState,
  index: number,
): DayGenerationStatusResponse {
  const saved = Boolean(day.daily_card_id);
  const drafted = Boolean(day.output) || saved;
  return {
    scheduled_date: day.scheduled_date,
    day_index: index,
    status: day.status,
    error_code: day.error_code ?? null,
    daily_card_id: day.daily_card_id ?? null,
    drafted,
    saved,
    attempt_count: day.attempts,
    started_at: day.started_at ?? null,
    completed_at: day.completed_at ?? null,
    retry_action: day.status === "failed" ? "regenerate_day" : undefined,
  };
}

type CompletedDraftStatusSnapshot = {
  daily_cards: GeneratedDailyCard[];
  strategy_summary: string;
  generated_at: string;
};

export function completedDraftStatusSummary(
  snapshot: CompletedDraftStatusSnapshot,
  weekStartDate: string | undefined,
): WeekGenerationStatusSummary {
  const cardsByDate = new Map<string, GeneratedDailyCard>(
    snapshot.daily_cards.flatMap((card) =>
      card.scheduled_date ? [[card.scheduled_date, card]] : []
    ),
  );
  const scheduledDates = weekStartDate
    ? weekDates(weekStartDate)
    : snapshot.daily_cards.map((card) => card.scheduled_date).filter((
      value,
    ): value is string => Boolean(value));
  const dayStatuses = scheduledDates.map((scheduledDate, index) => {
    const card = cardsByDate.get(scheduledDate);
    return {
      scheduled_date: scheduledDate,
      day_index: index,
      status: card ? "completed" as const : "pending" as const,
      error_code: null,
      daily_card_id: card?.id ?? null,
      drafted: Boolean(card),
      saved: Boolean(card?.id),
      attempt_count: 1,
      started_at: null,
      completed_at: snapshot.generated_at,
    };
  });
  const savedDayCount = dayStatuses.filter((day) => day.saved).length;
  const draftedDayCount = dayStatuses.filter((day) => day.drafted).length;
  return {
    overall_status: draftedDayCount === dayStatuses.length
      ? "completed"
      : draftedDayCount > 0
      ? "partial"
      : "failed",
    strategy_created: Boolean(snapshot.strategy_summary),
    drafted_day_count: draftedDayCount,
    saved_day_count: savedDayCount,
    failed_day_count: 0,
    completed_day_count: draftedDayCount,
    total_day_count: dayStatuses.length,
    current_day: null,
    day_statuses: dayStatuses,
  };
}

function normalizeDayGenerationStatus(
  value: unknown,
): DayGenerationStatus | undefined {
  return value === "pending" || value === "running" ||
      value === "completed" || value === "failed"
    ? value
    : undefined;
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0
    ? value
    : undefined;
}

function numberValue(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : undefined;
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item) => typeof item === "string")
    : [];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
