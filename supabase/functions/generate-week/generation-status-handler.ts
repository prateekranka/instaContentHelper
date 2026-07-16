import {
  jsonResponse,
  SupabaseAdminClient,
  VerifiedDeviceSession,
} from "../_shared/device-auth.ts";
import type {
  AIProviderConfig,
  GeneratedDailyCard,
  GeneratedWeekOutput,
  GenerationInputSnapshot,
  RegenerateDayRequest,
} from "./generation.ts";
import { isUUID } from "./generation-validation.ts";
import { readQueuedDayJobsForRun } from "./generation-day-job-store.ts";
import { generationPersistFailure } from "./generation-persistence.ts";
import {
  allDaysTerminal,
  isParallelWeekGenerationTerminal,
  isTerminalDayGenerationState,
  mergeSavedDailyCardsIntoProgress,
  normalizeStaleRunningDays,
  savedDailyCardsForProgress,
  shouldResumeParallelWeekGeneration,
} from "./generation-day-progress.ts";
import {
  createSeededDayJobsFromProgress,
  finalizeParallelWeekGeneration,
  isGenerationRunRecordCancelled,
  maxDayGenerationAttempts,
  parallelWeekGenerationConcurrency,
  type ParallelWeekWorkerHost,
  type ParallelWeekWorkerPreparedGeneration,
  runningDayStaleMS,
  runParallelWeekGeneration,
  shouldDispatchQueuedDayJobRecovery,
} from "./generation-parallel-week-worker.ts";
import {
  completedDraftStatusSummary,
  initialParallelWeekGenerationSnapshot,
  normalizePerDayGenerationSnapshot,
  queuedDayJobStatusSummary,
  weekGenerationStatusSummary,
} from "./generation-status.ts";
import type {
  PerDayGenerationSnapshot,
  QueuedDayJobRecord,
} from "./generation-status.ts";
import {
  isDayDraftResponseSnapshot,
  isDraftResponseSnapshot,
  normalizeSingleDayGenerationSnapshot,
  normalizeStoredInputSnapshot,
} from "./generation-run-snapshot.ts";
import type {
  GenerationRunStatusRecord,
  SingleDayGenerationSnapshot,
} from "./generation-run-snapshot.ts";
import { readGenerationRunStatus } from "./generation-run-store.ts";

export type EnvReader = {
  get: (name: string) => string | undefined;
};

export type StatusHandlerPreparedDayGeneration = {
  request: RegenerateDayRequest;
  session: VerifiedDeviceSession;
  plan: {
    id: string;
    week_start_date?: string;
    weekly_setup_id?: string | null;
    status?: string;
  };
  targetCard?: Record<string, unknown> & {
    id: string;
    scheduled_date: string;
  };
  inputSnapshot: GenerationInputSnapshot;
  providers: AIProviderConfig[];
  model: string;
  mockEnabled: boolean;
};

export type GenerationStatusHandlerHost = {
  prepareGenerationFromRun: (
    env: EnvReader,
    run: GenerationRunStatusRecord,
    session: VerifiedDeviceSession,
    inputSnapshot: GenerationInputSnapshot,
  ) =>
    | { prepared: ParallelWeekWorkerPreparedGeneration }
    | { response: Response };
  prepareSingleDayGenerationFromRun: (
    admin: SupabaseAdminClient,
    generationID: string,
    env: EnvReader,
    run: GenerationRunStatusRecord,
    session: VerifiedDeviceSession,
    inputSnapshot: GenerationInputSnapshot,
    progress: SingleDayGenerationSnapshot,
  ) => Promise<
    | { prepared: StatusHandlerPreparedDayGeneration }
    | { response: Response }
  >;
  markGenerationRunFailed: (
    admin: SupabaseAdminClient,
    generationID: string,
    errorCode: string,
  ) => Promise<void>;
  updateGenerationProgress: (
    admin: SupabaseAdminClient,
    generationID: string,
    progress: PerDayGenerationSnapshot | SingleDayGenerationSnapshot,
  ) => Promise<{ ok: true } | { response: Response }>;
  scheduleNextPendingDayGeneration: (
    admin: SupabaseAdminClient,
    generationID: string,
    prepared: ParallelWeekWorkerPreparedGeneration,
    progress: PerDayGenerationSnapshot,
  ) => Promise<
    { progress: PerDayGenerationSnapshot } | { response: Response }
  >;
  readSavedDailyCards: (
    admin: SupabaseAdminClient,
    workspaceID: string,
    creatorID: string,
    weeklyPlanID: string,
  ) => Promise<
    { dailyCards: GeneratedDailyCard[] } | { response: Response }
  >;
  scheduleSingleDayGeneration: (
    admin: SupabaseAdminClient,
    generationID: string,
    prepared: StatusHandlerPreparedDayGeneration,
    progress: SingleDayGenerationSnapshot,
  ) => Promise<{ ok: true } | { response: Response }>;
  runParallelWeekGenerationInBackground: (
    admin: SupabaseAdminClient,
    prepared: ParallelWeekWorkerPreparedGeneration,
    generationID: string,
    weeklyPlanID: string,
    progress: PerDayGenerationSnapshot,
  ) => void;
  parallelWeekWorkerHost: ParallelWeekWorkerHost;
  makeInitialWeekStrategyOutput: (
    inputSnapshot: GenerationInputSnapshot,
  ) => GeneratedWeekOutput;
};

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0
    ? value
    : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isDayGenerationRun(run: GenerationRunStatusRecord): boolean {
  return run.generation_scope === "day";
}

