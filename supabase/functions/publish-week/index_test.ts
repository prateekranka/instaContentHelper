import {
  handlePublishWeekRequest,
  normalizeDraftCard,
  replaceExistingPublishedWeek,
} from "./index.ts";

const workspaceID = "11111111-1111-4111-8111-111111111111";
const authenticatedMemberID = "22222222-2222-4222-8222-222222222222";
const spoofedMemberID = "99999999-9999-4999-8999-999999999999";
const creatorID = "33333333-3333-4333-8333-333333333333";
const weeklyPlanID = "77777777-7777-4777-8777-777777777771";

Deno.test("draft publish payload preserves rich generated daily card fields", () => {
  const normalized = normalizeDraftCard({
    id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
    scheduled_date: "2026-06-08",
    title: "Generated Monday reset",
    why_today: "Start with a calm routine.",
    growth_job: "Build consistency.",
    content_pillar: "lifestyle",
    shootability: "easy",
    estimated_shoot_minutes: 11,
    energy_required: "medium",
    language_mode: "English",
    scene_list: [
      {
        number: 1,
        title: "Shoes",
        duration: "3 sec",
        symbol: "shoeprints.fill",
      },
    ],
    script: "One calm line.",
    no_voiceover_version: "Three quiet clips.",
    on_screen_text: ["Simple today"],
    caption: "Keeping it simple.",
    cta: "Save this.",
    hashtags: ["routine"],
    cover_text: "Monday reset",
    post_instructions: "Use calm audio.",
    brand_event_notes: "No brand.",
    backup_story: "One story frame.",
    backup_caption_only: "Caption-only backup.",
    creator_fit_score: 89,
    risk_notes: ["Avoid hype."],
    assumptions: ["Low energy day."],
    source_note: "Confirmed reference.",
    storyboard_thumbnail_assets: [
      {
        row_index: 0,
        public_url:
          "https://example.supabase.co/storage/v1/object/public/storyboard-thumbnails/thumb.jpg",
      },
    ],
  });

  assert(normalized !== null);
  assertEquals(normalized.title, "Generated Monday reset");
  assertEquals(normalized.script, "One calm line.");
  assertEquals(normalized.caption, "Keeping it simple.");
  assertEquals(
    (normalized.backup_story as Record<string, string>).line,
    "One story frame.",
  );
  assertEquals(
    (normalized.backup_caption_only as Record<string, string>).line,
    "Caption-only backup.",
  );
  assertEquals(
    (normalized.post_instructions as Record<string, string>).line,
    "Use calm audio.",
  );
  assertEquals(normalized.creator_fit_score, 89);
  assertEquals(
    (normalized.storyboard_thumbnail_assets as unknown[]).length,
    1,
  );
});

Deno.test("draft publish payload rejects missing scheduled date or title", () => {
  assertEquals(normalizeDraftCard({ title: "Missing date" }), null);
  assertEquals(
    normalizeDraftCard({ scheduled_date: "2026-06-08", title: " " }),
    null,
  );
});

Deno.test("draft publish payload includes review_state with build-19 fallback to ready", () => {
  const withReviewState = normalizeDraftCard({
    id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
    scheduled_date: "2026-06-08",
    title: "Reviewed Monday",
    review_state: "backup",
  });
  assert(withReviewState !== null);
  assertEquals(withReviewState.review_state, "backup");

  const withoutReviewState = normalizeDraftCard({
    id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2",
    scheduled_date: "2026-06-09",
    title: "Default review",
  });
  assert(withoutReviewState !== null);
  assertEquals(
    withoutReviewState.review_state,
    "ready",
    "missing review_state defaults to ready for build-19 compat",
  );

  const invalidReviewState = normalizeDraftCard({
    id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3",
    scheduled_date: "2026-06-10",
    title: "Invalid review",
    review_state: "unknown",
  });
  assert(invalidReviewState !== null);
  assertEquals(
    invalidReviewState.review_state,
    "ready",
    "invalid review_state defaults to ready",
  );
});

