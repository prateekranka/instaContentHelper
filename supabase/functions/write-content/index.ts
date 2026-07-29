import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  CONTENT_CREATOR_ROLES,
  corsHeaders,
  jsonResponse,
  SupabaseAdminClient,
  VerifiedDeviceSession,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";

type WriteAction =
  | "complete_today"
  | "upsert_archive_decision"
  | "select_idea_for_next_open_day"
  | "update_weekly_setup"
  | "update_creator_profile"
  | "update_daily_card_review_state";

type WriteContentRequest = {
  action?: WriteAction;
  creator_id?: string;
  daily_card_id?: string;
  idea_id?: string;
  weekly_plan_id?: string | null;
  weekly_setup_id?: string | null;
  week_start_date?: string;
  setup_sections?: unknown;
  weekly_brief?: unknown;
  notes?: unknown;
  positioning?: unknown;
  voice_rules?: unknown;
  content_pillars?: unknown;
  caption_style?: unknown;
  never_say?: unknown;
  recurring_formats?: unknown;
  archive_date?: string;
  decision?: string | {
    status?: string;
    output_line?: string;
    has_post_thumbnail?: unknown;
  };
  decision_at?: string | null;
  output_line?: string;
  has_post_thumbnail?: unknown;
  review_state?: string;
};

const DAILY_DECISION_STATUSES = new Set([
  "shot",
  "posted",
  "used_backup",
  "saved_for_tomorrow",
  "skipped_intentionally",
]);

const WEEKLY_SETUP_SELECT =
  "id,location,workout_race_schedule,family_travel_moments,energy_constraints,shooting_constraints,no_go_topics,selected_sources,notes";

const CREATOR_PROFILE_SELECT =
  "id,positioning,voice_rules,content_pillars,caption_style,never_say,recurring_formats,updated_at";

const WEEKLY_SETUP_TEXT_COLUMNS = new Set(["location", "notes"]);
const WEEKLY_SETUP_ARRAY_COLUMNS = new Set([
  "workout_race_schedule",
  "family_travel_moments",
  "energy_constraints",
  "shooting_constraints",
  "no_go_topics",
  "selected_sources",
]);

const WEEKLY_SETUP_SECTION_ALIASES: Record<string, string> = {
  location: "location",
  place: "location",
  notes: "notes",
  note: "notes",
  weekly_brief: "notes",
  brief: "notes",
  workout: "workout_race_schedule",
  workouts: "workout_race_schedule",
  body: "workout_race_schedule",
  workout_race_schedule: "workout_race_schedule",
  family: "family_travel_moments",
  travel: "family_travel_moments",
  family_travel_moments: "family_travel_moments",
  energy: "energy_constraints",
  energy_constraints: "energy_constraints",
  shooting: "shooting_constraints",
  shooting_constraints: "shooting_constraints",
  boundaries: "no_go_topics",
  boundary: "no_go_topics",
  no_go: "no_go_topics",
  no_go_topics: "no_go_topics",
  source_pulse: "selected_sources",
  sources: "selected_sources",
  selected_sources: "selected_sources",
  constraints: "__constraints__",
};

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

  let body: WriteContentRequest;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const action = body.action;
  const creatorID = body.creator_id?.trim();

  if (!isWriteAction(action)) {
    return jsonResponse({ error: "invalid_write_payload" }, 400);
  }
  if (!isUUID(creatorID)) {
    return jsonResponse({
      error: invalidPayloadError(action),
    }, 400);
  }

  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const authResult = await verifyDeviceSession(
    request,
    admin,
    allowedRoles(action),
  );
  if ("response" in authResult) {
    return authResult.response;
  }

  const { session } = authResult;
  const creatorResult = await assertCreator(admin, session, creatorID, action);
  if (creatorResult) {
    return creatorResult;
  }

  if (action === "update_weekly_setup") {
    return await updateWeeklySetup(admin, session, creatorID, body);
  }

  if (action === "update_creator_profile") {
    return await updateCreatorProfile(admin, session, creatorID, body);
  }

  if (action === "update_daily_card_review_state") {
    if (
      !isUUID(body.daily_card_id) ||
      !isReviewState(body.review_state)
    ) {
      return jsonResponse({ error: "invalid_review_state_payload" }, 400);
    }

    const payload = {
      action: body.action,
      workspace_id: session.workspaceID,
      creator_id: creatorID,
      member_id: session.memberID,
      daily_card_id: body.daily_card_id,
      review_state: body.review_state,
    };

    const { data, error } = await admin.rpc("write_content", { payload });
    if (error) {
      return jsonResponse({ error: "review_state_update_failed" }, 500);
    }

    if (data?.error) {
      const responseError = stableWriteError(data.error, action);
      return jsonResponse(
        { error: responseError },
        typeof data.status === "number" ? data.status : 500,
      );
    }

    return jsonResponse(data ?? { action });
  }

  const payload = normalizedPayload(body, session, creatorID);
  if (!payload) {
    return jsonResponse({ error: "invalid_write_payload" }, 400);
  }

  const { data, error } = await admin.rpc("write_content", { payload });
  if (error) {
    return jsonResponse({ error: actionFailureError(action) }, 500);
  }

  if (data?.error) {
    const responseError = stableWriteError(data.error, action);
    return jsonResponse(
      { error: responseError },
      typeof data.status === "number" ? data.status : 500,
    );
  }

  return jsonResponse(data ?? { action });
});

