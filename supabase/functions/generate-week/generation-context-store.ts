import { SupabaseAdminClient } from "../_shared/device-auth.ts";

export const CREATOR_LOOKUP_SELECT = "id,display_name,default_timezone";

export const PUBLISHED_WEEK_LOOKUP_SELECT = "id";

export const DAY_GENERATION_PLAN_SELECT =
  "id,status,is_soft_locked,week_start_date,weekly_setup_id";

export const WEEKLY_SETUP_LOOKUP_SELECT =
  "id,creator_profile_id,week_start_date,status,location,workout_race_schedule,family_travel_moments,energy_constraints,shooting_constraints,no_go_topics,selected_sources,notes";

export const CREATOR_PROFILE_CONTEXT_SELECT =
  "id,status,version,positioning,voice_rules,content_pillars,caption_style,never_say,weekly_routine,family_race_travel_context,language_preferences,recurring_formats,trend_filter_rules,influencer_adaptation_rules";

export const CONFIRMED_REFERENCES_CONTEXT_SELECT =
  "id,source_type,source_url,manual_notes,analysis_confidence,status,created_at";

export const REFERENCE_EXTRACTIONS_CONTEXT_SELECT =
  "id,source_reference_id,extraction_kind,extracted_payload,confidence,status,created_at";

export const RECENT_ARCHIVE_CONTEXT_SELECT =
  "id,archive_date,decision,output_line,has_post_thumbnail,daily_cards(title,content_pillar,shootability,source_note)";

export const IDEA_BANK_CONTEXT_SELECT =
  "id,title,summary,tags,suggested_use,shootability,fit_score,notes,status,source_reference_id,source_pattern_id,source_trend_id,source_audio_option_id";

export const PATTERNS_CONTEXT_SELECT =
  "id,title,pattern_type,summary,fit_notes,avoid_notes,creator_adaptation,creator_fit_score,status";

export const TRENDS_CONTEXT_SELECT =
  "id,title,summary,timing_recommendation,creator_adaptation,creator_fit_score,status";

export const AUDIO_OPTIONS_CONTEXT_SELECT =
  "id,title,artist_or_creator,usage_notes,availability_confidence,verification_note,status";

export const BRAND_BRIEFS_CONTEXT_SELECT =
  "id,brand_name,campaign_title,deliverable,due_date,post_date,review_deadline,mandatory_points,must_avoid,required_tags,disclosure_requirement,tone,notes,status";

export const KEY_MOMENTS_CONTEXT_SELECT =
  "id,name,moment_date,location,kind,content_angle,required_scenes,pre_event_notes,post_event_notes,status";

export type GenerationContextRows = {
  profile_rows: Record<string, unknown>[];
  confirmed_references: Record<string, unknown>[];
  reference_extractions: Record<string, unknown>[];
  recent_archive: Record<string, unknown>[];
  idea_bank: Record<string, unknown>[];
  patterns: Record<string, unknown>[];
  trends: Record<string, unknown>[];
  audio_options: Record<string, unknown>[];
  brand_briefs: Record<string, unknown>[];
  key_moments: Record<string, unknown>[];
};

type ContextQuery = {
  eq: (column: string, value: unknown) => ContextQuery;
  in: (column: string, values: unknown[]) => ContextQuery;
  gte: (column: string, value: unknown) => ContextQuery;
  lte: (column: string, value: unknown) => ContextQuery;
  order: (
    column: string,
    options?: { ascending?: boolean },
  ) => ContextQuery;
  limit: (count: number) => ContextQuery;
  then: (
    onfulfilled?:
      | ((
        value: { data: unknown; error: unknown },
      ) => unknown | PromiseLike<unknown>)
      | null,
    onrejected?: ((reason: unknown) => unknown | PromiseLike<unknown>) | null,
  ) => PromiseLike<unknown>;
};

