import { jsonResponse, SupabaseAdminClient } from "../_shared/device-auth.ts";
import type { VerifiedDeviceSession } from "../_shared/device-auth.ts";
import {
  GeneratedDailyCard,
  GeneratedDayOutput,
  GenerationInputSnapshot,
  RegenerateDayRequest,
  validateGeneratedDayOutput,
  weekDates,
} from "./generation.ts";
import type { AIProviderConfig } from "./generation.ts";
import type {
  RegenerateDayDraftResponse,
  SingleDayGenerationSnapshot,
} from "./generation-run-snapshot.ts";
import { runningDayStaleMS } from "./generation-parallel-week-worker.ts";

export type SingleDayRunnerPreparedGeneration = {
  request: RegenerateDayRequest;
  session: VerifiedDeviceSession;
  plan: {
    id: string;
    week_start_date?: string;
    weekly_setup_id?: string | null;
    status?: string;
    is_soft_locked?: boolean;
  };
  targetCard?: {
    id: string;
    scheduled_date: string;
  } & Record<string, unknown>;
  inputSnapshot: GenerationInputSnapshot;
  providers: AIProviderConfig[];
  model: string;
  mockEnabled: boolean;
};

export type SingleDayGenerationLifecycleEvent = {
  phase: "generation_started" | "generation_completed" | "generation_failed";
  status: "running" | "completed" | "failed";
  generation_id: string;
  weekly_plan_id: string;
  week_start_date: string;
  scheduled_date: string;
  day_index: number | null;
  duration_ms: number | null;
  day_guidance_present: boolean;
  day_guidance_chars: number;
};

export type SingleDayRunnerHost = {
  generateOutput: (
    prepared: SingleDayRunnerPreparedGeneration,
    generationID: string,
    dayIndex: number,
  ) => Promise<GeneratedDayOutput>;
  mockOutput: (
    inputSnapshot: GenerationInputSnapshot,
    dayIndex: number,
  ) => GeneratedDayOutput;
  persistRegeneratedDay: (
    admin: SupabaseAdminClient,
    prepared: SingleDayRunnerPreparedGeneration,
    generatedCard: GeneratedDailyCard,
  ) => Promise<{ dailyCard: GeneratedDailyCard } | { response: Response }>;
  completeDayGenerationRun: (
    admin: SupabaseAdminClient,
    generationID: string,
    payload: RegenerateDayDraftResponse,
    completedAt: string,
  ) => Promise<{ ok: true } | { response: Response }>;
  markGenerationRunFailed: (
    admin: SupabaseAdminClient,
    generationID: string,
    errorCode: string,
  ) => Promise<void>;
  stableGenerationError: (error: unknown) => string;
  updateGenerationProgress: (
    admin: SupabaseAdminClient,
    generationID: string,
    progress: SingleDayGenerationSnapshot,
  ) => Promise<{ ok: true } | { response: Response }>;
  scheduleBackgroundTask: (promise: Promise<unknown>) => void;
  emitLifecycleEvent: (event: SingleDayGenerationLifecycleEvent) => void;
  dayHeartbeatIntervalMS?: number;
};

const DAY_GENERATION_HEARTBEAT_MIN_MS = 10;
const DAY_GENERATION_HEARTBEAT_MAX_MS = 60_000;

function singleDayHeartbeatIntervalMS(host: SingleDayRunnerHost): number {
  const configured = host.dayHeartbeatIntervalMS;
  if (
    typeof configured === "number" && Number.isFinite(configured) &&
    configured > 0
  ) {
    return Math.max(Math.trunc(configured), DAY_GENERATION_HEARTBEAT_MIN_MS);
  }
  return Math.max(
    DAY_GENERATION_HEARTBEAT_MIN_MS,
    Math.min(
      Math.floor(runningDayStaleMS() / 4),
      DAY_GENERATION_HEARTBEAT_MAX_MS,
    ),
  );
}

async function withSingleDayGenerationHeartbeat<T>(
  admin: SupabaseAdminClient,
  generationID: string,
  progress: SingleDayGenerationSnapshot,
  host: SingleDayRunnerHost,
  operation: () => Promise<T>,
): Promise<T> {
  let latestProgress = progress;
  const heartbeatID = setInterval(() => {
    const now = new Date().toISOString();
    latestProgress = {
      ...latestProgress,
      heartbeat_at: now,
      updated_at: now,
    };
    host.updateGenerationProgress(admin, generationID, latestProgress).catch(
      () => undefined,
    );
  }, singleDayHeartbeatIntervalMS(host));
  try {
    return await operation();
  } finally {
    clearInterval(heartbeatID);
  }
}

function guidanceMetadata(
  prepared: SingleDayRunnerPreparedGeneration,
): Pick<
  SingleDayGenerationLifecycleEvent,
  "day_guidance_present" | "day_guidance_chars"
> {
  return {
    day_guidance_present: prepared.request.day_guidance !== undefined,
    day_guidance_chars: prepared.request.day_guidance?.length ?? 0,
  };
}

export async function scheduleSingleDayGeneration(
  admin: SupabaseAdminClient,
  generationID: string,
  prepared: SingleDayRunnerPreparedGeneration,
  progress: SingleDayGenerationSnapshot,
  host: SingleDayRunnerHost,
): Promise<{ ok: true } | { response: Response }> {
  const now = new Date().toISOString();
  const runningProgress: SingleDayGenerationSnapshot = {
    ...progress,
    status: "running",
    started_at: now,
    updated_at: now,
  };
  const updateResult = await host.updateGenerationProgress(
    admin,
    generationID,
    runningProgress,
  );
  if ("response" in updateResult) {
    return updateResult;
  }
  host.scheduleBackgroundTask(
    runDayGenerationPipeline(admin, generationID, prepared, host),
  );
  return { ok: true };
}

