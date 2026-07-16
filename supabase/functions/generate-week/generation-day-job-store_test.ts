import {
  cancelActiveQueuedDayJobs,
  claimQueuedDayJob,
  completeDayJob,
  failDayJob,
  heartbeatDayJob,
  isQueuedDayJobStale,
  lookupQueuedDayJobsExist,
  markFailedDayJobRetrying,
  markGenerationRunCancelled,
  normalizeQueuedDayJobRows,
  normalizeQueuedDayJobStatus,
  queuedDayJobSelect,
  readQueuedActionGenerationRun,
  readQueuedDayJobsForRun,
  reclaimStaleDayJob,
  releaseOverCapacityDayJob,
  stageDayJobOutput,
  upsertDayJobRows,
} from "./generation-day-job-store.ts";
import {
  markGenerationRunCancelled as markGenerationRunCancelledFromRunStore,
  readQueuedActionGenerationRun as readQueuedActionGenerationRunFromRunStore,
} from "./generation-run-store.ts";
import type { QueuedDayJobRecord } from "./generation-status.ts";

type FakeJob = Record<string, unknown>;

type CapturedOp = {
  table: string;
  operation: "select" | "update" | "upsert";
  values: unknown;
  filters: Record<string, unknown>;
  selectColumns?: string;
  onConflict?: string;
  order?: { column: string; ascending?: boolean };
  limit?: number;
};

type FakeStoreState = {
  dayJobs: FakeJob[];
  generationRuns: FakeJob[];
  rpcCalls: Array<{ fn: string; params: Record<string, unknown> }>;
  ops: CapturedOp[];
  lookupError?: { message: string };
  writeError?: { message: string };
};

function baseJob(overrides: Partial<FakeJob> = {}): FakeJob {
  return {
    id: "11111111-1111-4111-8111-111111111111",
    generation_run_id: "22222222-2222-4222-8222-222222222222",
    weekly_plan_id: "33333333-3333-4333-8333-333333333333",
    workspace_id: "44444444-4444-4444-8444-444444444444",
    creator_id: "55555555-5555-4555-8555-555555555555",
    scheduled_date: "2026-06-08",
    day_index: 0,
    status: "queued",
    attempt_count: 0,
    daily_card_id: null,
    error_code: null,
    error_message: null,
    started_at: null,
    completed_at: null,
    heartbeat_at: null,
    lease_token: null,
    worker_boot_id: null,
    staged_output: null,
    ...overrides,
  };
}

function fakeAdmin(state: FakeStoreState): {
  from: (table: string) => FakeQuery;
  rpc: (
    fn: string,
    params?: Record<string, unknown>,
  ) => Promise<{ data: unknown; error: unknown }>;
} {
  return {
    from(table: string) {
      return new FakeQuery(table, state);
    },
    async rpc(fn: string, params: Record<string, unknown> = {}) {
      state.rpcCalls.push({ fn, params });
      if (fn === "claim_queued_day_job") {
        const job = state.dayJobs.find((candidate) =>
          candidate.generation_run_id === params.p_generation_run_id &&
          (candidate.status === "queued" || candidate.status === "retrying")
        );
        if (!job) return { data: null, error: null };
        job.status = "generating";
        job.lease_token = params.p_lease_token;
        job.worker_boot_id = params.p_worker_boot_id;
        job.attempt_count = ((job.attempt_count as number) ?? 0) + 1;
        job.heartbeat_at = "2026-06-08T12:00:00.000Z";
        job.started_at = "2026-06-08T12:00:00.000Z";
        return { data: { ...job }, error: null };
      }
      if (fn === "reclaim_stale_day_job") {
        const job = state.dayJobs.find((candidate) =>
          candidate.generation_run_id === params.p_generation_run_id &&
          candidate.status === "generating"
        );
        if (!job) return { data: null, error: null };
        job.lease_token = params.p_lease_token;
        job.worker_boot_id = params.p_worker_boot_id;
        job.attempt_count = ((job.attempt_count as number) ?? 0) + 1;
        return { data: { ...job }, error: null };
      }
      if (fn === "stage_day_job_output") {
        const job = state.dayJobs.find((candidate) =>
          candidate.id === params.p_job_id &&
          candidate.lease_token === params.p_lease_token &&
          candidate.attempt_count === params.p_attempt &&
          candidate.status === "generating"
        );
        if (!job) return { data: null, error: null };
        job.status = "ready_to_persist";
        job.staged_output = params.p_output;
        return { data: { ...job }, error: null };
      }
      return { data: null, error: null };
    },
  };
}

