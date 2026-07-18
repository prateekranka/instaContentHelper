import { createDayGenerationRun } from "./generation-run-start.ts";
import type { GenerationInputSnapshot } from "./generation.ts";

type CapturedOp = {
  table: string;
  operation: "insert" | "update";
  values: unknown;
  filters: Record<string, unknown>;
  filterOrder: string[];
  selectColumns?: string;
  terminal?: "single";
};

type FakeState = {
  ops: CapturedOp[];
  runs: Record<string, unknown>[];
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
  private operation: CapturedOp["operation"] = "insert";
  private values: unknown = null;
  private filters: Record<string, unknown> = {};
  private filterOrder: string[] = [];
  private selectColumns?: string;
  private terminal?: "single";

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
      (!this.filters.status || run.status === this.filters.status)
    );
    rows.forEach((row) =>
      Object.assign(row, this.values as Record<string, unknown>)
    );
    return { data: rows[0] ?? null, error: null };
  }
}

function dayInputSnapshot(): GenerationInputSnapshot {
  return {
    week_start_date: "2026-06-08",
    creator: { id: CREATOR, display_name: "Creator" },
    weekly_setup: null,
    published_week: null,
    brand_briefs: [],
    key_moments: [],
    audio_options: [],
  } as unknown as GenerationInputSnapshot;
}

Deno.test("createDayGenerationRun writes exact day scope payload and returns id", async () => {
  const state: FakeState = { ops: [], runs: [] };
  const inputSnapshot = dayInputSnapshot();
  const result = await createDayGenerationRun(
    fakeAdmin(state) as never,
    {
      session: { workspaceID: WORKSPACE },
      request: {
        creator_id: CREATOR,
        weekly_plan_id: PLAN,
        scheduled_date: "2026-06-08",
      },
      plan: { weekly_setup_id: SETUP },
      targetCard: { id: CARD },
      model: "deepseek-test",
      inputSnapshot,
    },
    MEMBER,
  );
  assertEquals(result, { run: { id: RUN_ID } });

  const op = state.ops[0];
  assertEquals(op.table, "weekly_generation_runs");
  assertEquals(op.operation, "insert");
  assertEquals(op.values, {
    workspace_id: WORKSPACE,
    creator_id: CREATOR,
    weekly_setup_id: SETUP,
    weekly_plan_id: PLAN,
    requested_by_member_id: MEMBER,
    status: "running",
    model: "deepseek-test",
    prompt_version: "creator-weekly-generation-v1",
    generation_scope: "day",
    target_daily_card_id: CARD,
    target_scheduled_date: "2026-06-08",
    input_snapshot: inputSnapshot,
    warnings: [],
    assumptions: [],
  });
  assertEquals(op.selectColumns, "id");
  assertEquals(op.terminal, "single");
});

Deno.test("createDayGenerationRun nulls missing weekly_setup and target card", async () => {
  const state: FakeState = { ops: [], runs: [] };
  await createDayGenerationRun(
    fakeAdmin(state) as never,
    {
      session: { workspaceID: WORKSPACE },
      request: {
        creator_id: CREATOR,
        weekly_plan_id: PLAN,
        scheduled_date: "2026-06-09",
      },
      plan: {},
      model: "deepseek-test",
      inputSnapshot: dayInputSnapshot(),
    },
    MEMBER,
  );
  const values = state.ops[0].values as Record<string, unknown>;
  assertEquals(values.weekly_setup_id, null);
  assertEquals(values.target_daily_card_id, null);
});

Deno.test("createDayGenerationRun maps insert failures to create_day_generation_run", async () => {
  const nullState: FakeState = { ops: [], runs: [], insertReturnNull: true };
  const nullResult = await createDayGenerationRun(
    fakeAdmin(nullState) as never,
    {
      session: { workspaceID: WORKSPACE },
      request: {
        creator_id: CREATOR,
        weekly_plan_id: PLAN,
        scheduled_date: "2026-06-08",
      },
      plan: { weekly_setup_id: null },
      model: "deepseek-test",
      inputSnapshot: dayInputSnapshot(),
    },
    MEMBER,
  );
  assert("response" in nullResult);
  assertEquals(nullResult.response.status, 500);
  const nullBody = await nullResult.response.json();
  assertEquals(nullBody.step, "create_day_generation_run");

  const errorState: FakeState = {
    ops: [],
    runs: [],
    writeError: { message: "day_insert_failed" },
  };
  const errorResult = await createDayGenerationRun(
    fakeAdmin(errorState) as never,
    {
      session: { workspaceID: WORKSPACE },
      request: {
        creator_id: CREATOR,
        weekly_plan_id: PLAN,
        scheduled_date: "2026-06-08",
      },
      plan: { weekly_setup_id: null },
      model: "deepseek-test",
      inputSnapshot: dayInputSnapshot(),
    },
    MEMBER,
  );
  assert("response" in errorResult);
  assertEquals(errorResult.response.status, 500);
  const errorBody = await errorResult.response.json();
  assertEquals(errorBody, {
    error: "generation_persist_failed",
    step: "create_day_generation_run",
    detail: "day_insert_failed",
  });
});
