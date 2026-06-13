import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  corsHeaders,
  jsonResponse,
  SupabaseAdminClient,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";

type PublishWeekRequest = {
  creator_id?: string;
  member_id?: string;
  weekly_plan_id?: string;
  week_start_date?: string;
  strategy_summary?: string;
  days?: PublishWeekDay[];
  draft_daily_cards?: DraftDailyCardPublishPayload[];
};

type PublishWeekDay = {
  id?: string;
  scheduled_date?: string;
  title?: string;
  why_today?: string;
  source?: string;
  state?: "planned" | "backup" | "open";
  shootability?: string;
  estimated_shoot_minutes?: number;
  scene_list?: unknown[];
};

type DraftDailyCardPublishPayload = {
  id?: string;
  scheduled_date?: string;
  title?: string;
  why_today?: string;
  growth_job?: string;
  content_pillar?: string;
  shootability?: string;
  estimated_shoot_minutes?: number;
  energy_required?: string;
  language_mode?: string;
  scene_list?: unknown[];
  script?: string;
  no_voiceover_version?: string;
  on_screen_text?: unknown[];
  caption?: string;
  cta?: string;
  hashtags?: string[];
  cover_text?: string;
  post_instructions?: unknown;
  brand_event_notes?: string;
  backup_story?: unknown;
  backup_caption_only?: unknown;
  audio_option_id?: string;
  audio_fallback_id?: string;
  creator_fit_score?: number;
  risk_notes?: unknown[];
  assumptions?: unknown[];
  source_note?: string;
};

type NormalizedPublishWeekDay = Required<PublishWeekDay>;

type WeeklyPlanRecord = {
  id: string;
  workspace_id: string;
  creator_id: string;
  week_start_date: string;
  status: string;
  is_soft_locked: boolean;
  published_at?: string | null;
};

type CardIdentityRecord = {
  id: string;
  scheduled_date: string;
};

type HandlerDependencies = {
  createAdminClient?: (
    supabaseURL: string,
    serviceRoleKey: string,
  ) => SupabaseAdminClient;
  env?: { get: (name: string) => string | undefined };
};

const REPLACED_DAILY_CARD_STATUSES = [
  "published",
  "in_decision",
  "shot",
  "posted",
  "used_backup",
  "saved_for_tomorrow",
  "skipped_intentionally",
];

export async function handlePublishWeekRequest(
  request: Request,
  dependencies: HandlerDependencies = {},
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

  let body: PublishWeekRequest;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const creatorID = body.creator_id;
  if (!creatorID) {
    return jsonResponse({ error: "invalid_publish_payload" }, 400);
  }

  const { session } = authResult;
  const creatorResult = await assertCreator(
    admin,
    session.workspaceID,
    creatorID,
  );
  if (creatorResult) {
    return creatorResult;
  }

  if (body.weekly_plan_id && !hasLegacySevenDayPayload(body)) {
    return publishExistingDraft(admin, session.workspaceID, creatorID, body);
  }

  return publishCallerSuppliedDays(
    admin,
    session.workspaceID,
    creatorID,
    body,
    session.memberID,
  );
}

async function assertCreator(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
): Promise<Response | null> {
  const { data: creator, error: creatorError } = await admin
    .from("creators")
    .select("id")
    .eq("id", creatorID)
    .eq("workspace_id", workspaceID)
    .eq("status", "active")
    .maybeSingle();

  if (creatorError) {
    return jsonResponse({ error: "creator_lookup_failed" }, 500);
  }

  if (!creator) {
    return jsonResponse({ error: "creator_not_found" }, 404);
  }

  return null;
}

