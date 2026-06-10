import { handleGenerateWeekRequest } from "./index.ts";
import { makeMockGeneratedWeek } from "./generation.ts";

const workspaceID = "11111111-1111-4111-8111-111111111111";
const memberID = "22222222-2222-4222-8222-222222222222";
const creatorID = "33333333-3333-4333-8333-333333333333";
const setupID = "44444444-4444-4444-8444-444444444444";
const generationRunID = "55555555-5555-4555-8555-555555555555";
const weeklyPlanID = "66666666-6666-4666-8666-666666666666";
const dailyCardIDs = Array.from(
  { length: 7 },
  (_, index) => `77777777-7777-4777-8777-77777777777${index}`,
);

Deno.test("generate-week rejects creator role", async () => {
  const response = await callHandler(
    {
      creator_id: creatorID,
      week_start_date: "2026-06-08",
    },
    { memberRole: "creator" },
  );

  assertEquals(response.status, 403);
  assertEquals(await errorCode(response), "role_not_allowed");
});

Deno.test("generate-week rejects cross-workspace creator ids", async () => {
  const response = await callHandler(
    {
      creator_id: creatorID,
      week_start_date: "2026-06-08",
    },
    { creatorExists: false, openAIKey: "test-key" },
  );

  assertEquals(response.status, 404);
  assertEquals(await errorCode(response), "creator_not_found");
});

Deno.test("generate-week returns missing_openai_api_key when real AI key is absent", async () => {
  const response = await callHandler(
    {
      creator_id: creatorID,
      week_start_date: "2026-06-08",
    },
    {},
  );

  assertEquals(response.status, 500);
  assertEquals(await errorCode(response), "missing_openai_api_key");
});

Deno.test("generate-week ignores request mock unless mock requests are explicitly allowed", async () => {
  const response = await callHandler(
    {
      creator_id: creatorID,
      week_start_date: "2026-06-08",
      mock: true,
    },
    {},
  );

  assertEquals(response.status, 500);
  assertEquals(await errorCode(response), "missing_openai_api_key");
});

Deno.test("generate-week rejects missing weekly setup id in workspace", async () => {
  const response = await callHandler(
    {
      creator_id: creatorID,
      week_start_date: "2026-06-08",
      weekly_setup_id: setupID,
    },
    { openAIKey: "test-key", setupExists: false },
  );

  assertEquals(response.status, 404);
  assertEquals(await errorCode(response), "weekly_setup_not_found");
});

Deno.test("generate-week published week lock prevents accidental overwrite", async () => {
  const response = await callHandler(
    {
      creator_id: creatorID,
      week_start_date: "2026-06-08",
    },
    { openAIKey: "test-key", publishedWeekExists: true },
  );

  assertEquals(response.status, 409);
  assertEquals(await errorCode(response), "existing_published_week_locked");
});

Deno.test("generate-week passes enriched context into the AI client", async () => {
  let capturedInput: Record<string, unknown> | undefined;
  const response = await handleGenerateWeekRequest(
    new Request("http://localhost/generate-week", {
      method: "POST",
      headers: { "x-mco-device-token": "device-token" },
      body: JSON.stringify({
        creator_id: creatorID,
        week_start_date: "2026-06-08",
      }),
    }),
    {
      env: fakeEnv("test-key"),
      createAdminClient: () => fakeAdmin({}),
      generateAI: async (input) => {
        capturedInput = input as unknown as Record<string, unknown>;
        return makeMockGeneratedWeek(input);
      },
    },
  );

  assertEquals(response.status, 200);
  assertArrayContainsObject(
    capturedInput?.reference_extractions,
    "extracted_payload",
    { summary: "hook-led sock transition" },
  );
  assertArrayContainsObject(
    capturedInput?.brand_briefs,
    "brand_name",
    "Brand hydration reminder",
  );
  assertArrayContainsObject(
    capturedInput?.key_moments,
    "name",
    "Sunday 10K",
  );
});

