import { jsonResponse, SupabaseAdminClient } from "../_shared/device-auth.ts";
import type { VerifiedDeviceSession } from "../_shared/device-auth.ts";
import {
  GeneratedDailyCard,
  GeneratedDayOutput,
  GeneratedWeekOutput,
  GenerateWeekRequest,
  GenerateWeekValidationError,
  validateGeneratedDayOutput,
  weekDates,
} from "./generation.ts";
import { isRecord, isUUID } from "./generation-validation.ts";
import {
  completedDraftStatusSummary,
  weekGenerationStatusSummary,
} from "./generation-status.ts";
import type {
  DayGenerationState,
  PerDayGenerationSnapshot,
  QueuedDayJobRecord,
  QueuedDayJobStatus,
} from "./generation-status.ts";
import type { GenerateWeekDraftResponse } from "./generation-run-snapshot.ts";
import {
  claimQueuedDayJob,
  completeDayJob,
  failDayJob,
  heartbeatDayJob,
  isQueuedDayJobStale,
  readQueuedDayJobsForRun,
  reclaimStaleDayJob,
  releaseOverCapacityDayJob,
  stageDayJobOutput,
  upsertDayJobRows,
} from "./generation-day-job-store.ts";
import {
  generationPersistFailure,
  insertGeneratedIdeas,
  upsertGeneratedDailyCards,
} from "./generation-persistence.ts";
import {
  completePartialGenerationRun as completePartialGenerationRunStore,
  markGenerationRunFailed as markGenerationRunFailedStore,
  readGenerationRunCancellationState,
  updateGenerationRunProgress,
} from "./generation-run-store.ts";
import {
  availableParallelDayJobSlots as availableParallelDayJobSlotsFor,
  hasActiveParallelDayGeneration,
  isRunningDayStale,
  isTerminalDayGenerationState,
  liveParallelDayJobCount,
  mergeSavedDailyCardsIntoProgress,
  normalizeStaleRunningDays,
  progressReconciledWithDayJobs,
  savedDailyCardsForProgress,
} from "./generation-day-progress.ts";
import type { GenerationInputSnapshot } from "./generation.ts";
import type { AIProviderConfig } from "./generation.ts";

export type ParallelWeekWorkerPreparedGeneration = {
  request: GenerateWeekRequest;
  session: VerifiedDeviceSession;
  weeklySetup: Record<string, unknown> | null;
  inputSnapshot: GenerationInputSnapshot;
  providers: AIProviderConfig[];
  model: string;
  mockEnabled: boolean;
};

export type ParallelWeekWorkerHost = {
  generateDayOutput: (
    prepared: ParallelWeekWorkerPreparedGeneration,
    scheduledDate: string,
    dayIndex: number,
    generationID: string,
    retryContext?: Record<string, unknown>,
  ) => Promise<GeneratedDayOutput>;
  assertDayRespectsWeeklyBriefContext: (
    inputSnapshot: GenerationInputSnapshot,
    card: GeneratedDailyCard,
  ) => void;
  dayGenerationRetryContext: (
    day: DayGenerationState,
    dayIndex: number,
    nextAttempts: number,
  ) => Record<string, unknown> | undefined;
  readSavedDailyCards: (
    admin: SupabaseAdminClient,
    workspaceID: string,
    creatorID: string,
    weeklyPlanID: string,
  ) => Promise<{ dailyCards: GeneratedDailyCard[] } | { response: Response }>;
  makeInitialWeekStrategyOutput: (
    inputSnapshot: GenerationInputSnapshot,
  ) => GeneratedWeekOutput;
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
  dayHeartbeatIntervalMS?: number;
};

const DEFAULT_RUNNING_DAY_STALE_MS = 135_000;
const DAY_GENERATION_HEARTBEAT_MIN_MS = 1_000;
const DAY_GENERATION_HEARTBEAT_MAX_MS = 60_000;
const DEFAULT_DAY_GENERATION_MAX_ATTEMPTS = 3;

type ShutdownTelemetry = {
  generation_id: string;
  boot_id: string;
  reason:
    | "completed"
    | "cancelled"
    | "error"
    | "incomplete_loop_exit"
    | "runtime_shutdown";
  shutdown_reason?: string | null;
  active_job_ids?: string[];
  day_jobs_claimed: number;
  day_jobs_completed: number;
  day_jobs_failed: number;
  duration_ms: number;
};

