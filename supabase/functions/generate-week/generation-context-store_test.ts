import {
  AUDIO_OPTIONS_CONTEXT_SELECT,
  BRAND_BRIEFS_CONTEXT_SELECT,
  CONFIRMED_REFERENCES_CONTEXT_SELECT,
  CREATOR_LOOKUP_SELECT,
  CREATOR_PROFILE_CONTEXT_SELECT,
  DAY_GENERATION_PLAN_SELECT,
  dayGenerationCardSelect,
  IDEA_BANK_CONTEXT_SELECT,
  KEY_MOMENTS_CONTEXT_SELECT,
  PATTERNS_CONTEXT_SELECT,
  PUBLISHED_WEEK_LOOKUP_SELECT,
  readContextTableRows,
  readCreatorRow,
  readDailyCardsForPlan,
  readDayGenerationPlanRow,
  readGenerationContextRows,
  readLatestWeeklySetupForWeek,
  readPublishedWeekRow,
  readWeeklySetupByID,
  RECENT_ARCHIVE_CONTEXT_SELECT,
  REFERENCE_EXTRACTIONS_CONTEXT_SELECT,
  requestWeekWindowEnd,
  rowsOrEmpty,
  TRENDS_CONTEXT_SELECT,
  WEEKLY_SETUP_LOOKUP_SELECT,
} from "./generation-context-store.ts";

type CapturedOp = {
  table: string;
  operation: "select";
  filters: Record<string, unknown>;
  filterOrder: string[];
  inFilters: Record<string, unknown[]>;
  rangeFilters: Record<string, { gte?: unknown; lte?: unknown }>;
  selectColumns?: string;
  order?: { column: string; ascending?: boolean };
  limit?: number;
  terminal?: "single" | "maybeSingle";
};

type FakeState = {
  ops: CapturedOp[];
  rowsByTable: Record<string, Record<string, unknown>[]>;
  errorsByTable?: Record<string, { message: string }>;
  globalSelectError?: { message: string };
};

const WORKSPACE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const CREATOR = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const PLAN = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const SETUP = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const WEEK_START = "2026-06-08";

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
  private filters: Record<string, unknown> = {};
  private filterOrder: string[] = [];
  private inFilters: Record<string, unknown[]> = {};
  private rangeFilters: Record<string, { gte?: unknown; lte?: unknown }> = {};
  private selectColumns?: string;
  private orderSpec?: { column: string; ascending?: boolean };
  private limitCount?: number;
  private terminal?: "single" | "maybeSingle";

  constructor(
    private readonly table: string,
    private readonly state: FakeState,
  ) {}

  select(columns?: string): FakeQuery {
    this.selectColumns = columns;
    return this;
  }

  eq(column: string, value: unknown): FakeQuery {
    this.filters[column] = value;
    this.filterOrder.push(column);
    return this;
  }

  in(column: string, values: unknown[]): FakeQuery {
    this.inFilters[column] = values;
    this.filterOrder.push(`in:${column}`);
    return this;
  }

  gte(column: string, value: unknown): FakeQuery {
    this.rangeFilters[column] = {
      ...this.rangeFilters[column],
      gte: value,
    };
    this.filterOrder.push(`gte:${column}`);
    return this;
  }

  lte(column: string, value: unknown): FakeQuery {
    this.rangeFilters[column] = {
      ...this.rangeFilters[column],
      lte: value,
    };
    this.filterOrder.push(`lte:${column}`);
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

  private resolve(): { data: unknown; error: unknown } {
    this.state.ops.push({
      table: this.table,
      operation: "select",
      filters: { ...this.filters },
      filterOrder: [...this.filterOrder],
      inFilters: { ...this.inFilters },
      rangeFilters: { ...this.rangeFilters },
      selectColumns: this.selectColumns,
      order: this.orderSpec,
      limit: this.limitCount,
      terminal: this.terminal,
    });

    if (this.state.globalSelectError) {
      return { data: null, error: this.state.globalSelectError };
    }
    const tableError = this.state.errorsByTable?.[this.table];
    if (tableError) {
      return { data: null, error: tableError };
    }

    let rows = (this.state.rowsByTable[this.table] ?? []).filter((row) =>
      this.matches(row)
    );

    if (this.orderSpec) {
      const column = this.orderSpec.column;
      const ascending = this.orderSpec.ascending !== false;
      rows = [...rows].sort((left, right) => {
        const a = String(left[column] ?? "");
        const b = String(right[column] ?? "");
        return ascending ? a.localeCompare(b) : b.localeCompare(a);
      });
    }

    if (this.limitCount != null) {
      rows = rows.slice(0, this.limitCount);
    }

    if (this.terminal === "maybeSingle") {
      return { data: rows[0] ?? null, error: null };
    }
    return { data: rows, error: null };
  }

  private matches(row: Record<string, unknown>): boolean {
    for (const [key, value] of Object.entries(this.filters)) {
      if (row[key] !== value) return false;
    }
    for (const [key, values] of Object.entries(this.inFilters)) {
      if (!values.includes(row[key])) return false;
    }
    for (const [key, range] of Object.entries(this.rangeFilters)) {
      const value = row[key];
      if (range.gte != null && String(value) < String(range.gte)) return false;
      if (range.lte != null && String(value) > String(range.lte)) return false;
    }
    return true;
  }
}