Deno.test("generate-week orders DeepSeek before OpenAI when both provider keys exist", async () => {
  let providerOrder = "";
  const response = await handleGenerateWeekRequest(
    new Request("http://localhost/generate-week", {
      method: "POST",
      headers: { "x-mco-device-token": "device-token" },
      body: JSON.stringify({
        creator_id: creatorID,
        week_start_date: "2026-06-08",
      }),
    }),
    {
      env: fakeEnv("openai-key", false, "deepseek-key"),
      createAdminClient: () => fakeAdmin({}),
      generateAI: async (input, providers) => {
        providerOrder = providers.map((provider) => provider.provider).join(
          ",",
        );
        return makeMockGeneratedWeek(input);
      },
    },
  );

  assertEquals(response.status, 200);
  assertEquals(providerOrder, "deepseek,openai");
});

Deno.test("generate-week async mode returns running and schedules background generation", async () => {
  let scheduled: Promise<void> | undefined;
  const response = await handleGenerateWeekRequest(
    new Request("http://localhost/generate-week", {
      method: "POST",
      headers: { "x-mco-device-token": "device-token" },
      body: JSON.stringify({
        creator_id: creatorID,
        week_start_date: "2026-06-08",
        response_mode: "async",
      }),
    }),
    {
      env: fakeEnv("test-key"),
      createAdminClient: () => fakeAdmin({}),
      generateAI: async (input) => makeMockGeneratedWeek(input),
      runInBackground: (promise) => {
        scheduled = promise;
      },
    },
  );

  assertEquals(response.status, 202);
  const body = await response.json();
  assertEquals(body.generation_id, generationRunID);
  assertEquals(body.status, "running");

  if (!scheduled) {
    throw new Error("Expected background generation to be scheduled.");
  }
  await scheduled;
});

