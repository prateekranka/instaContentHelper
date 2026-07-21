import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  corsHeaders,
  jsonResponse,
  SupabaseAdminClient,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";

type UnpublishDayRequest = {
  creator_id?: string;
  scheduled_date?: string;
  daily_card_id?: string;
};

type UnpublishDayAdminClient = SupabaseAdminClient & {
  rpc: (
    functionName: string,
    args: Record<string, unknown>,
  ) => Promise<{
    data: unknown;
    error: { message?: string } | null;
  }>;
};

type HandlerDependencies = {
  createAdminClient?: (
    supabaseURL: string,
    serviceRoleKey: string,
  ) => SupabaseAdminClient;
  env?: { get: (name: string) => string | undefined };
};

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function handleUnpublishDayRequest(
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

  const admin =
    (dependencies.createAdminClient
      ? dependencies.createAdminClient(supabaseURL, serviceRoleKey)
      : createClient(supabaseURL, serviceRoleKey, {
        auth: { persistSession: false },
      })) as UnpublishDayAdminClient;

  const authResult = await verifyDeviceSession(request, admin, [
    "owner",
    "editor",
    "creator",
  ]);
  if ("response" in authResult) {
    return authResult.response;
  }

  let body: UnpublishDayRequest;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const creatorID = body.creator_id?.trim();
  const scheduledDate = body.scheduled_date?.trim();
  const dailyCardID = body.daily_card_id?.trim();

  if (!creatorID || !UUID_PATTERN.test(creatorID)) {
    return jsonResponse({ error: "invalid_unpublish_day_payload" }, 400);
  }

  if (!scheduledDate && !dailyCardID) {
    return jsonResponse({ error: "invalid_unpublish_day_payload" }, 400);
  }

  if (scheduledDate && !DATE_PATTERN.test(scheduledDate)) {
    return jsonResponse({ error: "invalid_unpublish_day_payload" }, 400);
  }

  if (dailyCardID && !UUID_PATTERN.test(dailyCardID)) {
    return jsonResponse({ error: "invalid_unpublish_day_payload" }, 400);
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

  const payload: Record<string, unknown> = {
    workspace_id: session.workspaceID,
    creator_id: creatorID,
  };
  if (scheduledDate) {
    payload.scheduled_date = scheduledDate;
  }
  if (dailyCardID) {
    payload.daily_card_id = dailyCardID;
  }

  const { data, error } = await admin.rpc("unpublish_day", { payload });
  if (error) {
    return jsonResponse({ error: "unpublish_day_failed" }, 500);
  }

  const result = (data ?? {}) as Record<string, unknown>;
  if (typeof result.error === "string" && result.error.length > 0) {
    const status = typeof result.status === "number" ? result.status : 500;
    return jsonResponse({ error: stableError(result.error) }, status);
  }

  return jsonResponse({
    daily_card_id: result.daily_card_id,
    scheduled_date: result.scheduled_date,
    status: result.status ?? "draft",
    previous_status: result.previous_status,
    cleared_live_decision: result.cleared_live_decision === true,
    archive_retained: result.archive_retained === true,
    weekly_plan_id: result.weekly_plan_id,
  });
}

async function assertCreator(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
): Promise<Response | null> {
  const { data: creator, error } = await admin
    .from("creators")
    .select("id")
    .eq("id", creatorID)
    .eq("workspace_id", workspaceID)
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

function stableError(code: string): string {
  switch (code) {
    case "invalid_unpublish_day_payload":
    case "daily_card_not_found":
    case "daily_card_already_draft":
    case "daily_card_not_ready":
    case "unpublish_day_conflict":
      return code;
    default:
      return "unpublish_day_failed";
  }
}

if (import.meta.main) {
  Deno.serve((request) => handleUnpublishDayRequest(request));
}