class FakeQuery {
  private operation: "select" | "update" | "upsert" = "select";
  private filters: Record<string, unknown> = {};
  private values: unknown = null;
  private selectColumns?: string;
  private onConflict?: string;
  private orderSpec?: { column: string; ascending?: boolean };
  private limitCount?: number;

  constructor(
    private readonly table: string,
    private readonly state: FakeStoreState,
  ) {}

  select(columns?: string): FakeQuery {
    this.selectColumns = columns;
    return this;
  }

  update(values: Record<string, unknown>): FakeQuery {
    this.operation = "update";
    this.values = values;
    return this;
  }

  upsert(
    values: unknown,
    options?: { onConflict?: string },
  ): FakeQuery {
    this.operation = "upsert";
    this.values = values;
    this.onConflict = options?.onConflict;
    return this;
  }

  eq(column: string, value: unknown): FakeQuery {
    this.filters[column] = value;
    return this;
  }

  in(column: string, value: unknown): FakeQuery {
    this.filters[column] = value;
    return this;
  }

  order(column: string, options?: { ascending?: boolean }): FakeQuery {
    this.orderSpec = { column, ascending: options?.ascending };
    return this;
  }

  limit(count: number): FakeQuery {
    this.limitCount = count;
    return this;
  }

  maybeSingle(): Promise<{ data: unknown; error: unknown }> {
    const result = this.resolve();
    return Promise.resolve({
      data: Array.isArray(result.data) ? result.data[0] ?? null : result.data,
      error: result.error,
    });
  }

  then<TResult1 = { data: unknown; error: unknown }, TResult2 = never>(
    onfulfilled?:
      | ((
        value: { data: unknown; error: unknown },
      ) => TResult1 | PromiseLike<TResult1>)
      | null,
    onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
  ): Promise<TResult1 | TResult2> {
    return Promise.resolve(this.resolve()).then(onfulfilled, onrejected);
  }

  private capture(): void {
    this.state.ops.push({
      table: this.table,
      operation: this.operation,
      values: this.values,
      filters: { ...this.filters },
      selectColumns: this.selectColumns,
      onConflict: this.onConflict,
      order: this.orderSpec,
      limit: this.limitCount,
    });
  }