function isLegacyGenerationStatusReadOnly(
  run: GenerationRunStatusRecord,
): boolean {
  return !isDayGenerationRun(run);
}

export async function readGenerationStatus(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  body: Record<string, unknown>,
  env: EnvReader,
  host: GenerationStatusHandlerHost,
): Promise<Response> {
  const generationID = stringValue(body.generation_id);
  const creatorID = stringValue(body.creator_id);
  if (
    !isUUID(generationID) || (creatorID !== undefined && !isUUID(creatorID))
  ) {
    return jsonResponse({ error: "invalid_generation_payload" }, 400);
  }

  const { data, error } = await readGenerationRunStatus(
    admin,
    generationID,
    session.workspaceID,
  );

  if (error) {
    return generationPersistFailure("read_generation_status", error).response;
  }
  if (!isRecord(data)) {
    return jsonResponse({ error: "invalid_generation_payload" }, 404);
  }
  if (creatorID && data.creator_id !== creatorID) {
    return jsonResponse({ error: "invalid_generation_payload" }, 404);
  }

  const queuedJobsResult = await readQueuedDayJobsForRun(
    admin,
    generationID,
    session.workspaceID,
    stringValue(data.creator_id) ?? "",
  );
  if ("response" in queuedJobsResult) {
    return queuedJobsResult.response;
  }
  if (queuedJobsResult.jobs.length > 0) {
    const runRecord = data as GenerationRunStatusRecord;
    if (isGenerationRunRecordCancelled(runRecord)) {
      const summary = queuedDayJobStatusSummary(queuedJobsResult.jobs);
      return jsonResponse({
        generation_id: generationID,
        weekly_plan_id: stringValue(runRecord.weekly_plan_id) ??
          queuedJobsResult.jobs.find((job) => isUUID(job.weekly_plan_id))
            ?.weekly_plan_id ??
          null,
        status: "cancelled",
        message: "generation_cancelled",
        ...summary,
        days: summary.day_statuses,
        failed_days: summary.day_statuses.filter((day) =>
          day.status === "failed"
        ),
        poll_after_seconds: null,
      });
    }
    if (
      stringValue(runRecord.status) === "running" &&
      !isLegacyGenerationStatusReadOnly(runRecord)
    ) {
      dispatchQueuedDayJobRecovery(
        admin,
        generationID,
        runRecord,
        queuedJobsResult.jobs,
        env,
        host,
      );
    }
    return await readQueuedGenerationStatus(
      admin,
      generationID,
      runRecord,
      queuedJobsResult.jobs,
      host,
    );
  }

  const status = stringValue(data.status) ?? "running";
  if (status === "completed") {
    if (isDraftResponseSnapshot(data.output_snapshot)) {
      const inputSnapshot = normalizeStoredInputSnapshot(
        (data as GenerationRunStatusRecord).input_snapshot,
      );
      return jsonResponse({
        ...data.output_snapshot,
        ...completedDraftStatusSummary(
          data.output_snapshot,
          inputSnapshot?.week_start_date,
        ),
      });
    }
    if (isDayDraftResponseSnapshot(data.output_snapshot)) {
      return jsonResponse({ ...data.output_snapshot });
    }
    const run = data as GenerationRunStatusRecord;
    const inputSnapshot = normalizeStoredInputSnapshot(run.input_snapshot);
    if (inputSnapshot) {
      const progress = normalizePerDayGenerationSnapshot(
        run.output_snapshot,
        inputSnapshot.week_start_date,
      );
      if (progress.kind === "parallel_week_generation_v1") {
        return await readParallelGenerationStatus(
          admin,
          generationID,
          run,
          session,
          inputSnapshot,
          progress,
          env,
          host,
          { readOnly: isLegacyGenerationStatusReadOnly(run) },
        );
      }
      return await readCompletedPerDayGenerationStatus(
        admin,
        generationID,
        run,
        session,
        inputSnapshot,
        progress,
        host,
      );
    }
    return jsonResponse({
      generation_id: generationID,
      status: "failed",
      error: "invalid_generated_week",
    });
  }

  if (status === "failed") {
    const inputSnapshot = normalizeStoredInputSnapshot(
      (data as GenerationRunStatusRecord).input_snapshot,
    );
    if (inputSnapshot) {
      const progress = normalizePerDayGenerationSnapshot(
        (data as GenerationRunStatusRecord).output_snapshot,
        inputSnapshot.week_start_date,
      );
      if (progress.kind === "parallel_week_generation_v1") {
        return await readParallelGenerationStatus(
          admin,
          generationID,
          data as GenerationRunStatusRecord,
          session,
          inputSnapshot,
          progress,
          env,
          host,
          {
            readOnly: isLegacyGenerationStatusReadOnly(
              data as GenerationRunStatusRecord,
            ),
          },
        );
      }
      const summary = weekGenerationStatusSummary(
        progress,
        "failed",
        (day) => isTerminalDayGenerationState(day, maxDayGenerationAttempts()),
      );
      return jsonResponse({
        generation_id: generationID,
        status: summary.overall_status,
        error: stringValue(data.error_code) ?? "invalid_generated_week",
        ...summary,
        poll_after_seconds: summary.overall_status === "partial" ? null : 5,
      });
    }
    return jsonResponse({
      generation_id: generationID,
      status: "failed",
      error: stringValue(data.error_code) ?? "invalid_generated_week",
    });
  }

  const run = data as GenerationRunStatusRecord;
  const inputSnapshot = normalizeStoredInputSnapshot(run.input_snapshot);
  if (!inputSnapshot) {
    if (isDayGenerationRun(run)) {
      await host.markGenerationRunFailed(
        admin,
        generationID,
        "invalid_generation_payload",
      );
    }
    return jsonResponse({
      generation_id: generationID,
      status: "failed",
      error: "invalid_generation_payload",
    });
  }

  if (isDayGenerationRun(run)) {
    return await resumeSingleDayGeneration(
      admin,
      generationID,
      run,
      session,
      inputSnapshot,
      env,
      host,
    );
  }

  const progress = normalizePerDayGenerationSnapshot(
    run.output_snapshot,
    inputSnapshot.week_start_date,
  );
  if (progress.kind === "parallel_week_generation_v1") {
    return await readParallelGenerationStatus(
      admin,
      generationID,
      run,
      session,
      inputSnapshot,
      progress,
      env,
      host,
      { readOnly: true },
    );
  }
  if (allDaysTerminal(progress, maxDayGenerationAttempts())) {
    return await readCompletedPerDayGenerationStatus(
      admin,
      generationID,
      run,
      session,
      inputSnapshot,
      progress,
      host,
    );
  }
  return readLegacyPerDayRunningGenerationStatus(generationID, progress);
}

