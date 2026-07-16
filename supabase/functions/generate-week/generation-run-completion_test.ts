import {
  completeDayGenerationRun,
  completeGenerationRun,
  markGenerationRunFailed,
} from "./generation-run-completion.ts";
import type { RegenerateDayDraftResponse } from "./generation-run-snapshot.ts";

type CapturedOp = {
  table: string;
  operation: "update";
  values: unknown;
  filters: Record<string, unknown>;
  filterOrder: string[];
};

type FakeState = {
  ops: CapturedOp[];
  runs: Record<string, unknown>[];
  snapshotWriteError?: { message: string };
  minimalWriteError?: { message: string };
};

const RUN_ID = "22222222-2222-4222-8222-222222222222";
const PLAN = "33333333-3333-4333-8333-333333333333";
const COMPLETED_AT = "2026-06-08T14:00:00.000Z";

const WEEK_PAYLOAD = {
  generation_id: RUN_ID,
  weekly_plan_id: PLAN,
  status: "draft" as const,
  strategy_summary: "week strategy",
  warnings: ["week warning"],
  assumptions: ["week assumption"],
  daily_cards: [],
  idea_bank: [],
  source_summary: "sources",
  generated_at: COMPLETED_AT,
};

const DAY_PAYLOAD: RegenerateDayDraftResponse = {
  generation_id: RUN_ID,
  weekly_plan_id: PLAN,
  status: "draft",
  target_scheduled_date: "2026-06-08",
  daily_card: { title: "day card" } as RegenerateDayDraftResponse["daily_card"],
  warnings: ["day warning"],
  assumptions: ["day assumption"],
  source_summary: "day sources",
  generated_at: COMPLETED_AT,
};

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
  private values: Record<string, unknown> = {};
  private filters: Record<string, unknown> = {};
  private filterOrder: string[] = [];

  constructor(
    private readonly table: string,
    private readonly state: FakeState,
  ) {}

  update(values: Record<string, unknown>): FakeQuery {
    this.values = values;
    return this;
  }

  eq(column: string, value: unknown): FakeQuery {
    this.filters[column] = value;
    this.filterOrder.push(column);
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
      operation: "update",
      values: { ...this.values },
      filters: { ...this.filters },
      filterOrder: [...this.filterOrder],
    });
  }

  private resolve(): { data: unknown; error: unknown } {
    this.capture();
    assertEquals(this.table, "weekly_generation_runs");

    const opIndex = this.state.ops.length - 1;
    if (opIndex === 0 && this.state.snapshotWriteError) {
      return { data: null, error: this.state.snapshotWriteError };
    }
    if (this.state.minimalWriteError) {
      const isMinimalFallback = opIndex > 0 ||
        (!this.state.snapshotWriteError &&
          !("output_snapshot" in this.values));
      if (isMinimalFallback) {
        return { data: null, error: this.state.minimalWriteError };
      }
    }

    const rows = this.state.runs.filter((
      run,
    ) => (!this.filters.id || run.id === this.filters.id));
    rows.forEach((row) => Object.assign(row, this.values));
    return { data: rows[0] ?? null, error: null };
  }
}

Deno.test("successful full-week completion performs one exact update", async () => {
  const state: FakeState = {
    ops: [],
    runs: [{ id: RUN_ID, status: "running" }],
  };

  const result = await completeGenerationRun(
    fakeAdmin(state) as never,
    RUN_ID,
    PLAN,
    WEEK_PAYLOAD,
    COMPLETED_AT,
  );

  assertEquals(result, { ok: true });
  assertEquals(state.ops.length, 1);
  assertEquals(state.ops[0].values, {
    weekly_plan_id: PLAN,
    status: "completed",
    output_snapshot: WEEK_PAYLOAD,
    warnings: WEEK_PAYLOAD.warnings,
    assumptions: WEEK_PAYLOAD.assumptions,
    completed_at: COMPLETED_AT,
    error_code: null,
  });
  assertEquals(state.ops[0].filterOrder, ["id"]);
  assertEquals(state.ops[0].filters, { id: RUN_ID });
});