  private resolve(): { data: unknown; error: unknown } {
    this.capture();

    if (this.table === "weekly_generation_runs") {
      if (this.operation === "select") {
        if (this.state.lookupError) {
          return { data: null, error: this.state.lookupError };
        }
        const row = this.state.generationRuns.find((run) =>
          (!this.filters.id || run.id === this.filters.id) &&
          (!this.filters.workspace_id ||
            run.workspace_id === this.filters.workspace_id)
        );
        return { data: row ?? null, error: null };
      }
      if (this.operation === "update") {
        if (this.state.writeError) {
          return { data: null, error: this.state.writeError };
        }
        const rows = this.state.generationRuns.filter((run) =>
          !this.filters.id || run.id === this.filters.id
        );
        rows.forEach((row) =>
          Object.assign(row, this.values as Record<string, unknown>)
        );
        return { data: rows[0] ?? null, error: null };
      }
      return { data: null, error: null };
    }

    if (this.table !== "weekly_generation_day_jobs") {
      return { data: null, error: null };
    }

    if (this.operation === "select") {
      if (this.state.lookupError) {
        return { data: null, error: this.state.lookupError };
      }
      let rows = this.state.dayJobs.filter((job) =>
        (!this.filters.generation_run_id ||
          job.generation_run_id === this.filters.generation_run_id) &&
        (!this.filters.workspace_id ||
          job.workspace_id === this.filters.workspace_id) &&
        (!this.filters.creator_id ||
          job.creator_id === this.filters.creator_id) &&
        (!this.filters.id || job.id === this.filters.id) &&
        (!this.filters.scheduled_date ||
          job.scheduled_date === this.filters.scheduled_date) &&
        (!this.filters.status || job.status === this.filters.status ||
          (Array.isArray(this.filters.status) &&
            this.filters.status.includes(job.status)))
      );
      if (this.orderSpec?.column === "day_index") {
        rows = [...rows].sort((left, right) =>
          Number(left.day_index) - Number(right.day_index)
        );
      }
      if (typeof this.limitCount === "number") {
        rows = rows.slice(0, this.limitCount);
      }
      return { data: rows, error: null };
    }

    if (this.operation === "upsert") {
      if (this.state.writeError) {
        return { data: null, error: this.state.writeError };
      }
      const values = Array.isArray(this.values)
        ? this.values as FakeJob[]
        : [this.values as FakeJob];
      values.forEach((value, index) => {
        const existing = this.state.dayJobs.find((job) =>
          job.generation_run_id === value.generation_run_id &&
          job.scheduled_date === value.scheduled_date
        );
        const row = {
          id: `99999999-9999-4999-8999-99999999999${index}`,
          ...value,
        };
        if (existing) {
          Object.assign(existing, row);
        } else {
          this.state.dayJobs.push(row);
        }
      });
      let rows = [...this.state.dayJobs];
      if (this.orderSpec?.column === "day_index") {
        rows = rows.sort((left, right) =>
          Number(left.day_index) - Number(right.day_index)
        );
      }
      return { data: rows, error: null };
    }

    const rows = this.state.dayJobs.filter((job) =>
      (!this.filters.id || job.id === this.filters.id) &&
      (!this.filters.lease_token ||
        job.lease_token === this.filters.lease_token) &&
      (!this.filters.generation_run_id ||
        job.generation_run_id === this.filters.generation_run_id) &&
      (!this.filters.workspace_id ||
        job.workspace_id === this.filters.workspace_id) &&
      (!this.filters.creator_id ||
        job.creator_id === this.filters.creator_id) &&
      (!this.filters.scheduled_date ||
        job.scheduled_date === this.filters.scheduled_date) &&
      (!this.filters.status || job.status === this.filters.status ||
        (Array.isArray(this.filters.status) &&
          this.filters.status.includes(job.status)))
    );
    if (this.state.writeError) {
      return { data: null, error: this.state.writeError };
    }
    if (rows.length === 0 || !this.values) {
      // PostgREST maybeSingle/update with zero matches returns null data, no error.
      return { data: null, error: null };
    }
    rows.forEach((row) =>
      Object.assign(row, this.values as Record<string, unknown>)
    );
    return {
      data: this.selectColumns === queuedDayJobSelect()
        ? rows[0]
        : { id: rows[0].id },
      error: null,
    };
  }
}

Deno.test("queuedDayJobSelect preserves the exact column contract", () => {
  assertEquals(
    queuedDayJobSelect(),
    [
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
    ].join(","),
  );
});

Deno.test("normalizeQueuedDayJobRows sorts, fills defaults, and drops malformed rows", () => {
  const rows = normalizeQueuedDayJobRows([
    {
      id: "b",
      generation_run_id: "run",
      weekly_plan_id: "plan",
      workspace_id: "ws",
      creator_id: "creator",
      scheduled_date: "2026-06-09",
      day_index: 1,
      status: "generated",
      attempt_count: 2,
      staged_output: { ok: true },
    },
    {
      id: "a",
      generation_run_id: "run",
      weekly_plan_id: "plan",
      workspace_id: "ws",
      creator_id: "creator",
      scheduled_date: "2026-06-08",
      day_index: 0,
      status: "queued",
    },
    {
      scheduled_date: "2026-06-10",
      day_index: 2,
      status: "not-a-status",
    },
    {
      scheduled_date: "   ",
      day_index: 3,
      status: "queued",
    },
    {
      scheduled_date: "2026-06-11",
      status: "queued",
    },
    null,
    "skip",
  ]);

  assertEquals(rows.length, 2);
  assertEquals(rows[0].day_index, 0);
  assertEquals(rows[0].attempt_count, 0);
  assertEquals(rows[0].daily_card_id, null);
  assertEquals(rows[0].lease_token, null);
  assertEquals(rows[1].day_index, 1);
  assertEquals(rows[1].staged_output?.ok, true);
  assertEquals(normalizeQueuedDayJobRows(null).length, 0);
  assertEquals(normalizeQueuedDayJobRows({}).length, 0);
});

