import { createClient } from "jsr:@supabase/supabase-js@2";

export type DayJobStatus =
  | "queued"
  | "retrying"
  | "generating"
  | "generated"
  | "failed"
  | "cancelled";

export type DayJob = {
  id: string;
  generation_run_id: string;
  workspace_id: string;
  creator_id: string;
  weekly_plan_id: string;
  scheduled_date: string;
  day_index: number;
  status: DayJobStatus;
  attempt_count: number | null;
  daily_card_id: string | null;
  error_code: string | null;
  created_at?: string;
  updated_at?: string;
};

type JsonObject = Record<string, unknown>;

type WorkerOptions = {
  concurrency: number;
  dryRun: boolean;
  once: boolean;
  runID?: string;
  stub: boolean;
};

export type ProcessResult =
  | { status: "generated"; dailyCardID: string | null }
  | { status: "failed"; errorCode: string };

export type DayJobStore = {
  peekJob: (filter?: DayJobFilter) => Promise<DayJob | null>;
  claimJob: (
    candidate: DayJob,
    fields: {
      attemptCount: number;
      now: string;
    },
  ) => Promise<DayJob | null>;
  markGenerated: (
    job: DayJob,
    dailyCardID: string | null,
    now: string,
  ) => Promise<void>;
  markFailed: (job: DayJob, errorCode: string, now: string) => Promise<void>;
};

export type DayJobFilter = {
  runID?: string;
};

export type ClaimOptions = {
  filter?: DayJobFilter;
  maxClaimAttempts?: number;
  wait?: (ms: number) => Promise<void>;
  now?: () => string;
  onLostRace?: (candidate: DayJob, attempt: number) => void;
};

export type WorkerPoolOptions = {
  concurrency: number;
  dryRun: boolean;
  filter?: DayJobFilter;
  onClaimLostRace?: (candidate: DayJob, attempt: number) => void;
};

export type WorkerPoolResult = {
  claimed: number;
  generated: number;
  failed: number;
};

export type ProcessJobContext = {
  stub: boolean;
  serviceRoleKey: string;
  dayGenerationEndpointURL: string;
  workerDeviceToken?: string;
  mock: boolean;
};

if (import.meta.main) {
  await main(Deno.args);
}

export async function main(args: string[]): Promise<void> {
  const options = parseOptions(args);
  const supabaseURL = requiredEnv("SUPABASE_URL", "MCO_SUPABASE_URL")
    .replace(/\/+$/, "");
  const serviceRoleKey = requiredEnv(
    "SUPABASE_SERVICE_ROLE_KEY",
    "MCO_SUPABASE_SERVICE_ROLE_KEY",
  );
  const dayGenerationEndpointURL = (
    env("MCO_GENERATE_WEEK_FUNCTION_URL") ??
      `${supabaseURL}/functions/v1/generate-week`
  ).replace(/\/+$/, "");

  if (!options.once) {
    fail(
      "Only once mode is supported. Omit --loop and run this worker repeatedly.",
    );
  }

  const supabase = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const store = createSupabaseDayJobStore(supabase);

  const processContext: ProcessJobContext = {
    stub: options.stub,
    serviceRoleKey,
    dayGenerationEndpointURL,
    workerDeviceToken: env("MCO_WORKER_DEVICE_TOKEN"),
    mock: env("MCO_DAY_WORKER_MOCK") === "1",
  };

  const poolResult = await runWorkerPool(store, processContext, {
    concurrency: options.concurrency,
    dryRun: options.dryRun,
    filter: { runID: options.runID },
    onClaimLostRace: (candidate, attempt) => {
      info("day_job_claim_lost_race", {
        candidate_job_id: candidate.id,
        attempt,
      });
    },
  });
  info("worker_pool_complete", poolResult);
}

export function createSupabaseDayJobStore(supabase: {
  from: (table: string) => any;
}): DayJobStore {
  return {
    async peekJob(filter: DayJobFilter = {}): Promise<DayJob | null> {
      let query = supabase
        .from("weekly_generation_day_jobs")
        .select(dayJobSelect())
        .in("status", ["queued", "retrying"]);
      if (filter.runID) {
        query = query.eq("generation_run_id", filter.runID);
      }
      const { data, error } = await query
        .order("created_at", { ascending: true })
        .limit(1)
        .maybeSingle();

      if (error) {
        fail(`day_job_peek_failed: ${safeErrorMessage(error)}`);
      }
      return (data as DayJob | null) ?? null;
    },

    async claimJob(
      candidate: DayJob,
      fields: { attemptCount: number; now: string },
    ): Promise<DayJob | null> {
      const { data, error } = await supabase
        .from("weekly_generation_day_jobs")
        .update({
          status: "generating",
          attempt_count: fields.attemptCount,
          error_code: null,
          started_at: fields.now,
          updated_at: fields.now,
        })
        .eq("id", candidate.id)
        .in("status", ["queued", "retrying"])
        .select(dayJobSelect())
        .maybeSingle();

      if (error) {
        fail(`day_job_claim_failed: ${safeErrorMessage(error)}`);
      }
      return data ? data as unknown as DayJob : null;
    },

    async markGenerated(
      job: DayJob,
      dailyCardID: string | null,
      now: string,
    ): Promise<void> {
      const { error } = await supabase
        .from("weekly_generation_day_jobs")
        .update({
          status: "generated",
          daily_card_id: dailyCardID,
          error_code: null,
          completed_at: now,
          updated_at: now,
        })
        .eq("id", job.id)
        .eq("status", "generating");

      if (error) {
        fail(`day_job_mark_generated_failed: ${safeErrorMessage(error)}`);
      }
    },

    async markFailed(
      job: DayJob,
      errorCode: string,
      now: string,
    ): Promise<void> {
      const { error } = await supabase
        .from("weekly_generation_day_jobs")
        .update({
          status: "failed",
          error_code: errorCode,
          completed_at: now,
          updated_at: now,
        })
        .eq("id", job.id)
        .eq("status", "generating");

      if (error) {
        fail(`day_job_mark_failed_failed: ${safeErrorMessage(error)}`);
      }
    },
  };
}

