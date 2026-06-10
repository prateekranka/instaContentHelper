// deno-lint-ignore-file no-explicit-any
import { bearerToken, handleExchangeAuthSessionRequest } from "./index.ts";

const workspaceID = "11111111-1111-4111-8111-111111111111";
const memberID = "22222222-2222-4222-8222-222222222222";
const creatorID = "33333333-3333-4333-8333-333333333333";
const installationID = "44444444-4444-4444-8444-444444444444";
const userID = "55555555-5555-4555-8555-555555555555";

Deno.test("bearerToken requires a bearer authorization header", () => {
  assertEquals(bearerToken(null), null);
  assertEquals(bearerToken("Basic abc"), null);
  assertEquals(bearerToken("Bearer signed-jwt"), "signed-jwt");
});

Deno.test("approved auth user receives existing device session contract", async () => {
  const state = exchangeState();
  const response = await handleExchangeAuthSessionRequest(
    exchangeRequest(),
    dependencies(state),
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.workspace_id, workspaceID);
  assertEquals(body.creator_id, creatorID);
  assertEquals(body.member_id, memberID);
  assertEquals(body.member_role, "editor");
  assertEquals(body.device_installation_id, installationID);
  assertEquals(body.device_token, "deterministic-device-token");
  assertEquals(state.installWrites.length, 1);
});

Deno.test("exchange rotates an owned installation token", async () => {
  const state = exchangeState();
  const response = await handleExchangeAuthSessionRequest(
    exchangeRequest({ device_installation_id: installationID }),
    dependencies(state),
  );

  assertEquals(response.status, 200);
  assertEquals(state.updateWrites.length, 1);
  assert(state.updateWrites[0].token_hash !== "old-token-hash");
  assertEquals(state.installWrites.length, 0);
});

Deno.test("unapproved auth user is rejected", async () => {
  const state = exchangeState({ memberships: [] });
  const response = await handleExchangeAuthSessionRequest(
    exchangeRequest(),
    dependencies(state),
  );

  assertEquals(response.status, 403);
  assertEquals((await response.json()).error, "tester_not_approved");
});

Deno.test("revoked approved member receives stable revoked error", async () => {
  const member = exchangeState().memberships[0];
  const state = exchangeState({
    memberships: [{ ...member, status: "revoked" }],
  });
  const response = await handleExchangeAuthSessionRequest(
    exchangeRequest(),
    dependencies(state),
  );

  assertEquals(response.status, 403);
  assertEquals((await response.json()).error, "member_revoked");
});

Deno.test("ambiguous workspace membership is rejected", async () => {
  const member = exchangeState().memberships[0];
  const state = exchangeState({
    memberships: [member, { ...member, workspace_id: crypto.randomUUID() }],
  });
  const response = await handleExchangeAuthSessionRequest(
    exchangeRequest(),
    dependencies(state),
  );

  assertEquals(response.status, 409);
  assertEquals((await response.json()).error, "workspace_unavailable");
});

type ExchangeState = {
  memberships: Record<string, unknown>[];
  installWrites: Record<string, unknown>[];
  updateWrites: Record<string, unknown>[];
};

function exchangeState(
  overrides: Partial<ExchangeState> = {},
): ExchangeState {
  return {
    memberships: [{
      id: memberID,
      workspace_id: workspaceID,
      email: "tester@example.com",
      display_name: "Tester",
      role: "editor",
      status: "active",
    }],
    installWrites: [],
    updateWrites: [],
    ...overrides,
  };
}

function exchangeRequest(body: Record<string, unknown> = {}): Request {
  return new Request("http://localhost/exchange-auth-session", {
    method: "POST",
    headers: {
      Authorization: "Bearer valid-auth-jwt",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ device_name: "Test iPhone", ...body }),
  });
}

function dependencies(state: ExchangeState) {
  return {
    env: {
      get(name: string) {
        return name === "SUPABASE_URL"
          ? "http://127.0.0.1:54321"
          : name === "SUPABASE_SERVICE_ROLE_KEY"
          ? "service-role"
          : undefined;
      },
    },
    generateDeviceToken: () => "deterministic-device-token",
    now: () => new Date("2026-06-10T12:00:00.000Z"),
    createAdminClient: () => ({
      auth: {
        getUser: () =>
          Promise.resolve({
            data: { user: { id: userID, email: "tester@example.com" } },
            error: null,
          }),
      },
      from: (table: string) => new FakeExchangeQuery(table, state),
    }),
  };
}

class FakeExchangeQuery {
  private operation: "select" | "insert" | "update" = "select";
  private values: Record<string, unknown> = {};
  private filters: Record<string, unknown> = {};

  constructor(
    private readonly table: string,
    private readonly state: ExchangeState,
  ) {}

  select(_columns?: string): FakeExchangeQuery {
    return this;
  }

  insert(values: Record<string, unknown>): FakeExchangeQuery {
    this.operation = "insert";
    this.values = values;
    return this;
  }

  update(values: Record<string, unknown>): FakeExchangeQuery {
    this.operation = "update";
    this.values = values;
    return this;
  }

  eq(column: string, value: unknown): FakeExchangeQuery {
    this.filters[column] = value;
    return this;
  }

  limit(_value: number): FakeExchangeQuery {
    return this;
  }

  order(_column: string, _options?: unknown): FakeExchangeQuery {
    return this;
  }

  maybeSingle(): Promise<{ data: any; error: null }> {
    return Promise.resolve({ data: this.resolveSingle(), error: null });
  }

  single(): Promise<{ data: any; error: null }> {
    return Promise.resolve({ data: this.resolveSingle(), error: null });
  }

  then<TResult1 = { data: any; error: null }, TResult2 = never>(
    onfulfilled?: ((value: { data: any; error: null }) => TResult1) | null,
    onrejected?: ((reason: unknown) => TResult2) | null,
  ): Promise<TResult1 | TResult2> {
    return Promise.resolve({ data: this.resolveList(), error: null }).then(
      onfulfilled,
      onrejected,
    );
  }

  private resolveList(): any[] {
    if (this.table === "members") {
      return this.state.memberships;
    }
    return [];
  }

  private resolveSingle(): any {
    if (this.table === "workspaces") {
      return { id: workspaceID, name: "Mamta Content OS" };
    }
    if (this.table === "creators") {
      return { id: creatorID, display_name: "Mamta" };
    }
    if (this.table === "device_installations") {
      if (this.operation === "update") {
        if (this.filters.id !== installationID) return null;
        this.state.updateWrites.push(this.values);
      } else {
        this.state.installWrites.push(this.values);
      }
      return {
        id: installationID,
        paired_at: "2026-06-10T12:00:00.000Z",
      };
    }
    return null;
  }
}

function assert(condition: unknown): asserts condition {
  if (!condition) throw new Error("Assertion failed");
}

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