Deno.test("normalizeQueuedDayJobStatus accepts only known stored statuses", () => {
  const accepted = [
    "queued",
    "generating",
    "generated",
    "failed",
    "retrying",
    "cancelled",
    "ready_to_persist",
  ] as const;
  for (const status of accepted) {
    assertEquals(normalizeQueuedDayJobStatus(status), status);
  }
  assertEquals(normalizeQueuedDayJobStatus("running"), undefined);
  assertEquals(normalizeQueuedDayJobStatus(null), undefined);
});

Deno.test("isQueuedDayJobStale uses heartbeat then started_at against the threshold", () => {
  const now = Date.parse("2026-06-08T12:10:00.000Z");
  assertEquals(
    isQueuedDayJobStale(
      {
        heartbeat_at: "2026-06-08T12:08:00.000Z",
        started_at: "2026-06-08T11:00:00.000Z",
      },
      135_000,
      now,
    ),
    false,
  );
  assertEquals(
    isQueuedDayJobStale(
      {
        heartbeat_at: "2026-06-08T12:00:00.000Z",
        started_at: "2026-06-08T12:09:00.000Z",
      },
      135_000,
      now,
    ),
    true,
    "heartbeat takes precedence over a fresher started_at",
  );
  assertEquals(
    isQueuedDayJobStale(
      {
        started_at: "2026-06-08T12:00:00.000Z",
      },
      135_000,
      now,
    ),
    true,
  );
  assertEquals(isQueuedDayJobStale({}, 135_000, now), false);
  assertEquals(
    isQueuedDayJobStale({ heartbeat_at: "not-a-date" }, 135_000, now),
    false,
  );
});

Deno.test("claimQueuedDayJob and reclaimStaleDayJob preserve RPC names and payloads", async () => {
  const state: FakeStoreState = {
    dayJobs: [baseJob({ status: "queued" })],
    generationRuns: [],
    rpcCalls: [],
    ops: [],
  };
  const admin = fakeAdmin(state);

  const claimed = await claimQueuedDayJob(
    admin,
    "22222222-2222-4222-8222-222222222222",
    "lease-a",
    "boot-a",
    2,
    135_000,
  );
  assertEquals(claimed?.id, "11111111-1111-4111-8111-111111111111");
  assertEquals(claimed?.status, "generating");
  assertEquals(state.rpcCalls[0]?.fn, "claim_queued_day_job");
  assertEquals(
    state.rpcCalls[0]?.params.p_generation_run_id,
    "22222222-2222-4222-8222-222222222222",
  );
  assertEquals(state.rpcCalls[0]?.params.p_lease_token, "lease-a");
  assertEquals(state.rpcCalls[0]?.params.p_worker_boot_id, "boot-a");
  assertEquals(state.rpcCalls[0]?.params.p_max_live_jobs, 2);
  assertEquals(state.rpcCalls[0]?.params.p_stale_threshold_ms, 135_000);

  state.dayJobs[0].status = "generating";
  const reclaimed = await reclaimStaleDayJob(
    admin,
    "22222222-2222-4222-8222-222222222222",
    "lease-b",
    "boot-b",
    240_000,
    4,
    3,
  );
  assertEquals(reclaimed?.lease_token, "lease-b");
  assertEquals(state.rpcCalls[1]?.fn, "reclaim_stale_day_job");
  assertEquals(
    state.rpcCalls[1]?.params.p_generation_run_id,
    "22222222-2222-4222-8222-222222222222",
  );
  assertEquals(state.rpcCalls[1]?.params.p_lease_token, "lease-b");
  assertEquals(state.rpcCalls[1]?.params.p_worker_boot_id, "boot-b");
  assertEquals(state.rpcCalls[1]?.params.p_stale_threshold_ms, 240_000);
  assertEquals(state.rpcCalls[1]?.params.p_max_attempts, 3);
  assertEquals(state.rpcCalls[1]?.params.p_max_live_jobs, 4);
});

