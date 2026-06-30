import { readWeekly } from "./index.ts";

const workspaceID = "11111111-1111-4111-8111-111111111111";
const creatorID = "33333333-3333-4333-8333-333333333333";
const session = {
  workspaceID,
  role: "owner",
  deviceInstallationID: "dev-inst-id",
  memberID: "member-id",
};

Deno.test("readWeekly returns published_weekly_plan when both published and draft rows exist", async () => {
  const publishedPlanID = "pub-plan-id";
  const draftPlanID = "draft-plan-id";

  const publishedPlan = {
    id: publishedPlanID,
    workspace_id: workspaceID,
    creator_id: creatorID,
    week_start_date: "2026-06-01",
    status: "published",
    strategy_summary: "Published strategy",
    warnings: [],
    assumptions: [],
    is_soft_locked: true,
    published_at: "2026-06-01T08:00:00Z",
    weekly_setup_id: "pub-setup-id",
  };

  const draftPlan = {
    id: draftPlanID,
    workspace_id: workspaceID,
    creator_id: creatorID,
    week_start_date: "2026-06-08",
    status: "draft",
    strategy_summary: "Draft strategy",
    warnings: [],
    assumptions: [],
    is_soft_locked: false,
    published_at: null,
    weekly_setup_id: "draft-setup-id",
  };

  const publishedCards = [
    {
      id: "pub-card-1",
      workspace_id: workspaceID,
      creator_id: creatorID,
      weekly_plan_id: publishedPlanID,
      scheduled_date: "2026-06-01",
    },
    {
      id: "pub-card-2",
      workspace_id: workspaceID,
      creator_id: creatorID,
      weekly_plan_id: publishedPlanID,
      scheduled_date: "2026-06-02",
    },
  ];

  const draftCards = [
    {
      id: "draft-card-1",
      workspace_id: workspaceID,
      creator_id: creatorID,
      weekly_plan_id: draftPlanID,
      scheduled_date: "2026-06-08",
    },
  ];

  const admin = new FakeReadAdmin({
    planRows: [publishedPlan, draftPlan],
    cardsByPlanID: {
      [publishedPlanID]: publishedCards,
      [draftPlanID]: draftCards,
    },
    setupsByID: {
      "pub-setup-id": { id: "pub-setup-id", notes: "published setup" },
      "draft-setup-id": { id: "draft-setup-id", notes: "draft setup" },
    },
  });

  const response = await readWeekly(admin, session, creatorID);

  const body = await response.json();
  assertEquals(body.published_weekly_plan?.id, publishedPlanID);
  assertEquals(body.published_weekly_plan?.status, "published");
  assertEquals(body.published_daily_cards.length, 2);
  assertEquals(body.published_weekly_setup?.id, "pub-setup-id");

  assertEquals(body.weekly_plan?.id, draftPlanID);
  assertEquals(body.weekly_plan?.status, "draft");
  assertEquals(body.daily_cards.length, 1);
  assertEquals(body.weekly_setup?.id, "draft-setup-id");
});

Deno.test("readWeekly returns only published_weekly_plan when no draft exists", async () => {
  const publishedPlanID = "pub-plan-id";

  const publishedPlan = {
    id: publishedPlanID,
    workspace_id: workspaceID,
    creator_id: creatorID,
    week_start_date: "2026-06-01",
    status: "published",
    strategy_summary: "Only published",
    warnings: [],
    assumptions: [],
    is_soft_locked: true,
    published_at: "2026-06-01T08:00:00Z",
    weekly_setup_id: "pub-setup-id",
  };

  const publishedCards = [
    {
      id: "pub-card-1",
      workspace_id: workspaceID,
      creator_id: creatorID,
      weekly_plan_id: publishedPlanID,
      scheduled_date: "2026-06-01",
    },
  ];

  const admin = new FakeReadAdmin({
    planRows: [publishedPlan],
    cardsByPlanID: {
      [publishedPlanID]: publishedCards,
    },
    setupsByID: {
      "pub-setup-id": { id: "pub-setup-id", notes: "published setup" },
    },
  });

  const response = await readWeekly(admin, session, creatorID);

  const body = await response.json();
  assertEquals(body.published_weekly_plan?.id, publishedPlanID);
  assertEquals(body.published_weekly_plan?.status, "published");
  assertEquals(body.published_daily_cards.length, 1);
  assertEquals(body.published_weekly_setup?.id, "pub-setup-id");
  assertEquals(body.weekly_plan, null);
  assertEquals(body.daily_cards.length, 0);
});

