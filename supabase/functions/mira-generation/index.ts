import { createClient } from "jsr:@supabase/supabase-js@2";
import { z } from "npm:zod@4.6.7";
import {
  CONTENT_CREATOR_ROLES,
  corsHeaders,
  jsonResponse,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";
import { inputSchema } from "./contracts.ts";
import { generate } from "./provider.ts";
const envelope = z.object({
  action: z.enum(["start", "status", "cancel"]),
  id: z.uuid(),
  creatorID: z.uuid(),
  inputRevision: z.number().int().nonnegative().optional(),
  input: inputSchema.optional(),
  consentVersion: z.literal(1).optional(),
}).strict();
// deno-lint-ignore no-explicit-any
type Admin = any;
type Dependencies = {
  env?: { get(name: string): string | undefined };
  admin?: Admin;
  verify?: typeof verifyDeviceSession;
  generate?: typeof generate;
  defer?: (promise: Promise<unknown>) => void;
};
export async function handleMira(
  request: Request,
  deps: Dependencies = {},
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }
  if (Number(request.headers.get("content-length") ?? 0) > 100000) {
    return jsonResponse({ error: "input_too_large" }, 413);
  }
  const env = deps.env ?? Deno.env;
  const url = env.get("SUPABASE_URL"),
    key = env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    return jsonResponse({ error: "server_not_configured" }, 503);
  }
  const admin = deps.admin ??
    createClient(url, key, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  const auth = await (deps.verify ?? verifyDeviceSession)(request, admin, [
    ...CONTENT_CREATOR_ROLES,
  ]);
  if ("response" in auth) return auth.response;
  const parsed = envelope.safeParse(await request.json().catch(() => null));
  if (!parsed.success) return jsonResponse({ error: "invalid_input" }, 400);
  const body = parsed.data, session = auth.session;
  const creator = await admin.from("creators").select("id").eq(
    "id",
    body.creatorID,
  ).eq("workspace_id", session.workspaceID).maybeSingle();
  if (creator.error) {
    return jsonResponse({ error: "creator_lookup_failed" }, 503);
  }
  if (!creator.data) return jsonResponse({ error: "not_found" }, 404);
  const scope = () =>
    admin.from("mira_generation_jobs").select("*").eq("id", body.id).eq(
      "workspace_id",
      session.workspaceID,
    ).eq("creator_id", body.creatorID).eq("member_id", session.memberID)
      .maybeSingle();
  if (body.action === "start") {
    if (
      !body.input || body.inputRevision === undefined ||
      body.consentVersion !== 1
    ) return jsonResponse({ error: "input_and_consent_required" }, 400);
    if (
      body.input.operation !== "requirements" && body.input.brief &&
      !body.input.brief.confirmed
    ) return jsonResponse({ error: "brief_confirmation_required" }, 400);
    if (
      ["storyboard", "reviseShot", "reviseStoryboard"].includes(
        body.input.operation,
      ) && !body.input.script
    ) return jsonResponse({ error: "script_required" }, 400);
    if (body.input.operation === "reviseScript" && !body.input.script) {
      return jsonResponse({ error: "script_required" }, 400);
    }
    if (
      body.input.operation === "reviseShot" &&
      (!body.input.targetShotID ||
        !body.input.storyboard?.shots.some((x) =>
          x.id === body.input!.targetShotID
        ))
    ) return jsonResponse({ error: "invalid_target" }, 400);
    const result = await admin.rpc("mira_enqueue", {
      p_id: body.id,
      p_workspace: session.workspaceID,
      p_creator: body.creatorID,
      p_member: session.memberID,
      p_revision: body.inputRevision,
      p_input: body.input,
    });
    if (result.error) {
      return jsonResponse({
        error: result.error.message?.includes("rate_limited") ||
            result.error.message?.includes("active_jobs")
          ? "rate_limited"
          : "job_conflict",
      }, 409);
    }
  }
  let result = await scope();
  if (result.error) return jsonResponse({ error: "job_lookup_failed" }, 503);
  if (!result.data) return jsonResponse({ error: "not_found" }, 404);
  if (body.action === "cancel") {
    const cancelled = await admin.from("mira_generation_jobs").update({
      status: "cancelled",
      updated_at: new Date().toISOString(),
    }).eq("id", body.id).eq("member_id", session.memberID).in("status", [
      "queued",
      "running",
    ]).select("*").maybeSingle();
    if (cancelled.error) return jsonResponse({ error: "cancel_failed" }, 503);
    result = await scope();
  } else if (["queued", "running"].includes(result.data.status)) {
    const work = runJob(admin, body.id, env, deps.generate ?? generate);
    if (deps.defer) deps.defer(work);
    else if (typeof EdgeRuntime !== "undefined") EdgeRuntime.waitUntil(work);
    else await work;
  }
  return jsonResponse({ job: toJob(result.data) });
}
function toJob(row: Record<string, unknown>) {
  return {
    id: row.id,
    inputRevision: row.input_revision,
    input: row.input,
    state: row.status === "queued" || row.status === "running"
      ? "working"
      : row.status,
    output: row.output ?? undefined,
    error: row.error ?? undefined,
  };
}
async function runJob(
  admin: Admin,
  id: string,
  env: { get(name: string): string | undefined },
  generator: typeof generate,
) {
  const claim = await admin.rpc("mira_claim", { p_id: id });
  const row = claim.data?.[0];
  if (claim.error || !row) return;
  try {
    const input = inputSchema.parse(row.input),
      output = await generator(input, env);
    const result = await admin.from("mira_generation_jobs").update({
      status: "succeeded",
      output,
      error: null,
      updated_at: new Date().toISOString(),
    }).eq("id", id).eq("lease_id", row.lease_id).eq("status", "running");
    if (result.error) throw Error("result_persist_failed");
  } catch (error) {
    const transient = error instanceof Error &&
      (error.message === "transient_provider_error" ||
        error.name === "TimeoutError" ||
        error.message === "result_persist_failed");
    await admin.from("mira_generation_jobs").update({
      status: transient && row.attempts < 3 ? "queued" : "failed",
      error: transient
        ? "Generation interrupted. Retrying is bounded; a prior provider request may have completed."
        : "Generation failed validation or provider configuration. Your saved work is unchanged.",
      next_attempt_at: new Date(Date.now() + row.attempts * 5000).toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", id).eq("lease_id", row.lease_id).eq("status", "running");
  }
}
declare const EdgeRuntime: undefined | {
  waitUntil(promise: Promise<unknown>): void;
};
if (import.meta.main) Deno.serve((request) => handleMira(request));
