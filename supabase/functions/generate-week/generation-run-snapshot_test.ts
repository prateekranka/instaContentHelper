import {
  combineNonBlankStrings,
  initialSingleDayGenerationSnapshot,
  isDayDraftResponseSnapshot,
  isDraftResponseSnapshot,
  makeGeneratedWeekOutputFromCompletedDays,
  normalizeSingleDayGenerationSnapshot,
  normalizeStoredInputSnapshot,
  requestFromRun,
  uniqueNonBlankStrings,
} from "./generation-run-snapshot.ts";
import type {
  GenerationRunStatusRecord,
  SingleDayGenerationSnapshot,
} from "./generation-run-snapshot.ts";
import { initialPerDayGenerationSnapshot } from "./generation-status.ts";
import type {
  GeneratedDailyCard,
  GeneratedDayOutput,
  GeneratedIdea,
  RegenerateDayRequest,
} from "./generation.ts";

const NOW_ISO = "2026-06-15T12:00:00.000Z";
const CREATOR_ID = "33333333-3333-4333-8333-333333333333";
const GENERATION_ID = "55555555-5555-4555-8555-555555555555";
const WEEKLY_PLAN_ID = "66666666-6666-4666-8666-666666666666";
const WEEK_START = "2026-06-08";
const SCHEDULED_DATE = "2026-06-10";

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  if (left !== right) {
    throw new Error(message ?? `Expected ${right}, got ${left}`);
  }
}

function assert(
  condition: unknown,
  message = "Assertion failed",
): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

function minimalDailyCard(scheduledDate: string): GeneratedDailyCard {
  return {
    scheduled_date: scheduledDate,
    format: "Reel",
    primary_surface: "instagram",
    duration_seconds: 30,
    title: `Day ${scheduledDate}`,
    hook: "hook",
    weekly_brief_anchor: "anchor",
    brief_alignment: "aligned",
    brief_context_tags: [],
    why_today: "why",
    growth_job: "growth",
    save_share_reason: "reason",
    content_pillar: "lifestyle",
    shootability: "easy",
    estimated_shoot_minutes: 20,
    energy_required: "low",
    language_mode: "english",
    scene_list: [],
    shot_timeline: [],
    script: "script",
    voiceover_timeline: [],
    no_voiceover_version: "silent",
    silent_version_timeline: [],
    on_screen_text: [],
    on_screen_text_timeline: [],
    caption: "caption",
    cta: "cta",
    hashtags: [],
    cover_text: "cover",
    post_instructions: "post",
    brand_event_notes: "",
    backup_story: "backup",
    backup_story_detail: [],
    backup_caption_only: "backup caption",
    caption_backup_detail: "detail",
    audio_option_notes: "",
    creator_fit_score: 0.8,
    risk_notes: [],
    assumptions: [],
    source_note: "source",
    source_reference_ids: [],
  };
}

function dayOutput(
  scheduledDate: string,
  overrides: Partial<GeneratedDayOutput> = {},
): GeneratedDayOutput {
  return {
    strategy_note: `note-${scheduledDate}`,
    warnings: [],
    assumptions: [],
    daily_card: minimalDailyCard(scheduledDate),
    idea_bank: [],
    source_summary: `source-${scheduledDate}`,
    ...overrides,
  };
}

function regenerateDayRequest(
  overrides: Partial<RegenerateDayRequest> = {},
): RegenerateDayRequest {
  return {
    action: "regenerate_day",
    creator_id: CREATOR_ID,
    weekly_plan_id: WEEKLY_PLAN_ID,
    scheduled_date: SCHEDULED_DATE,
    preserve_manual_edits: true,
    mock: false,
    response_mode: "async",
    ...overrides,
  };
}

function runRecord(
  overrides: Partial<GenerationRunStatusRecord> = {},
): GenerationRunStatusRecord {
  return {
    id: GENERATION_ID,
    workspace_id: "11111111-1111-4111-8111-111111111111",
    creator_id: CREATOR_ID,
    target_scheduled_date: SCHEDULED_DATE,
    ...overrides,
  };
}

Deno.test("isDraftResponseSnapshot accepts valid draft snapshots", () => {
  const snapshot = {
    generation_id: GENERATION_ID,
    weekly_plan_id: WEEKLY_PLAN_ID,
    status: "draft",
    strategy_summary: "summary",
    warnings: [],
    assumptions: [],
    daily_cards: [],
    idea_bank: [],
    source_summary: "source",
    generated_at: NOW_ISO,
  };
  assert(isDraftResponseSnapshot(snapshot));
});

Deno.test("isDraftResponseSnapshot rejects malformed draft snapshots", () => {
  assertEquals(isDraftResponseSnapshot(null), false);
  assertEquals(isDraftResponseSnapshot({ status: "draft" }), false);
  assertEquals(
    isDraftResponseSnapshot({
      generation_id: "not-a-uuid",
      weekly_plan_id: WEEKLY_PLAN_ID,
      status: "draft",
      daily_cards: [],
      idea_bank: [],
    }),
    false,
  );
  assertEquals(
    isDraftResponseSnapshot({
      generation_id: GENERATION_ID,
      weekly_plan_id: WEEKLY_PLAN_ID,
      status: "running",
      daily_cards: [],
      idea_bank: [],
    }),
    false,
  );
  assertEquals(
    isDraftResponseSnapshot({
      generation_id: GENERATION_ID,
      weekly_plan_id: WEEKLY_PLAN_ID,
      status: "draft",
      idea_bank: [],
    }),
    false,
  );
});

