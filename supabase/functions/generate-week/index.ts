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
  completedDraftStatusSummary,
  initialParallelWeekGenerationSnapshot,
  initialPerDayGenerationSnapshot,
  normalizePerDayGenerationSnapshot,
  queuedDayJobStatusResponse,
  queuedDayJobStatusSummary,
  weekGenerationStatusSummary,
} from "./generation-status.ts";
import type {
  DayGenerationState,
  DayGenerationStatus,
  PerDayGenerationSnapshot,
  QueuedDayJobRecord,
  QueuedDayJobStatus,
} from "./generation-status.ts";

type EnvReader = {
  get: (name: string) => string | undefined;
};

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

type GenerateWeekDraftResponse = {
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

type RegenerateDayDraftResponse = {
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

type GenerationRunStatusRecord = Record<string, unknown> & {
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

type SingleDayGenerationSnapshot = {
  kind: "single_day_generation_v1";
  scheduled_date: string;
  preserve_manual_edits: boolean;
  status: "pending" | "running";
  started_at?: string;
  updated_at: string;
};

type CreatorRecord = Record<string, unknown> & {
  id: string;
  display_name?: string;
};

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

const DEFAULT_DEEPSEEK_MODEL = "deepseek-v4-pro";
const DEFAULT_OPENAI_MODEL = "gpt-4.1-mini";
const PROMPT_VERSION = "creator-weekly-generation-v1";
const DEFAULT_RUNNING_DAY_STALE_MS = 135_000;
const DAY_GENERATION_HEARTBEAT_MIN_MS = 1_000;
const DAY_GENERATION_HEARTBEAT_MAX_MS = 60_000;
const DEFAULT_DAY_GENERATION_MAX_ATTEMPTS = 3;

let todayISOProvider: () => string = () =>
  new Date().toISOString().slice(0, 10);

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
      dependencies,
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
      isTerminalDayGenerationState,
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

  const existingResult = await admin
    .from("weekly_plans")
    .select("id,status,is_soft_locked")
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", request.creator_id)
    .eq("week_start_date", weekStartDate)
    .in("status", ["draft"])
    .order("updated_at", { ascending: false })
    .limit(1);
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
  const { data, error } = await admin
    .from("weekly_plans")
    .insert({
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
    })
    .select("id")
    .single();
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
  const { data, error } = await admin
    .from("weekly_plans")
    .select("id,status,is_soft_locked,week_start_date,weekly_setup_id")
    .eq("id", request.weekly_plan_id)
    .eq("workspace_id", workspaceID)
    .eq("creator_id", request.creator_id)
    .maybeSingle();
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
  const { data, error } = await admin
    .from("daily_cards")
    .select(dayGenerationCardSelect())
    .eq("workspace_id", workspaceID)
    .eq("creator_id", request.creator_id)
    .eq("weekly_plan_id", request.weekly_plan_id)
    .order("scheduled_date", { ascending: true });
  if (error) {
    return {
      response: jsonResponse({ error: "daily_card_lookup_failed" }, 500),
    };
  }
  return { cards: (data ?? []) as CardIdentityRecord[] };
}

async function readSavedDailyCards(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  weeklyPlanID: string,
): Promise<{ dailyCards: SavedDailyCard[] } | { response: Response }> {
  const { data, error } = await admin
    .from("daily_cards")
    .select(dayGenerationCardSelect())
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("weekly_plan_id", weeklyPlanID)
    .order("scheduled_date", { ascending: true });
  if (error) {
    return generationPersistFailure("daily_cards_lookup", error);
  }
  return {
    dailyCards: ((data ?? []) as CardIdentityRecord[]).map(
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

function savedDailyCardsForProgress(
  savedCards: SavedDailyCard[],
  progress: PerDayGenerationSnapshot,
): SavedDailyCard[] {
  return savedCards.filter((card) =>
    progress.days.some((day) => savedDailyCardMatchesProgressDay(card, day))
  );
}

function mergeSavedDailyCardsIntoProgress(
  progress: PerDayGenerationSnapshot,
  savedCards: SavedDailyCard[],
): PerDayGenerationSnapshot {
  let changed = false;
  const days = progress.days.map((day) => {
    const saved = savedCards.find((card) =>
      savedDailyCardMatchesProgressDay(card, day)
    );
    if (!saved) {
      return day;
    }
    if (
      day.status === "completed" &&
      day.daily_card_id === saved.id &&
      !day.error_code
    ) {
      return day;
    }
    changed = true;
    return {
      ...day,
      status: "completed" as const,
      daily_card_id: saved.id,
      completed_at: day.completed_at ?? saved.updated_at ??
        new Date().toISOString(),
      error_code: undefined,
    };
  });
  return changed
    ? { ...progress, days, updated_at: new Date().toISOString() }
    : progress;
}

function savedDailyCardMatchesProgressDay(
  card: SavedDailyCard,
  day: DayGenerationState,
): boolean {
  if (!isUUID(card.id) || card.scheduled_date !== day.scheduled_date) {
    return false;
  }
  if (isUUID(day.daily_card_id) && card.id === day.daily_card_id) {
    return true;
  }
  if (!isAttemptedDayGenerationState(day)) {
    return false;
  }
  return savedDailyCardUpdatedAfterDayStarted(card, day);
}

function isAttemptedDayGenerationState(day: DayGenerationState): boolean {
  return day.attempts > 0 ||
    day.status === "running" ||
    day.status === "completed" ||
    day.status === "failed" ||
    Boolean(day.output);
}

function savedDailyCardUpdatedAfterDayStarted(
  card: SavedDailyCard,
  day: DayGenerationState,
): boolean {
  const updatedAt = Date.parse(card.updated_at ?? "");
  const startedAt = Date.parse(day.started_at ?? "");
  return Number.isFinite(updatedAt) &&
    Number.isFinite(startedAt) &&
    updatedAt >= startedAt;
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

function dayGenerationCardSelect(): string {
  return [
    "id",
    "scheduled_date",
    "status",
    "title",
    "why_today",
    "growth_job",
    "content_pillar",
    "shootability",
    "estimated_shoot_minutes",
    "energy_required",
    "language_mode",
    "scene_list",
    "script",
    "no_voiceover_version",
    "on_screen_text",
    "caption",
    "cta",
    "hashtags",
    "cover_text",
    "post_instructions",
    "brand_event_notes",
    "backup_story",
    "backup_caption_only",
    "risk_notes",
    "assumptions",
    "source_note",
    "storyboard_thumbnail_assets",
    "updated_at",
  ].join(",");
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

function generationPersistFailure(
  step: string,
  error?: unknown,
): { response: Response } {
  console.error(
    "generate-week persist failed",
    step,
    postgrestErrorMessage(error),
  );
  const detail = postgrestErrorMessage(error);
  return {
    response: jsonResponse(
      {
        error: "generation_persist_failed",
        step,
        detail: detail.slice(0, 500),
      },
      500,
    ),
  };
}

function postgrestErrorMessage(error: unknown): string {
  if (isRecord(error)) {
    return stringValue(error.message) ??
      stringValue(error.details) ??
      stringValue(error.hint) ??
      stringValue(error.code) ??
      "unknown_error";
  }
  if (error instanceof Error) {
    return error.message;
  }
  return typeof error === "string" ? error : "unknown_error";
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
    dependencies,
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
        isTerminalDayGenerationState,
      ),
      poll_after_seconds: 5,
    }, 202);
  }

  const result = await runPromise;
  return "response" in result ? result.response : jsonResponse(result.payload);
}

async function clearExistingDraftDailyCardsForFullGeneration(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  weeklyPlanID: string,
): Promise<{ ok: true } | { response: Response }> {
  const { error } = await admin
    .from("daily_cards")
    .delete()
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("weekly_plan_id", weeklyPlanID);

  if (error) {
    return generationPersistFailure("daily_cards_clear_existing", error);
  }

  return { ok: true };
}

async function createQueuedDayJobs(
  admin: SupabaseAdminClient,
  prepared: PreparedGeneration,
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
    status: "queued",
    attempt_count: 0,
  }));

  const { data, error } = await admin
    .from("weekly_generation_day_jobs")
    .upsert(rows, { onConflict: "generation_run_id,scheduled_date" })
    .select(queuedDayJobSelect())
    .order("day_index", { ascending: true });

  if (error) {
    return generationPersistFailure("create_generation_day_jobs", error);
  }

  const jobs = normalizeQueuedDayJobRows(data);
  for (const job of jobs) {
    logGenerationLifecycle({
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
async function createSeededDayJobsFromProgress(
  admin: SupabaseAdminClient,
  prepared: PreparedGeneration,
  generationID: string,
  weeklyPlanID: string,
  progress: PerDayGenerationSnapshot,
): Promise<{ jobs: QueuedDayJobRecord[] } | { response: Response }> {
  const now = new Date().toISOString();
  const placeholderLease = crypto.randomUUID();
  const rows = progress.days.map((day, dayIndex) => {
    const running = day.status === "running" && !isRunningDayStale(day);
    const terminalFailure = day.status === "failed" &&
      day.attempts >= maxDayGenerationAttempts();
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

  const { data, error } = await admin
    .from("weekly_generation_day_jobs")
    .upsert(rows, { onConflict: "generation_run_id,scheduled_date" })
    .select(queuedDayJobSelect())
    .order("day_index", { ascending: true });

  if (error) {
    return generationPersistFailure("create_seeded_generation_day_jobs", error);
  }

  return { jobs: normalizeQueuedDayJobRows(data) };
}

function queuedDayJobSelect(): string {
  return [
    "id",
    "generation_run_id",
    "weekly_plan_id",
    "workspace_id",
    "creator_id",
    "scheduled_date",
    "day_index",
    "status",
    "attempt_count",
    "daily_card_id",
    "error_code",
    "error_message",
    "started_at",
    "completed_at",
    "heartbeat_at",
    "lease_token",
    "worker_boot_id",
    "staged_output",
  ].join(",");
}

// ── Day-job lease-guarded operations ──

async function dayJobRPC<T>(
  admin: SupabaseAdminClient,
  functionName: string,
  params: Record<string, unknown>,
): Promise<T | null> {
  const client = admin as unknown as {
    rpc: (
      fn: string,
      params: Record<string, unknown>,
    ) => Promise<{ data: T | null; error: unknown }>;
  };
  const { data, error } = await client.rpc(functionName, params);
  if (error) {
    console.warn("generate-week day-job RPC failed", {
      rpc: functionName,
      error: postgrestErrorMessage(error),
    });
    return null;
  }
  return data;
}

async function claimQueuedDayJob(
  admin: SupabaseAdminClient,
  generationRunID: string,
  leaseToken: string,
  bootID: string,
  concurrency: number,
  staleThresholdMS: number,
): Promise<QueuedDayJobRecord | null> {
  const row = await dayJobRPC<QueuedDayJobRecord>(
    admin,
    "claim_queued_day_job",
    {
      p_generation_run_id: generationRunID,
      p_lease_token: leaseToken,
      p_worker_boot_id: bootID,
      p_max_live_jobs: concurrency,
      p_stale_threshold_ms: staleThresholdMS,
    },
  );
  // RPC returns the raw Postgres row; normalise it.
  const rawRow = Array.isArray(row) ? row[0] : row;
  if (!isRecord(rawRow)) return null;
  const job = normalizeQueuedDayJobRows([rawRow])[0];
  return job.id ? job : null;
}

async function reclaimStaleDayJob(
  admin: SupabaseAdminClient,
  generationRunID: string,
  leaseToken: string,
  bootID: string,
  staleThresholdMS: number,
  concurrency: number,
): Promise<QueuedDayJobRecord | null> {
  const row = await dayJobRPC<QueuedDayJobRecord>(
    admin,
    "reclaim_stale_day_job",
    {
      p_generation_run_id: generationRunID,
      p_lease_token: leaseToken,
      p_worker_boot_id: bootID,
      p_stale_threshold_ms: staleThresholdMS,
      p_max_attempts: maxDayGenerationAttempts(),
      p_max_live_jobs: concurrency,
    },
  );
  const rawRow = Array.isArray(row) ? row[0] : row;
  if (!isRecord(rawRow)) return null;
  const job = normalizeQueuedDayJobRows([rawRow])[0];
  return job.id ? job : null;
}

async function releaseOverCapacityDayJob(
  admin: SupabaseAdminClient,
  job: QueuedDayJobRecord,
  leaseToken: string,
): Promise<boolean> {
  const releasedAttempts = Math.max(0, (job.attempt_count ?? 1) - 1);
  const releasedStatus: QueuedDayJobStatus = releasedAttempts > 0
    ? "retrying"
    : "queued";
  const { data, error } = await admin
    .from("weekly_generation_day_jobs")
    .update({
      status: releasedStatus,
      attempt_count: releasedAttempts,
      lease_token: null,
      worker_boot_id: null,
      heartbeat_at: null,
      started_at: null,
      completed_at: null,
      staged_output: null,
    })
    .eq("id", job.id)
    .eq("lease_token", leaseToken)
    .eq("status", "generating")
    .select("id")
    .maybeSingle();

  if (error) {
    console.warn("generate-week day-job over-capacity release failed", {
      generation_id: job.generation_run_id,
      job_id: job.id,
      scheduled_date: job.scheduled_date,
      error: postgrestErrorMessage(error),
    });
  }
  return isRecord(data) && Boolean(data.id);
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

async function heartbeatDayJob(
  admin: SupabaseAdminClient,
  jobID: string,
  leaseToken: string,
): Promise<boolean> {
  const { data, error } = await admin
    .from("weekly_generation_day_jobs")
    .update({ heartbeat_at: new Date().toISOString() })
    .eq("id", jobID)
    .eq("lease_token", leaseToken)
    .eq("status", "generating")
    .select("id")
    .maybeSingle();
  if (error) {
    console.warn("generate-week day-job heartbeat failed", {
      job_id: jobID,
      error: postgrestErrorMessage(error),
    });
  }
  return isRecord(data) && Boolean(data.id);
}

async function completeDayJob(
  admin: SupabaseAdminClient,
  jobID: string,
  leaseToken: string,
  dailyCardID: string,
): Promise<boolean> {
  const { data } = await admin
    .from("weekly_generation_day_jobs")
    .update({
      status: "generated",
      daily_card_id: dailyCardID,
      completed_at: new Date().toISOString(),
    })
    .eq("id", jobID)
    .eq("lease_token", leaseToken)
    .eq("status", "ready_to_persist")
    .select("id")
    .maybeSingle();
  return isRecord(data) && Boolean(data.id);
}

async function failDayJob(
  admin: SupabaseAdminClient,
  jobID: string,
  leaseToken: string,
  errorCode: string,
  errorMessage?: string,
): Promise<boolean> {
  const { data } = await admin
    .from("weekly_generation_day_jobs")
    .update({
      status: "failed",
      error_code: errorCode,
      error_message: errorMessage?.slice(0, 1000) ?? null,
      completed_at: new Date().toISOString(),
    })
    .eq("id", jobID)
    .eq("lease_token", leaseToken)
    .in("status", ["generating", "ready_to_persist"])
    .select("id")
    .maybeSingle();
  return isRecord(data) && Boolean(data.id);
}

async function stageDayJobOutput(
  admin: SupabaseAdminClient,
  jobID: string,
  leaseToken: string,
  attempt: number,
  output: Record<string, unknown>,
): Promise<boolean> {
  const row = await dayJobRPC<QueuedDayJobRecord>(
    admin,
    "stage_day_job_output",
    {
      p_job_id: jobID,
      p_lease_token: leaseToken,
      p_attempt: attempt,
      p_output: output,
    },
  );
  const rawRow = Array.isArray(row) ? row[0] : row;
  return isRecord(rawRow) && Boolean(rawRow.id);
}

function normalizeQueuedDayJobRows(value: unknown): QueuedDayJobRecord[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.filter(isRecord).flatMap((row) => {
    const scheduledDate = stringValue(row.scheduled_date);
    const status = normalizeQueuedDayJobStatus(row.status);
    const dayIndex = numberValue(row.day_index);
    if (!scheduledDate || !status || dayIndex === undefined) {
      return [];
    }
    return [{
      id: stringValue(row.id) ?? "",
      generation_run_id: stringValue(row.generation_run_id) ?? "",
      weekly_plan_id: stringValue(row.weekly_plan_id) ?? "",
      workspace_id: stringValue(row.workspace_id) ?? "",
      creator_id: stringValue(row.creator_id) ?? "",
      scheduled_date: scheduledDate,
      day_index: dayIndex,
      status,
      attempt_count: numberValue(row.attempt_count) ?? 0,
      daily_card_id: stringValue(row.daily_card_id) ?? null,
      error_code: stringValue(row.error_code) ?? null,
      error_message: stringValue(row.error_message) ?? null,
      started_at: stringValue(row.started_at) ?? null,
      completed_at: stringValue(row.completed_at) ?? null,
      heartbeat_at: stringValue(row.heartbeat_at) ?? null,
      lease_token: stringValue(row.lease_token) ?? null,
      worker_boot_id: stringValue(row.worker_boot_id) ?? null,
      staged_output: isRecord(row.staged_output) ? row.staged_output : null,
    }];
  }).sort((left, right) => left.day_index - right.day_index);
}

function normalizeQueuedDayJobStatus(
  value: unknown,
): QueuedDayJobStatus | undefined {
  return value === "queued" || value === "generating" ||
      value === "generated" || value === "failed" ||
      value === "retrying" || value === "cancelled" ||
      value === "ready_to_persist"
    ? value
    : undefined;
}
async function runParallelWeekGeneration(
  admin: SupabaseAdminClient,
  prepared: PreparedGeneration,
  generationID: string,
  weeklyPlanID: string,
  progress: PerDayGenerationSnapshot,
  dependencies: GenerateWeekDependencies,
): Promise<{ payload: Record<string, unknown> } | { response: Response }> {
  const bootID = generationBootID();
  registerShutdownTracking(generationID, bootID, []);
  const loopStartedAt = Date.now();
  let dayJobsClaimed = 0;
  let dayJobsCompleted = 0;
  let dayJobsFailed = 0;

  let latestProgress = {
    ...normalizeStaleRunningDays(progress),
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
  const heartbeatIntervalMS = dayGenerationHeartbeatMS(dependencies);
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
      const retryContext = dayGenerationRetryContext(
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
        dependencies,
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

  if (cancelled && hasActiveParallelDayGeneration(latestProgress)) {
    const summary = weekGenerationStatusSummary(
      latestProgress,
      "running",
      isTerminalDayGenerationState,
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

  if (hasActiveParallelDayGeneration(latestProgress)) {
    const summary = weekGenerationStatusSummary(
      latestProgress,
      "running",
      isTerminalDayGenerationState,
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
  );
}

function progressReconciledWithDayJobs(
  progress: PerDayGenerationSnapshot,
  jobs: QueuedDayJobRecord[],
): PerDayGenerationSnapshot {
  const jobsByDate = new Map(jobs.map((job) => [job.scheduled_date, job]));
  return {
    ...progress,
    days: progress.days.map((day) => {
      const job = jobsByDate.get(day.scheduled_date);
      if (!job) return day;
      const status: DayGenerationStatus = job.status === "generated"
        ? "completed"
        : job.status === "failed" || job.status === "cancelled"
        ? "failed"
        : job.status === "generating" || job.status === "ready_to_persist"
        ? "running"
        : "pending";
      return {
        scheduled_date: day.scheduled_date,
        status,
        attempts: job.attempt_count ?? 0,
        daily_card_id: job.daily_card_id ?? undefined,
        started_at: job.started_at ?? undefined,
        completed_at: job.completed_at ?? undefined,
        heartbeat_at: job.heartbeat_at ?? undefined,
        error_code: job.error_code ?? undefined,
      };
    }),
    updated_at: new Date().toISOString(),
  };
}

function nextParallelDayGenerationIndex(
  progress: PerDayGenerationSnapshot,
  inFlight: Map<number, unknown>,
): number {
  return progress.days.findIndex((day, index) =>
    !inFlight.has(index) && shouldRunDayGeneration(day)
  );
}

function activeParallelDayGenerationCount(
  progress: PerDayGenerationSnapshot,
): number {
  return progress.days.filter((day) =>
    day.status === "running" && !isRunningDayStale(day)
  ).length;
}

function hasActiveParallelDayGeneration(
  progress: PerDayGenerationSnapshot,
): boolean {
  return activeParallelDayGenerationCount(progress) > 0;
}

function liveParallelDayJobCount(
  jobs: Array<{
    status?: unknown;
    heartbeat_at?: unknown;
    started_at?: unknown;
  }>,
  staleThresholdMS: number,
  now = Date.now(),
): number {
  return jobs.filter((job) =>
    job.status === "generating" &&
    !isQueuedDayJobStale(job, staleThresholdMS, now)
  ).length;
}

function parallelWeekGenerationConcurrency(): number {
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
  prepared: PreparedGeneration,
  generationID: string,
  weeklyPlanID: string,
  scheduledDate: string,
  dayIndex: number,
  attempts: number,
  dependencies: GenerateWeekDependencies,
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
    const rawOutput = await generateDayOutput(
      prepared,
      scheduledDate,
      dayIndex,
      dependencies,
      generationID,
      "parallel_day_generation",
      retryContext,
    );
    const output = validateGeneratedDayOutput(
      rawOutput,
      scheduledDate,
      dayIndex,
    );
    assertDayRespectsWeeklyBriefContext(
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
  prepared: PreparedGeneration,
  weeklyPlanID: string,
  job: QueuedDayJobRecord,
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
    assertDayRespectsWeeklyBriefContext(
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
  prepared: PreparedGeneration,
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

async function finalizeParallelWeekGeneration(
  admin: SupabaseAdminClient,
  prepared: PreparedGeneration,
  generationID: string,
  weeklyPlanID: string,
  progress: PerDayGenerationSnapshot,
): Promise<{ payload: Record<string, unknown> } | { response: Response }> {
  const completedAt = new Date().toISOString();
  const savedCards = await readSavedDailyCards(
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

  const finalProgress = {
    ...mergeSavedDailyCardsIntoProgress(progress, savedCardsForRun),
    updated_at: completedAt,
  };
  const summary = weekGenerationStatusSummary(
    finalProgress,
    savedCardsForRun.length === 0 ? "failed" : "completed",
    isTerminalDayGenerationState,
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

  const strategy = makeInitialWeekStrategyOutput(prepared.inputSnapshot);
  if (summary.saved_day_count === summary.total_day_count) {
    const generated: GeneratedWeekOutput = {
      ...strategy,
      daily_cards: savedCardsForRun,
      idea_bank: [],
    };
    const payload = makeGenerateWeekDraftResponse(
      generationID,
      weeklyPlanID,
      generated,
      savedCardsForRun,
      [],
      completedAt,
    );
    const completedResult = await completeGenerationRun(
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

async function completePartialGenerationRun(
  admin: SupabaseAdminClient,
  generationID: string,
  weeklyPlanID: string,
  progress: PerDayGenerationSnapshot,
  completedAt: string,
): Promise<{ ok: true } | { response: Response }> {
  const { error } = await admin
    .from("weekly_generation_runs")
    .update({
      weekly_plan_id: weeklyPlanID,
      status: "completed",
      output_snapshot: progress,
      error_code: "partial_generation",
      completed_at: completedAt,
    })
    .eq("id", generationID);
  if (error) {
    return generationPersistFailure("complete_partial_generation_run", error);
  }
  return { ok: true };
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

  const { data, error } = await admin
    .from("weekly_generation_day_jobs")
    .update({
      status: "retrying",
      error_code: null,
      error_message: null,
      completed_at: null,
      heartbeat_at: null,
    })
    .eq("generation_run_id", generationID)
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", runResult.run.creator_id)
    .eq("scheduled_date", scheduledDate)
    .eq("status", "failed")
    .select(queuedDayJobSelect())
    .maybeSingle();

  if (error) {
    return generationPersistFailure("retry_generation_day_job", error).response;
  }
  if (!isRecord(data)) {
    return jsonResponse({ error: "day_job_not_retryable" }, 409);
  }

  logGenerationLifecycle({
    action: "retry_day",
    phase: "day_job_retrying",
    status: "retrying",
    generation_id: generationID,
    weekly_plan_id: stringValue(runResult.run.weekly_plan_id) ??
      stringValue(data.weekly_plan_id) ?? null,
    week_start_date: null,
    scheduled_date: scheduledDate,
    day_index: numberValue(data.day_index) ?? null,
    duration_ms: null,
    day_guidance_present: null,
    day_guidance_chars: null,
  });

  return jsonResponse({
    generation_id: generationID,
    weekly_plan_id: stringValue(runResult.run.weekly_plan_id) ??
      stringValue(data.weekly_plan_id) ?? null,
    status: "running",
    day: queuedDayJobStatusResponse(
      normalizeQueuedDayJobRows([data])[0],
    ),
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
  const { data: dayJobsData, error: dayJobsError } = await admin
    .from("weekly_generation_day_jobs")
    .select("id")
    .eq("generation_run_id", generationID)
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", runResult.run.creator_id)
    .limit(1);

  if (dayJobsError) {
    return generationPersistFailure(
      "cancel_generation_day_jobs_lookup",
      dayJobsError,
    ).response;
  }

  // Queued mode: delegate to existing queued cancel flow.
  if (dayJobsData && dayJobsData.length > 0) {
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

  const { error: updateError } = await admin
    .from("weekly_generation_runs")
    .update({
      status: "failed",
      error_code: "generation_cancelled",
      completed_at: new Date().toISOString(),
    })
    .eq("id", generationID);

  if (updateError) {
    return generationPersistFailure(
      "cancel_generation_run",
      updateError,
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

  const { error } = await admin
    .from("weekly_generation_day_jobs")
    .update({
      status: "cancelled",
      completed_at: new Date().toISOString(),
    })
    .eq("generation_run_id", generationID)
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", runResult.run.creator_id)
    .in("status", ["queued", "retrying", "generating", "ready_to_persist"]);

  if (error) {
    return generationPersistFailure("cancel_generation_day_jobs", error)
      .response;
  }

  const { error: cancelError } = await admin
    .from("weekly_generation_runs")
    .update({
      status: "failed",
      error_code: "generation_cancelled",
      completed_at: new Date().toISOString(),
    })
    .eq("id", generationID);

  if (cancelError) {
    return generationPersistFailure("cancel_generation_run", cancelError)
      .response;
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
  const { data, error } = await admin
    .from("weekly_generation_runs")
    .select("id,workspace_id,creator_id,status,weekly_plan_id,error_code")
    .eq("id", generationID)
    .eq("workspace_id", session.workspaceID)
    .maybeSingle();

  if (error) {
    return generationPersistFailure("read_generation_run", error);
  }
  if (!isRecord(data)) {
    return {
      response: jsonResponse({ error: "invalid_generation_payload" }, 404),
    };
  }
  return { run: data as GenerationRunStatusRecord };
}

function isGenerationRunRecordCancelled(
  run: Record<string, unknown> | null | undefined,
): boolean {
  const status = stringValue(run?.status);
  return status === "cancelled" ||
    (status === "failed" &&
      stringValue(run?.error_code) === "generation_cancelled");
}

async function isGenerationRunCancelled(
  admin: SupabaseAdminClient,
  generationID: string,
): Promise<boolean> {
  const { data } = await admin
    .from("weekly_generation_runs")
    .select("status,error_code")
    .eq("id", generationID)
    .maybeSingle();
  return isGenerationRunRecordCancelled(isRecord(data) ? data : null);
}

async function readGenerationStatus(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  body: Record<string, unknown>,
  env: EnvReader,
  dependencies: GenerateWeekDependencies,
): Promise<Response> {
  const generationID = stringValue(body.generation_id);
  const creatorID = stringValue(body.creator_id);
  if (
    !isUUID(generationID) || (creatorID !== undefined && !isUUID(creatorID))
  ) {
    return jsonResponse({ error: "invalid_generation_payload" }, 400);
  }

  const { data, error } = await admin
    .from("weekly_generation_runs")
    .select(
      "id,workspace_id,creator_id,weekly_setup_id,requested_by_member_id,status,weekly_plan_id,output_snapshot,input_snapshot,error_code,completed_at,model,generation_scope,target_daily_card_id,target_scheduled_date",
    )
    .eq("id", generationID)
    .eq("workspace_id", session.workspaceID)
    .maybeSingle();

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
    if (stringValue(runRecord.status) === "running") {
      dispatchQueuedDayJobRecovery(
        admin,
        generationID,
        runRecord,
        queuedJobsResult.jobs,
        env,
        dependencies,
      );
    }
    return await readQueuedGenerationStatus(
      admin,
      generationID,
      runRecord,
      queuedJobsResult.jobs,
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
          dependencies,
        );
      }
      return await readCompletedPerDayGenerationStatus(
        admin,
        generationID,
        run,
        session,
        inputSnapshot,
        progress,
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
          dependencies,
        );
      }
      const summary = weekGenerationStatusSummary(
        progress,
        "failed",
        isTerminalDayGenerationState,
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
    await markGenerationRunFailed(
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

  if (run.generation_scope === "day") {
    return await resumeSingleDayGeneration(
      admin,
      generationID,
      run,
      session,
      inputSnapshot,
      env,
      dependencies,
    );
  }

  let progress = normalizePerDayGenerationSnapshot(
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
      dependencies,
    );
  }
  const normalizedProgress = normalizeStaleRunningDays(progress);
  if (normalizedProgress !== progress) {
    const updateResult = await updateGenerationProgress(
      admin,
      generationID,
      normalizedProgress,
    );
    if ("response" in updateResult) {
      return updateResult.response;
    }
    progress = normalizedProgress;
  }
  if (allDaysCompleted(progress)) {
    const finalizeResult = await finalizePerDayGeneration(
      admin,
      generationID,
      run,
      session,
      inputSnapshot,
      progress,
    );
    if ("response" in finalizeResult) {
      return finalizeResult.response;
    }
    return jsonResponse(finalizeResult.payload);
  }
  if (allDaysTerminal(progress)) {
    const finalizeResult = await finalizeTerminalPerDayGeneration(
      admin,
      generationID,
      run,
      session,
      inputSnapshot,
      progress,
    );
    if ("response" in finalizeResult) {
      return finalizeResult.response;
    }
    return jsonResponse(finalizeResult.payload);
  }

  const preparedResult = prepareGenerationFromRun(
    env,
    run,
    session,
    inputSnapshot,
  );
  if ("response" in preparedResult) {
    return preparedResult.response;
  }

  const scheduleResult = await scheduleNextPendingDayGeneration(
    admin,
    generationID,
    preparedResult.prepared,
    progress,
    dependencies,
  );
  if ("response" in scheduleResult) {
    return scheduleResult.response;
  }

  const latestProgress = scheduleResult.progress;
  const summary = weekGenerationStatusSummary(
    latestProgress,
    "running",
    isTerminalDayGenerationState,
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

async function readQueuedDayJobsForRun(
  admin: SupabaseAdminClient,
  generationID: string,
  workspaceID: string,
  creatorID: string,
): Promise<{ jobs: QueuedDayJobRecord[] } | { response: Response }> {
  const { data, error } = await admin
    .from("weekly_generation_day_jobs")
    .select(queuedDayJobSelect())
    .eq("generation_run_id", generationID)
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .order("day_index", { ascending: true });

  if (error) {
    return generationPersistFailure("read_generation_day_jobs", error);
  }

  return { jobs: normalizeQueuedDayJobRows(data) };
}

// Fire-and-forget background recovery: claim/reclaim queued/stale day jobs
// and process them without blocking the status response.
function dispatchQueuedDayJobRecovery(
  admin: SupabaseAdminClient,
  generationID: string,
  run: GenerationRunStatusRecord,
  jobs: QueuedDayJobRecord[],
  env: EnvReader,
  dependencies: GenerateWeekDependencies,
): void {
  if (!shouldDispatchQueuedDayJobRecovery(jobs)) {
    return;
  }

  const inputSnapshot = normalizeStoredInputSnapshot(run.input_snapshot);
  if (!inputSnapshot) return;

  const preparedResult = prepareGenerationFromRun(env, run, {
    workspaceID: stringValue(run.workspace_id) ?? "",
    memberID: stringValue(run.requested_by_member_id) ?? "",
  } as VerifiedDeviceSession, inputSnapshot);
  if ("response" in preparedResult) return;

  const weeklyPlanID = stringValue(run.weekly_plan_id);
  if (!weeklyPlanID || !isUUID(weeklyPlanID)) return;

  scheduleBackgroundGeneration(
    runParallelWeekGeneration(
      admin,
      preparedResult.prepared,
      generationID,
      weeklyPlanID,
      initialParallelWeekGenerationSnapshot(
        inputSnapshot.week_start_date,
        weeklyPlanID,
        makeInitialWeekStrategyOutput(inputSnapshot),
      ),
      dependencies,
    ),
    dependencies,
  );
}

function shouldDispatchQueuedDayJobRecovery(
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
  ) > 0;
}

async function readQueuedGenerationStatus(
  admin: SupabaseAdminClient,
  generationID: string,
  run: GenerationRunStatusRecord,
  jobs: QueuedDayJobRecord[],
): Promise<Response> {
  const weeklyPlanID = stringValue(run.weekly_plan_id) ??
    jobs.find((job) => isUUID(job.weekly_plan_id))?.weekly_plan_id ?? null;
  const summary = queuedDayJobStatusSummary(jobs);
  const responseStatus = summary.overall_status === "completed"
    ? "draft"
    : summary.overall_status;
  const dailyCardsResult = weeklyPlanID
    ? await readSavedDailyCards(
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

function isDraftResponseSnapshot(
  value: unknown,
): value is GenerateWeekDraftResponse {
  return isRecord(value) &&
    isUUID(stringValue(value.generation_id)) &&
    isUUID(stringValue(value.weekly_plan_id)) &&
    value.status === "draft" &&
    Array.isArray(value.daily_cards) &&
    Array.isArray(value.idea_bank);
}

function isDayDraftResponseSnapshot(
  value: unknown,
): value is RegenerateDayDraftResponse {
  return isRecord(value) &&
    isUUID(stringValue(value.generation_id)) &&
    isUUID(stringValue(value.weekly_plan_id)) &&
    value.status === "draft" &&
    typeof value.target_scheduled_date === "string" &&
    isRecord(value.daily_card);
}

function initialSingleDayGenerationSnapshot(
  request: RegenerateDayRequest,
): SingleDayGenerationSnapshot {
  return {
    kind: "single_day_generation_v1",
    scheduled_date: request.scheduled_date,
    preserve_manual_edits: request.preserve_manual_edits,
    status: "pending",
    updated_at: new Date().toISOString(),
  };
}

function normalizeSingleDayGenerationSnapshot(
  value: unknown,
  run: GenerationRunStatusRecord,
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
    updated_at: stringValue(value.updated_at) ?? new Date().toISOString(),
  };
}

async function resumeSingleDayGeneration(
  admin: SupabaseAdminClient,
  generationID: string,
  run: GenerationRunStatusRecord,
  session: VerifiedDeviceSession,
  inputSnapshot: GenerationInputSnapshot,
  env: EnvReader,
  dependencies: GenerateWeekDependencies,
): Promise<Response> {
  const progress = normalizeSingleDayGenerationSnapshot(
    run.output_snapshot,
    run,
  );
  const weeklyPlanID = stringValue(run.weekly_plan_id);
  const targetCardID = stringValue(run.target_daily_card_id);
  const scheduledDate = stringValue(run.target_scheduled_date);
  if (!progress || !isUUID(weeklyPlanID) || !scheduledDate) {
    await markGenerationRunFailed(
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

  const providers = aiProviderConfigs(env);
  const mockEnabled = env.get("MCO_AI_MOCK") === "1";
  if (!mockEnabled && providers.length === 0) {
    return jsonResponse({ error: "missing_openai_api_key" }, 500);
  }

  const existingCards = inputSnapshot.existing_week_cards ?? [];
  const targetCard = targetCardID
    ? existingCards.find((card) =>
      card.id === targetCardID && card.scheduled_date === scheduledDate
    )
    : existingCards.find((card) => card.scheduled_date === scheduledDate);
  if (targetCardID && !targetCard) {
    await markGenerationRunFailed(
      admin,
      generationID,
      "daily_card_not_found",
    );
    return jsonResponse({
      generation_id: generationID,
      status: "failed",
      error: "daily_card_not_found",
    });
  }

  const prepared: PreparedDayGeneration = {
    request: {
      action: "regenerate_day",
      creator_id: run.creator_id,
      weekly_plan_id: weeklyPlanID,
      scheduled_date: scheduledDate,
      preserve_manual_edits: progress.preserve_manual_edits,
      mock: false,
      response_mode: "async",
    },
    session: {
      ...session,
      memberID: stringValue(run.requested_by_member_id) ?? session.memberID,
    },
    plan: {
      id: weeklyPlanID,
      week_start_date: inputSnapshot.week_start_date,
      weekly_setup_id: stringValue(run.weekly_setup_id),
      status: "draft",
    },
    targetCard: targetCard as CardIdentityRecord,
    inputSnapshot,
    providers,
    model: stringValue(run.model) ?? providerModelSummary(providers),
    mockEnabled,
  };

  const isActive = progress.status === "running" &&
    progress.started_at &&
    Date.now() - Date.parse(progress.started_at) <= 10 * 60 * 1000;
  if (!isActive) {
    const scheduleResult = await scheduleSingleDayGeneration(
      admin,
      generationID,
      prepared,
      { ...progress, status: "pending", started_at: undefined },
      dependencies,
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
): Promise<Response> {
  const weeklyPlanID = stringValue(run.weekly_plan_id) ??
    progress.weekly_plan_id;
  const savedCards = weeklyPlanID && isUUID(weeklyPlanID)
    ? await readSavedDailyCards(
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
  );
  const summary = weekGenerationStatusSummary(
    mergedProgress,
    stringValue(run.status) ?? "completed",
    isTerminalDayGenerationState,
  );
  const strategy = makeInitialWeekStrategyOutput(inputSnapshot);
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
  dependencies: GenerateWeekDependencies,
): Promise<Response> {
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
      isTerminalDayGenerationState,
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

  if (stringValue(run.status) === "running") {
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
    const normalizedProgress = normalizeStaleRunningDays(
      progress,
      dayJobHeartbeats,
    );
    if (normalizedProgress !== progress) {
      const updateResult = await updateGenerationProgress(
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

  const savedCards = await readSavedDailyCards(
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
  );
  if (mergedProgress !== progress) {
    const updateResult = await updateGenerationProgress(
      admin,
      generationID,
      mergedProgress,
    );
    if ("response" in updateResult) {
      return updateResult.response;
    }
    progress = mergedProgress;
  }

  if (
    stringValue(run.status) === "running" &&
    isParallelWeekGenerationTerminal(progress)
  ) {
    const preparedResult = prepareGenerationFromRun(
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
    );
    if ("response" in finalized) {
      return finalized.response;
    }
    return jsonResponse(finalized.payload);
  }

  if (
    stringValue(run.status) === "running" &&
    shouldResumeParallelWeekGeneration(progress)
  ) {
    const preparedResult = prepareGenerationFromRun(
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
    scheduleBackgroundGeneration(
      runParallelWeekGeneration(
        admin,
        preparedResult.prepared,
        generationID,
        weeklyPlanID,
        progress,
        dependencies,
      ),
      dependencies,
    );
  }

  const summary = weekGenerationStatusSummary(
    progress,
    stringValue(run.status) ?? "running",
    isTerminalDayGenerationState,
  );
  const responseStatus = summary.overall_status === "completed"
    ? "draft"
    : summary.overall_status;
  return jsonResponse({
    generation_id: generationID,
    weekly_plan_id: weeklyPlanID,
    status: responseStatus,
    strategy_summary: progress.strategy_summary ??
      makeInitialWeekStrategyOutput(inputSnapshot).strategy_summary,
    warnings: progress.warnings ?? [],
    assumptions: progress.assumptions ?? [],
    daily_cards: savedCardsForRun,
    idea_bank: [],
    source_summary: progress.source_summary ??
      makeInitialWeekStrategyOutput(inputSnapshot).source_summary,
    generated_at: stringValue(run.completed_at) ?? progress.updated_at,
    error: summary.overall_status === "failed"
      ? stringValue(run.error_code) ?? "invalid_generated_week"
      : undefined,
    ...summary,
    poll_after_seconds: summary.overall_status === "running" ? 5 : null,
  });
}

function shouldResumeParallelWeekGeneration(
  progress: PerDayGenerationSnapshot,
): boolean {
  if (!progress.days.some(shouldRunDayGeneration)) {
    return false;
  }
  return activeParallelDayGenerationCount(progress) <
    parallelWeekGenerationConcurrency();
}

function isParallelWeekGenerationTerminal(
  progress: PerDayGenerationSnapshot,
): boolean {
  return progress.days.length > 0 &&
    progress.days.every(isTerminalDayGenerationState);
}

function normalizeStaleRunningDays(
  progress: PerDayGenerationSnapshot,
  dayJobHeartbeats?: Map<number, string | undefined>,
): PerDayGenerationSnapshot {
  let changed = false;
  const days = progress.days.map((day, index) => {
    if (day.status !== "running") return day;

    const effectiveHeartbeat = dayJobHeartbeats?.get(index) ?? day.heartbeat_at;
    const effectiveDay: DayGenerationState = effectiveHeartbeat !==
        day.heartbeat_at
      ? { ...day, heartbeat_at: effectiveHeartbeat }
      : day;

    if (isRunningDayStale(effectiveDay)) {
      changed = true;
      return staleDayFailure(effectiveDay);
    }
    return effectiveDay !== day ? effectiveDay : day;
  });
  return changed
    ? { ...progress, days, updated_at: new Date().toISOString() }
    : progress;
}

function shouldRunDayGeneration(day: DayGenerationState): boolean {
  if (day.status === "pending") {
    return true;
  }
  if (day.status === "failed") {
    return day.attempts < maxDayGenerationAttempts();
  }
  return day.status === "running" && isRunningDayStale(day) &&
    day.attempts < maxDayGenerationAttempts();
}

function isTerminalDayGenerationState(day: DayGenerationState): boolean {
  return day.status === "completed" ||
    (day.status === "failed" && day.attempts >= maxDayGenerationAttempts());
}

function normalizeStoredInputSnapshot(
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

function requestFromRun(
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

async function scheduleNextPendingDayGeneration(
  admin: SupabaseAdminClient,
  generationID: string,
  prepared: PreparedGeneration,
  progress: PerDayGenerationSnapshot,
  dependencies: GenerateWeekDependencies,
): Promise<
  { progress: PerDayGenerationSnapshot } | { response: Response }
> {
  const activeIndex = progress.days.findIndex((day) =>
    day.status === "running" && !isRunningDayStale(day)
  );
  if (activeIndex >= 0) {
    return { progress };
  }

  const normalizedProgress = {
    ...progress,
    days: progress.days.map((day) =>
      day.status === "running" && isRunningDayStale(day)
        ? staleDayFailure(day)
        : day
    ),
  };
  const dayIndex = normalizedProgress.days.findIndex(shouldRunDayGeneration);
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

function staleDayFailure(day: DayGenerationState): DayGenerationState {
  if (day.attempts < maxDayGenerationAttempts()) {
    return {
      ...day,
      status: "pending",
      started_at: undefined,
      heartbeat_at: undefined,
    };
  }

  const completedAt = new Date().toISOString();
  return {
    ...day,
    status: "failed",
    completed_at: completedAt,
    error_code: "generation_timeout",
    output: undefined,
  };
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
    } else if (allDaysTerminal(completedProgress)) {
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
    if (allDaysTerminal(failedProgress)) {
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
      isTerminalDayGenerationState,
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
    inputSnapshot,
    completedOutputs,
    baseProgress,
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
    isTerminalDayGenerationState,
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

function makeGeneratedWeekOutputFromCompletedDays(
  inputSnapshot: GenerationInputSnapshot,
  dayOutputs: GeneratedDayOutput[],
  progress: PerDayGenerationSnapshot,
): GeneratedWeekOutput {
  const strategy = makeInitialWeekStrategyOutput(inputSnapshot);
  return {
    strategy_summary: progress.strategy_summary ??
      combineNonBlankStrings(
        dayOutputs.map((output) => output.strategy_note),
        strategy.strategy_summary,
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
        strategy.source_summary,
      ),
  };
}

function combineNonBlankStrings(values: string[], fallback: string): string {
  const combined = uniqueNonBlankStrings(values).join(" ");
  return combined.length > 0 ? combined : fallback;
}

function uniqueNonBlankStrings(values: string[]): string[] {
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

async function updateGenerationProgress(
  admin: SupabaseAdminClient,
  generationID: string,
  progress: PerDayGenerationSnapshot | SingleDayGenerationSnapshot,
): Promise<{ ok: true } | { response: Response }> {
  const { error } = await admin
    .from("weekly_generation_runs")
    .update({ output_snapshot: progress })
    .eq("id", generationID)
    .eq("status", "running");

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

function allDaysCompleted(progress: PerDayGenerationSnapshot): boolean {
  return progress.days.length === 7 &&
    progress.days.every((day) => day.status === "completed" && day.output);
}

function allDaysTerminal(progress: PerDayGenerationSnapshot): boolean {
  return progress.days.length === 7 &&
    progress.days.every(isTerminalDayGenerationState);
}

function isRunningDayStale(day: DayGenerationState): boolean {
  const lastLiveness = day.heartbeat_at ?? day.started_at;
  if (!lastLiveness) {
    return false;
  }
  return Date.now() - Date.parse(lastLiveness) > runningDayStaleMS();
}

function isQueuedDayJobStale(
  job: {
    heartbeat_at?: unknown;
    started_at?: unknown;
  },
  staleThresholdMS: number,
  now = Date.now(),
): boolean {
  const lastLiveness = stringValue(job.heartbeat_at) ??
    stringValue(job.started_at);
  if (!lastLiveness) {
    return false;
  }
  const lastLivenessMS = Date.parse(lastLiveness);
  return Number.isFinite(lastLivenessMS) &&
    now - lastLivenessMS > staleThresholdMS;
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
  const liveRunningCount = liveParallelDayJobCount(
    jobs,
    staleThresholdMS,
    now,
  );
  return Math.max(0, concurrency - liveRunningCount);
}

function dayGenerationHeartbeatMS(
  dependencies: GenerateWeekDependencies,
): number {
  const configured = dependencies.dayHeartbeatIntervalMS;
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

function runningDayStaleMS(): number {
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

function maxDayGenerationAttempts(): number {
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

async function readCreator(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
): Promise<{ creator: CreatorRecord } | { response: Response }> {
  const { data, error } = await admin
    .from("creators")
    .select("id,display_name,default_timezone")
    .eq("id", creatorID)
    .eq("workspace_id", workspaceID)
    .eq("status", "active")
    .maybeSingle();

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
  const { data, error } = await admin
    .from("weekly_plans")
    .select("id")
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("week_start_date", weekStartDate)
    .eq("status", "published")
    .maybeSingle();

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
  const select =
    "id,creator_profile_id,week_start_date,status,location,workout_race_schedule,family_travel_moments,energy_constraints,shooting_constraints,no_go_topics,selected_sources,notes";

  if (request.weekly_setup_id) {
    const { data, error } = await admin
      .from("weekly_setups")
      .select(select)
      .eq("workspace_id", workspaceID)
      .eq("creator_id", request.creator_id)
      .eq("id", request.weekly_setup_id)
      .maybeSingle();

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
    return { setup: data as Record<string, unknown> };
  }

  const { data, error } = await admin
    .from("weekly_setups")
    .select(select)
    .eq("workspace_id", workspaceID)
    .eq("creator_id", request.creator_id)
    .eq("week_start_date", request.week_start_date)
    .order("updated_at", { ascending: false })
    .limit(1);

  if (error) {
    return {
      response: jsonResponse({ error: "weekly_setup_lookup_failed" }, 500),
    };
  }

  return { setup: (data?.[0] ?? null) as Record<string, unknown> | null };
}

async function buildGenerationInput(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  weekStartDate: string,
  creator: CreatorRecord,
  weeklySetup: Record<string, unknown> | null,
): Promise<{ input: GenerationInputSnapshot } | { response: Response }> {
  const [
    profile,
    confirmedReferences,
    referenceExtractions,
    recentArchive,
    ideaBank,
    patterns,
    trends,
    audioOptions,
    brandBriefs,
    keyMoments,
  ] = await Promise.all([
    readRows(
      admin,
      "creator_profiles",
      "id,status,version,positioning,voice_rules,content_pillars,caption_style,never_say,weekly_routine,family_race_travel_context,language_preferences,recurring_formats,trend_filter_rules,influencer_adaptation_rules",
      workspaceID,
      creatorID,
      (query) =>
        query.eq("status", "active").order("version", { ascending: false })
          .limit(1),
    ),
    readRows(
      admin,
      "source_references",
      "id,source_type,source_url,manual_notes,analysis_confidence,status,created_at",
      workspaceID,
      creatorID,
      (query) =>
        query.eq("status", "confirmed").order("created_at", {
          ascending: false,
        }).limit(12),
    ),
    readRows(
      admin,
      "reference_extractions",
      "id,source_reference_id,extraction_kind,extracted_payload,confidence,status,created_at",
      workspaceID,
      creatorID,
      (query) =>
        query.eq("status", "confirmed").order("updated_at", {
          ascending: false,
        }).limit(20),
    ),
    readRows(
      admin,
      "archive_entries",
      "id,archive_date,decision,output_line,has_post_thumbnail,daily_cards(title,content_pillar,shootability,source_note)",
      workspaceID,
      creatorID,
      (query) => query.order("archive_date", { ascending: false }).limit(20),
    ),
    readRows(
      admin,
      "ideas",
      "id,title,summary,tags,suggested_use,shootability,fit_score,notes,status,source_reference_id,source_pattern_id,source_trend_id,source_audio_option_id",
      workspaceID,
      creatorID,
      (query) =>
        query.in("status", ["saved", "scheduled"]).order("updated_at", {
          ascending: false,
        }).limit(30),
    ),
    readRows(
      admin,
      "patterns",
      "id,title,pattern_type,summary,fit_notes,avoid_notes,creator_adaptation,creator_fit_score,status",
      workspaceID,
      creatorID,
      (query) =>
        query.in("status", ["approved", "used"]).order("updated_at", {
          ascending: false,
        }).limit(12),
    ),
    readRows(
      admin,
      "trends",
      "id,title,summary,timing_recommendation,creator_adaptation,creator_fit_score,status",
      workspaceID,
      creatorID,
      (query) =>
        query.in("status", ["approved", "used"]).order("updated_at", {
          ascending: false,
        }).limit(12),
    ),
    readRows(
      admin,
      "audio_options",
      "id,title,artist_or_creator,usage_notes,availability_confidence,verification_note,status",
      workspaceID,
      creatorID,
      (query) =>
        query.in("status", ["verified_available", "used"]).order(
          "updated_at",
          { ascending: false },
        ).limit(12),
    ),
    readRows(
      admin,
      "brand_briefs",
      "id,brand_name,campaign_title,deliverable,due_date,post_date,review_deadline,mandatory_points,must_avoid,required_tags,disclosure_requirement,tone,notes,status",
      workspaceID,
      creatorID,
      (query) =>
        query.in("status", [
          "active",
          "scheduled",
          "awaiting_approval",
          "approved",
        ]).order("updated_at", { ascending: false }).limit(12),
    ),
    readRows(
      admin,
      "key_moments",
      "id,name,moment_date,location,kind,content_angle,required_scenes,pre_event_notes,post_event_notes,status",
      workspaceID,
      creatorID,
      (query) =>
        query.in("status", ["upcoming", "active"])
          .gte("moment_date", requestWeekWindowEnd(weekStartDate, -7))
          .lte("moment_date", requestWeekWindowEnd(weekStartDate, 21))
          .order("moment_date", { ascending: true })
          .limit(12),
    ),
  ]);

  const profileRow = rowsOrEmpty(profile)[0] ?? null;

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
      confirmed_references: rowsOrEmpty(confirmedReferences),
      reference_extractions: rowsOrEmpty(referenceExtractions),
      recent_archive: rowsOrEmpty(recentArchive),
      idea_bank: rowsOrEmpty(ideaBank),
      patterns: rowsOrEmpty(patterns),
      trends: rowsOrEmpty(trends),
      audio_options: rowsOrEmpty(audioOptions),
      brand_briefs: rowsOrEmpty(brandBriefs),
      key_moments: rowsOrEmpty(keyMoments),
    },
  };
}

function rowsOrEmpty(
  result: { rows: Record<string, unknown>[] } | { response: Response },
): Record<string, unknown>[] {
  return "rows" in result ? result.rows : [];
}

function requestWeekWindowEnd(
  weekStartDate: string,
  offsetDays: number,
): string {
  const [year, month, day] = weekStartDate.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  date.setUTCDate(date.getUTCDate() + offsetDays);
  return date.toISOString().slice(0, 10);
}

async function readRows(
  admin: SupabaseAdminClient,
  table: string,
  select: string,
  workspaceID: string,
  creatorID: string,
  configure: (query: any) => any,
): Promise<{ rows: Record<string, unknown>[] } | { response: Response }> {
  const query = configure(
    admin
      .from(table)
      .select(select)
      .eq("workspace_id", workspaceID)
      .eq("creator_id", creatorID),
  );
  const { data, error } = await query;
  if (error) {
    return { response: jsonResponse({ error: `${table}_lookup_failed` }, 500) };
  }
  return { rows: (data ?? []) as Record<string, unknown>[] };
}

async function createGenerationRun(
  admin: SupabaseAdminClient,
  workspaceID: string,
  request: GenerateWeekRequest,
  memberID: string,
  model: string,
  inputSnapshot: GenerationInputSnapshot,
): Promise<{ run: RunRecord } | { response: Response }> {
  const { data, error } = await admin
    .from("weekly_generation_runs")
    .insert({
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
    })
    .select("id")
    .single();

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
  const { data, error } = await admin
    .from("weekly_generation_runs")
    .insert({
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
    })
    .select("id")
    .single();
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
  const { error } = await admin
    .from("weekly_generation_runs")
    .update({ weekly_plan_id: weeklyPlanID })
    .eq("id", generationID)
    .eq("status", "running");

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
  const { data, error } = await admin
    .from("daily_cards")
    .update(values)
    .eq("id", existing.id)
    .eq("workspace_id", prepared.session.workspaceID)
    .eq("creator_id", prepared.request.creator_id)
    .eq("weekly_plan_id", prepared.request.weekly_plan_id)
    .eq("scheduled_date", prepared.request.scheduled_date)
    .eq("status", "draft")
    .select("id,scheduled_date")
    .maybeSingle();
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

function generatedDailyCardValues(
  card: GeneratedDailyCard,
): Record<string, unknown> {
  return {
    status: "draft",
    title: card.title,
    why_today: card.why_today,
    growth_job: card.growth_job,
    content_pillar: card.content_pillar,
    shootability: card.shootability,
    estimated_shoot_minutes: card.estimated_shoot_minutes,
    energy_required: card.energy_required,
    language_mode: card.language_mode,
    scene_list: card.scene_list,
    script: card.script,
    no_voiceover_version: card.no_voiceover_version,
    on_screen_text: card.on_screen_text,
    caption: card.caption,
    cta: card.cta,
    hashtags: card.hashtags,
    cover_text: card.cover_text,
    post_instructions: {
      instructions: card.post_instructions,
      audio_option_notes: card.audio_option_notes,
      format: card.format,
      primary_surface: card.primary_surface,
      duration_seconds: card.duration_seconds,
      hook: card.hook,
      weekly_brief_anchor: card.weekly_brief_anchor,
      brief_alignment: card.brief_alignment,
      brief_context_tags: card.brief_context_tags,
      save_share_reason: card.save_share_reason,
      shot_timeline: card.shot_timeline,
      voiceover_timeline: card.voiceover_timeline,
      silent_version_timeline: card.silent_version_timeline,
      on_screen_text_timeline: card.on_screen_text_timeline,
      caption_backup_detail: card.caption_backup_detail,
      creator_fit_score: card.creator_fit_score,
    },
    brand_event_notes: card.brand_event_notes || null,
    backup_story: { line: card.backup_story, detail: card.backup_story_detail },
    backup_caption_only: {
      line: card.backup_caption_only,
      detail: card.caption_backup_detail,
    },
    risk_notes: card.risk_notes,
    assumptions: card.assumptions,
    source_note: card.source_note,
    storyboard_thumbnail_assets: [],
  };
}

async function replaceDailyCardReferences(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  dailyCardID: string,
  card: GeneratedDailyCard,
): Promise<{ ok: true } | { response: Response }> {
  const { error: clearError } = await admin
    .from("daily_card_references")
    .delete()
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("daily_card_id", dailyCardID);
  if (clearError) {
    console.warn("generate-week day reference clear failed; continuing", {
      step: "replace_day_references_clear",
      error: clearError,
    });
  }
  const references = (card.source_reference_ids ?? []).filter(isUUID).map(
    (sourceReferenceID) => ({
      workspace_id: workspaceID,
      creator_id: creatorID,
      daily_card_id: dailyCardID,
      source_reference_id: sourceReferenceID,
      reason: card.source_note,
    }),
  );
  if (references.length > 0) {
    const { error } = await admin
      .from("daily_card_references")
      .insert(references);
    if (error) {
      console.warn("generate-week day reference insert failed; continuing", {
        step: "replace_day_references_insert",
        error,
      });
    }
  }
  return { ok: true };
}

async function completeDayGenerationRun(
  admin: SupabaseAdminClient,
  generationID: string,
  payload: RegenerateDayDraftResponse,
  completedAt: string,
): Promise<{ ok: true } | { response: Response }> {
  const { error } = await admin
    .from("weekly_generation_runs")
    .update({
      status: "completed",
      output_snapshot: payload,
      warnings: payload.warnings,
      assumptions: payload.assumptions,
      completed_at: completedAt,
      error_code: null,
    })
    .eq("id", generationID);
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

async function upsertDraftWeeklyPlan(
  admin: SupabaseAdminClient,
  workspaceID: string,
  request: GenerateWeekRequest,
  memberID: string,
  weeklySetup: Record<string, unknown> | null,
  inputSnapshot: GenerationInputSnapshot,
  generated: GeneratedWeekOutput,
): Promise<{ weeklyPlanID: string } | { response: Response }> {
  const existingResult = await admin
    .from("weekly_plans")
    .select("id,status,is_soft_locked")
    .eq("workspace_id", workspaceID)
    .eq("creator_id", request.creator_id)
    .eq("week_start_date", request.week_start_date)
    .in("status", ["draft", "reviewed"])
    .order("updated_at", { ascending: false })
    .limit(1);

  if (existingResult.error) {
    return generationPersistFailure(
      "weekly_plan_lookup",
      existingResult.error,
    );
  }

  const existing = (existingResult.data?.[0] ?? null) as PlanRecord | null;
  if (existing?.is_soft_locked) {
    return {
      response: jsonResponse({ error: "existing_published_week_locked" }, 409),
    };
  }

  const recoveredPlanID = existing?.id
    ? undefined
    : await recoverWeeklyPlanIDFromExistingCards(
      admin,
      workspaceID,
      request.creator_id,
      request.week_start_date,
    );
  const weeklyPlanID = existing?.id ?? recoveredPlanID ?? crypto.randomUUID();
  const planValues = {
    id: weeklyPlanID,
    workspace_id: workspaceID,
    creator_id: request.creator_id,
    weekly_setup_id: weeklySetup?.id ?? null,
    creator_profile_id: stringValue(weeklySetup?.creator_profile_id) ??
      stringValue(inputSnapshot.creator_profile?.id) ??
      null,
    week_start_date: request.week_start_date,
    status: "draft",
    strategy_summary: generated.strategy_summary,
    warnings: generated.warnings,
    assumptions: generated.assumptions,
    is_soft_locked: false,
    created_by_member_id: memberID,
  };

  const write = existing || recoveredPlanID
    ? admin.from("weekly_plans").update(planValues).eq("id", weeklyPlanID)
      .select("id").single()
    : admin.from("weekly_plans").insert(planValues).select("id").single();

  const { data, error } = await write;
  if (error || !data) {
    return generationPersistFailure("weekly_plan_write", error);
  }

  return { weeklyPlanID };
}

async function recoverWeeklyPlanIDFromExistingCards(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  weekStartDate: string,
): Promise<string | undefined> {
  const dates = new Set(weekDates(weekStartDate));
  const { data, error } = await admin
    .from("daily_cards")
    .select("weekly_plan_id,scheduled_date")
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .in("scheduled_date", [...dates]);
  if (error) {
    console.warn("generate-week existing card plan recovery failed", {
      step: "recover_weekly_plan_from_cards",
      error,
    });
    return undefined;
  }
  const rows = ((data ?? []) as Record<string, unknown>[]).filter((row) =>
    dates.has(stringValue(row.scheduled_date) ?? "")
  );
  const planIDs = new Set(
    rows.map((row) => stringValue(row.weekly_plan_id)).filter((
      value,
    ): value is string => isUUID(value)),
  );
  if (rows.length === dates.size && planIDs.size === 1) {
    return [...planIDs][0];
  }
  return undefined;
}

async function insertGeneratedIdeas(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  generated: GeneratedWeekOutput,
): Promise<{ ideaBank: Record<string, unknown>[] } | { response: Response }> {
  if (generated.idea_bank.length === 0) {
    return { ideaBank: [] };
  }

  const rows = generated.idea_bank.map((idea) => ({
    workspace_id: workspaceID,
    creator_id: creatorID,
    title: idea.title,
    summary: idea.summary,
    tags: idea.tags,
    suggested_use: idea.suggested_use,
    shootability: idea.shootability,
    fit_score: idea.fit_score,
    notes: idea.source_note,
    status: idea.status,
  }));

  const { data, error } = await admin
    .from("ideas")
    .insert(rows)
    .select("id,title,summary,suggested_use,shootability,status");

  if (error) {
    console.warn("generate-week idea bank insert failed; continuing", {
      step: "ideas_insert",
      error,
    });
    return { ideaBank: [] };
  }

  return { ideaBank: (data ?? []) as Record<string, unknown>[] };
}

async function upsertGeneratedDailyCards(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  weeklyPlanID: string,
  cards: GeneratedDailyCard[],
  preserveManualEdits: boolean,
): Promise<{ dailyCards: GeneratedDailyCard[] } | { response: Response }> {
  const existingCardsResult = await admin
    .from("daily_cards")
    .select(
      [
        "id",
        "scheduled_date",
        "title",
        "why_today",
        "shootability",
        "estimated_shoot_minutes",
        "scene_list",
        "caption",
        "backup_story",
        "backup_caption_only",
      ].join(","),
    )
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("weekly_plan_id", weeklyPlanID);

  if (existingCardsResult.error) {
    return generationPersistFailure(
      "daily_cards_lookup",
      existingCardsResult.error,
    );
  }

  const existingIDs = new Map<string, string>(
    ((existingCardsResult.data ?? []) as CardIdentityRecord[]).map((row) => [
      row.scheduled_date,
      row.id,
    ]),
  );
  const existingCards = new Map<string, CardIdentityRecord>(
    ((existingCardsResult.data ?? []) as CardIdentityRecord[]).map((row) => [
      row.scheduled_date,
      row,
    ]),
  );
  const cardsToWrite = preserveManualEdits
    ? cards.map((card) =>
      preserveManualDailyCardEdits(card, existingCards.get(card.scheduled_date))
    )
    : cards;

  const rows = cardsToWrite.map((card) => ({
    id: existingIDs.get(card.scheduled_date) ?? crypto.randomUUID(),
    workspace_id: workspaceID,
    creator_id: creatorID,
    weekly_plan_id: weeklyPlanID,
    scheduled_date: card.scheduled_date,
    status: "draft",
    title: card.title,
    why_today: card.why_today,
    growth_job: card.growth_job,
    content_pillar: card.content_pillar,
    shootability: card.shootability,
    estimated_shoot_minutes: card.estimated_shoot_minutes,
    energy_required: card.energy_required,
    language_mode: card.language_mode,
    scene_list: card.scene_list,
    script: card.script,
    no_voiceover_version: card.no_voiceover_version,
    on_screen_text: card.on_screen_text,
    caption: card.caption,
    cta: card.cta,
    hashtags: card.hashtags,
    cover_text: card.cover_text,
    post_instructions: {
      instructions: card.post_instructions,
      audio_option_notes: card.audio_option_notes,
      format: card.format,
      primary_surface: card.primary_surface,
      duration_seconds: card.duration_seconds,
      hook: card.hook,
      weekly_brief_anchor: card.weekly_brief_anchor,
      brief_alignment: card.brief_alignment,
      brief_context_tags: card.brief_context_tags,
      save_share_reason: card.save_share_reason,
      shot_timeline: card.shot_timeline,
      voiceover_timeline: card.voiceover_timeline,
      silent_version_timeline: card.silent_version_timeline,
      on_screen_text_timeline: card.on_screen_text_timeline,
      caption_backup_detail: card.caption_backup_detail,
      creator_fit_score: card.creator_fit_score,
    },
    brand_event_notes: card.brand_event_notes || null,
    backup_story: { line: card.backup_story, detail: card.backup_story_detail },
    backup_caption_only: {
      line: card.backup_caption_only,
      detail: card.caption_backup_detail,
    },
    risk_notes: card.risk_notes,
    assumptions: card.assumptions,
    source_note: card.source_note,
    storyboard_thumbnail_assets: [],
  }));

  const writtenIDs = new Map<string, string>();
  for (const row of rows) {
    if (existingIDs.has(row.scheduled_date)) {
      const {
        id,
        workspace_id: _workspaceID,
        creator_id: _creatorID,
        weekly_plan_id: _weeklyPlanID,
        scheduled_date: _scheduledDate,
        ...updateValues
      } = row;
      const { data, error } = await admin
        .from("daily_cards")
        .update(updateValues)
        .eq("id", id)
        .eq("workspace_id", workspaceID)
        .eq("creator_id", creatorID)
        .eq("weekly_plan_id", weeklyPlanID)
        .eq("scheduled_date", row.scheduled_date)
        .select("id,scheduled_date")
        .maybeSingle();

      if (error) {
        return generationPersistFailure("daily_card_update", error);
      }
      if (!isRecord(data)) {
        const fallback = await upsertDailyCardRow(admin, row);
        if ("response" in fallback) {
          return fallback;
        }
        writtenIDs.set(fallback.scheduledDate, fallback.id);
        continue;
      }
      writtenIDs.set(
        stringValue(data.scheduled_date) ?? row.scheduled_date,
        stringValue(data.id) ?? id,
      );
      continue;
    }

    const insertResult = await upsertDailyCardRow(admin, row);
    if ("response" in insertResult) {
      return insertResult;
    }
    writtenIDs.set(insertResult.scheduledDate, insertResult.id);
  }

  const dailyCards = cardsToWrite.map((card) => ({
    ...card,
    id: writtenIDs.get(card.scheduled_date) ??
      rows.find((row) => row.scheduled_date === card.scheduled_date)?.id,
  }));

  const dailyCardIDs = dailyCards
    .map((card) => card.id)
    .filter((id): id is string => isUUID(id));
  if (dailyCardIDs.length > 0) {
    const { error: clearReferenceError } = await admin
      .from("daily_card_references")
      .delete()
      .eq("workspace_id", workspaceID)
      .eq("creator_id", creatorID)
      .in("daily_card_id", dailyCardIDs);
    if (clearReferenceError) {
      console.warn(
        "generate-week daily card reference clear failed; continuing",
        {
          step: "daily_card_references_clear",
          error: clearReferenceError,
        },
      );
    }
  }

  const references = dailyCards.flatMap((card) =>
    (card.source_reference_ids ?? []).filter(isUUID).map((
      sourceReferenceID,
    ) => ({
      workspace_id: workspaceID,
      creator_id: creatorID,
      daily_card_id: card.id,
      source_reference_id: sourceReferenceID,
      reason: card.source_note,
    }))
  ).filter((row) => row.daily_card_id);

  if (references.length > 0) {
    const { error: referenceError } = await admin
      .from("daily_card_references")
      .insert(references);
    if (referenceError) {
      console.warn(
        "generate-week daily card reference insert failed; continuing",
        {
          step: "daily_card_references_insert",
          error: referenceError,
        },
      );
    }
  }

  return { dailyCards };
}

async function upsertDailyCardRow(
  admin: SupabaseAdminClient,
  row: Record<string, unknown> & { id: string; scheduled_date: string },
): Promise<
  { id: string; scheduledDate: string } | { response: Response }
> {
  const { data, error } = await admin
    .from("daily_cards")
    .insert(row)
    .select("id,scheduled_date")
    .single();

  if (error || !isRecord(data)) {
    const recovered = await recoverInsertedDailyCardRow(admin, row);
    if (recovered) {
      return recovered;
    }
    const recoveredConflict = await recoverConflictingDailyCardRow(admin, row);
    if (recoveredConflict) {
      return recoveredConflict;
    }
    return generationPersistFailure(
      "daily_card_upsert",
      error ?? new Error("daily_card_upsert_no_returned_row"),
    );
  }

  return {
    id: stringValue(data.id) ?? row.id,
    scheduledDate: stringValue(data.scheduled_date) ?? row.scheduled_date,
  };
}

async function recoverConflictingDailyCardRow(
  admin: SupabaseAdminClient,
  row: Record<string, unknown> & { id: string; scheduled_date: string },
): Promise<{ id: string; scheduledDate: string } | null> {
  const { data: existing, error: lookupError } = await admin
    .from("daily_cards")
    .select("id,scheduled_date")
    .eq("workspace_id", row.workspace_id)
    .eq("creator_id", row.creator_id)
    .eq("weekly_plan_id", row.weekly_plan_id)
    .eq("scheduled_date", row.scheduled_date)
    .maybeSingle();

  if (lookupError || !isRecord(existing)) {
    return null;
  }

  const existingID = stringValue(existing.id);
  if (!existingID) {
    return null;
  }

  const {
    id: _id,
    workspace_id: _workspaceID,
    creator_id: _creatorID,
    weekly_plan_id: _weeklyPlanID,
    scheduled_date: _scheduledDate,
    ...updateValues
  } = row;
  const { data, error } = await admin
    .from("daily_cards")
    .update(updateValues)
    .eq("id", existingID)
    .eq("workspace_id", row.workspace_id)
    .eq("creator_id", row.creator_id)
    .eq("weekly_plan_id", row.weekly_plan_id)
    .eq("scheduled_date", row.scheduled_date)
    .select("id,scheduled_date")
    .maybeSingle();

  if (error || !isRecord(data)) {
    return null;
  }

  return {
    id: stringValue(data.id) ?? existingID,
    scheduledDate: stringValue(data.scheduled_date) ?? row.scheduled_date,
  };
}

async function recoverInsertedDailyCardRow(
  admin: SupabaseAdminClient,
  row: Record<string, unknown> & { id: string; scheduled_date: string },
): Promise<{ id: string; scheduledDate: string } | null> {
  const { data, error } = await admin
    .from("daily_cards")
    .select("id,scheduled_date")
    .eq("id", row.id)
    .eq("workspace_id", row.workspace_id)
    .eq("creator_id", row.creator_id)
    .eq("weekly_plan_id", row.weekly_plan_id)
    .eq("scheduled_date", row.scheduled_date)
    .maybeSingle();

  if (error || !isRecord(data)) {
    return null;
  }

  return {
    id: stringValue(data.id) ?? row.id,
    scheduledDate: stringValue(data.scheduled_date) ?? row.scheduled_date,
  };
}

async function completeGenerationRun(
  admin: SupabaseAdminClient,
  generationID: string,
  weeklyPlanID: string,
  payload: GenerateWeekDraftResponse,
  completedAt: string,
): Promise<{ ok: true } | { response: Response }> {
  const { error } = await admin
    .from("weekly_generation_runs")
    .update({
      weekly_plan_id: weeklyPlanID,
      status: "completed",
      output_snapshot: payload,
      warnings: payload.warnings,
      assumptions: payload.assumptions,
      completed_at: completedAt,
      error_code: null,
    })
    .eq("id", generationID);

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

  const { error } = await admin
    .from("weekly_generation_runs")
    .update(update)
    .eq("id", generationID);

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
  await admin
    .from("weekly_generation_runs")
    .update({
      status: "failed",
      error_code: errorCode,
      completed_at: new Date().toISOString(),
    })
    .eq("id", generationID);
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

function recordArray(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value) ? value.filter(isRecord) : [];
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

type ShutdownRecord = {
  generation_id: string;
  boot_id: string;
  job_ids: string[];
  started_at: number;
};

const activeShutdownTrackers = new Map<string, ShutdownRecord>();

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
