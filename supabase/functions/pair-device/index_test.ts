import { handlePairDeviceRequest } from "./index.ts";

const workspaceID = "11111111-1111-4111-8111-111111111111";
const inviteID = "22222222-2222-4222-8222-222222222222";
const creatorID = "33333333-3333-4333-8333-333333333333";
const memberID = "44444444-4444-4444-8444-444444444444";
const installationID = "55555555-5555-4555-8555-555555555555";

Deno.test("pair-device consumes an active invite and returns a device session", async () => {
  const state = pairState();
  const response = await handlePairDeviceRequest(pairRequest(), {
    env: {
      get(name: string) {
        return name === "SUPABASE_URL"
          ? "http://127.0.0.1:54321"
          : name === "SUPABASE_SERVICE_ROLE_KEY"
          ? "service-role"
          : undefined;
      },
    },
    createAdminClient: () => ({
      from: (table: string) => new FakePairQuery(table, state),
    }),
    generateDeviceToken: () => "deterministic-device-token",
    now: () => new Date("2026-06-10T12:00:00.000Z"),
  });

  assertEquals(response.status, 200);
  assertEquals(state.inviteUpdates[0].used_count, 1);
  assertEquals(state.memberInserts[0].display_name, "QA iPhone");
  assertEquals(state.memberInserts[0].role, "creator");
  assertEquals(state.installationInserts[0].device_name, "QA iPhone");
  assertEquals(state.installationInserts[0].platform, "ios");

  const body = await response.json();
  assertEquals(body.workspace_id, workspaceID);
  assertEquals(body.workspace_name, "Creator Content OS");
  assertEquals(body.creator_id, creatorID);
  assertEquals(body.creator_display_name, "Creator");
  assertEquals(body.member_id, memberID);
  assertEquals(body.member_role, "creator");
  assertEquals(body.device_installation_id, installationID);
  assertEquals(body.device_token, "deterministic-device-token");
  assertEquals(body.paired_at, "2026-06-10T12:00:00.000Z");
});

type PairState = {
  inviteUpdates: Record<string, unknown>[];
  memberInserts: Record<string, unknown>[];
  installationInserts: Record<string, unknown>[];
};

function pairState(): PairState {
  return {
    inviteUpdates: [],
    memberInserts: [],
    installationInserts: [],
  };
}

function pairRequest(): Request {
  return new Request("http://localhost/pair-device", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      invite_code: " QA 123 ",
      device_name: " QA iPhone ",
      platform: "ios",
    }),
  });
}

class FakePairQuery {
  private operation: "select" | "insert" | "update" | "delete" = "select";
  private values: Record<string, unknown> = {};

  constructor(
    private readonly table: string,
    private readonly state: PairState,
  ) {}

  select(_columns?: string): FakePairQuery {
    return this;
  }

  insert(values: Record<string, unknown>): FakePairQuery {
    this.operation = "insert";
    this.values = values;
    return this;
  }

  update(values: Record<string, unknown>): FakePairQuery {
    this.operation = "update";
    this.values = values;
    return this;
  }

  delete(): FakePairQuery {
    this.operation = "delete";
    return this;
  }

  eq(_column: string, _value: unknown): FakePairQuery {
    return this;
  }

  is(_column: string, _value: unknown): FakePairQuery {
    return this;
  }

  gt(_column: string, _value: unknown): FakePairQuery {
    return this;
  }

  lt(_column: string, _value: unknown): FakePairQuery {
    return this;
  }

  order(_column: string, _options?: Record<string, unknown>): FakePairQuery {
    return this;
  }

  limit(_count: number): FakePairQuery {
    return this;
  }

  maybeSingle(): Promise<{ data: Record<string, unknown> | null; error: null }> {
    if (this.table === "device_invites") {
      return Promise.resolve({
        data: {
          id: inviteID,
          workspace_id: workspaceID,
          role_granted: "creator",
          expires_at: "2026-06-11T12:00:00.000Z",
          use_limit: 2,
          used_count: 0,
          revoked_at: null,
        },
        error: null,
      });
    }
    return Promise.resolve({ data: null, error: null });
  }

  single(): Promise<{ data: Record<string, unknown> | null; error: null }> {
    if (this.table === "workspaces") {
      return Promise.resolve({
        data: { id: workspaceID, name: "Creator Content OS" },
        error: null,
      });
    }
    if (this.table === "creators") {
      return Promise.resolve({
        data: { id: creatorID, display_name: "Creator" },
        error: null,
      });
    }
    if (this.table === "device_invites" && this.operation === "update") {
      this.state.inviteUpdates.push(this.values);
      return Promise.resolve({ data: { id: inviteID }, error: null });
    }
    if (this.table === "members" && this.operation === "insert") {
      this.state.memberInserts.push(this.values);
      return Promise.resolve({
        data: { id: memberID, role: this.values.role },
        error: null,
      });
    }
    if (this.table === "device_installations" && this.operation === "insert") {
      this.state.installationInserts.push(this.values);
      return Promise.resolve({
        data: { id: installationID, paired_at: "2026-06-10T12:00:00.000Z" },
        error: null,
      });
    }
    return Promise.resolve({ data: null, error: null });
  }
}

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