Deno.test("generate-week status returns completed draft snapshot", async () => {
  const generated = makeMockGeneratedWeek({
    creator_id: creatorID,
    week_start_date: "2026-06-08",
    creator_profile: null,
    weekly_setup: null,
    confirmed_references: [],
    reference_extractions: [],
    recent_archive: [],
    idea_bank: [],
    patterns: [],
    trends: [],
    audio_options: [],
    brand_briefs: [],
    key_moments: [],
  });
  const snapshot = {
    generation_id: generationRunID,
    weekly_plan_id: weeklyPlanID,
    status: "draft",
    strategy_summary: generated.strategy_summary,
    warnings: generated.warnings,
    assumptions: generated.assumptions,
    daily_cards: generated.daily_cards,
    idea_bank: [],
    source_summary: generated.source_summary,
    generated_at: "2026-06-08T08:00:00.000Z",
  };

  const response = await callHandler(
    {
      action: "status",
      generation_id: generationRunID,
      creator_id: creatorID,
    },
    {
      generationRun: {
        id: generationRunID,
        workspace_id: workspaceID,
        creator_id: creatorID,
        status: "completed",
        weekly_plan_id: weeklyPlanID,
        output_snapshot: snapshot,
      },
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.generation_id, generationRunID);
  assertEquals(body.weekly_plan_id, weeklyPlanID);
  assertEquals(Array.isArray(body.daily_cards), true);
  assertEquals((body.daily_cards as unknown[]).length, 7);
});

Deno.test("regenerate_day updates exactly one draft card and leaves the other six unchanged", async () => {
  const state = dayGenerationState();
  const before = structuredClone(state.dailyCards);
  const response = await handleGenerateWeekRequest(
    requestFor({
      action: "regenerate_day",
      creator_id: creatorID,
      weekly_plan_id: weeklyPlanID,
      scheduled_date: "2026-06-10",
      preserve_manual_edits: false,
    }),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(state),
      generateDayAI: async (input, providers, scheduledDate, dayIndex) => {
        assertEquals(providers[0].provider, "openai");
        const mock = makeMockGeneratedWeek(input);
        return {
          strategy_note: "Regenerated Wednesday only.",
          warnings: [],
          assumptions: [],
          daily_card: {
            ...mock.daily_cards[dayIndex],
            scheduled_date: scheduledDate,
            title: "Fresh Wednesday",
          },
          idea_bank: [],
          source_summary: "Live context plus the other six cards.",
        };
      },
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.target_scheduled_date, "2026-06-10");
  assertEquals(body.daily_card.title, "Fresh Wednesday");
  assertEquals(state.dailyCards[2].title, "Fresh Wednesday");
  for (const index of [0, 1, 3, 4, 5, 6]) {
    assertEquals(
      JSON.stringify(state.dailyCards[index]),
      JSON.stringify(before[index]),
      `card ${index} must remain unchanged`,
    );
  }
  assertEquals(state.updatedDailyCardIDs.join(","), dailyCardIDs[2]);
});

Deno.test("regenerate_day preserves manual review fields by default", async () => {
  const state = dayGenerationState();
  state.dailyCards[2].title = "Manual title";
  state.dailyCards[2].caption = "Manual caption";
  const response = await handleGenerateWeekRequest(
    requestFor({
      action: "regenerate_day",
      creator_id: creatorID,
      weekly_plan_id: weeklyPlanID,
      scheduled_date: "2026-06-10",
    }),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(state),
      generateDayAI: async (input, _providers, scheduledDate, dayIndex) => {
        const card = makeMockGeneratedWeek(input).daily_cards[dayIndex];
        return {
          strategy_note: "One day",
          warnings: [],
          assumptions: [],
          daily_card: {
            ...card,
            scheduled_date: scheduledDate,
            title: "AI title",
            caption: "AI caption",
            script: "New AI script",
          },
          idea_bank: [],
          source_summary: "Context",
        };
      },
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.daily_card.title, "Manual title");
  assertEquals(body.daily_card.caption, "Manual caption");
  assertEquals(body.daily_card.script, "New AI script");
});

Deno.test("regenerate_day rejects cross-workspace plans and published locks", async () => {
  const missingPlan = dayGenerationState();
  missingPlan.weeklyPlan = null;
  const missingResponse = await handleGenerateWeekRequest(
    requestFor(regenerateDayBody()),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(missingPlan),
    },
  );
  assertEquals(missingResponse.status, 404);
  assertEquals(await errorCode(missingResponse), "weekly_plan_not_found");

  const published = dayGenerationState();
  published.weeklyPlan = { ...published.weeklyPlan!, status: "published" };
  const publishedResponse = await handleGenerateWeekRequest(
    requestFor(regenerateDayBody()),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(published),
    },
  );
  assertEquals(publishedResponse.status, 409);
  assertEquals(
    await errorCode(publishedResponse),
    "existing_published_week_locked",
  );
});

Deno.test("regenerate_day rejects dates outside the plan week", async () => {
  const response = await handleGenerateWeekRequest(
    requestFor({ ...regenerateDayBody(), scheduled_date: "2026-06-15" }),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(dayGenerationState()),
    },
  );
  assertEquals(response.status, 400);
  assertEquals(await errorCode(response), "date_not_in_plan");
});

Deno.test("regenerate_day async mode schedules one card and returns a pollable run", async () => {
  const state = dayGenerationState();
  let scheduled: Promise<void> | undefined;
  const response = await handleGenerateWeekRequest(
    requestFor({
      ...regenerateDayBody(),
      preserve_manual_edits: false,
      response_mode: "async",
    }),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(state),
      generateDayAI: async (input, _providers, scheduledDate, dayIndex) => {
        const card = makeMockGeneratedWeek(input).daily_cards[dayIndex];
        return {
          strategy_note: "Async day",
          warnings: [],
          assumptions: [],
          daily_card: {
            ...card,
            scheduled_date: scheduledDate,
            title: "Async Wednesday",
          },
          idea_bank: [],
          source_summary: "Async context",
        };
      },
      runInBackground: (promise) => {
        scheduled = promise;
      },
    },
  );
  assertEquals(response.status, 202);
  const body = await response.json();
  assertEquals(body.generation_id, generationRunID);
  assertEquals(body.weekly_plan_id, weeklyPlanID);
  assertEquals(body.target_scheduled_date, "2026-06-10");
  if (!scheduled) {
    throw new Error("Expected single-day generation to be scheduled.");
  }
  await scheduled;
  assertEquals(state.dailyCards[2].title, "Async Wednesday");
  assertEquals(state.updatedDailyCardIDs.join(","), dailyCardIDs[2]);
});