export function dayGenerationCardSelect(): string {
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

export async function readCreatorRow(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
): Promise<{ data: Record<string, unknown> | null; error: unknown }> {
  const { data, error } = await admin
    .from("creators")
    .select(CREATOR_LOOKUP_SELECT)
    .eq("id", creatorID)
    .eq("workspace_id", workspaceID)
    .eq("status", "active")
    .maybeSingle();

  return {
    data: isRecord(data) ? data : null,
    error,
  };
}

export async function readPublishedWeekRow(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  weekStartDate: string,
): Promise<{ data: Record<string, unknown> | null; error: unknown }> {
  const { data, error } = await admin
    .from("weekly_plans")
    .select(PUBLISHED_WEEK_LOOKUP_SELECT)
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("week_start_date", weekStartDate)
    .eq("status", "published")
    .maybeSingle();

  return {
    data: isRecord(data) ? data : null,
    error,
  };
}

export async function readWeeklySetupByID(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  weeklySetupID: string,
): Promise<{ data: Record<string, unknown> | null; error: unknown }> {
  const { data, error } = await admin
    .from("weekly_setups")
    .select(WEEKLY_SETUP_LOOKUP_SELECT)
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("id", weeklySetupID)
    .maybeSingle();

  return {
    data: isRecord(data) ? data : null,
    error,
  };
}

export async function readLatestWeeklySetupForWeek(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  weekStartDate: string,
): Promise<{ data: Record<string, unknown> | null; error: unknown }> {
  const { data, error } = await admin
    .from("weekly_setups")
    .select(WEEKLY_SETUP_LOOKUP_SELECT)
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("week_start_date", weekStartDate)
    .order("updated_at", { ascending: false })
    .limit(1);

  const rows = Array.isArray(data) ? data.filter(isRecord) : [];
  return {
    data: rows[0] ?? null,
    error,
  };
}

export async function readDayGenerationPlanRow(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  weeklyPlanID: string,
): Promise<{ data: Record<string, unknown> | null; error: unknown }> {
  const { data, error } = await admin
    .from("weekly_plans")
    .select(DAY_GENERATION_PLAN_SELECT)
    .eq("id", weeklyPlanID)
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .maybeSingle();

  return {
    data: isRecord(data) ? data : null,
    error,
  };
}

export async function readDailyCardsForPlan(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  weeklyPlanID: string,
): Promise<{ data: Record<string, unknown>[]; error: unknown }> {
  const { data, error } = await admin
    .from("daily_cards")
    .select(dayGenerationCardSelect())
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("weekly_plan_id", weeklyPlanID)
    .order("scheduled_date", { ascending: true });

  return {
    data: Array.isArray(data) ? data.filter(isRecord) : [],
    error,
  };
}

/**
 * Parallel read-only context lookups used to assemble GenerationInputSnapshot.
 * Optional-query failure behavior matches the prior index.ts rowsOrEmpty path:
 * a failed table contributes an empty array and does not fail the bundle.
 */
export async function readGenerationContextRows(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  weekStartDate: string,
): Promise<GenerationContextRows> {
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
    readContextTableRows(
      admin,
      "creator_profiles",
      CREATOR_PROFILE_CONTEXT_SELECT,
      workspaceID,
      creatorID,
      (query) =>
        query.eq("status", "active").order("version", { ascending: false })
          .limit(1),
    ),
    readContextTableRows(
      admin,
      "source_references",
      CONFIRMED_REFERENCES_CONTEXT_SELECT,
      workspaceID,
      creatorID,
      (query) =>
        query.eq("status", "confirmed").order("created_at", {
          ascending: false,
        }).limit(12),
    ),
    readContextTableRows(
      admin,
      "reference_extractions",
      REFERENCE_EXTRACTIONS_CONTEXT_SELECT,
      workspaceID,
      creatorID,
      (query) =>
        query.eq("status", "confirmed").order("updated_at", {
          ascending: false,
        }).limit(20),
    ),
    readContextTableRows(
      admin,
      "archive_entries",
      RECENT_ARCHIVE_CONTEXT_SELECT,
      workspaceID,
      creatorID,
      (query) => query.order("archive_date", { ascending: false }).limit(20),
    ),
    readContextTableRows(
      admin,
      "ideas",
      IDEA_BANK_CONTEXT_SELECT,
      workspaceID,
      creatorID,
      (query) =>
        query.in("status", ["saved", "scheduled"]).order("updated_at", {
          ascending: false,
        }).limit(30),
    ),
    readContextTableRows(
      admin,
      "patterns",
      PATTERNS_CONTEXT_SELECT,
      workspaceID,
      creatorID,
      (query) =>
        query.in("status", ["approved", "used"]).order("updated_at", {
          ascending: false,
        }).limit(12),
    ),
    readContextTableRows(
      admin,
      "trends",
      TRENDS_CONTEXT_SELECT,
      workspaceID,
      creatorID,
      (query) =>
        query.in("status", ["approved", "used"]).order("updated_at", {
          ascending: false,
        }).limit(12),
    ),
    readContextTableRows(
      admin,
      "audio_options",
      AUDIO_OPTIONS_CONTEXT_SELECT,
      workspaceID,
      creatorID,
      (query) =>
        query.in("status", ["verified_available", "used"]).order(
          "updated_at",
          { ascending: false },
        ).limit(12),
    ),
    readContextTableRows(
      admin,
      "brand_briefs",
      BRAND_BRIEFS_CONTEXT_SELECT,
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
    readContextTableRows(
      admin,
      "key_moments",
      KEY_MOMENTS_CONTEXT_SELECT,
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

  return {
    profile_rows: rowsOrEmpty(profile),
    confirmed_references: rowsOrEmpty(confirmedReferences),
    reference_extractions: rowsOrEmpty(referenceExtractions),
    recent_archive: rowsOrEmpty(recentArchive),
    idea_bank: rowsOrEmpty(ideaBank),
    patterns: rowsOrEmpty(patterns),
    trends: rowsOrEmpty(trends),
    audio_options: rowsOrEmpty(audioOptions),
    brand_briefs: rowsOrEmpty(brandBriefs),
    key_moments: rowsOrEmpty(keyMoments),
  };
}

export async function readContextTableRows(
  admin: SupabaseAdminClient,
  table: string,
  select: string,
  workspaceID: string,
  creatorID: string,
  configure: (query: ContextQuery) => ContextQuery,
): Promise<{ rows: Record<string, unknown>[] } | { error: unknown }> {
  const query = configure(
    admin
      .from(table)
      .select(select)
      .eq("workspace_id", workspaceID)
      .eq("creator_id", creatorID) as unknown as ContextQuery,
  );
  const { data, error } = await query as unknown as {
    data: unknown;
    error: unknown;
  };
  if (error) {
    return { error };
  }
  return {
    rows: Array.isArray(data) ? data.filter(isRecord) : [],
  };
}

export function rowsOrEmpty(
  result: { rows: Record<string, unknown>[] } | { error: unknown },
): Record<string, unknown>[] {
  return "rows" in result ? result.rows : [];
}

export function requestWeekWindowEnd(
  weekStartDate: string,
  offsetDays: number,
): string {
  const [year, month, day] = weekStartDate.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  date.setUTCDate(date.getUTCDate() + offsetDays);
  return date.toISOString().slice(0, 10);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
