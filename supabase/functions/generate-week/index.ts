import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  corsHeaders,
  jsonResponse,
  SupabaseAdminClient,
  VerifiedDeviceSession,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";
import {
  AIGenerationAttemptLog,
  AIGenerationInstrumentation,
  AIGenerationPhase,
  AIProviderConfig,
  callAIProviders,
  callAIProvidersForDay,
  callAIProvidersForSplitWeek,
  combineGeneratedDayOutputs,
  GenerateDayRequest,
  GeneratedDailyCard,
  GeneratedDayOutput,
  GeneratedWeekOutput,
  GenerateWeekRequest,
  GenerateWeekValidationError,
  GenerationInputSnapshot,
  isUUID,
  makeMockGeneratedWeek,
  normalizeGenerateDayRequest,
  normalizeGenerateWeekRequest,
  normalizeRegenerateDayRequest,
  preserveManualDailyCardEdits,
  RegenerateDayRequest,
  validateGeneratedDayOutput,
  validateGeneratedWeek,
  weekDates,
  weekStartDateForDate,
} from "./generation.ts";
import {
  initialParallelWeekGenerationSnapshot,
  initialPerDayGenerationSnapshot,
  queuedDayJobStatusResponse,
  queuedDayJobStatusSummary,
  weekGenerationStatusSummary,
} from "./generation-status.ts";
import {
  initialSingleDayGenerationSnapshot,
  makeGeneratedWeekOutputFromCompletedDays,
  normalizeStoredInputSnapshot,
  requestFromRun,
  uniqueNonBlankStrings,
} from "./generation-run-snapshot.ts";
import type {
  GenerateWeekDraftResponse,
  GenerationRunStatusRecord,
  RegenerateDayDraftResponse,
  SingleDayGenerationSnapshot,
} from "./generation-run-snapshot.ts";
import type {
  DayGenerationState,
  PerDayGenerationSnapshot,
  QueuedDayJobRecord,
  QueuedDayJobStatus,
} from "./generation-status.ts";
import {
  cancelActiveQueuedDayJobs,
  lookupQueuedDayJobsExist,
  markFailedDayJobRetrying,
  readQueuedDayJobsForRun,
} from "./generation-day-job-store.ts";
import {
  clearExistingDraftDailyCardsForFullGeneration,
  findLatestDraftDayPlanContainer,
  generatedDailyCardValues,
  generationPersistFailure,
  insertGeneratedIdeas,
  insertThinDraftDayPlanContainer,
  replaceDailyCardReferences,
  updateExistingDraftDailyCard,
  upsertDraftWeeklyPlan,
  upsertGeneratedDailyCards,
} from "./generation-persistence.ts";
import {
  completeDayGenerationRun as completeDayGenerationRunStore,
  completeFullWeekGenerationRun,
  completeGenerationRunMinimal,
  insertDayGenerationRun,
  insertWeekGenerationRun,
  linkGenerationRunWeeklyPlan,
  markGenerationRunCancelled,
  markGenerationRunFailed as markGenerationRunFailedStore,
  readGenerationRunCancellationState,
  readGenerationRunStatus,
  readQueuedActionGenerationRun,
  updateGenerationRunProgress,
} from "./generation-run-store.ts";
import {
  allDaysCompleted,
  allDaysTerminal,
  isParallelWeekGenerationTerminal,
  isRunningDayStale,
  isTerminalDayGenerationState,
  mergeSavedDailyCardsIntoProgress,
  normalizeStaleRunningDays,
  savedDailyCardsForProgress,
  shouldResumeParallelWeekGeneration,
  shouldRunDayGeneration,
  staleDayFailure,
} from "./generation-day-progress.ts";
import {
  readCreatorRow,
  readDailyCardsForPlan,
  readDayGenerationPlanRow,
  readGenerationContextRows,
  readLatestWeeklySetupForWeek,
  readPublishedWeekRow,
  readWeeklySetupByID,
} from "./generation-context-store.ts";
import {
  availableParallelDayJobSlots as availableParallelDayJobSlotsFromWorker,
  completePartialGenerationRun,
  createQueuedDayJobs,
  isGenerationRunCancelled,
  isGenerationRunRecordCancelled,
  maxDayGenerationAttempts,
  parallelWeekGenerationConcurrency,
  type ParallelWeekWorkerHost,
  runningDayStaleMS,
  runParallelWeekGeneration,
} from "./generation-parallel-week-worker.ts";
import {
  type EnvReader,
  type GenerationStatusHandlerHost,
  readGenerationStatus,
  type StatusHandlerPreparedDayGeneration,
} from "./generation-status-handler.ts";

type GenerateWeekDependencies = {
  env?: EnvReader;
  createAdminClient?: (
    supabaseURL: string,
    serviceRoleKey: string,
  ) => SupabaseAdminClient;
  generateAI?: (
    input: GenerationInputSnapshot,
    providers: AIProviderConfig[],
    instrumentation?: AIGenerationInstrumentation,
  ) => Promise<GeneratedWeekOutput>;
  generateDayAI?: (
    input: GenerationInputSnapshot,
    providers: AIProviderConfig[],
    scheduledDate: string,
    dayIndex: number,
    instrumentation?: AIGenerationInstrumentation,
  ) => Promise<GeneratedDayOutput>;
  runInBackground?: (promise: Promise<void>) => void;
  dayHeartbeatIntervalMS?: number;
};

type RunRecord = {
  id: string;
};

type PreparedGeneration = {
  request: GenerateWeekRequest;
  session: VerifiedDeviceSession;
  weeklySetup: Record<string, unknown> | null;
  inputSnapshot: GenerationInputSnapshot;
  providers: AIProviderConfig[];
  model: string;
  mockEnabled: boolean;
};

function generationAIInstrumentation(
  generationID: string,
  phase: AIGenerationPhase,
  generationScope: "week" | "day",
): AIGenerationInstrumentation {
  return {
    generationID,
    generationScope,
    phase,
    logger: logAIGenerationAttempt,
  };
}

function logAIGenerationAttempt(log: AIGenerationAttemptLog): void {
  console.log(JSON.stringify(log));
}

type GenerationLifecycleLog = {
  action: "generate_week" | "generate_day" | "regenerate_day" | "retry_day";
  phase:
    | "request_accepted"
    | "generation_started"
    | "generation_completed"
    | "generation_failed"
    | "day_job_queued"
    | "day_job_retrying";
  status: "running" | "completed" | "failed" | "queued" | "retrying";
  generation_id: string | null;
  weekly_plan_id: string | null;
  week_start_date: string | null;
  scheduled_date: string | null;
  day_index: number | null;
  duration_ms: number | null;
  day_guidance_present: boolean | null;
  day_guidance_chars: number | null;
};

function logGenerationLifecycle(log: GenerationLifecycleLog): void {
  console.log(JSON.stringify({
    event: "generation_lifecycle",
    timestamp: new Date().toISOString(),
    ...log,
  }));
}

type PlanRecord = {
  id: string;
  status?: string;
  is_soft_locked?: boolean;
  week_start_date?: string;
  weekly_setup_id?: string | null;
};

type CardIdentityRecord = {
  id: string;
  scheduled_date: string;
} & Record<string, unknown>;

type SavedDailyCard = GeneratedDailyCard & {
  updated_at?: string;
  storyboard_thumbnail_assets?: Record<string, unknown>[];
};

type PreparedDayGeneration = {
  request: RegenerateDayRequest;
  session: VerifiedDeviceSession;
  plan: PlanRecord;
  targetCard?: CardIdentityRecord;
  inputSnapshot: GenerationInputSnapshot;
  providers: AIProviderConfig[];
  model: string;
  mockEnabled: boolean;
};

type CreatorRecord = Record<string, unknown> & {
  id: string;
  display_name?: string;
};

const DEFAULT_DEEPSEEK_MODEL = "deepseek-v4-pro";
const DEFAULT_OPENAI_MODEL = "gpt-4.1-mini";
const PROMPT_VERSION = "creator-weekly-generation-v1";

let todayISOProvider: () => string = () =>
  new Date().toISOString().slice(0, 10);

export function availableParallelDayJobSlots(
  jobs: Parameters<typeof availableParallelDayJobSlotsFromWorker>[0],
  concurrency: number,
  staleThresholdMS: number,
  now?: number,
): number {
  return availableParallelDayJobSlotsFromWorker(
    jobs,
    concurrency,
    staleThresholdMS,
    now,
  );
}

export function overrideTodayISO(provider: () => string): void {
  todayISOProvider = provider;
}

function isDateBeforeToday(dateStr: string): boolean {
  return dateStr < todayISOProvider();
}

function pastDateNotAllowedResponse(): Response {
  return jsonResponse({ error: "past_generation_date_not_allowed" }, 400);
}

export async function handleGenerateWeekRequest(
  request: Request,
  dependencies: GenerateWeekDependencies = {},
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const env = dependencies.env ?? Deno.env;
  const supabaseURL = env.get("SUPABASE_URL");
  const serviceRoleKey = env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseURL || !serviceRoleKey) {
    return jsonResponse({ error: "missing_function_secrets" }, 500);
  }

  const admin = dependencies.createAdminClient
    ? dependencies.createAdminClient(supabaseURL, serviceRoleKey)
    : createClient(supabaseURL, serviceRoleKey, {
      auth: { persistSession: false },
    });

  const authResult = await verifyDeviceSession(request, admin, [
    "owner",
    "editor",
  ]);
  if ("response" in authResult) {
    return authResult.response;
  }

  let rawBody: unknown;
  try {
    rawBody = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_generation_payload" }, 400);
  }

  const { session } = authResult;
  if (isStatusAction(rawBody)) {
    return await readGenerationStatus(
      admin,
      session,
      rawBody,
      env,
      buildGenerationStatusHandlerHost(dependencies),
    );
  }

  if (isRetryDayAction(rawBody)) {
    return await retryQueuedDayGeneration(admin, session, rawBody);
  }

  if (isCancelGenerationAction(rawBody)) {
    return await cancelGeneration(admin, session, rawBody);
  }

  if (isGenerateDayAction(rawBody)) {
    return await handleGenerateDayRequest(
      admin,
      env,
      rawBody,
      session,
      dependencies,
    );
  }

  if (isRegenerateDayAction(rawBody)) {
    return await handleRegenerateDayRequest(
      admin,
      env,
      rawBody,
      session,
      dependencies,
    );
  }

  const preparedResult = await prepareGeneration(
    admin,
    env,
    rawBody,
    session,
  );
  if ("response" in preparedResult) {
    return preparedResult.response;
  }

  const { prepared } = preparedResult;
  const runResult = await createGenerationRun(
    admin,
    session.workspaceID,
    prepared.request,
    session.memberID,
    prepared.model,
    prepared.inputSnapshot,
  );
  if ("response" in runResult) {
    return runResult.response;
  }

  logGenerationLifecycle({
    action: "generate_week",
    phase: "request_accepted",
    status: "running",
    generation_id: runResult.run.id,
    weekly_plan_id: null,
    week_start_date: prepared.request.week_start_date,
    scheduled_date: null,
    day_index: null,
    duration_ms: null,
    day_guidance_present: null,
    day_guidance_chars: null,
  });

  if (isQueuedWeekGenerationEnabled(rawBody, env)) {
    return await handleQueuedWeekGeneration(
      admin,
      prepared,
      runResult.run.id,
    );
  }

  if (isParallelWeekGenerationEnabled(rawBody, env)) {
    return await handleParallelWeekGeneration(
      admin,
      prepared,
      runResult.run.id,
      dependencies,
    );
  }

  if (prepared.request.response_mode === "async") {
    const progress = initialPerDayGenerationSnapshot(
      prepared.request.week_start_date,
    );
    const progressResult = await updateGenerationProgress(
      admin,
      runResult.run.id,
      progress,
    );
    if ("response" in progressResult) {
      return progressResult.response;
    }

    const scheduledResult = await scheduleNextPendingDayGeneration(
      admin,
      runResult.run.id,
      prepared,
      progress,
      dependencies,
    );
    if ("response" in scheduledResult) {
      return scheduledResult.response;
    }

    const summary = weekGenerationStatusSummary(
      scheduledResult.progress,
      "running",
      (day) => isTerminalDayGenerationState(day, maxDayGenerationAttempts()),
    );
    return jsonResponse({
      generation_id: runResult.run.id,
      weekly_plan_id: null,
      status: "running",
      message: "generation_started",
      ...summary,
      poll_after_seconds: 5,
    }, 202);
  }

  const pipelinePromise = runGenerationPipeline(
    admin,
    prepared,
    runResult.run.id,
    dependencies,
  );
  const pipelineResult = await pipelinePromise;
  if ("response" in pipelineResult) {
    return pipelineResult.response;
  }

  return jsonResponse(pipelineResult.payload);
}