Deno.test("stageDayJobOutput preserves stage_day_job_output RPC payload fields", async () => {
  const state: FakeStoreState = {
    dayJobs: [baseJob({
      status: "generating",
      lease_token: "lease-a",
      attempt_count: 2,
    })],
    generationRuns: [],
    rpcCalls: [],
    ops: [],
  };
  const admin = fakeAdmin(state);
  const staged = await stageDayJobOutput(
    admin,
    "11111111-1111-4111-8111-111111111111",
    "lease-a",
    2,
    { source_summary: "staged" },
  );
  assertEquals(staged, true);
  assertEquals(state.rpcCalls[0]?.fn, "stage_day_job_output");
  assertEquals(
    state.rpcCalls[0]?.params.p_job_id,
    "11111111-1111-4111-8111-111111111111",
  );
  assertEquals(state.rpcCalls[0]?.params.p_lease_token, "lease-a");
  assertEquals(state.rpcCalls[0]?.params.p_attempt, 2);
  assertEquals(
    (state.rpcCalls[0]?.params.p_output as { source_summary?: string })
      .source_summary,
    "staged",
  );
  assertEquals(state.dayJobs[0].status, "ready_to_persist");
});

Deno.test("heartbeat, complete, fail, and capacity release enforce lease transitions", async () => {
  const generating = baseJob({
    status: "generating",
    lease_token: "lease-a",
    attempt_count: 1,
  });
  const ready = baseJob({
    id: "66666666-6666-4666-8666-666666666666",
    scheduled_date: "2026-06-09",
    day_index: 1,
    status: "ready_to_persist",
    lease_token: "lease-b",
    attempt_count: 1,
  });
  const state: FakeStoreState = {
    dayJobs: [generating, ready],
    generationRuns: [],
    rpcCalls: [],
    ops: [],
  };
  const admin = fakeAdmin(state);

  assertEquals(
    await heartbeatDayJob(
      admin,
      "11111111-1111-4111-8111-111111111111",
      "lease-a",
    ),
    true,
  );
  assertEquals(typeof generating.heartbeat_at, "string");

  assertEquals(
    await heartbeatDayJob(
      admin,
      "11111111-1111-4111-8111-111111111111",
      "wrong-lease",
    ),
    false,
  );

  assertEquals(
    await completeDayJob(
      admin,
      "66666666-6666-4666-8666-666666666666",
      "lease-b",
      "card-1",
    ),
    true,
  );
  assertEquals(ready.status, "generated");
  assertEquals(ready.daily_card_id, "card-1");
  assertEquals(typeof ready.completed_at, "string");

  generating.status = "generating";
  generating.lease_token = "lease-a";
  assertEquals(
    await failDayJob(
      admin,
      "11111111-1111-4111-8111-111111111111",
      "lease-a",
      "provider_failed",
      "x".repeat(1200),
    ),
    true,
  );
  assertEquals(generating.status, "failed");
  assertEquals(generating.error_code, "provider_failed");
  assertEquals((generating.error_message as string).length, 1000);

  const overCapacity = baseJob({
    id: "77777777-7777-4777-8777-777777777777",
    status: "generating",
    lease_token: "lease-c",
    attempt_count: 2,
  }) as unknown as QueuedDayJobRecord;
  state.dayJobs.push(overCapacity as unknown as FakeJob);
  assertEquals(
    await releaseOverCapacityDayJob(admin, overCapacity, "lease-c"),
    true,
  );
  assertEquals(overCapacity.status, "retrying");
  assertEquals(overCapacity.attempt_count, 1);
  assertEquals(overCapacity.lease_token, null);
  assertEquals(overCapacity.heartbeat_at, null);
});

Deno.test("readQueuedDayJobsForRun normalizes rows and surfaces persist failures", async () => {
  const state: FakeStoreState = {
    dayJobs: [
      baseJob({ day_index: 1, scheduled_date: "2026-06-09", status: "queued" }),
      baseJob({
        id: "88888888-8888-4888-8888-888888888888",
        day_index: 0,
        scheduled_date: "2026-06-08",
        status: "generated",
        daily_card_id: "card-0",
      }),
    ],
    generationRuns: [],
    rpcCalls: [],
    ops: [],
  };
  const admin = fakeAdmin(state);
  const result = await readQueuedDayJobsForRun(
    admin,
    "22222222-2222-4222-8222-222222222222",
    "44444444-4444-4444-8444-444444444444",
    "55555555-5555-4555-8555-555555555555",
  );
  assert("jobs" in result);
  assertEquals(result.jobs.length, 2);
  assertEquals(result.jobs[0].day_index, 0);
  assertEquals(result.jobs[1].day_index, 1);

  state.lookupError = { message: "select failed" };
  const failed = await readQueuedDayJobsForRun(
    admin,
    "22222222-2222-4222-8222-222222222222",
    "44444444-4444-4444-8444-444444444444",
    "55555555-5555-4555-8555-555555555555",
  );
  assert("response" in failed);
  assertEquals(failed.response.status, 500);
  const body = await failed.response.json();
  assertEquals(body.error, "generation_persist_failed");
  assertEquals(body.step, "read_generation_day_jobs");
});

