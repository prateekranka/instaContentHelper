import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  assertCreator,
  CONTENT_CREATOR_ROLES,
  corsHeaders,
  jsonResponse,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";
import { exchangeCodeForTokens } from "../_shared/instagram.ts";

type ConnectRequest = {
  creator_id?: string;
  code?: string;
  redirect_uri?: string;
};

export async function handleInstagramConnectRequest(
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
  const appID = Deno.env.get("INSTAGRAM_APP_ID");
  const appSecret = Deno.env.get("INSTAGRAM_APP_SECRET");
  const defaultRedirect = Deno.env.get("INSTAGRAM_REDIRECT_URI");

  if (!supabaseURL || !serviceRoleKey || !appID || !appSecret) {
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

  let body: ConnectRequest;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const creatorID = body.creator_id?.trim();
  const code = body.code?.trim();
  const redirectURI = body.redirect_uri?.trim() || defaultRedirect;
  if (!creatorID || !code || !redirectURI) {
    return jsonResponse({ error: "invalid_connect_payload" }, 400);
  }

  const { session } = authResult;
  const creatorResult = await assertCreator(admin, session, creatorID);
  if (creatorResult) {
    return creatorResult;
  }

  let tokens;
  try {
    tokens = await exchangeCodeForTokens({ code, appID, appSecret, redirectURI });
  } catch (_error) {
    return jsonResponse({ error: "instagram_connect_failed" }, 502);
  }

  const { error: upsertError } = await admin
    .from("creator_instagram_connections")
    .upsert({
      workspace_id: session.workspaceID,
      creator_id: creatorID,
      ig_user_id: tokens.igUserID,
      username: tokens.username,
      account_type: tokens.accountType,
      access_token: tokens.accessToken,
      token_expires_at: tokens.expiresAt,
      scopes: "instagram_business_basic,instagram_business_manage_insights",
      connected_at: new Date().toISOString(),
      revoked_at: null,
    }, { onConflict: "workspace_id,creator_id" });

  if (upsertError) {
    return jsonResponse({ error: "connection_store_failed" }, 500);
  }

  return jsonResponse({
    connected: true,
    username: tokens.username,
    account_type: tokens.accountType,
  });
}

if (import.meta.main) Deno.serve(handleInstagramConnectRequest);