Deno.test("readCreatorRow uses exact select, filters, and maybeSingle", async () => {
  const state: FakeState = {
    ops: [],
    rowsByTable: {
      creators: [{
        id: CREATOR,
        workspace_id: WORKSPACE,
        status: "active",
        display_name: "Ada",
        default_timezone: "Asia/Kolkata",
      }],
    },
  };

  const result = await readCreatorRow(
    fakeAdmin(state) as never,
    WORKSPACE,
    CREATOR,
  );
  assertEquals(result.error, null);
  assertEquals(result.data?.id, CREATOR);
  assertEquals(CREATOR_LOOKUP_SELECT, "id,display_name,default_timezone");

  const op = state.ops[0];
  assertEquals(op.table, "creators");
  assertEquals(op.selectColumns, CREATOR_LOOKUP_SELECT);
  assertEquals(op.filterOrder, ["id", "workspace_id", "status"]);
  assertEquals(op.filters, {
    id: CREATOR,
    workspace_id: WORKSPACE,
    status: "active",
  });
  assertEquals(op.terminal, "maybeSingle");
});

Deno.test("readPublishedWeekRow selects published plan identity", async () => {
  const state: FakeState = {
    ops: [],
    rowsByTable: {
      weekly_plans: [{
        id: PLAN,
        workspace_id: WORKSPACE,
        creator_id: CREATOR,
        week_start_date: WEEK_START,
        status: "published",
      }],
    },
  };

  const result = await readPublishedWeekRow(
    fakeAdmin(state) as never,
    WORKSPACE,
    CREATOR,
    WEEK_START,
  );
  assertEquals(result.error, null);
  assertEquals(result.data?.id, PLAN);
  assertEquals(PUBLISHED_WEEK_LOOKUP_SELECT, "id");

  const op = state.ops[0];
  assertEquals(op.table, "weekly_plans");
  assertEquals(op.selectColumns, PUBLISHED_WEEK_LOOKUP_SELECT);
  assertEquals(op.filterOrder, [
    "workspace_id",
    "creator_id",
    "week_start_date",
    "status",
  ]);
  assertEquals(op.filters, {
    workspace_id: WORKSPACE,
    creator_id: CREATOR,
    week_start_date: WEEK_START,
    status: "published",
  });
  assertEquals(op.terminal, "maybeSingle");
});