Deno.test("generate-week status returns completed single-day snapshot", async () => {
  const state = dayGenerationState();
  const card = state.dailyCards[2];
  const snapshot = {
    generation_id: generationRunID,
    weekly_plan_id: weeklyPlanID,
    status: "draft",
    target_scheduled_date: "2026-06-10",
    daily_card: card,
    warnings: [],
    assumptions: [],
    source_summary: "One day",
    generated_at: "2026-06-10T08:00:00.000Z",
  };
  const response = await callHandler(
    {
      action: "status",
      generation_id: generationRunID,
      creator_id: creatorID,
    },
    {
      generationRun: {
        id: generationRunID,
        workspace_id: workspaceID,
        creator_id: creatorID,
        generation_scope: "day",
        status: "completed",
        weekly_plan_id: weeklyPlanID,
        target_daily_card_id: dailyCardIDs[2],
        target_scheduled_date: "2026-06-10",
        output_snapshot: snapshot,
      },
    },
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.target_scheduled_date, "2026-06-10");
  assertEquals(body.daily_card.id, dailyCardIDs[2]);
});

function requestFor(body: Record<string, unknown>): Request {
  return new Request("http://localhost/generate-week", {
    method: "POST",
    headers: { "x-mco-device-token": "device-token" },
    body: JSON.stringify(body),
  });
}

function regenerateDayBody(): Record<string, unknown> {
  return {
    action: "regenerate_day",
    creator_id: creatorID,
    weekly_plan_id: weeklyPlanID,
    scheduled_date: "2026-06-10",
  };
}

async function callHandler(
  body: Record<string, unknown>,
  state: Partial<FakeState>,
): Promise<Response> {
  return await handleGenerateWeekRequest(
    new Request("http://localhost/generate-week", {
      method: "POST",
      headers: { "x-mco-device-token": "device-token" },
      body: JSON.stringify(body),
    }),
    {
      env: fakeEnv(state.openAIKey, state.allowMockRequest),
      createAdminClient: () => fakeAdmin(state),
    },
  );
}

function fakeEnv(
  openAIKey?: string,
  allowMockRequest = false,
  deepSeekKey?: string,
): { get: (name: string) => string | undefined } {
  const values: Record<string, string> = {
    SUPABASE_URL: "http://127.0.0.1:54321",
    SUPABASE_SERVICE_ROLE_KEY: "local-service-role",
  };
  if (openAIKey) {
    values.OPENAI_API_KEY = openAIKey;
  }
  if (deepSeekKey) {
    values.DEEPSEEK_API_KEY = deepSeekKey;
  }
  if (allowMockRequest) {
    values.MCO_ALLOW_AI_MOCK_REQUEST = "1";
  }
  return { get: (name) => values[name] };
}

type FakeState = {
  memberRole: string;
  creatorExists: boolean;
  setupExists: boolean;
  publishedWeekExists: boolean;
  generationRun: Record<string, unknown> | null;
  weeklyPlan: Record<string, unknown> | null;
  dailyCards: Record<string, unknown>[];
  updatedDailyCardIDs: string[];
  openAIKey?: string;
  allowMockRequest: boolean;
};

