import { createClient } from "jsr:@supabase/supabase-js@2";

type PairDeviceRequest = {
  invite_code?: string;
  device_name?: string;
  platform?: string;
};

type DeviceInvite = {
  id: string;
  workspace_id: string;
  role_granted: string;
  expires_at: string;
  use_limit: number;
  used_count: number;
  revoked_at: string | null;
};

type SupabaseAdminClient = {
  from: (table: string) => any;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
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

  let body: PairDeviceRequest;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const inviteCode = normalizeInviteCode(body.invite_code);
  const platform = body.platform ?? "ios";
  const deviceName = normalizeDeviceName(body.device_name);

  if (!inviteCode) {
    return jsonResponse({ error: "blank_invite_code" }, 400);
  }

  if (platform !== "ios") {
    return jsonResponse({ error: "unsupported_platform" }, 400);
  }

  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const codeHash = await sha256Hex(inviteCode);
  const { data: invite, error: inviteError } = await admin
    .from("device_invites")
    .select("id, workspace_id, role_granted, expires_at, use_limit, used_count, revoked_at")
    .eq("code_hash", codeHash)
    .maybeSingle();

  if (inviteError) {
    return jsonResponse({ error: "invite_lookup_failed" }, 500);
  }

  if (!invite) {
    return jsonResponse({ error: "invalid_invite_code" }, 404);
  }

  const deviceInvite = invite as DeviceInvite;

  const now = new Date();
  const nowISO = now.toISOString();

  if (deviceInvite.revoked_at !== null) {
    return jsonResponse({ error: "invite_revoked" }, 410);
  }

  if (Date.parse(deviceInvite.expires_at) <= now.getTime()) {
    return jsonResponse({ error: "invite_expired" }, 410);
  }

  if (deviceInvite.used_count >= deviceInvite.use_limit) {
    return jsonResponse({ error: "invite_exhausted" }, 409);
  }

  const { data: workspace, error: workspaceError } = await admin
    .from("workspaces")
    .select("id, name")
    .eq("id", deviceInvite.workspace_id)
    .eq("status", "active")
    .single();

  if (workspaceError || !workspace) {
    return jsonResponse({ error: "workspace_unavailable" }, 404);
  }

  const { data: creator, error: creatorError } = await admin
    .from("creators")
    .select("id, display_name")
    .eq("workspace_id", deviceInvite.workspace_id)
    .eq("status", "active")
    .order("created_at", { ascending: true })
    .limit(1)
    .single();

  if (creatorError || !creator) {
    return jsonResponse({ error: "creator_unavailable" }, 404);
  }

  const { data: consumedInvite, error: consumeError } = await admin
    .from("device_invites")
    .update({ used_count: deviceInvite.used_count + 1 })
    .eq("id", deviceInvite.id)
    .eq("used_count", deviceInvite.used_count)
    .is("revoked_at", null)
    .gt("expires_at", nowISO)
    .lt("used_count", deviceInvite.use_limit)
    .select("id")
    .single();

  if (consumeError || !consumedInvite) {
    return jsonResponse({ error: "invite_already_consumed" }, 409);
  }

  const { data: member, error: memberError } = await admin
    .from("members")
    .insert({
      workspace_id: deviceInvite.workspace_id,
      display_name: deviceName ?? "Paired iPhone",
      role: deviceInvite.role_granted,
      status: "active",
    })
    .select("id, role")
    .single();

  if (memberError || !member) {
    await rollbackInvite(admin, deviceInvite);
    return jsonResponse({ error: "member_create_failed" }, 500);
  }

  const deviceToken = generateDeviceToken();
  const tokenHash = await sha256Hex(deviceToken);

  const { data: installation, error: installationError } = await admin
    .from("device_installations")
    .insert({
      workspace_id: deviceInvite.workspace_id,
      member_id: member.id,
      device_name: deviceName,
      platform,
      token_hash: tokenHash,
      last_seen_at: nowISO,
    })
    .select("id, paired_at")
    .single();

  if (installationError || !installation) {
    await admin.from("members").delete().eq("id", member.id);
    await rollbackInvite(admin, deviceInvite);
    return jsonResponse({ error: "device_installation_failed" }, 500);
  }

  return jsonResponse({
    workspace_id: workspace.id,
    workspace_name: workspace.name,
    creator_id: creator.id,
    creator_display_name: creator.display_name,
    member_id: member.id,
    member_role: member.role,
    device_installation_id: installation.id,
    device_token: deviceToken,
    paired_at: installation.paired_at,
  });
});

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function normalizeInviteCode(value: string | undefined): string | null {
  const normalized = value?.trim().replace(/\s+/g, "").toUpperCase();
  return normalized && normalized.length > 0 ? normalized : null;
}

function normalizeDeviceName(value: string | undefined): string | null {
  const normalized = value?.trim();
  return normalized && normalized.length > 0 ? normalized : null;
}

async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function generateDeviceToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  const binary = Array.from(bytes, (byte) => String.fromCharCode(byte)).join("");
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

async function rollbackInvite(admin: SupabaseAdminClient, invite: DeviceInvite) {
  await admin
    .from("device_invites")
    .update({ used_count: invite.used_count })
    .eq("id", invite.id)
    .eq("used_count", invite.used_count + 1);
}