export async function claimOneJobFromStore(
  store: DayJobStore,
  options: ClaimOptions = {},
): Promise<DayJob | null> {
  const maxClaimAttempts = options.maxClaimAttempts ?? 10;
  const wait = options.wait ?? delay;
  const now = options.now ?? (() => new Date().toISOString());
  for (let attempt = 0; attempt < maxClaimAttempts; attempt += 1) {
    const candidate = await store.peekJob(options.filter);
    if (!candidate) {
      return null;
    }

    const nextAttemptCount = (candidate.attempt_count ?? 0) + 1;
    const claimed = await store.claimJob(candidate, {
      attemptCount: nextAttemptCount,
      now: now(),
    });
    if (claimed) {
      return claimed;
    }

    options.onLostRace?.(candidate, attempt + 1);
    await wait(100 + attempt * 50);
  }
  return null;
}

export async function runWorkerPool(
  store: DayJobStore,
  context: ProcessJobContext,
  options: WorkerPoolOptions,
): Promise<WorkerPoolResult> {
  const concurrency = normalizeConcurrency(options.concurrency);
  const totals: WorkerPoolResult = { claimed: 0, generated: 0, failed: 0 };

  if (options.dryRun) {
    const job = await store.peekJob(options.filter);
    if (!job) {
      info("no_job", {});
      return totals;
    }
    info("dry_run_job", {
      job_id: job.id,
      generation_run_id: job.generation_run_id,
      weekly_plan_id: job.weekly_plan_id,
      scheduled_date: job.scheduled_date,
      day_index: job.day_index,
      would_call: context.stub ? "stub" : context.dayGenerationEndpointURL,
    });
    return totals;
  }

  async function runLane(laneIndex: number): Promise<void> {
    while (true) {
      const job = await claimOneJobFromStore(store, {
        filter: options.filter,
        onLostRace: options.onClaimLostRace,
      });
      if (!job) {
        if (laneIndex === 0) {
          info("no_job", {});
        }
        return;
      }

      totals.claimed += 1;
      info("job_claimed", {
        job_id: job.id,
        generation_run_id: job.generation_run_id,
        scheduled_date: job.scheduled_date,
        attempt_count: job.attempt_count,
      });

      const result = await processJob(job, context);
      await recordProcessResult(store, job, result);
      if (result.status === "generated") {
        totals.generated += 1;
        info("job_generated", {
          job_id: job.id,
          daily_card_id: result.dailyCardID,
        });
      } else {
        totals.failed += 1;
        info("job_failed", {
          job_id: job.id,
          error_code: result.errorCode,
        });
      }
    }
  }

  await Promise.all(
    Array.from({ length: concurrency }, (_, index) => runLane(index)),
  );
  return totals;
}

export async function processJob(
  job: DayJob,
  context: ProcessJobContext,
): Promise<ProcessResult> {
  if (context.stub) {
    return {
      status: "failed",
      errorCode: "day_generation_endpoint_stubbed",
    };
  }

  const headers: Record<string, string> = {
    "Authorization": `Bearer ${context.serviceRoleKey}`,
    "apikey": context.serviceRoleKey,
    "Content-Type": "application/json",
  };
  if (context.workerDeviceToken) {
    headers["x-mco-device-token"] = context.workerDeviceToken;
  }

  let response: Response;
  try {
    response = await fetch(context.dayGenerationEndpointURL, {
      method: "POST",
      headers,
      body: JSON.stringify({
        action: "regenerate_day",
        creator_id: job.creator_id,
        weekly_plan_id: job.weekly_plan_id,
        scheduled_date: job.scheduled_date,
        preserve_manual_edits: true,
        response_mode: "sync",
        mock: context.mock,
      }),
    });
  } catch {
    return {
      status: "failed",
      errorCode: "day_generation_endpoint_unreachable",
    };
  }

  const body = await response.json().catch(() => null);
  if (!response.ok) {
    return {
      status: "failed",
      errorCode: stableEndpointError(body, response.status),
    };
  }

  if (
    !isRecord(body) || body.status !== "draft" || !isRecord(body.daily_card)
  ) {
    return {
      status: "failed",
      errorCode: "invalid_day_generation_response",
    };
  }

  return {
    status: "generated",
    dailyCardID: stringValue(body.daily_card.id) ?? null,
  };
}

