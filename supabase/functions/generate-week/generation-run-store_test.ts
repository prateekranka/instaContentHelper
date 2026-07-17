import {
  completeDayGenerationRun,
  completeFullWeekGenerationRun,
  completeGenerationRunMinimal,
  completePartialGenerationRun,
  GENERATION_RUN_CANCELLATION_SELECT,
  GENERATION_RUN_STATUS_SELECT,
  insertDayGenerationRun,
  insertWeekGenerationRun,
  linkGenerationRunWeeklyPlan,
  markGenerationRunFailed,
  readGenerationRunCancellationState,
  readGenerationRunStatus,
  updateGenerationRunProgress,
} from "./generation-run-store.ts";

type CapturedOp = {
  table: string;
  operation: "select" | "insert" | "update";
  values: unknown;
  filters: Record<string, unknown>;
  filterOrder: string[];
  selectColumns?: string;
  terminal?: "single" | "maybeSingle";
};

type FakeState = {
  ops: CapturedOp[];
  runs: Record<string, unknown>[];
  lookupError?: { message: string };
  writeError?: { message: string };
  insertReturnNull?: boolean;
};

const RUN_ID = "22222222-2222-4222-8222-222222222222";
const WORKSPACE = "44444444-4444-4444-8444-444444444444";
const CREATOR = "55555555-5555-4555-8555-555555555555";
const PLAN = "33333333-3333-4333-8333-333333333333";
const MEMBER = "66666666-6666-4666-8666-666666666666";
const SETUP = "77777777-7777-4777-8777-777777777777";
const CARD = "88888888-8888-4888-8888-888888888888";

function assert(
  condition: unknown,
  message = "Assertion failed",
): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

function assertEquals(actual: unknown, expected: unknown, message?: string) {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  if (left !== right) {
    throw new Error(message ?? `Expected ${right}, got ${left}`);
  }
}

function fakeAdmin(state: FakeState) {
  return {
    from(table: string) {
      return new FakeQuery(table, state);
    },
  };
}

class FakeQuery {
  private operation: CapturedOp["operation"] = "select";
  private values: unknown = null;
  private filters: Record<string, unknown> = {};
  private filterOrder: string[] = [];
  private selectColumns?: string;
  private terminal?: "single" | "maybeSingle";

  constructor(
    private readonly table: string,
    private readonly state: FakeState,
  ) {}

  select(columns?: string): FakeQuery {
    this.selectColumns = columns;
    return this;
  }

  insert(values: unknown): FakeQuery {
    this.operation = "insert";
    this.values = values;
    return this;
  }

  update(values: Record<string, unknown>): FakeQuery {
    this.operation = "update";
    this.values = values;
    return this;
  }

  eq(column: string, value: unknown): FakeQuery {
    this.filters[column] = value;
    this.filterOrder.push(column);
    return this;
  }

  single(): FakeQuery {
    this.terminal = "single";
    return this;
  }

  maybeSingle(): FakeQuery {
    this.terminal = "maybeSingle";
    return this;
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
      filterOrder: [...this.filterOrder],
      selectColumns: this.selectColumns,
      terminal: this.terminal,
    });
  }

  private resolve(): { data: unknown; error: unknown } {
    this.capture();
    assertEquals(this.table, "weekly_generation_runs");

    if (this.operation === "select") {
      if (this.state.lookupError) {
        return { data: null, error: this.state.lookupError };
      }
      const row = this.state.runs.find((run) =>
        (!this.filters.id || run.id === this.filters.id) &&
        (!this.filters.workspace_id ||
          run.workspace_id === this.filters.workspace_id) &&
        (!this.filters.status || run.status === this.filters.status)
      );
      return { data: row ?? null, error: null };
    }

    if (this.operation === "insert") {
      if (this.state.writeError) {
        return { data: null, error: this.state.writeError };
      }
      if (this.state.insertReturnNull) {
        return { data: null, error: null };
      }
      const row = {
        id: RUN_ID,
        ...(this.values as Record<string, unknown>),
      };
      this.state.runs.push(row);
      return {
        data: this.selectColumns === "id" ? { id: row.id } : row,
        error: null,
      };
    }

    if (this.state.writeError) {
      return { data: null, error: this.state.writeError };
    }
    const rows = this.state.runs.filter((run) =>
      (!this.filters.id || run.id === this.filters.id) &&
      (!this.filters.workspace_id ||
        run.workspace_id === this.filters.workspace_id) &&
      (!this.filters.status || run.status === this.filters.status)
    );
    rows.forEach((row) =>
      Object.assign(row, this.values as Record<string, unknown>)
    );
    return { data: rows[0] ?? null, error: null };
  }
}

