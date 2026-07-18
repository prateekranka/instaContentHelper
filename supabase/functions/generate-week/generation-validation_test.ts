import {
  GenerateWeekValidationError,
  makeMockGeneratedWeek,
} from "./generation.ts";
import {
  parseGeneratedDayJSON,
  parseGeneratedWeekJSON,
  validateGeneratedDayOutput,
  validateGeneratedWeek,
} from "./generation-validation.ts";
import type { GenerationInputSnapshot } from "./generation.ts";

Deno.test("parseGeneratedWeekJSON accepts markdown-fenced valid JSON", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  const fenced = "```json\n" + JSON.stringify(generated) + "\n```";
  const parsed = parseGeneratedWeekJSON(fenced, "2026-06-08");
  assertEquals(parsed.daily_cards.length, 7);
});

Deno.test("parseGeneratedDayJSON accepts a valid daily card payload", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  const card = generated.daily_cards[2];
  const parsed = parseGeneratedDayJSON(
    JSON.stringify({
      strategy_note: "Day strategy",
      warnings: [],
      assumptions: [],
      daily_card: card,
      idea_bank: [],
      source_summary: "Sources",
    }),
    card.scheduled_date,
    2,
  );
  assertEquals(parsed.daily_card.scheduled_date, card.scheduled_date);
  assertEquals(parsed.daily_card.content_pillar, card.content_pillar);
});

Deno.test("GenerateWeekValidationError identity is preserved through generation re-export", () => {
  try {
    parseGeneratedWeekJSON("{", "2026-06-08");
  } catch (error) {
    assert(
      error instanceof GenerateWeekValidationError,
      "should be validation error class",
    );
    assertEquals(
      (error as GenerateWeekValidationError).code,
      "invalid_ai_json",
    );
    return;
  }
  throw new Error("expected parse failure");
});

Deno.test("per-day validator rejects weekday language that conflicts with scheduled date", () => {
  const card = {
    ...makeMockGeneratedWeek(fixtureInput()).daily_cards[0],
    scheduled_date: "2026-06-21",
    why_today: "Monday is the ideal day to restart the gym routine.",
    brief_alignment:
      "This uses Monday as a practical re-entry day after travel.",
  };

  assertThrowsGenerationCode(
    () => validateGeneratedDayOutput({ daily_card: card }, "2026-06-21", 0),
    "invalid_generated_week",
  );
});

Deno.test("validator rejects malformed AI JSON", () => {
  assertThrowsGenerationCode(
    () => parseGeneratedWeekJSON("{", "2026-06-08"),
    "invalid_ai_json",
  );
});

Deno.test("validator rejects fewer or more than seven cards", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  const sixCards = {
    ...generated,
    daily_cards: generated.daily_cards.slice(0, 6),
  };
  const eightCards = {
    ...generated,
    daily_cards: [...generated.daily_cards, generated.daily_cards[0]],
  };

  assertThrowsGenerationCode(
    () => validateGeneratedWeek(sixCards, "2026-06-08"),
    "invalid_generated_week",
  );
  assertThrowsGenerationCode(
    () => validateGeneratedWeek(eightCards, "2026-06-08"),
    "invalid_generated_week",
  );
});

Deno.test("validator rejects dates outside requested week", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  generated.daily_cards[3] = {
    ...generated.daily_cards[3],
    scheduled_date: "2026-06-20",
  };

  assertThrowsGenerationCode(
    () => validateGeneratedWeek(generated, "2026-06-08"),
    "invalid_generated_week",
  );
});

Deno.test("validator normalizes numeric scene durations from JSON-mode providers", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  generated.daily_cards[0] = {
    ...generated.daily_cards[0],
    scene_list: [{
      number: 1,
      title: "Numeric duration scene",
      duration: 15,
      symbol: "timer",
    } as never],
  };

  const validated = validateGeneratedWeek(generated, "2026-06-08");
  assertEquals(validated.daily_cards[0].scene_list[0].duration, "15 sec");
});

Deno.test("validator rejects missing timeline details and invalid timestamp strings", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  generated.daily_cards[0] = {
    ...generated.daily_cards[0],
    shot_timeline: [{
      timestamp: "first three seconds",
      detail: "Show the gym bag.",
    }],
  };

  assertThrowsGenerationCode(
    () => validateGeneratedWeek(generated, "2026-06-08"),
    "invalid_generated_week",
  );
});

Deno.test("validator rejects placeholder production copy", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  generated.daily_cards[0] = {
    ...generated.daily_cards[0],
    caption_backup_detail: "TBD",
  };

  assertThrowsGenerationCode(
    () => validateGeneratedWeek(generated, "2026-06-08"),
    "invalid_generated_week",
  );
});

Deno.test("validator rejects missing weekly brief evidence", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  generated.daily_cards[0] = {
    ...generated.daily_cards[0],
    weekly_brief_anchor: "",
    brief_context_tags: [],
  };

  assertThrowsGenerationCode(
    () => validateGeneratedWeek(generated, "2026-06-08"),
    "invalid_generated_week",
  );
});