async function publishExistingDraft(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  body: PublishWeekRequest,
): Promise<Response> {
  const weeklyPlanID = body.weekly_plan_id!;
  const { data: plan, error: planError } = await admin
    .from("weekly_plans")
    .select(
      "id,workspace_id,creator_id,week_start_date,status,is_soft_locked,published_at",
    )
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("id", weeklyPlanID)
    .maybeSingle();

  if (planError) {
    return jsonResponse({ error: "weekly_plan_lookup_failed" }, 500);
  }
  if (!plan) {
    return jsonResponse({ error: "weekly_plan_not_found" }, 404);
  }

  const draftPlan = plan as WeeklyPlanRecord;
  if (draftPlan.status === "published") {
    return summarizePublishedPlan(admin, weeklyPlanID, draftPlan);
  }
  if (
    draftPlan.is_soft_locked ||
    !["draft", "reviewed"].includes(draftPlan.status)
  ) {
    return jsonResponse({ error: "existing_published_week_locked" }, 409);
  }

  if (Array.isArray(body.draft_daily_cards)) {
    const updateResult = await upsertDraftCardPayloads(
      admin,
      workspaceID,
      creatorID,
      weeklyPlanID,
      draftPlan.week_start_date,
      body.draft_daily_cards,
    );
    if (updateResult) {
      return updateResult;
    }
  }

  const replaceResult = await replaceExistingPublishedWeek(
    admin,
    workspaceID,
    creatorID,
    draftPlan.week_start_date,
    weeklyPlanID,
  );
  if (replaceResult) {
    return replaceResult;
  }

  const nowISO = new Date().toISOString();
  const planUpdate: Record<string, unknown> = {
    status: "published",
    is_soft_locked: true,
    published_at: nowISO,
  };
  if (body.strategy_summary?.trim()) {
    planUpdate.strategy_summary = body.strategy_summary.trim();
  }

  const { error: planPublishError } = await admin
    .from("weekly_plans")
    .update(planUpdate)
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("id", weeklyPlanID);

  if (planPublishError) {
    return jsonResponse({ error: "weekly_plan_publish_failed" }, 500);
  }

  const { data: updatedCards, error: cardsPublishError } = await admin
    .from("daily_cards")
    .update({ status: "published" })
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("weekly_plan_id", weeklyPlanID)
    .eq("status", "draft")
    .select("id");

  if (cardsPublishError) {
    return jsonResponse({ error: "daily_cards_publish_failed" }, 500);
  }

  const { data: allCards, error: countError } = await admin
    .from("daily_cards")
    .select("id")
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("weekly_plan_id", weeklyPlanID);

  if (countError) {
    return jsonResponse({ error: "daily_cards_publish_failed" }, 500);
  }

  return jsonResponse({
    weekly_plan_id: weeklyPlanID,
    daily_card_count: allCards?.length ?? updatedCards?.length ?? 0,
    is_soft_locked: true,
    published_at: nowISO,
  });
}

async function publishCallerSuppliedDays(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  body: PublishWeekRequest,
  authenticatedMemberID: string,
): Promise<Response> {
  const weeklyPlanID = body.weekly_plan_id ?? crypto.randomUUID();
  const weekStartDate = body.week_start_date;
  const days = Array.isArray(body.days) ? body.days : [];

  if (!isDateString(weekStartDate) || days.length !== 7) {
    return jsonResponse({ error: "invalid_publish_payload" }, 400);
  }

  const normalizedDays = days.map(normalizeDay);
  if (normalizedDays.some((day) => day === null)) {
    return jsonResponse({ error: "invalid_day_payload" }, 400);
  }
  const publishDays = normalizedDays.filter((
    day,
  ): day is NormalizedPublishWeekDay => day !== null);

  const replaceResult = await replaceExistingPublishedWeek(
    admin,
    workspaceID,
    creatorID,
    weekStartDate,
    weeklyPlanID,
  );
  if (replaceResult) {
    return replaceResult;
  }

  const nowISO = new Date().toISOString();
  const planValues = {
    id: weeklyPlanID,
    workspace_id: workspaceID,
    creator_id: creatorID,
    week_start_date: weekStartDate,
    status: "published",
    strategy_summary: body.strategy_summary ??
      "Published from Manager Weekly Control.",
    warnings: [],
    assumptions: [],
    is_soft_locked: true,
    published_at: nowISO,
    created_by_member_id: authenticatedMemberID,
  };

  const { data: existingPlan, error: existingPlanError } = await admin
    .from("weekly_plans")
    .select("id")
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("id", weeklyPlanID)
    .maybeSingle();

  if (existingPlanError) {
    return jsonResponse({ error: "weekly_plan_lookup_failed" }, 500);
  }

  const planWrite = existingPlan
    ? admin.from("weekly_plans").update(planValues).eq("id", weeklyPlanID)
      .select("id").single()
    : admin.from("weekly_plans").insert(planValues).select("id").single();

  const { data: writtenPlan, error: planWriteError } = await planWrite;
  if (planWriteError || !writtenPlan) {
    return jsonResponse({ error: "weekly_plan_publish_failed" }, 500);
  }

  const cardRows = publishDays.map((day) => ({
    id: day.id ?? crypto.randomUUID(),
    workspace_id: workspaceID,
    creator_id: creatorID,
    weekly_plan_id: weeklyPlanID,
    scheduled_date: day.scheduled_date,
    status: day.state === "open" ? "draft" : "published",
    title: day.title,
    why_today: day.why_today,
    content_pillar: day.source,
    shootability: day.shootability,
    estimated_shoot_minutes: day.estimated_shoot_minutes,
    scene_list: day.scene_list,
    hashtags: [],
    source_note: day.source ? `${displayTitle(day.source)} source` : null,
  }));

  const { data: writtenCards, error: cardsError } = await admin
    .from("daily_cards")
    .upsert(cardRows, { onConflict: "weekly_plan_id,scheduled_date" })
    .select("id");

  if (cardsError) {
    return jsonResponse({ error: "daily_cards_publish_failed" }, 500);
  }

  return jsonResponse({
    weekly_plan_id: weeklyPlanID,
    daily_card_count: writtenCards?.length ?? cardRows.length,
    is_soft_locked: true,
    published_at: nowISO,
  });
}