function readLegacyPerDayRunningGenerationStatus(
  generationID: string,
  progress: PerDayGenerationSnapshot,
): Response {
  const summary = weekGenerationStatusSummary(
    progress,
    "running",
    (day) => isTerminalDayGenerationState(day, maxDayGenerationAttempts()),
  );
  const responseStatus = summary.overall_status === "completed"
    ? "draft"
    : summary.overall_status;
  return jsonResponse({
    generation_id: generationID,
    status: responseStatus,
    ...summary,
    poll_after_seconds: summary.overall_status === "running" ? 5 : null,
  });
}

function dispatchQueuedDayJobRecovery(
  admin: SupabaseAdminClient,
  generationID: string,
  run: GenerationRunStatusRecord,
  jobs: QueuedDayJobRecord[],
  env: EnvReader,
  host: GenerationStatusHandlerHost,
): void {
  if (!shouldDispatchQueuedDayJobRecovery(jobs)) {
    return;
  }

  const inputSnapshot = normalizeStoredInputSnapshot(run.input_snapshot);
  if (!inputSnapshot) return;

  const preparedResult = host.prepareGenerationFromRun(env, run, {
    workspaceID: stringValue(run.workspace_id) ?? "",
    memberID: stringValue(run.requested_by_member_id) ?? "",
  } as VerifiedDeviceSession, inputSnapshot);
  if ("response" in preparedResult) return;

  const weeklyPlanID = stringValue(run.weekly_plan_id);
  if (!weeklyPlanID || !isUUID(weeklyPlanID)) return;

  host.runParallelWeekGenerationInBackground(
    admin,
    preparedResult.prepared,
    generationID,
    weeklyPlanID,
    initialParallelWeekGenerationSnapshot(
      inputSnapshot.week_start_date,
      weeklyPlanID,
      host.makeInitialWeekStrategyOutput(inputSnapshot),
    ),
  );
}

