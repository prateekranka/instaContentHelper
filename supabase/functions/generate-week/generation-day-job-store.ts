import { jsonResponse, SupabaseAdminClient } from "../_shared/device-auth.ts";
import type {
  QueuedDayJobRecord,
  QueuedDayJobStatus,
} from "./generation-status.ts";

export function queuedDayJobSelect(): string {
  return [
    "id",
    "generation_run_id",
    "weekly_plan_id",
    "workspace_id",
    "creator_id",
    "scheduled_date",
    "day_index",
    "status",
    "attempt_count",
    "daily_card_id",
    "error_code",
    "error_message",
    "started_at",
    "completed_at",
    "heartbeat_at",
    "lease_token",
    "worker_boot_id",
    "staged_output",
  ].join(",");
}

async function dayJobRPC<T>(
  admin: SupabaseAdminClient,
  functionName: string,
  params: Record<string, unknown>,
): Promise<T | null> {
  const client = admin as unknown as {
    rpc: (
      fn: string,
      params: Record<string, unknown>,
    ) => Promise<{ data: T | null; error: unknown }>;
  };
  const { data, error } = await client.rpc(functionName, params);
  if (error) {
    console.warn("generate-week day-job RPC failed", {
      rpc: functionName,
      error: postgrestErrorMessage(error),
    });
    return null;
  }
  return data;
}

export async function claimQueuedDayJob(
  admin: SupabaseAdminClient,
  generationRunID: string,
  leaseToken: string,
  bootID: string,
  concurrency: number,
  staleThresholdMS: number,
): Promise<QueuedDayJobRecord | null> {
  const row = await dayJobRPC<QueuedDayJobRecord>(
    admin,
    "claim_queued_day_job",
    {
      p_generation_run_id: generationRunID,
      p_lease_token: leaseToken,
      p_worker_boot_id: bootID,
      p_max_live_jobs: concurrency,
      p_stale_threshold_ms: staleThresholdMS,
    },
  );
  // RPC returns the raw Postgres row; normalise it.
  const rawRow = Array.isArray(row) ? row[0] : row;
  if (!isRecord(rawRow)) return null;
  const job = normalizeQueuedDayJobRows([rawRow])[0];
  return job.id ? job : null;
}

export async function reclaimStaleDayJob(
  admin: SupabaseAdminClient,
  generationRunID: string,
  leaseToken: string,
  bootID: string,
  staleThresholdMS: number,
  concurrency: number,
  maxAttempts: number,
): Promise<QueuedDayJobRecord | null> {
  const row = await dayJobRPC<QueuedDayJobRecord>(
    admin,
    "reclaim_stale_day_job",
    {
      p_generation_run_id: generationRunID,
      p_lease_token: leaseToken,
      p_worker_boot_id: bootID,
      p_stale_threshold_ms: staleThresholdMS,
      p_max_attempts: maxAttempts,
      p_max_live_jobs: concurrency,
    },
  );
  const rawRow = Array.isArray(row) ? row[0] : row;
  if (!isRecord(rawRow)) return null;
  const job = normalizeQueuedDayJobRows([rawRow])[0];
  return job.id ? job : null;
}

export async function releaseOverCapacityDayJob(
  admin: SupabaseAdminClient,
  job: QueuedDayJobRecord,
  leaseToken: string,
): Promise<boolean> {
  const releasedAttempts = Math.max(0, (job.attempt_count ?? 1) - 1);
  const releasedStatus: QueuedDayJobStatus = releasedAttempts > 0
    ? "retrying"
    : "queued";
  const { data, error } = await admin
    .from("weekly_generation_day_jobs")
    .update({
      status: releasedStatus,
      attempt_count: releasedAttempts,
      lease_token: null,
      worker_boot_id: null,
      heartbeat_at: null,
      started_at: null,
      completed_at: null,
      staged_output: null,
    })
    .eq("id", job.id)
    .eq("lease_token", leaseToken)
    .eq("status", "generating")
    .select("id")
    .maybeSingle();

  if (error) {
    console.warn("generate-week day-job over-capacity release failed", {
      generation_id: job.generation_run_id,
      job_id: job.id,
      scheduled_date: job.scheduled_date,
      error: postgrestErrorMessage(error),
    });
  }
  return isRecord(data) && Boolean(data.id);
}

