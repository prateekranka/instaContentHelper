import {
  canonicalJSON,
  generationIntent,
  generationReplayResponse,
  readGenerationReplay,
} from "./generation-idempotency.ts";

function assertEquals(actual: unknown, expected: unknown) {
  if (canonicalJSON(actual) !== canonicalJSON(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

const body = {
  action: "generate_day",
  creator_id: "33333333-3333-4333-8333-333333333333",
  scheduled_date: "2026-10-21",
  day_brief: "A quiet walk",
  idempotency_key: "walk-1",
};
const intent = generationIntent(body);

Deno.test("generation intent ignores transport mode and distinguishes a new brief", () => {
  assertEquals(generationIntent({ ...body, response_mode: "async" }), intent);
  assertEquals(
    generationIntent({ ...body, day_brief: "New brief" }).identity.day_brief,
    "New brief",
  );
  assertEquals(
    canonicalJSON({ a: 1, b: { c: 2, d: 3 } }),
    canonicalJSON({ b: { d: 3, c: 2 }, a: 1 }),
  );
});

Deno.test("invalid keys are rejected", () => {
  for (const key of ["", " \n", null, 3, "a".repeat(201)]) {
    let error: unknown;
    try {
      generationIntent({ ...body, idempotency_key: key });
    } catch (caught) {
      error = caught;
    }
    assertEquals((error as Error)?.message, "invalid_idempotency_key");
  }
});

Deno.test("completed replay returns the stored revision without any writes", async () => {
  const response = await generationReplayResponse({
    from() {
      throw new Error("unexpected write");
    },
  }, {
    id: "run",
    status: "completed",
    request_identity: intent.identity,
    output_snapshot: {
      status: "draft",
      daily_card: { id: "old-revision", title: "Original" },
    },
  }, intent);
  assertEquals((await response.json()).daily_card.id, "old-revision");
});

Deno.test("same key with changed brief conflicts and failed runs never restart", async () => {
  const admin = {
    from() {
      throw new Error("unexpected write");
    },
  };
  const conflict = await generationReplayResponse(admin, {
    request_identity: intent.identity,
  }, generationIntent({ ...body, day_brief: "Changed" }));
  assertEquals(conflict.status, 409);
  const failed = await generationReplayResponse(admin, {
    id: "failed-run",
    status: "failed",
    error_code: "generation_stale",
    request_identity: intent.identity,
  }, intent);
  assertEquals((await failed.json()).status, "failed");
});

Deno.test("run lookup is scoped by workspace, creator, and key", async () => {
  const filters: Record<string, unknown> = {};
  const query = {
    select() {
      return this;
    },
    eq(key: string, value: unknown) {
      filters[key] = value;
      return this;
    },
    maybeSingle() {
      return Promise.resolve({ data: null, error: null });
    },
  };
  assertEquals(
    await readGenerationReplay(
      {
        from(table: string) {
          assertEquals(table, "weekly_generation_runs");
          return query;
        },
      },
      "workspace",
      body.creator_id,
      intent,
    ),
    null,
  );
  assertEquals(filters, {
    workspace_id: "workspace",
    creator_id: body.creator_id,
    idempotency_key: "walk-1",
  });
});

Deno.test("a stale keyed run closes instead of starting another worker", async () => {
  let update: Record<string, unknown> = {};
  const query = {
    update(value: Record<string, unknown>) {
      update = value;
      return this;
    },
    eq() {
      return this;
    },
    select() {
      return this;
    },
    maybeSingle() {
      return Promise.resolve({
        data: {
          id: "run",
          status: update.status,
          error_code: update.error_code,
        },
        error: null,
      });
    },
    then(resolve: (value: unknown) => void) {
      resolve({ error: null });
    },
  };
  const response = await generationReplayResponse({
    from() {
      return query;
    },
  }, {
    id: "run",
    status: "running",
    request_identity: intent.identity,
    updated_at: "2020-01-01T00:00:00Z",
  }, intent);
  assertEquals(update.status, "failed");
  assertEquals((await response.json()).error, "generation_stale");
});
