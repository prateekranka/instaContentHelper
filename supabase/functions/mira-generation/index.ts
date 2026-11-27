import { createClient } from "jsr:@supabase/supabase-js@2";
import { z } from "npm:zod@4.6.7";
import {
  CONTENT_CREATOR_ROLES,
  corsHeaders,
  jsonResponse,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";
import { inputSchema, type MiraOutput, type TodayStep } from "./contracts.ts";
import { leaseSeconds, providerDeadline } from "./job-policy.ts";
import { generate } from "./provider.ts";
import { pictureCount, shotPictures } from "./shot-pictures.ts";
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
  pictureFetch?: typeof fetch;
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
    if (body.input.operation === "todayIdea" && !body.input.angle?.trim()) {
      return jsonResponse({ error: "angle_required" }, 400);
    }
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
    if (body.input.operation === "script" && !body.input.idea) {
      return jsonResponse({ error: "idea_required" }, 400);
    }
    if (
      body.input.operation === "requirements" &&
      !body.input.brief?.original.trim()
    ) return jsonResponse({ error: "brief_source_required" }, 400);
    if (
      body.input.operation === "reviseShot" && (
        body.input.storyboard?.sourceScriptID !== body.input.script?.id ||
        body.input.storyboard?.requirementsRevision !==
          (body.input.brief?.revision ?? 0)
      )
    ) return jsonResponse({ error: "stale_shot_list" }, 409);
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
  const defer = deps.defer ?? ((work: Promise<unknown>) => {
    if (typeof EdgeRuntime !== "undefined") EdgeRuntime.waitUntil(work);
    else return work;
  });
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
    const operation = inputSchema.shape.operation.safeParse(
      result.data.input?.operation,
    );
    const work = runJob(
      admin,
      body.id,
      leaseSeconds(operation.data),
      env,
      deps.generate ?? generate,
    );
    await defer(work);
  }
  const job = toJob(result.data);
  const output = job.output as MiraOutput | undefined;
  let pictures: Awaited<ReturnType<typeof shotPictures>> | undefined;
  if (
    body.action !== "cancel" && job.state === "succeeded" &&
    result.data.picture_count > 0 && output?.storyboard
  ) {
    try {
      pictures = await shotPictures(
        admin,
        body.id,
        output.storyboard.shots,
        env,
        defer,
        deps.pictureFetch,
      );
    } catch {
      console.error(`mira_picture_status_failed ${body.id}`);
    }
  }
  const response = jsonResponse({ job: { ...job, pictures } });
  response.headers.set("Cache-Control", "no-store");
  return response;
}
function toJob(row: Record<string, unknown>) {
  const phase = (row.status === "queued" && Number(row.attempts) > 0) ||
      (row.status === "running" && Number(row.attempts) < 3 &&
        typeof row.lease_until === "string" &&
        Date.parse(row.lease_until) <= Date.now())
    ? "waiting_to_retry"
    : row.status;
  return {
    id: row.id,
    inputRevision: row.input_revision,
    input: row.input,
    state: row.status === "queued" || row.status === "running"
      ? "working"
      : row.status,
    phase,
    step: phase === "running" || phase === "succeeded"
      ? row.step ?? undefined
      : undefined,
    output: row.output ?? undefined,
    error: row.error ?? undefined,
  };
}
async function runJob(
  admin: Admin,
  id: string,
  claimLeaseSeconds: number,
  env: { get(name: string): string | undefined },
  generator: typeof generate,
) {
  const claim = await admin.rpc("mira_claim", {
    p_id: id,
    p_lease_seconds: claimLeaseSeconds,
  });
  if (claim.error) {
    const reason = claim.error.message === "mira_lease_too_short"
      ? "mira_lease_too_short"
      : "mira_claim_failed";
    console.error(`${reason} ${id}`);
    return;
  }
  const row = claim.data?.[0];
  if (!row) return;
  try {
    const input = inputSchema.parse(row.input);
    const signal = providerDeadline(input.operation, row.lease_until);
    const onStep = async (step: TodayStep) => {
      const result = await admin.from("mira_generation_jobs").update({
        step,
        updated_at: new Date().toISOString(),
      }).eq("id", id).eq("lease_id", row.lease_id).eq("status", "running")
        .gt("lease_until", new Date().toISOString());
      if (result.error) console.error(`mira_step_persist_failed ${id}`);
    };
    const output = await generator(input, env, signal, undefined, onStep);
    const result = await admin.from("mira_generation_jobs").update({
      status: "succeeded",
      output,
      picture_count: input.operation === "todayIdea" && output.storyboard
        ? pictureCount(env)
        : null,
      error: null,
      updated_at: new Date().toISOString(),
    }).eq("id", id).eq("lease_id", row.lease_id).eq("status", "running");
    if (result.error) throw Error("result_persist_failed");
  } catch (error) {
    const transient = error instanceof Error &&
      (error.message === "transient_provider_error" ||
        error.name === "TimeoutError" ||
        error.message === "result_persist_failed");
    const reason = failureReason(error);
    console.error(`mira_job_failed ${id} ${reason}`);
    await admin.from("mira_generation_jobs").update({
      status: transient && row.attempts < 3 ? "queued" : "failed",
      error: transient
        ? "Generation interrupted. Retrying is bounded; a prior provider request may have completed."
        : `Generation failed validation or provider configuration. Your saved work is unchanged. (${reason})`,
      next_attempt_at: new Date(Date.now() + row.attempts * 5000).toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", id).eq("lease_id", row.lease_id).eq("status", "running");
  }
}
function failureReason(error: unknown): string {
  if (!(error instanceof Error)) return "unknown_error";
  if (
    error.name === "ZodError" && "issues" in error &&
    Array.isArray(error.issues)
  ) {
    const issue = error.issues[0] as
      | { path?: unknown[]; code?: unknown }
      | undefined;
    const path = (issue?.path ?? []).map((part) => String(part)).join(".");
    return `output_check_failed ${String(issue?.code ?? "")} ${path}`.trim()
      .slice(0, 160);
  }
  if (error.name === "SyntaxError") return "invalid_json_from_provider";
  return error.message.replace(/[^a-zA-Z0-9_. -]/g, "").slice(0, 160) ||
    error.name;
}
declare const EdgeRuntime: undefined | {
  waitUntil(promise: Promise<unknown>): void;
};
if (import.meta.main) Deno.serve((request) => handleMira(request));
