import {
  buildDeepSeekChatRequest,
  buildDeepSeekDayChatRequest,
  buildOpenAIDayResponsesRequest,
  buildOpenAIResponsesRequest,
  buildPromptMessages,
  callAIProviders,
  callAIProvidersForDay,
  callAIProvidersForSplitWeek,
  extractChatCompletionOutputText,
  extractOpenAIOutputText,
  GenerationInputSnapshot,
  makeMockGeneratedWeek,
  parseGeneratedWeekJSON,
  preserveManualDailyCardEdits,
  validateGeneratedWeek,
  weekDates,
} from "./generation.ts";

Deno.test("prompt builder includes profile, setup, references, extractions, obligations, archive, and idea bank", () => {
  const input = fixtureInput();
  const prompt = buildPromptMessages(input);

  assert(prompt.system.includes("strict JSON"));
  assert(prompt.user.includes("Premium fitness after 60"));
  assert(prompt.user.includes("Bombay"));
  assert(prompt.user.includes("Confirmed towel transition"));
  assert(prompt.user.includes("hook-led sock transition"));
  assert(prompt.user.includes("Brand hydration reminder"));
  assert(prompt.user.includes("Sunday 10K"));
  assert(prompt.user.includes("Used backup story"));
  assert(prompt.user.includes("Quiet Sunday family walk"));
});

Deno.test("prompt builder includes Mamta growth reference rubric", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assertIncludesAll(guidance, [
    "Age Myth Reversal",
    "Real-Life Contradiction Hook",
    "Proof Before Advice",
    "Saveable Practical Cue",
    "Instagram Reels Default",
    "I eat out. I drink sometimes. I still stay fit at 62.",
    "0:00-0:02: motion plus bold text.",
  ]);
});

Deno.test("prompt builder gives weekly brief/setup notes precedence over stale stored context", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assertIncludesAll(guidance, ["Bombay", "back to gym", "podcast"]);
  assertIncludesAll(guidance, ["New Jersey", "HYROX", "race recovery"]);
  assert(
    /weekly (brief|setup|notes?).{0,120}(win|override|precedence|supersede|higher priority)|(?:win|override|precedence|supersede|higher priority).{0,120}weekly (brief|setup|notes?)/i
      .test(guidance),
    "prompt should explicitly say weekly brief/setup notes win for week-specific facts",
  );
  assertHasAvoidanceFor(guidance, "New Jersey");
  assertHasAvoidanceFor(guidance, "HYROX");
  assertHasAvoidanceFor(guidance, "race recovery");
});

Deno.test("OpenAI Responses request uses strict structured JSON output schema", () => {
  const request = buildOpenAIResponsesRequest(fixtureInput(), "gpt-4.1-mini");
  const format = recordValue(recordValue(request.text).format);
  const schema = recordValue(format.schema);
  const cardSchema = recordValue(
    recordValue(recordValue(schema.properties).daily_cards).items,
  );
  const cardProperties = recordValue(cardSchema.properties);

  assertEquals(request.model, "gpt-4.1-mini");
  assertEquals(format.type, "json_schema");
  assertEquals(format.name, "creator_weekly_generation");
  assertEquals(format.strict, true);
  assertEquals(schema.additionalProperties, false);
  assertEquals(cardSchema.additionalProperties, false);
  assertEquals(recordValue(cardProperties.scheduled_date).format, "date");
  assertEquals(
    recordValue(recordValue(cardProperties.source_reference_ids).items).format,
    "uuid",
  );
  assert(
    Array.isArray(cardSchema.required) &&
      cardSchema.required.includes("script") &&
      cardSchema.required.includes("backup_story") &&
      cardSchema.required.includes("audio_option_notes") &&
      cardSchema.required.includes("format") &&
      cardSchema.required.includes("duration_seconds") &&
      cardSchema.required.includes("weekly_brief_anchor") &&
      cardSchema.required.includes("brief_alignment") &&
      cardSchema.required.includes("brief_context_tags") &&
      cardSchema.required.includes("shot_timeline") &&
      cardSchema.required.includes("voiceover_timeline") &&
      cardSchema.required.includes("on_screen_text_timeline") &&
      cardSchema.required.includes("silent_version_timeline") &&
      cardSchema.required.includes("backup_story_detail") &&
      cardSchema.required.includes("caption_backup_detail"),
    "rich generated card fields must be required in structured output schema",
  );
  const formatEnum = recordValue(cardProperties.format).enum;
  assert(
    Array.isArray(formatEnum),
    "format schema should declare the allowed content formats",
  );
  assertEquals(formatEnum.join(","), "Reel,Post,Story");
  assertEquals(recordValue(cardProperties.shot_timeline).minItems, 1);
  assertEquals(recordValue(cardProperties.voiceover_timeline).minItems, 1);
  assertEquals(recordValue(cardProperties.brief_context_tags).minItems, 1);
  assertEquals(recordValue(cardProperties.brief_context_tags).maxItems, 4);
});