export async function runDayGenerationPipeline(
  admin: SupabaseAdminClient,
  generationID: string,
  prepared: SingleDayRunnerPreparedGeneration,
  host: SingleDayRunnerHost,
): Promise<
  { payload: RegenerateDayDraftResponse } | { response: Response }
> {
  const guidance = guidanceMetadata(prepared);
  const dayIndex = weekDates(prepared.inputSnapshot.week_start_date).indexOf(
    prepared.request.scheduled_date,
  );
  if (dayIndex < 0) {
    await host.markGenerationRunFailed(admin, generationID, "date_not_in_plan");
    host.emitLifecycleEvent({
      phase: "generation_failed",
      status: "failed",
      generation_id: generationID,
      weekly_plan_id: prepared.request.weekly_plan_id,
      week_start_date: prepared.inputSnapshot.week_start_date,
      scheduled_date: prepared.request.scheduled_date,
      day_index: null,
      duration_ms: null,
      ...guidance,
    });
    return {
      response: jsonResponse({ error: "date_not_in_plan" }, 400),
    };
  }

  const pipelineStartedAtISO = new Date().toISOString();
  const pipelineStartedAt = Date.parse(pipelineStartedAtISO);
  host.emitLifecycleEvent({
    phase: "generation_started",
    status: "running",
    generation_id: generationID,
    weekly_plan_id: prepared.request.weekly_plan_id,
    week_start_date: prepared.inputSnapshot.week_start_date,
    scheduled_date: prepared.request.scheduled_date,
    day_index: dayIndex,
    duration_ms: null,
    ...guidance,
  });

  const runningProgress: SingleDayGenerationSnapshot = {
    kind: "single_day_generation_v1",
    scheduled_date: prepared.request.scheduled_date,
    preserve_manual_edits: prepared.request.preserve_manual_edits,
    status: "running",
    started_at: pipelineStartedAtISO,
    updated_at: pipelineStartedAtISO,
  };

  let generated: GeneratedDayOutput;
  try {
    const rawOutput = await withSingleDayGenerationHeartbeat(
      admin,
      generationID,
      runningProgress,
      host,
      async () =>
        prepared.mockEnabled
          ? host.mockOutput(prepared.inputSnapshot, dayIndex)
          : await host.generateOutput(prepared, generationID, dayIndex),
    );
    generated = validateGeneratedDayOutput(
      rawOutput,
      prepared.request.scheduled_date,
      dayIndex,
    );
  } catch (error) {
    const errorCode = host.stableGenerationError(error);
    await host.markGenerationRunFailed(admin, generationID, errorCode);
    host.emitLifecycleEvent({
      phase: "generation_failed",
      status: "failed",
      generation_id: generationID,
      weekly_plan_id: prepared.request.weekly_plan_id,
      week_start_date: prepared.inputSnapshot.week_start_date,
      scheduled_date: prepared.request.scheduled_date,
      day_index: dayIndex,
      duration_ms: Date.now() - pipelineStartedAt,
      ...guidance,
    });
    return {
      response: jsonResponse(
        { error: errorCode },
        errorCode === "openai_request_failed" ? 502 : 400,
      ),
    };
  }

  const persistResult = await host.persistRegeneratedDay(
    admin,
    prepared,
    generated.daily_card,
  );
  if ("response" in persistResult) {
    await host.markGenerationRunFailed(
      admin,
      generationID,
      "generation_persist_failed",
    );
    host.emitLifecycleEvent({
      phase: "generation_failed",
      status: "failed",
      generation_id: generationID,
      weekly_plan_id: prepared.request.weekly_plan_id,
      week_start_date: prepared.inputSnapshot.week_start_date,
      scheduled_date: prepared.request.scheduled_date,
      day_index: dayIndex,
      duration_ms: Date.now() - pipelineStartedAt,
      ...guidance,
    });
    return persistResult;
  }

  const completedAt = new Date().toISOString();
  const payload: RegenerateDayDraftResponse = {
    generation_id: generationID,
    weekly_plan_id: prepared.request.weekly_plan_id,
    status: "draft",
    target_scheduled_date: prepared.request.scheduled_date,
    daily_card: persistResult.dailyCard,
    warnings: generated.warnings,
    assumptions: generated.assumptions,
    source_summary: generated.source_summary,
    generated_at: completedAt,
  };
  const completedResult = await host.completeDayGenerationRun(
    admin,
    generationID,
    payload,
    completedAt,
  );
  if ("response" in completedResult) {
    await host.markGenerationRunFailed(
      admin,
      generationID,
      "generation_persist_failed",
    );
    host.emitLifecycleEvent({
      phase: "generation_failed",
      status: "failed",
      generation_id: generationID,
      weekly_plan_id: prepared.request.weekly_plan_id,
      week_start_date: prepared.inputSnapshot.week_start_date,
      scheduled_date: prepared.request.scheduled_date,
      day_index: dayIndex,
      duration_ms: Date.now() - pipelineStartedAt,
      ...guidance,
    });
    return completedResult;
  }
  host.emitLifecycleEvent({
    phase: "generation_completed",
    status: "completed",
    generation_id: generationID,
    weekly_plan_id: prepared.request.weekly_plan_id,
    week_start_date: prepared.inputSnapshot.week_start_date,
    scheduled_date: prepared.request.scheduled_date,
    day_index: dayIndex,
    duration_ms: Date.now() - pipelineStartedAt,
    ...guidance,
  });
  return { payload };
}
