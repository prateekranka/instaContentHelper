import { createClient } from "jsr:@supabase/supabase-js@2";
import { z } from "npm:zod@4.6.7";
import {
  CONTENT_CREATOR_ROLES,
  corsHeaders,
  jsonResponse,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";
import {
  inputSchema,
  type MiraInput,
  type MiraOutput,
  operationSchema,
  type TodayStep,
} from "./contracts.ts";
import { leaseSeconds, providerDeadline } from "./job-policy.ts";
import { isPhaseEInput } from "./phase-e.ts";
import { generate } from "./provider.ts";
import { pictureCount, shotPictures } from "./shot-pictures.ts";
const envelope = z.object({
  action: z.enum(["start", "status", "cancel"]),
  id: z.uuid(),
  creatorID: z.uuid(),
  inputRevision: z.number().int().nonnegative().optional(),
  input: inputSchema.optional(),
  consentVersion: z.literal(1).optional(),
  pictures: z.boolean().optional(),
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
  let jobID = body.id;
  const scope = () =>
    admin.from("mira_generation_jobs").select("*").eq("id", jobID).eq(
      "workspace_id",
      session.workspaceID,
    ).eq("creator_id", body.creatorID).eq("member_id", session.memberID)
      .maybeSingle();
  if (body.action === "start") {
    if (
      !body.input || body.inputRevision === undefined ||
      body.consentVersion !== 1
    ) return jsonResponse({ error: "input_and_consent_required" }, 400);
    const startInput = body.input;
    if (!isPhaseEInput(startInput) && startInput.operation !== "pickIdea") {
      if (startInput.operation === "todayIdea" && !startInput.angle?.trim()) {
        return jsonResponse({ error: "angle_required" }, 400);
      }
      if (
        startInput.operation !== "requirements" && startInput.brief &&
        !startInput.brief.confirmed
      ) return jsonResponse({ error: "brief_confirmation_required" }, 400);
      if (
        ["storyboard", "reviseShot", "reviseStoryboard"].includes(
          startInput.operation,
        ) && !startInput.script
      ) return jsonResponse({ error: "script_required" }, 400);
      if (startInput.operation === "reviseScript" && !startInput.script) {
        return jsonResponse({ error: "script_required" }, 400);
      }
      if (startInput.operation === "script" && !startInput.idea) {
        return jsonResponse({ error: "idea_required" }, 400);
      }
      if (
        startInput.operation === "requirements" &&
        !startInput.brief?.original.trim()
      ) return jsonResponse({ error: "brief_source_required" }, 400);
      if (
        startInput.operation === "reviseShot" && (
          startInput.storyboard?.sourceScriptID !== startInput.script?.id ||
          startInput.storyboard?.requirementsRevision !==
            (startInput.brief?.revision ?? 0)
        )
      ) return jsonResponse({ error: "stale_shot_list" }, 409);
      if (
        startInput.operation === "reviseShot" &&
        (!startInput.targetShotID ||
          !startInput.storyboard?.shots.some((x) =>
            x.id.toLowerCase() === startInput.targetShotID?.toLowerCase()
          ))
      ) return jsonResponse({ error: "invalid_target" }, 400);
    }
    const result = await admin.rpc("mira_enqueue", {
      p_id: body.id,
      p_workspace: session.workspaceID,
      p_creator: body.creatorID,
      p_member: session.memberID,
      p_revision: body.inputRevision,
      p_input: body.input,
    });
    if (result.error) {
      const reason = result.error.message;
      if (reason === "operation_daily_cap_reached") {
        return jsonResponse({ error: reason }, 429);
      }
      if (reason === "daily_note_scope_conflict") {
        return jsonResponse({ error: reason }, 409);
      }
      return jsonResponse({
        error: result.error.message?.includes("rate_limited") ||
            result.error.message?.includes("active_jobs")
          ? "rate_limited"
          : "job_conflict",
      }, 409);
    }
    if (body.input.operation === "dailyNote") jobID = result.data.id;
  }
  const result = body.action === "cancel"
    ? await admin.rpc("mira_cancel", {
      p_id: body.id,
      p_workspace: session.workspaceID,
      p_creator: body.creatorID,
      p_member: session.memberID,
    })
    : await scope();
  if (result.error && body.action === "cancel") {
    return jsonResponse({ error: "cancel_failed" }, 503);
  }
  if (result.error) return jsonResponse({ error: "job_lookup_failed" }, 503);
  if (!result.data?.id) return jsonResponse({ error: "not_found" }, 404);
  const defer = deps.defer ?? ((work: Promise<unknown>) => {
    if (typeof EdgeRuntime !== "undefined") EdgeRuntime.waitUntil(work);
    else return work;
  });
  if (
    body.action !== "cancel" &&
    ["queued", "running"].includes(result.data.status)
  ) {
    const operation = operationSchema.safeParse(
      result.data.input?.operation,
    );
    const work = runJob(
      admin,
      jobID,
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
    body.action === "status" && body.pictures === true &&
    job.state === "succeeded" &&
    result.data.picture_count > 0 && output && "storyboard" in output &&
    output.storyboard
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
  const expired = row.status === "running" &&
    typeof row.lease_until === "string" &&
    Date.parse(row.lease_until) <= Date.now();
  const operation = (row.input as { operation?: string } | null)?.operation;
  const maxAttempts = operation === "dailyNote" ? 1 : 3;
  const phase = (row.status === "queued" && Number(row.attempts) > 0) ||
      (expired && !row.provider_started && Number(row.attempts) < maxAttempts)
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
    step: (phase === "running" && !expired) || phase === "succeeded"
      ? row.step ?? undefined
      : undefined,
    output: row.status === "succeeded" ? row.output ?? undefined : undefined,
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
  const update = (changes: Record<string, unknown>) =>
    admin.from("mira_generation_jobs").update({
      ...changes,
      updated_at: new Date().toISOString(),
    }).eq("id", id).eq("lease_id", row.lease_id).eq("status", "running");
  let output: MiraOutput;
  let input: MiraInput;
  try {
    input = inputSchema.parse(row.input);
    const signal = providerDeadline(input.operation, row.lease_until);
    const started = await update({ provider_started: true })
      .gt("lease_until", new Date().toISOString()).select("id").maybeSingle();
    if (started.error) {
      console.error(`mira_dispatch_save_failed ${id}`);
      return;
    }
    if (!started.data) return;
    signal.throwIfAborted();
    const onStep = async (step: TodayStep) => {
      const result = await update({ step })
        .gt("lease_until", new Date().toISOString());
      if (result.error) console.error(`mira_step_persist_failed ${id}`);
    };
    output = await generator(input, env, signal, undefined, onStep);
  } catch (error) {
    const transient = error instanceof Error &&
      (error.message === "transient_provider_error" ||
        error.name === "TimeoutError");
    const retry = transient && row.input.operation !== "dailyNote" &&
      row.attempts < 3;
    const reason = failureReason(error);
    console.error(`mira_job_failed ${id} ${reason}`);
    await update({
      status: retry ? "queued" : "failed",
      ...(retry ? { provider_started: false } : {}),
      error: transient
        ? row.input.operation === "dailyNote"
          ? "Daily note interrupted. Try again tomorrow."
          : "Generation interrupted. Retrying is bounded; a prior provider request may have completed."
        : `Generation failed validation or provider configuration. Your saved work is unchanged. (${reason})`,
      next_attempt_at: new Date(Date.now() + row.attempts * 5000).toISOString(),
    });
    return;
  }
  const count =
    (input.operation === "todayIdea" || input.operation === "pickIdea") &&
      "storyboard" in output && output.storyboard
      ? pictureCount(env)
      : null;
  for (let attempt = 0; attempt < 3; attempt++) {
    const saved = await update({ output, picture_count: count }).is(
      "output",
      null,
    )
      .select("id").maybeSingle();
    if (saved.error) {
      console.error(`mira_result_save_failed ${id}`);
      continue;
    }
    if (saved.data) {
      const finished = await update({ status: "succeeded", error: null });
      if (finished.error) console.error(`mira_result_finish_failed ${id}`);
    }
    return;
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
