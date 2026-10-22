import { handleMovePieceRequest } from "./index.ts";

const workspace = "11111111-1111-4111-8111-111111111111";
const creator = "33333333-3333-4333-8333-333333333333";
const piece = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1";
const valid = {
  creator_id: creator,
  piece_id: piece,
  scheduled_date: "2026-10-22",
  target_scheduled_date: "2026-10-24",
  idempotency_key: "move-one",
};
const success = {
  piece_id: piece,
  source_scheduled_date: valid.scheduled_date,
  scheduled_date: valid.target_scheduled_date,
  position: 2,
  affected_pieces: [],
  replayed: false,
};

async function invoke(
  body: unknown = valid,
  options: {
    role?: string;
    result?: unknown;
    transport?: boolean;
    token?: boolean;
    creator?: boolean;
    method?: string;
  } = {},
) {
  let calls = 0;
  let payload: Record<string, unknown> | undefined;
  const response = await handleMovePieceRequest(
    new Request("http://localhost/move-piece", {
      method: options.method ?? "POST",
      headers: options.token === false
        ? {}
        : { "x-mco-device-token": "device-token" },
      ...((options.method ?? "POST") === "POST"
        ? { body: JSON.stringify(body) }
        : {}),
    }),
    {
      env: {
        get: (key) =>
          ({
            SUPABASE_URL: "http://127.0.0.1:54321",
            SUPABASE_SERVICE_ROLE_KEY: "local-key",
          })[key],
      },
      createAdminClient: () => ({
        from(table: string) {
          const query = {
            select: (_value: string) => query,
            eq: (_key: string, _value: unknown) => query,
            is: (_key: string, _value: unknown) => query,
            update: (_value: unknown) => query,
            then: (resolve: (value: unknown) => void) =>
              resolve({ data: null, error: null }),
            maybeSingle: () =>
              Promise.resolve({
                data: table === "device_installations"
                  ? { id: piece, workspace_id: workspace, member_id: piece }
                  : table === "members"
                  ? {
                    id: piece,
                    workspace_id: workspace,
                    role: options.role ?? "creator",
                  }
                  : options.creator === false
                  ? null
                  : { id: creator },
                error: null,
              }),
          };
          return query;
        },
        rpc(_name: string, args: Record<string, unknown>) {
          if (_name !== "move_content_piece") throw new Error("wrong RPC");
          calls += 1;
          payload = args.payload as Record<string, unknown>;
          return Promise.resolve({
            data: options.result ?? success,
            error: options.transport ? { message: "unavailable" } : null,
          });
        },
      }),
    },
  );
  return {
    status: response.status,
    body: await response.json(),
    calls,
    payload,
  };
}
function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
  }
}
Deno.test("move piece supplies authenticated scope and returns append position and replay state", async () => {
  const result = await invoke({ ...valid, workspace_id: piece });
  equal(result.status, 200);
  equal(result.body, success);
  equal(result.payload?.workspace_id, workspace);
  equal(result.payload?.piece_id, piece);
  equal(result.payload?.target_scheduled_date, valid.target_scheduled_date);
  equal(result.payload?.idempotency_key, "move-one");
  equal(result.calls, 1);
  equal(
    (await invoke(valid, { result: { ...success, replayed: true } })).body
      .replayed,
    true,
  );
});
for (
  const [body, code] of [
    [null, "invalid_move_piece_payload"],
    [[], "invalid_move_piece_payload"],
    [{ ...valid, piece_id: "bad" }, "invalid_piece_id"],
    [{ ...valid, scheduled_date: "2026-02-30" }, "invalid_move_piece_payload"],
    [
      { ...valid, target_scheduled_date: "tomorrow" },
      "invalid_move_piece_payload",
    ],
    [{ ...valid, idempotency_key: " " }, "invalid_move_piece_payload"],
    [
      { ...valid, idempotency_key: "x".repeat(201) },
      "invalid_move_piece_payload",
    ],
    [{ ...valid, creator_id: 1 }, "invalid_move_piece_payload"],
  ] as const
) {
  Deno.test(`move piece rejects invalid input: ${JSON.stringify(body)}`, async () => {
    const result = await invoke(body);
    equal(result.status, 400);
    equal(result.body.error, code);
    equal(result.calls, 0);
  });
}
for (
  const [code, status] of [
    ["piece_not_found", 404],
    ["piece_removed", 409],
    ["piece_scope_mismatch", 409],
    ["piece_date_conflict", 409],
    ["piece_generation_running", 409],
    ["idempotency_key_conflict", 409],
  ] as const
) {
  Deno.test(`move piece forwards ${code}`, async () => {
    const result = await invoke(valid, { result: { error: code, status } });
    equal(result.status, status);
    equal(result.body.error, code);
  });
}
Deno.test("move piece rejects unauthenticated, scout, and missing creator requests", async () => {
  equal((await invoke(valid, { token: false })).status, 401);
  equal((await invoke(valid, { role: "scout" })).status, 403);
  equal((await invoke(valid, { creator: false })).status, 404);
  equal((await invoke(valid, { method: "GET" })).status, 405);
});
Deno.test("move piece maps persistence failures", async () => {
  equal(
    (await invoke(valid, { transport: true })).body.error,
    "move_piece_failed",
  );
});