function isRegenerateDayAction(body: unknown): body is Record<string, unknown> {
  return isRecord(body) && body.action === "regenerate_day";
}

function isGenerateDayAction(body: unknown): body is Record<string, unknown> {
  return isRecord(body) && body.action === "generate_day";
}

async function handleRegenerateDayRequest(
  admin: SupabaseAdminClient,
  env: EnvReader,
  rawBody: unknown,
  session: VerifiedDeviceSession,
  dependencies: GenerateWeekDependencies,
): Promise<Response> {
  const preparedResult = await prepareDayGeneration(
    admin,
    env,
    rawBody,
    session,
  );
  if ("response" in preparedResult) {
    return preparedResult.response;
  }

  return await startPreparedDayGeneration(
    admin,
    preparedResult.prepared,
    session,
    dependencies,
    "regenerate_day",
  );
}

/**
 * Day-at-a-time generation: the caller supplies a target date and a
 * free-text brief for that day. The server finds or creates a thin draft
 * weekly plan container for the containing week, then runs the existing
 * single-day generation pipeline. The day brief is the only brief sent to
 * the AI provider: it replaces any stored weekly setup in the prompt input
 * so the generated card anchors to what the user asked for that day
 * (including one-off asks like brand deliverables).
 */
async function handleGenerateDayRequest(
  admin: SupabaseAdminClient,
  env: EnvReader,
  rawBody: unknown,
  session: VerifiedDeviceSession,
  dependencies: GenerateWeekDependencies,
): Promise<Response> {
  let request: GenerateDayRequest;
  try {
    request = normalizeGenerateDayRequest(rawBody);
  } catch (error) {
    return jsonResponse({
      error: error instanceof GenerateWeekValidationError
        ? error.code
        : "invalid_generation_payload",
    }, 400);
  }

  if (isDateBeforeToday(request.scheduled_date)) {
    return pastDateNotAllowedResponse();
  }

  const creatorResult = await readCreator(
    admin,
    session.workspaceID,
    request.creator_id,
  );
  if ("response" in creatorResult) {
    return creatorResult.response;
  }

  const containerResult = await ensureDayPlanContainer(
    admin,
    session,
    request,
  );
  if ("response" in containerResult) {
    return containerResult.response;
  }

  const regenerateBody: Record<string, unknown> = {
    action: "regenerate_day",
    creator_id: request.creator_id,
    weekly_plan_id: containerResult.weeklyPlanID,
    scheduled_date: request.scheduled_date,
    preserve_manual_edits: false,
    mock: request.mock,
    response_mode: request.response_mode,
    day_guidance: request.day_brief,
  };

  const preparedResult = await prepareDayGeneration(
    admin,
    env,
    regenerateBody,
    session,
  );
  if ("response" in preparedResult) {
    return preparedResult.response;
  }

  // Per-day brief only: replace any stored weekly setup so the day brief is
  // the single brief the prompt and validators anchor to.
  const prepared: PreparedDayGeneration = {
    ...preparedResult.prepared,
    inputSnapshot: {
      ...preparedResult.prepared.inputSnapshot,
      weekly_setup: { notes: request.day_brief },
      day_guidance: request.day_brief,
    },
  };

  return await startPreparedDayGeneration(
    admin,
    prepared,
    session,
    dependencies,
    "generate_day",
  );
}

/**
 * Find the latest draft weekly plan covering the requested date, or create a
 * thin draft container so a single day can be generated without a full-week
 * generation run.
 */
async function ensureDayPlanContainer(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  request: GenerateDayRequest,
): Promise<{ weeklyPlanID: string } | { response: Response }> {
  const weekStartDate = weekStartDateForDate(request.scheduled_date);

  const existingResult = await findLatestDraftDayPlanContainer(
    admin,
    session.workspaceID,
    request.creator_id,
    weekStartDate,
  );
  if (existingResult.error) {
    return generationPersistFailure(
      "day_container_plan_lookup",
      existingResult.error,
    );
  }

  const existing = (existingResult.data?.[0] ?? null) as PlanRecord | null;
  if (existing?.is_soft_locked) {
    return {
      response: jsonResponse({ error: "existing_published_week_locked" }, 409),
    };
  }
  if (existing?.id) {
    return { weeklyPlanID: existing.id };
  }

  const weeklyPlanID = crypto.randomUUID();
  const { data, error } = await insertThinDraftDayPlanContainer(admin, {
    id: weeklyPlanID,
    workspace_id: session.workspaceID,
    creator_id: request.creator_id,
    weekly_setup_id: null,
    creator_profile_id: null,
    week_start_date: weekStartDate,
    status: "draft",
    strategy_summary: "Day-at-a-time container week.",
    warnings: [],
    assumptions: ["Created automatically for single-day generation."],
    is_soft_locked: false,
    created_by_member_id: session.memberID,
  });
  if (error || !data) {
    return generationPersistFailure("day_container_plan_write", error);
  }

  return { weeklyPlanID };
}

async function startPreparedDayGeneration(
  admin: SupabaseAdminClient,
  prepared: PreparedDayGeneration,
  session: VerifiedDeviceSession,
  dependencies: GenerateWeekDependencies,
  action: "generate_day" | "regenerate_day",
): Promise<Response> {
  const runResult = await createDayGenerationRun(
    admin,
    prepared,
    session.memberID,
  );
  if ("response" in runResult) {
    return runResult.response;
  }

  logGenerationLifecycle({
    action,
    phase: "request_accepted",
    status: "running",
    generation_id: runResult.run.id,
    weekly_plan_id: prepared.request.weekly_plan_id,
    week_start_date: prepared.inputSnapshot.week_start_date,
    scheduled_date: prepared.request.scheduled_date,
    day_index: null,
    duration_ms: null,
    day_guidance_present: prepared.request.day_guidance !== undefined,
    day_guidance_chars: prepared.request.day_guidance?.length ?? 0,
  });

  if (prepared.request.response_mode === "async") {
    const progress = initialSingleDayGenerationSnapshot(prepared.request);
    const progressResult = await updateGenerationProgress(
      admin,
      runResult.run.id,
      progress,
    );
    if ("response" in progressResult) {
      return progressResult.response;
    }
    const scheduleResult = await scheduleSingleDayGeneration(
      admin,
      runResult.run.id,
      prepared,
      progress,
      dependencies,
    );
    if ("response" in scheduleResult) {
      return scheduleResult.response;
    }
    return jsonResponse({
      generation_id: runResult.run.id,
      weekly_plan_id: prepared.request.weekly_plan_id,
      status: "running",
      target_scheduled_date: prepared.request.scheduled_date,
      poll_after_seconds: 5,
    }, 202);
  }

  const result = await runDayGenerationPipeline(
    admin,
    runResult.run.id,
    prepared,
    dependencies,
  );
  return "response" in result ? result.response : jsonResponse(result.payload);
}

async function prepareDayGeneration(
  admin: SupabaseAdminClient,
  env: EnvReader,
  rawBody: unknown,
  session: VerifiedDeviceSession,
): Promise<{ prepared: PreparedDayGeneration } | { response: Response }> {
  let request: RegenerateDayRequest;
  try {
    request = normalizeRegenerateDayRequest(rawBody);
  } catch (error) {
    return {
      response: jsonResponse({
        error: error instanceof GenerateWeekValidationError
          ? error.code
          : "invalid_generation_payload",
      }, 400),
    };
  }

  const creatorResult = await readCreator(
    admin,
    session.workspaceID,
    request.creator_id,
  );
  if ("response" in creatorResult) {
    return creatorResult;
  }

  const planResult = await readDayGenerationPlan(
    admin,
    session.workspaceID,
    request,
  );
  if ("response" in planResult) {
    return planResult;
  }
  const plan = planResult.plan;
  if (plan.status === "published" || plan.is_soft_locked) {
    return {
      response: jsonResponse({ error: "existing_published_week_locked" }, 409),
    };
  }
  if (plan.status !== "draft") {
    return {
      response: jsonResponse({ error: "weekly_plan_not_found" }, 409),
    };
  }
  if (
    !plan.week_start_date ||
    !weekDates(plan.week_start_date).includes(request.scheduled_date)
  ) {
    return { response: jsonResponse({ error: "date_not_in_plan" }, 400) };
  }

  const cardsResult = await readPlanCardsForDayGeneration(
    admin,
    session.workspaceID,
    request,
  );
  if ("response" in cardsResult) {
    return cardsResult;
  }
  const targetCard = cardsResult.cards.find((card) =>
    card.scheduled_date === request.scheduled_date
  );
  if (targetCard && targetCard.status !== "draft") {
    return {
      response: jsonResponse({ error: "daily_card_not_found" }, 404),
    };
  }

  const weeklySetupResult = await readWeeklySetup(
    admin,
    session.workspaceID,
    {
      creator_id: request.creator_id,
      week_start_date: plan.week_start_date ?? "",
      weekly_setup_id: plan.weekly_setup_id ?? undefined,
      mode: "regenerate_draft",
      preserve_manual_edits: request.preserve_manual_edits,
      mock: request.mock,
      response_mode: request.response_mode,
    },
  );
  if ("response" in weeklySetupResult) {
    return weeklySetupResult;
  }

  const inputResult = await buildGenerationInput(
    admin,
    session.workspaceID,
    request.creator_id,
    plan.week_start_date ?? "",
    creatorResult.creator,
    weeklySetupResult.setup,
  );
  if ("response" in inputResult) {
    return inputResult;
  }

  let inputSnapshot: GenerationInputSnapshot = {
    ...inputResult.input,
    existing_week_cards: cardsResult.cards,
    day_guidance: request.day_guidance,
  };
  if (
    request.input_overrides &&
    env.get("MCO_ALLOW_AI_INPUT_OVERRIDES") === "1"
  ) {
    inputSnapshot = {
      ...inputSnapshot,
      ...request.input_overrides,
    } as GenerationInputSnapshot;
  }

  const providers = aiProviderConfigs(env);
  const mockEnabled = env.get("MCO_AI_MOCK") === "1" ||
    (request.mock && env.get("MCO_ALLOW_AI_MOCK_REQUEST") === "1");
  if (!mockEnabled && providers.length === 0) {
    return { response: jsonResponse({ error: "missing_openai_api_key" }, 500) };
  }

  return {
    prepared: {
      request,
      session,
      plan,
      targetCard,
      inputSnapshot,
      providers,
      model: providerModelSummary(providers),
      mockEnabled,
    },
  };
}

