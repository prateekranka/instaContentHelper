import { jsonResponse, SupabaseAdminClient } from "../_shared/device-auth.ts";
import type { VerifiedDeviceSession } from "../_shared/device-auth.ts";
import {
  generateStoryboardThumbnailsForCard,
  StorageCapableAdminClient,
  StoryboardThumbnailGenerationError,
} from "../_shared/storyboard-thumbnail-generation.ts";
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
import { generatedDailyCardValues } from "./generation-persistence.ts";

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
  stage_timings_ms: SingleDayGenerationStageTimings;
  day_guidance_present: boolean;
  day_guidance_chars: number;
};

export type SingleDayGenerationStageTimings = {
  text_generation: number | null;
  validation: number | null;
  persistence: number | null;
  storyboard_visuals: number | null;
  finalization: number | null;
  total: number | null;
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
  /** Optional monotonic clock override for deterministic timing tests. */
  nowMS?: () => number;
  dayHeartbeatIntervalMS?: number;
  /**
   * Optional override for tests. Default attaches Gemini storyboard
   * thumbnails as part of day generation (soft-fails if unavailable).
   */
  attachDayStoryboardThumbnails?: (
    admin: SupabaseAdminClient,
    prepared: SingleDayRunnerPreparedGeneration,
    dailyCard: GeneratedDailyCard,
  ) => Promise<GeneratedDailyCard>;
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

const SINGLE_DAY_TIMED_STAGES = [
  "text_generation",
  "validation",
  "persistence",
  "storyboard_visuals",
  "finalization",
] as const;

type SingleDayTimedStage = typeof SINGLE_DAY_TIMED_STAGES[number];

function emptySingleDayStageTimings(): SingleDayGenerationStageTimings {
  return {
    text_generation: null,
    validation: null,
    persistence: null,
    storyboard_visuals: null,
    finalization: null,
    total: null,
  };
}

function nonNegativeDurationMS(startMS: number, endMS: number): number {
  if (!Number.isFinite(startMS) || !Number.isFinite(endMS)) return 0;
  return Math.max(0, Math.floor(endMS - startMS));
}

function singleDayStageTimingTracker(host: SingleDayRunnerHost): {
  start: (stage: SingleDayTimedStage) => void;
  finish: (stage: SingleDayTimedStage) => void;
  snapshot: () => SingleDayGenerationStageTimings;
} {
  const nowMS = host.nowMS ?? (() => performance.now());
  const pipelineStartedAtMS = nowMS();
  const stageStartedAtMS = new Map<SingleDayTimedStage, number>();
  const timings = emptySingleDayStageTimings();

  return {
    start: (stage) => {
      stageStartedAtMS.set(stage, nowMS());
    },
    finish: (stage) => {
      const startedAtMS = stageStartedAtMS.get(stage);
      if (startedAtMS === undefined) return;
      timings[stage] = nonNegativeDurationMS(startedAtMS, nowMS());
      stageStartedAtMS.delete(stage);
    },
    snapshot: () => {
      const measuredTotalMS = nonNegativeDurationMS(
        pipelineStartedAtMS,
        nowMS(),
      );
      const measuredStageTotalMS = SINGLE_DAY_TIMED_STAGES.reduce(
        (total, stage) => total + (timings[stage] ?? 0),
        0,
      );
      timings.total = Math.max(measuredTotalMS, measuredStageTotalMS);
      return { ...timings };
    },
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
      stage_timings_ms: emptySingleDayStageTimings(),
      ...guidance,
    });
    return {
      response: jsonResponse({ error: "date_not_in_plan" }, 400),
    };
  }

  const pipelineStartedAtISO = new Date().toISOString();
  const stageTimings = singleDayStageTimingTracker(host);
  host.emitLifecycleEvent({
    phase: "generation_started",
    status: "running",
    generation_id: generationID,
    weekly_plan_id: prepared.request.weekly_plan_id,
    week_start_date: prepared.inputSnapshot.week_start_date,
    scheduled_date: prepared.request.scheduled_date,
    day_index: dayIndex,
    duration_ms: null,
    stage_timings_ms: emptySingleDayStageTimings(),
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
  stageTimings.start("text_generation");
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
    stageTimings.finish("text_generation");
    stageTimings.start("validation");
    try {
      generated = validateGeneratedDayOutput(
        rawOutput,
        prepared.request.scheduled_date,
        dayIndex,
      );
    } finally {
      stageTimings.finish("validation");
    }
  } catch (error) {
    stageTimings.finish("text_generation");
    stageTimings.finish("validation");
    const errorCode = host.stableGenerationError(error);
    await host.markGenerationRunFailed(admin, generationID, errorCode);
    const timingSnapshot = stageTimings.snapshot();
    host.emitLifecycleEvent({
      phase: "generation_failed",
      status: "failed",
      generation_id: generationID,
      weekly_plan_id: prepared.request.weekly_plan_id,
      week_start_date: prepared.inputSnapshot.week_start_date,
      scheduled_date: prepared.request.scheduled_date,
      day_index: dayIndex,
      duration_ms: timingSnapshot.total,
      stage_timings_ms: timingSnapshot,
      ...guidance,
    });
    return {
      response: jsonResponse(
        { error: errorCode },
        errorCode === "openai_request_failed" ? 502 : 400,
      ),
    };
  }

  stageTimings.start("persistence");
  let persistResult: Awaited<
    ReturnType<SingleDayRunnerHost["persistRegeneratedDay"]>
  >;
  try {
    persistResult = await host.persistRegeneratedDay(
      admin,
      prepared,
      generated.daily_card,
    );
  } finally {
    stageTimings.finish("persistence");
  }
  if ("response" in persistResult) {
    await host.markGenerationRunFailed(
      admin,
      generationID,
      "generation_persist_failed",
    );
    const timingSnapshot = stageTimings.snapshot();
    host.emitLifecycleEvent({
      phase: "generation_failed",
      status: "failed",
      generation_id: generationID,
      weekly_plan_id: prepared.request.weekly_plan_id,
      week_start_date: prepared.inputSnapshot.week_start_date,
      scheduled_date: prepared.request.scheduled_date,
      day_index: dayIndex,
      duration_ms: timingSnapshot.total,
      stage_timings_ms: timingSnapshot,
      ...guidance,
    });
    return persistResult;
  }

  const attachStoryboard = host.attachDayStoryboardThumbnails ??
    defaultAttachDayStoryboardThumbnails;
  stageTimings.start("storyboard_visuals");
  let dailyCardWithStoryboard: GeneratedDailyCard;
  try {
    dailyCardWithStoryboard = await withSingleDayGenerationHeartbeat(
      admin,
      generationID,
      {
        ...runningProgress,
        status: "running",
        updated_at: new Date().toISOString(),
      },
      host,
      () => attachStoryboard(admin, prepared, persistResult.dailyCard),
    );
  } finally {
    stageTimings.finish("storyboard_visuals");
  }

  const completedAt = new Date().toISOString();
  const payload: RegenerateDayDraftResponse = {
    generation_id: generationID,
    weekly_plan_id: prepared.request.weekly_plan_id,
    status: "draft",
    target_scheduled_date: prepared.request.scheduled_date,
    daily_card: dailyCardWithStoryboard,
    warnings: generated.warnings,
    assumptions: generated.assumptions,
    source_summary: generated.source_summary,
    generated_at: completedAt,
  };
  stageTimings.start("finalization");
  let completedResult: Awaited<
    ReturnType<SingleDayRunnerHost["completeDayGenerationRun"]>
  >;
  try {
    completedResult = await host.completeDayGenerationRun(
      admin,
      generationID,
      payload,
      completedAt,
    );
  } finally {
    stageTimings.finish("finalization");
  }
  if ("response" in completedResult) {
    await host.markGenerationRunFailed(
      admin,
      generationID,
      "generation_persist_failed",
    );
    const timingSnapshot = stageTimings.snapshot();
    host.emitLifecycleEvent({
      phase: "generation_failed",
      status: "failed",
      generation_id: generationID,
      weekly_plan_id: prepared.request.weekly_plan_id,
      week_start_date: prepared.inputSnapshot.week_start_date,
      scheduled_date: prepared.request.scheduled_date,
      day_index: dayIndex,
      duration_ms: timingSnapshot.total,
      stage_timings_ms: timingSnapshot,
      ...guidance,
    });
    return completedResult;
  }
  const timingSnapshot = stageTimings.snapshot();
  host.emitLifecycleEvent({
    phase: "generation_completed",
    status: "completed",
    generation_id: generationID,
    weekly_plan_id: prepared.request.weekly_plan_id,
    week_start_date: prepared.inputSnapshot.week_start_date,
    scheduled_date: prepared.request.scheduled_date,
    day_index: dayIndex,
    duration_ms: timingSnapshot.total,
    stage_timings_ms: timingSnapshot,
    ...guidance,
  });
  return { payload };
}