Deno.test("isDayDraftResponseSnapshot accepts valid single-day draft snapshots", () => {
  const snapshot = {
    generation_id: GENERATION_ID,
    weekly_plan_id: WEEKLY_PLAN_ID,
    status: "draft",
    target_scheduled_date: SCHEDULED_DATE,
    daily_card: minimalDailyCard(SCHEDULED_DATE),
    warnings: [],
    assumptions: [],
    source_summary: "source",
    generated_at: NOW_ISO,
  };
  assert(isDayDraftResponseSnapshot(snapshot));
});

Deno.test("isDayDraftResponseSnapshot rejects malformed single-day draft snapshots", () => {
  assertEquals(isDayDraftResponseSnapshot(null), false);
  assertEquals(
    isDayDraftResponseSnapshot({
      generation_id: GENERATION_ID,
      weekly_plan_id: WEEKLY_PLAN_ID,
      status: "draft",
      target_scheduled_date: SCHEDULED_DATE,
      daily_card: "not-a-record",
    }),
    false,
  );
});

Deno.test("initialSingleDayGenerationSnapshot uses injected nowISO", () => {
  const snapshot = initialSingleDayGenerationSnapshot(
    regenerateDayRequest({ preserve_manual_edits: false }),
    NOW_ISO,
  );
  assertEquals(
    snapshot,
    {
      kind: "single_day_generation_v1",
      scheduled_date: SCHEDULED_DATE,
      preserve_manual_edits: false,
      status: "pending",
      updated_at: NOW_ISO,
    } satisfies SingleDayGenerationSnapshot,
  );
});

Deno.test("normalizeSingleDayGenerationSnapshot normalizes pending and running states", () => {
  const pending = normalizeSingleDayGenerationSnapshot(
    {
      kind: "single_day_generation_v1",
      scheduled_date: SCHEDULED_DATE,
      status: "pending",
      preserve_manual_edits: false,
      updated_at: "2026-06-10T08:00:00.000Z",
    },
    runRecord(),
    NOW_ISO,
  );
  assertEquals(pending?.status, "pending");
  assertEquals(pending?.preserve_manual_edits, false);

  const running = normalizeSingleDayGenerationSnapshot(
    {
      kind: "single_day_generation_v1",
      scheduled_date: SCHEDULED_DATE,
      status: "running",
      started_at: "2026-06-10T08:00:00.000Z",
      heartbeat_at: "2026-06-10T08:05:00.000Z",
    },
    runRecord(),
    NOW_ISO,
  );
  assertEquals(running?.status, "running");
  assertEquals(running?.started_at, "2026-06-10T08:00:00.000Z");
  assertEquals(
    running?.heartbeat_at,
    "2026-06-10T08:05:00.000Z",
  );
});

Deno.test("normalizeSingleDayGenerationSnapshot defaults preserve_manual_edits and updated_at", () => {
  const normalized = normalizeSingleDayGenerationSnapshot(
    {
      kind: "single_day_generation_v1",
      scheduled_date: SCHEDULED_DATE,
      status: "pending",
    },
    runRecord(),
    NOW_ISO,
  );
  assertEquals(normalized?.preserve_manual_edits, true);
  assertEquals(normalized?.updated_at, NOW_ISO);
});

Deno.test("normalizeSingleDayGenerationSnapshot rejects malformed or mismatched snapshots", () => {
  assertEquals(
    normalizeSingleDayGenerationSnapshot(null, runRecord(), NOW_ISO),
    null,
  );
  assertEquals(
    normalizeSingleDayGenerationSnapshot(
      { kind: "single_day_generation_v1", scheduled_date: "2026-06-11" },
      runRecord(),
      NOW_ISO,
    ),
    null,
  );
  assertEquals(
    normalizeSingleDayGenerationSnapshot(
      { kind: "per_day_generation_v1", scheduled_date: SCHEDULED_DATE },
      runRecord(),
      NOW_ISO,
    ),
    null,
  );
  assertEquals(
    normalizeSingleDayGenerationSnapshot(
      { kind: "single_day_generation_v1", scheduled_date: SCHEDULED_DATE },
      runRecord({ target_scheduled_date: null }),
      NOW_ISO,
    ),
    null,
  );
});