Deno.test("claimQueuedDayJob returns null for empty-id and invalid RPC rows", async () => {
  const emptyIDAdmin = {
    from() {
      throw new Error("from should not be called");
    },
    async rpc() {
      return {
        data: {
          id: "   ",
          generation_run_id: "run",
          weekly_plan_id: "plan",
          workspace_id: "ws",
          creator_id: "creator",
          scheduled_date: "2026-06-08",
          day_index: 0,
          status: "queued",
        },
        error: null,
      };
    },
  };
  assertEquals(
    await claimQueuedDayJob(emptyIDAdmin, "run", "lease", "boot", 1, 135_000),
    null,
  );

  const invalidAdmin = {
    from() {
      throw new Error("from should not be called");
    },
    async rpc() {
      return {
        data: {
          scheduled_date: "2026-06-08",
          day_index: 0,
          status: "not-valid",
        },
        error: null,
      };
    },
  };
  let threw = false;
  try {
    await claimQueuedDayJob(invalidAdmin, "run", "lease", "boot", 1, 135_000);
  } catch {
    threw = true;
  }
  assertEquals(
    threw,
    true,
    "invalid status rows still short-circuit via missing normalized job",
  );
});

Deno.test("upsertDayJobRows uses exact table, conflict target, select, and order", async () => {
  const state: FakeStoreState = {
    dayJobs: [],
    generationRuns: [],
    rpcCalls: [],
    ops: [],
  };
  const admin = fakeAdmin(state);
  const rows = [
    {
      generation_run_id: "22222222-2222-4222-8222-222222222222",
      weekly_plan_id: "33333333-3333-4333-8333-333333333333",
      workspace_id: "44444444-4444-4444-8444-444444444444",
      creator_id: "55555555-5555-4555-8555-555555555555",
      scheduled_date: "2026-06-09",
      day_index: 1,
      status: "queued",
      attempt_count: 0,
    },
    {
      generation_run_id: "22222222-2222-4222-8222-222222222222",
      weekly_plan_id: "33333333-3333-4333-8333-333333333333",
      workspace_id: "44444444-4444-4444-8444-444444444444",
      creator_id: "55555555-5555-4555-8555-555555555555",
      scheduled_date: "2026-06-08",
      day_index: 0,
      status: "queued",
      attempt_count: 0,
    },
  ];

  const result = await upsertDayJobRows(admin, rows);
  assert("jobs" in result);
  assertEquals(result.jobs.length, 2);
  assertEquals(result.jobs[0].day_index, 0);
  assertEquals(result.jobs[1].day_index, 1);

  const op = state.ops[0];
  assertEquals(op.table, "weekly_generation_day_jobs");
  assertEquals(op.operation, "upsert");
  assertEquals(op.onConflict, "generation_run_id,scheduled_date");
  assertEquals(op.selectColumns, queuedDayJobSelect());
  assertEquals(op.order?.column, "day_index");
  assertEquals(op.order?.ascending, true);

  state.writeError = { message: "upsert failed" };
  const failed = await upsertDayJobRows(admin, rows);
  assert("error" in failed);
  assertEquals((failed.error as { message: string }).message, "upsert failed");
});