Deno.test("OpenAI per-day request uses strict structured JSON output schema", () => {
  const request = buildOpenAIDayResponsesRequest(
    fixtureInput(),
    "gpt-4.1-mini",
    "2026-06-10",
    2,
  );
  const format = recordValue(recordValue(request.text).format);
  const schema = recordValue(format.schema);
  const dailyCard = recordValue(recordValue(schema.properties).daily_card);

  assertEquals(format.type, "json_schema");
  assertEquals(format.name, "creator_daily_generation");
  assertEquals(format.strict, true);
  assertEquals(request.max_output_tokens, 12000);
  assertEquals(schema.additionalProperties, false);
  assertEquals(dailyCard.additionalProperties, false);
  assert(
    Array.isArray(dailyCard.required) &&
      dailyCard.required.includes("shot_timeline") &&
      dailyCard.required.includes("voiceover_timeline") &&
      dailyCard.required.includes("backup_story_detail") &&
      dailyCard.required.includes("weekly_brief_anchor") &&
      dailyCard.required.includes("brief_alignment") &&
      dailyCard.required.includes("brief_context_tags"),
    "per-day schema should require Instagram production detail and weekly brief evidence fields",
  );
});

Deno.test("DeepSeek Chat request uses JSON object mode with max thinking effort", () => {
  const request = buildDeepSeekChatRequest(fixtureInput(), "deepseek-v4-pro");
  const messages = request.messages as Record<string, string>[];
  const responseFormat = recordValue(request.response_format);
  const thinking = recordValue(request.thinking);

  assertEquals(request.model, "deepseek-v4-pro");
  assertEquals(request.max_tokens, 12000);
  assertEquals(responseFormat.type, "json_object");
  assertEquals(thinking.type, "enabled");
  assertEquals(request.reasoning_effort, "max");
  assertEquals(messages[0].role, "system");
  assert(messages[0].content.includes("strict JSON"));
  assertEquals(messages[1].role, "user");
  assert(messages[1].content.includes("Confirmed towel transition"));
  assert(messages[1].content.includes("Instagram Reels"));
  assert(messages[1].content.includes("shot_timeline"));
  assert(messages[1].content.includes("weekly_brief_anchor"));
  assert(messages[1].content.includes("0:00-0:03"));
  assert(messages[1].content.includes("Return one valid JSON object only"));
  assert(messages[1].content.includes("non-empty text"));
  assert(messages[1].content.includes("scheduled_dates_in_order"));
  assert(messages[1].content.includes("Never use day_of_week"));
});

Deno.test("day AI request includes target day intent and diversity guidance", () => {
  const request = buildDeepSeekDayChatRequest(
    fixtureInput(),
    "deepseek-v4-pro",
    "2026-06-10",
    2,
  );
  const requestText = JSON.stringify(request);

  assertEquals(request.max_tokens, 12000);
  assert(requestText.includes("2026-06-10"));
  assert(requestText.includes("non-empty text"));
  assert(
    /day.{0,80}(intent|role|purpose|job)|(?:intent|role|purpose|job).{0,80}day/i
      .test(requestText),
    "day request should include a target day intent, role, purpose, or job",
  );
  assert(
    /divers|distinct|varied|avoid.{0,60}generic|not all generic|different/i
      .test(requestText),
    "day request should include diversity guidance so cards are not generic repeats",
  );
});