Deno.test("successful day completion performs one exact update", async () => {
  const state: FakeState = {
    ops: [],
    runs: [{ id: RUN_ID, status: "running" }],
  };

  const result = await completeDayGenerationRun(
    fakeAdmin(state) as never,
    RUN_ID,
    DAY_PAYLOAD,
    COMPLETED_AT,
  );

  assertEquals(result, { ok: true });
  assertEquals(state.ops.length, 1);
  assertEquals(state.ops[0].values, {
    status: "completed",
    output_snapshot: DAY_PAYLOAD,
    warnings: DAY_PAYLOAD.warnings,
    assumptions: DAY_PAYLOAD.assumptions,
    completed_at: COMPLETED_AT,
    error_code: null,
  });
  assertEquals(state.ops[0].filterOrder, ["id"]);
  assertEquals(state.ops[0].filters, { id: RUN_ID });
});

Deno.test("snapshot failure falls back to exact minimal completion update", async () => {
  const state: FakeState = {
    ops: [],
    runs: [{ id: RUN_ID, status: "running" }],
    snapshotWriteError: { message: "snapshot_write_failed" },
  };
  const warnings: string[] = [];
  const originalWarn = console.warn;
  console.warn = (...args: unknown[]) => {
    warnings.push(String(args[0]));
  };
  try {
    const result = await completeGenerationRun(
      fakeAdmin(state) as never,
      RUN_ID,
      PLAN,
      WEEK_PAYLOAD,
      COMPLETED_AT,
    );
    assertEquals(result, { ok: true });
    assertEquals(state.ops.length, 2);
    assertEquals(state.ops[1].values, {
      status: "completed",
      completed_at: COMPLETED_AT,
      error_code: null,
      weekly_plan_id: PLAN,
    });
    assertEquals(state.ops[1].filterOrder, ["id"]);
    assertEquals(state.ops[1].filters, { id: RUN_ID });
    assertEquals(warnings, [
      "generate-week completion snapshot write failed; retrying minimal completion",
    ]);
  } finally {
    console.warn = originalWarn;
  }
});

Deno.test("minimal fallback includes weekly_plan_id for week and omits it for day", async () => {
  const weekState: FakeState = {
    ops: [],
    runs: [{ id: RUN_ID, status: "running" }],
    snapshotWriteError: { message: "snapshot_write_failed" },
  };
  const weekResult = await completeGenerationRun(
    fakeAdmin(weekState) as never,
    RUN_ID,
    PLAN,
    WEEK_PAYLOAD,
    COMPLETED_AT,
  );
  assertEquals(weekResult, { ok: true });
  assertEquals(weekState.ops[1].values, {
    status: "completed",
    completed_at: COMPLETED_AT,
    error_code: null,
    weekly_plan_id: PLAN,
  });

  const dayState: FakeState = {
    ops: [],
    runs: [{ id: RUN_ID, status: "running" }],
    snapshotWriteError: { message: "snapshot_write_failed" },
  };
  const dayResult = await completeDayGenerationRun(
    fakeAdmin(dayState) as never,
    RUN_ID,
    DAY_PAYLOAD,
    COMPLETED_AT,
  );
  assertEquals(dayResult, { ok: true });
  assertEquals(dayState.ops[1].values, {
    status: "completed",
    completed_at: COMPLETED_AT,
    error_code: null,
  });
  assert(
    !("weekly_plan_id" in
      (dayState.ops[1].values as Record<string, unknown>)),
  );
});

