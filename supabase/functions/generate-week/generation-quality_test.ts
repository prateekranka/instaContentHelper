import {
  containsInstructorEnding,
  containsInstructorPhrasing,
  countExplicitSaveCTAs,
  scoreGeneratedDayOutputQuality,
  scoreGeneratedWeekOutputQuality,
} from "./generation-quality.ts";
import type {
  GeneratedDailyCard,
  GeneratedDayOutput,
  GeneratedWeekOutput,
  GenerationInputSnapshot,
} from "./generation.ts";

Deno.test("containsInstructorPhrasing detects banned phrasing case-insensitively", () => {
  assertEquals(
    containsInstructorPhrasing("DO THIS EXERCISE slowly"),
    true,
    "should detect uppercase 'DO THIS EXERCISE'",
  );
  assertEquals(
    containsInstructorPhrasing("Try This Workout after lunch"),
    true,
    "should detect mixed-case 'Try This Workout'",
  );
  assertEquals(
    containsInstructorPhrasing("Your Client asked about form"),
    true,
    "should detect mixed-case 'Your Client'",
  );
});

Deno.test("containsInstructorPhrasing does not flag normal first-person creator language", () => {
  assertEquals(
    containsInstructorPhrasing("I had to fix my form on the sled push today"),
    false,
    "first-person 'fix my form' should be allowed",
  );
  assertEquals(
    containsInstructorPhrasing("worked with a new brand client today"),
    false,
    "brand-collab 'client' should be allowed",
  );
  assertEquals(
    containsInstructorPhrasing(
      "I noticed my shoulders felt tighter after rest",
    ),
    false,
    "ordinary first-person observation should be allowed",
  );
});

Deno.test("containsInstructorEnding detects banned endings case-insensitively", () => {
  assertEquals(
    containsInstructorEnding("JUST START with one light set."),
    true,
    "should detect uppercase 'JUST START'",
  );
  assertEquals(
    containsInstructorEnding("Remember, The Real Win is showing up."),
    true,
    "should detect mixed-case 'The Real Win'",
  );
  assertEquals(
    containsInstructorEnding("You Got This. Keep going."),
    true,
    "should detect mixed-case 'You Got This'",
  );
});

Deno.test("containsInstructorEnding does not flag an ordinary observation or question", () => {
  assertEquals(
    containsInstructorEnding("I noticed the sled felt heavier today"),
    false,
    "ordinary observation should be allowed",
  );
  assertEquals(
    containsInstructorEnding("What felt different in your warm-up today?"),
    false,
    "ordinary question should be allowed",
  );
});

Deno.test("countExplicitSaveCTAs counts a card only once when several fields contain a save CTA", () => {
  assertEquals(
    countExplicitSaveCTAs([
      qualityCard({
        cta: "Save this for your next session.",
        script: "Also says Save this reel if it helps.",
        caption: "Save this post for later.",
        on_screen_text: ["Save this to your notes"],
      }),
    ]),
    1,
    "multiple save CTAs on one card should count once",
  );
});

Deno.test("countExplicitSaveCTAs detects supported CTA forms across audience-facing fields", () => {
  assertEquals(
    countExplicitSaveCTAs([
      qualityCard({ cta: "Save this for your next gym day." }),
      qualityCard({ script: "A script that says Save this reel if useful." }),
      qualityCard({ caption: "Save this post when you need a reset." }),
      qualityCard({
        backup_story: "Save this to your recovery notes.",
      }),
      qualityCard({
        backup_caption_only: "Save this for a quiet morning.",
      }),
      qualityCard({
        caption_backup_detail: "Save this for later.",
      }),
      qualityCard({
        on_screen_text: ["Save this for later"],
      }),
    ]),
    7,
    "should detect save CTAs in cta, script, captions, backups, and on-screen text",
  );
});

Deno.test("countExplicitSaveCTAs does not count ordinary save phrasing", () => {
  assertEquals(
    countExplicitSaveCTAs([
      qualityCard({
        cta: "Share your morning routine!",
        script: "This will save time in the morning.",
        caption: "I saved my breakfast for later.",
        on_screen_text: ["Save time", "Morning reset"],
        backup_story: "I save this kind of energy for later.",
      }),
    ]),
    0,
    "ordinary 'save time' / 'saved my breakfast' phrasing should not count",
  );
});