Deno.test("validator rejects a content_pillar outside the four pillars", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  generated.daily_cards[0] = {
    ...generated.daily_cards[0],
    content_pillar: "upper-body cue",
  };

  assertThrowsGenerationCode(
    () => validateGeneratedWeek(generated, "2026-06-08"),
    "invalid_generated_week",
  );
});

Deno.test("validator normalizes legacy pillar aliases to the four pillars", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  generated.daily_cards[0] = {
    ...generated.daily_cards[0],
    content_pillar: "training",
  };
  generated.daily_cards[1] = {
    ...generated.daily_cards[1],
    content_pillar: "Healthy Eating",
  };

  const validated = validateGeneratedWeek(generated, "2026-06-08");
  assertEquals(validated.daily_cards[0].content_pillar, "gym");
  assertEquals(validated.daily_cards[1].content_pillar, "eating");
});

Deno.test("validator rejects a week with too many gym-primary days", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  // Mock week has gym x1, lifestyle x3, recovery x2, eating x1. Force 5 gym.
  generated.daily_cards.forEach((card, index) => {
    if (index < 5) {
      generated.daily_cards[index] = { ...card, content_pillar: "gym" };
    }
  });

  assertThrowsGenerationCode(
    () => validateGeneratedWeek(generated, "2026-06-08"),
    "invalid_generated_week",
  );
});

Deno.test("validator allows a gym-heavy week when the brief narrows scope", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  generated.daily_cards.forEach((card, index) => {
    if (index < 5) {
      generated.daily_cards[index] = { ...card, content_pillar: "gym" };
    }
  });
  const narrowBrief = {
    ...generated,
    strategy_summary:
      "This week is a gym focus block. Five gym-primary days per the brief.",
  };

  // Should NOT throw because the brief explicitly narrows scope.
  const validated = validateGeneratedWeek(narrowBrief, "2026-06-08");
  assertEquals(validated.daily_cards.length, 7);
});

Deno.test("validator rejects instructor phrasing like upper body cue", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  generated.daily_cards[0] = {
    ...generated.daily_cards[0],
    title: "Upper body cue for your next session",
    hook: "Try this upper body cue today.",
  };

  assertThrowsGenerationCode(
    () => validateGeneratedWeek(generated, "2026-06-08"),
    "invalid_generated_week",
  );
});

Deno.test("validator rejects coach language mentioning clients", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  generated.daily_cards[2] = {
    ...generated.daily_cards[2],
    caption: "My clients always ask me how to fix this.",
  };

  assertThrowsGenerationCode(
    () => validateGeneratedWeek(generated, "2026-06-08"),
    "invalid_generated_week",
  );
});

Deno.test("validator rejects instructor phrasing in backup story copy", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  generated.daily_cards[1] = {
    ...generated.daily_cards[1],
    backup_story: "Use this upper body cue in a quick story instead.",
  };

  assertThrowsGenerationCode(
    () => validateGeneratedWeek(generated, "2026-06-08"),
    "invalid_generated_week",
  );
});

Deno.test("validator requires at least 3 of 4 pillars across the week", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  // Collapse every day to only gym + lifestyle (2 distinct pillars).
  generated.daily_cards.forEach((card, index) => {
    generated.daily_cards[index] = {
      ...card,
      content_pillar: index < 4 ? "gym" : "lifestyle",
    };
  });

  assertThrowsGenerationCode(
    () => validateGeneratedWeek(generated, "2026-06-08"),
    "invalid_generated_week",
  );
});

Deno.test("mock generation week satisfies four-pillar balance", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  const validated = validateGeneratedWeek(generated, "2026-06-08");
  const pillars = new Set(validated.daily_cards.map((c) => c.content_pillar));
  const gymDays =
    validated.daily_cards.filter((c) => c.content_pillar === "gym").length;

  assert(pillars.size >= 3, "mock week should cover at least 3 pillars");
  assert(gymDays <= 2, "mock week should not exceed the gym-primary cap of 2");
});

Deno.test("validator rejects cards containing banned instructor endings", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  generated.daily_cards[0] = {
    ...generated.daily_cards[0],
    script:
      "Today was tough. But just start. One set, then the next. You got this.",
  };

  assertThrowsGenerationCode(
    () => validateGeneratedWeek(generated, "2026-06-08"),
    "invalid_generated_week",
  );
});

Deno.test("validator rejects cards with 'the real win' as instructor ending", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  generated.daily_cards[1] = {
    ...generated.daily_cards[1],
    caption: "Remember, the real win is just showing up for yourself.",
  };

  assertThrowsGenerationCode(
    () => validateGeneratedWeek(generated, "2026-06-08"),
    "invalid_generated_week",
  );
});

// ── CTA count validation: reject > 2 save CTAs, accept ≤ 2 ──

Deno.test("validator rejects week with more than 2 explicit save CTAs", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  generated.daily_cards[0] = {
    ...generated.daily_cards[0],
    cta: "Save this for your next gym day.",
    script: "A first-person gym observation with an earned save.",
    caption: "Save this for your next session.",
  };
  generated.daily_cards[1] = {
    ...generated.daily_cards[1],
    cta: "Save this for leg day.",
    script: "A lower-body observation.",
  };
  generated.daily_cards[2] = {
    ...generated.daily_cards[2],
    cta: "Save this for your recovery routine.",
    script: "A recovery day reflection.",
  };
  // That's 3 save CTAs (indices 0, 1, 2) — should reject.

  assertThrowsGenerationCode(
    () => validateGeneratedWeek(generated, "2026-06-08"),
    "invalid_generated_week",
  );
});