export async function readQueuedGenerationStatus(
  admin: SupabaseAdminClient,
  generationID: string,
  run: GenerationRunStatusRecord,
  jobs: QueuedDayJobRecord[],
  host: GenerationStatusHandlerHost,
): Promise<Response> {
  const weeklyPlanID = stringValue(run.weekly_plan_id) ??
    jobs.find((job) => isUUID(job.weekly_plan_id))?.weekly_plan_id ?? null;
  const summary = queuedDayJobStatusSummary(jobs);
  const responseStatus = summary.overall_status === "completed"
    ? "draft"
    : summary.overall_status;
  const dailyCardsResult = weeklyPlanID
    ? await host.readSavedDailyCards(
      admin,
      stringValue(run.workspace_id) ?? "",
      stringValue(run.creator_id) ?? "",
      weeklyPlanID,
    )
    : { dailyCards: [] as GeneratedDailyCard[] };
  if ("response" in dailyCardsResult) {
    return dailyCardsResult.response;
  }

  return jsonResponse({
    generation_id: generationID,
    weekly_plan_id: weeklyPlanID,
    status: responseStatus,
    daily_cards: dailyCardsResult.dailyCards,
    ...summary,
    days: summary.day_statuses,
    failed_days: summary.day_statuses.filter((day) => day.status === "failed"),
    poll_after_seconds: summary.overall_status === "running" ? 5 : null,
  });
}

async function resumeSingleDayGeneration(
  admin: SupabaseAdminClient,
  generationID: string,
  run: GenerationRunStatusRecord,
  session: VerifiedDeviceSession,
  inputSnapshot: GenerationInputSnapshot,
  env: EnvReader,
  host: GenerationStatusHandlerHost,
): Promise<Response> {
  const progress = normalizeSingleDayGenerationSnapshot(
    run.output_snapshot,
    run,
  );
  const weeklyPlanID = stringValue(run.weekly_plan_id);
  const scheduledDate = stringValue(run.target_scheduled_date);
  if (!progress || !isUUID(weeklyPlanID) || !scheduledDate) {
    await host.markGenerationRunFailed(
      admin,
      generationID,
      "invalid_generation_payload",
    );
    return jsonResponse({
      generation_id: generationID,
      status: "failed",
      error: "invalid_generation_payload",
    });
  }

  const preparedResult = await host.prepareSingleDayGenerationFromRun(
    admin,
    generationID,
    env,
    run,
    session,
    inputSnapshot,
    progress,
  );
  if ("response" in preparedResult) {
    return preparedResult.response;
  }

  const isActive = progress.status === "running" &&
    progress.started_at &&
    Date.now() - Date.parse(progress.started_at) <= 10 * 60 * 1000;
  if (!isActive) {
    const scheduleResult = await host.scheduleSingleDayGeneration(
      admin,
      generationID,
      preparedResult.prepared,
      { ...progress, status: "pending", started_at: undefined },
    );
    if ("response" in scheduleResult) {
      return scheduleResult.response;
    }
  }

  return jsonResponse({
    generation_id: generationID,
    weekly_plan_id: weeklyPlanID,
    status: "running",
    target_scheduled_date: scheduledDate,
    poll_after_seconds: 5,
  });
}

