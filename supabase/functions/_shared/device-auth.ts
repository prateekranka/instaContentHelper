export type SupabaseAdminClient = {
  from: (table: string) => any;
};

export type VerifiedDeviceSession = {
  deviceInstallationID: string;
  workspaceID: string;
  memberID: string;
  role: string;
};

export async function verifyDeviceSession(
  request: Request,
  admin: SupabaseAdminClient,
  allowedRoles: string[],
): Promise<{ session: VerifiedDeviceSession } | { response: Response }> {
  const deviceToken = request.headers.get("x-mco-device-token")?.trim();

  if (!deviceToken) {
    return { response: jsonResponse({ error: "missing_device_token" }, 401) };
  }

  const tokenHash = await sha256Hex(deviceToken);
  const { data: installation, error: installationError } = await admin
    .from("device_installations")
    .select("id, workspace_id, member_id, revoked_at")
    .eq("token_hash", tokenHash)
    .is("revoked_at", null)
    .maybeSingle();

  if (installationError) {
    return { response: jsonResponse({ error: "device_lookup_failed" }, 500) };
  }

  if (!installation) {
    return { response: jsonResponse({ error: "invalid_device_token" }, 401) };
  }

  const { data: member, error: memberError } = await admin
    .from("members")
    .select("id, workspace_id, role, status")
    .eq("id", installation.member_id)
    .eq("workspace_id", installation.workspace_id)
    .eq("status", "active")
    .maybeSingle();

  if (memberError) {
    return { response: jsonResponse({ error: "member_lookup_failed" }, 500) };
  }

  if (!member || !allowedRoles.includes(member.role)) {
    return { response: jsonResponse({ error: "role_not_allowed" }, 403) };
  }

  await admin
    .from("device_installations")
    .update({ last_seen_at: new Date().toISOString() })
    .eq("id", installation.id);

  return {
    session: {
      deviceInstallationID: installation.id,
      workspaceID: installation.workspace_id,
      memberID: member.id,
      role: member.role,
    },
  };
}

export async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function jsonResponse(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-mco-device-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
