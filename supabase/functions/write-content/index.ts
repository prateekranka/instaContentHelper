import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  corsHeaders,
  jsonResponse,
  SupabaseAdminClient,
  VerifiedDeviceSession,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";

type WriteAction =
  | "complete_today"
  | "upsert_archive_decision"
  | "select_idea_for_next_open_day";

type WriteContentRequest = {
  action?: WriteAction;
  creator_id?: string;
  daily_card_id?: string;
  idea_id?: string;
  weekly_plan_id?: string | null;
  archive_date?: string;
  decision?: string | {
    status?: string;
    output_line?: string;
    has_post_thumbnail?: unknown;
  };
  decision_at?: string | null;
  output_line?: string;
  has_post_thumbnail?: unknown;
};

const DAILY_DECISION_STATUSES = new Set([
  "shot",
  "posted",
  "used_backup",
  "saved_for_tomorrow",
  "skipped_intentionally",
]);

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

  if (!isWriteAction(action) || !isUUID(creatorID)) {
    return jsonResponse({ error: "invalid_write_payload" }, 400);
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
  const creatorResult = await assertCreator(admin, session, creatorID);
  if (creatorResult) {
    return creatorResult;
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
  }

  return null;
}

function allowedRoles(action: WriteAction): string[] {
  if (action === "select_idea_for_next_open_day") {
    return ["owner", "editor"];
  }

  return ["owner", "editor", "creator"];
}

function stableWriteError(value: unknown, action: WriteAction): string {
  if (
    value === "creator_not_found" ||
    value === "daily_card_not_found" ||
    value === "idea_not_found" ||
    value === "archive_upsert_failed" ||
    value === "complete_today_failed" ||
    value === "select_idea_failed"
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
  }
}

function isWriteAction(value: string | undefined): value is WriteAction {
  return value === "complete_today" ||
    value === "upsert_archive_decision" ||
    value === "select_idea_for_next_open_day";
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

function isUUID(value: string | undefined | null): value is string {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value ?? "");
}