export async function defaultAttachDayStoryboardThumbnails(
  admin: SupabaseAdminClient,
  prepared: SingleDayRunnerPreparedGeneration,
  dailyCard: GeneratedDailyCard,
): Promise<GeneratedDailyCard> {
  if (prepared.mockEnabled) {
    return dailyCard;
  }

  const dailyCardID = typeof dailyCard.id === "string" && dailyCard.id.trim()
    ? dailyCard.id.trim()
    : null;
  if (!dailyCardID) {
    console.warn(JSON.stringify({
      event: "day_storyboard_skipped",
      reason: "missing_daily_card_id",
      scheduled_date: prepared.request.scheduled_date,
    }));
    return dailyCard;
  }

  const cardRecord: Record<string, unknown> = {
    ...generatedDailyCardValues(dailyCard),
    id: dailyCardID,
    hook: dailyCard.hook,
    shot_timeline: dailyCard.shot_timeline,
    voiceover_timeline: dailyCard.voiceover_timeline,
    on_screen_text_timeline: dailyCard.on_screen_text_timeline,
    storyboard_thumbnail_assets: dailyCard.storyboard_thumbnail_assets ?? [],
  };

  try {
    const result = await generateStoryboardThumbnailsForCard({
      admin: admin as StorageCapableAdminClient,
      workspaceID: prepared.session.workspaceID,
      creatorID: prepared.request.creator_id,
      dailyCardID,
      cardRecord,
      persist: true,
    });

    if (result.skippedReason) {
      console.warn(JSON.stringify({
        event: "day_storyboard_skipped",
        reason: result.skippedReason,
        daily_card_id: dailyCardID,
        scheduled_date: prepared.request.scheduled_date,
      }));
      return dailyCard;
    }

    console.log(JSON.stringify({
      event: "day_storyboard_attached",
      daily_card_id: dailyCardID,
      scheduled_date: prepared.request.scheduled_date,
      generated_count: result.generatedCount,
      cached_count: result.cachedCount,
      model: result.model,
    }));

    return {
      ...dailyCard,
      storyboard_thumbnail_assets: result.assets as Array<
        Record<string, unknown>
      >,
    };
  } catch (error) {
    const code = error instanceof StoryboardThumbnailGenerationError
      ? error.code
      : "storyboard_thumbnail_gemini_failed";
    // Soft-fail: day copy/storyboard text still ships; manager can retry visuals.
    console.error(JSON.stringify({
      event: "day_storyboard_attach_failed",
      daily_card_id: dailyCardID,
      scheduled_date: prepared.request.scheduled_date,
      error: code,
      detail: error instanceof Error ? error.message : String(error),
    }));
    return dailyCard;
  }
}