Deno.test("readGenerationRunStatus uses exact select, filters, and maybeSingle", async () => {
  const state: FakeState = {
    ops: [],
    runs: [{
      id: RUN_ID,
      workspace_id: WORKSPACE,
      creator_id: CREATOR,
      status: "running",
    }],
  };
  const result = await readGenerationRunStatus(
    fakeAdmin(state) as never,
    RUN_ID,
    WORKSPACE,
  );
  assertEquals(result.error, null);
  assertEquals(result.data?.id, RUN_ID);

  const op = state.ops[0];
  assertEquals(op.table, "weekly_generation_runs");
  assertEquals(op.operation, "select");
  assertEquals(op.selectColumns, GENERATION_RUN_STATUS_SELECT);
  assertEquals(
    GENERATION_RUN_STATUS_SELECT,
    "id,workspace_id,creator_id,weekly_setup_id,requested_by_member_id,status,weekly_plan_id,output_snapshot,input_snapshot,error_code,completed_at,model,generation_scope,target_daily_card_id,target_scheduled_date",
  );
  assertEquals(op.filterOrder, ["id", "workspace_id"]);
  assertEquals(op.filters, { id: RUN_ID, workspace_id: WORKSPACE });
  assertEquals(op.terminal, "maybeSingle");
});

Deno.test("readGenerationRunCancellationState selects status/error_code by id", async () => {
  const state: FakeState = {
    ops: [],
    runs: [{
      id: RUN_ID,
      status: "failed",
      error_code: "generation_cancelled",
    }],
  };
  const result = await readGenerationRunCancellationState(
    fakeAdmin(state) as never,
    RUN_ID,
  );
  assertEquals(result.error, null);
  assertEquals(result.data?.status, "failed");
  assertEquals(result.data?.error_code, "generation_cancelled");

  const op = state.ops[0];
  assertEquals(op.table, "weekly_generation_runs");
  assertEquals(op.selectColumns, GENERATION_RUN_CANCELLATION_SELECT);
  assertEquals(GENERATION_RUN_CANCELLATION_SELECT, "status,error_code");
  assertEquals(op.filterOrder, ["id"]);
  assertEquals(op.filters, { id: RUN_ID });
  assertEquals(op.terminal, "maybeSingle");
});

Deno.test("insertWeekGenerationRun writes week payload and returns id via single", async () => {
  const state: FakeState = { ops: [], runs: [] };
  const row = {
    workspace_id: WORKSPACE,
    creator_id: CREATOR,
    weekly_setup_id: SETUP,
    requested_by_member_id: MEMBER,
    status: "running",
    model: "gpt-test",
    prompt_version: "creator-weekly-generation-v1",
    input_snapshot: { week: true },
    warnings: [],
    assumptions: [],
  };
  const result = await insertWeekGenerationRun(fakeAdmin(state) as never, row);
  assertEquals(result.error, null);
  assertEquals(result.data, { id: RUN_ID });

  const op = state.ops[0];
  assertEquals(op.table, "weekly_generation_runs");
  assertEquals(op.operation, "insert");
  assertEquals(op.values, row);
  assertEquals(op.selectColumns, "id");
  assertEquals(op.terminal, "single");
  assertEquals(op.filterOrder, []);
});

Deno.test("insertDayGenerationRun writes day scope payload and returns id via single", async () => {
  const state: FakeState = { ops: [], runs: [] };
  const row = {
    workspace_id: WORKSPACE,
    creator_id: CREATOR,
    weekly_setup_id: null,
    weekly_plan_id: PLAN,
    requested_by_member_id: MEMBER,
    status: "running",
    model: "deepseek-test",
    prompt_version: "creator-weekly-generation-v1",
    generation_scope: "day",
    target_daily_card_id: CARD,
    target_scheduled_date: "2026-06-08",
    input_snapshot: { day: true },
    warnings: [],
    assumptions: [],
  };
  const result = await insertDayGenerationRun(fakeAdmin(state) as never, row);
  assertEquals(result.error, null);
  assertEquals(result.data, { id: RUN_ID });

  const op = state.ops[0];
  assertEquals(op.table, "weekly_generation_runs");
  assertEquals(op.operation, "insert");
  assertEquals(op.values, row);
  assertEquals(
    (op.values as Record<string, unknown>).generation_scope,
    "day",
  );
  assertEquals(
    (op.values as Record<string, unknown>).target_daily_card_id,
    CARD,
  );
  assertEquals(
    (op.values as Record<string, unknown>).target_scheduled_date,
    "2026-06-08",
  );
  assertEquals(
    (op.values as Record<string, unknown>).model,
    "deepseek-test",
  );
  assertEquals(
    (op.values as Record<string, unknown>).prompt_version,
    "creator-weekly-generation-v1",
  );
  assertEquals(op.selectColumns, "id");
  assertEquals(op.terminal, "single");
});