function fakeAdmin(
  state: Partial<FakeState>,
): { from: (table: string) => any } {
  const resolved: FakeState = {
    memberRole: state.memberRole ?? "owner",
    creatorExists: state.creatorExists ?? true,
    setupExists: state.setupExists ?? true,
    publishedWeekExists: state.publishedWeekExists ?? false,
    generationRun: state.generationRun ?? null,
    weeklyPlan: state.weeklyPlan ?? null,
    dailyCards: state.dailyCards ?? [],
    updatedDailyCardIDs: state.updatedDailyCardIDs ?? [],
    openAIKey: state.openAIKey,
    allowMockRequest: state.allowMockRequest ?? false,
  };
  return {
    from(table: string) {
      return new FakeQuery(table, resolved);
    },
  };
}

class FakeQuery {
  private operation: "select" | "update" | "insert" | "upsert" | "delete" =
    "select";
  private filters: Record<string, unknown> = {};
  private values: unknown;

  constructor(
    private readonly table: string,
    private readonly state: FakeState,
  ) {}

  select(_columns?: string): FakeQuery {
    return this;
  }

  update(values: unknown): FakeQuery {
    this.operation = "update";
    this.values = values;
    return this;
  }

  insert(values: unknown): FakeQuery {
    this.operation = "insert";
    this.values = values;
    return this;
  }

  upsert(values: unknown): FakeQuery {
    this.operation = "upsert";
    this.values = values;
    return this;
  }

  delete(): FakeQuery {
    this.operation = "delete";
    return this;
  }

  eq(column: string, value: unknown): FakeQuery {
    this.filters[column] = value;
    return this;
  }

  is(column: string, value: unknown): FakeQuery {
    this.filters[column] = value;
    return this;
  }

  in(column: string, value: unknown): FakeQuery {
    this.filters[column] = value;
    return this;
  }

  gte(column: string, value: unknown): FakeQuery {
    this.filters[`${column}.gte`] = value;
    return this;
  }

  lte(column: string, value: unknown): FakeQuery {
    this.filters[`${column}.lte`] = value;
    return this;
  }

  order(_column: string, _options?: unknown): FakeQuery {
    return this;
  }

  limit(_count: number): FakeQuery {
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
      if (
        this.table === "weekly_generation_runs" &&
        this.operation === "insert"
      ) {
        const values = this.values as Record<string, unknown>;
        this.state.generationRun = { id: generationRunID, ...values };
        return { data: { id: generationRunID }, error: null };
      }
      if (
        this.table === "weekly_generation_runs" &&
        this.operation === "update" && this.state.generationRun
      ) {
        Object.assign(
          this.state.generationRun,
          this.values as Record<string, unknown>,
        );
      }
      if (this.table === "daily_cards" && this.operation === "update") {
        const card = this.state.dailyCards.find((candidate) =>
          candidate.id === this.filters.id &&
          candidate.scheduled_date === this.filters.scheduled_date
        );
        if (!card) {
          return { data: null, error: null };
        }
        Object.assign(card, this.values as Record<string, unknown>);
        this.state.updatedDailyCardIDs.push(String(card.id));
        return {
          data: { id: card.id, scheduled_date: card.scheduled_date },
          error: null,
        };
      }
      return {
        data: Array.isArray(this.values) ? this.values : this.values ?? {
          id: "write-ok",
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
            member_id: memberID,
            revoked_at: null,
          },
          error: null,
        };
      case "members":
        return {
          data: {
            id: memberID,
            workspace_id: workspaceID,
            role: this.state.memberRole,
            status: "active",
          },
          error: null,
        };
      case "creators":
        return {
          data: this.state.creatorExists
            ? {
              id: creatorID,
              display_name: "Mamta",
              default_timezone: "Asia/Kolkata",
            }
            : null,
          error: null,
        };
      case "weekly_plans":
        if (this.filters.id === weeklyPlanID) {
          return { data: this.state.weeklyPlan, error: null };
        }
        return {
          data: this.state.publishedWeekExists &&
              this.filters.status === "published"
            ? { id: "published-plan-id" }
            : [],
          error: null,
        };
      case "weekly_generation_runs":
        return {
          data: this.state.generationRun ? this.state.generationRun : [],
          error: null,
        };
      case "daily_cards":
        return {
          data: this.state.dailyCards.filter((card) =>
            (!this.filters.weekly_plan_id ||
              card.weekly_plan_id === this.filters.weekly_plan_id) &&
            (!this.filters.creator_id ||
              card.creator_id === this.filters.creator_id)
          ),
          error: null,
        };
      case "weekly_setups":
        return {
          data: this.state.setupExists
            ? [{
              id: setupID,
              creator_profile_id: null,
              week_start_date: "2026-06-08",
              status: "draft",
              location: "Mumbai",
            }]
            : [],
          error: null,
        };
      case "creator_profiles":
        return {
          data: [{
            id: "profile-id",
            status: "active",
            positioning: "Fitness after 60",
          }],
          error: null,
        };
      case "source_references":
        return {
          data: [{
            id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
            source_type: "reel_link",
            manual_notes: "Confirmed towel transition",
            status: "confirmed",
          }],
          error: null,
        };
      case "reference_extractions":
        return {
          data: [{
            id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1",
            source_reference_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
            extraction_kind: "pattern",
            extracted_payload: { summary: "hook-led sock transition" },
            status: "confirmed",
          }],
          error: null,
        };
      case "archive_entries":
        return { data: [], error: null };
      case "ideas":
        return { data: [], error: null };
      case "patterns":
        return { data: [], error: null };
      case "trends":
        return { data: [], error: null };
      case "audio_options":
        return { data: [], error: null };
      case "brand_briefs":
        return {
          data: [{
            id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            brand_name: "Brand hydration reminder",
            status: "active",
          }],
          error: null,
        };
      case "key_moments":
        return {
          data: [{
            id: "cccccccc-cccc-4ccc-8ccc-ccccccccccc1",
            name: "Sunday 10K",
            moment_date: "2026-06-14",
            status: "upcoming",
          }],
          error: null,
        };
      default:
        return { data: [], error: null };
    }
  }
}