export async function heartbeatDayJob(
  admin: SupabaseAdminClient,
  jobID: string,
  leaseToken: string,
): Promise<boolean> {
  const { data, error } = await admin
    .from("weekly_generation_day_jobs")
    .update({ heartbeat_at: new Date().toISOString() })
    .eq("id", jobID)
    .eq("lease_token", leaseToken)
    .eq("status", "generating")
    .select("id")
    .maybeSingle();
  if (error) {
    console.warn("generate-week day-job heartbeat failed", {
      job_id: jobID,
      error: postgrestErrorMessage(error),
    });
  }
  return isRecord(data) && Boolean(data.id);
}

export async function completeDayJob(
  admin: SupabaseAdminClient,
  jobID: string,
  leaseToken: string,
  dailyCardID: string,
): Promise<boolean> {
  const { data } = await admin
    .from("weekly_generation_day_jobs")
    .update({
      status: "generated",
      daily_card_id: dailyCardID,
      completed_at: new Date().toISOString(),
    })
    .eq("id", jobID)
    .eq("lease_token", leaseToken)
    .eq("status", "ready_to_persist")
    .select("id")
    .maybeSingle();
  return isRecord(data) && Boolean(data.id);
}

export async function failDayJob(
  admin: SupabaseAdminClient,
  jobID: string,
  leaseToken: string,
  errorCode: string,
  errorMessage?: string,
): Promise<boolean> {
  const { data } = await admin
    .from("weekly_generation_day_jobs")
    .update({
      status: "failed",
      error_code: errorCode,
      error_message: errorMessage?.slice(0, 1000) ?? null,
      completed_at: new Date().toISOString(),
    })
    .eq("id", jobID)
    .eq("lease_token", leaseToken)
    .in("status", ["generating", "ready_to_persist"])
    .select("id")
    .maybeSingle();
  return isRecord(data) && Boolean(data.id);
}

export async function stageDayJobOutput(
  admin: SupabaseAdminClient,
  jobID: string,
  leaseToken: string,
  attempt: number,
  output: Record<string, unknown>,
): Promise<boolean> {
  const row = await dayJobRPC<QueuedDayJobRecord>(
    admin,
    "stage_day_job_output",
    {
      p_job_id: jobID,
      p_lease_token: leaseToken,
      p_attempt: attempt,
      p_output: output,
    },
  );
  const rawRow = Array.isArray(row) ? row[0] : row;
  return isRecord(rawRow) && Boolean(rawRow.id);
}

export async function readQueuedDayJobsForRun(
  admin: SupabaseAdminClient,
  generationID: string,
  workspaceID: string,
  creatorID: string,
): Promise<{ jobs: QueuedDayJobRecord[] } | { response: Response }> {
  const { data, error } = await admin
    .from("weekly_generation_day_jobs")
    .select(queuedDayJobSelect())
    .eq("generation_run_id", generationID)
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .order("day_index", { ascending: true });

  if (error) {
    return generationPersistFailure("read_generation_day_jobs", error);
  }

  return { jobs: normalizeQueuedDayJobRows(data) };
}

export type DayJobUpsertRow = {
  generation_run_id: string;
  weekly_plan_id: string;
  workspace_id: string;
  creator_id: string;
  scheduled_date: string;
  day_index: number;
  status: QueuedDayJobStatus | string;
  attempt_count: number;
  daily_card_id?: string | null;
  error_code?: string | null;
  started_at?: string | null;
  completed_at?: string | null;
  lease_token?: string | null;
  heartbeat_at?: string | null;
};