async function assertCreator(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  creatorID: string,
  action: WriteAction,
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
    if (action === "update_creator_profile") {
      const { data: crossWorkspaceCreator, error: crossWorkspaceError } =
        await admin
          .from("creators")
          .select("id")
          .eq("id", creatorID)
          .maybeSingle();

      if (crossWorkspaceError) {
        return jsonResponse({ error: "creator_profile_update_failed" }, 500);
      }

      if (crossWorkspaceCreator) {
        return jsonResponse({ error: "cross_workspace_forbidden" }, 403);
      }
    }

    return jsonResponse({ error: "creator_not_found" }, 404);
  }

  return null;
}

function normalizedPayload(
  body: WriteContentRequest,
  session: VerifiedDeviceSession,
  creatorID: string,
): Record<string, unknown> | null {
  const base = {
    action: body.action,
    workspace_id: session.workspaceID,
    creator_id: creatorID,
    member_id: session.memberID,
  };

  switch (body.action) {
    case "complete_today": {
      const decision = typeof body.decision === "object" ? body.decision : null;
      const decisionAt = body.decision_at?.trim() || null;

      if (
        !isUUID(body.daily_card_id) ||
        !decision ||
        !isDecisionStatus(decision.status) ||
        !isNonBlankString(decision.output_line) ||
        typeof decision.has_post_thumbnail !== "boolean" ||
        (decisionAt !== null && Number.isNaN(Date.parse(decisionAt)))
      ) {
        return null;
      }

      return {
        ...base,
        daily_card_id: body.daily_card_id,
        decision: {
          status: decision.status,
          output_line: decision.output_line.trim(),
          has_post_thumbnail: decision.has_post_thumbnail,
        },
        decision_at: decisionAt,
      };
    }

    case "upsert_archive_decision": {
      if (
        !isUUID(body.daily_card_id) ||
        !isDateString(body.archive_date) ||
        !isDecisionStatus(
          typeof body.decision === "string" ? body.decision : undefined,
        ) ||
        !isNonBlankString(body.output_line) ||
        typeof body.has_post_thumbnail !== "boolean"
      ) {
        return null;
      }

      return {
        ...base,
        daily_card_id: body.daily_card_id,
        archive_date: body.archive_date,
        decision: body.decision,
        output_line: body.output_line.trim(),
        has_post_thumbnail: body.has_post_thumbnail,
      };
    }

    case "select_idea_for_next_open_day": {
      const weeklyPlanID = body.weekly_plan_id?.trim() || null;

      if (
        !isUUID(body.idea_id) ||
        (weeklyPlanID !== null && !isUUID(weeklyPlanID))
      ) {
        return null;
      }

      return {
        ...base,
        idea_id: body.idea_id,
        weekly_plan_id: weeklyPlanID,
      };
    }

    case "update_weekly_setup":
    case "update_creator_profile":
    case "update_daily_card_review_state":
      return null;
  }

  return null;
}

