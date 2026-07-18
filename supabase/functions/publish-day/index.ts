import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  corsHeaders,
  jsonResponse,
  SupabaseAdminClient,
  VerifiedDeviceSession,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";

type PublishDayRequest = {
  creator_id?: string;
  daily_card_id?: string;
};

type PublishDayAdminClient = SupabaseAdminClient & {
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
  verifySession?: (
    request: Request,
    admin: SupabaseAdminClient,
    allowedRoles: string[],
  ) => Promise<{ session: VerifiedDeviceSession } | { response: Response }>;
  env?: { get: (name: string) => string | undefined };
};

const STABLE_RPC_ERRORS = new Set([
  "daily_card_not_found",
  "daily_card_not_publishable",
  "cross_workspace_forbidden",
  "invalid_publish_payload",
]);

export async function handlePublishDayRequest(
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
      })) as PublishDayAdminClient;

  const verifySession = dependencies.verifySession ?? verifyDeviceSession;
  const authResult = await verifySession(request, admin, ["owner", "editor"]);
  if ("response" in authResult) {
    return authResult.response;
  }

  let body: PublishDayRequest;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  if (!isUUID(body.creator_id) || !isUUID(body.daily_card_id)) {
    return jsonResponse({ error: "invalid_publish_payload" }, 400);
  }

  const payload = {
    workspace_id: authResult.session.workspaceID,
    creator_id: body.creator_id,
    daily_card_id: body.daily_card_id,
  };
  const { data, error } = await admin.rpc("publish_day_atomic", { payload });
  if (error) {
    return jsonResponse({ error: "daily_card_publish_failed" }, 500);
  }

  const result = data as Record<string, unknown> | null;
  if (typeof result?.error === "string") {
    const code = STABLE_RPC_ERRORS.has(result.error)
      ? result.error
      : "daily_card_publish_failed";
    const status = typeof result.status === "number" ? result.status : 500;
    return jsonResponse({ error: code }, status);
  }

  if (
    !result ||
    !isUUID(result.daily_card_id) ||
    !isDateString(result.scheduled_date) ||
    typeof result.published_at !== "string"
  ) {
    return jsonResponse({ error: "invalid_publish_day_result" }, 500);
  }

  return jsonResponse(result);
}

function isUUID(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

function isDateString(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value);
}

if (import.meta.main) {
  Deno.serve((request) => handlePublishDayRequest(request));
}