type ShutdownRecord = {
  generation_id: string;
  boot_id: string;
  job_ids: string[];
  started_at: number;
};

const activeShutdownTrackers = new Map<string, ShutdownRecord>();

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function logShutdownTelemetry(telemetry: ShutdownTelemetry): void {
  console.log(JSON.stringify({
    event: "generation_shutdown",
    timestamp: new Date().toISOString(),
    execution_id: safeEnvironmentValue("SB_EXECUTION_ID"),
    ...telemetry,
  }));
}

function safeEnvironmentValue(name: string): string | null {
  try {
    return Deno.env.get(name)?.trim() || null;
  } catch {
    return null;
  }
}

function generationBootID(): string {
  return crypto.randomUUID();
}

function logWorkerLifecycle(log: {
  action: "generate_week";
  phase: "day_job_queued";
  status: "queued";
  generation_id: string | null;
  weekly_plan_id: string | null;
  week_start_date: string | null;
  scheduled_date: string | null;
  day_index: number | null;
  duration_ms: number | null;
  day_guidance_present: boolean | null;
  day_guidance_chars: number | null;
}): void {
  console.log(JSON.stringify({
    event: "generation_lifecycle",
    timestamp: new Date().toISOString(),
    ...log,
  }));
}

async function persistenceFailureDetail(
  response: Response,
): Promise<{ step: string | null; detail: string | null }> {
  try {
    const body = await response.clone().json();
    return isRecord(body)
      ? {
        step: stringValue(body.step) ?? null,
        detail: stringValue(body.detail) ?? null,
      }
      : { step: null, detail: null };
  } catch {
    return { step: null, detail: null };
  }
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

async function updateGenerationProgress(
  admin: SupabaseAdminClient,
  generationID: string,
  progress: PerDayGenerationSnapshot,
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

async function markGenerationRunFailed(
  admin: SupabaseAdminClient,
  generationID: string,
  errorCode: string,
): Promise<void> {
  await markGenerationRunFailedStore(admin, generationID, errorCode);
}

export function isGenerationRunRecordCancelled(
  run: Record<string, unknown> | null | undefined,
): boolean {
  const status = stringValue(run?.status);
  return status === "cancelled" ||
    (status === "failed" &&
      stringValue(run?.error_code) === "generation_cancelled");
}

export async function isGenerationRunCancelled(
  admin: SupabaseAdminClient,
  generationID: string,
): Promise<boolean> {
  const { data } = await readGenerationRunCancellationState(
    admin,
    generationID,
  );
  return isGenerationRunRecordCancelled(data);
}

export async function createQueuedDayJobs(
  admin: SupabaseAdminClient,
  prepared: ParallelWeekWorkerPreparedGeneration,
  generationID: string,
  weeklyPlanID: string,
): Promise<{ jobs: QueuedDayJobRecord[] } | { response: Response }> {
  const rows = weekDates(prepared.request.week_start_date).map((
    scheduledDate,
    dayIndex,
  ) => ({
    generation_run_id: generationID,
    weekly_plan_id: weeklyPlanID,
    workspace_id: prepared.session.workspaceID,
    creator_id: prepared.request.creator_id,
    scheduled_date: scheduledDate,
    day_index: dayIndex,
    status: "queued" as const,
    attempt_count: 0,
  }));

  const upsertResult = await upsertDayJobRows(admin, rows);
  if ("error" in upsertResult) {
    return generationPersistFailure(
      "create_generation_day_jobs",
      upsertResult.error,
    );
  }

  const jobs = upsertResult.jobs;
  for (const job of jobs) {
    logWorkerLifecycle({
      action: "generate_week",
      phase: "day_job_queued",
      status: "queued",
      generation_id: generationID,
      weekly_plan_id: weeklyPlanID,
      week_start_date: prepared.request.week_start_date,
      scheduled_date: job.scheduled_date,
      day_index: job.day_index,
      duration_ms: null,
      day_guidance_present: null,
      day_guidance_chars: null,
    });
  }
  return { jobs };
}

export async function createSeededDayJobsFromProgress(
  admin: SupabaseAdminClient,
  prepared: ParallelWeekWorkerPreparedGeneration,
  generationID: string,
  weeklyPlanID: string,
  progress: PerDayGenerationSnapshot,
): Promise<{ jobs: QueuedDayJobRecord[] } | { response: Response }> {
  const now = new Date().toISOString();
  const nowMS = Date.now();
  const staleThresholdMS = runningDayStaleMS();
  const maxAttempts = maxDayGenerationAttempts();
  const placeholderLease = crypto.randomUUID();
  const rows = progress.days.map((day, dayIndex) => {
    const running = day.status === "running" &&
      !isRunningDayStale(day, staleThresholdMS, nowMS);
    const terminalFailure = day.status === "failed" &&
      day.attempts >= maxAttempts;
    const status: QueuedDayJobStatus = day.status === "completed"
      ? "generated"
      : terminalFailure
      ? "failed"
      : running
      ? "generating"
      : day.status === "failed" || day.status === "running"
      ? "retrying"
      : "queued";
    return {
      generation_run_id: generationID,
      weekly_plan_id: weeklyPlanID,
      workspace_id: prepared.session.workspaceID,
      creator_id: prepared.request.creator_id,
      scheduled_date: day.scheduled_date,
      day_index: dayIndex,
      status,
      attempt_count: day.attempts,
      daily_card_id: day.daily_card_id ?? null,
      error_code: day.error_code ?? null,
      started_at: day.started_at ?? null,
      completed_at: day.completed_at ?? null,
      lease_token: running
        ? `${placeholderLease}-running-${day.scheduled_date}`
        : null,
      heartbeat_at: running ? day.heartbeat_at ?? now : null,
    };
  });

  const upsertResult = await upsertDayJobRows(admin, rows);
  if ("error" in upsertResult) {
    return generationPersistFailure(
      "create_seeded_generation_day_jobs",
      upsertResult.error,
    );
  }

  return { jobs: upsertResult.jobs };
}

async function claimedDayJobFitsLiveCapacity(
  admin: SupabaseAdminClient,
  job: QueuedDayJobRecord,
  leaseToken: string,
  concurrency: number,
  staleThresholdMS: number,
): Promise<boolean> {
  const dayJobs = await readQueuedDayJobsForRun(
    admin,
    job.generation_run_id,
    job.workspace_id,
    job.creator_id,
  );
  if ("response" in dayJobs) {
    await releaseOverCapacityDayJob(admin, job, leaseToken);
    return false;
  }

  const liveRunningCount = liveParallelDayJobCount(
    dayJobs.jobs,
    staleThresholdMS,
    Date.now(),
  );
  if (liveRunningCount <= concurrency) {
    return true;
  }

  const released = await releaseOverCapacityDayJob(admin, job, leaseToken);
  console.warn("generate-week day-job claim released over capacity", {
    generation_id: job.generation_run_id,
    job_id: job.id,
    scheduled_date: job.scheduled_date,
    day_index: job.day_index,
    attempt_count: job.attempt_count,
    live_running_count: liveRunningCount,
    concurrency,
    released,
  });
  return false;
}

export async function runParallelWeekGeneration(
  admin: SupabaseAdminClient,
  prepared: ParallelWeekWorkerPreparedGeneration,
  generationID: string,
  weeklyPlanID: string,
  progress: PerDayGenerationSnapshot,
  host: ParallelWeekWorkerHost,
): Promise<{ payload: Record<string, unknown> } | { response: Response }> {
  const bootID = generationBootID();
  registerShutdownTracking(generationID, bootID, []);
  const loopStartedAt = Date.now();
  let dayJobsClaimed = 0;
  let dayJobsCompleted = 0;
  let dayJobsFailed = 0;

  const normalizeNowMS = Date.now();
  const normalizeNowISO = new Date().toISOString();
  let latestProgress = {
    ...normalizeStaleRunningDays(progress, {
      maxAttempts: maxDayGenerationAttempts(),
      staleThresholdMS: runningDayStaleMS(),
      nowMS: normalizeNowMS,
      nowISO: normalizeNowISO,
    }),
    weekly_plan_id: weeklyPlanID,
  };
  let writeQueue = Promise.resolve();

  const recordDays = (
    states: Array<{ dayIndex: number; state: DayGenerationState }>,
  ): Promise<void> => {
    writeQueue = writeQueue.then(async () => {
      latestProgress = {
        ...latestProgress,
        days: latestProgress.days.map((day, index) => {
          const replacement = states.find((s) => s.dayIndex === index);
          return replacement ? replacement.state : day;
        }),
        updated_at: new Date().toISOString(),
      };
      const updateResult = await updateGenerationProgress(
        admin,
        generationID,
        latestProgress,
      );
      if ("response" in updateResult) {
        throw new Error("generation_persist_failed:update_generation_progress");
      }
    });
    return writeQueue;
  };

  const concurrency = parallelWeekGenerationConcurrency();
  const heartbeatIntervalMS = dayGenerationHeartbeatMS(host);
  const staleThresholdMS = runningDayStaleMS();
  let cancelled = false;

  const inFlight = new Map<
    string,
    Promise<{ job: QueuedDayJobRecord; state: DayGenerationState }>
  >();

  while (true) {
    if (await isGenerationRunCancelled(admin, generationID)) {
      cancelled = true;
      break;
    }

    const dayJobs = await readQueuedDayJobsForRun(
      admin,
      generationID,
      prepared.session.workspaceID,
      prepared.request.creator_id,
    );
    if ("response" in dayJobs) break;

    const hasWork = dayJobs.jobs.some((j) =>
      j.status === "queued" || j.status === "retrying" ||
      j.status === "generating" || j.status === "ready_to_persist"
    );
    if (!hasWork && inFlight.size === 0) break;

    const slotsFree = availableParallelDayJobSlots(
      dayJobs.jobs,
      concurrency,
      staleThresholdMS,
      Date.now(),
    );

    const readyJobs = dayJobs.jobs.filter((job) =>
      job.status === "ready_to_persist" && job.staged_output
    );
    for (const job of readyJobs) {
      if (inFlight.has(job.id)) continue;
      const taskPromise = persistReadyDayJob(
        admin,
        prepared,
        weeklyPlanID,
        job,
        host,
      ).then((state) => ({ job, state }));
      inFlight.set(job.id, taskPromise);
    }

    for (let slot = 0; slot < slotsFree; slot++) {
      const leaseToken = crypto.randomUUID();
      let claimed = await claimQueuedDayJob(
        admin,
        generationID,
        leaseToken,
        bootID,
        concurrency,
        staleThresholdMS,
      );

      if (!claimed) {
        claimed = await reclaimStaleDayJob(
          admin,
          generationID,
          leaseToken,
          bootID,
          staleThresholdMS,
          concurrency,
          maxDayGenerationAttempts(),
        );
      }

      if (!claimed) break;

      const job = claimed;
      const fitsCapacity = await claimedDayJobFitsLiveCapacity(
        admin,
        job,
        leaseToken,
        concurrency,
        staleThresholdMS,
      );
      if (!fitsCapacity) break;

      dayJobsClaimed++;
      console.log("generate-week parallel day job claimed", {
        generation_id: generationID,
        job_id: job.id,
        scheduled_date: job.scheduled_date,
        day_index: job.day_index,
        attempt_count: job.attempt_count,
        concurrency,
      });
      trackShutdownJob(generationID, job.id);
      const dayIndex = job.day_index;
      const snapshotDay = latestProgress.days[dayIndex];
      const retryContext = host.dayGenerationRetryContext(
        {
          scheduled_date: job.scheduled_date,
          status: job.status === "retrying"
            ? "failed"
            : snapshotDay?.status ?? "pending",
          attempts: job.attempt_count ?? 0,
          error_code: snapshotDay?.error_code ?? job.error_code ?? undefined,
        },
        dayIndex,
        job.attempt_count ?? 1,
      );

      const heartbeatID = setInterval(() => {
        heartbeatDayJob(admin, job.id, leaseToken).catch(() => {});
      }, heartbeatIntervalMS);

      const taskPromise = runParallelDayGenerationTask(
        admin,
        prepared,
        generationID,
        weeklyPlanID,
        job.scheduled_date,
        dayIndex,
        job.attempt_count ?? 1,
        host,
        retryContext,
        job.id,
        leaseToken,
      ).then((state) => {
        if (state.status === "completed") dayJobsCompleted++;
        else dayJobsFailed++;
        return { job, state };
      }).finally(() => clearInterval(heartbeatID));

      inFlight.set(job.id, taskPromise);
    }

    if (inFlight.size === 0) {
      // Fresh generating rows are owned by another isolate. This invocation
      // must return instead of holding the worker open until they become stale.
      break;
    }

    const done = await Promise.race(inFlight.values());
    inFlight.delete(done.job.id);
    await recordDays([{ dayIndex: done.job.day_index, state: done.state }]);

    if (await isGenerationRunCancelled(admin, generationID)) {
      cancelled = true;
      const remaining = await Promise.all(inFlight.values());
      for (const r of remaining) {
        await recordDays([{ dayIndex: r.job.day_index, state: r.state }]);
      }
      break;
    }
  }

  await writeQueue;
  const finalJobsResult = await readQueuedDayJobsForRun(
    admin,
    generationID,
    prepared.session.workspaceID,
    prepared.request.creator_id,
  );
  if (!("response" in finalJobsResult)) {
    latestProgress = {
      ...progressReconciledWithDayJobs(
        latestProgress,
        finalJobsResult.jobs,
        new Date().toISOString(),
      ),
      weekly_plan_id: weeklyPlanID,
    };
    await updateGenerationProgress(admin, generationID, latestProgress);
  }

  logShutdownTelemetry({
    generation_id: generationID,
    boot_id: bootID,
    reason: cancelled
      ? "cancelled"
      : dayJobsCompleted + dayJobsFailed === 0
      ? "incomplete_loop_exit"
      : "completed",
    day_jobs_claimed: dayJobsClaimed,
    day_jobs_completed: dayJobsCompleted,
    day_jobs_failed: dayJobsFailed,
    duration_ms: Date.now() - loopStartedAt,
  });
  deregisterShutdownTracking(generationID);

  const activeCheckNowMS = Date.now();
  const activeCheckStaleMS = runningDayStaleMS();
  if (
    cancelled &&
    hasActiveParallelDayGeneration(
      latestProgress,
      activeCheckStaleMS,
      activeCheckNowMS,
    )
  ) {
    const summary = weekGenerationStatusSummary(
      latestProgress,
      "running",
      (day) => isTerminalDayGenerationState(day, maxDayGenerationAttempts()),
    );
    return {
      payload: {
        generation_id: generationID,
        weekly_plan_id: weeklyPlanID,
        status: "cancelled",
        message: "generation_cancelled",
        ...summary,
        poll_after_seconds: null,
      },
    };
  }

  if (
    hasActiveParallelDayGeneration(
      latestProgress,
      activeCheckStaleMS,
      activeCheckNowMS,
    )
  ) {
    const summary = weekGenerationStatusSummary(
      latestProgress,
      "running",
      (day) => isTerminalDayGenerationState(day, maxDayGenerationAttempts()),
    );
    return {
      payload: {
        generation_id: generationID,
        weekly_plan_id: weeklyPlanID,
        status: summary.overall_status === "completed"
          ? "draft"
          : summary.overall_status,
        ...summary,
        poll_after_seconds: summary.overall_status === "running" ? 5 : null,
      },
    };
  }
  return await finalizeParallelWeekGeneration(
    admin,
    prepared,
    generationID,
    weeklyPlanID,
    latestProgress,
    host,
  );
}

export function parallelWeekGenerationConcurrency(): number {
  const configured = Deno.env.get("MCO_PARALLEL_WEEK_GENERATION_CONCURRENCY")
    ?.trim();
  const parsed = configured ? Number(configured) : 2;
  if (!Number.isFinite(parsed)) {
    return 2;
  }
  return Math.max(1, Math.min(Math.trunc(parsed), 7));
}

async function runParallelDayGenerationTask(
  admin: SupabaseAdminClient,
  prepared: ParallelWeekWorkerPreparedGeneration,
  generationID: string,
  weeklyPlanID: string,
  scheduledDate: string,
  dayIndex: number,
  attempts: number,
  host: ParallelWeekWorkerHost,
  retryContext?: Record<string, unknown>,
  jobID?: string,
  leaseToken?: string,
): Promise<DayGenerationState> {
  const startedAt = new Date().toISOString();
  if (await isGenerationRunCancelled(admin, generationID)) {
    if (jobID && leaseToken) {
      await failDayJob(admin, jobID, leaseToken, "generation_cancelled");
    }
    return {
      scheduled_date: scheduledDate,
      status: "failed",
      attempts,
      started_at: startedAt,
      completed_at: new Date().toISOString(),
      error_code: "generation_cancelled",
    };
  }
  try {
    const rawOutput = await host.generateDayOutput(
      prepared,
      scheduledDate,
      dayIndex,
      generationID,
      retryContext,
    );
    const output = validateGeneratedDayOutput(
      rawOutput,
      scheduledDate,
      dayIndex,
    );
    host.assertDayRespectsWeeklyBriefContext(
      prepared.inputSnapshot,
      output.daily_card,
    );
    if (jobID && leaseToken) {
      const staged = await stageDayJobOutput(
        admin,
        jobID,
        leaseToken,
        attempts,
        output as unknown as Record<string, unknown>,
      );
      if (!staged) {
        return {
          scheduled_date: scheduledDate,
          status: "running",
          attempts,
          started_at: startedAt,
        };
      }
    }
    return await persistGeneratedDayOutput(
      admin,
      prepared,
      weeklyPlanID,
      output,
      scheduledDate,
      attempts,
      startedAt,
      jobID,
      leaseToken,
    );
  } catch (error) {
    const errorCode = stableGenerationError(error);
    if (jobID && leaseToken) {
      await failDayJob(admin, jobID, leaseToken, errorCode);
    }
    return {
      scheduled_date: scheduledDate,
      status: "failed",
      attempts,
      started_at: startedAt,
      completed_at: new Date().toISOString(),
      error_code: errorCode,
    };
  }
}

async function persistReadyDayJob(
  admin: SupabaseAdminClient,
  prepared: ParallelWeekWorkerPreparedGeneration,
  weeklyPlanID: string,
  job: QueuedDayJobRecord,
  host: ParallelWeekWorkerHost,
): Promise<DayGenerationState> {
  const startedAt = job.started_at ?? new Date().toISOString();
  try {
    if (!job.staged_output) {
      throw new Error("invalid_generated_week:missing_staged_output");
    }
    const output = validateGeneratedDayOutput(
      job.staged_output as unknown as GeneratedDayOutput,
      job.scheduled_date,
      job.day_index,
    );
    host.assertDayRespectsWeeklyBriefContext(
      prepared.inputSnapshot,
      output.daily_card,
    );
    return await persistGeneratedDayOutput(
      admin,
      prepared,
      weeklyPlanID,
      output,
      job.scheduled_date,
      job.attempt_count ?? 1,
      startedAt,
      job.id,
      job.lease_token ?? undefined,
    );
  } catch (error) {
    const errorCode = stableGenerationError(error);
    if (job.lease_token) {
      await failDayJob(admin, job.id, job.lease_token, errorCode);
    }
    return {
      scheduled_date: job.scheduled_date,
      status: "failed",
      attempts: job.attempt_count ?? 1,
      started_at: startedAt,
      completed_at: new Date().toISOString(),
      error_code: errorCode,
    };
  }
}

async function persistGeneratedDayOutput(
  admin: SupabaseAdminClient,
  prepared: ParallelWeekWorkerPreparedGeneration,
  weeklyPlanID: string,
  output: GeneratedDayOutput,
  scheduledDate: string,
  attempts: number,
  startedAt: string,
  jobID?: string,
  leaseToken?: string,
): Promise<DayGenerationState> {
  try {
    const persistResult = await upsertGeneratedDailyCards(
      admin,
      prepared.session.workspaceID,
      prepared.request.creator_id,
      weeklyPlanID,
      [output.daily_card],
      prepared.request.preserve_manual_edits,
    );
    if ("response" in persistResult) {
      const failure = await persistenceFailureDetail(persistResult.response);
      const errorCode = failure.step
        ? `generation_persist_failed:${failure.step}`
        : "generation_persist_failed";
      if (jobID && leaseToken) {
        await failDayJob(
          admin,
          jobID,
          leaseToken,
          errorCode,
          failure.detail ?? undefined,
        );
      }
      return {
        scheduled_date: scheduledDate,
        status: "failed",
        attempts,
        started_at: startedAt,
        completed_at: new Date().toISOString(),
        error_code: errorCode,
      };
    }

    const ideaResult = await insertGeneratedIdeas(
      admin,
      prepared.session.workspaceID,
      prepared.request.creator_id,
      {
        strategy_summary: output.strategy_note,
        warnings: output.warnings,
        assumptions: output.assumptions,
        daily_cards: [output.daily_card],
        idea_bank: output.idea_bank,
        source_summary: output.source_summary,
      },
    );
    if ("response" in ideaResult) {
      console.warn("generate-week day idea insert failed; continuing", {
        scheduled_date: scheduledDate,
      });
    }

    const cardID = persistResult.dailyCards[0]?.id;
    if (jobID && leaseToken && cardID) {
      await completeDayJob(admin, jobID, leaseToken, cardID);
    }

    return {
      scheduled_date: scheduledDate,
      status: "completed",
      attempts,
      daily_card_id: cardID,
      started_at: startedAt,
      completed_at: new Date().toISOString(),
    };
  } catch (error) {
    const errorCode = stableGenerationError(error);
    if (jobID && leaseToken) {
      await failDayJob(admin, jobID, leaseToken, errorCode);
    }
    return {
      scheduled_date: scheduledDate,
      status: "failed",
      attempts,
      started_at: startedAt,
      completed_at: new Date().toISOString(),
      error_code: errorCode,
    };
  }
}

export async function finalizeParallelWeekGeneration(
  admin: SupabaseAdminClient,
  prepared: ParallelWeekWorkerPreparedGeneration,
  generationID: string,
  weeklyPlanID: string,
  progress: PerDayGenerationSnapshot,
  host: ParallelWeekWorkerHost,
): Promise<{ payload: Record<string, unknown> } | { response: Response }> {
  const completedAt = new Date().toISOString();
  const savedCards = await host.readSavedDailyCards(
    admin,
    prepared.session.workspaceID,
    prepared.request.creator_id,
    weeklyPlanID,
  );
  if ("response" in savedCards) {
    await markGenerationRunFailed(
      admin,
      generationID,
      "generation_persist_failed",
    );
    return savedCards;
  }

  const savedCardsForRun = savedDailyCardsForProgress(
    savedCards.dailyCards,
    progress,
  );

  // Merge fallback timestamps are created after the saved-card read (pre-extraction timing).
  const mergeNowISO = new Date().toISOString();
  const finalProgress = {
    ...mergeSavedDailyCardsIntoProgress(
      progress,
      savedCardsForRun,
      mergeNowISO,
    ),
    updated_at: completedAt,
  };
  const summary = weekGenerationStatusSummary(
    finalProgress,
    savedCardsForRun.length === 0 ? "failed" : "completed",
    (day) => isTerminalDayGenerationState(day, maxDayGenerationAttempts()),
  );

  if (summary.saved_day_count === 0) {
    await updateGenerationProgress(admin, generationID, finalProgress);
    await markGenerationRunFailed(
      admin,
      generationID,
      "invalid_generated_week",
    );
    return {
      response: jsonResponse({
        generation_id: generationID,
        weekly_plan_id: weeklyPlanID,
        status: "failed",
        error: "invalid_generated_week",
        ...summary,
      }, 400),
    };
  }

  const strategy = host.makeInitialWeekStrategyOutput(prepared.inputSnapshot);
  if (summary.saved_day_count === summary.total_day_count) {
    const generated: GeneratedWeekOutput = {
      ...strategy,
      daily_cards: savedCardsForRun,
      idea_bank: [],
    };
    const payload = host.makeGenerateWeekDraftResponse(
      generationID,
      weeklyPlanID,
      generated,
      savedCardsForRun,
      [],
      completedAt,
    );
    const completedResult = await host.completeGenerationRun(
      admin,
      generationID,
      weeklyPlanID,
      payload,
      completedAt,
    );
    if ("response" in completedResult) {
      return completedResult;
    }
    return {
      payload: {
        ...payload,
        ...completedDraftStatusSummary(
          payload,
          prepared.request.week_start_date,
        ),
      },
    };
  }

  const payload = {
    generation_id: generationID,
    weekly_plan_id: weeklyPlanID,
    status: "partial",
    strategy_summary: progress.strategy_summary ?? strategy.strategy_summary,
    warnings: [
      ...(progress.warnings ?? []),
      "Some days were saved and some days failed. Retry failed days before publishing.",
    ],
    assumptions: progress.assumptions ?? [],
    daily_cards: savedCardsForRun,
    idea_bank: [],
    source_summary: progress.source_summary ?? strategy.source_summary,
    generated_at: completedAt,
    ...summary,
  };
  const completedResult = await completePartialGenerationRun(
    admin,
    generationID,
    weeklyPlanID,
    finalProgress,
    completedAt,
  );
  if ("response" in completedResult) {
    return completedResult;
  }
  return { payload };
}

export async function completePartialGenerationRun(
  admin: SupabaseAdminClient,
  generationID: string,
  weeklyPlanID: string,
  progress: PerDayGenerationSnapshot,
  completedAt: string,
): Promise<{ ok: true } | { response: Response }> {
  const { error } = await completePartialGenerationRunStore(
    admin,
    generationID,
    {
      weekly_plan_id: weeklyPlanID,
      output_snapshot: progress,
      completed_at: completedAt,
    },
  );
  if (error) {
    return generationPersistFailure("complete_partial_generation_run", error);
  }
  return { ok: true };
}

export function shouldDispatchQueuedDayJobRecovery(
  jobs: QueuedDayJobRecord[],
): boolean {
  const staleThresholdMS = runningDayStaleMS();
  const hasReadyToPersist = jobs.some((job) =>
    job.status === "ready_to_persist" && job.staged_output
  );
  if (hasReadyToPersist) {
    return true;
  }

  const hasRunnableJob = jobs.some((job) =>
    job.status === "queued" || job.status === "retrying" ||
    (job.status === "generating" &&
      isQueuedDayJobStale(job, staleThresholdMS))
  );
  if (!hasRunnableJob) {
    return false;
  }

  return availableParallelDayJobSlots(
    jobs,
    parallelWeekGenerationConcurrency(),
    staleThresholdMS,
    Date.now(),
  ) > 0;
}

export function availableParallelDayJobSlots(
  jobs: Array<{
    status?: unknown;
    heartbeat_at?: unknown;
    started_at?: unknown;
  }>,
  concurrency: number,
  staleThresholdMS: number,
  now = Date.now(),
): number {
  return availableParallelDayJobSlotsFor(
    jobs,
    concurrency,
    staleThresholdMS,
    now,
  );
}

function dayGenerationHeartbeatMS(
  host: ParallelWeekWorkerHost,
): number {
  const configured = host.dayHeartbeatIntervalMS;
  if (
    typeof configured === "number" && Number.isFinite(configured) &&
    configured > 0
  ) {
    return Math.max(Math.trunc(configured), 10);
  }
  return Math.max(
    DAY_GENERATION_HEARTBEAT_MIN_MS,
    Math.min(
      Math.floor(runningDayStaleMS() / 4),
      DAY_GENERATION_HEARTBEAT_MAX_MS,
    ),
  );
}

export function runningDayStaleMS(): number {
  const configured = Deno.env.get("MCO_GENERATION_DAY_STALE_MS")?.trim();
  if (!configured) {
    return DEFAULT_RUNNING_DAY_STALE_MS;
  }
  const parsed = Number(configured);
  if (!Number.isFinite(parsed) || parsed < 30_000) {
    return DEFAULT_RUNNING_DAY_STALE_MS;
  }
  return Math.min(parsed, 600_000);
}

export function maxDayGenerationAttempts(): number {
  const configured = Deno.env.get("MCO_GENERATION_DAY_MAX_ATTEMPTS")?.trim();
  if (!configured) {
    return DEFAULT_DAY_GENERATION_MAX_ATTEMPTS;
  }

  const parsed = Number(configured);
  if (!Number.isFinite(parsed) || parsed < 1) {
    return DEFAULT_DAY_GENERATION_MAX_ATTEMPTS;
  }
  return Math.min(Math.trunc(parsed), 5);
}

function registerShutdownTracking(
  generationID: string,
  bootID: string,
  jobIDs: string[],
): void {
  activeShutdownTrackers.set(generationID, {
    generation_id: generationID,
    boot_id: bootID,
    job_ids: [...jobIDs],
    started_at: Date.now(),
  });
}

function trackShutdownJob(generationID: string, jobID: string): void {
  const tracker = activeShutdownTrackers.get(generationID);
  if (!tracker || tracker.job_ids.includes(jobID)) return;
  tracker.job_ids.push(jobID);
}

function deregisterShutdownTracking(generationID: string): void {
  activeShutdownTrackers.delete(generationID);
}

if (typeof globalThis.addEventListener === "function") {
  globalThis.addEventListener("beforeunload", (event) => {
    const now = Date.now();
    const shutdownReason = isRecord(event) && isRecord(event.detail)
      ? stringValue(event.detail.reason) ?? "unknown"
      : "unknown";
    const entries = [...activeShutdownTrackers.values()];
    for (const entry of entries) {
      logShutdownTelemetry({
        generation_id: entry.generation_id,
        boot_id: entry.boot_id,
        reason: "runtime_shutdown",
        shutdown_reason: shutdownReason,
        active_job_ids: entry.job_ids,
        day_jobs_claimed: 0,
        day_jobs_completed: 0,
        day_jobs_failed: 0,
        duration_ms: now - entry.started_at,
      });
      activeShutdownTrackers.delete(entry.generation_id);
    }
  });
}