async function readCompletedPerDayGenerationStatus(
  admin: SupabaseAdminClient,
  generationID: string,
  run: GenerationRunStatusRecord,
  session: VerifiedDeviceSession,
  inputSnapshot: GenerationInputSnapshot,
  progress: PerDayGenerationSnapshot,
  host: GenerationStatusHandlerHost,
): Promise<Response> {
  const weeklyPlanID = stringValue(run.weekly_plan_id) ??
    progress.weekly_plan_id;
  const savedCards = weeklyPlanID && isUUID(weeklyPlanID)
    ? await host.readSavedDailyCards(
      admin,
      session.workspaceID,
      run.creator_id,
      weeklyPlanID,
    )
    : { dailyCards: [] as GeneratedDailyCard[] };
  if ("response" in savedCards) {
    return savedCards.response;
  }

  const savedCardsForRun = savedDailyCardsForProgress(
    savedCards.dailyCards,
    progress,
  );
  const outputCardsForRun = progress.days.flatMap((day) =>
    day.status === "completed" && day.output
      ? [{
        ...day.output.daily_card,
        id: day.daily_card_id ?? day.output.daily_card.id,
      }]
      : []
  );
  const dailyCards = savedCardsForRun.length > 0
    ? savedCardsForRun
    : outputCardsForRun;
  const mergedProgress = mergeSavedDailyCardsIntoProgress(
    progress,
    savedCardsForRun,
    new Date().toISOString(),
  );
  const summary = weekGenerationStatusSummary(
    mergedProgress,
    stringValue(run.status) ?? "completed",
    (day) => isTerminalDayGenerationState(day, maxDayGenerationAttempts()),
  );
  const strategy = host.makeInitialWeekStrategyOutput(inputSnapshot);
  const responseStatus = summary.overall_status === "completed"
    ? "draft"
    : summary.overall_status;
  return jsonResponse({
    generation_id: generationID,
    weekly_plan_id: weeklyPlanID ?? null,
    status: responseStatus,
    strategy_summary: progress.strategy_summary ?? strategy.strategy_summary,
    warnings: progress.warnings ?? [],
    assumptions: progress.assumptions ?? [],
    daily_cards: dailyCards,
    idea_bank: [],
    source_summary: progress.source_summary ?? strategy.source_summary,
    generated_at: stringValue(run.completed_at) ?? progress.updated_at,
    error: summary.overall_status === "failed"
      ? stringValue(run.error_code) ?? "invalid_generated_week"
      : undefined,
    ...summary,
    failed_days: summary.day_statuses.filter((day) => day.status === "failed"),
    poll_after_seconds: null,
  });
}

