import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  corsHeaders,
  jsonResponse,
  SupabaseAdminClient,
  VerifiedDeviceSession,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";

type ReadAction =
  | "today"
  | "weekly"
  | "archive"
  | "creator_profile"
  | "intelligence";

type ReadContentRequest = {
  action?: ReadAction;
  creator_id?: string;
  today_date?: string;
};

type WeeklyPlanRecord = Record<string, unknown> & {
  id: string;
  weekly_setup_id?: string | null;
};

const ALL_DEVICE_ROLES = ["owner", "editor", "creator", "scout"];
const ADMIN_ACTIONS = new Set<ReadAction>(["weekly", "intelligence"]);

const DAILY_CARD_SELECT =
  "id,workspace_id,creator_id,weekly_plan_id,origin_idea_id,brand_brief_id,key_moment_id,scheduled_date,status,title,why_today,growth_job,content_pillar,shootability,estimated_shoot_minutes,energy_required,language_mode,scene_list,script,no_voiceover_version,on_screen_text,caption,cta,hashtags,cover_text,post_instructions,brand_event_notes,backup_story,backup_caption_only,audio_option_id,audio_fallback_id,creator_fit_score,risk_notes,assumptions,source_note,decision_at";
const WEEKLY_PLAN_SELECT =
  "id,workspace_id,creator_id,weekly_setup_id,creator_profile_id,week_start_date,status,strategy_summary,warnings,assumptions,is_soft_locked,published_at";
const WEEKLY_SETUP_SELECT =
  "id,location,workout_race_schedule,family_travel_moments,energy_constraints,shooting_constraints,no_go_topics,selected_sources,notes";
const IDEA_SELECT = "id,title,summary,suggested_use,shootability,status";
const SOURCE_REFERENCE_SELECT =
  "id,source_type,source_url,storage_path,manual_notes,status,analysis_confidence,created_at";
const BENCHMARK_CREATOR_SELECT =
  "id,handle,display_name,platform,region,relevance_notes,status,normalized_handle,created_at,updated_at";
const PUBLISHED_DAILY_STATUSES = [
  "published",
  "in_decision",
  "shot",
  "posted",
  "used_backup",
  "saved_for_tomorrow",
  "skipped_intentionally",
];

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

  const authResult = await verifyDeviceSession(
    request,
    admin,
    ALL_DEVICE_ROLES,
  );
  if ("response" in authResult) {
    return authResult.response;
  }

  let body: ReadContentRequest;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const action = body.action;
  const creatorID = body.creator_id?.trim();

  if (!isReadAction(action) || !creatorID) {
    return jsonResponse({ error: "invalid_read_payload" }, 400);
  }

  const { session } = authResult;
  if (!canReadAction(session.role, action)) {
    return jsonResponse({ error: "role_not_allowed" }, 403);
  }

  const creatorResult = await assertCreator(admin, session, creatorID);
  if (creatorResult) {
    return creatorResult;
  }

  switch (action) {
    case "today":
      return readToday(
        admin,
        session,
        creatorID,
        normalizedDate(body.today_date),
      );
    case "weekly":
      return readWeekly(admin, session, creatorID);
    case "archive":
      return readArchive(admin, session, creatorID);
    case "creator_profile":
      return readCreatorProfile(admin, session, creatorID);
    case "intelligence":
      return readIntelligence(admin, session, creatorID);
  }
});

async function assertCreator(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  creatorID: string,
): Promise<Response | null> {
  const { data: creator, error } = await admin
    .from("creators")
    .select("id")
    .eq("id", creatorID)
    .eq("workspace_id", session.workspaceID)
    .eq("status", "active")
    .maybeSingle();

  if (error) {
    return jsonResponse({ error: "creator_lookup_failed" }, 500);
  }

  if (!creator) {
    return jsonResponse({ error: "creator_not_found" }, 404);
  }

  return null;
}

async function readToday(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  creatorID: string,
  todayDate: string,
): Promise<Response> {
  const { data: todayRows, error: todayError } = await admin
    .from("daily_cards")
    .select(DAILY_CARD_SELECT)
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", creatorID)
    .eq("scheduled_date", todayDate)
    .in("status", PUBLISHED_DAILY_STATUSES)
    .order("updated_at", { ascending: false })
    .limit(1);

  if (todayError) {
    return jsonResponse({ error: "today_card_lookup_failed" }, 500);
  }

  const { data: weekRows, error: weekError } = await admin
    .from("daily_cards")
    .select(DAILY_CARD_SELECT)
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", creatorID)
    .in("status", PUBLISHED_DAILY_STATUSES)
    .order("scheduled_date", { ascending: true })
    .limit(14);

  if (weekError) {
    return jsonResponse({ error: "week_cards_lookup_failed" }, 500);
  }

  return jsonResponse({
    today_card: todayRows?.[0] ?? null,
    week_cards: weekRows ?? [],
  });
}