async function readDayGenerationPlan(
  admin: SupabaseAdminClient,
  workspaceID: string,
  request: RegenerateDayRequest,
): Promise<{ plan: PlanRecord } | { response: Response }> {
  const { data, error } = await readDayGenerationPlanRow(
    admin,
    workspaceID,
    request.creator_id,
    request.weekly_plan_id,
  );
  if (error) {
    return {
      response: jsonResponse({ error: "weekly_plan_lookup_failed" }, 500),
    };
  }
  if (!isRecord(data)) {
    return { response: jsonResponse({ error: "weekly_plan_not_found" }, 404) };
  }
  return { plan: data as PlanRecord };
}

async function readPlanCardsForDayGeneration(
  admin: SupabaseAdminClient,
  workspaceID: string,
  request: RegenerateDayRequest,
): Promise<{ cards: CardIdentityRecord[] } | { response: Response }> {
  const { data, error } = await readDailyCardsForPlan(
    admin,
    workspaceID,
    request.creator_id,
    request.weekly_plan_id,
  );
  if (error) {
    return {
      response: jsonResponse({ error: "daily_card_lookup_failed" }, 500),
    };
  }
  return { cards: data as CardIdentityRecord[] };
}

async function readSavedDailyCards(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  weeklyPlanID: string,
): Promise<{ dailyCards: SavedDailyCard[] } | { response: Response }> {
  const { data, error } = await readDailyCardsForPlan(
    admin,
    workspaceID,
    creatorID,
    weeklyPlanID,
  );
  if (error) {
    return generationPersistFailure("daily_cards_lookup", error);
  }
  return {
    dailyCards: (data as CardIdentityRecord[]).map(
      storedDailyCardToGenerated,
    ),
  };
}

function storedDailyCardToGenerated(
  card: CardIdentityRecord,
): SavedDailyCard {
  const postInstructions = isRecord(card.post_instructions)
    ? card.post_instructions
    : {};
  return {
    id: stringValue(card.id),
    scheduled_date: card.scheduled_date,
    format: contentFormatValue(postInstructions.format),
    primary_surface: stringValue(postInstructions.primary_surface) ?? "",
    duration_seconds: numberValue(postInstructions.duration_seconds) ?? 0,
    title: stringValue(card.title) ?? "",
    hook: stringValue(postInstructions.hook) ?? "",
    weekly_brief_anchor: stringValue(postInstructions.weekly_brief_anchor) ??
      "",
    brief_alignment: stringValue(postInstructions.brief_alignment) ?? "",
    brief_context_tags: stringArray(postInstructions.brief_context_tags),
    why_today: stringValue(card.why_today) ?? "",
    growth_job: stringValue(card.growth_job) ?? "",
    save_share_reason: stringValue(postInstructions.save_share_reason) ?? "",
    content_pillar: stringValue(card.content_pillar) ?? "",
    shootability: stringValue(card.shootability) ?? "",
    estimated_shoot_minutes: numberValue(card.estimated_shoot_minutes) ?? 0,
    energy_required: stringValue(card.energy_required) ?? "",
    language_mode: stringValue(card.language_mode) ?? "",
    scene_list: Array.isArray(card.scene_list)
      ? card.scene_list as GeneratedDailyCard["scene_list"]
      : [],
    shot_timeline: timelineArray(postInstructions.shot_timeline),
    script: stringValue(card.script) ?? "",
    voiceover_timeline: voiceoverTimelineArray(
      postInstructions.voiceover_timeline,
    ),
    no_voiceover_version: stringValue(card.no_voiceover_version) ?? "",
    silent_version_timeline: timelineArray(
      postInstructions.silent_version_timeline,
    ),
    on_screen_text: stringArray(card.on_screen_text),
    on_screen_text_timeline: onScreenTextTimelineArray(
      postInstructions.on_screen_text_timeline,
    ),
    caption: stringValue(card.caption) ?? "",
    cta: stringValue(card.cta) ?? "",
    hashtags: stringArray(card.hashtags),
    cover_text: stringValue(card.cover_text) ?? "",
    post_instructions: stringValue(postInstructions.instructions) ??
      stringValue(card.post_instructions) ?? "",
    brand_event_notes: stringValue(card.brand_event_notes) ?? "",
    backup_story: storedBackupText(card.backup_story),
    backup_story_detail: isRecord(card.backup_story)
      ? timelineArray(card.backup_story.detail)
      : [],
    backup_caption_only: storedBackupText(card.backup_caption_only),
    caption_backup_detail:
      stringValue(postInstructions.caption_backup_detail) ??
        (isRecord(card.backup_caption_only)
          ? stringValue(card.backup_caption_only.detail)
          : undefined) ??
        "",
    audio_option_notes: stringValue(postInstructions.audio_option_notes) ?? "",
    creator_fit_score: numberValue(postInstructions.creator_fit_score) ??
      numberValue(card.creator_fit_score) ?? 0,
    risk_notes: stringArray(card.risk_notes),
    assumptions: stringArray(card.assumptions),
    source_note: stringValue(card.source_note) ?? "",
    source_reference_ids: [],
    storyboard_thumbnail_assets: Array.isArray(card.storyboard_thumbnail_assets)
      ? card.storyboard_thumbnail_assets as Record<string, unknown>[]
      : [],
    updated_at: stringValue(card.updated_at) ?? undefined,
  };
}

function storedBackupText(value: unknown): string {
  if (isRecord(value)) {
    return stringValue(value.line) ?? "";
  }
  return stringValue(value) ?? "";
}

function contentFormatValue(value: unknown): "Reel" | "Post" | "Story" {
  const format = stringValue(value);
  return format === "Post" || format === "Story" ? format : "Reel";
}

function timelineArray(
  value: unknown,
): GeneratedDailyCard["shot_timeline"] {
  return Array.isArray(value)
    ? value as GeneratedDailyCard["shot_timeline"]
    : [];
}

function voiceoverTimelineArray(
  value: unknown,
): GeneratedDailyCard["voiceover_timeline"] {
  return Array.isArray(value)
    ? value as GeneratedDailyCard["voiceover_timeline"]
    : [];
}

function onScreenTextTimelineArray(
  value: unknown,
): GeneratedDailyCard["on_screen_text_timeline"] {
  return Array.isArray(value)
    ? value as GeneratedDailyCard["on_screen_text_timeline"]
    : [];
}

async function prepareGeneration(
  admin: SupabaseAdminClient,
  env: EnvReader,
  rawBody: unknown,
  session: VerifiedDeviceSession,
): Promise<{ prepared: PreparedGeneration } | { response: Response }> {
  let body: GenerateWeekRequest;
  try {
    body = normalizeGenerateWeekRequest(rawBody);
  } catch (error) {
    if (error instanceof GenerateWeekValidationError) {
      return { response: jsonResponse({ error: error.code }, 400) };
    }
    return {
      response: jsonResponse({ error: "invalid_generation_payload" }, 400),
    };
  }

  if (isDateBeforeToday(body.week_start_date)) {
    return { response: pastDateNotAllowedResponse() };
  }

  const creatorResult = await readCreator(
    admin,
    session.workspaceID,
    body.creator_id,
  );
  if ("response" in creatorResult) {
    return creatorResult;
  }

  const publishedLock = await hasPublishedWeek(
    admin,
    session.workspaceID,
    body.creator_id,
    body.week_start_date,
  );
  if ("response" in publishedLock) {
    return publishedLock;
  }
  if (publishedLock.locked) {
    return {
      response: jsonResponse({ error: "existing_published_week_locked" }, 409),
    };
  }

  const weeklySetupResult = await readWeeklySetup(
    admin,
    session.workspaceID,
    body,
  );
  if ("response" in weeklySetupResult) {
    return weeklySetupResult;
  }

  const inputResult = await buildGenerationInput(
    admin,
    session.workspaceID,
    body.creator_id,
    body.week_start_date,
    creatorResult.creator,
    weeklySetupResult.setup,
  );
  if ("response" in inputResult) {
    return inputResult;
  }

  let inputSnapshot = inputResult.input;
  if (
    body.input_overrides &&
    env.get("MCO_ALLOW_AI_INPUT_OVERRIDES") === "1"
  ) {
    inputSnapshot = {
      ...inputSnapshot,
      ...body.input_overrides,
    } as GenerationInputSnapshot;
  }

  const providers = aiProviderConfigs(env);
  const model = providerModelSummary(providers);
  const mockEnabled = env.get("MCO_AI_MOCK") === "1" ||
    (body.mock && env.get("MCO_ALLOW_AI_MOCK_REQUEST") === "1");

  if (!mockEnabled && providers.length === 0) {
    return { response: jsonResponse({ error: "missing_openai_api_key" }, 500) };
  }

  return {
    prepared: {
      request: body,
      session,
      weeklySetup: weeklySetupResult.setup,
      inputSnapshot,
      providers,
      model,
      mockEnabled,
    },
  };
}

