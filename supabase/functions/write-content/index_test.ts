import {
  handleWriteContentRequest,
  normalizedCreatorProfileUpdate,
} from "./index.ts";

Deno.test("normalizedCreatorProfileUpdate omits adaptive fields from update payload", () => {
  const update = requireUpdate({
    action: "update_creator_profile",
    creator_id: "33333333-3333-4333-8333-333333333333",
    caption_style: "Caption-only edit",
  }, "expected a valid update payload");

  assertEquals(update.caption_style, "Caption-only edit");
  assertEquals("voice_rules" in update, false);
  assertEquals("content_pillars" in update, false);
  assertEquals("taste_example_ids" in update, false);
  assertEquals("production_formats" in update, false);
  assertEquals("on_camera_restrictions" in update, false);
  assertEquals("first_idea_handoff" in update, false);
  assertEquals("onboarding_state" in update, false);
  assertEquals("starting_point" in update, false);
  assertEquals("custom_subjects" in update, false);
  assert(typeof update.updated_at === "string", "expected updated_at");
});

Deno.test("normalizedCreatorProfileUpdate clears text arrays on explicit null or empty", () => {
  const clearedNull = requireUpdate({
    action: "update_creator_profile",
    creator_id: "33333333-3333-4333-8333-333333333333",
    voice_rules: null,
    content_pillars: [],
  }, "expected null-array clear payload");

  assertEquals(clearedNull.voice_rules, []);
  assertEquals(clearedNull.content_pillars, []);

  const clearedEmptyString = requireUpdate({
    action: "update_creator_profile",
    creator_id: "33333333-3333-4333-8333-333333333333",
    never_say: "",
  }, "expected empty-string clear payload");

  assertEquals(clearedEmptyString.never_say, []);
});

Deno.test("normalizedCreatorProfileUpdate clears JSON objects on explicit null", () => {
  const update = requireUpdate({
    action: "update_creator_profile",
    creator_id: "33333333-3333-4333-8333-333333333333",
    on_camera_restrictions: null,
    first_idea_handoff: null,
    language_preferences: null,
  }, "expected JSON clear payload");

  assertEquals(update.on_camera_restrictions, {});
  assertEquals(update.first_idea_handoff, {});
  assertEquals(update.language_preferences, {});
});

Deno.test("normalizedCreatorProfileUpdate preserves explicit adaptive values when present", () => {
  const update = requireUpdate({
    action: "update_creator_profile",
    creator_id: "33333333-3333-4333-8333-333333333333",
    taste_example_ids: ["example-a", "example-b"],
    production_formats: ["reels"],
    on_camera_restrictions: { no_full_face: true },
    onboarding_state: "established",
    starting_point: "already_posting",
  }, "expected adaptive update payload");

  assertEquals(update.taste_example_ids, ["example-a", "example-b"]);
  assertEquals(update.production_formats, ["reels"]);
  assertEquals(update.on_camera_restrictions, { no_full_face: true });
  assertEquals(update.onboarding_state, "established");
  assertEquals(update.starting_point, "already_posting");
});

function requireUpdate(
  body: Parameters<typeof normalizedCreatorProfileUpdate>[0],
  label: string,
): Record<string, unknown> {
  const update = normalizedCreatorProfileUpdate(body);
  if (update === null) {
    throw new Error(`Assertion failed: ${label}`);
  }
  return update;
}

function assert(value: boolean, label: string) {
  if (!value) {
    throw new Error(`Assertion failed: ${label}`);
  }
}

function assertEquals(actual: unknown, expected: unknown) {
  const actualSerialized = typeof actual === "object" && actual !== null
    ? JSON.stringify(actual)
    : actual;
  const expectedSerialized = typeof expected === "object" && expected !== null
    ? JSON.stringify(expected)
    : expected;

  if (actualSerialized !== expectedSerialized) {
    throw new Error(
      `Assertion failed: expected ${JSON.stringify(expected)}, got ${
        JSON.stringify(actual)
      }`,
    );
  }
}

const revisionID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1";
const creatorID = "33333333-3333-4333-8333-333333333333";
const workspaceID = "11111111-1111-4111-8111-111111111111";
const memberID = "22222222-2222-4222-8222-222222222222";
const postedSnapshot = {
  id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
  daily_card_id: revisionID,
  decision: "posted",
  title_snapshot: "Posted title",
  caption_snapshot: "Posted caption",
  decision_at: "2026-10-20T10:00:00+00:00",
};

