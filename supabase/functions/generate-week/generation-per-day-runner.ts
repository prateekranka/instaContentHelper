import { jsonResponse, SupabaseAdminClient } from "../_shared/device-auth.ts";
import type { VerifiedDeviceSession } from "../_shared/device-auth.ts";
import {
  combineGeneratedDayOutputs,
  GeneratedDailyCard,
  GeneratedDayOutput,
  GeneratedWeekOutput,
  GenerateWeekRequest,
  GenerateWeekValidationError,
  GenerationInputSnapshot,
} from "./generation.ts";
import type { AIGenerationPhase, AIProviderConfig } from "./generation.ts";
import { weekGenerationStatusSummary } from "./generation-status.ts";
import type {
  DayGenerationState,
  PerDayGenerationSnapshot,
} from "./generation-status.ts";
import {
  makeGeneratedWeekOutputFromCompletedDays,
  requestFromRun,
  uniqueNonBlankStrings,
} from "./generation-run-snapshot.ts";
import type {
  GenerateWeekDraftResponse,
  GenerationRunStatusRecord,
  SingleDayGenerationSnapshot,
} from "./generation-run-snapshot.ts";
import { generationPersistFailure } from "./generation-persistence.ts";
import { updateGenerationRunProgress } from "./generation-run-store.ts";
import {
  allDaysCompleted,
  allDaysTerminal,
  isRunningDayStale,
  isTerminalDayGenerationState,
  shouldRunDayGeneration,
  staleDayFailure,
} from "./generation-day-progress.ts";
import {
  completePartialGenerationRun,
  maxDayGenerationAttempts,
  runningDayStaleMS,
} from "./generation-parallel-week-worker.ts";

export type PerDayRunnerPreparedGeneration = {
  request: GenerateWeekRequest;
  session: VerifiedDeviceSession;
  weeklySetup: Record<string, unknown> | null;
  inputSnapshot: GenerationInputSnapshot;
  providers: AIProviderConfig[];
  model: string;
  mockEnabled: boolean;
};

export type PerDayRunnerHost = {
  generateDayOutput: (
    prepared: PerDayRunnerPreparedGeneration,
    scheduledDate: string,
    dayIndex: number,
    generationID: string,
    phase: AIGenerationPhase,
    retryContext?: Record<string, unknown>,
  ) => Promise<GeneratedDayOutput>;
  markGenerationRunFailed: (
    admin: SupabaseAdminClient,
    generationID: string,
    errorCode: string,
  ) => Promise<void>;
  persistGeneratedWeek: (
    admin: SupabaseAdminClient,
    workspaceID: string,
    request: GenerateWeekRequest,
    memberID: string,
    weeklySetup: Record<string, unknown> | null,
    inputSnapshot: GenerationInputSnapshot,
    generated: GeneratedWeekOutput,
  ) => Promise<
    {
      weeklyPlanID: string;
      dailyCards: GeneratedDailyCard[];
      ideaBank: Record<string, unknown>[];
    } | { response: Response }
  >;
  makeGenerateWeekDraftResponse: (
    generationID: string,
    weeklyPlanID: string,
    generated: GeneratedWeekOutput,
    dailyCards: GeneratedDailyCard[],
    ideaBank: Record<string, unknown>[],
    generatedAt: string,
  ) => GenerateWeekDraftResponse;
  completeGenerationRun: (
    admin: SupabaseAdminClient,
    generationID: string,
    weeklyPlanID: string,
    payload: GenerateWeekDraftResponse,
    completedAt: string,
  ) => Promise<{ ok: true } | { response: Response }>;
  persistenceFailureStep: (response: Response) => Promise<string | null>;
  makeInitialWeekStrategyOutput: (
    inputSnapshot: GenerationInputSnapshot,
  ) => GeneratedWeekOutput;
  scheduleBackgroundTask: (promise: Promise<void>) => void;
};

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0
    ? value
    : undefined;
}

function stableGenerationError(error: unknown): string {
  if (error instanceof GenerateWeekValidationError) {
    return error.code;
  }
  if (
    error instanceof Error &&
    (error.message.startsWith("openai_request_failed") ||
      error.message.startsWith("deepseek_request_failed") ||
      error.message.startsWith("ai_provider_request_failed"))
  ) {
    return "openai_request_failed";
  }
  return "invalid_generated_week";
}