async function upsertDraftCardPayloads(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  weeklyPlanID: string,
  weekStartDate: string,
  cards: DraftDailyCardPublishPayload[],
): Promise<Response | null> {
  if (cards.length !== 7) {
    return jsonResponse({ error: "invalid_day_payload" }, 400);
  }

  const expectedDates = new Set(weekDates(weekStartDate));
  const seenDates = new Set<string>();
  const normalized = cards.map((card) => normalizeDraftCard(card));
  if (normalized.some((card) => card === null)) {
    return jsonResponse({ error: "invalid_day_payload" }, 400);
  }

  const publishCards = normalized.filter((
    card,
  ): card is Record<string, unknown> & { scheduled_date: string } =>
    card !== null
  );

  for (const card of publishCards) {
    if (
      !expectedDates.has(card.scheduled_date) ||
      seenDates.has(card.scheduled_date)
    ) {
      return jsonResponse({ error: "invalid_day_payload" }, 400);
    }
    seenDates.add(card.scheduled_date);
  }

  const existingCardsResult = await admin
    .from("daily_cards")
    .select("id,scheduled_date")
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("weekly_plan_id", weeklyPlanID);

  if (existingCardsResult.error) {
    return jsonResponse({ error: "daily_cards_publish_failed" }, 500);
  }

  const existingIDs = new Map<string, string>(
    ((existingCardsResult.data ?? []) as CardIdentityRecord[]).map((row) => [
      row.scheduled_date,
      row.id,
    ]),
  );

  const rows = publishCards.map((card) => ({
    ...card,
    id: existingIDs.get(card.scheduled_date) ??
      stringValue(card.id) ??
      crypto.randomUUID(),
    workspace_id: workspaceID,
    creator_id: creatorID,
    weekly_plan_id: weeklyPlanID,
    status: "draft",
  }));

  const { error } = await admin
    .from("daily_cards")
    .upsert(rows, { onConflict: "weekly_plan_id,scheduled_date" })
    .select("id");

  if (error) {
    return jsonResponse({ error: "daily_cards_publish_failed" }, 500);
  }

  return null;
}

export function normalizeDraftCard(
  card: DraftDailyCardPublishPayload,
): (Record<string, unknown> & { scheduled_date: string }) | null {
  if (!isDateString(card.scheduled_date) || !card.title?.trim()) {
    return null;
  }

  const minutes = card.estimated_shoot_minutes;
  const score = card.creator_fit_score;
  return {
    id: card.id,
    scheduled_date: card.scheduled_date,
    title: card.title.trim(),
    why_today: card.why_today?.trim() || "Prepared for this day.",
    growth_job: card.growth_job?.trim() || null,
    content_pillar: card.content_pillar?.trim() || null,
    shootability: card.shootability?.trim() || "easy",
    estimated_shoot_minutes:
      typeof minutes === "number" && Number.isFinite(minutes)
        ? Math.max(0, Math.trunc(minutes))
        : 10,
    energy_required: card.energy_required?.trim() || null,
    language_mode: card.language_mode?.trim() || null,
    scene_list: Array.isArray(card.scene_list) ? card.scene_list : [],
    script: card.script?.trim() || null,
    no_voiceover_version: card.no_voiceover_version?.trim() || null,
    on_screen_text: Array.isArray(card.on_screen_text)
      ? card.on_screen_text
      : [],
    caption: card.caption?.trim() || null,
    cta: card.cta?.trim() || null,
    hashtags: Array.isArray(card.hashtags) ? card.hashtags : [],
    cover_text: card.cover_text?.trim() || null,
    post_instructions: normalizeJSONPayload(card.post_instructions),
    brand_event_notes: card.brand_event_notes?.trim() || null,
    backup_story: normalizeJSONPayload(card.backup_story),
    backup_caption_only: normalizeJSONPayload(card.backup_caption_only),
    audio_option_id: isUUID(card.audio_option_id) ? card.audio_option_id : null,
    audio_fallback_id: isUUID(card.audio_fallback_id)
      ? card.audio_fallback_id
      : null,
    creator_fit_score: typeof score === "number" && Number.isFinite(score)
      ? Math.max(0, Math.min(100, score))
      : null,
    risk_notes: Array.isArray(card.risk_notes) ? card.risk_notes : [],
    assumptions: Array.isArray(card.assumptions) ? card.assumptions : [],
    source_note: card.source_note?.trim() || null,
  };
}

