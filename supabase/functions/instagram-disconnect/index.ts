import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  assertCreator,
  CONTENT_CREATOR_ROLES,
  corsHeaders,
  jsonResponse,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";

type DisconnectRequest = { creator_id?: string };

export async function handleInstagramDisconnectRequest(
  request: Request,
): Promise<Response> {
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
    [...CONTENT_CREATOR_ROLES],
  );
  if ("response" in authResult) {
    return authResult.response;
  }

  let body: DisconnectRequest;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const creatorID = body.creator_id?.trim();
  if (!creatorID) {
    return jsonResponse({ error: "invalid_disconnect_payload" }, 400);
  }

  const { session } = authResult;
  const creatorResult = await assertCreator(admin, session, creatorID);
  if (creatorResult) {
    return creatorResult;
  }

  const { error: updateError } = await admin
    .from("creator_instagram_connections")
    .update({ revoked_at: new Date().toISOString(), access_token: "" })
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", creatorID)
    .is("revoked_at", null);

  if (updateError) {
    return jsonResponse({ error: "disconnect_failed" }, 500);
  }

  return jsonResponse({ connected: false });
}

if (import.meta.main) Deno.serve(handleInstagramDisconnectRequest);