Deno.test("published week replacement archives old published daily cards", async () => {
  const updates: UpdateCapture[] = [];
  const admin = {
    from(table: string) {
      return new FakePublishQuery(table, updates);
    },
    rpc(
      _fn: string,
      _args?: Record<string, unknown>,
    ): Promise<{ data: unknown; error: null }> {
      return Promise.resolve({ data: null, error: null });
    },
  };

  const response = await replaceExistingPublishedWeek(
    admin,
    "11111111-1111-4111-8111-111111111111",
    "33333333-3333-4333-8333-333333333333",
    "2026-06-08",
    "new-plan-id",
  );

  assertEquals(response, null);
  const planUpdate = updates.find((update) => update.table === "weekly_plans");
  const cardUpdate = updates.find((update) => update.table === "daily_cards");

  assert(planUpdate !== undefined);
  assertEquals(planUpdate.values.status, "replaced");
  assertEquals(planUpdate.values.is_soft_locked, false);
  assertEquals(planUpdate.values.replaced_by_weekly_plan_id, "new-plan-id");

  assert(cardUpdate !== undefined);
  assertEquals(cardUpdate.values.status, "archived");
  assertEquals(cardUpdate.filters.weekly_plan_id, "old-plan-id");
  assert(
    Array.isArray(cardUpdate.filters.status) &&
      cardUpdate.filters.status.includes("published") &&
      cardUpdate.filters.status.includes("saved_for_tomorrow"),
  );
});

Deno.test("legacy caller-supplied publish records authenticated member id", async () => {
  const captures: HandlerCapture[] = [];
  const response = await callPublishHandler(
    {
      creator_id: creatorID,
      member_id: spoofedMemberID,
      weekly_plan_id: weeklyPlanID,
      week_start_date: "2026-06-08",
      days: legacySevenDays("2026-06-08"),
    },
    { captures },
  );

  assertEquals(response.status, 200);
  const planInsert = captures.find((capture) =>
    capture.table === "weekly_plans" && capture.operation === "insert"
  );
  assert(planInsert !== undefined);
  assertEquals(
    planInsert.values.created_by_member_id,
    authenticatedMemberID,
  );
});

