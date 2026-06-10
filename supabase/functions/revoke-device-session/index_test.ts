import { handleRevokeDeviceSessionRequest } from "./index.ts";

const installationID = "11111111-1111-4111-8111-111111111111";
const workspaceID = "22222222-2222-4222-8222-222222222222";
const memberID = "33333333-3333-4333-8333-333333333333";

Deno.test("revoke-device-session revokes the authenticated installation", async () => {
  const writes: Record<string, unknown>[] = [];
  const response = await handleRevokeDeviceSessionRequest(
    new Request("http://localhost/revoke-device-session", { method: "POST" }),
    {
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
      verifySession: () =>
        Promise.resolve({
          session: {
            deviceInstallationID: installationID,
            workspaceID,
            memberID,
            role: "editor",
          },
        }),
      createAdminClient: () => ({
        from: () => new FakeRevokeQuery(writes),
      }),
    },
  );

  assertEquals(response.status, 200);
  assertEquals(writes[0].revoked_at, "2026-06-10T12:00:00.000Z");
  assertEquals((await response.json()).device_installation_id, installationID);
});

class FakeRevokeQuery {
  private values: Record<string, unknown> = {};

  constructor(private readonly writes: Record<string, unknown>[]) {}

  update(values: Record<string, unknown>): FakeRevokeQuery {
    this.values = values;
    return this;
  }

  eq(_column: string, _value: unknown): FakeRevokeQuery {
    return this;
  }

  is(_column: string, _value: unknown): FakeRevokeQuery {
    return this;
  }

  select(_columns: string): FakeRevokeQuery {
    return this;
  }

  maybeSingle(): Promise<{ data: Record<string, unknown>; error: null }> {
    this.writes.push(this.values);
    return Promise.resolve({
      data: { id: installationID, revoked_at: this.values.revoked_at },
      error: null,
    });
  }
}

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