Deno.test("readWeekly returns only working weekly_plan when no published plan exists", async () => {
  const draftPlanID = "draft-plan-id";

  const draftPlan = {
    id: draftPlanID,
    workspace_id: workspaceID,
    creator_id: creatorID,
    week_start_date: "2026-06-08",
    status: "draft",
    strategy_summary: "Draft only",
    warnings: [],
    assumptions: [],
    is_soft_locked: false,
    published_at: null,
    weekly_setup_id: "draft-setup-id",
  };

  const draftCards = [
    {
      id: "draft-card-1",
      workspace_id: workspaceID,
      creator_id: creatorID,
      weekly_plan_id: draftPlanID,
      scheduled_date: "2026-06-08",
    },
  ];

  const admin = new FakeReadAdmin({
    planRows: [draftPlan],
    cardsByPlanID: {
      [draftPlanID]: draftCards,
    },
    setupsByID: {
      "draft-setup-id": { id: "draft-setup-id", notes: "draft setup" },
    },
  });

  const response = await readWeekly(admin, session, creatorID);

  const body = await response.json();
  assertEquals(body.published_weekly_plan, null);
  assertEquals(body.published_daily_cards.length, 0);
  assertEquals(body.published_weekly_setup, null);
  assertEquals(body.weekly_plan?.id, draftPlanID);
  assertEquals(body.weekly_plan?.status, "draft");
  assertEquals(body.daily_cards.length, 1);
  assertEquals(body.weekly_setup?.id, "draft-setup-id");
});

Deno.test("readWeekly returns null for both when no plans exist", async () => {
  const admin = new FakeReadAdmin({
    planRows: [],
    cardsByPlanID: {},
  });

  const response = await readWeekly(admin, session, creatorID);

  const body = await response.json();
  assertEquals(body.weekly_plan, null);
  assertEquals(body.daily_cards, []);
  assertEquals(body.published_weekly_plan, null);
  assertEquals(body.published_daily_cards, []);
  assertEquals(body.published_weekly_setup, null);
  assertEquals(body.idea_bank, []);
});

type FakeAdminConfig = {
  planRows: Record<string, unknown>[];
  cardsByPlanID: Record<string, Record<string, unknown>[]>;
  setupsByID?: Record<string, Record<string, unknown>>;
};

class FakeReadAdmin {
  constructor(private config: FakeAdminConfig) {}

  from(table: string): FakeReadQuery {
    return new FakeReadQuery(table, this.config);
  }
}

class FakeReadQuery {
  private _select = "*";
  private _filters: Record<string, unknown> = {};
  private _orderColumn = "";
  private _orderAsc = false;
  private _limit = 100;
  private _asSingle = false;

  constructor(
    private table: string,
    private config: FakeAdminConfig,
  ) {}

  select(columns: string): FakeReadQuery {
    this._select = columns;
    return this;
  }

  eq(column: string, value: unknown): FakeReadQuery {
    this._filters[column] = value;
    return this;
  }

  in(column: string, values: unknown): FakeReadQuery {
    this._filters[column] = values;
    return this;
  }

  order(column: string, options: { ascending: boolean }): FakeReadQuery {
    this._orderColumn = column;
    this._orderAsc = options.ascending;
    return this;
  }

  limit(n: number): FakeReadQuery {
    this._limit = n;
    return this;
  }

  maybeSingle(): Promise<{ data: unknown; error: null }> {
    this._asSingle = true;
    return this.execute();
  }

  then<TResult1 = { data: unknown; error: null }, TResult2 = never>(
    onfulfilled?:
      | ((
        value: { data: unknown; error: null },
      ) => TResult1 | PromiseLike<TResult1>)
      | null,
    onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
  ): Promise<TResult1 | TResult2> {
    return this.execute().then(onfulfilled, onrejected);
  }

  private async execute(): Promise<{ data: unknown; error: null }> {
    let rows: Record<string, unknown>[] = [];

    if (this.table === "weekly_plans") {
      rows = this.config.planRows.filter((row) => {
        if (
          this._filters.workspace_id !== undefined &&
          row.workspace_id !== this._filters.workspace_id
        ) return false;
        if (
          this._filters.creator_id !== undefined &&
          row.creator_id !== this._filters.creator_id
        ) return false;
        if (this._filters.status !== undefined) {
          const statuses = this._filters.status as string[];
          if (!statuses.includes(row.status as string)) return false;
        }
        return true;
      });
    } else if (this.table === "daily_cards") {
      const planID = this._filters.weekly_plan_id as string;
      rows = (this.config.cardsByPlanID[planID] ?? []).filter((row) => {
        if (
          this._filters.workspace_id !== undefined &&
          row.workspace_id !== this._filters.workspace_id
        ) return false;
        if (
          this._filters.creator_id !== undefined &&
          row.creator_id !== this._filters.creator_id
        ) return false;
        return true;
      });
    } else if (this.table === "weekly_setups") {
      const setupID = this._filters.id as string | undefined;
      rows = setupID && this.config.setupsByID?.[setupID]
        ? [this.config.setupsByID[setupID]]
        : [];
    }
    // ideas table (readIdeaBank) and any other unhandled table → empty.
    // All tables default to an empty result so readWeekly doesn't crash.

    if (this._asSingle) {
      return { data: rows[0] ?? null, error: null };
    }
    return { data: rows.slice(0, this._limit), error: null };
  }
}

function assert(
  condition: unknown,
  message = "Assertion failed",
): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  if (
    actual !== expected && JSON.stringify(actual) !== JSON.stringify(expected)
  ) {
    throw new Error(
      message ??
        `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