Deno.test("write-content returns current revision undo with saved text and a new decision time", async () => {
  for (const action of ["complete_today", "upsert_archive_decision"]) {
    const archive = {
      ...postedSnapshot,
      decision: "shot",
      decision_at: "2026-10-20T11:00:00+00:00",
    };
    const response = await decisionRequest(action, "shot", {
      action,
      ...(action === "complete_today"
        ? {
          daily_card: {
            id: revisionID,
            status: "shot",
            decision_at: archive.decision_at,
          },
        }
        : {}),
      archive_entry: archive,
    });
    assertEquals(response.status, 200);
    const body = await response.json();
    assertEquals(body.archive_entry, archive);
    assertEquals(
      body.archive_entry.title_snapshot,
      postedSnapshot.title_snapshot,
    );
    assertEquals(
      body.archive_entry.caption_snapshot,
      postedSnapshot.caption_snapshot,
    );
    assert(
      body.archive_entry.decision_at !== postedSnapshot.decision_at,
      "undo must use a new decision time",
    );
    if (action === "complete_today") {
      assertEquals(body.daily_card.status, "shot");
    }
  }
});

Deno.test("write-content keeps replaced revision conflicts for undo and other changes", async () => {
  for (const action of ["complete_today", "upsert_archive_decision"]) {
    for (
      const error of [
        "posted_revision_immutable",
        "historical_revision_immutable",
      ]
    ) {
      for (
        const decision of [
          "shot",
          "posted",
          "used_backup",
          "saved_for_tomorrow",
          "skipped_intentionally",
        ]
      ) {
        const response = await decisionRequest(action, decision, {
          error,
          status: 409,
        });
        assertEquals(response.status, 409);
        assertEquals(await response.json(), { error });
      }
    }
  }
});

Deno.test("write-content returns the stored replaced posted snapshot on an exact retry", async () => {
  for (const action of ["complete_today", "upsert_archive_decision"]) {
    const response = await decisionRequest(action, "posted", {
      action,
      archive_entry: postedSnapshot,
    });
    assertEquals(response.status, 200);
    assertEquals((await response.json()).archive_entry, postedSnapshot);
  }
});

async function decisionRequest(
  action: string,
  decision: string,
  rpcResult: Record<string, unknown>,
): Promise<Response> {
  const previousFetch = globalThis.fetch;
  const previousURL = Deno.env.get("SUPABASE_URL");
  const previousKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  let rpcCalls = 0;
  Deno.env.set("SUPABASE_URL", "http://creator-loop.invalid");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "local-test-key");
  globalThis.fetch = async (input, init) => {
    const request = new Request(input, init);
    const url = new URL(request.url);
    assertEquals(url.origin, "http://creator-loop.invalid");
    switch (url.pathname) {
      case "/rest/v1/device_installations":
        return Response.json(
          request.method === "PATCH" ? [] : {
            id: "device",
            workspace_id: workspaceID,
            member_id: memberID,
            revoked_at: null,
          },
        );
      case "/rest/v1/members":
        return Response.json({
          id: memberID,
          role: "creator",
          status: "active",
        });
      case "/rest/v1/creators":
        return Response.json({ id: creatorID });
      case "/rest/v1/rpc/write_content": {
        rpcCalls++;
        const { payload } = await request.json();
        assertEquals(payload.action, action);
        assertEquals(payload.daily_card_id, revisionID);
        assertEquals(payload.creator_id, creatorID);
        assertEquals(payload.workspace_id, workspaceID);
        assertEquals(payload.member_id, memberID);
        assertEquals(
          action === "complete_today"
            ? payload.decision.status
            : payload.decision,
          decision,
        );
        return Response.json(rpcResult);
      }
      default:
        throw new Error(`Unexpected test request ${url.pathname}`);
    }
  };
  try {
    const response = await handleWriteContentRequest(
      new Request("http://localhost/write-content", {
        method: "POST",
        headers: { "x-mco-device-token": "local-test-token" },
        body: JSON.stringify({
          action,
          creator_id: creatorID,
          daily_card_id: revisionID,
          archive_date: "2026-10-20",
          decision: action === "complete_today"
            ? {
              status: decision,
              output_line: "Decision",
              has_post_thumbnail: false,
            }
            : decision,
          output_line: "Decision",
          has_post_thumbnail: false,
        }),
      }),
    );
    assertEquals(rpcCalls, 1);
    return response;
  } finally {
    globalThis.fetch = previousFetch;
    for (
      const [name, value] of [["SUPABASE_URL", previousURL], [
        "SUPABASE_SERVICE_ROLE_KEY",
        previousKey,
      ]]
    ) {
      if (value === undefined) Deno.env.delete(name!);
      else Deno.env.set(name!, value);
    }
  }
}