Deno.test("lookupQueuedDayJobsExist uses id select, auth filters, and limit 1", async () => {
  const state: FakeStoreState = {
    dayJobs: [baseJob()],
    generationRuns: [],
    rpcCalls: [],
    ops: [],
  };
  const admin = fakeAdmin(state);
  const found = await lookupQueuedDayJobsExist(
    admin,
    "22222222-2222-4222-8222-222222222222",
    "44444444-4444-4444-8444-444444444444",
    "55555555-5555-4555-8555-555555555555",
  );
  assert("exists" in found);
  assertEquals(found.exists, true);

  const op = state.ops[0];
  assertEquals(op.table, "weekly_generation_day_jobs");
  assertEquals(op.operation, "select");
  assertEquals(op.selectColumns, "id");
  assertEquals(
    op.filters.generation_run_id,
    "22222222-2222-4222-8222-222222222222",
  );
  assertEquals(op.filters.workspace_id, "44444444-4444-4444-8444-444444444444");
  assertEquals(op.filters.creator_id, "55555555-5555-4555-8555-555555555555");
  assertEquals(op.limit, 1);

  state.dayJobs = [];
  const missing = await lookupQueuedDayJobsExist(
    admin,
    "22222222-2222-4222-8222-222222222222",
    "44444444-4444-4444-8444-444444444444",
    "55555555-5555-4555-8555-555555555555",
  );
  assert("exists" in missing);
  assertEquals(missing.exists, false);
});

Deno.test("markFailedDayJobRetrying updates failed rows with exact payload and filters", async () => {
  const failedJob = baseJob({
    status: "failed",
    error_code: "provider_failed",
    error_message: "boom",
    completed_at: "2026-06-08T12:00:00.000Z",
    heartbeat_at: "2026-06-08T12:00:00.000Z",
  });
  const state: FakeStoreState = {
    dayJobs: [failedJob],
    generationRuns: [],
    rpcCalls: [],
    ops: [],
  };
  const admin = fakeAdmin(state);

  const result = await markFailedDayJobRetrying(admin, {
    generationRunID: "22222222-2222-4222-8222-222222222222",
    workspaceID: "44444444-4444-4444-8444-444444444444",
    creatorID: "55555555-5555-4555-8555-555555555555",
    scheduledDate: "2026-06-08",
  });
  assert("job" in result);
  assertEquals(result.job?.status, "retrying");
  assertEquals(failedJob.status, "retrying");
  assertEquals(failedJob.error_code, null);
  assertEquals(failedJob.error_message, null);
  assertEquals(failedJob.completed_at, null);
  assertEquals(failedJob.heartbeat_at, null);

  const op = state.ops[0];
  assertEquals(op.table, "weekly_generation_day_jobs");
  assertEquals(op.operation, "update");
  assertEquals(op.selectColumns, queuedDayJobSelect());
  assertEquals((op.values as Record<string, unknown>).status, "retrying");
  assertEquals((op.values as Record<string, unknown>).error_code, null);
  assertEquals((op.values as Record<string, unknown>).error_message, null);
  assertEquals((op.values as Record<string, unknown>).completed_at, null);
  assertEquals((op.values as Record<string, unknown>).heartbeat_at, null);
  assertEquals(
    op.filters.generation_run_id,
    "22222222-2222-4222-8222-222222222222",
  );
  assertEquals(op.filters.workspace_id, "44444444-4444-4444-8444-444444444444");
  assertEquals(op.filters.creator_id, "55555555-5555-4555-8555-555555555555");
  assertEquals(op.filters.scheduled_date, "2026-06-08");
  assertEquals(op.filters.status, "failed");

  const notRetryable = await markFailedDayJobRetrying(admin, {
    generationRunID: "22222222-2222-4222-8222-222222222222",
    workspaceID: "44444444-4444-4444-8444-444444444444",
    creatorID: "55555555-5555-4555-8555-555555555555",
    scheduledDate: "2026-06-09",
  });
  assert("job" in notRetryable);
  assertEquals(notRetryable.job, null);
});

Deno.test("cancelActiveQueuedDayJobs cancels only active statuses with auth filters", async () => {
  const state: FakeStoreState = {
    dayJobs: [
      baseJob({ status: "queued" }),
      baseJob({
        id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        scheduled_date: "2026-06-09",
        day_index: 1,
        status: "generated",
      }),
      baseJob({
        id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        scheduled_date: "2026-06-10",
        day_index: 2,
        status: "ready_to_persist",
      }),
    ],
    generationRuns: [],
    rpcCalls: [],
    ops: [],
  };
  const admin = fakeAdmin(state);

  const result = await cancelActiveQueuedDayJobs(
    admin,
    "22222222-2222-4222-8222-222222222222",
    "44444444-4444-4444-8444-444444444444",
    "55555555-5555-4555-8555-555555555555",
  );
  assertEquals(result.error, null);
  assertEquals(state.dayJobs[0].status, "cancelled");
  assertEquals(typeof state.dayJobs[0].completed_at, "string");
  assertEquals(state.dayJobs[1].status, "generated");
  assertEquals(state.dayJobs[2].status, "cancelled");

  const op = state.ops[0];
  assertEquals(op.table, "weekly_generation_day_jobs");
  assertEquals(op.operation, "update");
  assertEquals((op.values as Record<string, unknown>).status, "cancelled");
  assertEquals(
    typeof (op.values as Record<string, unknown>).completed_at,
    "string",
  );
  assertEquals(
    op.filters.generation_run_id,
    "22222222-2222-4222-8222-222222222222",
  );
  assertEquals(op.filters.workspace_id, "44444444-4444-4444-8444-444444444444");
  assertEquals(op.filters.creator_id, "55555555-5555-4555-8555-555555555555");
  assertEquals(
    JSON.stringify(op.filters.status),
    JSON.stringify(["queued", "retrying", "generating", "ready_to_persist"]),
  );
});

