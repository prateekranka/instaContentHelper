import { handleGenerateWeekRequest } from "./index.ts";
import { makeMockGeneratedWeek } from "./generation.ts";

const workspaceID = "11111111-1111-4111-8111-111111111111";
const memberID = "22222222-2222-4222-8222-222222222222";
const creatorID = "33333333-3333-4333-8333-333333333333";
const setupID = "44444444-4444-4444-8444-444444444444";

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
        return {
          data: this.state.publishedWeekExists &&
              this.filters.status === "published"
            ? { id: "published-plan-id" }
            : [],
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
