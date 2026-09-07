import { normalizedCreatorProfileUpdate } from "./index.ts";

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