Deno.test("normalizeStoredInputSnapshot validates creator and week_start_date", () => {
  const normalized = normalizeStoredInputSnapshot({
    creator_id: CREATOR_ID,
    week_start_date: WEEK_START,
    creator_profile: { positioning: "creator" },
    weekly_setup: { notes: "brief" },
    confirmed_references: [{ id: "ref-1" }],
    idea_bank: "not-an-array",
  });
  assert(normalized);
  assertEquals(normalized?.creator_id, CREATOR_ID);
  assertEquals(normalized?.week_start_date, WEEK_START);
  assertEquals(normalized?.creator_profile, { positioning: "creator" });
  assertEquals(normalized?.weekly_setup, { notes: "brief" });
  assertEquals(normalized?.confirmed_references, [{ id: "ref-1" }]);
  assertEquals(normalized?.idea_bank, []);

  assertEquals(normalizeStoredInputSnapshot(null), null);
  assertEquals(
    normalizeStoredInputSnapshot({
      creator_id: "bad",
      week_start_date: WEEK_START,
    }),
    null,
  );
  assertEquals(
    normalizeStoredInputSnapshot({
      creator_id: CREATOR_ID,
      week_start_date: "  ",
    }),
    null,
  );
});

Deno.test("requestFromRun reconstructs regenerate_draft async request", () => {
  const inputSnapshot = normalizeStoredInputSnapshot({
    creator_id: CREATOR_ID,
    week_start_date: WEEK_START,
  });
  assert(inputSnapshot);
  const request = requestFromRun(
    runRecord({ weekly_setup_id: "44444444-4444-4444-8444-444444444444" }),
    inputSnapshot,
  );
  assertEquals(request, {
    creator_id: CREATOR_ID,
    week_start_date: WEEK_START,
    weekly_setup_id: "44444444-4444-4444-8444-444444444444",
    mode: "regenerate_draft",
    preserve_manual_edits: false,
    mock: false,
    response_mode: "async",
  });
});

Deno.test("uniqueNonBlankStrings dedupes trims and preserves order", () => {
  assertEquals(
    uniqueNonBlankStrings([
      "  First  ",
      "first",
      "Second",
      "",
      "   ",
      "second",
      "Third",
    ]),
    ["First", "Second", "Third"],
  );
});

Deno.test("combineNonBlankStrings joins unique values or uses fallback", () => {
  assertEquals(
    combineNonBlankStrings([" note-a ", "note-b", "note-a"], "fallback"),
    "note-a note-b",
  );
  assertEquals(combineNonBlankStrings(["", "   "], "fallback"), "fallback");
});

Deno.test("makeGeneratedWeekOutputFromCompletedDays prefers progress summaries and caps ideas", () => {
  const progress = {
    ...initialPerDayGenerationSnapshot(WEEK_START),
    strategy_summary: "progress strategy",
    source_summary: "progress source",
  };
  const idea = (title: string): GeneratedIdea => ({
    title,
    summary: title,
    tags: [],
    suggested_use: "bank",
    shootability: "easy",
    fit_score: 0.5,
    source_note: "",
    status: "saved",
  });
  const outputs = [
    dayOutput("2026-06-08", {
      strategy_note: "day-1",
      source_summary: "day-1-source",
      warnings: ["warn-a", " warn-b "],
      assumptions: ["assume-a"],
      idea_bank: Array.from(
        { length: 8 },
        (_, index) => idea(`idea-a-${index}`),
      ),
    }),
    dayOutput("2026-06-09", {
      strategy_note: "day-2",
      source_summary: "day-2-source",
      warnings: ["WARN-B", "warn-c"],
      assumptions: ["assume-a", "assume-b"],
      idea_bank: Array.from(
        { length: 8 },
        (_, index) => idea(`idea-b-${index}`),
      ),
    }),
  ];

  const generated = makeGeneratedWeekOutputFromCompletedDays(
    outputs,
    progress,
    {
      strategy_summary: "fallback strategy",
      source_summary: "fallback source",
    },
  );

  assertEquals(generated.strategy_summary, "progress strategy");
  assertEquals(generated.source_summary, "progress source");
  assertEquals(generated.warnings, ["warn-a", "warn-b", "warn-c"]);
  assertEquals(generated.assumptions, ["assume-a", "assume-b"]);
  assertEquals(
    generated.daily_cards.map((card) => card.scheduled_date),
    ["2026-06-08", "2026-06-09"],
  );
  assertEquals(generated.idea_bank.length, 14);
  assertEquals(generated.idea_bank[0].title, "idea-a-0");
  assertEquals(generated.idea_bank[13].title, "idea-b-5");
});

Deno.test("makeGeneratedWeekOutputFromCompletedDays falls back to day notes and strategy", () => {
  const progress = initialPerDayGenerationSnapshot(WEEK_START);
  const outputs = [
    dayOutput("2026-06-08", {
      strategy_note: "day-one",
      source_summary: "source-one",
    }),
    dayOutput("2026-06-09", {
      strategy_note: "day-two",
      source_summary: "source-two",
    }),
  ];

  const generated = makeGeneratedWeekOutputFromCompletedDays(
    outputs,
    progress,
    {
      strategy_summary: "fallback strategy",
      source_summary: "fallback source",
    },
  );

  assertEquals(generated.strategy_summary, "day-one day-two");
  assertEquals(generated.source_summary, "source-one source-two");
});
