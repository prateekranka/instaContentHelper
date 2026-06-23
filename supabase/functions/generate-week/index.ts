import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  corsHeaders,
  jsonResponse,
  SupabaseAdminClient,
  VerifiedDeviceSession,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";
import {
  AIProviderConfig,
  callAIProviders,
  callAIProvidersForDay,
  callAIProvidersForSplitWeek,
  combineGeneratedDayOutputs,
  GeneratedDailyCard,
  GeneratedDayOutput,
  GeneratedWeekOutput,
  GenerateWeekRequest,
  GenerateWeekValidationError,
  GenerationInputSnapshot,
  isUUID,
  makeMockGeneratedWeek,
  normalizeGenerateWeekRequest,
  normalizeRegenerateDayRequest,
  preserveManualDailyCardEdits,
  RegenerateDayRequest,
  validateGeneratedDayOutput,
  validateGeneratedWeek,
  weekDates,
} from "./generation.ts";

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
  ) => Promise<GeneratedWeekOutput>;
  generateDayAI?: (
    input: GenerationInputSnapshot,
    providers: AIProviderConfig[],
    scheduledDate: string,
    dayIndex: number,
  ) => Promise<GeneratedDayOutput>;
  runInBackground?: (promise: Promise<void>) => void;
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

type DayGenerationStatus = "pending" | "running" | "completed" | "failed";
type GenerationOverallStatus = "running" | "completed" | "partial" | "failed";

type DayGenerationState = {
  scheduled_date: string;
  status: DayGenerationStatus;
  attempts: number;
  daily_card_id?: string;
  started_at?: string;
  completed_at?: string;
  error_code?: string;
  output?: GeneratedDayOutput;
};

