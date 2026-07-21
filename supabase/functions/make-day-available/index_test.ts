import { handleMakeDayAvailableRequest } from "./index.ts";

const workspaceID = "11111111-1111-4111-8111-111111111111";
const authenticatedMemberID = "22222222-2222-4222-8222-222222222222";
const creatorID = "33333333-3333-4333-8333-333333333333";
const weeklyPlanID = "77777777-7777-4777-8777-777777777771";
const dailyCardID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1";
const scheduledDate = "2026-07-21";

Deno.test("make_day_available promotes a single draft without soft-locking the week", async () => {
  let rpcCalled = false;
  const captured: { payload: Record<string, unknown> | null } = { payload: null };

  const response = await handleMakeDayAvailableRequest(
    new Request("http://localhost/make-day-available", {
      method: "POST",
      headers: { "x-mco-device-token": "device-token" },
      body: JSON.stringify({
        creator_id: creatorID,
        scheduled_date: scheduledDate,
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
          return new FakeAuthQuery(table);
        },
        rpc(
          fn: string,
          args: Record<string, unknown>,
        ): Promise<{ data: unknown; error: null }> {
          if (fn === "make_day_available") {
            rpcCalled = true;
            captured.payload = args.payload as Record<string, unknown>;
            return Promise.resolve({
              data: {
                daily_card_id: dailyCardID,
                scheduled_date: scheduledDate,
                status: "published",
                weekly_plan_id: weeklyPlanID,
                week_is_soft_locked: false,
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
  assert(rpcCalled, "expected make_day_available RPC to be called");
  const payload = captured.payload!;
  assertEquals(payload.workspace_id, workspaceID);
  assertEquals(payload.creator_id, creatorID);
  assertEquals(payload.scheduled_date, scheduledDate);

  const body = await response.json();
  assertEquals(body.daily_card_id, dailyCardID);
  assertEquals(body.scheduled_date, scheduledDate);
  assertEquals(body.status, "published");
  assertEquals(body.week_is_soft_locked, false);
  assertEquals(body.weekly_plan_id, weeklyPlanID);
});

Deno.test("make_day_available maps daily_card_not_draft to 409", async () => {
  const response = await handleMakeDayAvailableRequest(
    new Request("http://localhost/make-day-available", {
      method: "POST",
      headers: { "x-mco-device-token": "device-token" },
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
      createAdminClient: () => ({
        from(table: string) {
          return new FakeAuthQuery(table);
        },
        rpc(): Promise<{ data: unknown; error: null }> {
          return Promise.resolve({
            data: { error: "daily_card_not_draft", status: 409 },
            error: null,
          });
        },
      }),
    },
  );

  assertEquals(response.status, 409);
  const body = await response.json();
  assertEquals(body.error, "daily_card_not_draft");
});

Deno.test("make_day_available rejects missing scheduled_date and daily_card_id", async () => {
  const response = await handleMakeDayAvailableRequest(
    new Request("http://localhost/make-day-available", {
      method: "POST",
      headers: { "x-mco-device-token": "device-token" },
      body: JSON.stringify({ creator_id: creatorID }),
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
          return new FakeAuthQuery(table);
        },
        rpc(): Promise<{ data: unknown; error: null }> {
          return Promise.resolve({ data: null, error: null });
        },
      }),
    },
  );

  assertEquals(response.status, 400);
  const body = await response.json();
  assertEquals(body.error, "invalid_make_day_available_payload");
});

Deno.test("make_day_available does not require seven days in the payload", async () => {
  const captured: { payload: Record<string, unknown> | null } = { payload: null };

  const response = await handleMakeDayAvailableRequest(
    new Request("http://localhost/make-day-available", {
      method: "POST",
      headers: { "x-mco-device-token": "device-token" },
      body: JSON.stringify({
        creator_id: creatorID,
        scheduled_date: scheduledDate,
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
      createAdminClient: () => ({
        from(table: string) {
          return new FakeAuthQuery(table);
        },
        rpc(
          _fn: string,
          args: Record<string, unknown>,
        ): Promise<{ data: unknown; error: null }> {
          captured.payload = args.payload as Record<string, unknown>;
          return Promise.resolve({
            data: {
              daily_card_id: dailyCardID,
              scheduled_date: scheduledDate,
              status: "published",
              weekly_plan_id: weeklyPlanID,
              week_is_soft_locked: false,
            },
            error: null,
          });
        },
      }),
    },
  );

  assertEquals(response.status, 200);
  const payload = captured.payload!;
  assertEquals(payload.daily_card_id, dailyCardID);
  assertEquals(payload.scheduled_date, scheduledDate);
  assert(
    !("draft_daily_cards" in payload),
    "must not require a seven-day draft_daily_cards payload",
  );
});

class FakeAuthQuery {
  constructor(private readonly table: string) {}

  select(_columns?: string): FakeAuthQuery {
    return this;
  }

  eq(_column: string, _value: unknown): FakeAuthQuery {
    return this;
  }

  is(_column: string, _value: unknown): FakeAuthQuery {
    return this;
  }

  update(_values: Record<string, unknown>): FakeAuthQuery {
    return this;
  }

  maybeSingle(): Promise<{ data: unknown; error: null }> {
    switch (this.table) {
      case "device_installations":
        return Promise.resolve({
          data: {
            id: "device-installation-id",
            workspace_id: workspaceID,
            member_id: authenticatedMemberID,
            revoked_at: null,
          },
          error: null,
        });
      case "members":
        return Promise.resolve({
          data: {
            id: authenticatedMemberID,
            workspace_id: workspaceID,
            role: "owner",
            status: "active",
          },
          error: null,
        });
      case "creators":
        return Promise.resolve({ data: { id: creatorID }, error: null });
      default:
        return Promise.resolve({ data: null, error: null });
    }
  }

  then<TResult1 = { data: unknown; error: null }, TResult2 = never>(
    onfulfilled?:
      | ((
        value: { data: unknown; error: null },
      ) => TResult1 | PromiseLike<TResult1>)
      | null,
    onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
  ): Promise<TResult1 | TResult2> {
    return Promise.resolve({ data: null, error: null }).then(
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
        `Expected ${Deno.inspect(expected)}, got ${Deno.inspect(actual)}`,
    );
  }
}