export function dayGenerationRetryContext(
  day: DayGenerationState,
  dayIndex: number,
  nextAttempts: number,
): Record<string, unknown> | undefined {
  if (nextAttempts <= 1) {
    return undefined;
  }

  const retryKind = day.status === "running"
    ? "stale_day_repair"
    : "failed_day_repair";
  const retryReason = day.error_code ??
    (day.status === "running" ? "generation_stale" : "previous_day_failed");
  return {
    retry_kind: retryKind,
    retry_reason: retryReason,
    scheduled_date: day.scheduled_date,
    day_index: dayIndex + 1,
    day_attempt: nextAttempts,
    previous_status: day.status,
    previous_started_at: day.started_at ?? null,
    previous_completed_at: day.completed_at ?? null,
    instruction:
      "Retry only this daily card. Keep the target scheduled_date fixed, simplify the concept if the prior run timed out, and return a complete valid daily-card contract.",
  };
}

export function dayGenerationPhase(
  progress: PerDayGenerationSnapshot,
): AIGenerationPhase {
  return progress.kind === "parallel_week_generation_v1"
    ? "parallel_day_generation"
    : "async_day_generation";
}

export async function updateGenerationProgress(
  admin: SupabaseAdminClient,
  generationID: string,
  progress: PerDayGenerationSnapshot | SingleDayGenerationSnapshot,
): Promise<{ ok: true } | { response: Response }> {
  const { error } = await updateGenerationRunProgress(
    admin,
    generationID,
    progress,
  );

  if (error) {
    return generationPersistFailure("update_generation_progress", error);
  }
  return { ok: true };
}

export async function scheduleNextPendingDayGeneration(
  admin: SupabaseAdminClient,
  generationID: string,
  prepared: PerDayRunnerPreparedGeneration,
  progress: PerDayGenerationSnapshot,
  host: PerDayRunnerHost,
): Promise<
  { progress: PerDayGenerationSnapshot } | { response: Response }
> {
  const staleThresholdMS = runningDayStaleMS();
  const nowMS = Date.now();
  const maxAttempts = maxDayGenerationAttempts();
  const nowISO = new Date().toISOString();
  const activeIndex = progress.days.findIndex((day) =>
    day.status === "running" &&
    !isRunningDayStale(day, staleThresholdMS, nowMS)
  );
  if (activeIndex >= 0) {
    return { progress };
  }

  const normalizedProgress = {
    ...progress,
    days: progress.days.map((day) =>
      day.status === "running" &&
        isRunningDayStale(day, staleThresholdMS, nowMS)
        ? staleDayFailure(day, maxAttempts, nowISO)
        : day
    ),
  };
  const dayIndex = normalizedProgress.days.findIndex((day) =>
    shouldRunDayGeneration(day, maxAttempts, staleThresholdMS, nowMS)
  );
  if (dayIndex < 0) {
    return { progress: normalizedProgress };
  }

  const day = normalizedProgress.days[dayIndex];
  const nextAttempts = day.attempts + 1;
  const retryContext = dayGenerationRetryContext(
    day,
    dayIndex,
    nextAttempts,
  );
  const now = new Date().toISOString();
  const runningProgress = {
    ...normalizedProgress,
    days: normalizedProgress.days.map((day, index) =>
      index === dayIndex
        ? {
          ...day,
          status: "running" as const,
          attempts: nextAttempts,
          started_at: now,
          error_code: undefined,
        }
        : day
    ),
    updated_at: now,
  };
  const updateResult = await updateGenerationProgress(
    admin,
    generationID,
    runningProgress,
  );
  if ("response" in updateResult) {
    return updateResult;
  }

  host.scheduleBackgroundTask(
    runSingleDayGenerationStep(
      admin,
      generationID,
      prepared,
      runningProgress,
      dayIndex,
      host,
      retryContext,
    ),
  );

  return { progress: runningProgress };
}

