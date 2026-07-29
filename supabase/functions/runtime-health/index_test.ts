import { handleRuntimeHealthRequest } from "./index.ts";

const installationID = "11111111-1111-4111-8111-111111111111";
const workspaceID = "22222222-2222-4222-8222-222222222222";
const memberID = "33333333-3333-4333-8333-333333333333";

Deno.test("runtime-health reports live supabase and gemini probes", async () => {
  const response = await handleRuntimeHealthRequest(
    new Request("http://localhost/runtime-health", { method: "POST" }),
    {
      env: {
        get(name: string) {
          if (name === "SUPABASE_URL") return "http://127.0.0.1:54321";
          if (name === "SUPABASE_SERVICE_ROLE_KEY") return "service-role";
          if (name === "GEMINI_API_KEY") return "gemini-key";
          return undefined;
        },
      },
      now: () => new Date("2026-07-21T12:00:00.000Z"),
      verifySession: () =>
        Promise.resolve({
          session: {
            deviceInstallationID: installationID,
            workspaceID,
            memberID,
            role: "creator",
          },
        }),
      createAdminClient: () => ({
        from: () => ({
          select: () => ({
            limit: () => Promise.resolve({ data: [{ id: workspaceID }], error: null }),
          }),
        }),
      }),
      fetchFn: () =>
        Promise.resolve(
          new Response(JSON.stringify({ models: [{ name: "models/gemini" }] }), {
            status: 200,
          }),
        ),
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.checked_at, "2026-07-21T12:00:00.000Z");
  assertEquals(body.supabase.ok, true);
  assertEquals(body.gemini.ok, true);
});

Deno.test("runtime-health marks gemini down when api key missing", async () => {
  const response = await handleRuntimeHealthRequest(
    new Request("http://localhost/runtime-health", { method: "POST" }),
    {
      env: {
        get(name: string) {
          if (name === "SUPABASE_URL") return "http://127.0.0.1:54321";
          if (name === "SUPABASE_SERVICE_ROLE_KEY") return "service-role";
          return undefined;
        },
      },
      verifySession: () =>
        Promise.resolve({
          session: {
            deviceInstallationID: installationID,
            workspaceID,
            memberID,
            role: "creator",
          },
        }),
      createAdminClient: () => ({
        from: () => ({
          select: () => ({
            limit: () => Promise.resolve({ data: [{ id: workspaceID }], error: null }),
          }),
        }),
      }),
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.supabase.ok, true);
  assertEquals(body.gemini.ok, false);
  assertEquals(body.gemini.detail, "gemini_api_key_missing");
});

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