async function updateWeeklySetup(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  creatorID: string,
  body: WriteContentRequest,
): Promise<Response> {
  const weeklySetupID = body.weekly_setup_id?.trim() || null;
  const weeklyPlanID = body.weekly_plan_id?.trim() || null;
  const weekStartDate = body.week_start_date?.trim();
  const update = normalizedWeeklySetupUpdate(body);

  if (
    !update ||
    (weeklySetupID !== null && !isUUID(weeklySetupID)) ||
    (weeklyPlanID !== null && !isUUID(weeklyPlanID)) ||
    (weeklySetupID === null && weeklyPlanID === null &&
      !isDateString(weekStartDate))
  ) {
    return jsonResponse({ error: "invalid_weekly_setup_payload" }, 400);
  }

  let resolvedWeeklySetupID = weeklySetupID;
  let resolvedWeekStartDate = weekStartDate;
  let resolvedWeeklyPlan:
    | {
      id: string;
      workspace_id: string;
      creator_id: string;
      weekly_setup_id: string | null;
      week_start_date: string | null;
    }
    | null = null;

  if (!resolvedWeeklySetupID && weeklyPlanID) {
    const { data: weeklyPlan, error: planLookupError } = await admin
      .from("weekly_plans")
      .select("id,workspace_id,creator_id,weekly_setup_id,week_start_date")
      .eq("id", weeklyPlanID)
      .maybeSingle();

    if (planLookupError) {
      return jsonResponse({ error: "weekly_setup_update_failed" }, 500);
    }

    if (!weeklyPlan) {
      if (isDateString(resolvedWeekStartDate)) {
        resolvedWeeklySetupID = null;
      } else {
        return jsonResponse({ error: "weekly_setup_not_found" }, 404);
      }
    } else if (
      weeklyPlan.workspace_id !== session.workspaceID ||
      weeklyPlan.creator_id !== creatorID
    ) {
      if (isDateString(resolvedWeekStartDate)) {
        resolvedWeeklySetupID = null;
      } else {
        return jsonResponse({ error: "cross_workspace_forbidden" }, 403);
      }
    } else {
      resolvedWeeklyPlan = weeklyPlan;
      resolvedWeeklySetupID = weeklyPlan.weekly_setup_id ?? null;
      if (!isDateString(resolvedWeekStartDate)) {
        resolvedWeekStartDate = weeklyPlan.week_start_date ??
          resolvedWeekStartDate;
      }
    }
  }

  if (!resolvedWeeklySetupID && !isDateString(resolvedWeekStartDate)) {
    return jsonResponse({ error: "invalid_weekly_setup_payload" }, 400);
  }

  let query = admin
    .from("weekly_setups")
    .update(update)
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", creatorID)
    .select(WEEKLY_SETUP_SELECT);

  if (resolvedWeeklySetupID) {
    query = query.eq("id", resolvedWeeklySetupID);
  } else {
    query = query.eq("week_start_date", resolvedWeekStartDate);
  }

  const { data: weeklySetup, error } = await query.maybeSingle();

  if (error) {
    return jsonResponse({ error: "weekly_setup_update_failed" }, 500);
  }

  if (weeklySetup) {
    await maybeAttachWeeklySetupToPlan(
      admin,
      resolvedWeeklyPlan,
      weeklySetup.id,
      resolvedWeekStartDate,
    );
    return jsonResponse({
      action: "update_weekly_setup",
      weekly_setup: weeklySetup,
    });
  }

  if (resolvedWeeklySetupID) {
    const { data: existingSetup, error: lookupError } = await admin
      .from("weekly_setups")
      .select("id,workspace_id,creator_id")
      .eq("id", resolvedWeeklySetupID)
      .maybeSingle();

    if (lookupError) {
      return jsonResponse({ error: "weekly_setup_update_failed" }, 500);
    }

    if (existingSetup) {
      return jsonResponse({ error: "cross_workspace_forbidden" }, 403);
    }
  }

  const createResult = await createWeeklySetupForWeek(
    admin,
    session,
    creatorID,
    resolvedWeekStartDate!,
    update,
  );
  if ("response" in createResult) {
    return createResult.response;
  }

  await maybeAttachWeeklySetupToPlan(
    admin,
    resolvedWeeklyPlan,
    createResult.weeklySetup.id,
    resolvedWeekStartDate,
  );

  return jsonResponse({
    action: "update_weekly_setup",
    weekly_setup: createResult.weeklySetup,
  });
}