async function runGenerationPipeline(
  admin: SupabaseAdminClient,
  prepared: PreparedGeneration,
  generationID: string,
  dependencies: GenerateWeekDependencies,
): Promise<{ payload: GenerateWeekDraftResponse } | { response: Response }> {
  const pipelineStartedAt = Date.now();
  logGenerationLifecycle({
    action: "generate_week",
    phase: "generation_started",
    status: "running",
    generation_id: generationID,
    weekly_plan_id: null,
    week_start_date: prepared.request.week_start_date,
    scheduled_date: null,
    day_index: null,
    duration_ms: null,
    day_guidance_present: null,
    day_guidance_chars: null,
  });

  let generated: GeneratedWeekOutput;
  try {
    const rawOutput = prepared.mockEnabled
      ? makeMockGeneratedWeek(prepared.inputSnapshot)
      : await generateWeekOutputWithFallback(
        prepared,
        generationID,
        dependencies,
      );
    generated = validateGeneratedWeek(
      rawOutput,
      prepared.request.week_start_date,
    );
  } catch (error) {
    const errorCode = stableGenerationError(error);
    await markGenerationRunFailed(admin, generationID, errorCode);
    logGenerationLifecycle({
      action: "generate_week",
      phase: "generation_failed",
      status: "failed",
      generation_id: generationID,
      weekly_plan_id: null,
      week_start_date: prepared.request.week_start_date,
      scheduled_date: null,
      day_index: null,
      duration_ms: Date.now() - pipelineStartedAt,
      day_guidance_present: null,
      day_guidance_chars: null,
    });
    return {
      response: jsonResponse(
        { error: errorCode },
        errorCode === "openai_request_failed" ? 502 : 400,
      ),
    };
  }

  const persistResult = await persistGeneratedWeek(
    admin,
    prepared.session.workspaceID,
    prepared.request,
    prepared.session.memberID,
    prepared.weeklySetup,
    prepared.inputSnapshot,
    generated,
  );
  if ("response" in persistResult) {
    await markGenerationRunFailed(
      admin,
      generationID,
      "generation_persist_failed",
    );
    logGenerationLifecycle({
      action: "generate_week",
      phase: "generation_failed",
      status: "failed",
      generation_id: generationID,
      weekly_plan_id: null,
      week_start_date: prepared.request.week_start_date,
      scheduled_date: null,
      day_index: null,
      duration_ms: Date.now() - pipelineStartedAt,
      day_guidance_present: null,
      day_guidance_chars: null,
    });
    return persistResult;
  }

  const completedAt = new Date().toISOString();
  const payload = makeGenerateWeekDraftResponse(
    generationID,
    persistResult.weeklyPlanID,
    generated,
    persistResult.dailyCards,
    persistResult.ideaBank,
    completedAt,
  );
  const completedRunResult = await completeGenerationRun(
    admin,
    generationID,
    persistResult.weeklyPlanID,
    payload,
    completedAt,
  );
  if ("response" in completedRunResult) {
    await markGenerationRunFailed(
      admin,
      generationID,
      "generation_persist_failed",
    );
    logGenerationLifecycle({
      action: "generate_week",
      phase: "generation_failed",
      status: "failed",
      generation_id: generationID,
      weekly_plan_id: persistResult.weeklyPlanID,
      week_start_date: prepared.request.week_start_date,
      scheduled_date: null,
      day_index: null,
      duration_ms: Date.now() - pipelineStartedAt,
      day_guidance_present: null,
      day_guidance_chars: null,
    });
    return completedRunResult;
  }

  logGenerationLifecycle({
    action: "generate_week",
    phase: "generation_completed",
    status: "completed",
    generation_id: generationID,
    weekly_plan_id: persistResult.weeklyPlanID,
    week_start_date: prepared.request.week_start_date,
    scheduled_date: null,
    day_index: null,
    duration_ms: Date.now() - pipelineStartedAt,
    day_guidance_present: null,
    day_guidance_chars: null,
  });
  return { payload };
}

async function generateWeekOutputWithFallback(
  prepared: PreparedGeneration,
  generationID: string,
  dependencies: GenerateWeekDependencies,
): Promise<GeneratedWeekOutput> {
  if (!dependencies.generateAI) {
    return await generateSplitWeekOutput(prepared, generationID, dependencies);
  }

  try {
    return await dependencies.generateAI(
      prepared.inputSnapshot,
      prepared.providers,
      generationAIInstrumentation(
        generationID,
        "full_week_generation",
        "week",
      ),
    );
  } catch (error) {
    if (!shouldRetryWeekAsSplitGeneration(error)) {
      throw error;
    }
    return await generateSplitWeekOutput(prepared, generationID, dependencies);
  }
}

async function generateSplitWeekOutput(
  prepared: PreparedGeneration,
  generationID: string,
  dependencies: GenerateWeekDependencies,
): Promise<GeneratedWeekOutput> {
  const instrumentation = generationAIInstrumentation(
    generationID,
    "split_week_day_generation",
    "day",
  );
  if (dependencies.generateDayAI) {
    const dayOutputs = await runDayGenerationBatches(
      weekDates(prepared.inputSnapshot.week_start_date),
      (scheduledDate, dayIndex) =>
        dependencies.generateDayAI!(
          prepared.inputSnapshot,
          prepared.providers,
          scheduledDate,
          dayIndex,
          instrumentation,
        ),
    );
    return combineGeneratedDayOutputs(prepared.inputSnapshot, dayOutputs);
  }
  return await callAIProvidersForSplitWeek(
    prepared.inputSnapshot,
    prepared.providers,
    undefined,
    instrumentation,
  );
}

async function runDayGenerationBatches<T>(
  dates: string[],
  generate: (scheduledDate: string, dayIndex: number) => Promise<T>,
): Promise<T[]> {
  const concurrency = parallelWeekGenerationConcurrency();
  const outputs: T[] = [];
  for (let start = 0; start < dates.length; start += concurrency) {
    const batch = dates.slice(start, start + concurrency);
    const batchOutputs = await Promise.all(
      batch.map((scheduledDate, offset) =>
        generate(scheduledDate, start + offset)
      ),
    );
    outputs.push(...batchOutputs);
  }
  return outputs;
}

function shouldRetryWeekAsSplitGeneration(error: unknown): boolean {
  return error instanceof GenerateWeekValidationError &&
    (error.code === "invalid_ai_json" ||
      error.code === "invalid_generated_week");
}