async function runSingleDayGenerationStep(
  admin: SupabaseAdminClient,
  generationID: string,
  prepared: PerDayRunnerPreparedGeneration,
  progress: PerDayGenerationSnapshot,
  dayIndex: number,
  host: PerDayRunnerHost,
  retryContext?: Record<string, unknown>,
): Promise<void> {
  const day = progress.days[dayIndex];
  try {
    const output = await host.generateDayOutput(
      prepared,
      day.scheduled_date,
      dayIndex,
      generationID,
      dayGenerationPhase(progress),
      retryContext,
    );
    const completedAt = new Date().toISOString();
    const completedProgress = {
      ...progress,
      days: progress.days.map((entry, index) =>
        index === dayIndex
          ? {
            ...entry,
            status: "completed" as const,
            completed_at: completedAt,
            output,
          }
          : entry
      ),
      updated_at: completedAt,
    };
    const updateResult = await updateGenerationProgress(
      admin,
      generationID,
      completedProgress,
    );
    if ("response" in updateResult) {
      await host.markGenerationRunFailed(
        admin,
        generationID,
        "generation_persist_failed",
      );
      return;
    }

    if (allDaysCompleted(completedProgress)) {
      const run: GenerationRunStatusRecord = {
        id: generationID,
        workspace_id: prepared.session.workspaceID,
        creator_id: prepared.request.creator_id,
        weekly_setup_id: prepared.request.weekly_setup_id,
        requested_by_member_id: prepared.session.memberID,
      };
      await finalizePerDayGeneration(
        admin,
        generationID,
        run,
        prepared.session,
        prepared.inputSnapshot,
        completedProgress,
        host,
      );
    } else if (allDaysTerminal(completedProgress, maxDayGenerationAttempts())) {
      const run: GenerationRunStatusRecord = {
        id: generationID,
        workspace_id: prepared.session.workspaceID,
        creator_id: prepared.request.creator_id,
        weekly_setup_id: prepared.request.weekly_setup_id,
        requested_by_member_id: prepared.session.memberID,
      };
      await finalizeTerminalPerDayGeneration(
        admin,
        generationID,
        run,
        prepared.session,
        prepared.inputSnapshot,
        completedProgress,
        host,
      );
    }
  } catch (error) {
    const errorCode = stableGenerationError(error);
    const failedAt = new Date().toISOString();
    const failedProgress = {
      ...progress,
      days: progress.days.map((entry, index) =>
        index === dayIndex
          ? {
            ...entry,
            status: "failed" as const,
            error_code: errorCode,
            completed_at: failedAt,
          }
          : entry
      ),
      updated_at: failedAt,
    };
    await updateGenerationProgress(admin, generationID, failedProgress);
    if (allDaysTerminal(failedProgress, maxDayGenerationAttempts())) {
      const run: GenerationRunStatusRecord = {
        id: generationID,
        workspace_id: prepared.session.workspaceID,
        creator_id: prepared.request.creator_id,
        weekly_setup_id: prepared.request.weekly_setup_id,
        requested_by_member_id: prepared.session.memberID,
      };
      await finalizeTerminalPerDayGeneration(
        admin,
        generationID,
        run,
        prepared.session,
        prepared.inputSnapshot,
        failedProgress,
        host,
      );
    }
  }
}

export async function finalizePerDayGeneration(
  admin: SupabaseAdminClient,
  generationID: string,
  run: GenerationRunStatusRecord,
  session: VerifiedDeviceSession,
  inputSnapshot: GenerationInputSnapshot,
  progress: PerDayGenerationSnapshot,
  host: PerDayRunnerHost,
): Promise<{ payload: GenerateWeekDraftResponse } | { response: Response }> {
  const dayOutputs = progress.days.map((day) => day.output);
  if (dayOutputs.some((output) => !output)) {
    await host.markGenerationRunFailed(
      admin,
      generationID,
      "invalid_generated_week",
    );
    return {
      response: jsonResponse({ error: "invalid_generated_week" }, 400),
    };
  }

  const generated = combineGeneratedDayOutputs(
    inputSnapshot,
    dayOutputs as GeneratedDayOutput[],
  );
  const request = requestFromRun(run, inputSnapshot);
  const persistResult = await host.persistGeneratedWeek(
    admin,
    session.workspaceID,
    request,
    stringValue(run.requested_by_member_id) ?? session.memberID,
    inputSnapshot.weekly_setup,
    inputSnapshot,
    generated,
  );
  if ("response" in persistResult) {
    const step = await host.persistenceFailureStep(persistResult.response);
    await host.markGenerationRunFailed(
      admin,
      generationID,
      step ? `generation_persist_failed:${step}` : "generation_persist_failed",
    );
    return persistResult;
  }

  const completedAt = new Date().toISOString();
  const payload = host.makeGenerateWeekDraftResponse(
    generationID,
    persistResult.weeklyPlanID,
    generated,
    persistResult.dailyCards,
    persistResult.ideaBank,
    completedAt,
  );
  const completedRunResult = await host.completeGenerationRun(
    admin,
    generationID,
    persistResult.weeklyPlanID,
    payload,
    completedAt,
  );
  if ("response" in completedRunResult) {
    const step = await host.persistenceFailureStep(completedRunResult.response);
    await host.markGenerationRunFailed(
      admin,
      generationID,
      step ? `generation_persist_failed:${step}` : "generation_persist_failed",
    );
    return completedRunResult;
  }

  return { payload };
}