export async function recordProcessResult(
  store: DayJobStore,
  job: DayJob,
  result: ProcessResult,
  now: () => string = () => new Date().toISOString(),
): Promise<void> {
  if (result.status === "generated") {
    await store.markGenerated(job, result.dailyCardID, now());
  } else {
    await store.markFailed(job, result.errorCode, now());
  }
}

function dayJobSelect(): string {
  return [
    "id",
    "generation_run_id",
    "workspace_id",
    "creator_id",
    "weekly_plan_id",
    "scheduled_date",
    "day_index",
    "status",
    "attempt_count",
    "daily_card_id",
    "error_code",
    "created_at",
    "updated_at",
  ].join(",");
}

function parseOptions(args: string[]): WorkerOptions {
  const options: WorkerOptions = {
    concurrency: parseConcurrency(env("MCO_DAY_WORKER_CONCURRENCY")),
    dryRun: env("MCO_DAY_WORKER_DRY_RUN") === "1",
    once: true,
    stub: env("MCO_DAY_WORKER_STUB") === "1",
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--dry-run") {
      options.dryRun = true;
    } else if (arg === "--once") {
      options.once = true;
    } else if (arg === "--stub") {
      options.stub = true;
    } else if (arg === "--loop") {
      options.once = false;
    } else if (arg.startsWith("--concurrency=")) {
      options.concurrency = parseConcurrency(
        arg.slice("--concurrency=".length),
      );
    } else if (arg === "--concurrency") {
      options.concurrency = parseConcurrency(
        requiredArgValue("--concurrency", args[++index] ?? ""),
      );
    } else if (arg.startsWith("--run-id=")) {
      options.runID = requiredArgValue(
        "--run-id",
        arg.slice("--run-id=".length),
      );
    } else if (arg === "--run-id") {
      options.runID = requiredArgValue("--run-id", args[++index] ?? "");
    } else if (arg === "--help" || arg === "-h") {
      printUsage();
      Deno.exit(0);
    } else {
      fail(`Unknown argument: ${arg}`);
    }
  }

  return options;
}

function parseConcurrency(value: string | undefined): number {
  if (!value) {
    return 4;
  }
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1) {
    fail(`Invalid concurrency: ${value}`);
  }
  return normalizeConcurrency(parsed);
}

function normalizeConcurrency(value: number): number {
  return Math.max(1, Math.floor(value));
}

function requiredArgValue(name: string, value: string): string {
  const trimmed = value.trim();
  if (!trimmed) {
    fail(`${name} requires a non-empty value`);
  }
  return trimmed;
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function printUsage(): void {
  console.log(
    [
      "Usage: deno run --allow-env --allow-net scripts/workers/generate-day-worker.ts [--once] [--dry-run] [--stub]",
      "       deno run --allow-env --allow-net scripts/workers/generate-day-worker.ts [--concurrency=4] [--run-id=<generation_run_id>]",
      "",
      "Required env:",
      "  SUPABASE_URL or MCO_SUPABASE_URL",
      "  SUPABASE_SERVICE_ROLE_KEY or MCO_SUPABASE_SERVICE_ROLE_KEY",
      "",
      "Generation endpoint env:",
      "  MCO_GENERATE_WEEK_FUNCTION_URL defaults to <supabase-url>/functions/v1/generate-week",
      "  MCO_WORKER_DEVICE_TOKEN is required for the current generate-week regenerate_day endpoint",
      "",
      "Safety env:",
      "  MCO_DAY_WORKER_DRY_RUN=1 selects one job without mutation",
      "  MCO_DAY_WORKER_STUB=1 claims one job and marks it failed with day_generation_endpoint_stubbed",
      "  MCO_DAY_WORKER_MOCK=1 forwards mock:true to generate-week where allowed",
      "  MCO_DAY_WORKER_CONCURRENCY sets the bounded pool size; defaults to 4",
    ].join("\n"),
  );
}

function stableEndpointError(body: unknown, status: number): string {
  if (isRecord(body)) {
    const error = stringValue(body.error);
    if (error) {
      return error;
    }
  }
  return `day_generation_endpoint_http_${status}`;
}

function requiredEnv(...names: string[]): string {
  for (const name of names) {
    const value = env(name);
    if (value) {
      return value;
    }
  }
  fail(`Missing required env: ${names.join(" or ")}`);
}

function env(name: string): string | undefined {
  const value = Deno.env.get(name)?.trim();
  return value ? value : undefined;
}

function isRecord(value: unknown): value is JsonObject {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0
    ? value
    : undefined;
}

function safeErrorMessage(error: unknown): string {
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

function info(event: string, fields: JsonObject): void {
  console.log(JSON.stringify({ event, ...fields }));
}

function fail(message: string): never {
  console.error(JSON.stringify({ event: "worker_failed", error: message }));
  Deno.exit(1);
}