async function persistenceFailureStep(
  response: Response,
): Promise<string | null> {
  return (await persistenceFailureDetail(response)).step;
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

function makeGenerateWeekDraftResponse(
  generationID: string,
  weeklyPlanID: string,
  generated: GeneratedWeekOutput,
  dailyCards: GeneratedDailyCard[],
  ideaBank: Record<string, unknown>[],
  generatedAt: string,
): GenerateWeekDraftResponse {
  return {
    generation_id: generationID,
    weekly_plan_id: weeklyPlanID,
    status: "draft",
    strategy_summary: generated.strategy_summary,
    warnings: generated.warnings,
    assumptions: generated.assumptions,
    daily_cards: dailyCards,
    idea_bank: ideaBank,
    source_summary: generated.source_summary,
    generated_at: generatedAt,
  };
}

function isParallelWeekGenerationEnabled(
  rawBody: unknown,
  env: EnvReader,
): boolean {
  if (env.get("MCO_PARALLEL_WEEK_GENERATION") === "1") {
    return true;
  }
  if (!isRecord(rawBody)) {
    return false;
  }
  const flags = rawBody.feature_flags;
  if (Array.isArray(flags)) {
    return flags.includes("parallel_week_generation");
  }
  if (isRecord(flags)) {
    return flags.parallel_week_generation === true;
  }
  return false;
}

function isQueuedWeekGenerationEnabled(
  rawBody: unknown,
  env: EnvReader,
): boolean {
  if (env.get("MCO_QUEUED_WEEK_GENERATION") === "1") {
    return true;
  }
  if (!isRecord(rawBody)) {
    return false;
  }
  const flags = rawBody.feature_flags;
  if (Array.isArray(flags)) {
    return flags.includes("queued_week_generation");
  }
  if (isRecord(flags)) {
    return flags.queued_week_generation === true;
  }
  return false;
}

function buildParallelWeekWorkerHost(
  dependencies: GenerateWeekDependencies,
): ParallelWeekWorkerHost {
  return {
    generateDayOutput: (
      prepared,
      scheduledDate,
      dayIndex,
      generationID,
      retryContext,
    ) =>
      generateDayOutput(
        prepared,
        scheduledDate,
        dayIndex,
        dependencies,
        generationID,
        "parallel_day_generation",
        retryContext,
      ),
    assertDayRespectsWeeklyBriefContext,
    dayGenerationRetryContext,
    readSavedDailyCards,
    makeInitialWeekStrategyOutput,
    makeGenerateWeekDraftResponse,
    completeGenerationRun,
    dayHeartbeatIntervalMS: dependencies.dayHeartbeatIntervalMS,
  };
}

function buildGenerationStatusHandlerHost(
  dependencies: GenerateWeekDependencies,
): GenerationStatusHandlerHost {
  return {
    prepareGenerationFromRun,
    prepareSingleDayGenerationFromRun,
    markGenerationRunFailed,
    updateGenerationProgress,
    scheduleNextPendingDayGeneration: (
      admin,
      generationID,
      prepared,
      progress,
    ) =>
      scheduleNextPendingDayGeneration(
        admin,
        generationID,
        prepared,
        progress,
        dependencies,
      ),
    finalizePerDayGeneration,
    finalizeTerminalPerDayGeneration,
    readSavedDailyCards,
    scheduleSingleDayGeneration: (
      admin,
      generationID,
      prepared,
      progress,
    ) =>
      scheduleSingleDayGeneration(
        admin,
        generationID,
        prepared as PreparedDayGeneration,
        progress,
        dependencies,
      ),
    runParallelWeekGenerationInBackground: (
      admin,
      prepared,
      generationID,
      weeklyPlanID,
      progress,
    ) => {
      scheduleBackgroundGeneration(
        runParallelWeekGeneration(
          admin,
          prepared,
          generationID,
          weeklyPlanID,
          progress,
          buildParallelWeekWorkerHost(dependencies),
        ),
        dependencies,
      );
    },
    parallelWeekWorkerHost: buildParallelWeekWorkerHost(dependencies),
    makeInitialWeekStrategyOutput,
  };
}
async function handleQueuedWeekGeneration(
  admin: SupabaseAdminClient,
  prepared: PreparedGeneration,
  generationID: string,
): Promise<Response> {
  const strategy = makeInitialWeekStrategyOutput(prepared.inputSnapshot);
  const planResult = await upsertDraftWeeklyPlan(
    admin,
    prepared.session.workspaceID,
    prepared.request,
    prepared.session.memberID,
    prepared.weeklySetup,
    prepared.inputSnapshot,
    strategy,
  );
  if ("response" in planResult) {
    await markGenerationRunFailed(
      admin,
      generationID,
      "generation_persist_failed",
    );
    return planResult.response;
  }

  const linkResult = await updateGenerationRunWeeklyPlan(
    admin,
    generationID,
    planResult.weeklyPlanID,
  );
  if ("response" in linkResult) {
    await markGenerationRunFailed(
      admin,
      generationID,
      "generation_persist_failed",
    );
    return linkResult.response;
  }

  const clearResult = await clearExistingDraftDailyCardsForFullGeneration(
    admin,
    prepared.session.workspaceID,
    prepared.request.creator_id,
    planResult.weeklyPlanID,
  );
  if ("response" in clearResult) {
    await markGenerationRunFailed(
      admin,
      generationID,
      "generation_persist_failed",
    );
    return clearResult.response;
  }

  const progress = initialParallelWeekGenerationSnapshot(
    prepared.request.week_start_date,
    planResult.weeklyPlanID,
    strategy,
  );
  const progressResult = await updateGenerationProgress(
    admin,
    generationID,
    progress,
  );
  if ("response" in progressResult) {
    await markGenerationRunFailed(
      admin,
      generationID,
      "generation_persist_failed",
    );
    return progressResult.response;
  }

  const jobsResult = await createQueuedDayJobs(
    admin,
    prepared,
    generationID,
    planResult.weeklyPlanID,
  );
  if ("response" in jobsResult) {
    await markGenerationRunFailed(
      admin,
      generationID,
      "generation_persist_failed",
    );
    return jobsResult.response;
  }

  const summary = queuedDayJobStatusSummary(jobsResult.jobs);
  return jsonResponse({
    generation_id: generationID,
    weekly_plan_id: planResult.weeklyPlanID,
    status: "running",
    message: "generation_queued",
    ...summary,
    days: summary.day_statuses,
    poll_after_seconds: 5,
  }, 202);
}

async function handleParallelWeekGeneration(
  admin: SupabaseAdminClient,
  prepared: PreparedGeneration,
  generationID: string,
  dependencies: GenerateWeekDependencies,
): Promise<Response> {
  const strategy = makeInitialWeekStrategyOutput(prepared.inputSnapshot);
  const planResult = await upsertDraftWeeklyPlan(
    admin,
    prepared.session.workspaceID,
    prepared.request,
    prepared.session.memberID,
    prepared.weeklySetup,
    prepared.inputSnapshot,
    strategy,
  );
  if ("response" in planResult) {
    await markGenerationRunFailed(
      admin,
      generationID,
      "generation_persist_failed",
    );
    return planResult.response;
  }

  const linkResult = await updateGenerationRunWeeklyPlan(
    admin,
    generationID,
    planResult.weeklyPlanID,
  );
  if ("response" in linkResult) {
    await markGenerationRunFailed(
      admin,
      generationID,
      "generation_persist_failed",
    );
    return linkResult.response;
  }

  const clearResult = await clearExistingDraftDailyCardsForFullGeneration(
    admin,
    prepared.session.workspaceID,
    prepared.request.creator_id,
    planResult.weeklyPlanID,
  );
  if ("response" in clearResult) {
    await markGenerationRunFailed(
      admin,
      generationID,
      "generation_persist_failed",
    );
    return clearResult.response;
  }

  const progress = initialParallelWeekGenerationSnapshot(
    prepared.request.week_start_date,
    planResult.weeklyPlanID,
    strategy,
  );
  const progressResult = await updateGenerationProgress(
    admin,
    generationID,
    progress,
  );
  if ("response" in progressResult) {
    await markGenerationRunFailed(
      admin,
      generationID,
      "generation_persist_failed",
    );
    return progressResult.response;
  }

  const jobsResult = await createQueuedDayJobs(
    admin,
    prepared,
    generationID,
    planResult.weeklyPlanID,
  );
  if ("response" in jobsResult) {
    await markGenerationRunFailed(
      admin,
      generationID,
      "generation_persist_failed",
    );
    return jobsResult.response;
  }

  const runPromise = runParallelWeekGeneration(
    admin,
    prepared,
    generationID,
    planResult.weeklyPlanID,
    progress,
    buildParallelWeekWorkerHost(dependencies),
  );

  if (prepared.request.response_mode === "async") {
    scheduleBackgroundGeneration(runPromise, dependencies);
    return jsonResponse({
      generation_id: generationID,
      weekly_plan_id: planResult.weeklyPlanID,
      status: "running",
      message: "generation_started",
      ...weekGenerationStatusSummary(
        progress,
        "running",
        (day) => isTerminalDayGenerationState(day, maxDayGenerationAttempts()),
      ),
      poll_after_seconds: 5,
    }, 202);
  }

  const result = await runPromise;
  return "response" in result ? result.response : jsonResponse(result.payload);
}

function assertDayRespectsWeeklyBriefContext(
  inputSnapshot: GenerationInputSnapshot,
  card: GeneratedDailyCard,
): void {
  const weeklyBrief = weeklyBriefText(inputSnapshot).toLowerCase();
  const generatedText = [
    card.title,
    card.why_today,
    card.growth_job,
    card.script,
    card.caption,
    card.cover_text,
    card.backup_story,
    card.backup_caption_only,
    card.post_instructions,
    card.brand_event_notes,
    card.audio_option_notes,
    card.source_note,
    ...card.on_screen_text,
    ...card.risk_notes,
    ...card.assumptions,
    ...card.scene_list.map((scene) => scene.title),
  ].join(" ").toLowerCase();

  const briefSaysBombay = /\b(bombay|mumbai)\b/.test(weeklyBrief);
  if (briefSaysBombay && /\b(new jersey|nj)\b/.test(generatedText)) {
    throw new GenerateWeekValidationError(
      "invalid_generated_week",
      "Generated day used stale location context.",
    );
  }

  const briefSaysGymReturn =
    /\b(back to gym|back in the gym|gym routine|gym reset|restarting (?:her )?gym|regular life)\b/
      .test(weeklyBrief);
  if (
    briefSaysGymReturn &&
    /\b(hyrox|post-race|post race|race recovery|race week|big race)\b/.test(
      generatedText,
    )
  ) {
    throw new GenerateWeekValidationError(
      "invalid_generated_week",
      "Generated day used stale race-recovery context.",
    );
  }
}

function weeklyBriefText(inputSnapshot: GenerationInputSnapshot): string {
  const setup = inputSnapshot.weekly_setup;
  if (!isRecord(setup)) {
    return "";
  }
  return [
    stringValue(setup.notes),
    stringValue(setup.location),
    stringValue(setup.workout_race_schedule),
    stringValue(setup.family_travel_moments),
    stringValue(setup.energy_constraints),
    stringValue(setup.shooting_constraints),
    stringValue(setup.no_go_topics),
  ].filter((value): value is string => Boolean(value)).join("\n");
}

function makeInitialWeekStrategyOutput(
  inputSnapshot: GenerationInputSnapshot,
): GeneratedWeekOutput {
  const setup = inputSnapshot.weekly_setup ?? {};
  const profile = inputSnapshot.creator_profile ?? {};
  const note = stringValue(setup.notes);
  const positioning = stringValue(profile.positioning);
  const location = stringValue(setup.location);
  const currentLocation = shouldUseStoredWeeklyLocation(note, location)
    ? location
    : undefined;
  const parts = [
    note ? `Weekly brief: ${note}` : null,
    positioning ? `Creator profile: ${positioning}` : null,
    currentLocation ? `Location/context: ${currentLocation}` : null,
    inputSnapshot.brand_briefs.length > 0
      ? `${inputSnapshot.brand_briefs.length} brand context item(s) available.`
      : null,
    inputSnapshot.key_moments.length > 0
      ? `${inputSnapshot.key_moments.length} key moment(s) in or near this week.`
      : null,
  ].filter((part): part is string => Boolean(part));
  return {
    strategy_summary: parts.length > 0
      ? parts.join("\n")
      : "Use the creator profile, weekly brief, references, and recent archive to create a coherent seven-day draft week.",
    warnings: [],
    assumptions: [
      "Generated with per-day persistence so completed days can be reviewed even if another day fails.",
    ],
    daily_cards: [],
    idea_bank: [],
    source_summary:
      "Creator profile, weekly setup, confirmed references, recent archive, idea bank, patterns, trends, audio options, brand briefs, and key moments.",
  };
}

function shouldUseStoredWeeklyLocation(
  weeklyBrief: string | undefined,
  storedLocation: string | undefined,
): boolean {
  if (!storedLocation) {
    return false;
  }
  if (!weeklyBrief) {
    return true;
  }

  const brief = weeklyBrief.toLowerCase();
  const location = storedLocation.toLowerCase();
  const knownLocations = [
    "bombay",
    "mumbai",
    "new jersey",
    "nj",
    "delhi",
    "london",
    "dubai",
    "singapore",
  ];
  const briefLocations = knownLocations.filter((candidate) =>
    brief.includes(candidate)
  );
  if (briefLocations.length === 0) {
    return true;
  }

  return briefLocations.some((candidate) => location.includes(candidate));
}

function scheduleBackgroundGeneration(
  promise: Promise<unknown>,
  dependencies: GenerateWeekDependencies,
): void {
  const guarded = promise.then(() => undefined).catch((error) => {
    console.error(
      "generate-week background task failed",
      error instanceof Error ? error.message : "unknown_error",
    );
  });

  if (dependencies.runInBackground) {
    dependencies.runInBackground(guarded);
    return;
  }

  const edgeRuntime = (globalThis as typeof globalThis & {
    EdgeRuntime?: {
      waitUntil?: (promise: Promise<unknown>) => Promise<unknown> | void;
    };
  }).EdgeRuntime;
  if (edgeRuntime?.waitUntil) {
    edgeRuntime.waitUntil(guarded);
    return;
  }

  void guarded;
}

function isStatusAction(body: unknown): body is Record<string, unknown> {
  return isRecord(body) && body.action === "status";
}

function isRetryDayAction(body: unknown): body is Record<string, unknown> {
  return isRecord(body) && body.action === "retry_day";
}

function isCancelGenerationAction(
  body: unknown,
): body is Record<string, unknown> {
  return isRecord(body) && body.action === "cancel_generation";
}

async function retryQueuedDayGeneration(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  body: Record<string, unknown>,
): Promise<Response> {
  const generationID = stringValue(body.generation_id);
  const scheduledDate = stringValue(body.scheduled_date);
  if (!isUUID(generationID) || !scheduledDate) {
    return jsonResponse({ error: "invalid_generation_payload" }, 400);
  }

  if (isDateBeforeToday(scheduledDate)) {
    return pastDateNotAllowedResponse();
  }

  const runResult = await readGenerationRunForQueuedAction(
    admin,
    session,
    generationID,
  );
  if ("response" in runResult) {
    return runResult.response;
  }

  const retryResult = await markFailedDayJobRetrying(admin, {
    generationRunID: generationID,
    workspaceID: session.workspaceID,
    creatorID: stringValue(runResult.run.creator_id) ?? "",
    scheduledDate,
  });
  if ("error" in retryResult) {
    return generationPersistFailure(
      "retry_generation_day_job",
      retryResult.error,
    ).response;
  }
  if (!retryResult.job) {
    return jsonResponse({ error: "day_job_not_retryable" }, 409);
  }

  logGenerationLifecycle({
    action: "retry_day",
    phase: "day_job_retrying",
    status: "retrying",
    generation_id: generationID,
    weekly_plan_id: stringValue(runResult.run.weekly_plan_id) ??
      stringValue(retryResult.job.weekly_plan_id) ?? null,
    week_start_date: null,
    scheduled_date: scheduledDate,
    day_index: numberValue(retryResult.job.day_index) ?? null,
    duration_ms: null,
    day_guidance_present: null,
    day_guidance_chars: null,
  });

  return jsonResponse({
    generation_id: generationID,
    weekly_plan_id: stringValue(runResult.run.weekly_plan_id) ??
      stringValue(retryResult.job.weekly_plan_id) ?? null,
    status: "running",
    day: queuedDayJobStatusResponse(retryResult.job),
    message: "day_retry_queued",
    poll_after_seconds: 5,
  });
}

async function cancelGeneration(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  body: Record<string, unknown>,
): Promise<Response> {
  const generationID = stringValue(body.generation_id);
  if (!isUUID(generationID)) {
    return jsonResponse({ error: "invalid_generation_payload" }, 400);
  }

  const runResult = await readGenerationRunForQueuedAction(
    admin,
    session,
    generationID,
  );
  if ("response" in runResult) {
    return runResult.response;
  }

  // Determine mode: queued runs have day jobs, parallel runs do not.
  const lookupResult = await lookupQueuedDayJobsExist(
    admin,
    generationID,
    session.workspaceID,
    stringValue(runResult.run.creator_id) ?? "",
  );
  if ("error" in lookupResult) {
    return generationPersistFailure(
      "cancel_generation_day_jobs_lookup",
      lookupResult.error,
    ).response;
  }

  // Queued mode: delegate to existing queued cancel flow.
  if (lookupResult.exists) {
    return await cancelQueuedGeneration(admin, session, body);
  }

  // Parallel mode: mark the run as cancelled directly. In-flight day tasks
  // will detect generation_cancelled and return early.
  const runStatus = stringValue(runResult.run.status);
  if (isGenerationRunRecordCancelled(runResult.run)) {
    return jsonResponse({
      generation_id: generationID,
      weekly_plan_id: stringValue(runResult.run.weekly_plan_id) ?? null,
      status: "cancelled",
      message: "generation_cancelled",
    });
  }
  if (runStatus !== "running") {
    return jsonResponse({
      generation_id: generationID,
      weekly_plan_id: stringValue(runResult.run.weekly_plan_id) ?? null,
      status: runStatus ?? "running",
      message: "generation_not_cancellable",
    }, 409);
  }

  const cancelRunResult = await markGenerationRunCancelled(admin, generationID);
  if (cancelRunResult.error) {
    return generationPersistFailure(
      "cancel_generation_run",
      cancelRunResult.error,
    ).response;
  }

  return jsonResponse({
    generation_id: generationID,
    weekly_plan_id: stringValue(runResult.run.weekly_plan_id) ?? null,
    status: "cancelled",
    message: "generation_cancelled",
  });
}

async function cancelQueuedGeneration(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  body: Record<string, unknown>,
): Promise<Response> {
  const generationID = stringValue(body.generation_id);
  if (!isUUID(generationID)) {
    return jsonResponse({ error: "invalid_generation_payload" }, 400);
  }

  const runResult = await readGenerationRunForQueuedAction(
    admin,
    session,
    generationID,
  );
  if ("response" in runResult) {
    return runResult.response;
  }

  const cancelJobsResult = await cancelActiveQueuedDayJobs(
    admin,
    generationID,
    session.workspaceID,
    stringValue(runResult.run.creator_id) ?? "",
  );
  if (cancelJobsResult.error) {
    return generationPersistFailure(
      "cancel_generation_day_jobs",
      cancelJobsResult.error,
    ).response;
  }

  const cancelRunResult = await markGenerationRunCancelled(admin, generationID);
  if (cancelRunResult.error) {
    return generationPersistFailure(
      "cancel_generation_run",
      cancelRunResult.error,
    ).response;
  }

  return jsonResponse({
    generation_id: generationID,
    weekly_plan_id: stringValue(runResult.run.weekly_plan_id) ?? null,
    status: "cancelled",
    message: "generation_cancelled",
  });
}

async function readGenerationRunForQueuedAction(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  generationID: string,
): Promise<{ run: GenerationRunStatusRecord } | { response: Response }> {
  const { data, error } = await readQueuedActionGenerationRun(
    admin,
    generationID,
    session.workspaceID,
  );

  if (error) {
    return generationPersistFailure("read_generation_run", error);
  }
  if (!data) {
    return {
      response: jsonResponse({ error: "invalid_generation_payload" }, 404),
    };
  }
  return { run: data as GenerationRunStatusRecord };
}

function prepareGenerationFromRun(
  env: EnvReader,
  run: GenerationRunStatusRecord,
  session: VerifiedDeviceSession,
  inputSnapshot: GenerationInputSnapshot,
): { prepared: PreparedGeneration } | { response: Response } {
  const providers = aiProviderConfigs(env);
  const mockEnabled = env.get("MCO_AI_MOCK") === "1";
  if (!mockEnabled && providers.length === 0) {
    return { response: jsonResponse({ error: "missing_openai_api_key" }, 500) };
  }

  return {
    prepared: {
      request: requestFromRun(run, inputSnapshot),
      session: {
        ...session,
        memberID: stringValue(run.requested_by_member_id) ?? session.memberID,
      },
      weeklySetup: inputSnapshot.weekly_setup,
      inputSnapshot,
      providers,
      model: stringValue(run.model) ?? providerModelSummary(providers),
      mockEnabled,
    },
  };
}

function prepareSingleDayGenerationFromRun(
  admin: SupabaseAdminClient,
  generationID: string,
  env: EnvReader,
  run: GenerationRunStatusRecord,
  session: VerifiedDeviceSession,
  inputSnapshot: GenerationInputSnapshot,
  progress: SingleDayGenerationSnapshot,
): Promise<
  | { prepared: StatusHandlerPreparedDayGeneration }
  | { response: Response }
> {
  const weeklyPlanID = stringValue(run.weekly_plan_id);
  const targetCardID = stringValue(run.target_daily_card_id);
  const scheduledDate = stringValue(run.target_scheduled_date);

  const providers = aiProviderConfigs(env);
  const mockEnabled = env.get("MCO_AI_MOCK") === "1";
  if (!mockEnabled && providers.length === 0) {
    return Promise.resolve({
      response: jsonResponse({ error: "missing_openai_api_key" }, 500),
    });
  }

  const existingCards = inputSnapshot.existing_week_cards ?? [];
  const targetCard = targetCardID
    ? existingCards.find((card) =>
      card.id === targetCardID && card.scheduled_date === scheduledDate
    )
    : existingCards.find((card) => card.scheduled_date === scheduledDate);
  if (targetCardID && !targetCard) {
    return markGenerationRunFailed(
      admin,
      generationID,
      "daily_card_not_found",
    ).then(() => ({
      response: jsonResponse({
        generation_id: generationID,
        status: "failed",
        error: "daily_card_not_found",
      }),
    }));
  }

  return Promise.resolve({
    prepared: {
      request: {
        action: "regenerate_day",
        creator_id: run.creator_id,
        weekly_plan_id: weeklyPlanID!,
        scheduled_date: scheduledDate!,
        preserve_manual_edits: progress.preserve_manual_edits,
        mock: false,
        response_mode: "async",
      },
      session: {
        ...session,
        memberID: stringValue(run.requested_by_member_id) ?? session.memberID,
      },
      plan: {
        id: weeklyPlanID!,
        week_start_date: inputSnapshot.week_start_date,
        weekly_setup_id: stringValue(run.weekly_setup_id),
        status: "draft",
      },
      targetCard: targetCard as CardIdentityRecord,
      inputSnapshot,
      providers,
      model: stringValue(run.model) ?? providerModelSummary(providers),
      mockEnabled,
    },
  });
}

async function scheduleNextPendingDayGeneration(
  admin: SupabaseAdminClient,
  generationID: string,
  prepared: PreparedGeneration,
  progress: PerDayGenerationSnapshot,
  dependencies: GenerateWeekDependencies,
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

  scheduleBackgroundGeneration(
    runSingleDayGenerationStep(
      admin,
      generationID,
      prepared,
      runningProgress,
      dayIndex,
      dependencies,
      retryContext,
    ),
    dependencies,
  );

  return { progress: runningProgress };
}

async function runSingleDayGenerationStep(
  admin: SupabaseAdminClient,
  generationID: string,
  prepared: PreparedGeneration,
  progress: PerDayGenerationSnapshot,
  dayIndex: number,
  dependencies: GenerateWeekDependencies,
  retryContext?: Record<string, unknown>,
): Promise<void> {
  const day = progress.days[dayIndex];
  try {
    const output = await generateDayOutput(
      prepared,
      day.scheduled_date,
      dayIndex,
      dependencies,
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
      await markGenerationRunFailed(
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
      );
    }
  }
}

async function generateDayOutput(
  prepared: PreparedGeneration,
  scheduledDate: string,
  dayIndex: number,
  dependencies: GenerateWeekDependencies,
  generationID: string,
  phase: AIGenerationPhase,
  retryContext?: Record<string, unknown>,
): Promise<GeneratedDayOutput> {
  const generationInput = retryContext
    ? { ...prepared.inputSnapshot, day_retry_context: retryContext }
    : prepared.inputSnapshot;
  if (prepared.mockEnabled) {
    return mockGeneratedDayOutput(generationInput, dayIndex);
  }

  const instrumentation = generationAIInstrumentation(
    generationID,
    phase,
    "day",
  );
  if (dependencies.generateDayAI) {
    return await dependencies.generateDayAI(
      generationInput,
      prepared.providers,
      scheduledDate,
      dayIndex,
      instrumentation,
    );
  }
  return await callAIProvidersForDay(
    generationInput,
    prepared.providers,
    scheduledDate,
    dayIndex,
    undefined,
    instrumentation,
  );
}

function dayGenerationRetryContext(
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

function dayGenerationPhase(
  progress: PerDayGenerationSnapshot,
): AIGenerationPhase {
  return progress.kind === "parallel_week_generation_v1"
    ? "parallel_day_generation"
    : "async_day_generation";
}

async function finalizePerDayGeneration(
  admin: SupabaseAdminClient,
  generationID: string,
  run: GenerationRunStatusRecord,
  session: VerifiedDeviceSession,
  inputSnapshot: GenerationInputSnapshot,
  progress: PerDayGenerationSnapshot,
): Promise<{ payload: GenerateWeekDraftResponse } | { response: Response }> {
  const dayOutputs = progress.days.map((day) => day.output);
  if (dayOutputs.some((output) => !output)) {
    await markGenerationRunFailed(
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
  const persistResult = await persistGeneratedWeek(
    admin,
    session.workspaceID,
    request,
    stringValue(run.requested_by_member_id) ?? session.memberID,
    inputSnapshot.weekly_setup,
    inputSnapshot,
    generated,
  );
  if ("response" in persistResult) {
    const step = await persistenceFailureStep(persistResult.response);
    await markGenerationRunFailed(
      admin,
      generationID,
      step ? `generation_persist_failed:${step}` : "generation_persist_failed",
    );
    return persistResult;
  }

  const completedAt = new Date().toISOString();
  const payload = makeGenerateWeekDraftResponse(
    generationID,
    persistResult.weeklyPlanID,
    generated,
    persistResult.dailyCards,
    persistResult.ideaBank,
    completedAt,
  );
  const completedRunResult = await completeGenerationRun(
    admin,
    generationID,
    persistResult.weeklyPlanID,
    payload,
    completedAt,
  );
  if ("response" in completedRunResult) {
    const step = await persistenceFailureStep(completedRunResult.response);
    await markGenerationRunFailed(
      admin,
      generationID,
      step ? `generation_persist_failed:${step}` : "generation_persist_failed",
    );
    return completedRunResult;
  }

  return { payload };
}

async function finalizeTerminalPerDayGeneration(
  admin: SupabaseAdminClient,
  generationID: string,
  run: GenerationRunStatusRecord,
  session: VerifiedDeviceSession,
  inputSnapshot: GenerationInputSnapshot,
  progress: PerDayGenerationSnapshot,
): Promise<{ payload: Record<string, unknown> } | { response: Response }> {
  if (allDaysCompleted(progress)) {
    return await finalizePerDayGeneration(
      admin,
      generationID,
      run,
      session,
      inputSnapshot,
      progress,
    );
  }

  const completedAt = new Date().toISOString();
  const completedOutputs = progress.days.flatMap((day) =>
    day.status === "completed" && day.output ? [day.output] : []
  );
  const baseProgress = { ...progress, updated_at: completedAt };

  if (completedOutputs.length === 0) {
    await updateGenerationProgress(admin, generationID, baseProgress);
    await markGenerationRunFailed(
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
    makeInitialWeekStrategyOutput(inputSnapshot),
  );
  const request = requestFromRun(run, inputSnapshot);
  const persistResult = await persistGeneratedWeek(
    admin,
    session.workspaceID,
    request,
    stringValue(run.requested_by_member_id) ?? session.memberID,
    inputSnapshot.weekly_setup,
    inputSnapshot,
    generated,
  );
  if ("response" in persistResult) {
    const step = await persistenceFailureStep(persistResult.response);
    await markGenerationRunFailed(
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

async function updateGenerationProgress(
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

function mockGeneratedDayOutput(
  inputSnapshot: GenerationInputSnapshot,
  dayIndex: number,
): GeneratedDayOutput {
  const mock = makeMockGeneratedWeek(inputSnapshot);
  return {
    strategy_note: mock.strategy_summary,
    warnings: dayIndex === 0 ? mock.warnings : [],
    assumptions: dayIndex === 0 ? mock.assumptions : [],
    daily_card: mock.daily_cards[dayIndex],
    idea_bank: dayIndex === 0 ? mock.idea_bank : [],
    source_summary: mock.source_summary,
  };
}

async function readCreator(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
): Promise<{ creator: CreatorRecord } | { response: Response }> {
  const { data, error } = await readCreatorRow(admin, workspaceID, creatorID);

  if (error) {
    return { response: jsonResponse({ error: "creator_lookup_failed" }, 500) };
  }
  if (!data) {
    return { response: jsonResponse({ error: "creator_not_found" }, 404) };
  }

  return { creator: data as CreatorRecord };
}

async function hasPublishedWeek(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  weekStartDate: string,
): Promise<{ locked: boolean } | { response: Response }> {
  const { data, error } = await readPublishedWeekRow(
    admin,
    workspaceID,
    creatorID,
    weekStartDate,
  );

  if (error) {
    return {
      response: jsonResponse({ error: "weekly_plan_lookup_failed" }, 500),
    };
  }

  return { locked: Boolean(data) };
}

async function readWeeklySetup(
  admin: SupabaseAdminClient,
  workspaceID: string,
  request: GenerateWeekRequest,
): Promise<{ setup: Record<string, unknown> | null } | { response: Response }> {
  if (request.weekly_setup_id) {
    const { data, error } = await readWeeklySetupByID(
      admin,
      workspaceID,
      request.creator_id,
      request.weekly_setup_id,
    );

    if (error) {
      return {
        response: jsonResponse({ error: "weekly_setup_lookup_failed" }, 500),
      };
    }
    if (!data) {
      return {
        response: jsonResponse({ error: "weekly_setup_not_found" }, 404),
      };
    }
    return { setup: data };
  }

  const { data, error } = await readLatestWeeklySetupForWeek(
    admin,
    workspaceID,
    request.creator_id,
    request.week_start_date,
  );

  if (error) {
    return {
      response: jsonResponse({ error: "weekly_setup_lookup_failed" }, 500),
    };
  }

  return { setup: data };
}

async function buildGenerationInput(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  weekStartDate: string,
  creator: CreatorRecord,
  weeklySetup: Record<string, unknown> | null,
): Promise<{ input: GenerationInputSnapshot } | { response: Response }> {
  const context = await readGenerationContextRows(
    admin,
    workspaceID,
    creatorID,
    weekStartDate,
  );

  const profileRow = context.profile_rows[0] ?? null;

  return {
    input: {
      creator_id: creatorID,
      week_start_date: weekStartDate,
      creator_profile: profileRow
        ? {
          ...profileRow,
          display_name: creator.display_name ?? "Creator",
          default_timezone: creator.default_timezone ?? "Asia/Kolkata",
        }
        : {
          display_name: creator.display_name ?? "Creator",
          default_timezone: creator.default_timezone ?? "Asia/Kolkata",
        },
      weekly_setup: weeklySetup,
      confirmed_references: context.confirmed_references,
      reference_extractions: context.reference_extractions,
      recent_archive: context.recent_archive,
      idea_bank: context.idea_bank,
      patterns: context.patterns,
      trends: context.trends,
      audio_options: context.audio_options,
      brand_briefs: context.brand_briefs,
      key_moments: context.key_moments,
    },
  };
}

async function createGenerationRun(
  admin: SupabaseAdminClient,
  workspaceID: string,
  request: GenerateWeekRequest,
  memberID: string,
  model: string,
  inputSnapshot: GenerationInputSnapshot,
): Promise<{ run: RunRecord } | { response: Response }> {
  const { data, error } = await insertWeekGenerationRun(admin, {
    workspace_id: workspaceID,
    creator_id: request.creator_id,
    weekly_setup_id: request.weekly_setup_id ?? null,
    requested_by_member_id: memberID,
    status: "running",
    model,
    prompt_version: PROMPT_VERSION,
    input_snapshot: inputSnapshot,
    warnings: [],
    assumptions: [],
  });

  if (error || !data) {
    return generationPersistFailure("create_generation_run", error);
  }

  return { run: data as RunRecord };
}

async function createDayGenerationRun(
  admin: SupabaseAdminClient,
  prepared: PreparedDayGeneration,
  memberID: string,
): Promise<{ run: RunRecord } | { response: Response }> {
  const { data, error } = await insertDayGenerationRun(admin, {
    workspace_id: prepared.session.workspaceID,
    creator_id: prepared.request.creator_id,
    weekly_setup_id: prepared.plan.weekly_setup_id ?? null,
    weekly_plan_id: prepared.request.weekly_plan_id,
    requested_by_member_id: memberID,
    status: "running",
    model: prepared.model,
    prompt_version: PROMPT_VERSION,
    generation_scope: "day",
    target_daily_card_id: prepared.targetCard?.id ?? null,
    target_scheduled_date: prepared.request.scheduled_date,
    input_snapshot: prepared.inputSnapshot,
    warnings: [],
    assumptions: [],
  });
  if (error || !data) {
    return generationPersistFailure("create_day_generation_run", error);
  }
  return { run: data as RunRecord };
}

async function updateGenerationRunWeeklyPlan(
  admin: SupabaseAdminClient,
  generationID: string,
  weeklyPlanID: string,
): Promise<{ ok: true } | { response: Response }> {
  const { error } = await linkGenerationRunWeeklyPlan(
    admin,
    generationID,
    weeklyPlanID,
  );

  if (error) {
    return generationPersistFailure("update_generation_weekly_plan", error);
  }
  return { ok: true };
}

async function scheduleSingleDayGeneration(
  admin: SupabaseAdminClient,
  generationID: string,
  prepared: PreparedDayGeneration,
  progress: SingleDayGenerationSnapshot,
  dependencies: GenerateWeekDependencies,
): Promise<{ ok: true } | { response: Response }> {
  const now = new Date().toISOString();
  const runningProgress: SingleDayGenerationSnapshot = {
    ...progress,
    status: "running",
    started_at: now,
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
  scheduleBackgroundGeneration(
    runDayGenerationPipeline(
      admin,
      generationID,
      prepared,
      dependencies,
    ),
    dependencies,
  );
  return { ok: true };
}

async function runDayGenerationPipeline(
  admin: SupabaseAdminClient,
  generationID: string,
  prepared: PreparedDayGeneration,
  dependencies: GenerateWeekDependencies,
): Promise<
  { payload: RegenerateDayDraftResponse } | { response: Response }
> {
  const dayIndex = weekDates(prepared.inputSnapshot.week_start_date).indexOf(
    prepared.request.scheduled_date,
  );
  if (dayIndex < 0) {
    await markGenerationRunFailed(admin, generationID, "date_not_in_plan");
    logGenerationLifecycle({
      action: "regenerate_day",
      phase: "generation_failed",
      status: "failed",
      generation_id: generationID,
      weekly_plan_id: prepared.request.weekly_plan_id,
      week_start_date: prepared.inputSnapshot.week_start_date,
      scheduled_date: prepared.request.scheduled_date,
      day_index: null,
      duration_ms: null,
      day_guidance_present: prepared.request.day_guidance !== undefined,
      day_guidance_chars: prepared.request.day_guidance?.length ?? 0,
    });
    return {
      response: jsonResponse({ error: "date_not_in_plan" }, 400),
    };
  }

  const pipelineStartedAt = Date.now();
  logGenerationLifecycle({
    action: "regenerate_day",
    phase: "generation_started",
    status: "running",
    generation_id: generationID,
    weekly_plan_id: prepared.request.weekly_plan_id,
    week_start_date: prepared.inputSnapshot.week_start_date,
    scheduled_date: prepared.request.scheduled_date,
    day_index: dayIndex,
    duration_ms: null,
    day_guidance_present: prepared.request.day_guidance !== undefined,
    day_guidance_chars: prepared.request.day_guidance?.length ?? 0,
  });

  let generated: GeneratedDayOutput;
  try {
    const rawOutput = prepared.mockEnabled
      ? mockGeneratedDayOutput(prepared.inputSnapshot, dayIndex)
      : await generateRegeneratedDayOutput(
        prepared,
        generationID,
        dayIndex,
        dependencies,
      );
    generated = validateGeneratedDayOutput(
      rawOutput,
      prepared.request.scheduled_date,
      dayIndex,
    );
  } catch (error) {
    const errorCode = stableGenerationError(error);
    await markGenerationRunFailed(admin, generationID, errorCode);
    logGenerationLifecycle({
      action: "regenerate_day",
      phase: "generation_failed",
      status: "failed",
      generation_id: generationID,
      weekly_plan_id: prepared.request.weekly_plan_id,
      week_start_date: prepared.inputSnapshot.week_start_date,
      scheduled_date: prepared.request.scheduled_date,
      day_index: dayIndex,
      duration_ms: Date.now() - pipelineStartedAt,
      day_guidance_present: prepared.request.day_guidance !== undefined,
      day_guidance_chars: prepared.request.day_guidance?.length ?? 0,
    });
    return {
      response: jsonResponse(
        { error: errorCode },
        errorCode === "openai_request_failed" ? 502 : 400,
      ),
    };
  }

  const persistResult = await persistRegeneratedDay(
    admin,
    prepared,
    generated.daily_card,
  );
  if ("response" in persistResult) {
    await markGenerationRunFailed(
      admin,
      generationID,
      "generation_persist_failed",
    );
    logGenerationLifecycle({
      action: "regenerate_day",
      phase: "generation_failed",
      status: "failed",
      generation_id: generationID,
      weekly_plan_id: prepared.request.weekly_plan_id,
      week_start_date: prepared.inputSnapshot.week_start_date,
      scheduled_date: prepared.request.scheduled_date,
      day_index: dayIndex,
      duration_ms: Date.now() - pipelineStartedAt,
      day_guidance_present: prepared.request.day_guidance !== undefined,
      day_guidance_chars: prepared.request.day_guidance?.length ?? 0,
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
  const completedResult = await completeDayGenerationRun(
    admin,
    generationID,
    payload,
    completedAt,
  );
  if ("response" in completedResult) {
    await markGenerationRunFailed(
      admin,
      generationID,
      "generation_persist_failed",
    );
    logGenerationLifecycle({
      action: "regenerate_day",
      phase: "generation_failed",
      status: "failed",
      generation_id: generationID,
      weekly_plan_id: prepared.request.weekly_plan_id,
      week_start_date: prepared.inputSnapshot.week_start_date,
      scheduled_date: prepared.request.scheduled_date,
      day_index: dayIndex,
      duration_ms: Date.now() - pipelineStartedAt,
      day_guidance_present: prepared.request.day_guidance !== undefined,
      day_guidance_chars: prepared.request.day_guidance?.length ?? 0,
    });
    return completedResult;
  }
  logGenerationLifecycle({
    action: "regenerate_day",
    phase: "generation_completed",
    status: "completed",
    generation_id: generationID,
    weekly_plan_id: prepared.request.weekly_plan_id,
    week_start_date: prepared.inputSnapshot.week_start_date,
    scheduled_date: prepared.request.scheduled_date,
    day_index: dayIndex,
    duration_ms: Date.now() - pipelineStartedAt,
    day_guidance_present: prepared.request.day_guidance !== undefined,
    day_guidance_chars: prepared.request.day_guidance?.length ?? 0,
  });
  return { payload };
}

async function generateRegeneratedDayOutput(
  prepared: PreparedDayGeneration,
  generationID: string,
  dayIndex: number,
  dependencies: GenerateWeekDependencies,
): Promise<GeneratedDayOutput> {
  const instrumentation = generationAIInstrumentation(
    generationID,
    "regenerate_day_generation",
    "day",
  );
  if (dependencies.generateDayAI) {
    return await dependencies.generateDayAI(
      prepared.inputSnapshot,
      prepared.providers,
      prepared.request.scheduled_date,
      dayIndex,
      instrumentation,
    );
  }
  return await callAIProvidersForDay(
    prepared.inputSnapshot,
    prepared.providers,
    prepared.request.scheduled_date,
    dayIndex,
    undefined,
    instrumentation,
  );
}

async function persistRegeneratedDay(
  admin: SupabaseAdminClient,
  prepared: PreparedDayGeneration,
  generatedCard: GeneratedDailyCard,
): Promise<{ dailyCard: GeneratedDailyCard } | { response: Response }> {
  const currentPlan = await readDayGenerationPlan(
    admin,
    prepared.session.workspaceID,
    prepared.request,
  );
  if ("response" in currentPlan) {
    return currentPlan;
  }
  if (
    currentPlan.plan.status === "published" ||
    currentPlan.plan.is_soft_locked
  ) {
    return {
      response: jsonResponse({ error: "existing_published_week_locked" }, 409),
    };
  }
  if (currentPlan.plan.status !== "draft") {
    return {
      response: jsonResponse({ error: "weekly_plan_not_found" }, 409),
    };
  }

  const freshCards = await readPlanCardsForDayGeneration(
    admin,
    prepared.session.workspaceID,
    prepared.request,
  );
  if ("response" in freshCards) {
    return freshCards;
  }
  const existing = freshCards.cards.find((card) =>
    (prepared.targetCard?.id ? card.id === prepared.targetCard.id : true) &&
    card.scheduled_date === prepared.request.scheduled_date &&
    card.status === "draft"
  );

  const card = prepared.request.preserve_manual_edits && existing
    ? preserveManualDailyCardEdits(generatedCard, existing)
    : generatedCard;
  if (!existing) {
    const persistResult = await upsertGeneratedDailyCards(
      admin,
      prepared.session.workspaceID,
      prepared.request.creator_id,
      prepared.request.weekly_plan_id,
      [card],
      false,
    );
    if ("response" in persistResult) {
      return persistResult;
    }
    const dailyCard = persistResult.dailyCards.find((entry) =>
      entry.scheduled_date === prepared.request.scheduled_date
    ) ?? persistResult.dailyCards[0];
    return dailyCard ? { dailyCard } : {
      response: jsonResponse(
        { error: "daily_card_not_found" },
        404,
      ),
    };
  }

  const values = generatedDailyCardValues(card);
  const { data, error } = await updateExistingDraftDailyCard(
    admin,
    values,
    {
      id: existing.id,
      workspace_id: prepared.session.workspaceID,
      creator_id: prepared.request.creator_id,
      weekly_plan_id: prepared.request.weekly_plan_id,
      scheduled_date: prepared.request.scheduled_date,
    },
  );
  if (error || !isRecord(data)) {
    return generationPersistFailure("regenerate_day_update_card", error);
  }

  const referenceResult = await replaceDailyCardReferences(
    admin,
    prepared.session.workspaceID,
    prepared.request.creator_id,
    existing.id,
    card,
  );
  if ("response" in referenceResult) {
    return referenceResult;
  }
  return { dailyCard: { ...card, id: existing.id } };
}

async function completeDayGenerationRun(
  admin: SupabaseAdminClient,
  generationID: string,
  payload: RegenerateDayDraftResponse,
  completedAt: string,
): Promise<{ ok: true } | { response: Response }> {
  const { error } = await completeDayGenerationRunStore(
    admin,
    generationID,
    {
      output_snapshot: payload,
      warnings: payload.warnings,
      assumptions: payload.assumptions,
      completed_at: completedAt,
    },
  );
  if (error) {
    const fallback = await completeGenerationRunWithoutSnapshot(
      admin,
      generationID,
      undefined,
      completedAt,
      "complete_day_generation_run",
      error,
    );
    if ("response" in fallback) {
      return fallback;
    }
  }
  return { ok: true };
}

async function persistGeneratedWeek(
  admin: SupabaseAdminClient,
  workspaceID: string,
  request: GenerateWeekRequest,
  memberID: string,
  weeklySetup: Record<string, unknown> | null,
  inputSnapshot: GenerationInputSnapshot,
  generated: GeneratedWeekOutput,
): Promise<
  {
    weeklyPlanID: string;
    dailyCards: GeneratedDailyCard[];
    ideaBank: Record<string, unknown>[];
  } | { response: Response }
> {
  for (const card of generated.daily_cards) {
    assertDayRespectsWeeklyBriefContext(inputSnapshot, card);
  }

  const planResult = await upsertDraftWeeklyPlan(
    admin,
    workspaceID,
    request,
    memberID,
    weeklySetup,
    inputSnapshot,
    generated,
  );
  if ("response" in planResult) {
    return planResult;
  }

  const ideasResult = await insertGeneratedIdeas(
    admin,
    workspaceID,
    request.creator_id,
    generated,
  );
  if ("response" in ideasResult) {
    return ideasResult;
  }

  const cardsResult = await upsertGeneratedDailyCards(
    admin,
    workspaceID,
    request.creator_id,
    planResult.weeklyPlanID,
    generated.daily_cards,
    request.preserve_manual_edits,
  );
  if ("response" in cardsResult) {
    return cardsResult;
  }

  return {
    weeklyPlanID: planResult.weeklyPlanID,
    dailyCards: cardsResult.dailyCards,
    ideaBank: ideasResult.ideaBank,
  };
}

async function completeGenerationRun(
  admin: SupabaseAdminClient,
  generationID: string,
  weeklyPlanID: string,
  payload: GenerateWeekDraftResponse,
  completedAt: string,
): Promise<{ ok: true } | { response: Response }> {
  const { error } = await completeFullWeekGenerationRun(
    admin,
    generationID,
    {
      weekly_plan_id: weeklyPlanID,
      output_snapshot: payload,
      warnings: payload.warnings,
      assumptions: payload.assumptions,
      completed_at: completedAt,
    },
  );

  if (error) {
    const fallback = await completeGenerationRunWithoutSnapshot(
      admin,
      generationID,
      weeklyPlanID,
      completedAt,
      "complete_generation_run",
      error,
    );
    if ("response" in fallback) {
      return fallback;
    }
  }

  return { ok: true };
}

async function completeGenerationRunWithoutSnapshot(
  admin: SupabaseAdminClient,
  generationID: string,
  weeklyPlanID: string | undefined,
  completedAt: string,
  step: string,
  originalError: unknown,
): Promise<{ ok: true } | { response: Response }> {
  console.warn(
    "generate-week completion snapshot write failed; retrying minimal completion",
    {
      step,
      error: originalError,
    },
  );
  const update: Record<string, unknown> = {
    status: "completed",
    completed_at: completedAt,
    error_code: null,
  };
  if (weeklyPlanID) {
    update.weekly_plan_id = weeklyPlanID;
  }

  const { error } = await completeGenerationRunMinimal(
    admin,
    generationID,
    update,
  );

  if (error) {
    return generationPersistFailure(step, error);
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

function aiProviderConfigs(env: EnvReader): AIProviderConfig[] {
  const deepSeekKey = env.get("DEEPSEEK_API_KEY")?.trim();
  const openAIKey = env.get("OPENAI_API_KEY")?.trim();
  const deepSeekModel = env.get("MCO_DEEPSEEK_MODEL")?.trim() ||
    DEFAULT_DEEPSEEK_MODEL;
  const openAIModel = env.get("MCO_OPENAI_MODEL")?.trim() ||
    DEFAULT_OPENAI_MODEL;
  const deepSeekBaseURL = env.get("MCO_DEEPSEEK_BASE_URL")?.trim() ||
    "https://api.deepseek.com";

  const providersByName: Record<string, AIProviderConfig | undefined> = {
    deepseek: deepSeekKey
      ? {
        provider: "deepseek",
        model: deepSeekModel,
        apiKey: deepSeekKey,
        baseURL: deepSeekBaseURL,
      }
      : undefined,
    openai: openAIKey
      ? { provider: "openai", model: openAIModel, apiKey: openAIKey }
      : undefined,
  };
  const order = (env.get("MCO_AI_PROVIDER_ORDER") ?? "openai,deepseek")
    .split(",")
    .map((provider) => provider.trim().toLowerCase())
    .filter((provider) => provider.length > 0);

  const seen = new Set<string>();
  return order.flatMap((provider) => {
    if (seen.has(provider)) {
      return [];
    }
    seen.add(provider);
    const config = providersByName[provider];
    return config ? [config] : [];
  });
}

function providerModelSummary(providers: AIProviderConfig[]): string {
  return providers.length > 0
    ? providers.map((provider) => `${provider.provider}:${provider.model}`)
      .join(" -> ")
    : `deepseek:${DEFAULT_DEEPSEEK_MODEL} -> openai:${DEFAULT_OPENAI_MODEL}`;
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

if (import.meta.main) {
  Deno.serve((request) => handleGenerateWeekRequest(request));
}
