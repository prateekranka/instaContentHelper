import {
  GeneratedDailyCard,
  GeneratedDayOutput,
  GeneratedWeekOutput,
  GenerateWeekRequest,
  GenerationInputSnapshot,
  isUUID,
  RegenerateDayRequest,
} from "./generation.ts";
import type { PerDayGenerationSnapshot } from "./generation-status.ts";

export type GenerateWeekDraftResponse = {
  generation_id: string;
  weekly_plan_id: string;
  status: "draft";
  strategy_summary: string;
  warnings: string[];
  assumptions: string[];
  daily_cards: GeneratedDailyCard[];
  idea_bank: Record<string, unknown>[];
  source_summary: string;
  generated_at: string;
};

export type RegenerateDayDraftResponse = {
  generation_id: string;
  weekly_plan_id: string;
  status: "draft";
  target_scheduled_date: string;
  daily_card: GeneratedDailyCard;
  warnings: string[];
  assumptions: string[];
  source_summary: string;
  generated_at: string;
};

export type GenerationRunStatusRecord = Record<string, unknown> & {
  id: string;
  workspace_id: string;
  creator_id: string;
  weekly_setup_id?: string | null;
  requested_by_member_id?: string | null;
  status?: string;
  weekly_plan_id?: string | null;
  output_snapshot?: unknown;
  input_snapshot?: unknown;
  error_code?: string | null;
  generation_scope?: string;
  target_daily_card_id?: string | null;
  target_scheduled_date?: string | null;
};

export type SingleDayGenerationSnapshot = {
  kind: "single_day_generation_v1";
  scheduled_date: string;
  preserve_manual_edits: boolean;
  status: "pending" | "running";
  started_at?: string;
  updated_at: string;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0
    ? value
    : undefined;
}

function recordArray(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value) ? value.filter(isRecord) : [];
}

export function isDraftResponseSnapshot(
  value: unknown,
): value is GenerateWeekDraftResponse {
  return isRecord(value) &&
    isUUID(stringValue(value.generation_id)) &&
    isUUID(stringValue(value.weekly_plan_id)) &&
    value.status === "draft" &&
    Array.isArray(value.daily_cards) &&
    Array.isArray(value.idea_bank);
}

export function isDayDraftResponseSnapshot(
  value: unknown,
): value is RegenerateDayDraftResponse {
  return isRecord(value) &&
    isUUID(stringValue(value.generation_id)) &&
    isUUID(stringValue(value.weekly_plan_id)) &&
    value.status === "draft" &&
    typeof value.target_scheduled_date === "string" &&
    isRecord(value.daily_card);
}

export function initialSingleDayGenerationSnapshot(
  request: RegenerateDayRequest,
  nowISO: string = new Date().toISOString(),
): SingleDayGenerationSnapshot {
  return {
    kind: "single_day_generation_v1",
    scheduled_date: request.scheduled_date,
    preserve_manual_edits: request.preserve_manual_edits,
    status: "pending",
    updated_at: nowISO,
  };
}

export function normalizeSingleDayGenerationSnapshot(
  value: unknown,
  run: GenerationRunStatusRecord,
  nowISO: string = new Date().toISOString(),
): SingleDayGenerationSnapshot | null {
  const scheduledDate = stringValue(run.target_scheduled_date);
  if (!scheduledDate || !isRecord(value)) {
    return null;
  }
  if (
    value.kind !== "single_day_generation_v1" ||
    value.scheduled_date !== scheduledDate
  ) {
    return null;
  }
  const status = value.status === "running" ? "running" : "pending";
  return {
    kind: "single_day_generation_v1",
    scheduled_date: scheduledDate,
    preserve_manual_edits: value.preserve_manual_edits !== false,
    status,
    started_at: stringValue(value.started_at),
    updated_at: stringValue(value.updated_at) ?? nowISO,
  };
}

export function normalizeStoredInputSnapshot(
  value: unknown,
): GenerationInputSnapshot | null {
  if (!isRecord(value) || !isUUID(stringValue(value.creator_id))) {
    return null;
  }
  const weekStartDate = stringValue(value.week_start_date);
  if (!weekStartDate) {
    return null;
  }
  return {
    creator_id: stringValue(value.creator_id) ?? "",
    week_start_date: weekStartDate,
    creator_profile: isRecord(value.creator_profile)
      ? value.creator_profile
      : null,
    weekly_setup: isRecord(value.weekly_setup) ? value.weekly_setup : null,
    confirmed_references: recordArray(value.confirmed_references),
    reference_extractions: recordArray(value.reference_extractions),
    recent_archive: recordArray(value.recent_archive),
    idea_bank: recordArray(value.idea_bank),
    patterns: recordArray(value.patterns),
    trends: recordArray(value.trends),
    audio_options: recordArray(value.audio_options),
    brand_briefs: recordArray(value.brand_briefs),
    key_moments: recordArray(value.key_moments),
    existing_week_cards: recordArray(value.existing_week_cards),
  };
}

export function requestFromRun(
  run: GenerationRunStatusRecord,
  inputSnapshot: GenerationInputSnapshot,
): GenerateWeekRequest {
  return {
    creator_id: run.creator_id,
    week_start_date: inputSnapshot.week_start_date,
    weekly_setup_id: stringValue(run.weekly_setup_id),
    mode: "regenerate_draft",
    preserve_manual_edits: false,
    mock: false,
    response_mode: "async",
  };
}

export function makeGeneratedWeekOutputFromCompletedDays(
  dayOutputs: GeneratedDayOutput[],
  progress: PerDayGenerationSnapshot,
  strategyFallback: Pick<
    GeneratedWeekOutput,
    "strategy_summary" | "source_summary"
  >,
): GeneratedWeekOutput {
  return {
    strategy_summary: progress.strategy_summary ??
      combineNonBlankStrings(
        dayOutputs.map((output) => output.strategy_note),
        strategyFallback.strategy_summary,
      ),
    warnings: uniqueNonBlankStrings(
      dayOutputs.flatMap((output) => output.warnings),
    ),
    assumptions: uniqueNonBlankStrings(
      dayOutputs.flatMap((output) => output.assumptions),
    ),
    daily_cards: dayOutputs.map((output) => output.daily_card),
    idea_bank: dayOutputs.flatMap((output) => output.idea_bank).slice(0, 14),
    source_summary: progress.source_summary ??
      combineNonBlankStrings(
        dayOutputs.map((output) => output.source_summary),
        strategyFallback.source_summary,
      ),
  };
}

export function combineNonBlankStrings(
  values: string[],
  fallback: string,
): string {
  const combined = uniqueNonBlankStrings(values).join(" ");
  return combined.length > 0 ? combined : fallback;
}

export function uniqueNonBlankStrings(values: string[]): string[] {
  const seen = new Set<string>();
  return values.flatMap((value) => {
    const normalized = value.trim();
    const key = normalized.toLowerCase();
    if (!normalized || seen.has(key)) {
      return [];
    }
    seen.add(key);
    return [normalized];
  });
}
