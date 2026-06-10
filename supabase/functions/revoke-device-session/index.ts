// deno-lint-ignore-file no-explicit-any
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  corsHeaders,
  jsonResponse,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";

type RevokeDependencies = {
  env?: { get: (name: string) => string | undefined };
  createAdminClient?: (url: string, key: string) => any;
  verifySession?: typeof verifyDeviceSession;
  now?: () => Date;
};

export async function handleRevokeDeviceSessionRequest(
  request: Request,
  dependencies: RevokeDependencies = {},
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

  const createAdminClient = dependencies.createAdminClient ??
    ((url, key) =>
      createClient(url, key, {
        auth: { persistSession: false, autoRefreshToken: false },
      }));
  const admin = createAdminClient(supabaseURL, serviceRoleKey);
  const authResult = await (dependencies.verifySession ?? verifyDeviceSession)(
    request,
    admin,
    ["owner", "editor", "creator", "scout"],
  );
  if ("response" in authResult) {
    return authResult.response;
  }

  const nowISO = (dependencies.now?.() ?? new Date()).toISOString();
  const { data, error } = await admin
    .from("device_installations")
    .update({ revoked_at: nowISO, updated_at: nowISO })
    .eq("id", authResult.session.deviceInstallationID)
    .eq("workspace_id", authResult.session.workspaceID)
    .eq("member_id", authResult.session.memberID)
    .is("revoked_at", null)
    .select("id,revoked_at")
    .maybeSingle();
  if (error || !data) {
    return jsonResponse({ error: "session_revoke_failed" }, 500);
  }

  return jsonResponse({
    device_installation_id: data.id,
    revoked_at: data.revoked_at,
  });
}

if (import.meta.main) {
  Deno.serve((request) => handleRevokeDeviceSessionRequest(request));
}
