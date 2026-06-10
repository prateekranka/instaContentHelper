// deno-lint-ignore-file no-explicit-any
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  corsHeaders,
  jsonResponse,
  sha256Hex,
} from "../_shared/device-auth.ts";

type ExchangeAuthSessionRequest = {
  device_name?: string;
  platform?: string;
  device_installation_id?: string;
};

type AuthUser = {
  id: string;
  email?: string | null;
};

type MemberRecord = {
  id: string;
  workspace_id: string;
  email: string | null;
  display_name: string;
  role: string;
  status: string;
};

type ExchangeDependencies = {
  env?: { get: (name: string) => string | undefined };
  createAdminClient?: (url: string, key: string) => any;
  now?: () => Date;
  generateDeviceToken?: () => string;
};

export async function handleExchangeAuthSessionRequest(
  request: Request,
  dependencies: ExchangeDependencies = {},
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

  const jwt = bearerToken(request.headers.get("Authorization"));
  if (!jwt) {
    return jsonResponse({ error: "invalid_auth_session" }, 401);
  }

  let body: ExchangeAuthSessionRequest;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const platform = body.platform ?? "ios";
  const deviceName = normalizeOptionalText(body.device_name);
  const installationID = normalizeOptionalText(body.device_installation_id);
  if (platform !== "ios" || (installationID && !isUUID(installationID))) {
    return jsonResponse({ error: "invalid_auth_session" }, 400);
  }

  const createAdminClient = dependencies.createAdminClient ??
    ((url, key) =>
      createClient(url, key, {
        auth: { persistSession: false, autoRefreshToken: false },
      }));
  const admin = createAdminClient(supabaseURL, serviceRoleKey);
  const { data: authData, error: authError } = await admin.auth.getUser(jwt);
  const user = authData?.user as AuthUser | undefined;
  if (authError || !user?.id) {
    return jsonResponse({ error: "invalid_auth_session" }, 401);
  }

  const { data: memberships, error: memberError } = await admin
    .from("members")
    .select("id,workspace_id,email,display_name,role,status")
    .eq("auth_user_id", user.id)
    .limit(3);
  if (memberError) {
    return jsonResponse({ error: "device_session_failed" }, 500);
  }

  if (!Array.isArray(memberships) || memberships.length === 0) {
    return jsonResponse({ error: "tester_not_approved" }, 403);
  }

  const activeMemberships = memberships.filter((membership) =>
    membership.status === "active"
  );
  if (activeMemberships.length === 0) {
    return jsonResponse({ error: "member_revoked" }, 403);
  }

  if (activeMemberships.length !== 1) {
    return jsonResponse({ error: "workspace_unavailable" }, 409);
  }

  const member = activeMemberships[0] as MemberRecord;

  const { data: workspace, error: workspaceError } = await admin
    .from("workspaces")
    .select("id,name")
    .eq("id", member.workspace_id)
    .eq("status", "active")
    .maybeSingle();
  if (workspaceError || !workspace) {
    return jsonResponse({ error: "workspace_unavailable" }, 404);
  }

  const { data: creator, error: creatorError } = await admin
    .from("creators")
    .select("id,display_name")
    .eq("workspace_id", member.workspace_id)
    .eq("status", "active")
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();
  if (creatorError || !creator) {
    return jsonResponse({ error: "creator_unavailable" }, 404);
  }

  const nowISO = (dependencies.now?.() ?? new Date()).toISOString();
  const deviceToken = dependencies.generateDeviceToken?.() ??
    generateDeviceToken();
  const tokenHash = await sha256Hex(deviceToken);

  let installation: { id: string; paired_at: string } | null = null;
  if (installationID) {
    const { data, error } = await admin
      .from("device_installations")
      .update({
        token_hash: tokenHash,
        device_name: deviceName,
        platform,
        paired_at: nowISO,
        last_seen_at: nowISO,
        revoked_at: null,
      })
      .eq("id", installationID)
      .eq("workspace_id", member.workspace_id)
      .eq("member_id", member.id)
      .select("id,paired_at")
      .maybeSingle();
    if (error) {
      return jsonResponse({ error: "device_session_failed" }, 500);
    }
    installation = data;
  }

  if (!installation) {
    const { data, error } = await admin
      .from("device_installations")
      .insert({
        workspace_id: member.workspace_id,
        member_id: member.id,
        device_name: deviceName,
        platform,
        token_hash: tokenHash,
        paired_at: nowISO,
        last_seen_at: nowISO,
      })
      .select("id,paired_at")
      .single();
    if (error || !data) {
      return jsonResponse({ error: "device_session_failed" }, 500);
    }
    installation = data;
  }

  if (!installation) {
    return jsonResponse({ error: "device_session_failed" }, 500);
  }

  return jsonResponse({
    workspace_id: workspace.id,
    workspace_name: workspace.name,
    creator_id: creator.id,
    creator_display_name: creator.display_name,
    member_id: member.id,
    member_role: member.role,
    member_email: member.email ?? user.email ?? null,
    device_installation_id: installation.id,
    device_token: deviceToken,
    paired_at: installation.paired_at,
  });
}

export function bearerToken(value: string | null): string | null {
  const match = value?.match(/^Bearer\s+(.+)$/i);
  return match?.[1]?.trim() || null;
}

function normalizeOptionalText(value: string | undefined): string | null {
  const normalized = value?.trim();
  return normalized ? normalized : null;
}

function isUUID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

function generateDeviceToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  const binary = Array.from(bytes, (byte) => String.fromCharCode(byte)).join(
    "",
  );
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/g,
    "",
  );
}

if (import.meta.main) {
  Deno.serve((request) => handleExchangeAuthSessionRequest(request));
}