async function readWeekly(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  creatorID: string,
): Promise<Response> {
  const ideaBank = await readIdeaBank(admin, session, creatorID, 25);
  if ("response" in ideaBank) {
    return ideaBank.response;
  }

  const { data: planRows, error: planError } = await admin
    .from("weekly_plans")
    .select(WEEKLY_PLAN_SELECT)
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", creatorID)
    .in("status", ["draft", "reviewed", "published"])
    .order("updated_at", { ascending: false })
    .limit(10);

  if (planError) {
    return jsonResponse({ error: "weekly_plan_lookup_failed" }, 500);
  }

  const weeklyPlan = chooseWeeklyPlan(planRows ?? []);
  if (!weeklyPlan) {
    return jsonResponse({
      weekly_plan: null,
      daily_cards: [],
      weekly_setup: null,
      idea_bank: ideaBank.rows,
    });
  }

  const { data: cardRows, error: cardError } = await admin
    .from("daily_cards")
    .select(DAILY_CARD_SELECT)
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", creatorID)
    .eq("weekly_plan_id", weeklyPlan.id)
    .order("scheduled_date", { ascending: true });

  if (cardError) {
    return jsonResponse({ error: "weekly_cards_lookup_failed" }, 500);
  }

  let weeklySetup = null;
  if (weeklyPlan.weekly_setup_id) {
    const { data: setup, error: setupError } = await admin
      .from("weekly_setups")
      .select(WEEKLY_SETUP_SELECT)
      .eq("workspace_id", session.workspaceID)
      .eq("creator_id", creatorID)
      .eq("id", weeklyPlan.weekly_setup_id)
      .maybeSingle();

    if (setupError) {
      return jsonResponse({ error: "weekly_setup_lookup_failed" }, 500);
    }

    weeklySetup = setup ?? null;
  }

  return jsonResponse({
    weekly_plan: weeklyPlan,
    daily_cards: cardRows ?? [],
    weekly_setup: weeklySetup,
    idea_bank: ideaBank.rows,
  });
}

function chooseWeeklyPlan(rows: unknown[]): WeeklyPlanRecord | null {
  const typedRows = rows as (WeeklyPlanRecord & { status?: string })[];
  return typedRows.find((row) => row.status === "draft") ??
    typedRows.find((row) => row.status === "reviewed") ??
    typedRows.find((row) => row.status === "published") ??
    null;
}

async function readArchive(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  creatorID: string,
): Promise<Response> {
  const { data: rows, error } = await admin
    .from("archive_entries")
    .select(
      "id,daily_card_id,archive_date,decision,output_line,has_post_thumbnail,daily_cards(title)",
    )
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", creatorID)
    .order("archive_date", { ascending: false })
    .limit(50);

  if (error) {
    return jsonResponse({ error: "archive_lookup_failed" }, 500);
  }

  return jsonResponse({ entries: rows ?? [] });
}

async function readCreatorProfile(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  creatorID: string,
): Promise<Response> {
  const { data: profile, error } = await admin
    .from("creator_profiles")
    .select("positioning,voice_rules,never_say")
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", creatorID)
    .eq("status", "active")
    .order("version", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) {
    return jsonResponse({ error: "creator_profile_lookup_failed" }, 500);
  }

  return jsonResponse({ profile: profile ?? null });
}

async function readIntelligence(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  creatorID: string,
): Promise<Response> {
  const confirmedReferences = await readConfirmedReferences(
    admin,
    session,
    creatorID,
  );
  if ("response" in confirmedReferences) {
    return confirmedReferences.response;
  }

  const reviewReferences = await readReviewReferences(
    admin,
    session,
    creatorID,
  );
  if ("response" in reviewReferences) {
    return reviewReferences.response;
  }

  const candidateCreators = await readCandidateCreators(
    admin,
    session,
    creatorID,
  );
  if ("response" in candidateCreators) {
    return candidateCreators.response;
  }

  const benchmarkCreatorCount = await readBenchmarkCreatorCount(
    admin,
    session,
    creatorID,
  );
  if ("response" in benchmarkCreatorCount) {
    return benchmarkCreatorCount.response;
  }

  const patterns = await readLibraryRows(
    admin,
    session,
    creatorID,
    "patterns",
    "id,title,pattern_type,summary,status",
    20,
  );
  if ("response" in patterns) {
    return patterns.response;
  }

  const trends = await readLibraryRows(
    admin,
    session,
    creatorID,
    "trends",
    "id,title,summary,status,timing_recommendation",
    20,
  );
  if ("response" in trends) {
    return trends.response;
  }

  const audioOptions = await readLibraryRows(
    admin,
    session,
    creatorID,
    "audio_options",
    "id,title,artist_or_creator,availability_confidence,verification_note,status",
    20,
  );
  if ("response" in audioOptions) {
    return audioOptions.response;
  }

  const ideas = await readIdeaBank(admin, session, creatorID, 20);
  if ("response" in ideas) {
    return ideas.response;
  }

  return jsonResponse({
    confirmed_source_references: confirmedReferences.rows,
    review_source_references: reviewReferences.rows,
    candidate_benchmark_creators: candidateCreators.rows,
    benchmark_creator_count: benchmarkCreatorCount.count,
    patterns: patterns.rows,
    trends: trends.rows,
    audio_options: audioOptions.rows,
    ideas: ideas.rows,
  });
}