export async function replaceExistingPublishedWeek(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  weekStartDate: string,
  replacementWeeklyPlanID: string,
): Promise<Response | null> {
  const { data: existingPublished, error: existingPublishedError } = await admin
    .from("weekly_plans")
    .select("id")
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("week_start_date", weekStartDate)
    .eq("status", "published")
    .maybeSingle();

  if (existingPublishedError) {
    return jsonResponse({ error: "published_week_lookup_failed" }, 500);
  }

  if (existingPublished && existingPublished.id !== replacementWeeklyPlanID) {
    const { error: replaceError } = await admin
      .from("weekly_plans")
      .update({
        status: "replaced",
        is_soft_locked: false,
        replaced_by_weekly_plan_id: replacementWeeklyPlanID,
      })
      .eq("id", existingPublished.id);

    if (replaceError) {
      return jsonResponse({ error: "replace_existing_week_failed" }, 500);
    }

    const { error: archiveCardsError } = await admin
      .from("daily_cards")
      .update({ status: "archived" })
      .eq("workspace_id", workspaceID)
      .eq("creator_id", creatorID)
      .eq("weekly_plan_id", existingPublished.id)
      .in("status", REPLACED_DAILY_CARD_STATUSES);

    if (archiveCardsError) {
      return jsonResponse({ error: "replace_existing_week_failed" }, 500);
    }
  }

  return null;
}

async function summarizePublishedPlan(
  admin: SupabaseAdminClient,
  weeklyPlanID: string,
  plan: WeeklyPlanRecord,
): Promise<Response> {
  const { data: cards, error } = await admin
    .from("daily_cards")
    .select("id")
    .eq("workspace_id", plan.workspace_id)
    .eq("creator_id", plan.creator_id)
    .eq("weekly_plan_id", weeklyPlanID);

  if (error) {
    return jsonResponse({ error: "daily_cards_publish_failed" }, 500);
  }

  return jsonResponse({
    weekly_plan_id: weeklyPlanID,
    daily_card_count: cards?.length ?? 0,
    is_soft_locked: true,
    published_at: plan.published_at ?? null,
  });
}

function normalizeDay(day: PublishWeekDay): NormalizedPublishWeekDay | null {
  if (!isDateString(day.scheduled_date) || !day.title?.trim()) {
    return null;
  }

  const state = day.state ?? "planned";
  const shootability = day.shootability?.trim() ||
    (state === "backup" ? "backup" : "easy");
  const requestedMinutes = day.estimated_shoot_minutes;

  return {
    id: day.id ?? crypto.randomUUID(),
    scheduled_date: day.scheduled_date,
    title: day.title.trim(),
    why_today: day.why_today?.trim() || "Prepared for this day.",
    source: day.source?.trim() || "routine",
    state,
    shootability,
    estimated_shoot_minutes:
      typeof requestedMinutes === "number" && Number.isFinite(requestedMinutes)
        ? Math.max(0, requestedMinutes)
        : state === "open"
        ? 0
        : 10,
    scene_list: Array.isArray(day.scene_list) ? day.scene_list : [],
  };
}

function hasLegacySevenDayPayload(body: PublishWeekRequest): boolean {
  return Array.isArray(body.days) && body.days.length === 7;
}

function normalizeJSONPayload(value: unknown): unknown {
  if (typeof value === "string") {
    return { line: value };
  }
  if (value && typeof value === "object") {
    return value;
  }
  return {};
}

function isDateString(value: string | undefined): value is string {
  return /^\d{4}-\d{2}-\d{2}$/.test(value ?? "");
}

function isUUID(value: string | undefined): value is string {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value ?? "");
}

function weekDates(weekStartDate: string): string[] {
  const [year, month, day] = weekStartDate.split("-").map(Number);
  const start = new Date(Date.UTC(year, month - 1, day));
  return Array.from({ length: 7 }, (_, index) => {
    const date = new Date(start);
    date.setUTCDate(start.getUTCDate() + index);
    return date.toISOString().slice(0, 10);
  });
}

function displayTitle(value: string): string {
  return value
    .split("_")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0
    ? value
    : undefined;
}

if (import.meta.main) {
  Deno.serve((request) => handlePublishWeekRequest(request));
}
