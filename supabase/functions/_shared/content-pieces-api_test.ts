import { handleMakeDayAvailableRequest } from "../make-day-available/index.ts";
import { handleUnpublishDayRequest } from "../unpublish-day/index.ts";
import { handleUpdateReadyDayPackageRequest } from "../update-ready-day-package/index.ts";

const workspaceID = "11111111-1111-4111-8111-111111111111";
const memberID = "22222222-2222-4222-8222-222222222222";
const creatorID = "33333333-3333-4333-8333-333333333333";
const pieceID = "44444444-4444-4444-8444-444444444444";

function assertEquals(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

for (
  const [name, handler] of [
    ["make ready", handleMakeDayAvailableRequest],
    ["unpublish", handleUnpublishDayRequest],
    ["package edit", handleUpdateReadyDayPackageRequest],
  ] as const
) {
  Deno.test(`${name} forwards piece identity and returns piece scope errors`, async () => {
    for (
      const error of [
        null,
        "piece_scope_mismatch",
        "piece_revision_mismatch",
        "piece_removed",
      ]
    ) {
      const query = {
        select() {
          return this;
        },
        eq() {
          return this;
        },
        is() {
          return this;
        },
        update() {
          return this;
        },
        maybeSingle() {
          return Promise.resolve({
            data: {
              id: creatorID,
              workspace_id: workspaceID,
              member_id: memberID,
              role: "owner",
              status: "active",
              revoked_at: null,
            },
            error: null,
          });
        },
        then(resolve: (value: unknown) => void) {
          resolve({ data: null, error: null });
        },
      };
      const response = await handler(
        new Request("http://localhost/piece", {
          method: "POST",
          headers: { "x-mco-device-token": "local" },
          body: JSON.stringify({
            creator_id: creatorID,
            piece_id: pieceID,
            scheduled_date: "2026-10-21",
            package: { caption: "Saved caption" },
          }),
        }),
        {
          env: {
            get: (key: string) =>
              ({
                SUPABASE_URL: "http://127.0.0.1:54321",
                SUPABASE_SERVICE_ROLE_KEY: "local",
              })[key],
          },
          createAdminClient: () =>
            ({
              from() {
                return query;
              },
              rpc(_name: string, args: Record<string, unknown>) {
                const payload = args.payload as Record<string, unknown>;
                assertEquals(payload.piece_id, pieceID);
                assertEquals(payload.workspace_id, workspaceID);
                assertEquals(payload.scheduled_date, "2026-10-21");
                return Promise.resolve({
                  data: error ? { error, status: 409 } : {
                    piece_id: pieceID,
                    daily_card_id: "revision",
                    scheduled_date: "2026-10-21",
                    status: "published",
                  },
                  error: null,
                });
              },
            }) as never,
        },
      );
      assertEquals(response.status, error ? 409 : 200);
      const body = await response.json();
      assertEquals(error ? body.error : body.piece_id, error ?? pieceID);
    }
  });
}
