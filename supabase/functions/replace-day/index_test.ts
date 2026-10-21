import { handleReplaceDayRequest } from "./index.ts";

const workspace = "11111111-1111-4111-8111-111111111111";
const creator = "33333333-3333-4333-8333-333333333333";
const member = "22222222-2222-4222-8222-222222222222";
const planID = "44444444-4444-4444-8444-444444444444";
const cardID = "55555555-5555-4555-8555-555555555555";
const pieceID = "88888888-8888-4888-8888-888888888888";
const runID = "66666666-6666-4666-8666-666666666666";
const date = new Date(Date.now() + 86_400_000).toISOString().slice(0, 10);
const week = new Date(`${date}T00:00:00Z`);
week.setUTCDate(week.getUTCDate() - (week.getUTCDay() + 6) % 7);
const env = {
  get(name: string) {
    return {
      SUPABASE_URL: "http://localhost",
      SUPABASE_SERVICE_ROLE_KEY: "local-key",
      MCO_AI_MOCK: "1",
    }[name];
  },
};

function assertEquals(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

Deno.test("replace-day keeps method and JSON errors stable", async () => {
  assertEquals(
    (await handleReplaceDayRequest(
      new Request("http://localhost", { method: "OPTIONS" }),
    )).status,
    200,
  );
  assertEquals(
    (await handleReplaceDayRequest(
      new Request("http://localhost", { method: "GET" }),
    )).status,
    405,
  );
  assertEquals(
    (await handleReplaceDayRequest(
      new Request("http://localhost", { method: "POST", body: "{" }),
    )).status,
    400,
  );
});

Deno.test("replace-day archives and starts through one RPC, then saves a new revision", async () => {
  const calls: string[] = [];
  const oldCard = {
    id: cardID,
    piece_id: pieceID,
    workspace_id: workspace,
    creator_id: creator,
    weekly_plan_id: planID,
    scheduled_date: date,
    title: "Posted title",
    status: "posted",
    post_instructions: {
      filmed_shots: ["1407e44a-1f70-4b96-8ee2-000000000001"],
    },
  };
  const otherCard = {
    ...oldCard,
    id: "99999999-9999-4999-8999-999999999999",
    piece_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    status: "draft",
  };
  const savedOther = JSON.stringify(otherCard);
  const run: Record<string, unknown> = {};
  let background: Promise<void> | undefined;
  let newCard: Record<string, unknown> | undefined;
  class Query {
    pieceFilter?: unknown;
    constructor(
      readonly table: string,
      private values?: Record<string, unknown>,
    ) {}
    select() {
      return this;
    }
    eq(column: string, value: unknown) {
      if (column === "piece_id") this.pieceFilter = value;
      return this;
    }
    in() {
      return this;
    }
    gte() {
      return this;
    }
    lte() {
      return this;
    }
    is() {
      return this;
    }
    order() {
      return this;
    }
    limit() {
      return this;
    }
    update(values: Record<string, unknown>) {
      this.values = values;
      return this;
    }
    delete() {
      return this;
    }
    insert() {
      return this;
    }
    maybeSingle() {
      const rows = this.rows();
      return Promise.resolve({ data: rows[0] ?? null, error: null });
    }
    single() {
      return this.maybeSingle();
    }
    rows(): Record<string, unknown>[] {
      if (this.values && this.table === "weekly_generation_runs") {
        Object.assign(run, this.values);
      }
      switch (this.table) {
        case "device_installations":
          return [{
            id: "device",
            workspace_id: workspace,
            member_id: member,
            revoked_at: null,
          }];
        case "members":
          return [{
            id: member,
            workspace_id: workspace,
            status: "active",
            role: "creator",
          }];
        case "creators":
          return [{ id: creator, display_name: "Creator" }];
        case "weekly_plans":
          return [{
            id: planID,
            status: "published",
            is_soft_locked: true,
            week_start_date: week.toISOString().slice(0, 10),
          }];
        case "content_pieces":
          return [{
            id: pieceID,
            workspace_id: workspace,
            creator_id: creator,
            scheduled_date: date,
            removed_at: null,
          }];
        case "daily_cards":
          return [newCard ?? oldCard, otherCard].filter((card) =>
            this.pieceFilter === undefined || card.piece_id === this.pieceFilter
          );
        case "weekly_generation_runs":
          return run.id ? [run] : [];
        default:
          return [];
      }
    }
    then<TResult1 = { data: unknown; error: null }, TResult2 = never>(
      resolve?:
        | ((
          value: { data: unknown; error: null },
        ) => TResult1 | PromiseLike<TResult1>)
        | null,
      reject?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
    ): Promise<TResult1 | TResult2> {
      return Promise.resolve({ data: this.rows(), error: null }).then(
        resolve,
        reject,
      );
    }
  }
  const response = await handleReplaceDayRequest(
    new Request("http://localhost/replace-day", {
      method: "POST",
      headers: { "x-mco-device-token": "device-token" },
      body: JSON.stringify({
        creator_id: creator,
        piece_id: pieceID,
        scheduled_date: date,
        daily_card_id: cardID,
        day_brief: "A quiet walk outside",
        idempotency_key: "replace-1",
        response_mode: "async",
      }),
    }),
    {
      env,
      createAdminClient: () => ({
        from(table: string) {
          return new Query(table);
        },
        rpc(name: string, args: Record<string, unknown>) {
          calls.push(name);
          const payload = args.payload as Record<string, unknown>;
          if (name === "replace_day") {
            assertEquals(payload.daily_card_id, cardID);
            assertEquals(payload.piece_id, pieceID);
            oldCard.status = "archived";
            Object.assign(run, {
              id: runID,
              status: "running",
              replaced_daily_card_id: cardID,
              piece_id: pieceID,
            });
            return Promise.resolve({ data: run, error: null });
          }
          if (name === "persist_day_revision") {
            newCard = {
              ...(payload.card as Record<string, unknown>),
              id: "77777777-7777-4777-8777-777777777777",
              scheduled_date: date,
              piece_id: pieceID,
            };
            return Promise.resolve({ data: newCard, error: null });
          }
          throw new Error(`unexpected RPC ${name}`);
        },
      }),
      runInBackground(promise) {
        background = promise;
      },
    },
  );
  assertEquals(response.status, 202);
  assertEquals((await response.json()).piece_id, pieceID);
  await background;
  assertEquals(calls, ["replace_day", "persist_day_revision"]);
  assertEquals(oldCard.title, "Posted title");
  assertEquals(oldCard.post_instructions.filmed_shots, [
    "1407e44a-1f70-4b96-8ee2-000000000001",
  ]);
  assertEquals(newCard?.id === cardID, false);
  assertEquals(run.status, "completed");
  assertEquals(JSON.stringify(otherCard), savedOther);
});