async function createWeeklySetupForWeek(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  creatorID: string,
  weekStartDate: string,
  update: Record<string, unknown>,
): Promise<
  { weeklySetup: Record<string, unknown> & { id: string } } | {
    response: Response;
  }
> {
  const { data: profile } = await admin
    .from("creator_profiles")
    .select("id")
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", creatorID)
    .order("updated_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  const { data: weeklySetup, error } = await admin
    .from("weekly_setups")
    .insert({
      workspace_id: session.workspaceID,
      creator_id: creatorID,
      creator_profile_id: profile?.id ?? null,
      week_start_date: weekStartDate,
      status: "ready_to_generate",
      created_by_member_id: session.memberID,
      ...update,
    })
    .select(WEEKLY_SETUP_SELECT)
    .maybeSingle();

  if (error) {
    if (error.code === "23505") {
      const { data: existing, error: lookupError } = await admin
        .from("weekly_setups")
        .update(update)
        .eq("workspace_id", session.workspaceID)
        .eq("creator_id", creatorID)
        .eq("week_start_date", weekStartDate)
        .select(WEEKLY_SETUP_SELECT)
        .maybeSingle();

      if (lookupError || !existing) {
        return {
          response: jsonResponse({ error: "weekly_setup_update_failed" }, 500),
        };
      }

      return {
        weeklySetup: existing as Record<string, unknown> & { id: string },
      };
    }

    return {
      response: jsonResponse({ error: "weekly_setup_update_failed" }, 500),
    };
  }

  if (!weeklySetup) {
    return {
      response: jsonResponse({ error: "weekly_setup_update_failed" }, 500),
    };
  }

  return {
    weeklySetup: weeklySetup as Record<string, unknown> & { id: string },
  };
}

async function maybeAttachWeeklySetupToPlan(
  admin: SupabaseAdminClient,
  weeklyPlan: {
    id: string;
    workspace_id: string;
    creator_id: string;
    weekly_setup_id: string | null;
    week_start_date: string | null;
  } | null,
  weeklySetupID: string,
  requestedWeekStartDate?: string,
): Promise<void> {
  if (
    !weeklyPlan ||
    weeklyPlan.weekly_setup_id ||
    weeklyPlan.week_start_date !== requestedWeekStartDate
  ) {
    return;
  }

  await admin
    .from("weekly_plans")
    .update({ weekly_setup_id: weeklySetupID })
    .eq("id", weeklyPlan.id)
    .eq("workspace_id", weeklyPlan.workspace_id)
    .eq("creator_id", weeklyPlan.creator_id);
}

function normalizedWeeklySetupUpdate(
  body: WriteContentRequest,
): Record<string, unknown> | null {
  const setupSections = body.setup_sections;
  const hasSetupSections = setupSections !== undefined;
  const hasTopLevelNotes = body.weekly_brief !== undefined ||
    body.notes !== undefined;

  if (!hasSetupSections && !hasTopLevelNotes) {
    return null;
  }

  const update: Record<string, unknown> = {};

  if (hasSetupSections) {
    if (!Array.isArray(setupSections) || setupSections.length === 0) {
      return null;
    }

    for (const section of setupSections) {
      if (!isRecord(section)) {
        return null;
      }

      const sectionKey = weeklySetupSectionKey(section);
      if (!sectionKey) {
        return null;
      }

      const column = WEEKLY_SETUP_SECTION_ALIASES[sectionKey];
      if (!column) {
        return null;
      }

      const value = sectionValue(section);
      if (column === "__constraints__") {
        if (typeof value === "string") {
          update.energy_constraints = jsonTextArray(value);
          continue;
        }
        if (!isRecord(value)) {
          return null;
        }

        const energy = value.energy_constraints ?? value.energyConstraints;
        const shooting = value.shooting_constraints ??
          value.shootingConstraints;
        let applied = false;

        if (energy !== undefined) {
          if (!Array.isArray(energy)) {
            return null;
          }
          update.energy_constraints = energy;
          applied = true;
        }

        if (shooting !== undefined) {
          if (!Array.isArray(shooting)) {
            return null;
          }
          update.shooting_constraints = shooting;
          applied = true;
        }

        if (!applied) {
          return null;
        }
        continue;
      }

      if (WEEKLY_SETUP_TEXT_COLUMNS.has(column)) {
        if (value === null) {
          update[column] = null;
          continue;
        }
        if (typeof value !== "string") {
          return null;
        }
        update[column] = value.trim() || null;
        continue;
      }

      if (WEEKLY_SETUP_ARRAY_COLUMNS.has(column)) {
        if (typeof value === "string") {
          update[column] = jsonTextArray(value);
          continue;
        }
        if (!Array.isArray(value)) {
          return null;
        }
        update[column] = value;
        continue;
      }

      return null;
    }
  }

  if (hasTopLevelNotes) {
    const weeklyBrief = body.weekly_brief !== undefined
      ? body.weekly_brief
      : body.notes;
    if (weeklyBrief !== null && typeof weeklyBrief !== "string") {
      return null;
    }
    update.notes = typeof weeklyBrief === "string"
      ? weeklyBrief.trim() || null
      : null;
  }

  if (Object.keys(update).length === 0) {
    return null;
  }

  update.updated_at = new Date().toISOString();
  return update;
}

async function updateCreatorProfile(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  creatorID: string,
  body: WriteContentRequest,
): Promise<Response> {
  const update = normalizedCreatorProfileUpdate(body);

  if (!update) {
    return jsonResponse({ error: "invalid_creator_profile_payload" }, 400);
  }

  const { data: activeProfile, error: lookupError } = await admin
    .from("creator_profiles")
    .select("id")
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", creatorID)
    .eq("status", "active")
    .order("version", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (lookupError) {
    return jsonResponse({ error: "creator_profile_update_failed" }, 500);
  }

  if (!activeProfile) {
    return jsonResponse({ error: "creator_profile_not_found" }, 404);
  }

  const { data: updatedProfile, error: updateError } = await admin
    .from("creator_profiles")
    .update(update)
    .eq("id", activeProfile.id)
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", creatorID)
    .eq("status", "active")
    .select(CREATOR_PROFILE_SELECT)
    .maybeSingle();

  if (updateError || !updatedProfile) {
    return jsonResponse({ error: "creator_profile_update_failed" }, 500);
  }

  return jsonResponse({
    action: "update_creator_profile",
    creator_profile: updatedProfile,
  });
}

function normalizedCreatorProfileUpdate(
  body: WriteContentRequest,
): Record<string, unknown> | null {
  const update: Record<string, unknown> = {};

  for (const column of ["positioning", "caption_style"] as const) {
    const value = body[column];
    if (value === undefined) {
      continue;
    }

    if (value !== null && typeof value !== "string") {
      return null;
    }

    update[column] = value?.trim() || null;
  }

  for (
    const column of [
      "voice_rules",
      "content_pillars",
      "never_say",
      "recurring_formats",
    ] as const
  ) {
    const value = body[column];
    if (value === undefined) {
      continue;
    }

    const normalized = normalizedTextArray(value);
    if (normalized === null) {
      return null;
    }

    update[column] = normalized;
  }

  if (Object.keys(update).length === 0) {
    return null;
  }

  update.updated_at = new Date().toISOString();
  return update;
}

function normalizedTextArray(value: unknown): string[] | null {
  if (value === null) {
    return [];
  }

  if (typeof value === "string") {
    return value.split(/\r?\n/)
      .map((item) => item.trim())
      .filter((item) => item.length > 0);
  }

  if (!Array.isArray(value)) {
    return null;
  }

  const normalized: string[] = [];
  for (const item of value) {
    if (typeof item !== "string") {
      return null;
    }
    const trimmedItem = item.trim();
    if (trimmedItem.length > 0) {
      normalized.push(trimmedItem);
    }
  }

  return normalized;
}

function weeklySetupSectionKey(
  section: Record<string, unknown>,
): string | null {
  const rawValue = stringProperty(section, [
    "key",
    "field",
    "column",
    "name",
    "id",
    "section",
    "title",
  ]);

  if (!rawValue) {
    return null;
  }

  return rawValue.trim().toLowerCase().replace(/[\s-]+/g, "_");
}

function sectionValue(section: Record<string, unknown>): unknown {
  if ("value" in section) {
    return section.value;
  }
  if ("items" in section) {
    return section.items;
  }
  if ("text" in section) {
    return section.text;
  }
  if ("summary" in section) {
    return section.summary;
  }
  return undefined;
}

function jsonTextArray(value: string): unknown[] {
  const trimmedValue = value.trim();
  return trimmedValue.length === 0 ? [] : [trimmedValue];
}

function allowedRoles(_action: WriteAction): string[] {
  return [...CONTENT_CREATOR_ROLES];
}

function stableWriteError(value: unknown, action: WriteAction): string {
  if (
    value === "creator_not_found" ||
    value === "daily_card_not_found" ||
    value === "idea_not_found" ||
    value === "archive_upsert_failed" ||
    value === "complete_today_failed" ||
    value === "select_idea_failed" ||
    value === "weekly_setup_not_found" ||
    value === "invalid_weekly_setup_payload" ||
    value === "weekly_setup_update_failed" ||
    value === "invalid_creator_profile_payload" ||
    value === "creator_profile_not_found" ||
    value === "creator_profile_update_failed" ||
    value === "cross_workspace_forbidden" ||
    value === "invalid_review_state_payload" ||
    value === "review_state_update_failed" ||
    value === "published_week_locked"
  ) {
    return value;
  }

  return actionFailureError(action);
}

function actionFailureError(action: WriteAction): string {
  switch (action) {
    case "complete_today":
      return "complete_today_failed";
    case "upsert_archive_decision":
      return "archive_upsert_failed";
    case "select_idea_for_next_open_day":
      return "select_idea_failed";
    case "update_weekly_setup":
      return "weekly_setup_update_failed";
    case "update_creator_profile":
      return "creator_profile_update_failed";
    case "update_daily_card_review_state":
      return "review_state_update_failed";
  }
}

function invalidPayloadError(action: WriteAction): string {
  switch (action) {
    case "update_weekly_setup":
      return "invalid_weekly_setup_payload";
    case "update_creator_profile":
      return "invalid_creator_profile_payload";
    case "update_daily_card_review_state":
      return "invalid_review_state_payload";
    case "complete_today":
    case "upsert_archive_decision":
    case "select_idea_for_next_open_day":
      return "invalid_write_payload";
  }
}

function isWriteAction(value: string | undefined): value is WriteAction {
  return value === "complete_today" ||
    value === "upsert_archive_decision" ||
    value === "select_idea_for_next_open_day" ||
    value === "update_weekly_setup" ||
    value === "update_creator_profile" ||
    value === "update_daily_card_review_state";
}

function isDecisionStatus(value: string | undefined): value is string {
  return typeof value === "string" && DAILY_DECISION_STATUSES.has(value);
}

function isDateString(value: string | undefined): value is string {
  return /^\d{4}-\d{2}-\d{2}$/.test(value ?? "");
}

function isNonBlankString(value: string | undefined): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringProperty(
  record: Record<string, unknown>,
  keys: string[],
): string | null {
  for (const key of keys) {
    const value = record[key];
    if (typeof value === "string" && value.trim().length > 0) {
      return value;
    }
  }

  return null;
}

function isUUID(value: string | undefined | null): value is string {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value ?? "");
}

function isReviewState(value: string | undefined): value is string {
  return value === "open" || value === "ready" || value === "backup";
}
