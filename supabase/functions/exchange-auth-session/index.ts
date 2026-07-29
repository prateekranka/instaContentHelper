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
  user_metadata?: Record<string, unknown> | null;
};

type MemberRecord = {
  id: string;
  workspace_id: string;
  email: string | null;
  display_name: string;
  role: string;
  status: string;
};

type WorkspaceRecord = {
  id: string;
  name: string;
};

type CreatorRecord = {
  id: string;
  display_name: string;
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

  let member: MemberRecord;
  let workspace: WorkspaceRecord;
  let creator: CreatorRecord;

  if (!Array.isArray(memberships) || memberships.length === 0) {
    const provisioned = await autoProvisionCreatorMembership(admin, user);
    if (!provisioned.ok) {
      return jsonResponse({ error: provisioned.error }, provisioned.status);
    }
    member = provisioned.member;
    workspace = provisioned.workspace;
    creator = provisioned.creator;
  } else {
    const activeMemberships = memberships.filter((membership) =>
      membership.status === "active"
    );
    if (activeMemberships.length === 0) {
      return jsonResponse({ error: "member_revoked" }, 403);
    }

    if (activeMemberships.length !== 1) {
      return jsonResponse({ error: "workspace_unavailable" }, 409);
    }

    member = activeMemberships[0] as MemberRecord;

    const { data: existingWorkspace, error: workspaceError } = await admin
      .from("workspaces")
      .select("id,name")
      .eq("id", member.workspace_id)
      .eq("status", "active")
      .maybeSingle();
    if (workspaceError || !existingWorkspace) {
      return jsonResponse({ error: "workspace_unavailable" }, 404);
    }
    workspace = existingWorkspace as WorkspaceRecord;

    const { data: existingCreator, error: creatorError } = await admin
      .from("creators")
      .select("id,display_name")
      .eq("workspace_id", member.workspace_id)
      .eq("status", "active")
      .order("created_at", { ascending: true })
      .limit(1)
      .maybeSingle();
    if (creatorError || !existingCreator) {
      return jsonResponse({ error: "creator_unavailable" }, 404);
    }
    creator = existingCreator as CreatorRecord;
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

async function autoProvisionCreatorMembership(
  admin: any,
  user: AuthUser,
): Promise<
  | {
    ok: true;
    member: MemberRecord;
    workspace: WorkspaceRecord;
    creator: CreatorRecord;
  }
  | { ok: false; error: string; status: number }
> {
  // Re-check in case another request provisioned between the first lookup and now.
  const { data: racedMemberships, error: raceError } = await admin
    .from("members")
    .select("id,workspace_id,email,display_name,role,status")
    .eq("auth_user_id", user.id)
    .eq("status", "active")
    .limit(3);
  if (raceError) {
    return { ok: false, error: "device_session_failed", status: 500 };
  }
  if (Array.isArray(racedMemberships) && racedMemberships.length === 1) {
    const member = racedMemberships[0] as MemberRecord;
    const { data: workspace } = await admin
      .from("workspaces")
      .select("id,name")
      .eq("id", member.workspace_id)
      .eq("status", "active")
      .maybeSingle();
    const { data: creator } = await admin
      .from("creators")
      .select("id,display_name")
      .eq("workspace_id", member.workspace_id)
      .eq("status", "active")
      .order("created_at", { ascending: true })
      .limit(1)
      .maybeSingle();
    if (workspace && creator) {
      return {
        ok: true,
        member,
        workspace: workspace as WorkspaceRecord,
        creator: creator as CreatorRecord,
      };
    }
  }

  const displayName = creatorDisplayName(user);
  const email = normalizeEmail(user.email);

  const { data: workspace, error: workspaceError } = await admin
    .from("workspaces")
    .insert({
      name: `${displayName}'s Workspace`,
      status: "active",
    })
    .select("id,name")
    .single();
  if (workspaceError || !workspace) {
    return { ok: false, error: "device_session_failed", status: 500 };
  }

  const { data: creator, error: creatorError } = await admin
    .from("creators")
    .insert({
      workspace_id: workspace.id,
      display_name: displayName,
      status: "active",
    })
    .select("id,display_name")
    .single();
  if (creatorError || !creator) {
    await admin.from("workspaces").delete().eq("id", workspace.id);
    return { ok: false, error: "device_session_failed", status: 500 };
  }

  const { data: member, error: memberError } = await admin
    .from("members")
    .insert({
      workspace_id: workspace.id,
      auth_user_id: user.id,
      email,
      display_name: displayName,
      role: "creator",
      status: "active",
    })
    .select("id,workspace_id,email,display_name,role,status")
    .single();
  if (memberError || !member) {
    await admin.from("workspaces").delete().eq("id", workspace.id);
    return { ok: false, error: "device_session_failed", status: 500 };
  }

  return {
    ok: true,
    member: member as MemberRecord,
    workspace: workspace as WorkspaceRecord,
    creator: creator as CreatorRecord,
  };
}

function creatorDisplayName(user: AuthUser): string {
  const metadataName = normalizeOptionalText(
    typeof user.user_metadata?.full_name === "string"
      ? user.user_metadata.full_name
      : typeof user.user_metadata?.name === "string"
      ? user.user_metadata.name
      : undefined,
  );
  if (metadataName) return metadataName;

  const emailLocal = normalizeEmail(user.email)?.split("@")[0];
  if (emailLocal) return emailLocal;

  return "Creator";
}

function normalizeEmail(value: string | null | undefined): string | null {
  const normalized = value?.trim().toLowerCase();
  return normalized ? normalized : null;
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