Deno.test("insert helpers return raw null data and write errors", async () => {
  const nullState: FakeState = { ops: [], runs: [], insertReturnNull: true };
  const nullResult = await insertWeekGenerationRun(
    fakeAdmin(nullState) as never,
    { status: "running" },
  );
  assertEquals(nullResult.data, null);
  assertEquals(nullResult.error, null);

  const errorState: FakeState = {
    ops: [],
    runs: [],
    writeError: { message: "insert_failed" },
  };
  const errorResult = await insertDayGenerationRun(
    fakeAdmin(errorState) as never,
    { status: "running" },
  );
  assertEquals(errorResult.data, null);
  assertEquals(errorResult.error, { message: "insert_failed" });
});

Deno.test("linkGenerationRunWeeklyPlan updates only running rows", async () => {
  const state: FakeState = {
    ops: [],
    runs: [{ id: RUN_ID, status: "running", weekly_plan_id: null }],
  };
  const result = await linkGenerationRunWeeklyPlan(
    fakeAdmin(state) as never,
    RUN_ID,
    PLAN,
  );
  assertEquals(result.error, null);
  assertEquals(state.runs[0].weekly_plan_id, PLAN);

  const op = state.ops[0];
  assertEquals(op.table, "weekly_generation_runs");
  assertEquals(op.operation, "update");
  assertEquals(op.values, { weekly_plan_id: PLAN });
  assertEquals(op.filterOrder, ["id", "status"]);
  assertEquals(op.filters, { id: RUN_ID, status: "running" });
});

Deno.test("updateGenerationRunProgress guards status running", async () => {
  const progress = { days: [], status: "running" };
  const state: FakeState = {
    ops: [],
    runs: [{ id: RUN_ID, status: "running", output_snapshot: null }],
  };
  const result = await updateGenerationRunProgress(
    fakeAdmin(state) as never,
    RUN_ID,
    progress,
  );
  assertEquals(result.error, null);
  assertEquals(state.runs[0].output_snapshot, progress);

  const op = state.ops[0];
  assertEquals(op.table, "weekly_generation_runs");
  assertEquals(op.values, { output_snapshot: progress });
  assertEquals(op.filterOrder, ["id", "status"]);
  assertEquals(op.filters, { id: RUN_ID, status: "running" });
});

Deno.test("completeFullWeekGenerationRun writes exact completion payload", async () => {
  const state: FakeState = {
    ops: [],
    runs: [{ id: RUN_ID, status: "running" }],
  };
  const snapshot = { status: "draft", daily_cards: [] };
  const result = await completeFullWeekGenerationRun(
    fakeAdmin(state) as never,
    RUN_ID,
    {
      weekly_plan_id: PLAN,
      output_snapshot: snapshot,
      warnings: ["w"],
      assumptions: ["a"],
      completed_at: "2026-06-08T12:00:00.000Z",
    },
  );
  assertEquals(result.error, null);

  const op = state.ops[0];
  assertEquals(op.table, "weekly_generation_runs");
  assertEquals(op.operation, "update");
  assertEquals(op.values, {
    weekly_plan_id: PLAN,
    status: "completed",
    output_snapshot: snapshot,
    warnings: ["w"],
    assumptions: ["a"],
    completed_at: "2026-06-08T12:00:00.000Z",
    error_code: null,
  });
  assertEquals(op.filterOrder, ["id"]);
  assertEquals(op.filters, { id: RUN_ID });
});

Deno.test("completePartialGenerationRun writes partial_generation error code", async () => {
  const state: FakeState = {
    ops: [],
    runs: [{ id: RUN_ID, status: "running" }],
  };
  const progress = { days: [{ status: "failed" }] };
  const result = await completePartialGenerationRun(
    fakeAdmin(state) as never,
    RUN_ID,
    {
      weekly_plan_id: PLAN,
      output_snapshot: progress,
      completed_at: "2026-06-08T12:30:00.000Z",
    },
  );
  assertEquals(result.error, null);

  const op = state.ops[0];
  assertEquals(op.values, {
    weekly_plan_id: PLAN,
    status: "completed",
    output_snapshot: progress,
    error_code: "partial_generation",
    completed_at: "2026-06-08T12:30:00.000Z",
  });
  assertEquals(op.filterOrder, ["id"]);
  assertEquals(op.filters, { id: RUN_ID });
});