function dayGenerationState(): FakeState {
  const input = {
    creator_id: creatorID,
    week_start_date: "2026-06-08",
    creator_profile: null,
    weekly_setup: null,
    confirmed_references: [],
    reference_extractions: [],
    recent_archive: [],
    idea_bank: [],
    patterns: [],
    trends: [],
    audio_options: [],
    brand_briefs: [],
    key_moments: [],
  };
  const cards = makeMockGeneratedWeek(input).daily_cards.map((card, index) => ({
    ...card,
    id: dailyCardIDs[index],
    workspace_id: workspaceID,
    creator_id: creatorID,
    weekly_plan_id: weeklyPlanID,
    status: "draft",
    backup_story: { line: card.backup_story },
    backup_caption_only: { line: card.backup_caption_only },
  }));
  return {
    memberRole: "owner",
    creatorExists: true,
    setupExists: true,
    publishedWeekExists: false,
    generationRun: null,
    weeklyPlan: {
      id: weeklyPlanID,
      workspace_id: workspaceID,
      creator_id: creatorID,
      weekly_setup_id: setupID,
      week_start_date: "2026-06-08",
      status: "draft",
      is_soft_locked: false,
    },
    dailyCards: cards,
    updatedDailyCardIDs: [],
    openAIKey: "openai-key",
    allowMockRequest: false,
  };
}

async function errorCode(response: Response): Promise<string | undefined> {
  return (await response.json()).error;
}

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  if (!Object.is(actual, expected)) {
    throw new Error(
      message ??
        `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

function assertArrayContainsObject(
  value: unknown,
  key: string,
  expected: unknown,
): void {
  if (!Array.isArray(value)) {
    throw new Error(`Expected array, got ${JSON.stringify(value)}`);
  }
  const found = value.some((item) =>
    typeof item === "object" &&
    item !== null &&
    Object.is(
      JSON.stringify((item as Record<string, unknown>)[key]),
      JSON.stringify(expected),
    )
  );
  if (!found) {
    throw new Error(
      `Expected array to contain ${key}=${JSON.stringify(expected)}, got ${
        JSON.stringify(value)
      }`,
    );
  }
}