async function readConfirmedReferences(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  creatorID: string,
): Promise<{ rows: unknown[] } | { response: Response }> {
  const { data: rows, error } = await admin
    .from("source_references")
    .select(SOURCE_REFERENCE_SELECT)
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", creatorID)
    .eq("status", "confirmed")
    .in("source_type", ["reel_link", "audio_link"])
    .order("created_at", { ascending: false })
    .limit(8);

  if (error) {
    return {
      response: jsonResponse(
        { error: "confirmed_references_lookup_failed" },
        500,
      ),
    };
  }

  return { rows: rows ?? [] };
}

async function readReviewReferences(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  creatorID: string,
): Promise<{ rows: unknown[] } | { response: Response }> {
  const { data: rows, error } = await admin
    .from("source_references")
    .select(SOURCE_REFERENCE_SELECT)
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", creatorID)
    .eq("status", "needs_review")
    .order("created_at", { ascending: false })
    .limit(50);

  if (error) {
    return {
      response: jsonResponse({ error: "review_references_lookup_failed" }, 500),
    };
  }

  return { rows: rows ?? [] };
}

async function readCandidateCreators(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  creatorID: string,
): Promise<{ rows: unknown[] } | { response: Response }> {
  const { data: rows, error } = await admin
    .from("benchmark_creators")
    .select(BENCHMARK_CREATOR_SELECT)
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", creatorID)
    .eq("platform", "instagram")
    .eq("status", "candidate")
    .order("updated_at", { ascending: false })
    .limit(50);

  if (error) {
    return {
      response: jsonResponse(
        { error: "candidate_creators_lookup_failed" },
        500,
      ),
    };
  }

  return { rows: rows ?? [] };
}

async function readBenchmarkCreatorCount(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  creatorID: string,
): Promise<{ count: number } | { response: Response }> {
  const { data: rows, error } = await admin
    .from("benchmark_creators")
    .select("id")
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", creatorID)
    .eq("platform", "instagram")
    .in("status", ["active", "candidate"])
    .limit(500);

  if (error) {
    return {
      response: jsonResponse({ error: "benchmark_creator_count_failed" }, 500),
    };
  }

  return { count: rows?.length ?? 0 };
}

async function readIdeaBank(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  creatorID: string,
  limit: number,
): Promise<{ rows: unknown[] } | { response: Response }> {
  return readLibraryRows(
    admin,
    session,
    creatorID,
    "ideas",
    IDEA_SELECT,
    limit,
  );
}

async function readLibraryRows(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  creatorID: string,
  table: string,
  select: string,
  limit: number,
): Promise<{ rows: unknown[] } | { response: Response }> {
  const { data: rows, error } = await admin
    .from(table)
    .select(select)
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", creatorID)
    .order("updated_at", { ascending: false })
    .limit(limit);

  if (error) {
    return { response: jsonResponse({ error: `${table}_lookup_failed` }, 500) };
  }

  return { rows: rows ?? [] };
}

function isReadAction(value: string | undefined): value is ReadAction {
  return value === "today" ||
    value === "weekly" ||
    value === "archive" ||
    value === "creator_profile" ||
    value === "intelligence";
}

function canReadAction(role: string, action: ReadAction): boolean {
  if (!ADMIN_ACTIONS.has(action)) {
    return role === "owner" || role === "editor" || role === "creator";
  }

  return role === "owner" || role === "editor";
}

function normalizedDate(value: string | undefined): string {
  return /^\d{4}-\d{2}-\d{2}$/.test(value ?? "")
    ? value!
    : new Date().toISOString().slice(0, 10);
}