export async function upsertDayJobRows(
  admin: SupabaseAdminClient,
  rows: DayJobUpsertRow[],
): Promise<{ jobs: QueuedDayJobRecord[] } | { error: unknown }> {
  const { data, error } = await admin
    .from("weekly_generation_day_jobs")
    .upsert(rows, { onConflict: "generation_run_id,scheduled_date" })
    .select(queuedDayJobSelect())
    .order("day_index", { ascending: true });

  if (error) {
    return { error };
  }
  return { jobs: normalizeQueuedDayJobRows(data) };
}

export function normalizeQueuedDayJobRows(
  value: unknown,
): QueuedDayJobRecord[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.filter(isRecord).flatMap((row) => {
    const scheduledDate = stringValue(row.scheduled_date);
    const status = normalizeQueuedDayJobStatus(row.status);
    const dayIndex = numberValue(row.day_index);
    if (!scheduledDate || !status || dayIndex === undefined) {
      return [];
    }
    return [{
      id: stringValue(row.id) ?? "",
      generation_run_id: stringValue(row.generation_run_id) ?? "",
      weekly_plan_id: stringValue(row.weekly_plan_id) ?? "",
      workspace_id: stringValue(row.workspace_id) ?? "",
      creator_id: stringValue(row.creator_id) ?? "",
      scheduled_date: scheduledDate,
      day_index: dayIndex,
      status,
      attempt_count: numberValue(row.attempt_count) ?? 0,
      daily_card_id: stringValue(row.daily_card_id) ?? null,
      error_code: stringValue(row.error_code) ?? null,
      error_message: stringValue(row.error_message) ?? null,
      started_at: stringValue(row.started_at) ?? null,
      completed_at: stringValue(row.completed_at) ?? null,
      heartbeat_at: stringValue(row.heartbeat_at) ?? null,
      lease_token: stringValue(row.lease_token) ?? null,
      worker_boot_id: stringValue(row.worker_boot_id) ?? null,
      staged_output: isRecord(row.staged_output) ? row.staged_output : null,
    }];
  }).sort((left, right) => left.day_index - right.day_index);
}

export function normalizeQueuedDayJobStatus(
  value: unknown,
): QueuedDayJobStatus | undefined {
  return value === "queued" || value === "generating" ||
      value === "generated" || value === "failed" ||
      value === "retrying" || value === "cancelled" ||
      value === "ready_to_persist"
    ? value
    : undefined;
}

export function isQueuedDayJobStale(
  job: {
    heartbeat_at?: unknown;
    started_at?: unknown;
  },
  staleThresholdMS: number,
  now = Date.now(),
): boolean {
  const lastLiveness = stringValue(job.heartbeat_at) ??
    stringValue(job.started_at);
  if (!lastLiveness) {
    return false;
  }
  const lastLivenessMS = Date.parse(lastLiveness);
  return Number.isFinite(lastLivenessMS) &&
    now - lastLivenessMS > staleThresholdMS;
}

function generationPersistFailure(
  step: string,
  error?: unknown,
): { response: Response } {
  console.error(
    "generate-week persist failed",
    step,
    postgrestErrorMessage(error),
  );
  const detail = postgrestErrorMessage(error);
  return {
    response: jsonResponse(
      {
        error: "generation_persist_failed",
        step,
        detail: detail.slice(0, 500),
      },
      500,
    ),
  };
}

function postgrestErrorMessage(error: unknown): string {
  if (isRecord(error)) {
    return stringValue(error.message) ??
      stringValue(error.details) ??
      stringValue(error.hint) ??
      stringValue(error.code) ??
      "unknown_error";
  }
  if (error instanceof Error) {
    return error.message;
  }
  return typeof error === "string" ? error : "unknown_error";
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0
    ? value
    : undefined;
}

function numberValue(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