Deno.test("readWeeklySetupByID requires setup id and returns raw error", async () => {
  const state: FakeState = {
    ops: [],
    rowsByTable: {},
    errorsByTable: {
      weekly_setups: { message: "setup boom" },
    },
  };

  const result = await readWeeklySetupByID(
    fakeAdmin(state) as never,
    WORKSPACE,
    CREATOR,
    SETUP,
  );
  assertEquals(result.data, null);
  assertEquals(result.error, { message: "setup boom" });

  const op = state.ops[0];
  assertEquals(op.table, "weekly_setups");
  assertEquals(op.selectColumns, WEEKLY_SETUP_LOOKUP_SELECT);
  assertEquals(op.filterOrder, ["workspace_id", "creator_id", "id"]);
  assertEquals(op.filters, {
    workspace_id: WORKSPACE,
    creator_id: CREATOR,
    id: SETUP,
  });
  assertEquals(op.terminal, "maybeSingle");
});

Deno.test("readLatestWeeklySetupForWeek orders by updated_at desc and limits 1", async () => {
  const state: FakeState = {
    ops: [],
    rowsByTable: {
      weekly_setups: [
        {
          id: "older",
          workspace_id: WORKSPACE,
          creator_id: CREATOR,
          week_start_date: WEEK_START,
          updated_at: "2026-06-01T00:00:00Z",
        },
        {
          id: SETUP,
          workspace_id: WORKSPACE,
          creator_id: CREATOR,
          week_start_date: WEEK_START,
          updated_at: "2026-06-07T00:00:00Z",
        },
      ],
    },
  };

  const result = await readLatestWeeklySetupForWeek(
    fakeAdmin(state) as never,
    WORKSPACE,
    CREATOR,
    WEEK_START,
  );
  assertEquals(result.error, null);
  assertEquals(result.data?.id, SETUP);

  const op = state.ops[0];
  assertEquals(op.table, "weekly_setups");
  assertEquals(op.selectColumns, WEEKLY_SETUP_LOOKUP_SELECT);
  assertEquals(op.filterOrder, [
    "workspace_id",
    "creator_id",
    "week_start_date",
  ]);
  assertEquals(op.order, { column: "updated_at", ascending: false });
  assertEquals(op.limit, 1);
  assertEquals(op.terminal, undefined);
});

Deno.test("readDayGenerationPlanRow uses exact select and filter order", async () => {
  const state: FakeState = {
    ops: [],
    rowsByTable: {
      weekly_plans: [{
        id: PLAN,
        workspace_id: WORKSPACE,
        creator_id: CREATOR,
        status: "draft",
        week_start_date: WEEK_START,
      }],
    },
  };

  const result = await readDayGenerationPlanRow(
    fakeAdmin(state) as never,
    WORKSPACE,
    CREATOR,
    PLAN,
  );
  assertEquals(result.error, null);
  assertEquals(result.data?.id, PLAN);
  assertEquals(
    DAY_GENERATION_PLAN_SELECT,
    "id,status,is_soft_locked,week_start_date,weekly_setup_id",
  );

  const op = state.ops[0];
  assertEquals(op.table, "weekly_plans");
  assertEquals(op.selectColumns, DAY_GENERATION_PLAN_SELECT);
  assertEquals(op.filterOrder, ["id", "workspace_id", "creator_id"]);
  assertEquals(op.filters, {
    id: PLAN,
    workspace_id: WORKSPACE,
    creator_id: CREATOR,
  });
  assertEquals(op.terminal, "maybeSingle");
});

