import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, jsonResponse, verifyDeviceSession } from "../_shared/device-auth.ts";

type PublishWeekRequest = {
  creator_id?: string;
  member_id?: string;
  weekly_plan_id?: string;
  week_start_date?: string;
  strategy_summary?: string;
  days?: PublishWeekDay[];
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

type NormalizedPublishWeekDay = Required<PublishWeekDay>;

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseURL || !serviceRoleKey) {
    return jsonResponse({ error: "missing_function_secrets" }, 500);
  }

  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const authResult = await verifyDeviceSession(request, admin, ["owner", "editor"]);
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
  const weeklyPlanID = body.weekly_plan_id ?? crypto.randomUUID();
  const weekStartDate = body.week_start_date;
  const days = Array.isArray(body.days) ? body.days : [];

  if (!creatorID || !isDateString(weekStartDate) || days.length !== 7) {
    return jsonResponse({ error: "invalid_publish_payload" }, 400);
  }

  const normalizedDays = days.map(normalizeDay);
  if (normalizedDays.some((day) => day === null)) {
    return jsonResponse({ error: "invalid_day_payload" }, 400);
  }
  const publishDays = normalizedDays.filter((day): day is NormalizedPublishWeekDay => day !== null);

  const { session } = authResult;
  const { data: creator, error: creatorError } = await admin
    .from("creators")
    .select("id")
    .eq("id", creatorID)
    .eq("workspace_id", session.workspaceID)
    .eq("status", "active")
    .maybeSingle();

  if (creatorError) {
    return jsonResponse({ error: "creator_lookup_failed" }, 500);
  }

  if (!creator) {
    return jsonResponse({ error: "creator_not_found" }, 404);
  }

  const nowISO = new Date().toISOString();
  const { data: existingPublished, error: existingPublishedError } = await admin
    .from("weekly_plans")
    .select("id")
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", creatorID)
    .eq("week_start_date", weekStartDate)
    .eq("status", "published")
    .maybeSingle();

  if (existingPublishedError) {
    return jsonResponse({ error: "published_week_lookup_failed" }, 500);
  }

  if (existingPublished && existingPublished.id !== weeklyPlanID) {
    const { error: replaceError } = await admin
      .from("weekly_plans")
      .update({
        status: "replaced",
        is_soft_locked: false,
        replaced_by_weekly_plan_id: weeklyPlanID,
      })
      .eq("id", existingPublished.id);

    if (replaceError) {
      return jsonResponse({ error: "replace_existing_week_failed" }, 500);
    }
  }

  const planValues = {
    id: weeklyPlanID,
    workspace_id: session.workspaceID,
    creator_id: creatorID,
    week_start_date: weekStartDate,
    status: "published",
    strategy_summary: body.strategy_summary ?? "Published from Prateek Weekly Control.",
    warnings: [],
    assumptions: [],
    is_soft_locked: true,
    published_at: nowISO,
    created_by_member_id: session.memberID,
  };

  const { data: existingPlan, error: existingPlanError } = await admin
    .from("weekly_plans")
    .select("id")
    .eq("id", weeklyPlanID)
    .maybeSingle();

  if (existingPlanError) {
    return jsonResponse({ error: "weekly_plan_lookup_failed" }, 500);
  }

  const planWrite = existingPlan
    ? admin.from("weekly_plans").update(planValues).eq("id", weeklyPlanID).select("id").single()
    : admin.from("weekly_plans").insert(planValues).select("id").single();

  const { data: writtenPlan, error: planWriteError } = await planWrite;
  if (planWriteError || !writtenPlan) {
    return jsonResponse({ error: "weekly_plan_publish_failed" }, 500);
  }

  const cardRows = publishDays.map((day) => ({
    id: day.id ?? crypto.randomUUID(),
    workspace_id: session.workspaceID,
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
});

function normalizeDay(day: PublishWeekDay): NormalizedPublishWeekDay | null {
  if (!isDateString(day.scheduled_date) || !day.title?.trim()) {
    return null;
  }

  const state = day.state ?? "planned";
  const shootability = day.shootability?.trim() || (state === "backup" ? "backup" : "easy");
  const requestedMinutes = day.estimated_shoot_minutes;

  return {
    id: day.id ?? crypto.randomUUID(),
    scheduled_date: day.scheduled_date,
    title: day.title.trim(),
    why_today: day.why_today?.trim() || "Prepared for this day.",
    source: day.source?.trim() || "routine",
    state,
    shootability,
    estimated_shoot_minutes: typeof requestedMinutes === "number" && Number.isFinite(requestedMinutes)
      ? Math.max(0, requestedMinutes)
      : state === "open"
        ? 0
        : 10,
    scene_list: Array.isArray(day.scene_list) ? day.scene_list : [],
  };
}

function isDateString(value: string | undefined): value is string {
  return /^\d{4}-\d{2}-\d{2}$/.test(value ?? "");
}

function displayTitle(value: string): string {
  return value
    .split("_")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}