Deno.test("completeDayGenerationRun writes day completion payload", async () => {
  const state: FakeState = {
    ops: [],
    runs: [{ id: RUN_ID, status: "running" }],
  };
  const snapshot = { status: "draft", daily_card: { title: "day" } };
  const result = await completeDayGenerationRun(
    fakeAdmin(state) as never,
    RUN_ID,
    {
      output_snapshot: snapshot,
      warnings: [],
      assumptions: ["day assumption"],
      completed_at: "2026-06-08T13:00:00.000Z",
    },
  );
  assertEquals(result.error, null);

  const op = state.ops[0];
  assertEquals(op.values, {
    status: "completed",
    output_snapshot: snapshot,
    warnings: [],
    assumptions: ["day assumption"],
    completed_at: "2026-06-08T13:00:00.000Z",
    error_code: null,
  });
  assertEquals(op.filterOrder, ["id"]);
  assertEquals(op.filters, { id: RUN_ID });
});

Deno.test("completeGenerationRunMinimal accepts caller-built fallback payload", async () => {
  const state: FakeState = {
    ops: [],
    runs: [{ id: RUN_ID, status: "running" }],
  };
  const withPlan = await completeGenerationRunMinimal(
    fakeAdmin(state) as never,
    RUN_ID,
    {
      status: "completed",
      completed_at: "2026-06-08T14:00:00.000Z",
      error_code: null,
      weekly_plan_id: PLAN,
    },
  );
  assertEquals(withPlan.error, null);
  assertEquals(state.ops[0].values, {
    status: "completed",
    completed_at: "2026-06-08T14:00:00.000Z",
    error_code: null,
    weekly_plan_id: PLAN,
  });
  assertEquals(state.ops[0].filterOrder, ["id"]);

  const withoutPlanState: FakeState = {
    ops: [],
    runs: [{ id: RUN_ID, status: "running" }],
  };
  const withoutPlan = await completeGenerationRunMinimal(
    fakeAdmin(withoutPlanState) as never,
    RUN_ID,
    {
      status: "completed",
      completed_at: "2026-06-08T14:00:00.000Z",
      error_code: null,
    },
  );
  assertEquals(withoutPlan.error, null);
  assertEquals(withoutPlanState.ops[0].values, {
    status: "completed",
    completed_at: "2026-06-08T14:00:00.000Z",
    error_code: null,
  });
  assert(
    !("weekly_plan_id" in
      (withoutPlanState.ops[0].values as Record<string, unknown>)),
  );
});

Deno.test("markGenerationRunFailed writes failed payload by id", async () => {
  const state: FakeState = {
    ops: [],
    runs: [{ id: RUN_ID, status: "running", error_code: null }],
  };
  await markGenerationRunFailed(
    fakeAdmin(state) as never,
    RUN_ID,
    "invalid_generated_week",
  );
  assertEquals(state.runs[0].status, "failed");
  assertEquals(state.runs[0].error_code, "invalid_generated_week");
  assertEquals(typeof state.runs[0].completed_at, "string");

  const op = state.ops[0];
  assertEquals(op.table, "weekly_generation_runs");
  assertEquals(op.operation, "update");
  assertEquals((op.values as Record<string, unknown>).status, "failed");
  assertEquals(
    (op.values as Record<string, unknown>).error_code,
    "invalid_generated_week",
  );
  assertEquals(
    typeof (op.values as Record<string, unknown>).completed_at,
    "string",
  );
  assertEquals(op.filterOrder, ["id"]);
  assertEquals(op.filters, { id: RUN_ID });
});

Deno.test("update helpers surface raw write errors without HTTP mapping", async () => {
  const state: FakeState = {
    ops: [],
    runs: [{ id: RUN_ID, status: "running" }],
    writeError: { message: "db_down" },
  };
  const admin = fakeAdmin(state) as never;

  assertEquals(
    (await linkGenerationRunWeeklyPlan(admin, RUN_ID, PLAN)).error,
    { message: "db_down" },
  );
  assertEquals(
    (await updateGenerationRunProgress(admin, RUN_ID, { x: 1 })).error,
    { message: "db_down" },
  );
  assertEquals(
    (await completeFullWeekGenerationRun(admin, RUN_ID, {
      weekly_plan_id: PLAN,
      output_snapshot: {},
      warnings: [],
      assumptions: [],
      completed_at: "2026-06-08T15:00:00.000Z",
    })).error,
    { message: "db_down" },
  );
  assertEquals(
    (await completePartialGenerationRun(admin, RUN_ID, {
      weekly_plan_id: PLAN,
      output_snapshot: {},
      completed_at: "2026-06-08T15:00:00.000Z",
    })).error,
    { message: "db_down" },
  );
  assertEquals(
    (await completeDayGenerationRun(admin, RUN_ID, {
      output_snapshot: {},
      warnings: [],
      assumptions: [],
      completed_at: "2026-06-08T15:00:00.000Z",
    })).error,
    { message: "db_down" },
  );
  assertEquals(
    (await completeGenerationRunMinimal(admin, RUN_ID, {
      status: "completed",
      completed_at: "2026-06-08T15:00:00.000Z",
      error_code: null,
    })).error,
    { message: "db_down" },
  );
});