Deno.test("idempotent existing published draft publish returns original published timestamp", async () => {
  const publishedAt = "2026-06-06T08:00:00.000Z";
  const response = await callPublishHandler(
    {
      creator_id: creatorID,
      weekly_plan_id: weeklyPlanID,
    },
    {
      existingDraftPlan: {
        id: weeklyPlanID,
        workspace_id: workspaceID,
        creator_id: creatorID,
        week_start_date: "2026-06-08",
        status: "published",
        is_soft_locked: true,
        published_at: publishedAt,
      },
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.weekly_plan_id, weeklyPlanID);
  assertEquals(body.is_soft_locked, true);
  assertEquals(body.published_at, publishedAt);
});

Deno.test("publishing an existing draft calls publish_week_atomic RPC with full payload", async () => {
  let rpcCalled = false;
  let rpcPayload: Record<string, unknown> | null = null;

  const response = await handlePublishWeekRequest(
    new Request("http://localhost/publish-week", {
      method: "POST",
      headers: { "x-mco-device-token": "device-token" },
      body: JSON.stringify({
        creator_id: creatorID,
        weekly_plan_id: weeklyPlanID,
        draft_daily_cards: reviewedDraftCards("2026-06-08"),
      }),
    }),
    {
      env: {
        get(name: string) {
          return {
            SUPABASE_URL: "http://127.0.0.1:54321",
            SUPABASE_SERVICE_ROLE_KEY: "local-service-role",
          }[name];
        },
      },
      createAdminClient: () => ({
        from(table: string) {
          return new FakePublishHandlerQuery(table, {
            existingDraftPlan: {
              id: weeklyPlanID,
              workspace_id: workspaceID,
              creator_id: creatorID,
              week_start_date: "2026-06-08",
              status: "draft",
              is_soft_locked: false,
              published_at: null,
            },
            existingDraftCards: existingDraftCardIdentities("2026-06-08"),
          });
        },
        rpc(
          fn: string,
          args: Record<string, unknown>,
        ): Promise<{ data: unknown; error: null }> {
          if (fn === "publish_week_atomic") {
            rpcCalled = true;
            rpcPayload = args.payload as Record<string, unknown>;
            return Promise.resolve({
              data: {
                weekly_plan_id: weeklyPlanID,
                daily_card_count: 7,
                is_soft_locked: true,
                published_at: new Date().toISOString(),
              },
              error: null,
            });
          }
          return Promise.resolve({ data: null, error: null });
        },
      }),
    },
  );

  assertEquals(response.status, 200);
  assert(rpcCalled, "expected publish_week_atomic RPC to be called");

  const payload = rpcPayload!;
  assertEquals(payload.workspace_id, workspaceID);
  assertEquals(payload.creator_id, creatorID);
  assertEquals(payload.weekly_plan_id, weeklyPlanID);
  assert(
    Array.isArray(payload.draft_daily_cards),
    "draft_daily_cards should be an array",
  );
  assertEquals((payload.draft_daily_cards as unknown[]).length, 7);
  const firstDraftCard =
    (payload.draft_daily_cards as Record<string, unknown>[])[0];
  assertEquals(
    (firstDraftCard.storyboard_thumbnail_assets as unknown[]).length,
    1,
  );

  const body = await response.json();
  assertEquals(body.weekly_plan_id, weeklyPlanID);
  assertEquals(body.daily_card_count, 7);
  assertEquals(body.is_soft_locked, true);
});

Deno.test("publish_week_atomic RPC errors are mapped to stable error responses", async () => {
  const errorCases = [
    { rpcError: "weekly_plan_not_found", expectedStatus: 404 },
    { rpcError: "existing_published_week_locked", expectedStatus: 409 },
    { rpcError: "invalid_day_payload", expectedStatus: 400 },
    { rpcError: "cross_workspace_forbidden", expectedStatus: 403 },
  ];

  for (const { rpcError, expectedStatus } of errorCases) {
    const response = await handlePublishWeekRequest(
      new Request("http://localhost/publish-week", {
        method: "POST",
        headers: { "x-mco-device-token": "device-token" },
        body: JSON.stringify({
          creator_id: creatorID,
          weekly_plan_id: weeklyPlanID,
          draft_daily_cards: reviewedDraftCards("2026-06-08"),
        }),
      }),
      {
        env: {
          get(name: string) {
            return {
              SUPABASE_URL: "http://127.0.0.1:54321",
              SUPABASE_SERVICE_ROLE_KEY: "local-service-role",
            }[name];
          },
        },
        createAdminClient: () => ({
          from(table: string) {
            return new FakePublishHandlerQuery(table, {
              existingDraftPlan: {
                id: weeklyPlanID,
                workspace_id: workspaceID,
                creator_id: creatorID,
                week_start_date: "2026-06-08",
                status: "draft",
                is_soft_locked: false,
                published_at: null,
              },
              existingDraftCards: existingDraftCardIdentities("2026-06-08"),
            });
          },
          rpc(): Promise<{ data: unknown; error: null }> {
            return Promise.resolve({
              data: { error: rpcError, status: expectedStatus },
              error: null,
            });
          },
        }),
      },
    );

    assertEquals(
      response.status,
      expectedStatus,
      `expected status ${expectedStatus} for ${rpcError}`,
    );
    const body = await response.json();
    assertEquals(body.error, rpcError, `expected error "${rpcError}"`);
  }
});

type UpdateCapture = {
  table: string;
  values: Record<string, unknown>;
  filters: Record<string, unknown>;
};

type HandlerCapture = {
  table: string;
  operation: string;
  values: Record<string, unknown>;
  filters: Record<string, unknown>;
};

type HandlerState = {
  captures?: HandlerCapture[];
  existingDraftPlan?: Record<string, unknown> | null;
  existingDraftCards?: Record<string, unknown>[];
};

async function callPublishHandler(
  body: Record<string, unknown>,
  state: HandlerState = {},
): Promise<Response> {
  return await handlePublishWeekRequest(
    new Request("http://localhost/publish-week", {
      method: "POST",
      headers: { "x-mco-device-token": "device-token" },
      body: JSON.stringify(body),
    }),
    {
      env: {
        get(name: string) {
          return {
            SUPABASE_URL: "http://127.0.0.1:54321",
            SUPABASE_SERVICE_ROLE_KEY: "local-service-role",
          }[name];
        },
      },
      createAdminClient: () => ({
        from(table: string) {
          return new FakePublishHandlerQuery(table, state);
        },
        rpc(
          _fn: string,
          _args?: Record<string, unknown>,
        ): Promise<{ data: unknown; error: null }> {
          if (_fn === "publish_week_atomic") {
            return Promise.resolve({
              data: {
                weekly_plan_id: weeklyPlanID,
                daily_card_count: 7,
                is_soft_locked: true,
                published_at: new Date().toISOString(),
              },
              error: null,
            });
          }
          return Promise.resolve({ data: null, error: null });
        },
      }),
    },
  );
}

function legacySevenDays(weekStartDate: string): Record<string, unknown>[] {
  const [year, month, day] = weekStartDate.split("-").map(Number);
  const start = new Date(Date.UTC(year, month - 1, day));
  return Array.from({ length: 7 }, (_, index) => {
    const date = new Date(start);
    date.setUTCDate(start.getUTCDate() + index);
    return {
      scheduled_date: date.toISOString().slice(0, 10),
      title: `Day ${index + 1}`,
      why_today: "Prepared for this day.",
      source: "routine",
      state: "planned",
      shootability: "easy",
      estimated_shoot_minutes: 12,
      scene_list: [],
    };
  });
}

function reviewedDraftCards(
  weekStartDate: string,
): Record<string, unknown>[] {
  const [year, month, day] = weekStartDate.split("-").map(Number);
  const start = new Date(Date.UTC(year, month - 1, day));
  return Array.from({ length: 7 }, (_, index) => {
    const date = new Date(start);
    date.setUTCDate(start.getUTCDate() + index);
    return {
      id: `reviewed-card-${index + 1}`,
      scheduled_date: date.toISOString().slice(0, 10),
      title: index === 0
        ? "Edited Monday concept"
        : `Reviewed day ${index + 1}`,
      why_today: "Prepared for this day.",
      growth_job: "Build consistency.",
      content_pillar: "lifestyle",
      shootability: "easy",
      estimated_shoot_minutes: 12,
      energy_required: "medium",
      language_mode: "English",
      scene_list: [],
      script: index === 0 ? "Edited script." : "Script.",
      no_voiceover_version: "No VO.",
      on_screen_text: ["Edited text"],
      caption: index === 0
        ? "Edited caption that should survive publish."
        : "Caption.",
      cta: "Save this.",
      hashtags: ["lifestylecreator"],
      cover_text: "Edited cover",
      post_instructions: index === 0
        ? "Use the edited publish notes."
        : "Use notes.",
      backup_story: "Edited backup story.",
      backup_caption_only: "Edited caption-only backup.",
      creator_fit_score: 92,
      risk_notes: [],
      assumptions: [],
      source_note: "Reviewed in app.",
      storyboard_thumbnail_assets: index === 0
        ? [
          {
            row_index: 0,
            public_url:
              "https://example.supabase.co/storage/v1/object/public/storyboard-thumbnails/thumb.jpg",
          },
        ]
        : [],
    };
  });
}

function existingDraftCardIdentities(
  weekStartDate: string,
): Record<string, unknown>[] {
  const [year, month, day] = weekStartDate.split("-").map(Number);
  const start = new Date(Date.UTC(year, month - 1, day));
  return Array.from({ length: 7 }, (_, index) => {
    const date = new Date(start);
    date.setUTCDate(start.getUTCDate() + index);
    return {
      id: `existing-card-${index + 1}`,
      scheduled_date: date.toISOString().slice(0, 10),
    };
  });
}

class FakePublishHandlerQuery {
  private operation: "select" | "update" | "insert" | "upsert" = "select";
  private filters: Record<string, unknown> = {};
  private values: Record<string, unknown> | Record<string, unknown>[] = {};

  constructor(
    private readonly table: string,
    private readonly state: HandlerState,
  ) {}

  select(_columns?: string): FakePublishHandlerQuery {
    return this;
  }

  update(values: Record<string, unknown>): FakePublishHandlerQuery {
    this.operation = "update";
    this.values = values;
    return this;
  }

  insert(values: Record<string, unknown>): FakePublishHandlerQuery {
    this.operation = "insert";
    this.values = values;
    return this;
  }

  upsert(values: Record<string, unknown>[]): FakePublishHandlerQuery {
    this.operation = "upsert";
    this.values = values;
    return this;
  }

  eq(column: string, value: unknown): FakePublishHandlerQuery {
    this.filters[column] = value;
    return this;
  }

  is(column: string, value: unknown): FakePublishHandlerQuery {
    this.filters[column] = value;
    return this;
  }

  in(column: string, value: unknown): FakePublishHandlerQuery {
    this.filters[column] = value;
    return this;
  }

  maybeSingle(): Promise<{ data: unknown; error: null }> {
    const result = this.resolve();
    return Promise.resolve({
      data: Array.isArray(result.data) ? result.data[0] ?? null : result.data,
      error: null,
    });
  }

  single(): Promise<{ data: unknown; error: null }> {
    const result = this.resolve();
    return Promise.resolve({
      data: Array.isArray(result.data) ? result.data[0] ?? null : result.data,
      error: null,
    });
  }

  then<TResult1 = { data: unknown; error: null }, TResult2 = never>(
    onfulfilled?:
      | ((
        value: { data: unknown; error: null },
      ) => TResult1 | PromiseLike<TResult1>)
      | null,
    onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
  ): Promise<TResult1 | TResult2> {
    return Promise.resolve(this.resolve()).then(onfulfilled, onrejected);
  }

  private resolve(): { data: unknown; error: null } {
    if (this.operation !== "select") {
      this.capture();
      if (Array.isArray(this.values)) {
        return {
          data: this.values.map((row, index) => ({
            id: row.id ?? `written-${index}`,
          })),
          error: null,
        };
      }
      return {
        data: {
          id: (this.values as Record<string, unknown>).id ?? "written-id",
        },
        error: null,
      };
    }

    switch (this.table) {
      case "device_installations":
        return {
          data: {
            id: "device-installation-id",
            workspace_id: workspaceID,
            member_id: authenticatedMemberID,
            revoked_at: null,
          },
          error: null,
        };
      case "members":
        return {
          data: {
            id: authenticatedMemberID,
            workspace_id: workspaceID,
            role: "owner",
            status: "active",
          },
          error: null,
        };
      case "creators":
        return { data: { id: creatorID }, error: null };
      case "weekly_plans":
        if (this.filters.status === "published") {
          return { data: null, error: null };
        }
        return { data: this.state.existingDraftPlan ?? null, error: null };
      case "daily_cards":
        return {
          data: this.state.existingDraftCards ?? [{ id: "daily-card-id" }],
          error: null,
        };
      default:
        return { data: null, error: null };
    }
  }

  private capture(): void {
    this.state.captures?.push({
      table: this.table,
      operation: this.operation,
      values: Array.isArray(this.values) ? { rows: this.values } : this.values,
      filters: this.filters,
    });
  }
}

class FakePublishQuery {
  private operation: "select" | "update" = "select";
  private filters: Record<string, unknown> = {};
  private values: Record<string, unknown> = {};

  constructor(
    private readonly table: string,
    private readonly updates: UpdateCapture[],
  ) {}

  select(_columns?: string): FakePublishQuery {
    this.operation = "select";
    return this;
  }

  update(values: Record<string, unknown>): FakePublishQuery {
    this.operation = "update";
    this.values = values;
    return this;
  }

  eq(column: string, value: unknown): FakePublishQuery {
    this.filters[column] = value;
    return this;
  }

  in(column: string, value: unknown): FakePublishQuery {
    this.filters[column] = value;
    return this;
  }

  maybeSingle(): Promise<{ data: unknown; error: null }> {
    return Promise.resolve({
      data: this.table === "weekly_plans" ? { id: "old-plan-id" } : null,
      error: null,
    });
  }

  then<TResult1 = { data: unknown; error: null }, TResult2 = never>(
    onfulfilled?:
      | ((
        value: { data: unknown; error: null },
      ) => TResult1 | PromiseLike<TResult1>)
      | null,
    onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
  ): Promise<TResult1 | TResult2> {
    if (this.operation === "update") {
      this.updates.push({
        table: this.table,
        values: this.values,
        filters: this.filters,
      });
    }
    return Promise.resolve({ data: [{ id: "updated" }], error: null }).then(
      onfulfilled,
      onrejected,
    );
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
  if (!Object.is(actual, expected)) {
    throw new Error(
      message ??
        `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
