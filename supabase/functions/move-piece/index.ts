import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  corsHeaders,
  jsonResponse,
  type SupabaseAdminClient,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";

type Admin = SupabaseAdminClient & {
  rpc: (
    name: string,
    args: Record<string, unknown>,
  ) => Promise<{ data: unknown; error: unknown }>;
};
type Dependencies = {
  createAdminClient?: (url: string, key: string) => SupabaseAdminClient;
  env?: { get: (name: string) => string | undefined };
};
const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function validDate(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
    Number.isFinite(Date.parse(value)) &&
    new Date(value).toISOString().slice(0, 10) === value;
}

export async function handleMovePieceRequest(
  request: Request,
  dependencies: Dependencies = {},
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }
  const env = dependencies.env ?? Deno.env;
  const url = env.get("SUPABASE_URL"),
    key = env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    return jsonResponse({ error: "missing_function_secrets" }, 500);
  }
  const admin = (dependencies.createAdminClient?.(url, key) ??
    createClient(url, key, { auth: { persistSession: false } })) as Admin;
  const auth = await verifyDeviceSession(request, admin, [
    "owner",
    "editor",
    "creator",
  ]);
  if ("response" in auth) return auth.response;
  let body: Record<string, unknown>;
  try {
    const value = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      return jsonResponse({ error: "invalid_move_piece_payload" }, 400);
    }
    body = value;
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }
  if (typeof body.piece_id !== "string" || !uuid.test(body.piece_id)) {
    return jsonResponse({ error: "invalid_piece_id" }, 400);
  }
  if (
    typeof body.creator_id !== "string" || !uuid.test(body.creator_id) ||
    !validDate(body.scheduled_date) ||
    !validDate(body.target_scheduled_date) ||
    typeof body.idempotency_key !== "string" ||
    !body.idempotency_key.trim() || body.idempotency_key.trim().length > 200
  ) return jsonResponse({ error: "invalid_move_piece_payload" }, 400);
  const creator = await admin.from("creators").select("id").eq(
    "id",
    body.creator_id,
  ).eq("workspace_id", auth.session.workspaceID).eq("status", "active")
    .maybeSingle();
  if (creator.error) {
    return jsonResponse({ error: "creator_lookup_failed" }, 500);
  }
  if (!creator.data) return jsonResponse({ error: "creator_not_found" }, 404);
  const { data, error } = await admin.rpc("move_content_piece", {
    payload: {
      workspace_id: auth.session.workspaceID,
      creator_id: body.creator_id,
      piece_id: body.piece_id,
      scheduled_date: body.scheduled_date,
      target_scheduled_date: body.target_scheduled_date,
      idempotency_key: body.idempotency_key.trim(),
    },
  });
  if (error || !data || typeof data !== "object") {
    return jsonResponse({ error: "move_piece_failed" }, 500);
  }
  const result = data as Record<string, unknown>;
  if (typeof result.error === "string") {
    const allowed = [
      "invalid_piece_id",
      "invalid_move_piece_payload",
      "piece_not_found",
      "piece_scope_mismatch",
      "piece_removed",
      "piece_date_conflict",
      "piece_generation_running",
      "idempotency_key_conflict",
    ];
    return jsonResponse({
      error: allowed.includes(result.error)
        ? result.error
        : "move_piece_failed",
    }, typeof result.status === "number" ? result.status : 500);
  }
  return jsonResponse(result);
}
if (import.meta.main) Deno.serve((request) => handleMovePieceRequest(request));
