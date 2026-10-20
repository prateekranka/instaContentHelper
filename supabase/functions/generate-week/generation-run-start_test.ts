import {
  createDayGenerationRun,
  type DayGenerationRunStartPrepared,
} from "./generation-run-start.ts";
import { generationIntent } from "./generation-idempotency.ts";
function assertEquals(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

const prepared = {
  session: { workspaceID: "workspace" },
  request: {
    creator_id: "33333333-3333-4333-8333-333333333333",
    weekly_plan_id: "plan",
    scheduled_date: "2026-10-21",
  },
  plan: {},
  model: "existing-model",
  inputSnapshot: {},
} as DayGenerationRunStartPrepared;

Deno.test("day run starts through an atomic RPC with a key for legacy callers", async () => {
  let payload: Record<string, unknown> = {};
  const result = await createDayGenerationRun(
    {
      from() {},
      rpc(name: string, args: Record<string, unknown>) {
        assertEquals(name, "start_day_generation");
        payload = args.payload as Record<string, unknown>;
        return Promise.resolve({ data: { id: "run" }, error: null });
      },
    } as never,
    prepared,
    "member",
  );
  assertEquals(result, { run: { id: "run" } });
  assertEquals(typeof payload.idempotency_key, "string");
  assertEquals(payload.member_id, "member");
  assertEquals(payload.creator_id, prepared.request.creator_id);
});

Deno.test("replace day starts through the replacement transaction", async () => {
  const intent = generationIntent({
    action: "replace_day",
    creator_id: prepared.request.creator_id,
    scheduled_date: "2026-10-21",
    day_brief: "New brief",
    idempotency_key: "replace-key",
    daily_card_id: "55555555-5555-4555-8555-555555555555",
  });
  const result = await createDayGenerationRun(
    {
      from() {},
      rpc(name: string, args: Record<string, unknown>) {
        assertEquals(name, "replace_day");
        const payload = args.payload as Record<string, unknown>;
        assertEquals(payload.idempotency_key, "replace-key");
        assertEquals(
          payload.daily_card_id,
          "55555555-5555-4555-8555-555555555555",
        );
        assertEquals(payload.request_identity, intent.identity);
        return Promise.resolve({
          data: {
            id: "new-run",
            replaced_daily_card_id: "55555555-5555-4555-8555-555555555555",
          },
          error: null,
        });
      },
    } as never,
    { ...prepared, generationIntent: intent },
    "member",
  );
  assertEquals("run" in result, true);
});

Deno.test("day run returns stable RPC errors and persistence errors", async () => {
  for (
    const data of [{ error: "idempotency_key_conflict", status: 409 }, null]
  ) {
    const result = await createDayGenerationRun(
      {
        from() {},
        rpc() {
          return Promise.resolve({ data, error: null });
        },
      } as never,
      prepared,
      "member",
    );
    if (!("response" in result)) throw new Error("expected response");
    assertEquals(result.response.status, data ? 409 : 500);
  }
});