Deno.test("AI provider caller falls back from DeepSeek to OpenAI", async () => {
  const calls: string[] = [];
  const generated = await callAIProviders(
    fixtureInput(),
    [
      {
        provider: "deepseek",
        model: "deepseek-v4-pro",
        apiKey: "deepseek-key",
      },
      { provider: "openai", model: "gpt-4.1-mini", apiKey: "openai-key" },
    ],
    async (input, provider) => {
      calls.push(provider.provider);
      if (provider.provider === "deepseek") {
        throw new Error("deepseek_request_failed:502");
      }
      return makeMockGeneratedWeek(input);
    },
  );

  assertEquals(calls.join(","), "deepseek,openai");
  assertEquals(generated.daily_cards.length, 7);
});

Deno.test("daily AI provider caller preserves DeepSeek-primary OpenAI-fallback order", async () => {
  const input = fixtureInput();
  const calls: string[] = [];
  const output = await callAIProvidersForDay(
    input,
    [
      {
        provider: "deepseek",
        model: "deepseek-v4-pro",
        apiKey: "deepseek-key",
      },
      { provider: "openai", model: "gpt-4.1-mini", apiKey: "openai-key" },
    ],
    "2026-06-10",
    2,
    async (_input, provider, scheduledDate, dayIndex) => {
      calls.push(provider.provider);
      if (provider.provider === "deepseek") {
        throw new Error("deepseek_request_failed:502");
      }
      const card = makeMockGeneratedWeek(input).daily_cards[dayIndex];
      return {
        strategy_note: "Fallback day",
        warnings: [],
        assumptions: [],
        daily_card: { ...card, scheduled_date: scheduledDate },
        idea_bank: [],
        source_summary: "Fallback context",
      };
    },
  );

  assertEquals(calls.join(","), "deepseek,openai");
  assertEquals(output.daily_card.scheduled_date, "2026-06-10");
});

Deno.test("split-week AI caller combines seven valid daily card outputs", async () => {
  const input = fixtureInput();
  const dates = weekDates("2026-06-08");
  const calls: string[] = [];
  const generated = await callAIProvidersForSplitWeek(
    input,
    [{
      provider: "deepseek",
      model: "deepseek-v4-pro",
      apiKey: "deepseek-key",
    }],
    async (_input, provider, scheduledDate, dayIndex) => {
      calls.push(`${provider.provider}:${scheduledDate}`);
      const mock = makeMockGeneratedWeek(input);
      return {
        strategy_note: `Strategy for ${scheduledDate}`,
        warnings: [],
        assumptions: [`Assumption ${dayIndex + 1}`],
        daily_card: {
          ...mock.daily_cards[dayIndex],
          scheduled_date: scheduledDate,
        },
        idea_bank: [],
        source_summary: `Source summary ${dayIndex + 1}`,
      };
    },
  );

  assertEquals(calls.length, 7);
  assertEquals(calls[0], "deepseek:2026-06-08");
  assertEquals(
    generated.daily_cards.map((card) => card.scheduled_date).join(","),
    dates.join(","),
  );
  assert(generated.strategy_summary.includes("Strategy for 2026-06-08"));
  assert(generated.source_summary.includes("Source summary 7"));
});

Deno.test("Chat completion extractor handles DeepSeek response content", () => {
  assertEquals(
    extractChatCompletionOutputText({
      choices: [{
        message: { role: "assistant", content: '{"ok":true}' },
      }],
    }),
    '{"ok":true}',
  );
  assertEquals(
    extractChatCompletionOutputText({ choices: [{ message: {} }] }),
    null,
  );
});

Deno.test("OpenAI output extractor handles direct and nested Responses text", () => {
  assertEquals(
    extractOpenAIOutputText({ output_text: '{"ok":true}' }),
    '{"ok":true}',
  );
  assertEquals(
    extractOpenAIOutputText({
      output: [{
        content: [
          { type: "output_text", text: '{"a":' },
          { type: "output_text", text: "1}" },
        ],
      }],
    }),
    '{"a":1}',
  );
});

Deno.test("OpenAI output extractor treats refusal-only responses as missing JSON", () => {
  assertEquals(
    extractOpenAIOutputText({
      output: [{
        content: [{ type: "refusal", refusal: "Cannot comply." }],
      }],
    }),
    null,
  );
});