export async function finalizeTerminalPerDayGeneration(
  admin: SupabaseAdminClient,
  generationID: string,
  run: GenerationRunStatusRecord,
  session: VerifiedDeviceSession,
  inputSnapshot: GenerationInputSnapshot,
  progress: PerDayGenerationSnapshot,
  host: PerDayRunnerHost,
): Promise<{ payload: Record<string, unknown> } | { response: Response }> {
  if (allDaysCompleted(progress)) {
    return await finalizePerDayGeneration(
      admin,
      generationID,
      run,
      session,
      inputSnapshot,
      progress,
      host,
    );
  }

  const completedAt = new Date().toISOString();
  const completedOutputs = progress.days.flatMap((day) =>
    day.status === "completed" && day.output ? [day.output] : []
  );
  const baseProgress = { ...progress, updated_at: completedAt };

  if (completedOutputs.length === 0) {
    await updateGenerationProgress(admin, generationID, baseProgress);
    await host.markGenerationRunFailed(
      admin,
      generationID,
      "invalid_generated_week",
    );
    const summary = weekGenerationStatusSummary(
      baseProgress,
      "failed",
      (day) => isTerminalDayGenerationState(day, maxDayGenerationAttempts()),
    );
    return {
      payload: {
        generation_id: generationID,
        status: "failed",
        error: "invalid_generated_week",
        ...summary,
        poll_after_seconds: null,
      },
    };
  }

  const generated = makeGeneratedWeekOutputFromCompletedDays(
    completedOutputs,
    baseProgress,
    host.makeInitialWeekStrategyOutput(inputSnapshot),
  );
  const request = requestFromRun(run, inputSnapshot);
  const persistResult = await host.persistGeneratedWeek(
    admin,
    session.workspaceID,
    request,
    stringValue(run.requested_by_member_id) ?? session.memberID,
    inputSnapshot.weekly_setup,
    inputSnapshot,
    generated,
  );
  if ("response" in persistResult) {
    const step = await host.persistenceFailureStep(persistResult.response);
    await host.markGenerationRunFailed(
      admin,
      generationID,
      step ? `generation_persist_failed:${step}` : "generation_persist_failed",
    );
    return persistResult;
  }

  const savedCardsByDate = new Map(
    persistResult.dailyCards.map((card) => [card.scheduled_date, card]),
  );
  const finalProgress: PerDayGenerationSnapshot = {
    ...baseProgress,
    weekly_plan_id: persistResult.weeklyPlanID,
    days: baseProgress.days.map((day) => {
      if (day.status !== "completed" || !day.output) {
        return day;
      }
      const saved = savedCardsByDate.get(day.scheduled_date);
      return saved
        ? {
          ...day,
          daily_card_id: saved.id,
          completed_at: day.completed_at ?? completedAt,
        }
        : day;
    }),
  };
  const summary = weekGenerationStatusSummary(
    finalProgress,
    "completed",
    (day) => isTerminalDayGenerationState(day, maxDayGenerationAttempts()),
  );
  const payload = {
    generation_id: generationID,
    weekly_plan_id: persistResult.weeklyPlanID,
    status: "partial",
    strategy_summary: generated.strategy_summary,
    warnings: uniqueNonBlankStrings([
      ...generated.warnings,
      "Some days were saved and some days failed. Retry failed days before publishing.",
    ]),
    assumptions: generated.assumptions,
    daily_cards: persistResult.dailyCards,
    idea_bank: persistResult.ideaBank,
    source_summary: generated.source_summary,
    generated_at: completedAt,
    ...summary,
    failed_days: summary.day_statuses.filter((day) => day.status === "failed"),
    poll_after_seconds: null,
  };
  const completedResult = await completePartialGenerationRun(
    admin,
    generationID,
    persistResult.weeklyPlanID,
    finalProgress,
    completedAt,
  );
  if ("response" in completedResult) {
    return completedResult;
  }

  return { payload };
}
