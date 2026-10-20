import { handleUpdateReadyDayPackageRequest } from "./index.ts";

const workspaceID = "11111111-1111-4111-8111-111111111111";
const authenticatedMemberID = "22222222-2222-4222-8222-222222222222";
const creatorID = "33333333-3333-4333-8333-333333333333";
const weeklyPlanID = "77777777-7777-4777-8777-777777777771";
const dailyCardID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1";
const scheduledDate = "2026-07-21";

Deno.test("update_ready_day_package keeps ready status and ignores week soft-lock", async () => {
  let rpcCalled = false;
  const captured: { payload: Record<string, unknown> | null } = {
    payload: null,
  };

  const response = await handleUpdateReadyDayPackageRequest(
    new Request("http://localhost/update-ready-day-package", {
      method: "POST",
      headers: { "x-mco-device-token": "device-token" },
      body: JSON.stringify({
        creator_id: creatorID,
        daily_card_id: dailyCardID,
        package: {
          caption: "Edited caption stays ready.",
          title: "Edited title",
        },
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
          if (fn === "update_ready_day_package") {
            rpcCalled = true;
            captured.payload = args.payload as Record<string, unknown>;
            return Promise.resolve({
              data: {
                daily_card_id: dailyCardID,
                scheduled_date: scheduledDate,
                status: "published",
                weekly_plan_id: weeklyPlanID,
                title: "Edited title",
                caption: "Edited caption stays ready.",
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
  assert(rpcCalled, "expected update_ready_day_package RPC");
  const payload = captured.payload!;
  assertEquals(payload.workspace_id, workspaceID);
  assertEquals(payload.daily_card_id, dailyCardID);
  const pkg = payload.package as Record<string, unknown>;
  assertEquals(pkg.caption, "Edited caption stays ready.");

  const body = await response.json();
  assertEquals(body.status, "published");
  assertEquals(body.caption, "Edited caption stays ready.");
});

Deno.test("update_ready_day_package maps daily_card_not_ready to 409", async () => {
  const response = await handleUpdateReadyDayPackageRequest(
    new Request("http://localhost/update-ready-day-package", {
      method: "POST",
      headers: { "x-mco-device-token": "device-token" },
      body: JSON.stringify({
        creator_id: creatorID,
        scheduled_date: scheduledDate,
        package: { caption: "Nope" },
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
            data: { error: "daily_card_not_ready", status: 409 },
            error: null,
          });
        },
      }),
    },
  );

  assertEquals(response.status, 409);
  const body = await response.json();
  assertEquals(body.error, "daily_card_not_ready");
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

Deno.test("package edits reject blank text and invalid text before writing", async () => {
  for (
    const [value, code] of [
      ["", "blank_package_text"],
      [" \n\t", "blank_package_text"],
      [null, "invalid_package_text"],
      [{ line: "text" }, "invalid_package_text"],
    ]
  ) {
    const response = await handleUpdateReadyDayPackageRequest(
      new Request("http://localhost/update-ready-day-package", {
        method: "POST",
        headers: { "x-mco-device-token": "device-token" },
        body: JSON.stringify({
          creator_id: creatorID,
          daily_card_id: dailyCardID,
          package: { caption: value },
        }),
      }),
      {
        env: {
          get(name: string) {
            return name === "SUPABASE_URL" ? "http://localhost" : "local-key";
          },
        },
        createAdminClient: () => ({
          from(table: string) {
            return new FakeAuthQuery(table);
          },
          rpc() {
            throw new Error("blank edit must not write");
          },
        }),
      },
    );
    assertEquals(response.status, 400);
    assertEquals((await response.json()).error, code);
  }
});

Deno.test("scene list validation rejects malformed lists before the RPC", async () => {
  for (const sceneList of [null, {}, "shots", 1, true]) {
    const response = await sceneRequest(sceneList, () => {
      throw new Error("invalid scene list must not write");
    });
    assertEquals(response.status, 400);
    const body = await response.json();
    assertEquals(body.error, "invalid_package_scene_list");
    assertEquals(body.field, "scene_list");
    assertEquals(body.shot_index, undefined);
  }
});

Deno.test("scene list validation checks every shot and every field type", async () => {
  const shot = {
    id: "1407e44a-1f70-4b96-8ee2-000000000001",
    title: "Opening",
    duration: "5 sec",
  };
  const invalidShots: unknown[] = [null, [], "shot", 1, true];
  for (
    const id of [
      "not-a-uuid",
      "",
      "1407e44a1f704b968ee2000000000001",
      " 1407e44a-1f70-4b96-8ee2-000000000001",
    ]
  ) {
    invalidShots.push({ ...shot, id });
  }
  for (const field of ["id", "title", "duration"]) {
    const missing: Record<string, unknown> = { ...shot };
    delete missing[field];
    invalidShots.push(missing);
    for (const value of [null, 1, true, [], {}]) {
      invalidShots.push({ ...shot, [field]: value });
    }
  }
  for (const value of [null, 1, true, [], {}]) {
    invalidShots.push({ ...shot, dialogue: value });
  }
  for (const invalid of invalidShots) {
    const response = await sceneRequest([shot, invalid], () => {
      throw new Error("invalid shot must not write any part of the patch");
    });
    assertEquals(response.status, 400);
    const body = await response.json();
    assertEquals(body.error, "invalid_package_scene_list");
    assertEquals(body.field, "scene_list");
    assertEquals(body.shot_index, 1);
  }
});

Deno.test("scene list accepts the Swift payload and retains optional shot metadata", async () => {
  const scenes = [
    {
      id: dailyCardID,
      number: 1,
      title: "Opening",
      duration: "5 sec",
      symbol: "camera",
      dialogue: "The opening line.",
    },
    {
      id: "1407e44a-1f70-4b96-8ee2-000000000002",
      number: 2,
      title: "Silent shot",
      duration: "3 sec",
      symbol: "camera",
    },
    {
      id: "1407e44a-1f70-4b96-8ee2-000000000003",
      title: "Blank line",
      duration: "0 sec",
      dialogue: "",
    },
  ];
  for (const sceneList of [scenes, []]) {
    let calls = 0;
    const response = await sceneRequest(sceneList, (payload) => {
      calls++;
      const patch = payload.package as Record<string, unknown>;
      assertEquals(JSON.stringify(patch.scene_list), JSON.stringify(sceneList));
      assertEquals(patch.caption, "Valid partial edit");
      return {
        data: { daily_card_id: dailyCardID, status: "published" },
        error: null,
      };
    });
    assertEquals(response.status, 200);
    assertEquals(calls, 1);
  }
});

Deno.test("scene validation errors returned by SQL retain the code and index", async () => {
  const response = await sceneRequest([], () => ({
    data: {
      error: "invalid_package_scene_list",
      field: "scene_list",
      shot_index: 2,
      status: 400,
    },
    error: null,
  }));
  assertEquals(response.status, 400);
  const body = await response.json();
  assertEquals(body.error, "invalid_package_scene_list");
  assertEquals(body.field, "scene_list");
  assertEquals(body.shot_index, 2);
});

function sceneRequest(
  sceneList: unknown,
  rpc: (payload: Record<string, unknown>) => { data: unknown; error: null },
): Promise<Response> {
  return handleUpdateReadyDayPackageRequest(
    new Request("http://localhost/update-ready-day-package", {
      method: "POST",
      headers: { "x-mco-device-token": "device-token" },
      body: JSON.stringify({
        creator_id: creatorID,
        daily_card_id: dailyCardID,
        package: { caption: "Valid partial edit", scene_list: sceneList },
      }),
    }),
    {
      env: {
        get(name: string) {
          return name === "SUPABASE_URL" ? "http://localhost" : "local-key";
        },
      },
      createAdminClient: () => ({
        from(table: string) {
          return new FakeAuthQuery(table);
        },
        rpc(_fn: string, args: Record<string, unknown>) {
          return Promise.resolve(rpc(args.payload as Record<string, unknown>));
        },
      }),
    },
  );
}
