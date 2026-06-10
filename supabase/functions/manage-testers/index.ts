// deno-lint-ignore-file no-explicit-any
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  corsHeaders,
  jsonResponse,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";

type ManageTesterRequest = {
  action?: "list" | "invite" | "resend" | "revoke";
  email?: string;
  member_id?: string;
  display_name?: string;
};

type ManageDependencies = {
  env?: { get: (name: string) => string | undefined };
  createAdminClient?: (url: string, key: string) => any;
  verifyOwner?: typeof verifyDeviceSession;
  now?: () => Date;
};

export async function handleManageTestersRequest(
  request: Request,
  dependencies: ManageDependencies = {},
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
  const authResult = await (dependencies.verifyOwner ?? verifyDeviceSession)(
    request,
    admin,
    ["owner"],
  );
  if ("response" in authResult) {
    return authResult.response;
  }

  let body: ManageTesterRequest;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const action = body.action;
  if (!action || !["list", "invite", "resend", "revoke"].includes(action)) {
    return jsonResponse({ error: "invalid_tester_action" }, 400);
  }

  const workspaceID = authResult.session.workspaceID;
  if (action === "list") {
    const { data, error } = await admin
      .from("members")
      .select("id,email,display_name,role,status,created_at,updated_at")
      .eq("workspace_id", workspaceID)
      .eq("role", "editor")
      .not("email", "is", null)
      .order("created_at", { ascending: true });
    if (error) {
      return jsonResponse({ error: "tester_list_failed" }, 500);
    }
    return jsonResponse({ testers: data ?? [] });
  }

  const email = normalizeEmail(body.email);
  if ((action === "invite" || action === "resend") && !email) {
    return jsonResponse({ error: "invalid_email" }, 400);
  }

  if (action === "invite") {
    return await inviteTester(
      admin,
      workspaceID,
      email!,
      normalizeDisplayName(body.display_name, email!),
    );
  }

  if (action === "resend") {
    const tester = await findTester(admin, workspaceID, email!, undefined);
    if (tester.error) {
      return jsonResponse({ error: "tester_invite_failed" }, 500);
    }
    if (!tester.data || tester.data.status !== "active") {
      return jsonResponse({ error: "tester_not_found" }, 404);
    }
    const { error } = await sendOTP(admin, email!);
    if (error) {
      return jsonResponse({ error: "tester_invite_failed" }, 500);
    }
    return jsonResponse({ tester: tester.data, otp_sent: true });
  }

  const memberID = body.member_id?.trim();
  if (!memberID || !isUUID(memberID)) {
    return jsonResponse({ error: "tester_not_found" }, 404);
  }
  const tester = await findTester(admin, workspaceID, undefined, memberID);
  if (tester.error) {
    return jsonResponse({ error: "tester_revoke_failed" }, 500);
  }
  if (!tester.data || tester.data.role !== "editor") {
    return jsonResponse({ error: "tester_not_found" }, 404);
  }

  const nowISO = (dependencies.now?.() ?? new Date()).toISOString();
  const { data: revokedMember, error: revokeError } = await admin
    .from("members")
    .update({ status: "revoked", updated_at: nowISO })
    .eq("id", tester.data.id)
    .eq("workspace_id", workspaceID)
    .eq("role", "editor")
    .select("id,email,display_name,role,status,created_at,updated_at")
    .maybeSingle();
  if (revokeError || !revokedMember) {
    return jsonResponse({ error: "tester_revoke_failed" }, 500);
  }

  const { error: installationError } = await admin
    .from("device_installations")
    .update({ revoked_at: nowISO, updated_at: nowISO })
    .eq("workspace_id", workspaceID)
    .eq("member_id", tester.data.id)
    .is("revoked_at", null);
  if (installationError) {
    return jsonResponse({ error: "tester_revoke_failed" }, 500);
  }

  return jsonResponse({ tester: revokedMember, access_revoked: true });
}

async function inviteTester(
  admin: any,
  workspaceID: string,
  email: string,
  displayName: string,
): Promise<Response> {
  const existing = await findTester(admin, workspaceID, email, undefined);
  if (existing.error) {
    return jsonResponse({ error: "tester_invite_failed" }, 500);
  }
  if (existing.data?.status === "active") {
    return jsonResponse({ error: "tester_already_exists" }, 409);
  }

  let authUser = await findAuthUserByEmail(admin, email);
  let createdAuthUser = false;
  if (!authUser) {
    const { data, error } = await admin.auth.admin.createUser({
      email,
      email_confirm: true,
      user_metadata: { display_name: displayName },
    });
    if (error || !data?.user) {
      return jsonResponse({ error: "tester_invite_failed" }, 500);
    }
    authUser = data.user;
    createdAuthUser = true;
  }

  let memberResult;
  if (existing.data) {
    memberResult = await admin
      .from("members")
      .update({
        auth_user_id: authUser.id,
        email,
        display_name: displayName,
        role: "editor",
        status: "active",
        updated_at: new Date().toISOString(),
      })
      .eq("id", existing.data.id)
      .eq("workspace_id", workspaceID)
      .select("id,email,display_name,role,status,created_at,updated_at")
      .single();
  } else {
    memberResult = await admin
      .from("members")
      .insert({
        workspace_id: workspaceID,
        auth_user_id: authUser.id,
        email,
        display_name: displayName,
        role: "editor",
        status: "active",
      })
      .select("id,email,display_name,role,status,created_at,updated_at")
      .single();
  }

  if (memberResult.error || !memberResult.data) {
    if (createdAuthUser) {
      await admin.auth.admin.deleteUser(authUser.id);
    }
    return jsonResponse({ error: "tester_invite_failed" }, 500);
  }

  const { error: otpError } = await sendOTP(admin, email);
  if (otpError) {
    await admin
      .from("members")
      .update({ status: "revoked", updated_at: new Date().toISOString() })
      .eq("id", memberResult.data.id);
    if (createdAuthUser) {
      await admin.auth.admin.deleteUser(authUser.id);
    }
    return jsonResponse({ error: "tester_invite_failed" }, 500);
  }

  return jsonResponse({ tester: memberResult.data, otp_sent: true }, 201);
}

async function findTester(
  admin: any,
  workspaceID: string,
  email?: string,
  memberID?: string,
): Promise<{ data: any; error: any }> {
  let query = admin
    .from("members")
    .select("id,email,display_name,role,status,created_at,updated_at")
    .eq("workspace_id", workspaceID);
  query = memberID ? query.eq("id", memberID) : query.eq("email", email);
  return await query.maybeSingle();
}

async function findAuthUserByEmail(admin: any, email: string): Promise<any> {
  for (let page = 1; page <= 10; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({
      page,
      perPage: 1000,
    });
    if (error) {
      return null;
    }
    const users = data?.users ?? [];
    const match = users.find((user: any) =>
      normalizeEmail(user.email) === email
    );
    if (match || users.length < 1000) {
      return match ?? null;
    }
  }
  return null;
}

function sendOTP(admin: any, email: string): Promise<{ error: any }> {
  return admin.auth.signInWithOtp({
    email,
    options: { shouldCreateUser: false },
  });
}

export function normalizeEmail(value: string | undefined): string | null {
  const normalized = value?.trim().toLowerCase();
  if (
    !normalized || normalized.length > 254 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized)
  ) {
    return null;
  }
  return normalized;
}

function normalizeDisplayName(
  value: string | undefined,
  email: string,
): string {
  return value?.trim() || email.split("@")[0];
}

function isUUID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

if (import.meta.main) {
  Deno.serve((request) => handleManageTestersRequest(request));
}