Deno.test("readDailyCardsForPlan uses dayGenerationCardSelect and ascending date order", async () => {
  const state: FakeState = {
    ops: [],
    rowsByTable: {
      daily_cards: [
        {
          id: "card-2",
          workspace_id: WORKSPACE,
          creator_id: CREATOR,
          weekly_plan_id: PLAN,
          scheduled_date: "2026-06-09",
        },
        {
          id: "card-1",
          workspace_id: WORKSPACE,
          creator_id: CREATOR,
          weekly_plan_id: PLAN,
          scheduled_date: "2026-06-08",
        },
      ],
    },
  };

  const result = await readDailyCardsForPlan(
    fakeAdmin(state) as never,
    WORKSPACE,
    CREATOR,
    PLAN,
  );
  assertEquals(result.error, null);
  assertEquals(result.data.map((row) => row.id), ["card-1", "card-2"]);

  const expectedSelect = [
    "id",
    "scheduled_date",
    "status",
    "title",
    "why_today",
    "growth_job",
    "content_pillar",
    "shootability",
    "estimated_shoot_minutes",
    "energy_required",
    "language_mode",
    "scene_list",
    "script",
    "no_voiceover_version",
    "on_screen_text",
    "caption",
    "cta",
    "hashtags",
    "cover_text",
    "post_instructions",
    "brand_event_notes",
    "backup_story",
    "backup_caption_only",
    "risk_notes",
    "assumptions",
    "source_note",
    "storyboard_thumbnail_assets",
    "updated_at",
  ].join(",");
  assertEquals(dayGenerationCardSelect(), expectedSelect);

  const op = state.ops[0];
  assertEquals(op.table, "daily_cards");
  assertEquals(op.selectColumns, expectedSelect);
  assertEquals(op.filterOrder, [
    "workspace_id",
    "creator_id",
    "weekly_plan_id",
  ]);
  assertEquals(op.filters, {
    workspace_id: WORKSPACE,
    creator_id: CREATOR,
    weekly_plan_id: PLAN,
  });
  assertEquals(op.order, { column: "scheduled_date", ascending: true });
  assertEquals(op.terminal, undefined);
});

Deno.test("readDailyCardsForPlan surfaces raw select errors", async () => {
  const state: FakeState = {
    ops: [],
    rowsByTable: {},
    errorsByTable: {
      daily_cards: { message: "cards boom" },
    },
  };

  const result = await readDailyCardsForPlan(
    fakeAdmin(state) as never,
    WORKSPACE,
    CREATOR,
    PLAN,
  );
  assertEquals(result.data, []);
  assertEquals(result.error, { message: "cards boom" });
});

Deno.test("requestWeekWindowEnd preserves UTC date math", () => {
  assertEquals(requestWeekWindowEnd(WEEK_START, -7), "2026-06-01");
  assertEquals(requestWeekWindowEnd(WEEK_START, 21), "2026-06-29");
});

Deno.test("rowsOrEmpty keeps rows and treats errors as empty", () => {
  assertEquals(rowsOrEmpty({ rows: [{ id: "1" }] }), [{ id: "1" }]);
  assertEquals(rowsOrEmpty({ error: { message: "x" } }), []);
});

Deno.test("readContextTableRows requires workspace/creator and returns raw error", async () => {
  const state: FakeState = {
    ops: [],
    rowsByTable: {},
    errorsByTable: {
      ideas: { message: "ideas boom" },
    },
  };

  const result = await readContextTableRows(
    fakeAdmin(state) as never,
    "ideas",
    IDEA_BANK_CONTEXT_SELECT,
    WORKSPACE,
    CREATOR,
    (query) =>
      query.in("status", ["saved", "scheduled"]).order("updated_at", {
        ascending: false,
      }).limit(30),
  );
  assert("error" in result);
  assertEquals(result.error, { message: "ideas boom" });

  const op = state.ops[0];
  assertEquals(op.table, "ideas");
  assertEquals(op.selectColumns, IDEA_BANK_CONTEXT_SELECT);
  assertEquals(op.filterOrder, ["workspace_id", "creator_id", "in:status"]);
  assertEquals(op.inFilters, { status: ["saved", "scheduled"] });
  assertEquals(op.order, { column: "updated_at", ascending: false });
  assertEquals(op.limit, 30);
});

