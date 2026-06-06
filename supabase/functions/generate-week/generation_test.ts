import {
  buildDeepSeekChatRequest,
  buildOpenAIResponsesRequest,
  buildPromptMessages,
  callAIProviders,
  extractChatCompletionOutputText,
  extractOpenAIOutputText,
  GenerationInputSnapshot,
  makeMockGeneratedWeek,
  parseGeneratedWeekJSON,
  preserveManualDailyCardEdits,
  validateGeneratedWeek,
} from "./generation.ts";

Deno.test("prompt builder includes profile, setup, references, extractions, obligations, archive, and idea bank", () => {
  const input = fixtureInput();
  const prompt = buildPromptMessages(input);

  assert(prompt.system.includes("strict JSON"));
  assert(prompt.user.includes("Premium fitness after 60"));
  assert(prompt.user.includes("Mumbai"));
  assert(prompt.user.includes("Confirmed towel transition"));
  assert(prompt.user.includes("hook-led sock transition"));
  assert(prompt.user.includes("Brand hydration reminder"));
  assert(prompt.user.includes("Sunday 10K"));
  assert(prompt.user.includes("Used backup story"));
  assert(prompt.user.includes("Quiet Sunday family walk"));
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
  assertEquals(format.name, "mamta_weekly_generation");
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
      cardSchema.required.includes("audio_option_notes"),
    "rich generated card fields must be required in structured output schema",
  );
});

Deno.test("DeepSeek Chat request uses JSON object mode with prompt context", () => {
  const request = buildDeepSeekChatRequest(fixtureInput(), "deepseek-v4-flash");
  const messages = request.messages as Record<string, string>[];
  const responseFormat = recordValue(request.response_format);

  assertEquals(request.model, "deepseek-v4-flash");
  assertEquals(request.max_tokens, 8192);
  assertEquals(responseFormat.type, "json_object");
  assertEquals(messages[0].role, "system");
  assert(messages[0].content.includes("strict JSON"));
  assertEquals(messages[1].role, "user");
  assert(messages[1].content.includes("Confirmed towel transition"));
  assert(messages[1].content.includes("Return one valid JSON object only"));
  assert(messages[1].content.includes("scheduled_dates_in_order"));
  assert(messages[1].content.includes("Never use day_of_week"));
});

Deno.test("AI provider caller falls back from DeepSeek to OpenAI", async () => {
  const calls: string[] = [];
  const generated = await callAIProviders(
    fixtureInput(),
    [
      {
        provider: "deepseek",
        model: "deepseek-v4-flash",
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
  assert(
    validated.daily_cards.every((card) =>
      card.source_reference_ids.includes(
        "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
      )
    ),
    "mock cards should preserve confirmed source reference ids",
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
      display_name: "Mamta",
      positioning: "Premium fitness after 60",
      never_say: ["weight talk", "politics"],
    },
    weekly_setup: {
      id: "77777777-7777-4777-8777-777777777771",
      location: "Mumbai",
      notes: "Race week but low energy.",
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
    ],
    idea_bank: [
      {
        title: "Quiet Sunday family walk",
        summary: "Shootable family moment.",
      },
    ],
    patterns: [],
    trends: [],
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

function recordValue(value: unknown): Record<string, unknown> {
  assert(
    typeof value === "object" && value !== null && !Array.isArray(value),
    `Expected object, got ${JSON.stringify(value)}`,
  );
  return value as Record<string, unknown>;
}
