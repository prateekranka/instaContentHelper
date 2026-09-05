import { jsonResponse, SupabaseAdminClient } from "../_shared/device-auth.ts";
import type { VerifiedDeviceSession } from "../_shared/device-auth.ts";
import {
  generateStoryboardThumbnailsForCard,
  StorageCapableAdminClient,
  StoryboardThumbnailGenerationError,
} from "../_shared/storyboard-thumbnail-generation.ts";
import {
  buildAllowedDayContentPillars,
  GeneratedDailyCard,
  GeneratedDayOutput,
  GenerationInputSnapshot,
  RegenerateDayRequest,
  validateGeneratedDayOutput,
  weekDates,
} from "./generation.ts";
import type { AIProviderConfig } from "./generation.ts";
import type {
  DayVisualsStatus,
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
  phase:
    | "generation_started"
    | "generation_completed"
    | "generation_failed"
    | "storyboard_visuals_started"
    | "storyboard_visuals_completed"
    | "storyboard_visuals_failed";
  status: "running" | "completed" | "failed" | "pending";
  generation_id: string;
  weekly_plan_id: string;
  week_start_date: string;
  scheduled_date: string;
  day_index: number | null;
  duration_ms: number | null;
  stage_timings_ms: SingleDayGenerationStageTimings;
  visuals_status?: DayVisualsStatus;
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
  /** Optional: patch completed snapshot after async visuals land. */
  patchCompletedDayGenerationSnapshot?: (
    admin: SupabaseAdminClient,
    generationID: string,
    payload: RegenerateDayDraftResponse,
  ) => Promise<{ ok: true } | { error: unknown }>;
  markGenerationRunFailed: (
    admin: SupabaseAdminClient,
    generationID: string,
    errorCode: string,
    detail?: {
      error_message?: string | null;
      validation_error?: Record<string, unknown> | null;
      output_snapshot_patch?: Record<string, unknown>;
    },
  ) => Promise<void>;
  stableGenerationError: (error: unknown) => string;
  /** Optional: extract structured validation failure for persistence. */
  validationFailureDetail?: (
    error: unknown,
  ) => Record<string, unknown> | null;
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
   * thumbnails asynchronously after script-ready completion (soft-fails).
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

/** Script-ready critical path stages (excludes async storyboard visuals). */
const SINGLE_DAY_SCRIPT_READY_STAGES = [
  "text_generation",
  "validation",
  "persistence",
  "finalization",
] as const;

type SingleDayTimedStage =
  | typeof SINGLE_DAY_SCRIPT_READY_STAGES[number]
  | "storyboard_visuals";

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
  /** Wall-clock to script-ready; excludes async storyboard_visuals. */
  snapshotScriptReady: () => SingleDayGenerationStageTimings;
  /** Full snapshot including measured storyboard_visuals when present. */
  snapshotWithVisuals: () => SingleDayGenerationStageTimings;
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
    snapshotScriptReady: () => {
      const measuredTotalMS = nonNegativeDurationMS(
        pipelineStartedAtMS,
        nowMS(),
      );
      const measuredStageTotalMS = SINGLE_DAY_SCRIPT_READY_STAGES.reduce(
        (total, stage) => total + (timings[stage] ?? 0),
        0,
      );
      return {
        ...timings,
        // Script-ready total never includes async visuals duration.
        storyboard_visuals: null,
        total: Math.max(measuredTotalMS, measuredStageTotalMS),
      };
    },
    snapshotWithVisuals: () => {
      const measuredTotalMS = nonNegativeDurationMS(
        pipelineStartedAtMS,
        nowMS(),
      );
      const measuredStageTotalMS = ([
        ...SINGLE_DAY_SCRIPT_READY_STAGES,
        "storyboard_visuals",
      ] as const).reduce(
        (total, stage) => total + (timings[stage] ?? 0),
        0,
      );
      return {
        ...timings,
        total: Math.max(measuredTotalMS, measuredStageTotalMS),
      };
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
        {
          allowedContentPillars: buildAllowedDayContentPillars(
            prepared.inputSnapshot.creator_profile,
          ),
        },
      );
    } finally {
      stageTimings.finish("validation");
    }
  } catch (error) {
    stageTimings.finish("text_generation");
    stageTimings.finish("validation");
    const errorCode = host.stableGenerationError(error);
    const validationError = host.validationFailureDetail?.(error) ?? null;
    const timingSnapshot = stageTimings.snapshotScriptReady();
    const failureSnapshot: SingleDayGenerationSnapshot = {
      ...runningProgress,
      status: "failed",
      updated_at: new Date().toISOString(),
      error_code: errorCode,
      error_message: error instanceof Error
        ? error.message.slice(0, 240)
        : null,
      validation_error: validationError,
      stage_timings_ms: timingSnapshot,
    };
    await host.markGenerationRunFailed(admin, generationID, errorCode, {
      error_message: failureSnapshot.error_message,
      validation_error: validationError,
      output_snapshot_patch: failureSnapshot as unknown as Record<
        string,
        unknown
      >,
    });
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
        {
          error: errorCode,
          error_message: failureSnapshot.error_message,
          validation_error: validationError,
        },
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
    const timingSnapshot = stageTimings.snapshotScriptReady();
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

  // Script-ready: mark the day complete before Gemini visuals.
  // Thumbs attach asynchronously with the same quality/prompt path.
  const visualsStatusAtReady: DayVisualsStatus = prepared.mockEnabled
    ? "skipped"
    : "pending";
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
    visuals_status: visualsStatusAtReady,
    // Pre-finalization snapshot; finalization itself is the completion write.
    stage_timings_ms: stageTimings.snapshotScriptReady(),
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
  const scriptReadyTimings = stageTimings.snapshotScriptReady();
  payload.stage_timings_ms = scriptReadyTimings;
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
      duration_ms: scriptReadyTimings.total,
      stage_timings_ms: scriptReadyTimings,
      visuals_status: visualsStatusAtReady,
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
    duration_ms: scriptReadyTimings.total,
    stage_timings_ms: scriptReadyTimings,
    visuals_status: visualsStatusAtReady,
    ...guidance,
  });

  if (visualsStatusAtReady === "pending") {
    scheduleAsyncDayStoryboardVisuals({
      admin,
      generationID,
      prepared,
      host,
      dayIndex,
      guidance,
      scriptReadyPayload: payload,
      scriptReadyTimings,
      stageTimings,
    });
  }

  return { payload };
}