Deno.test("readGenerationContextRows issues exact parallel query contracts", async () => {
  const state: FakeState = {
    ops: [],
    rowsByTable: {
      creator_profiles: [{
        id: "profile-1",
        workspace_id: WORKSPACE,
        creator_id: CREATOR,
        status: "active",
        version: 2,
      }],
      source_references: [{
        id: "ref-1",
        workspace_id: WORKSPACE,
        creator_id: CREATOR,
        status: "confirmed",
        created_at: "2026-06-07T00:00:00Z",
      }],
      reference_extractions: [{
        id: "extract-1",
        workspace_id: WORKSPACE,
        creator_id: CREATOR,
        status: "confirmed",
        updated_at: "2026-06-07T00:00:00Z",
      }],
      archive_entries: [{
        id: "archive-1",
        workspace_id: WORKSPACE,
        creator_id: CREATOR,
        archive_date: "2026-06-01",
      }],
      ideas: [{
        id: "idea-1",
        workspace_id: WORKSPACE,
        creator_id: CREATOR,
        status: "saved",
        updated_at: "2026-06-07T00:00:00Z",
      }],
      patterns: [{
        id: "pattern-1",
        workspace_id: WORKSPACE,
        creator_id: CREATOR,
        status: "approved",
        updated_at: "2026-06-07T00:00:00Z",
      }],
      trends: [{
        id: "trend-1",
        workspace_id: WORKSPACE,
        creator_id: CREATOR,
        status: "used",
        updated_at: "2026-06-07T00:00:00Z",
      }],
      audio_options: [{
        id: "audio-1",
        workspace_id: WORKSPACE,
        creator_id: CREATOR,
        status: "verified_available",
        updated_at: "2026-06-07T00:00:00Z",
      }],
      brand_briefs: [{
        id: "brief-1",
        workspace_id: WORKSPACE,
        creator_id: CREATOR,
        status: "active",
        updated_at: "2026-06-07T00:00:00Z",
      }],
      key_moments: [{
        id: "moment-1",
        workspace_id: WORKSPACE,
        creator_id: CREATOR,
        status: "upcoming",
        moment_date: "2026-06-10",
      }],
    },
  };

  const context = await readGenerationContextRows(
    fakeAdmin(state) as never,
    WORKSPACE,
    CREATOR,
    WEEK_START,
  );

  assertEquals(context.profile_rows[0]?.id, "profile-1");
  assertEquals(context.confirmed_references[0]?.id, "ref-1");
  assertEquals(context.reference_extractions[0]?.id, "extract-1");
  assertEquals(context.recent_archive[0]?.id, "archive-1");
  assertEquals(context.idea_bank[0]?.id, "idea-1");
  assertEquals(context.patterns[0]?.id, "pattern-1");
  assertEquals(context.trends[0]?.id, "trend-1");
  assertEquals(context.audio_options[0]?.id, "audio-1");
  assertEquals(context.brand_briefs[0]?.id, "brief-1");
  assertEquals(context.key_moments[0]?.id, "moment-1");

  const byTable = Object.fromEntries(
    state.ops.map((op) => [op.table, op]),
  );

  assertEquals(
    byTable.creator_profiles.selectColumns,
    CREATOR_PROFILE_CONTEXT_SELECT,
  );
  assertEquals(byTable.creator_profiles.filters, {
    workspace_id: WORKSPACE,
    creator_id: CREATOR,
    status: "active",
  });
  assertEquals(byTable.creator_profiles.order, {
    column: "version",
    ascending: false,
  });
  assertEquals(byTable.creator_profiles.limit, 1);

  assertEquals(
    byTable.source_references.selectColumns,
    CONFIRMED_REFERENCES_CONTEXT_SELECT,
  );
  assertEquals(byTable.source_references.filters.status, "confirmed");
  assertEquals(byTable.source_references.order, {
    column: "created_at",
    ascending: false,
  });
  assertEquals(byTable.source_references.limit, 12);

  assertEquals(
    byTable.reference_extractions.selectColumns,
    REFERENCE_EXTRACTIONS_CONTEXT_SELECT,
  );
  assertEquals(byTable.reference_extractions.filters.status, "confirmed");
  assertEquals(byTable.reference_extractions.order, {
    column: "updated_at",
    ascending: false,
  });
  assertEquals(byTable.reference_extractions.limit, 20);

  assertEquals(
    byTable.archive_entries.selectColumns,
    RECENT_ARCHIVE_CONTEXT_SELECT,
  );
  assertEquals(byTable.archive_entries.order, {
    column: "archive_date",
    ascending: false,
  });
  assertEquals(byTable.archive_entries.limit, 20);

  assertEquals(byTable.ideas.selectColumns, IDEA_BANK_CONTEXT_SELECT);
  assertEquals(byTable.ideas.inFilters, {
    status: ["saved", "scheduled"],
  });
  assertEquals(byTable.ideas.limit, 30);

  assertEquals(byTable.patterns.selectColumns, PATTERNS_CONTEXT_SELECT);
  assertEquals(byTable.patterns.inFilters, {
    status: ["approved", "used"],
  });
  assertEquals(byTable.patterns.limit, 12);

  assertEquals(byTable.trends.selectColumns, TRENDS_CONTEXT_SELECT);
  assertEquals(byTable.trends.inFilters, {
    status: ["approved", "used"],
  });
  assertEquals(byTable.trends.limit, 12);

  assertEquals(
    byTable.audio_options.selectColumns,
    AUDIO_OPTIONS_CONTEXT_SELECT,
  );
  assertEquals(byTable.audio_options.inFilters, {
    status: ["verified_available", "used"],
  });
  assertEquals(byTable.audio_options.limit, 12);

  assertEquals(byTable.brand_briefs.selectColumns, BRAND_BRIEFS_CONTEXT_SELECT);
  assertEquals(byTable.brand_briefs.inFilters, {
    status: ["active", "scheduled", "awaiting_approval", "approved"],
  });
  assertEquals(byTable.brand_briefs.limit, 12);

  assertEquals(byTable.key_moments.selectColumns, KEY_MOMENTS_CONTEXT_SELECT);
  assertEquals(byTable.key_moments.inFilters, {
    status: ["upcoming", "active"],
  });
  assertEquals(byTable.key_moments.rangeFilters, {
    moment_date: {
      gte: "2026-06-01",
      lte: "2026-06-29",
    },
  });
  assertEquals(byTable.key_moments.order, {
    column: "moment_date",
    ascending: true,
  });
  assertEquals(byTable.key_moments.limit, 12);

  assertEquals(state.ops.length, 10);
});

Deno.test("readGenerationContextRows treats optional table failures as empty arrays", async () => {
  const state: FakeState = {
    ops: [],
    rowsByTable: {
      creator_profiles: [{
        id: "profile-1",
        workspace_id: WORKSPACE,
        creator_id: CREATOR,
        status: "active",
        version: 1,
      }],
      ideas: [{
        id: "idea-1",
        workspace_id: WORKSPACE,
        creator_id: CREATOR,
        status: "saved",
        updated_at: "2026-06-07T00:00:00Z",
      }],
    },
    errorsByTable: {
      patterns: { message: "patterns boom" },
      trends: { message: "trends boom" },
    },
  };

  const context = await readGenerationContextRows(
    fakeAdmin(state) as never,
    WORKSPACE,
    CREATOR,
    WEEK_START,
  );

  assertEquals(context.profile_rows[0]?.id, "profile-1");
  assertEquals(context.idea_bank[0]?.id, "idea-1");
  assertEquals(context.patterns, []);
  assertEquals(context.trends, []);
  assertEquals(context.confirmed_references, []);
});