Deno.test("mock generation returns seven valid draft day cards", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  const validated = validateGeneratedWeek(generated, "2026-06-08");

  assertEquals(validated.daily_cards.length, 7);
  assertEquals(validated.daily_cards[0].scheduled_date, "2026-06-08");
  assertEquals(validated.daily_cards[6].scheduled_date, "2026-06-14");
  assert(validated.daily_cards.every((card) => card.script.length > 0));
  assert(validated.daily_cards.every((card) => card.caption.length > 0));
  assert(validated.daily_cards.every((card) => card.backup_story.length > 0));
  assert(validated.daily_cards.every((card) => card.format === "Reel"));
  assert(
    validated.daily_cards.every((card) =>
      card.primary_surface === "Instagram Reels" &&
      card.duration_seconds > 0 &&
      card.hook.length > 0 &&
      card.save_share_reason.length > 0 &&
      card.shot_timeline.length > 0 &&
      card.voiceover_timeline.length > 0 &&
      card.on_screen_text_timeline.length > 0 &&
      card.silent_version_timeline.length > 0 &&
      card.backup_story_detail.length > 0 &&
      card.caption_backup_detail.length > 0 &&
      card.weekly_brief_anchor.length > 0 &&
      card.brief_alignment.length > 0 &&
      card.brief_context_tags.length > 0
    ),
    "mock cards should include Instagram-specific production detail and brief evidence fields",
  );
  assert(
    validated.daily_cards.every((card) =>
      card.shot_timeline.every((item) =>
        /^\d{1,2}:\d{2}-\d{1,2}:\d{2}$/.test(item.timestamp)
      )
    ),
    "shot timelines should use timestamp ranges",
  );
  assert(
    validated.daily_cards.every((card) =>
      card.source_reference_ids.includes(
        "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
      )
    ),
    "mock cards should preserve confirmed source reference ids",
  );
});

Deno.test("mock generation output does not expose admin-facing implementation assumptions", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  const outputText = JSON.stringify(generated);

  assert(
    !outputText.includes("Mock generation used deterministic local context"),
    "mock output should not leak deterministic local-context implementation notes",
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

Deno.test("preserve manual edits keeps review-editable draft fields on regeneration", () => {
  const generated = makeMockGeneratedWeek(fixtureInput()).daily_cards[0];
  const preserved = preserveManualDailyCardEdits(generated, {
    title: "Edited title",
    why_today: "Edited why today.",
    shootability: "medium",
    estimated_shoot_minutes: 22,
    scene_list: [{
      number: 1,
      title: "Edited scene",
      duration: "5 sec",
      symbol: "pencil",
    }],
    caption: "Edited caption.",
    backup_story: { line: "Edited backup story." },
    backup_caption_only: { line: "Edited caption-only backup." },
  });

  assertEquals(preserved.title, "Edited title");
  assertEquals(preserved.why_today, "Edited why today.");
  assertEquals(preserved.shootability, "medium");
  assertEquals(preserved.estimated_shoot_minutes, 22);
  assertEquals(preserved.scene_list[0].title, "Edited scene");
  assertEquals(preserved.caption, "Edited caption.");
  assertEquals(preserved.backup_story, "Edited backup story.");
  assertEquals(
    preserved.backup_caption_only,
    "Edited caption-only backup.",
  );
  assertEquals(preserved.script, generated.script);
  assertEquals(preserved.source_note, generated.source_note);
});

function fixtureInput(): GenerationInputSnapshot {
  return {
    creator_id: "33333333-3333-4333-8333-333333333333",
    week_start_date: "2026-06-08",
    creator_profile: {
      display_name: "Creator",
      positioning: "Premium fitness after 60",
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

function assertIncludesAll(text: string, expected: string[]): void {
  for (const value of expected) {
    assert(text.includes(value), `Expected prompt to include ${value}`);
  }
}

function assertHasAvoidanceFor(text: string, phrase: string): void {
  const escapedPhrase = phrase.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const avoidPattern =
    `(?:avoid|exclude|do not use|do not lean on|stale|lower-priority|supersed|override).{0,120}${escapedPhrase}|${escapedPhrase}.{0,120}(?:avoid|exclude|do not use|do not lean on|stale|lower-priority|supersed|override)`;
  assert(
    new RegExp(avoidPattern, "i").test(text),
    `Expected prompt to include avoidance/exclusion guidance for ${phrase}`,
  );
}

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  if (!Object.is(actual, expected)) {
    throw new Error(
      message ??
        `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

function recordValue(value: unknown): Record<string, unknown> {
  assert(
    typeof value === "object" && value !== null && !Array.isArray(value),
    `Expected object, got ${JSON.stringify(value)}`,
  );
  return value as Record<string, unknown>;
}