Deno.test("quality scoring counts pillars, source references, instructor phrases, and instructor endings for week and day", () => {
  const input = emptyInput();
  const weekCards = [
    qualityCard({
      content_pillar: "gym",
      script: "Do this exercise before the warm-up feels rushed.",
      source_reference_ids: ["ref-1", "ref-2"],
    }),
    qualityCard({
      content_pillar: "lifestyle",
      caption: "Remember, the real win is showing up.",
      source_reference_ids: ["ref-3"],
    }),
    qualityCard({
      content_pillar: "eating",
      hook: "I noticed my breakfast felt steadier today.",
      source_reference_ids: [],
    }),
    qualityCard({
      content_pillar: "gym",
      title: "Same gym pillar again",
      source_reference_ids: [],
    }),
  ];

  const weekMetrics = scoreGeneratedWeekOutputQuality(
    input,
    {
      strategy_summary: "Week strategy",
      warnings: [],
      assumptions: [],
      daily_cards: weekCards,
      idea_bank: [],
      source_summary: "Sources",
    } satisfies GeneratedWeekOutput,
  );

  assertEquals(weekMetrics.pillar_count, 3);
  assertEquals(weekMetrics.instructor_phrase_count, 1);
  assertEquals(weekMetrics.instructor_ending_count, 1);
  assertEquals(weekMetrics.source_reference_link_count, 3);
  assertEquals(weekMetrics.cards_with_source_reference_count, 2);
  assertEquals(weekMetrics.version, "instagram_content_quality_v2");
  assert(
    typeof weekMetrics.score === "number" &&
      weekMetrics.score >= 0 &&
      weekMetrics.score <= 100,
    "week quality score should be a 0-100 number",
  );

  const dayCard = qualityCard({
    content_pillar: "recovery",
    script: "Try this workout after a long travel day. You got this.",
    source_reference_ids: ["ref-day-1"],
  });
  const dayMetrics = scoreGeneratedDayOutputQuality(
    input,
    {
      strategy_note: "Day strategy",
      warnings: [],
      assumptions: [],
      daily_card: dayCard,
      idea_bank: [],
      source_summary: "Day sources",
    } satisfies GeneratedDayOutput,
    "2026-06-08",
  );

  assertEquals(dayMetrics.pillar_count, 1);
  assertEquals(dayMetrics.instructor_phrase_count, 1);
  assertEquals(dayMetrics.instructor_ending_count, 1);
  assertEquals(dayMetrics.source_reference_link_count, 1);
  assertEquals(dayMetrics.cards_with_source_reference_count, 1);
  assertEquals(dayMetrics.version, "instagram_content_quality_v2");
  assert(
    typeof dayMetrics.score === "number" &&
      dayMetrics.score >= 0 &&
      dayMetrics.score <= 100,
    "day quality score should be a 0-100 number",
  );
});

function emptyInput(): GenerationInputSnapshot {
  return {
    creator_id: "creator-1",
    week_start_date: "2026-06-08",
    creator_profile: null,
    weekly_setup: null,
    confirmed_references: [],
    reference_extractions: [],
    recent_archive: [],
    idea_bank: [],
    patterns: [],
    trends: [],
    audio_options: [],
    brand_briefs: [],
    key_moments: [],
  };
}

function qualityCard(
  overrides: Partial<GeneratedDailyCard> = {},
): GeneratedDailyCard {
  return {
    scheduled_date: "2026-06-08",
    format: "Reel",
    primary_surface: "Instagram Reels",
    duration_seconds: 18,
    title: "A quiet morning observation",
    hook: "What changed after I slowed down?",
    weekly_brief_anchor: "Keep the week grounded in lived routine.",
    brief_alignment: "Aligned to the weekly brief.",
    brief_context_tags: ["routine"],
    why_today: "Today fits a light shoot.",
    growth_job: "Build trust with a specific detail.",
    save_share_reason: "Useful for a later reset.",
    content_pillar: "lifestyle",
    shootability: "easy",
    estimated_shoot_minutes: 10,
    energy_required: "low",
    language_mode: "English",
    scene_list: [],
    shot_timeline: [],
    script: "I noticed the room felt quieter after the kids left.",
    voiceover_timeline: [],
    no_voiceover_version: "",
    silent_version_timeline: [],
    on_screen_text: [],
    on_screen_text_timeline: [],
    caption: "A small lived detail from today.",
    cta: "What stood out for you?",
    hashtags: [],
    cover_text: "",
    post_instructions: "",
    brand_event_notes: "",
    backup_story: "",
    backup_story_detail: [],
    backup_caption_only: "",
    caption_backup_detail: "",
    audio_option_notes: "",
    creator_fit_score: 90,
    risk_notes: [],
    assumptions: [],
    source_note: "",
    source_reference_ids: [],
    ...overrides,
  };
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
