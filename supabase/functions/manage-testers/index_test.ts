// deno-lint-ignore-file no-explicit-any
import { handleManageTestersRequest, normalizeEmail } from "./index.ts";

const workspaceID = "11111111-1111-4111-8111-111111111111";
const ownerID = "22222222-2222-4222-8222-222222222222";
const testerID = "33333333-3333-4333-8333-333333333333";
const authUserID = "44444444-4444-4444-8444-444444444444";

Deno.test("normalizeEmail validates and canonicalizes approved email", () => {
  assertEquals(normalizeEmail(" Tester@Example.COM "), "tester@example.com");
  assertEquals(normalizeEmail("not-an-email"), null);
});

Deno.test("only owners may manage testers", async () => {
  const state = manageState();
  const response = await handleManageTestersRequest(
    manageRequest({ action: "list" }),
    dependencies(state, false),
  );
  assertEquals(response.status, 403);
  assertEquals((await response.json()).error, "role_not_allowed");
});

Deno.test("invite creates approved editor and sends OTP", async () => {
  const state = manageState();
  const response = await handleManageTestersRequest(
    manageRequest({
      action: "invite",
      email: " Tester@Example.com ",
      display_name: "Test Editor",
    }),
    dependencies(state),
  );

  assertEquals(response.status, 201);
  assertEquals(state.memberWrites[0].role, "editor");
  assertEquals(state.memberWrites[0].email, "tester@example.com");
  assertEquals(state.otpEmails, ["tester@example.com"]);
  assertEquals((await response.json()).otp_sent, true);
});

Deno.test("resend only sends OTP for active approved tester", async () => {
  const state = manageState({ existingTester: activeTester() });
  const response = await handleManageTestersRequest(
    manageRequest({ action: "resend", email: "tester@example.com" }),
    dependencies(state),
  );

  assertEquals(response.status, 200);
  assertEquals(state.otpEmails, ["tester@example.com"]);
});

Deno.test("revoke disables member and all active device tokens", async () => {
  const state = manageState({ existingTester: activeTester() });
  const response = await handleManageTestersRequest(
    manageRequest({ action: "revoke", member_id: testerID }),
    dependencies(state),
  );

  assertEquals(response.status, 200);
  assertEquals(state.memberUpdates[0].status, "revoked");
  assertEquals(typeof state.installationUpdates[0].revoked_at, "string");
  assertEquals((await response.json()).access_revoked, true);
});

type ManageState = {
  existingTester: Record<string, unknown> | null;
  memberWrites: Record<string, unknown>[];
  memberUpdates: Record<string, unknown>[];
  installationUpdates: Record<string, unknown>[];
  otpEmails: string[];
};

function manageState(overrides: Partial<ManageState> = {}): ManageState {
  return {
    existingTester: null,
    memberWrites: [],
    memberUpdates: [],
    installationUpdates: [],
    otpEmails: [],
    ...overrides,
  };
}

function activeTester(): Record<string, unknown> {
  return {
    id: testerID,
    email: "tester@example.com",
    display_name: "Tester",
    role: "editor",
    status: "active",
    created_at: "2026-06-10T10:00:00.000Z",
    updated_at: "2026-06-10T10:00:00.000Z",
  };
}

function manageRequest(body: Record<string, unknown>): Request {
  return new Request("http://localhost/manage-testers", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

function dependencies(state: ManageState, owner = true) {
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
    now: () => new Date("2026-06-10T12:00:00.000Z"),
    verifyOwner: () =>
      Promise.resolve(
        owner
          ? {
            session: {
              deviceInstallationID: crypto.randomUUID(),
              workspaceID,
              memberID: ownerID,
              role: "owner",
            },
          }
          : {
            response: new Response(
              JSON.stringify({ error: "role_not_allowed" }),
              {
                status: 403,
              },
            ),
          },
      ),
    createAdminClient: () => ({
      auth: {
        admin: {
          listUsers: () =>
            Promise.resolve({ data: { users: [] }, error: null }),
          createUser: () =>
            Promise.resolve({
              data: { user: { id: authUserID, email: "tester@example.com" } },
              error: null,
            }),
          deleteUser: () => Promise.resolve({ error: null }),
        },
        signInWithOtp: ({ email }: { email: string }) => {
          state.otpEmails.push(email);
          return Promise.resolve({ error: null });
        },
      },
      from: (table: string) => new FakeManageQuery(table, state),
    }),
  };
}

class FakeManageQuery {
  private operation: "select" | "insert" | "update" = "select";
  private values: Record<string, unknown> = {};

  constructor(
    private readonly table: string,
    private readonly state: ManageState,
  ) {}

  select(_columns?: string): FakeManageQuery {
    return this;
  }

  insert(values: Record<string, unknown>): FakeManageQuery {
    this.operation = "insert";
    this.values = values;
    return this;
  }

  update(values: Record<string, unknown>): FakeManageQuery {
    this.operation = "update";
    this.values = values;
    return this;
  }

  eq(_column: string, _value: unknown): FakeManageQuery {
    return this;
  }

  neq(_column: string, _value: unknown): FakeManageQuery {
    return this;
  }

  not(_column: string, _operator: string, _value: unknown): FakeManageQuery {
    return this;
  }

  is(_column: string, _value: unknown): FakeManageQuery {
    return this;
  }

  order(_column: string, _options?: unknown): FakeManageQuery {
    return this;
  }

  maybeSingle(): Promise<{ data: any; error: null }> {
    if (this.operation === "select") {
      return Promise.resolve({ data: this.state.existingTester, error: null });
    }
    return Promise.resolve({ data: this.captureWrite(), error: null });
  }

  single(): Promise<{ data: any; error: null }> {
    return Promise.resolve({ data: this.captureWrite(), error: null });
  }

  then<TResult1 = { data: any; error: null }, TResult2 = never>(
    onfulfilled?: ((value: { data: any; error: null }) => TResult1) | null,
    onrejected?: ((reason: unknown) => TResult2) | null,
  ): Promise<TResult1 | TResult2> {
    if (this.operation === "update") this.captureWrite();
    return Promise.resolve({ data: [], error: null }).then(
      onfulfilled,
      onrejected,
    );
  }

  private captureWrite(): Record<string, unknown> {
    if (this.table === "device_installations") {
      this.state.installationUpdates.push(this.values);
      return { id: crypto.randomUUID(), ...this.values };
    }
    if (this.operation === "insert") {
      this.state.memberWrites.push(this.values);
      return { id: testerID, ...this.values };
    }
    this.state.memberUpdates.push(this.values);
    return {
      ...(this.state.existingTester ?? { id: testerID }),
      ...this.values,
    };
  }
}

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