type PerDayGenerationSnapshot = {
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

type DayGenerationStatusResponse = {
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

type WeekGenerationStatusSummary = {
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

const DEFAULT_DEEPSEEK_MODEL = "deepseek-v4-pro";
const DEFAULT_OPENAI_MODEL = "gpt-4.1-mini";
const PROMPT_VERSION = "creator-weekly-generation-v1";
const DEFAULT_RUNNING_DAY_STALE_MS = 240_000;
const DEFAULT_DAY_GENERATION_MAX_ATTEMPTS = 2;

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

  const { prepared } = preparedResult;
  const runResult = await createDayGenerationRun(
    admin,
    prepared,
    session.memberID,
  );
  if ("response" in runResult) {
    return runResult.response;
  }

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
): Promise<{ dailyCards: GeneratedDailyCard[] } | { response: Response }> {
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
): GeneratedDailyCard {
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
  };
}

function savedDailyCardsForProgress(
  savedCards: GeneratedDailyCard[],
  progress: PerDayGenerationSnapshot,
): GeneratedDailyCard[] {
  const completedCardIDs = new Set(
    progress.days
      .filter((day) => day.status === "completed" && isUUID(day.daily_card_id))
      .map((day) => day.daily_card_id as string),
  );
  return savedCards.filter((card) =>
    isUUID(card.id) && completedCardIDs.has(card.id)
  );
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
  let generated: GeneratedWeekOutput;
  try {
    const rawOutput = prepared.mockEnabled
      ? makeMockGeneratedWeek(prepared.inputSnapshot)
      : await generateWeekOutputWithFallback(prepared, dependencies);
    generated = validateGeneratedWeek(
      rawOutput,
      prepared.request.week_start_date,
    );
  } catch (error) {
    const errorCode = stableGenerationError(error);
    await markGenerationRunFailed(admin, generationID, errorCode);
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
    return completedRunResult;
  }

  return { payload };
}

async function generateWeekOutputWithFallback(
  prepared: PreparedGeneration,
  dependencies: GenerateWeekDependencies,
): Promise<GeneratedWeekOutput> {
  if (!dependencies.generateAI) {
    return await generateSplitWeekOutput(prepared, dependencies);
  }

  try {
    return await dependencies.generateAI(
      prepared.inputSnapshot,
      prepared.providers,
    );
  } catch (error) {
    if (!shouldRetryWeekAsSplitGeneration(error)) {
      throw error;
    }
    return await generateSplitWeekOutput(prepared, dependencies);
  }
}

async function generateSplitWeekOutput(
  prepared: PreparedGeneration,
  dependencies: GenerateWeekDependencies,
): Promise<GeneratedWeekOutput> {
  if (dependencies.generateDayAI) {
    const dayOutputs = await runDayGenerationBatches(
      weekDates(prepared.inputSnapshot.week_start_date),
      (scheduledDate, dayIndex) =>
        dependencies.generateDayAI!(
          prepared.inputSnapshot,
          prepared.providers,
          scheduledDate,
          dayIndex,
        ),
    );
    return combineGeneratedDayOutputs(prepared.inputSnapshot, dayOutputs);
  }
  return await callAIProvidersForSplitWeek(
    prepared.inputSnapshot,
    prepared.providers,
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
  try {
    const body = await response.clone().json();
    return isRecord(body) ? stringValue(body.step) ?? null : null;
  } catch {
    return null;
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
      ...weekGenerationStatusSummary(progress, "running"),
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

async function runParallelWeekGeneration(
  admin: SupabaseAdminClient,
  prepared: PreparedGeneration,
  generationID: string,
  weeklyPlanID: string,
  progress: PerDayGenerationSnapshot,
  dependencies: GenerateWeekDependencies,
): Promise<{ payload: Record<string, unknown> } | { response: Response }> {
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
          const replacement = states.find((state) => state.dayIndex === index);
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
  while (true) {
    const pendingIndexes = latestProgress.days.flatMap((day, index) =>
      shouldRunDayGeneration(day) ? [index] : []
    );
    if (pendingIndexes.length === 0) {
      break;
    }

    for (let start = 0; start < pendingIndexes.length; start += concurrency) {
      const batch = pendingIndexes.slice(start, start + concurrency);
      const startedAt = new Date().toISOString();
      await recordDays(batch.map((dayIndex) => {
        const day = latestProgress.days[dayIndex];
        return {
          dayIndex,
          state: {
            ...day,
            status: "running" as const,
            attempts: day.attempts + 1,
            started_at: startedAt,
            error_code: undefined,
          },
        };
      }));

      await Promise.all(batch.map(async (dayIndex) => {
        const state = await runParallelDayGenerationTask(
          admin,
          prepared,
          weeklyPlanID,
          latestProgress.days[dayIndex].scheduled_date,
          dayIndex,
          latestProgress.days[dayIndex].attempts,
          dependencies,
        );
        await recordDays([{ dayIndex, state }]);
      }));
    }
  }

  await writeQueue;
  return await finalizeParallelWeekGeneration(
    admin,
    prepared,
    generationID,
    weeklyPlanID,
    latestProgress,
  );
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
  weeklyPlanID: string,
  scheduledDate: string,
  dayIndex: number,
  attempts: number,
  dependencies: GenerateWeekDependencies,
): Promise<DayGenerationState> {
  const startedAt = new Date().toISOString();
  try {
    const rawOutput = await generateDayOutput(
      prepared,
      scheduledDate,
      dayIndex,
      dependencies,
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
    const persistResult = await upsertGeneratedDailyCards(
      admin,
      prepared.session.workspaceID,
      prepared.request.creator_id,
      weeklyPlanID,
      [output.daily_card],
      prepared.request.preserve_manual_edits,
    );
    if ("response" in persistResult) {
      const step = await persistenceFailureStep(persistResult.response);
      return {
        scheduled_date: scheduledDate,
        status: "failed",
        attempts,
        started_at: startedAt,
        completed_at: new Date().toISOString(),
        error_code: step
          ? `generation_persist_failed:${step}`
          : "generation_persist_failed",
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

    return {
      scheduled_date: scheduledDate,
      status: "completed",
      attempts,
      daily_card_id: persistResult.dailyCards[0]?.id,
      started_at: startedAt,
      completed_at: new Date().toISOString(),
    };
  } catch (error) {
    return {
      scheduled_date: scheduledDate,
      status: "failed",
      attempts,
      started_at: startedAt,
      completed_at: new Date().toISOString(),
      error_code: stableGenerationError(error),
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
    ...progress,
    days: progress.days.map((day) => {
      const saved = savedCardsForRun.find((card) =>
        card.id === day.daily_card_id &&
        card.scheduled_date === day.scheduled_date
      );
      return saved
        ? {
          ...day,
          status: "completed" as const,
          daily_card_id: saved.id,
          completed_at: day.completed_at ?? completedAt,
        }
        : day;
    }),
    updated_at: completedAt,
  };
  const summary = weekGenerationStatusSummary(
    finalProgress,
    savedCardsForRun.length === 0 ? "failed" : "completed",
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
      const summary = weekGenerationStatusSummary(progress, "failed");
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
  const summary = weekGenerationStatusSummary(latestProgress, "running");
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

function initialPerDayGenerationSnapshot(
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

function initialParallelWeekGenerationSnapshot(
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

function normalizePerDayGenerationSnapshot(
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
    error_code: stringValue(value.error_code),
    output,
  };
}

function weekGenerationStatusSummary(
  progress: PerDayGenerationSnapshot,
  storedRunStatus: string,
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

function dayGenerationStatusResponse(
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

function completedDraftStatusSummary(
  snapshot: GenerateWeekDraftResponse,
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
  const mergedProgress = {
    ...progress,
    days: progress.days.map((day) => {
      const saved = savedCardsForRun.find((card) =>
        card.id === day.daily_card_id &&
        card.scheduled_date === day.scheduled_date
      );
      return saved
        ? {
          ...day,
          status: "completed" as const,
          daily_card_id: saved.id,
        }
        : day;
    }),
  };
  const summary = weekGenerationStatusSummary(
    mergedProgress,
    stringValue(run.status) ?? "completed",
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

  if (stringValue(run.status) === "running") {
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

  const mergedProgress = {
    ...progress,
    days: progress.days.map((day) => {
      const saved = savedCardsForRun.find((card) =>
        card.id === day.daily_card_id &&
        card.scheduled_date === day.scheduled_date
      );
      return saved
        ? {
          ...day,
          status: "completed" as const,
          daily_card_id: saved.id,
        }
        : day;
    }),
  };
  const summary = weekGenerationStatusSummary(
    mergedProgress,
    stringValue(run.status) ?? "running",
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
  const active = progress.days.some((day) =>
    day.status === "running" && !isRunningDayStale(day)
  );
  if (active) {
    return false;
  }
  return progress.days.some(shouldRunDayGeneration);
}

function isParallelWeekGenerationTerminal(
  progress: PerDayGenerationSnapshot,
): boolean {
  return progress.days.length > 0 &&
    progress.days.every(isTerminalDayGenerationState);
}

function normalizeStaleRunningDays(
  progress: PerDayGenerationSnapshot,
): PerDayGenerationSnapshot {
  let changed = false;
  const days = progress.days.map((day) => {
    if (day.status === "running" && isRunningDayStale(day)) {
      changed = true;
      return staleDayFailure(day);
    }
    return day;
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

function normalizeDayGenerationStatus(
  value: unknown,
): DayGenerationStatus | undefined {
  return value === "pending" || value === "running" ||
      value === "completed" || value === "failed"
    ? value
    : undefined;
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

  const now = new Date().toISOString();
  const runningProgress = {
    ...normalizedProgress,
    days: normalizedProgress.days.map((day, index) =>
      index === dayIndex
        ? {
          ...day,
          status: "running" as const,
          attempts: day.attempts + 1,
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
    ),
    dependencies,
  );

  return { progress: runningProgress };
}

function staleDayFailure(day: DayGenerationState): DayGenerationState {
  if (day.attempts < maxDayGenerationAttempts()) {
    return { ...day, status: "pending", started_at: undefined };
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
): Promise<void> {
  const day = progress.days[dayIndex];
  try {
    const output = await generateDayOutput(
      prepared,
      day.scheduled_date,
      dayIndex,
      dependencies,
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
): Promise<GeneratedDayOutput> {
  if (prepared.mockEnabled) {
    return mockGeneratedDayOutput(prepared.inputSnapshot, dayIndex);
  }

  return await (dependencies.generateDayAI ?? callAIProvidersForDay)(
    prepared.inputSnapshot,
    prepared.providers,
    scheduledDate,
    dayIndex,
  );
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
    const summary = weekGenerationStatusSummary(baseProgress, "failed");
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
  const summary = weekGenerationStatusSummary(finalProgress, "completed");
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
  if (!day.started_at) {
    return false;
  }
  return Date.now() - Date.parse(day.started_at) > runningDayStaleMS();
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
    return {
      response: jsonResponse({ error: "date_not_in_plan" }, 400),
    };
  }

  let generated: GeneratedDayOutput;
  try {
    const rawOutput = prepared.mockEnabled
      ? mockGeneratedDayOutput(prepared.inputSnapshot, dayIndex)
      : await (dependencies.generateDayAI ?? callAIProvidersForDay)(
        prepared.inputSnapshot,
        prepared.providers,
        prepared.request.scheduled_date,
        dayIndex,
      );
    generated = validateGeneratedDayOutput(
      rawOutput,
      prepared.request.scheduled_date,
      dayIndex,
    );
  } catch (error) {
    const errorCode = stableGenerationError(error);
    await markGenerationRunFailed(admin, generationID, errorCode);
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
    return completedResult;
  }
  return { payload };
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
    return generationPersistFailure("daily_card_upsert", error);
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