Deno.test("fallback failure returns generationPersistFailure with the original step", async () => {
  const weekState: FakeState = {
    ops: [],
    runs: [{ id: RUN_ID, status: "running" }],
    snapshotWriteError: { message: "snapshot_write_failed" },
    minimalWriteError: { message: "minimal_write_failed" },
  };
  const weekResult = await completeGenerationRun(
    fakeAdmin(weekState) as never,
    RUN_ID,
    PLAN,
    WEEK_PAYLOAD,
    COMPLETED_AT,
  );
  assert("response" in weekResult);
  assertEquals(weekResult.response.status, 500);
  const weekBody = await weekResult.response.json();
  assertEquals(weekBody, {
    error: "generation_persist_failed",
    step: "complete_generation_run",
    detail: "minimal_write_failed",
  });

  const dayState: FakeState = {
    ops: [],
    runs: [{ id: RUN_ID, status: "running" }],
    snapshotWriteError: { message: "snapshot_write_failed" },
    minimalWriteError: { message: "minimal_write_failed" },
  };
  const dayResult = await completeDayGenerationRun(
    fakeAdmin(dayState) as never,
    RUN_ID,
    DAY_PAYLOAD,
    COMPLETED_AT,
  );
  assert("response" in dayResult);
  assertEquals(dayResult.response.status, 500);
  const dayBody = await dayResult.response.json();
  assertEquals(dayBody, {
    error: "generation_persist_failed",
    step: "complete_day_generation_run",
    detail: "minimal_write_failed",
  });
});

Deno.test("markGenerationRunFailed preserves exact failed payload/filter semantics", async () => {
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
  assertEquals(state.ops.length, 1);
  assertEquals(state.ops[0].table, "weekly_generation_runs");
  assertEquals(state.ops[0].operation, "update");
  assertEquals(
    (state.ops[0].values as Record<string, unknown>).status,
    "failed",
  );
  assertEquals(
    (state.ops[0].values as Record<string, unknown>).error_code,
    "invalid_generated_week",
  );
  assertEquals(
    typeof (state.ops[0].values as Record<string, unknown>).completed_at,
    "string",
  );
  assertEquals(state.ops[0].filterOrder, ["id"]);
  assertEquals(state.ops[0].filters, { id: RUN_ID });
});

Deno.test("warning/fallback call order and no unnecessary fallback on success", async () => {
  const successState: FakeState = {
    ops: [],
    runs: [{ id: RUN_ID, status: "running" }],
  };
  const successWarnings: string[] = [];
  const originalWarn = console.warn;
  console.warn = (...args: unknown[]) => {
    successWarnings.push(String(args[0]));
  };
  try {
    const weekSuccess = await completeGenerationRun(
      fakeAdmin(successState) as never,
      RUN_ID,
      PLAN,
      WEEK_PAYLOAD,
      COMPLETED_AT,
    );
    assertEquals(weekSuccess, { ok: true });
    assertEquals(successState.ops.length, 1);
    assertEquals(successWarnings, []);

    const daySuccess = await completeDayGenerationRun(
      fakeAdmin({
        ops: [],
        runs: [{ id: RUN_ID, status: "running" }],
      }) as never,
      RUN_ID,
      DAY_PAYLOAD,
      COMPLETED_AT,
    );
    assertEquals(daySuccess, { ok: true });
    assertEquals(successWarnings, []);
  } finally {
    console.warn = originalWarn;
  }

  const fallbackState: FakeState = {
    ops: [],
    runs: [{ id: RUN_ID, status: "running" }],
    snapshotWriteError: { message: "snapshot_write_failed" },
  };
  const fallbackWarnings: string[] = [];
  console.warn = (...args: unknown[]) => {
    fallbackWarnings.push(String(args[0]));
  };
  try {
    await completeDayGenerationRun(
      fakeAdmin(fallbackState) as never,
      RUN_ID,
      DAY_PAYLOAD,
      COMPLETED_AT,
    );
    assertEquals(fallbackState.ops.length, 2);
    assertEquals(
      (fallbackState.ops[0].values as Record<string, unknown>).output_snapshot,
      DAY_PAYLOAD,
    );
    assert(
      !("output_snapshot" in
        (fallbackState.ops[1].values as Record<string, unknown>)),
    );
    assertEquals(fallbackWarnings, [
      "generate-week completion snapshot write failed; retrying minimal completion",
    ]);
  } finally {
    console.warn = originalWarn;
  }
});