function scheduleAsyncDayStoryboardVisuals(args: {
  admin: SupabaseAdminClient;
  generationID: string;
  prepared: SingleDayRunnerPreparedGeneration;
  host: SingleDayRunnerHost;
  dayIndex: number;
  guidance: Pick<
    SingleDayGenerationLifecycleEvent,
    "day_guidance_present" | "day_guidance_chars"
  >;
  scriptReadyPayload: RegenerateDayDraftResponse;
  scriptReadyTimings: SingleDayGenerationStageTimings;
  stageTimings: ReturnType<typeof singleDayStageTimingTracker>;
}): void {
  const {
    admin,
    generationID,
    prepared,
    host,
    dayIndex,
    guidance,
    scriptReadyPayload,
    scriptReadyTimings,
    stageTimings,
  } = args;
  const attachStoryboard = host.attachDayStoryboardThumbnails ??
    defaultAttachDayStoryboardThumbnails;

  host.scheduleBackgroundTask((async () => {
    host.emitLifecycleEvent({
      phase: "storyboard_visuals_started",
      status: "pending",
      generation_id: generationID,
      weekly_plan_id: prepared.request.weekly_plan_id,
      week_start_date: prepared.inputSnapshot.week_start_date,
      scheduled_date: prepared.request.scheduled_date,
      day_index: dayIndex,
      duration_ms: null,
      stage_timings_ms: {
        ...scriptReadyTimings,
        storyboard_visuals: null,
      },
      visuals_status: "pending",
      ...guidance,
    });

    stageTimings.start("storyboard_visuals");
    let visualsStatus: DayVisualsStatus = "failed";
    let dailyCardWithStoryboard = scriptReadyPayload.daily_card;
    try {
      dailyCardWithStoryboard = await attachStoryboard(
        admin,
        prepared,
        scriptReadyPayload.daily_card,
      );
      const assets = dailyCardWithStoryboard.storyboard_thumbnail_assets;
      const hasGeneratedAsset = Array.isArray(assets) &&
        assets.some((asset) =>
          isRecord(asset) && asset.status === "generated"
        );
      visualsStatus = hasGeneratedAsset ? "ready" : "skipped";
    } catch (error) {
      console.error(JSON.stringify({
        event: "day_storyboard_async_attach_failed",
        generation_id: generationID,
        scheduled_date: prepared.request.scheduled_date,
        detail: error instanceof Error ? error.message : String(error),
      }));
      visualsStatus = "failed";
      dailyCardWithStoryboard = scriptReadyPayload.daily_card;
    } finally {
      stageTimings.finish("storyboard_visuals");
    }

    const visualsTimings = stageTimings.snapshotWithVisuals();
    // Keep script-ready total in the completed payload; expose visuals
    // duration only on storyboard_visuals for secondary latency metrics.
    const patchedPayload: RegenerateDayDraftResponse = {
      ...scriptReadyPayload,
      daily_card: dailyCardWithStoryboard,
      visuals_status: visualsStatus,
      stage_timings_ms: {
        ...scriptReadyTimings,
        storyboard_visuals: visualsTimings.storyboard_visuals,
        total: scriptReadyTimings.total,
      },
    };

    if (host.patchCompletedDayGenerationSnapshot) {
      const patchResult = await host.patchCompletedDayGenerationSnapshot(
        admin,
        generationID,
        patchedPayload,
      );
      if ("error" in patchResult) {
        console.warn(JSON.stringify({
          event: "day_storyboard_snapshot_patch_failed",
          generation_id: generationID,
          scheduled_date: prepared.request.scheduled_date,
          detail: String(patchResult.error),
        }));
      }
    }

    host.emitLifecycleEvent({
      phase: visualsStatus === "failed"
        ? "storyboard_visuals_failed"
        : "storyboard_visuals_completed",
      status: visualsStatus === "failed" ? "failed" : "completed",
      generation_id: generationID,
      weekly_plan_id: prepared.request.weekly_plan_id,
      week_start_date: prepared.inputSnapshot.week_start_date,
      scheduled_date: prepared.request.scheduled_date,
      day_index: dayIndex,
      duration_ms: visualsTimings.storyboard_visuals,
      stage_timings_ms: patchedPayload.stage_timings_ms ??
        emptySingleDayStageTimings(),
      visuals_status: visualsStatus,
      ...guidance,
    });
  })());
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
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
      mode: "async_after_script_ready",
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