Deno.test("generation-day-job-store re-exports run-store cancellation helpers", () => {
  assertEquals(
    markGenerationRunCancelled,
    markGenerationRunCancelledFromRunStore,
  );
  assertEquals(
    readQueuedActionGenerationRun,
    readQueuedActionGenerationRunFromRunStore,
  );
});

Deno.test("markGenerationRunCancelled writes failed/cancelled payload by id", async () => {
  const state: FakeStoreState = {
    dayJobs: [],
    generationRuns: [{
      id: "22222222-2222-4222-8222-222222222222",
      workspace_id: "44444444-4444-4444-8444-444444444444",
      creator_id: "55555555-5555-4555-8555-555555555555",
      status: "running",
      weekly_plan_id: "33333333-3333-4333-8333-333333333333",
      error_code: null,
    }],
    rpcCalls: [],
    ops: [],
  };
  const admin = fakeAdmin(state);
  const result = await markGenerationRunCancelled(
    admin,
    "22222222-2222-4222-8222-222222222222",
  );
  assertEquals(result.error, null);
  assertEquals(state.generationRuns[0].status, "failed");
  assertEquals(state.generationRuns[0].error_code, "generation_cancelled");
  assertEquals(typeof state.generationRuns[0].completed_at, "string");

  const op = state.ops[0];
  assertEquals(op.table, "weekly_generation_runs");
  assertEquals(op.operation, "update");
  assertEquals((op.values as Record<string, unknown>).status, "failed");
  assertEquals(
    (op.values as Record<string, unknown>).error_code,
    "generation_cancelled",
  );
  assertEquals(
    typeof (op.values as Record<string, unknown>).completed_at,
    "string",
  );
  assertEquals(op.filters.id, "22222222-2222-4222-8222-222222222222");
});

Deno.test("readQueuedActionGenerationRun selects auth-scoped run columns", async () => {
  const state: FakeStoreState = {
    dayJobs: [],
    generationRuns: [{
      id: "22222222-2222-4222-8222-222222222222",
      workspace_id: "44444444-4444-4444-8444-444444444444",
      creator_id: "55555555-5555-4555-8555-555555555555",
      status: "running",
      weekly_plan_id: "33333333-3333-4333-8333-333333333333",
      error_code: null,
    }],
    rpcCalls: [],
    ops: [],
  };
  const admin = fakeAdmin(state);
  const result = await readQueuedActionGenerationRun(
    admin,
    "22222222-2222-4222-8222-222222222222",
    "44444444-4444-4444-8444-444444444444",
  );
  assertEquals(result.error, null);
  assertEquals(result.data?.id, "22222222-2222-4222-8222-222222222222");
  assertEquals(result.data?.creator_id, "55555555-5555-4555-8555-555555555555");

  const op = state.ops[0];
  assertEquals(op.table, "weekly_generation_runs");
  assertEquals(op.operation, "select");
  assertEquals(
    op.selectColumns,
    "id,workspace_id,creator_id,status,weekly_plan_id,error_code",
  );
  assertEquals(op.filters.id, "22222222-2222-4222-8222-222222222222");
  assertEquals(op.filters.workspace_id, "44444444-4444-4444-8444-444444444444");
});

function assert(
  condition: unknown,
  message = "Assertion failed",
): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  if (!Object.is(actual, expected)) {
    throw new Error(
      message ??
        `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