async function readParallelGenerationStatus(
  admin: SupabaseAdminClient,
  generationID: string,
  run: GenerationRunStatusRecord,
  session: VerifiedDeviceSession,
  inputSnapshot: GenerationInputSnapshot,
  progress: PerDayGenerationSnapshot,
  env: EnvReader,
  host: GenerationStatusHandlerHost,
  options: { readOnly?: boolean } = {},
): Promise<Response> {
  const readOnly = options.readOnly ?? false;
  const weeklyPlanID = stringValue(run.weekly_plan_id) ??
    progress.weekly_plan_id;
  if (!weeklyPlanID || !isUUID(weeklyPlanID)) {
    return jsonResponse({
      generation_id: generationID,
      status: "failed",
      error: "weekly_plan_not_found",
    }, 404);
  }

  if (isGenerationRunRecordCancelled(run)) {
    const summary = weekGenerationStatusSummary(
      progress,
      "cancelled",
      (day) => isTerminalDayGenerationState(day, maxDayGenerationAttempts()),
    );
    return jsonResponse({
      generation_id: generationID,
      weekly_plan_id: weeklyPlanID,
      status: "cancelled",
      message: "generation_cancelled",
      ...summary,
      poll_after_seconds: null,
    });
  }

  if (!readOnly && stringValue(run.status) === "running") {
    const dayJobsResult = await readQueuedDayJobsForRun(
      admin,
      generationID,
      session.workspaceID,
      run.creator_id,
    );
    let dayJobHeartbeats: Map<number, string | undefined> = new Map();
    if (!("response" in dayJobsResult)) {
      for (const job of dayJobsResult.jobs) {
        if (job.heartbeat_at) {
          dayJobHeartbeats.set(job.day_index, job.heartbeat_at);
        }
      }
    }
    const normalizedProgress = normalizeStaleRunningDays(progress, {
      maxAttempts: maxDayGenerationAttempts(),
      staleThresholdMS: runningDayStaleMS(),
      nowMS: Date.now(),
      nowISO: new Date().toISOString(),
      dayJobHeartbeats,
    });
    if (normalizedProgress !== progress) {
      const updateResult = await host.updateGenerationProgress(
        admin,
        generationID,
        normalizedProgress,
      );
      if ("response" in updateResult) {
        return updateResult.response;
      }
      progress = normalizedProgress;
    }
  }

  const savedCards = await host.readSavedDailyCards(
    admin,
    session.workspaceID,
    run.creator_id,
    weeklyPlanID,
  );
  if ("response" in savedCards) {
    return savedCards.response;
  }

  const savedCardsForRun = savedDailyCardsForProgress(
    savedCards.dailyCards,
    progress,
  );
  const mergedProgress = mergeSavedDailyCardsIntoProgress(
    progress,
    savedCardsForRun,
    new Date().toISOString(),
  );
  if (mergedProgress !== progress) {
    if (readOnly) {
      progress = mergedProgress;
    } else {
      const updateResult = await host.updateGenerationProgress(
        admin,
        generationID,
        mergedProgress,
      );
      if ("response" in updateResult) {
        return updateResult.response;
      }
      progress = mergedProgress;
    }
  }

  if (
    !readOnly &&
    stringValue(run.status) === "running" &&
    isParallelWeekGenerationTerminal(progress, maxDayGenerationAttempts())
  ) {
    const preparedResult = host.prepareGenerationFromRun(
      env,
      run,
      session,
      inputSnapshot,
    );
    if ("response" in preparedResult) {
      return preparedResult.response;
    }
    const finalized = await finalizeParallelWeekGeneration(
      admin,
      preparedResult.prepared,
      generationID,
      weeklyPlanID,
      progress,
      host.parallelWeekWorkerHost,
    );
    if ("response" in finalized) {
      return finalized.response;
    }
    return jsonResponse(finalized.payload);
  }

  if (
    !readOnly &&
    stringValue(run.status) === "running" &&
    shouldResumeParallelWeekGeneration(
      progress,
      parallelWeekGenerationConcurrency(),
      maxDayGenerationAttempts(),
      runningDayStaleMS(),
      Date.now(),
    )
  ) {
    const preparedResult = host.prepareGenerationFromRun(
      env,
      run,
      session,
      inputSnapshot,
    );
    if ("response" in preparedResult) {
      return preparedResult.response;
    }
    const jobsResult = await createSeededDayJobsFromProgress(
      admin,
      preparedResult.prepared,
      generationID,
      weeklyPlanID,
      progress,
    );
    if ("response" in jobsResult) {
      return jobsResult.response;
    }
    host.runParallelWeekGenerationInBackground(
      admin,
      preparedResult.prepared,
      generationID,
      weeklyPlanID,
      progress,
    );
  }

  const summary = weekGenerationStatusSummary(
    progress,
    stringValue(run.status) ?? "running",
    (day) => isTerminalDayGenerationState(day, maxDayGenerationAttempts()),
  );
  const responseStatus = summary.overall_status === "completed"
    ? "draft"
    : summary.overall_status;
  return jsonResponse({
    generation_id: generationID,
    weekly_plan_id: weeklyPlanID,
    status: responseStatus,
    strategy_summary: progress.strategy_summary ??
      host.makeInitialWeekStrategyOutput(inputSnapshot).strategy_summary,
    warnings: progress.warnings ?? [],
    assumptions: progress.assumptions ?? [],
    daily_cards: savedCardsForRun,
    idea_bank: [],
    source_summary: progress.source_summary ??
      host.makeInitialWeekStrategyOutput(inputSnapshot).source_summary,
    generated_at: stringValue(run.completed_at) ?? progress.updated_at,
    error: summary.overall_status === "failed"
      ? stringValue(run.error_code) ?? "invalid_generated_week"
      : undefined,
    ...summary,
    poll_after_seconds: summary.overall_status === "running" ? 5 : null,
  });
}