Deno.test("validator accepts week with exactly 2 save CTAs", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  generated.daily_cards[0] = {
    ...generated.daily_cards[0],
    cta: "Save this for your next gym day.",
    script: "A training-led Monday observation.",
    caption: "Practical gym content with a natural save trigger.",
  };
  generated.daily_cards[2] = {
    ...generated.daily_cards[2],
    cta: "Save this for your active recovery.",
    script: "Wednesday training observation with save.",
    caption: "Save this recovery cue.",
  };
  // All other cards use earned questions or punchlines (already set in mock).

  const validated = validateGeneratedWeek(generated, "2026-06-08");
  assertEquals(validated.daily_cards.length, 7);
});

Deno.test("validator does not reject ordinary uses of 'save' or 'tell' in captions or scripts", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  // Monday: save CTA (eligible)
  generated.daily_cards[0] = {
    ...generated.daily_cards[0],
    cta: "Save this for your restart day.",
    caption: "I save this kind of energy for the moments that matter.",
  };
  // Tuesday: ordinary "tell" in caption, no save CTA
  generated.daily_cards[1] = {
    ...generated.daily_cards[1],
    cta: "What's your go-to lower-body cue?",
    caption: "She didn't tell me the gym was closed, but I figured it out.",
  };
  // Wednesday: save CTA (eligible)
  generated.daily_cards[2] = {
    ...generated.daily_cards[2],
    cta: "Save this for an active recovery day.",
    caption: "Save this for when you need a quick reset.",
  };

  const validated = validateGeneratedWeek(generated, "2026-06-08");
  assertEquals(validated.daily_cards.length, 7);
});

Deno.test("validator continues to enforce four-pillar contract after all corrective changes", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  const validated = validateGeneratedWeek(generated, "2026-06-08");

  const pillars = new Set(validated.daily_cards.map((c) => c.content_pillar));
  assert(pillars.has("gym"), "gym pillar must be present");
  assert(pillars.has("lifestyle"), "lifestyle pillar must be present");
  assert(pillars.size >= 3, "at least 3 of 4 pillars must be represented");

  const gymDays =
    validated.daily_cards.filter((c) => c.content_pillar === "gym").length;
  assert(gymDays <= 2, `gym days (${gymDays}) must not exceed cap of 2`);
});

// ── Regenerate-day guidance + short-caption contract ──

function fixtureInput(): GenerationInputSnapshot {
  return {
    creator_id: "33333333-3333-4333-8333-333333333333",
    week_start_date: "2026-06-08",
    creator_profile: {
      display_name: "Creator",
      positioning: "Lifestyle creator after 60",
      never_say: ["weight talk", "politics"],
    },
    weekly_setup: {
      id: "77777777-7777-4777-8777-777777777771",
      location: "Bombay",
      notes:
        "Weekly brief: in Bombay this week, back to gym after travel, and recording a podcast. Use these week-specific facts ahead of older stored context.",
    },
    confirmed_references: [
      {
        id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
        source_type: "reel_link",
        manual_notes: "Confirmed towel transition",
      },
    ],
    reference_extractions: [
      {
        id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1",
        source_reference_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
        extraction_kind: "pattern",
        extracted_payload: { summary: "hook-led sock transition" },
      },
    ],
    recent_archive: [
      {
        archive_date: "2026-06-04",
        decision: "used_backup",
        output_line: "Used backup story",
      },
      {
        archive_date: "2026-05-28",
        decision: "published",
        output_line: "Older New Jersey HYROX race recovery walking card.",
      },
    ],
    idea_bank: [
      {
        title: "Quiet Sunday family walk",
        summary: "Shootable family moment.",
      },
    ],
    patterns: [
      {
        label: "Stored context from earlier block",
        notes:
          "Creator is in New Jersey, training for HYROX, and needs race recovery content.",
      },
    ],
    trends: [
      {
        title: "Race recovery walk format",
        notes: "Use only when current weekly brief still supports HYROX.",
      },
    ],
    audio_options: [],
    brand_briefs: [
      {
        brand_name: "Brand hydration reminder",
        deliverable: "One Reel",
      },
    ],
    key_moments: [
      {
        name: "Sunday 10K",
        moment_date: "2026-06-14",
      },
    ],
  };
}

function assertThrowsGenerationCode(
  operation: () => unknown,
  code: string,
): void {
  try {
    operation();
  } catch (error) {
    assert(
      error instanceof Error &&
        "code" in error &&
        (error as { code: string }).code === code,
      `Expected ${code}, got ${String(error)}`,
    );
    return;
  }

  throw new Error(`Expected ${code}`);
}

function assert(
  condition: unknown,
  message = "Assertion failed",
): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  if (!Object.is(actual, expected)) {
    throw new Error(
      message ??
        `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
