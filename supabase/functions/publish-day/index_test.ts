import { handlePublishDayRequest } from "./index.ts";

const workspaceID = "11111111-1111-4111-8111-111111111111";
const memberID = "22222222-2222-4222-8222-222222222222";
const creatorID = "33333333-3333-4333-8333-333333333333";
const dailyCardID = "44444444-4444-4444-8444-444444444444";

Deno.test("publish-day publishes exactly the selected card through the atomic contract", async () => {
  let capturedFunction = "";
  let capturedPayload: Record<string, unknown> | undefined;
  const response = await callPublishDay(
    { creator_id: creatorID, daily_card_id: dailyCardID },
    async (functionName, args) => {
      capturedFunction = functionName;
      capturedPayload = args.payload as Record<string, unknown>;
      return {
        data: {
          daily_card_id: dailyCardID,
          scheduled_date: "2026-07-18",
          published_at: "2026-07-18T10:00:00.000Z",
          archived_card_count: 1,
        },
        error: null,
      };
    },
  );

  assertEquals(response.status, 200);
  assertEquals(capturedFunction, "publish_day_atomic");
  assertEquals(capturedPayload?.workspace_id, workspaceID);
  assertEquals(capturedPayload?.creator_id, creatorID);
  assertEquals(capturedPayload?.daily_card_id, dailyCardID);
  const body = await response.json();
  assertEquals(body.daily_card_id, dailyCardID);
  assertEquals(body.scheduled_date, "2026-07-18");
});

Deno.test("publish-day rejects malformed or incomplete card selection", async () => {
  for (
    const body of [
      { creator_id: creatorID },
      { daily_card_id: dailyCardID },
      { creator_id: "not-a-uuid", daily_card_id: dailyCardID },
    ]
  ) {
    const response = await callPublishDay(body, async () => {
      throw new Error("RPC must not be called for invalid input");
    });
    assertEquals(response.status, 400);
    assertEquals((await response.json()).error, "invalid_publish_payload");
  }
});

Deno.test("publish-day preserves stable authorization and card-state errors", async () => {
  for (
    const [error, status] of [
      ["daily_card_not_found", 404],
      ["daily_card_not_publishable", 409],
      ["cross_workspace_forbidden", 403],
      ["invalid_publish_payload", 400],
    ] as const
  ) {
    const response = await callPublishDay(
      { creator_id: creatorID, daily_card_id: dailyCardID },
      async () => ({ data: { error, status }, error: null }),
    );
    assertEquals(response.status, status);
    assertEquals((await response.json()).error, error);
  }
});

Deno.test("publish-day rejects unauthenticated device sessions", async () => {
  const response = await handlePublishDayRequest(
    new Request("http://localhost/publish-day", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        creator_id: creatorID,
        daily_card_id: dailyCardID,
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
      verifySession: async () => ({
        response: new Response(JSON.stringify({ error: "device_session_invalid" }), {
          status: 401,
          headers: { "Content-Type": "application/json" },
        }),
      }),
      createAdminClient: () => ({
        from() {
          throw new Error("RPC must not run without auth");
        },
        rpc() {
          throw new Error("RPC must not run without auth");
        },
      }),
    },
  );

  assertEquals(response.status, 401);
  assertEquals((await response.json()).error, "device_session_invalid");
});

Deno.test("publish-day rejects invalid JSON bodies", async () => {
  const response = await handlePublishDayRequest(
    new Request("http://localhost/publish-day", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-mco-device-token": "device-token",
      },
      body: "{not-json",
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
      verifySession: async () => ({
        session: {
          deviceInstallationID: "device-installation",
          workspaceID,
          memberID,
          role: "editor",
        },
      }),
      createAdminClient: () => ({
        from() {
          throw new Error("RPC must not run for invalid JSON");
        },
        rpc() {
          throw new Error("RPC must not run for invalid JSON");
        },
      }),
    },
  );

  assertEquals(response.status, 400);
  assertEquals((await response.json()).error, "invalid_json");
});

Deno.test("publish-day maps publish_day_atomic transport failures to daily_card_publish_failed", async () => {
  const response = await callPublishDay(
    { creator_id: creatorID, daily_card_id: dailyCardID },
    async () => ({
      data: null,
      error: { message: "connection reset" },
    }),
  );

  assertEquals(response.status, 500);
  assertEquals((await response.json()).error, "daily_card_publish_failed");
});

Deno.test("publish-day rejects malformed publish_day_atomic success payloads", async () => {
  for (
    const data of [
      null,
      { daily_card_id: dailyCardID },
      {
        daily_card_id: dailyCardID,
        scheduled_date: "2026-07-18",
      },
      {
        daily_card_id: "not-a-uuid",
        scheduled_date: "2026-07-18",
        published_at: "2026-07-18T10:00:00.000Z",
      },
    ]
  ) {
    const response = await callPublishDay(
      { creator_id: creatorID, daily_card_id: dailyCardID },
      async () => ({ data, error: null }),
    );
    assertEquals(response.status, 500);
    assertEquals((await response.json()).error, "invalid_publish_day_result");
  }
});

async function callPublishDay(
  body: Record<string, unknown>,
  rpc: (
    functionName: string,
    args: Record<string, unknown>,
  ) => Promise<{
    data: unknown;
    error: { message?: string } | null;
  }>,
): Promise<Response> {
  return await handlePublishDayRequest(
    new Request("http://localhost/publish-day", {
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
      verifySession: async () => ({
        session: {
          deviceInstallationID: "device-installation",
          workspaceID,
          memberID,
          role: "editor",
        },
      }),
      createAdminClient: () => ({
        from() {
          throw new Error("publish-day must use the atomic RPC");
        },
        rpc,
      }),
    },
  );
}

function assert(
  condition: unknown,
  message = "assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(actual: unknown, expected: unknown): void {
  assert(
    JSON.stringify(actual) === JSON.stringify(expected),
    `expected ${JSON.stringify(expected)}, received ${JSON.stringify(actual)}`,
  );
}
