import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  corsHeaders,
  jsonResponse,
  SupabaseAdminClient,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";
import {
  AIProviderConfig,
  callAIProviders,
  GeneratedDailyCard,
  GeneratedWeekOutput,
  GenerateWeekRequest,
  GenerateWeekValidationError,
  GenerationInputSnapshot,
  isUUID,
  makeMockGeneratedWeek,
  normalizeGenerateWeekRequest,
  preserveManualDailyCardEdits,
  validateGeneratedWeek,
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
};

type RunRecord = {
  id: string;
};

type PlanRecord = {
  id: string;
  status?: string;
  is_soft_locked?: boolean;
};

type CardIdentityRecord = {
  id: string;
  scheduled_date: string;
} & Record<string, unknown>;

type CreatorRecord = Record<string, unknown> & {
  id: string;
  display_name?: string;
};

const DEFAULT_DEEPSEEK_MODEL = "deepseek-v4-pro";
const DEFAULT_OPENAI_MODEL = "gpt-4.1-mini";
const PROMPT_VERSION = "mamta-weekly-generation-v1";

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

  let body: GenerateWeekRequest;
  try {
    body = normalizeGenerateWeekRequest(await request.json());
  } catch (error) {
    if (error instanceof GenerateWeekValidationError) {
      return jsonResponse({ error: error.code }, 400);
    }
    return jsonResponse({ error: "invalid_generation_payload" }, 400);
  }

  const { session } = authResult;
  const creatorResult = await readCreator(
    admin,
    session.workspaceID,
    body.creator_id,
  );
  if ("response" in creatorResult) {
    return creatorResult.response;
  }

  const publishedLock = await hasPublishedWeek(
    admin,
    session.workspaceID,
    body.creator_id,
    body.week_start_date,
  );
  if ("response" in publishedLock) {
    return publishedLock.response;
  }
  if (publishedLock.locked) {
    return jsonResponse({ error: "existing_published_week_locked" }, 409);
  }

  const weeklySetupResult = await readWeeklySetup(
    admin,
    session.workspaceID,
    body,
  );
  if ("response" in weeklySetupResult) {
    return weeklySetupResult.response;
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
    return inputResult.response;
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
    return jsonResponse({ error: "missing_openai_api_key" }, 500);
  }

  const runResult = await createGenerationRun(
    admin,
    session.workspaceID,
    body,
    session.memberID,
    model,
    inputSnapshot,
  );
  if ("response" in runResult) {
    return runResult.response;
  }

  let generated: GeneratedWeekOutput;
  try {
    const rawOutput = mockEnabled
      ? makeMockGeneratedWeek(inputSnapshot)
      : await (dependencies.generateAI ?? callAIProviders)(
        inputSnapshot,
        providers,
      );
    generated = validateGeneratedWeek(rawOutput, body.week_start_date);
  } catch (error) {
    const errorCode = stableGenerationError(error);
    await markGenerationRunFailed(admin, runResult.run.id, errorCode);
    return jsonResponse(
      { error: errorCode },
      errorCode === "openai_request_failed" ? 502 : 400,
    );
  }

  const persistResult = await persistGeneratedWeek(
    admin,
    session.workspaceID,
    body,
    session.memberID,
    weeklySetupResult.setup,
    inputSnapshot,
    generated,
  );
  if ("response" in persistResult) {
    await markGenerationRunFailed(
      admin,
      runResult.run.id,
      "generation_persist_failed",
    );
    return persistResult.response;
  }

  const completedAt = new Date().toISOString();
  const completedRunResult = await completeGenerationRun(
    admin,
    runResult.run.id,
    persistResult.weeklyPlanID,
    generated,
    completedAt,
  );
  if ("response" in completedRunResult) {
    return completedRunResult.response;
  }

  return jsonResponse({
    generation_id: runResult.run.id,
    weekly_plan_id: persistResult.weeklyPlanID,
    status: "draft",
    strategy_summary: generated.strategy_summary,
    warnings: generated.warnings,
    assumptions: generated.assumptions,
    daily_cards: persistResult.dailyCards,
    idea_bank: persistResult.ideaBank,
    source_summary: generated.source_summary,
    generated_at: completedAt,
  });
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
      "id,title,pattern_type,summary,fit_notes,avoid_notes,mamta_adaptation,mamta_fit_score,status",
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
      "id,title,summary,timing_recommendation,mamta_adaptation,mamta_fit_score,status",
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

  const failures = [
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
  ].filter((result) => "response" in result);
  if (failures.length > 0) {
    return failures[0] as { response: Response };
  }

  const profileRow = (profile as { rows: Record<string, unknown>[] }).rows[0] ??
    null;

  return {
    input: {
      creator_id: creatorID,
      week_start_date: weekStartDate,
      creator_profile: profileRow
        ? {
          ...profileRow,
          display_name: creator.display_name ?? "Mamta",
          default_timezone: creator.default_timezone ?? "Asia/Kolkata",
        }
        : {
          display_name: creator.display_name ?? "Mamta",
          default_timezone: creator.default_timezone ?? "Asia/Kolkata",
        },
      weekly_setup: weeklySetup,
      confirmed_references:
        (confirmedReferences as { rows: Record<string, unknown>[] }).rows,
      reference_extractions:
        (referenceExtractions as { rows: Record<string, unknown>[] }).rows,
      recent_archive:
        (recentArchive as { rows: Record<string, unknown>[] }).rows,
      idea_bank: (ideaBank as { rows: Record<string, unknown>[] }).rows,
      patterns: (patterns as { rows: Record<string, unknown>[] }).rows,
      trends: (trends as { rows: Record<string, unknown>[] }).rows,
      audio_options: (audioOptions as { rows: Record<string, unknown>[] }).rows,
      brand_briefs: (brandBriefs as { rows: Record<string, unknown>[] }).rows,
      key_moments: (keyMoments as { rows: Record<string, unknown>[] }).rows,
    },
  };
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
    return {
      response: jsonResponse({ error: "generation_persist_failed" }, 500),
    };
  }

  return { run: data as RunRecord };
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
    return {
      response: jsonResponse({ error: "generation_persist_failed" }, 500),
    };
  }

  const existing = (existingResult.data?.[0] ?? null) as PlanRecord | null;
  if (existing?.is_soft_locked) {
    return {
      response: jsonResponse({ error: "existing_published_week_locked" }, 409),
    };
  }

  const weeklyPlanID = existing?.id ?? crypto.randomUUID();
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

  const write = existing
    ? admin.from("weekly_plans").update(planValues).eq("id", weeklyPlanID)
      .select("id").single()
    : admin.from("weekly_plans").insert(planValues).select("id").single();

  const { data, error } = await write;
  if (error || !data) {
    return {
      response: jsonResponse({ error: "generation_persist_failed" }, 500),
    };
  }

  return { weeklyPlanID };
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
    return {
      response: jsonResponse({ error: "generation_persist_failed" }, 500),
    };
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
    return {
      response: jsonResponse({ error: "generation_persist_failed" }, 500),
    };
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
    id: existingIDs.get(card.scheduled_date) ?? card.id ?? crypto.randomUUID(),
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
    },
    brand_event_notes: card.brand_event_notes || null,
    backup_story: { line: card.backup_story },
    backup_caption_only: { line: card.backup_caption_only },
    mamta_fit_score: card.mamta_fit_score,
    risk_notes: card.risk_notes,
    assumptions: card.assumptions,
    source_note: card.source_note,
  }));

  const { data, error } = await admin
    .from("daily_cards")
    .upsert(rows, { onConflict: "weekly_plan_id,scheduled_date" })
    .select("id,scheduled_date");

  if (error) {
    return {
      response: jsonResponse({ error: "generation_persist_failed" }, 500),
    };
  }

  const writtenIDs = new Map<string, string>(
    ((data ?? []) as CardIdentityRecord[]).map((row) => [
      row.scheduled_date,
      row.id,
    ]),
  );
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
      return {
        response: jsonResponse({ error: "generation_persist_failed" }, 500),
      };
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
      .upsert(references, { onConflict: "daily_card_id,source_reference_id" });
    if (referenceError) {
      return {
        response: jsonResponse({ error: "generation_persist_failed" }, 500),
      };
    }
  }

  return { dailyCards };
}

async function completeGenerationRun(
  admin: SupabaseAdminClient,
  generationID: string,
  weeklyPlanID: string,
  generated: GeneratedWeekOutput,
  completedAt: string,
): Promise<{ ok: true } | { response: Response }> {
  const { error } = await admin
    .from("weekly_generation_runs")
    .update({
      weekly_plan_id: weeklyPlanID,
      status: "completed",
      output_snapshot: generated,
      warnings: generated.warnings,
      assumptions: generated.assumptions,
      completed_at: completedAt,
    })
    .eq("id", generationID);

  if (error) {
    return {
      response: jsonResponse({ error: "generation_persist_failed" }, 500),
    };
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
  const order = (env.get("MCO_AI_PROVIDER_ORDER") ?? "deepseek,openai")
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

if (import.meta.main) {
  Deno.serve((request) => handleGenerateWeekRequest(request));
}
