import {
  AIGenerationAttemptLog,
  BANNED_CTA_TEMPLATES,
  BANNED_INSTRUCTOR_ENDINGS,
  buildDeepSeekChatRequest,
  buildDeepSeekDayChatRequest,
  buildOpenAIDayResponsesRequest,
  buildOpenAIResponsesRequest,
  buildPromptMessages,
  callAIProviders,
  callAIProvidersForDay,
  callAIProvidersForSplitWeek,
  containsInstructorEnding,
  containsInstructorPhrasing,
  countExplicitSaveCTAs,
  extractChatCompletionOutputText,
  extractOpenAIOutputText,
  GenerateWeekValidationError,
  GenerationInputSnapshot,
  INSTRUCTOR_ISH_PHRASES,
  makeMockGeneratedWeek,
  preserveManualDailyCardEdits,
  resolveAIDayRequestTimeoutMs,
  resolveAIRequestTimeoutMs,
  scopeInputForDayPrompt,
  validateGeneratedWeek,
  weekDates,
} from "./generation.ts";

Deno.test("prompt builder includes profile, setup, references, extractions, obligations, archive, and idea bank", () => {
  const input = fixtureInput();
  const prompt = buildPromptMessages(input);

  assert(prompt.system.includes("strict JSON"));
  assert(prompt.user.includes("Lifestyle creator after 60"));
  assert(prompt.user.includes("Bombay"));
  assert(prompt.user.includes("Confirmed towel transition"));
  assert(prompt.user.includes("hook-led sock transition"));
  assert(prompt.user.includes("Brand hydration reminder"));
  assert(prompt.user.includes("Sunday 10K"));
  assert(prompt.user.includes("Used backup story"));
  assert(prompt.user.includes("Quiet Sunday family walk"));
});

Deno.test("prompt builder includes creator lifestyle growth reference rubric", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assertIncludesAll(guidance, [
    "Tiny Thing I Changed Hook",
    "Real-Life Contradiction Hook",
    "What I'm Doing, Not How To Train",
    "Recovery Reset Hook",
    "The Meal That Helps Hook",
    "Instagram Reels Default",
    "The tiny thing I changed today",
    "0:00-0:02: motion plus bold text.",
  ]);
});

Deno.test("prompt builder frames creator as lifestyle creator with four pillars", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assertIncludesAll(guidance, ["gym", "lifestyle", "eating", "recovery"]);
  assert(
    guidance.toLowerCase().includes("not a gym instructor"),
    "prompt should state the creator is not a gym instructor",
  );
  assertIncludesAll(guidance, [
    "The tiny thing I changed today",
    "My recovery reset after a heavy week",
    "The meal that makes gym days easier",
  ]);
});

Deno.test("prompt builder includes creator positioning and voice rules", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assertIncludesAll(guidance, [
    "The creator",
    "Indian mother, wife, and HYROX athlete",
    "Proof that life does not shrink with age",
    "Do not mention the creator's age in every post",
    "Conversational, warm, witty",
    "slightly sarcastic",
    "Warm-up is not optional. It is a legal requirement.",
    "I don't train to look young",
  ]);
  assertHasAvoidanceFor(guidance, "age is just a number");
  assertHasAvoidanceFor(guidance, "beast mode");
});

Deno.test("prompt builder maps creator brand model to four production pillars", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assertIncludesAll(guidance, [
    "four_pillar_contract",
    "Output content_pillar must remain one of gym, lifestyle, eating, or recovery",
    "six_pillar_brand_lens",
    "HYROX and serious training",
    "Strength for the second half of life",
    "Real routine: food, hydration, recovery, home",
    "Family and Indian home life",
    "Funny gym realities",
    "Brand-friendly lifestyle",
    "production_pillar",
  ]);
});

Deno.test("prompt builder structures creator voice guidance with all required sections", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assert(guidance.includes("Creator Voice"));
  assertIncludesAll(guidance, [
    "voice_essence",
    "point_of_view",
    "sounds_like_creator",
    "never_sounds_like",
    "age_rule",
    "writing_test",
    "prefer_instead",
    "banned_trainer_wording",
  ]);
});

Deno.test("prompt builder writing test requires creator-specific lived detail for every line", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assertIncludesAll(guidance, [
    "could another creator say this unchanged",
    "rewrite it with Creator's lived detail",
    "family/home context",
    "dry humour",
    "Generic creator lines fail",
    "Specific, first-person moments pass",
    "another creator's account",
  ]);
});

Deno.test("OpenAI Responses request uses strict structured JSON output schema", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assertIncludesAll(guidance, [
    "one useful cue",
    "one simple cue",
    "restart your routine",
    "protect your joints",
    "save this reel",
    "here's what you need to know",
    "the one exercise you should",
    "do this exercise",
    "do this workout",
    "try this workout",
    "upper body cue",
    "training angle",
    "training clients",
  ]);
});

Deno.test("prompt builder prefers first-person lived moments over follower-directed teaching", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assertIncludesAll(guidance, [
    "First-person lived moments",
    "family/home texture",
    "specific real situations",
    "never instruct the viewer",
    "you should",
    "try this",
    "here's how",
    "I noticed",
    "I tried",
    "this worked for me",
  ]);
});

Deno.test("prompt builder includes creator voice essence and point of view", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assert(guidance.includes("has lived enough life to know what matters"));
  assert(
    guidance.includes(
      "not trying to look younger; she is making 60 feel like something to look forward to",
    ),
  );
  assert(
    guidance.includes("voice note from a friend, not a caption from a brand"),
  );
  assert(guidance.includes("This is what I'm doing, noticing, or trying"));
});

Deno.test("prompt builder includes creator voice examples", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assertIncludesAll(guidance, [
    "I came to the gym for strength. I did not come to negotiate with a sled",
    "My friends think my breakfast sounds sad",
    "Warm-up is not optional. It is a legal requirement.",
    "Everything hurts, but in a very successful way.",
    "I don't train to look young. I train so getting up from the floor is not a family event.",
  ]);
});

Deno.test("prompt builder keeps four-pillar production contract unchanged", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assertIncludesAll(guidance, [
    "gym",
    "lifestyle",
    "eating",
    "recovery",
    "four_pillar_contract",
    "Output content_pillar must remain one of gym, lifestyle, eating, or recovery",
    "six_pillar_brand_lens",
    "HYROX and serious training",
    "production_pillar",
  ]);
});

Deno.test("prompt builder includes shoot-first package and brand-collab rules", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assertIncludesAll(guidance, [
    "Shoot-first",
    "never claim it was sent",
    "exact videos to shoot",
    "VO or text-only script",
    "haldi jeera water",
    "Brand In My Real Routine",
    "real-life moment -> training/routine problem -> product naturally appears",
    "Never lead with the product",
    "Never claim live Instagram data was pulled",
  ]);
});

Deno.test("prompt builder includes creator day-of-week routine defaults", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assertIncludesAll(guidance, [
    "Monday: training-led",
    "Tuesday: recovery/eating/lifestyle",
    "Wednesday: training-led",
    "Thursday: eating",
    "Friday: lifestyle",
    "Saturday: experimental lifestyle",
    "Sunday: recovery/family",
    "The day-of-week routine is only the default",
  ]);
});

Deno.test("prompt builder bans instructor phrasing", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assertIncludesAll(guidance, [
    "fix your form",
    "upper body cue",
    "training angle",
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

Deno.test("prompt builder includes retention-first Reel rules for every Reel", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assert(guidance.includes("retention_first_rules"));
  assertIncludesAll(guidance, [
    "Every one of the seven Reels must be built for high retention and sharing",
    "0:00-0:02",
    "The first two seconds must create immediate tension, curiosity, contradiction, or recognition",
    "Each Reel must contain at least one unmistakable creator moment",
    "personal opinion, contradiction, confession, or comic observation",
    "at least one Creator-specific lived detail",
    "Every Reel needs a satisfying turn or payoff",
    "natural comment, share, or save trigger",
    "not a tacked-on",
  ]);
});

Deno.test("prompt builder enforces no-chill-days rule against low-stakes filler", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assert(guidance.includes("no_chill_days_rule"));
  assertIncludesAll(guidance, [
    "No chill days.",
    "Low-stakes filler concepts",
    "Generic reset/reminder posts",
    "Passive recovery montages",
    "Repeated 'one tiny thing I changed'",
    "Product-led concepts",
    "Recovery, eating, and family days stay in the four-pillar mix",
    "sharp creative stakes",
    "Do not default to 'gentle' or 'calm'",
    "litmus_test",
    "could be any creator's calm Monday",
  ]);
});

Deno.test("prompt builder includes seven-day distinctiveness rule with different hook engines", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assert(guidance.includes("seven_day_distinctiveness"));
  assertIncludesAll(guidance, [
    "Each of the seven days must use a different hook mechanism",
    "surprise/contradiction",
    "comic observation",
    "confession",
    "useful detail with tension",
    "emotional reflection",
    "different comic or emotional engine",
    "wry observation",
    "self-deprecation",
    "quiet pride",
    "deadpan humour",
    "Brand obligations must not make all seven scripts product-centered",
    "variety show, not a monotone wellness feed",
  ]);
});

Deno.test("prompt builder treats virality as ambition, never a guarantee or claim", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assert(guidance.includes("Treat virality as an ambition embedded in craft"));
  assertIncludesAll(guidance, [
    "never a guarantee",
    "never a claim",
    "Do not use words like viral, trending, algorithm-friendly",
  ]);
});

Deno.test("prompt builder sharpens recovery pillar to demand creative ambition", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assertIncludesAll(guidance, [
    "Recovery is not a background state",
    "content with a point of view",
    "creative ambition as a gym Reel",
    "Never produce a generic 'rest day' montage",
  ]);
});

Deno.test("prompt builder system prompt uses retention-first framing instead of calm framing", () => {
  const prompt = buildPromptMessages(fixtureInput());

  assert(
    prompt.system.includes("retention-first"),
    "system prompt should prioritize retention-first hooks, not calm practical tone",
  );
  assert(
    prompt.system.includes("Creative stakes win over trend chasing"),
    "system prompt should prioritize creative stakes over calm/gentle framing",
  );
  assert(
    !prompt.system.includes("calm practical tone"),
    "system prompt must not use calm practical tone framing",
  );
});

Deno.test("prompt builder still enforces four-pillar contract and six-pillar brand lens", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  // four-pillar contract unchanged
  assertIncludesAll(guidance, [
    "four_pillar_contract",
    "Output content_pillar must remain one of gym, lifestyle, eating, or recovery",
    "six_pillar_brand_lens",
    "HYROX and serious training",
    "Strength for the second half of life",
    "Real routine: food, hydration, recovery, home",
    "Family and Indian home life",
    "Funny gym realities",
    "Brand-friendly lifestyle",
    "production_pillar",
    "gym",
    "lifestyle",
    "eating",
    "recovery",
  ]);
});

Deno.test("prompt builder includes all creator voice sections alongside new retention rules", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  // All original creator voice sections still present
  assertIncludesAll(guidance, [
    "Creator Voice",
    "voice_essence",
    "point_of_view",
    "sounds_like_creator",
    "never_sounds_like",
    "age_rule",
    "writing_test",
    "prefer_instead",
    "banned_trainer_wording",
  ]);

  // New sections present
  assertIncludesAll(guidance, [
    "retention_first_rules",
    "no_chill_days_rule",
    "seven_day_distinctiveness",
    "Treat virality as an ambition embedded in craft",
  ]);
});

Deno.test("prompt builder bans trainer-coach wording observed in live output", () => {
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

Deno.test("per-day prompt scopes input to target day context", () => {
  const input: GenerationInputSnapshot = {
    ...fixtureInput(),
    confirmed_references: [
      {
        id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
        manual_notes:
          "Thursday strength snack brand integration at home after compound day.",
      },
      {
        id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2",
        manual_notes: "Sunday long run beach montage for a race recap.",
      },
    ],
    reference_extractions: [
      {
        id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1",
        source_reference_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
        extracted_payload: {
          summary: "Home snack prep sequence with brand pack shot.",
        },
      },
      {
        id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2",
        source_reference_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2",
        extracted_payload: { summary: "Beach running montage." },
      },
    ],
    brand_briefs: [
      {
        brand_name: "SnackCo",
        campaign_title: "Thursday strength snack",
        post_date: "2026-06-11",
      },
      {
        brand_name: "SundayShoes",
        campaign_title: "Sunday beach long run",
        post_date: "2026-06-14",
      },
    ],
    key_moments: [
      {
        name: "Thursday snack shoot",
        moment_date: "2026-06-11",
      },
      {
        name: "Sunday beach race",
        moment_date: "2026-06-14",
      },
    ],
    existing_week_cards: [
      {
        id: "44444444-4444-4444-8444-444444444411",
        scheduled_date: "2026-06-11",
        title: "Thursday snack card",
      },
      {
        id: "44444444-4444-4444-8444-444444444414",
        scheduled_date: "2026-06-14",
        title: "Sunday race card",
      },
    ],
  };

  const scoped = scopeInputForDayPrompt(input, "2026-06-11", 3);

  assertEquals(scoped.existing_week_cards?.length, 1);
  assertEquals(scoped.existing_week_cards?.[0].title, "Thursday snack card");
  assertEquals(scoped.confirmed_references.length, 1);
  assertEquals(
    scoped.confirmed_references[0].id,
    "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
  );
  assertEquals(scoped.reference_extractions.length, 1);
  assertEquals(scoped.brand_briefs.length, 1);
  assertEquals(scoped.brand_briefs[0].brand_name, "SnackCo");
  assertEquals(scoped.key_moments.length, 1);
  assertEquals(scoped.key_moments[0].name, "Thursday snack shoot");
});

Deno.test("per-day DeepSeek prompt omits unrelated day references", () => {
  const input: GenerationInputSnapshot = {
    ...fixtureInput(),
    confirmed_references: [
      {
        id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
        manual_notes:
          "Thursday strength snack brand integration at home after compound day.",
      },
      {
        id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2",
        manual_notes: "Sunday long run beach montage for a race recap.",
      },
    ],
    existing_week_cards: [
      {
        scheduled_date: "2026-06-11",
        title: "Thursday snack card",
      },
      {
        scheduled_date: "2026-06-14",
        title: "Sunday race card",
      },
    ],
  };
  const request = buildDeepSeekDayChatRequest(
    input,
    "deepseek-v4-pro",
    "2026-06-11",
    3,
  );
  const requestText = JSON.stringify(request);

  assert(requestText.includes("Thursday strength snack"));
  assert(requestText.includes("Thursday snack card"));
  assert(
    !requestText.includes("Sunday long run beach montage"),
    "Thursday prompt should not carry unrelated Sunday reference text",
  );
  assert(
    !requestText.includes("Sunday race card"),
    "Thursday prompt should not carry unrelated Sunday existing card text",
  );
});

Deno.test("day AI request uses the scheduled date weekday instead of the week slot", () => {
  const sundayStartInput = {
    ...fixtureInput(),
    week_start_date: "2026-06-21",
  };
  const request = buildDeepSeekDayChatRequest(
    sundayStartInput,
    "deepseek-v4-pro",
    "2026-06-21",
    0,
  );
  const messages = request.messages as Record<string, string>[];
  const userContent = messages[1].content;
  const userPayload = JSON.parse(userContent.split("\n")[0]);
  const requiredContract = recordValue(userPayload.required_contract);

  assertEquals(userPayload.target.weekday, "Sunday");
  assertEquals(userPayload.target.scheduled_date, "2026-06-21");
  assert(
    userContent.includes(
      "Hard day/date lock: this output is only for scheduled_date 2026-06-21, day 1.",
    ),
    "DeepSeek day prompt should repeat the date lock outside the JSON payload",
  );
  assertEquals(
    requiredContract.day_date_lock,
    "daily_card.scheduled_date must be exactly 2026-06-21; all copy, title, why_today, timelines, backup story, and caption must describe only that scheduled date's day intent.",
  );
  assert(
    userPayload.target.day_intent.includes("Sunday:"),
    "Sunday-start weeks should get Sunday-specific guidance",
  );
  assert(
    !userPayload.target.day_intent.includes("Monday:"),
    "Sunday-start weeks must not inherit the first slot's old Monday guidance",
  );
  assert(
    JSON.stringify(userPayload.generation_guidance.weekly_diversity)
      .includes("Sunday 2026-06-21"),
    "weekly arc should be labeled by actual scheduled weekdays",
  );
});

Deno.test("per-day prompt uses compact daily guidance instead of full weekly guidance", () => {
  const request = buildDeepSeekDayChatRequest(
    fixtureInput(),
    "deepseek-v4-pro",
    "2026-06-10",
    2,
  );
  const messages = request.messages as Record<string, string>[];
  const userPayload = JSON.parse(messages[1].content.split("\n")[0]);
  const guidance = recordValue(userPayload.generation_guidance);
  const guidanceText = JSON.stringify(guidance);

  assertEquals(
    guidance.compact_guidance_version,
    "creator_daily_generation_compact_v3",
  );
  assert(guidanceText.includes("Wednesday 2026-06-10"));
  assert(!guidanceText.includes("creator_positioning"));
  assert(!guidanceText.includes("retention_first_rules"));
  assert(!guidanceText.includes("growth_references"));
  assert(!guidanceText.includes("no_chill_days_rule"));
});

Deno.test("per-day prompt sends compact input instead of raw scoped snapshot", () => {
  const input: GenerationInputSnapshot = {
    ...fixtureInput(),
    creator_profile: {
      ...recordValue(fixtureInput().creator_profile),
      long_private_notes: "creator profile filler ".repeat(80),
      full_strategy_archive: "archive filler ".repeat(80),
    },
    weekly_setup: {
      ...recordValue(fixtureInput().weekly_setup),
      selected_sources: Array.from(
        { length: 20 },
        (_, index) => `source-${index}`,
      ),
      old_full_brief_dump: "weekly setup filler ".repeat(100),
    },
    recent_archive: Array.from({ length: 10 }, (_, index) => ({
      archive_date: `2026-05-${String(index + 1).padStart(2, "0")}`,
      decision: "published",
      output_line: "old unrelated archive filler ".repeat(30),
    })),
    idea_bank: Array.from({ length: 10 }, (_, index) => ({
      title: `Idea ${index}`,
      summary: "saved idea filler ".repeat(30),
    })),
  };
  const scoped = scopeInputForDayPrompt(input, "2026-06-10", 2);
  const request = buildDeepSeekDayChatRequest(
    input,
    "deepseek-v4-pro",
    "2026-06-10",
    2,
  );
  const messages = request.messages as Record<string, string>[];
  const userPayload = JSON.parse(messages[1].content.split("\n")[0]);
  const compactInput = recordValue(userPayload.input);

  assertEquals(
    compactInput.compact_input_version,
    "creator_day_prompt_input_v2",
  );
  assert(!("creator_id" in recordValue(compactInput.creator_profile)));
  assert(!("selected_sources" in recordValue(compactInput.weekly_setup)));
  assert(
    JSON.stringify(compactInput).length < JSON.stringify(scoped).length,
    "day prompt should send a smaller compact input than the raw scoped snapshot",
  );
});

Deno.test("per-day repair prompt includes the repair context and compact instruction", () => {
  const request = buildDeepSeekDayChatRequest(
    {
      ...fixtureInput(),
      day_retry_context: {
        retry_kind: "validation_repair",
        retry_reason: "invalid_generated_week",
        validation_error: { rule: "scene_count" },
      },
    },
    "deepseek-v4-pro",
    "2026-06-10",
    2,
  );
  const messages = request.messages as Record<string, string>[];
  const userPayload = JSON.parse(messages[1].content.split("\n")[0]);
  const compactInput = recordValue(userPayload.input);

  assertEquals(userPayload.repair_context.retry_kind, "validation_repair");
  assertEquals(
    userPayload.repair_context.retry_reason,
    "invalid_generated_week",
  );
  assertEquals(
    userPayload.generation_guidance.repair_instruction,
    "This is a repair retry for the same scheduled_date. Do not broaden the idea. Fix the stated issue, simplify the concept if needed, and return one complete valid daily card.",
  );
  assertEquals(
    compactInput.compact_input_version,
    "creator_day_prompt_repair_input_v2",
  );
  assertEquals(compactInput.repair_mode, true);
  assertEquals(recordValueArray(compactInput.confirmed_references).length, 0);
  assertEquals(recordValueArray(compactInput.reference_extractions).length, 0);
  assert(!("recent_archive" in compactInput));
  assert(!("idea_bank" in compactInput));
  assert(!("trends" in compactInput));
  assert(!("audio_options" in compactInput));
});

Deno.test("per-day repair prompt keeps day-scoped source context when available", () => {
  const request = buildDeepSeekDayChatRequest(
    {
      ...fixtureInput(),
      confirmed_references: [{
        id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
        manual_notes: "Wednesday source reference for floor work.",
      }],
      reference_extractions: [{
        id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1",
        source_reference_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
        extracted_payload: { summary: "Wednesday source reference detail." },
      }],
      day_retry_context: {
        retry_kind: "validation_repair",
        retry_reason: "invalid_generated_week",
        validation_error: {
          rule: "source_reference_ids",
          path: "source_reference_ids",
        },
      },
    },
    "deepseek-v4-pro",
    "2026-06-10",
    2,
  );
  const messages = request.messages as Record<string, string>[];
  const userPayload = JSON.parse(messages[1].content.split("\n")[0]);
  const compactInput = recordValue(userPayload.input);

  assertEquals(recordValueArray(compactInput.confirmed_references).length, 1);
  assertEquals(recordValueArray(compactInput.reference_extractions).length, 1);
});

Deno.test("per-day repair prompt is materially smaller than the first attempt", () => {
  const input: GenerationInputSnapshot = {
    ...fixtureInput(),
    confirmed_references: Array.from({ length: 5 }, (_, index) => ({
      id: `aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa${index}`,
      manual_notes: `Wednesday reference ${index} ${"detail ".repeat(80)}`,
    })),
    reference_extractions: Array.from({ length: 5 }, (_, index) => ({
      id: `eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee${index}`,
      source_reference_id: `aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa${index}`,
      extracted_payload: {
        summary: `Wednesday extraction ${index} ${"payload ".repeat(80)}`,
      },
    })),
    recent_archive: Array.from({ length: 5 }, (_, index) => ({
      archive_date: `2026-06-${String(index + 1).padStart(2, "0")}`,
      output_line: `archive ${index} ${"old context ".repeat(80)}`,
    })),
    idea_bank: Array.from({ length: 5 }, (_, index) => ({
      title: `Idea ${index}`,
      summary: `idea ${index} ${"saved detail ".repeat(80)}`,
    })),
  };
  const firstAttempt = buildDeepSeekDayChatRequest(
    input,
    "deepseek-v4-pro",
    "2026-06-10",
    2,
  );
  const repairAttempt = buildDeepSeekDayChatRequest(
    {
      ...input,
      day_retry_context: {
        retry_kind: "validation_repair",
        retry_reason: "invalid_generated_week",
        validation_error: { rule: "scene_count", path: "scene_list" },
        error_message: "scene_list must include at least one scene",
      },
    },
    "deepseek-v4-pro",
    "2026-06-10",
    2,
  );
  const repairUserPayload = JSON.parse(
    (repairAttempt.messages as Record<string, string>[])[1].content
      .split("\n")[0],
  );
  const repairInput = recordValue(repairUserPayload.input);

  assert(
    JSON.stringify(repairAttempt).length <
      JSON.stringify(firstAttempt).length * 0.9,
    "repair request should be materially smaller than the first attempt",
  );
  assertEquals(recordValueArray(repairInput.confirmed_references).length, 0);
  assertEquals(recordValueArray(repairInput.reference_extractions).length, 0);
  assert(!("recent_archive" in repairInput));
  assert(!("idea_bank" in repairInput));
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

Deno.test("daily AI provider caller makes second validation attempt repair-specific", async () => {
  const input = fixtureInput();
  const retryContexts: Array<Record<string, unknown> | undefined> = [];
  const output = await callAIProvidersForDay(
    input,
    [{
      provider: "deepseek",
      model: "deepseek-v4-pro",
      apiKey: "deepseek-key",
    }],
    "2026-06-10",
    2,
    async (attemptInput, _provider, scheduledDate, dayIndex) => {
      retryContexts.push(attemptInput.day_retry_context);
      if (retryContexts.length === 1) {
        throw new GenerateWeekValidationError(
          "invalid_generated_week",
          "scene_list must include at least one scene",
        );
      }
      const card = makeMockGeneratedWeek(attemptInput).daily_cards[dayIndex];
      return {
        strategy_note: "Repaired day",
        warnings: [],
        assumptions: [],
        daily_card: { ...card, scheduled_date: scheduledDate },
        idea_bank: [],
        source_summary: "Repaired context",
      };
    },
  );

  assertEquals(output.daily_card.scheduled_date, "2026-06-10");
  assertEquals(retryContexts[0], undefined);
  assertEquals(retryContexts[1]?.retry_kind, "validation_repair");
  assertEquals(retryContexts[1]?.retry_reason, "invalid_generated_week");
  assertEquals(retryContexts[1]?.scheduled_date, "2026-06-10");
  assertEquals(retryContexts[1]?.day_index, 3);
  assertEquals(
    recordValue(retryContexts[1]?.validation_error).rule,
    "scene_count",
  );
});

Deno.test("daily OpenAI provider instrumentation logs retries, usage, finish reason, and quality metrics", async () => {
  const input = fixtureInput();
  const logs: AIGenerationAttemptLog[] = [];
  const originalFetch = globalThis.fetch;
  let fetchCount = 0;
  const validDayOutput = {
    strategy_note: "Instrumented generation",
    warnings: [],
    assumptions: [],
    daily_card: makeMockGeneratedWeek(input).daily_cards[2],
    idea_bank: [],
    source_summary: "Used confirmed references.",
  };

  globalThis.fetch = () => {
    fetchCount += 1;
    if (fetchCount === 1) {
      return Promise.resolve(openAIResponse({
        outputText: JSON.stringify({ daily_card: {} }),
        inputTokens: 101,
        outputTokens: 31,
        totalTokens: 132,
        finishReason: "stop",
      }));
    }
    return Promise.resolve(openAIResponse({
      outputText: JSON.stringify(validDayOutput),
      inputTokens: 201,
      outputTokens: 73,
      totalTokens: 274,
      finishReason: "stop",
    }));
  };

  try {
    const output = await callAIProvidersForDay(
      input,
      [{ provider: "openai", model: "gpt-4.1-mini", apiKey: "openai-key" }],
      "2026-06-10",
      2,
      undefined,
      {
        generationID: "55555555-5555-4555-8555-555555555555",
        generationScope: "day",
        phase: "regenerate_day_generation",
        logger: (log) => logs.push(log),
      },
    );

    assertEquals(output.daily_card.scheduled_date, "2026-06-10");
  } finally {
    globalThis.fetch = originalFetch;
  }

  assertEquals(fetchCount, 2);
  assertEquals(logs.length, 2);
  assertEquals(logs[0].event, "generation_ai_attempt");
  assertEquals(logs[0].generation_id, "55555555-5555-4555-8555-555555555555");
  assertEquals(logs[0].phase, "regenerate_day_generation");
  assertEquals(logs[0].scheduled_date, "2026-06-10");
  assertEquals(logs[0].provider_attempt, 1);
  assertEquals(logs[0].status, "failure");
  assertEquals(logs[0].input_tokens, 101);
  assertEquals(logs[0].output_tokens, 31);
  assertEquals(logs[0].total_tokens, 132);
  assertEquals(logs[0].finish_reason, "stop");
  assertEquals(
    logs[0].output_text_chars,
    JSON.stringify({ daily_card: {} }).length,
  );
  assertEquals(logs[0].request_metrics?.confirmed_reference_count, 0);
  assertEquals(logs[0].request_metrics?.reference_extraction_count, 0);
  assertEquals(logs[0].request_metrics?.dropped_confirmed_reference_count, 1);
  assertEquals(logs[0].request_metrics?.dropped_reference_extraction_count, 1);
  assertEquals(
    logs[0].request_metrics?.request_input_version,
    "creator_day_prompt_input_v2",
  );
  assertEquals(logs[0].request_metrics?.request_timeout_ms, 240_000);
  assert(
    (logs[0].request_metrics?.prompt_total_chars ?? 0) > 0,
    "prompt size metrics should be logged",
  );
  assert(
    (logs[0].request_metrics?.reference_context_chars ?? 0) > 0,
    "reference context size metrics should be logged",
  );
  assertEquals(logs[0].quality_score, null);
  assertEquals(logs[0].error_category, "invalid_generated_week");
  assertEquals(logs[0].validation_error?.stage, "output_validation");
  assertEquals(logs[0].validation_error?.rule, "scene_count");
  assertEquals(logs[0].validation_error?.path, "scene_list");
  assertEquals(logs[0].validation_error?.retryable, true);

  assertEquals(logs[1].provider_attempt, 2);
  assertEquals(logs[1].status, "success");
  assertEquals(logs[1].input_tokens, 201);
  assertEquals(logs[1].output_tokens, 73);
  assertEquals(logs[1].total_tokens, 274);
  assertEquals(
    logs[1].output_text_chars,
    JSON.stringify(validDayOutput).length,
  );
  assertEquals(logs[1].request_metrics?.confirmed_reference_count, 0);
  assertEquals(logs[1].request_metrics?.reference_extraction_count, 0);
  assertEquals(logs[1].request_metrics?.dropped_confirmed_reference_count, 1);
  assertEquals(logs[1].request_metrics?.dropped_reference_extraction_count, 1);
  assertEquals(
    logs[1].request_metrics?.request_input_version,
    "creator_day_prompt_repair_input_v2",
  );
  assertEquals(logs[1].request_metrics?.request_timeout_ms, 240_000);
  assert(
    (logs[1].request_metrics?.dropped_reference_context_chars ?? 0) > 0,
    "repair retry should log dropped reference context unless the failure needs it",
  );
  assertEquals(logs[1].quality_version, "instagram_content_quality_v2");
  assertEquals(logs[1].quality_metrics?.pillar_count, 1);
  assertEquals(logs[1].quality_metrics?.instructor_phrase_count, 0);
  assertEquals(logs[1].quality_metrics?.instructor_ending_count, 0);
  assertEquals(logs[1].quality_metrics?.hook_first_3s_present, true);
  assertEquals(logs[1].quality_metrics?.watch_without_sound_ready, true);
  assertEquals(logs[1].quality_metrics?.clear_cta_present, true);
  assertEquals(logs[1].quality_metrics?.creator_lived_detail_present, true);
  assertEquals(logs[1].quality_metrics?.source_reference_link_count, 1);
  assertEquals(logs[1].quality_metrics?.cards_with_source_reference_count, 1);
  assert(
    (logs[1].quality_score ?? 0) > 80,
    "valid generated day should have a high operational quality score",
  );
  assertEquals(logs[1].error_category, null);
  assertEquals(logs[1].error_message, null);
  assertEquals(logs[1].validation_error, null);
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

Deno.test("mock generation week keeps Thursday and Friday aligned to their pillars", () => {
  const generated = makeMockGeneratedWeek(fixtureInput());
  const thursday = generated.daily_cards[3];
  const friday = generated.daily_cards[4];

  assertEquals(thursday.content_pillar, "eating");
  assert(thursday.title.toLowerCase().includes("meal"));
  assert(thursday.hook.toLowerCase().includes("meal"));
  assert(thursday.caption.toLowerCase().includes("meal"));

  assertEquals(friday.content_pillar, "lifestyle");
  assert(friday.title.toLowerCase().includes("habit"));
  assert(friday.hook.toLowerCase().includes("habit"));
  assert(!friday.title.toLowerCase().includes("core"));
  assert(!friday.caption.toLowerCase().includes("core"));
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

Deno.test("prompt enforces CTA diversity: max 2 save CTAs, bans template fillers", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assert(guidance.includes("cta_diversity_rules"));
  assertIncludesAll(guidance, [
    "at most 2 explicit save CTAs",
    "Do not end every script by instructing the audience",
    "punchline, natural observation, or a genuinely earned question",
    "save-this/share-this/tag-someone tack-on",
    "banned_cta_templates",
    "save this",
    "tell me",
    "send to a friend",
    "tag someone who",
    "share this with",
    "comment below",
    "follow for more",
    "like and save",
    "dm me",
  ]);
});

Deno.test("prompt includes banned instructor endings observed in live run", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assertIncludesAll(guidance, [
    "banned_instructor_endings",
    "just start",
    "one set, then the next",
    "if you needed a reminder",
    "the real win",
    "Never end a script by instructing the audience",
  ]);
});

Deno.test("prompt enforces factual discipline: no invented facts", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assert(guidance.includes("factual_discipline_rules"));
  assertIncludesAll(guidance, [
    "Use only supplied profile, weekly brief, confirmed reference facts",
    "Never invent",
    "biography details",
    "exact quotes",
    "family reactions",
    "equipment failures",
    "Place any uncertainty in assumptions or risk_notes",
    "Do not fabricate facts to fill gaps",
  ]);
});

Deno.test("prompt caps age to at most one card per ordinary week", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assertIncludesAll(guidance, [
    "Mention age in at most one card per ordinary week",
    "at most one card per ordinary week unless the weekly brief explicitly centers age",
  ]);
});

Deno.test("prompt requires non-training cards to have genuinely non-training centers", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assertIncludesAll(guidance, [
    "Every non-training card must have a genuinely non-training center",
    "Never relabel a gym script as lifestyle",
    "the content must earn its pillar",
  ]);
});

Deno.test("prompt defaults to exactly 2 training concepts, allows brief override", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assertIncludesAll(guidance, [
    "exactly 2 training/HYROX-led concepts",
    "Default to exactly 2 training/HYROX-led concepts",
    "operational mix",
    "day routines may anchor non-training lifestyle, eating, or recovery concepts",
  ]);
});

Deno.test("prompt preserves four-pillar contract and schema unchanged", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assertIncludesAll(guidance, [
    "gym",
    "lifestyle",
    "eating",
    "recovery",
    "four_pillar_contract",
    "Output content_pillar must remain one of gym, lifestyle, eating, or recovery",
    "six_pillar_brand_lens",
    "HYROX and serious training",
    "production_pillar",
  ]);
});

// ── F1: Per-day prompt includes week-level quota constraints ──

Deno.test("per-day system prompt mirrors quota constraints: factual discipline, CTA cap, age cap, instructor-ending ban, non-training-center rule", () => {
  const request = buildDeepSeekDayChatRequest(
    fixtureInput(),
    "deepseek-v4-pro",
    "2026-06-10",
    2,
  );
  const messages = request.messages as Record<string, string>[];
  const systemPrompt = messages[0].content as string;

  assertIncludesAll(systemPrompt, [
    "Never invent biography",
    "equipment failures",
    "Place any uncertainty in assumptions or risk_notes",
    "Explicit save CTA",
    "at most two named weekdays",
    "end with punchline",
    "earned question",
    "Mention age on at most one named weekday",
    "Never default to age as a hook",
    "non-training card",
    "genuinely non-training center",
    "Never relabel a gym script as lifestyle",
    "Reject instructor endings",
    "just start",
    "one set, then the next",
    "the real win",
    "do NOT end every script with a save CTA",
  ]);
});

Deno.test("weekly prompt retains all original quota constraints unchanged", () => {
  const prompt = buildPromptMessages(fixtureInput());

  assertIncludesAll(prompt.system, [
    "at most 2 explicit save CTAs",
    "Mention age in at most one card",
    "exactly 2 training/HYROX-led concepts",
    "Reject instructor endings",
    "just start",
    "the real win",
    "Every non-training card must have a genuinely non-training center",
    "Never invent biography",
    "Use only supplied profile, brief, and confirmed reference facts",
  ]);
});

// ── F2: Deterministic role/CTA allocation in dayIntentForScheduledDate ──

Deno.test("day intent assigns deterministic weekday roles: training-led Mon/Wed, eating Thu, lifestyle Fri, experimental Sat, recovery Sun", () => {
  const input = fixtureInput();
  const dateIntents: Record<string, string> = {};
  for (const date of weekDates("2026-06-08")) {
    const request = buildDeepSeekDayChatRequest(
      input,
      "deepseek-v4-pro",
      date,
      0,
    );
    const messages = request.messages as Record<string, string>[];
    const userContent = messages[1].content as string;
    const userPayload = JSON.parse(userContent.split("\n")[0]);
    const intent = userPayload.target.day_intent as string;
    dateIntents[date] = intent;
  }

  assert(
    dateIntents["2026-06-08"].includes("training-led"),
    `Monday should be training-led, got: ${dateIntents["2026-06-08"]}`,
  );
  assert(
    dateIntents["2026-06-10"].includes("training-led"),
    `Wednesday should be training-led, got: ${dateIntents["2026-06-10"]}`,
  );
  assert(
    dateIntents["2026-06-11"].includes("eating"),
    `Thursday should be eating, got: ${dateIntents["2026-06-11"]}`,
  );
  assert(
    dateIntents["2026-06-12"].includes("lifestyle"),
    `Friday should be lifestyle, got: ${dateIntents["2026-06-12"]}`,
  );
  assert(
    dateIntents["2026-06-13"].includes("experimental lifestyle"),
    `Saturday should be experimental lifestyle, got: ${
      dateIntents["2026-06-13"]
    }`,
  );
  assert(
    dateIntents["2026-06-14"].includes("recovery/family"),
    `Sunday should be recovery/family, got: ${dateIntents["2026-06-14"]}`,
  );
  assert(
    dateIntents["2026-06-09"].includes("recovery/eating/lifestyle"),
    `Tuesday should be recovery/eating/lifestyle, got: ${
      dateIntents["2026-06-09"]
    }`,
  );
});

Deno.test("day intent assigns save CTA eligibility to Monday and Wednesday only", () => {
  const input = fixtureInput();

  const mondayIntent = dayIntentFromPrompt(input, "2026-06-08");
  const wedIntent = dayIntentFromPrompt(input, "2026-06-10");
  assert(
    mondayIntent.includes("save CTA eligible"),
    `Monday: save CTA eligible, got: ${mondayIntent}`,
  );
  assert(
    wedIntent.includes("save CTA eligible"),
    `Wednesday: save CTA eligible, got: ${wedIntent}`,
  );

  const nonEligibleDates = [
    "2026-06-09",
    "2026-06-11",
    "2026-06-12",
    "2026-06-13",
    "2026-06-14",
  ];
  for (const date of nonEligibleDates) {
    const intent = dayIntentFromPrompt(input, date);
    assert(
      intent.includes("save CTA NOT eligible"),
      `Expected save CTA NOT eligible for ${date}, got: ${intent}`,
    );
  }
});

Deno.test("day intent assigns age eligibility to Monday only, never required", () => {
  const input = fixtureInput();

  const mondayIntent = dayIntentFromPrompt(input, "2026-06-08");
  assert(
    mondayIntent.includes("Age eligible if the weekly brief supports it"),
    `Monday: age eligible if brief supports it, got: ${mondayIntent}`,
  );
  assert(
    mondayIntent.includes("never required"),
    `Monday: age never required, got: ${mondayIntent}`,
  );

  const nonEligibleDates = [
    "2026-06-09",
    "2026-06-10",
    "2026-06-11",
    "2026-06-12",
    "2026-06-13",
    "2026-06-14",
  ];
  for (const date of nonEligibleDates) {
    const intent = dayIntentFromPrompt(input, date);
    assert(
      intent.includes("Age NOT eligible on this day"),
      `Expected Age NOT eligible for ${date}, got: ${intent}`,
    );
  }
});

Deno.test("day intent overrides non-training roles when weekly brief explicitly asks for gym-focused week", () => {
  const gymFocusInput: GenerationInputSnapshot = {
    ...fixtureInput(),
    weekly_setup: {
      id: "77777777-7777-4777-8777-777777777771",
      location: "Bombay",
      notes: "Weekly brief: gym focused week. Five training days this week.",
    },
  };

  const thursdayIntent = dayIntentFromPrompt(gymFocusInput, "2026-06-11");
  assert(
    thursdayIntent.includes("training-led"),
    `Thursday should be training-led in gym focus week, got: ${thursdayIntent}`,
  );
  assert(
    !thursdayIntent.includes("eating"),
    "Thursday should NOT be eating in gym focus week",
  );
});

// ── F3/F6: Template no longer contains 'Save this' as example text ──

Deno.test("daily card compact template does not include 'Save this' in on_screen_text", () => {
  const request = buildDeepSeekDayChatRequest(
    fixtureInput(),
    "deepseek-v4-pro",
    "2026-06-10",
    2,
  );
  const requestText = JSON.stringify(request);

  assert(
    !requestText.includes('"Save this"'),
    "Template on_screen_text must not contain 'Save this' as example text",
  );
});

// ── F4: BANNED_CTA_TEMPLATES uses full patterns, not broad substrings ──

Deno.test("BANNED_CTA_TEMPLATES contains full CTA patterns, not bare 'tell me'", () => {
  assert(
    !BANNED_CTA_TEMPLATES.includes("tell me"),
    "'tell me' alone is overbroad and must not be in BANNED_CTA_TEMPLATES",
  );
  assert(
    BANNED_CTA_TEMPLATES.includes("tell me in the comments"),
    "'tell me in the comments' should be in BANNED_CTA_TEMPLATES",
  );
  assert(
    BANNED_CTA_TEMPLATES.includes("tell me what you think"),
    "'tell me what you think' should be in BANNED_CTA_TEMPLATES",
  );
  assert(
    BANNED_CTA_TEMPLATES.includes("save this for"),
    "'save this for' should be in BANNED_CTA_TEMPLATES",
  );
  assert(
    BANNED_CTA_TEMPLATES.includes("send this to a friend"),
    "'send this to a friend' should be in BANNED_CTA_TEMPLATES",
  );
});

// ── F5: INSTRUCTOR_ISH_PHRASES excludes bare 'clients' and first-person 'fix my form' ──

Deno.test("INSTRUCTOR_ISH_PHRASES excludes bare 'clients' and 'fix my form' while retaining coaching-specific phrases", () => {
  assert(
    !INSTRUCTOR_ISH_PHRASES.includes("clients"),
    "bare 'clients' must not be in INSTRUCTOR_ISH_PHRASES",
  );
  assert(
    !INSTRUCTOR_ISH_PHRASES.includes("fix my form"),
    "'fix my form' must not be in INSTRUCTOR_ISH_PHRASES",
  );
  assert(
    INSTRUCTOR_ISH_PHRASES.includes("your client"),
    "'your client' should remain",
  );
  assert(
    INSTRUCTOR_ISH_PHRASES.includes("my clients"),
    "'my clients' should remain",
  );
  assert(
    INSTRUCTOR_ISH_PHRASES.includes("training clients"),
    "'training clients' should be present",
  );
});

Deno.test("containsInstructorPhrasing still catches coaching language but allows first-person 'fix my form' and brand-collab 'clients'", () => {
  assert(
    containsInstructorPhrasing("do this exercise"),
    "should catch 'do this exercise'",
  );
  assert(
    containsInstructorPhrasing("your client needs"),
    "should catch 'your client'",
  );
  assert(
    containsInstructorPhrasing("my clients ask me"),
    "should catch 'my clients'",
  );
  assert(
    containsInstructorPhrasing("upper body cue for today"),
    "should catch 'upper body cue'",
  );

  assert(
    !containsInstructorPhrasing("I had to fix my form on the sled push today"),
    "first-person 'fix my form' should be allowed",
  );
  assert(
    !containsInstructorPhrasing("worked with a new brand client today"),
    "brand-collab 'client' should be allowed",
  );
  assert(
    !containsInstructorPhrasing("the brand client loved the reel"),
    "brand-collab 'client' in context should be allowed",
  );
});

// ── F6: Runtime instructor-ending rejection ──

Deno.test("containsInstructorEnding catches banned instructor endings in card text", () => {
  assert(
    containsInstructorEnding("just start. One set, then the next."),
    "should catch 'just start'",
  );
  assert(
    containsInstructorEnding("the real win is showing up"),
    "should catch 'the real win'",
  );
  assert(
    containsInstructorEnding("if you needed a reminder, here it is"),
    "should catch 'if you needed a reminder'",
  );
  assert(
    containsInstructorEnding("you can do this. I believe in you."),
    "should catch 'you can do this'",
  );
  assert(
    containsInstructorEnding("you got this. Keep going."),
    "should catch 'you got this'",
  );
  assert(
    containsInstructorEnding("no excuses. Get it done."),
    "should catch 'no excuses'",
  );

  assert(
    !containsInstructorEnding("I noticed the sled felt heavier today"),
    "first-person observation should be allowed",
  );
  assert(
    !containsInstructorEnding("today felt like a real win for my consistency"),
    "first-person 'real win' used descriptively about own experience is a substring match but the pattern 'the real win' is banned — verify it catches the instructor form",
  );
  // 'the real win' as a follower-directed ending IS banned:
  assert(
    containsInstructorEnding("remember, the real win is showing up"),
    "'the real win' as follower-directed ending should be caught",
  );
});

Deno.test("countExplicitSaveCTAs counts save-this patterns across cta, script, caption, on_screen_text, and backup copy with each card counted at most once", () => {
  // Card 0: save CTA in cta field only → counted
  // Card 1: save CTA in script field only → counted
  // Card 2: save CTA in both cta and caption → counted once (not twice)
  assertEquals(
    countExplicitSaveCTAs([
      {
        cta: "Save this for your next session.",
        script: "Good script.",
        caption: "Nice caption.",
        on_screen_text: [],
        backup_story: "",
        backup_caption_only: "",
        caption_backup_detail: "",
      } as never,
      {
        cta: "Just a thought.",
        script: "A script that says Save this reel if it helps.",
        caption: "Nice caption.",
        on_screen_text: [],
        backup_story: "",
        backup_caption_only: "",
        caption_backup_detail: "",
      } as never,
      {
        cta: "Save this for later.",
        script: "Good script.",
        caption: "Also says Save this to your routine.",
        on_screen_text: [],
        backup_story: "",
        backup_caption_only: "",
        caption_backup_detail: "",
      } as never,
    ]),
    3,
    "should count 3 cards with save CTAs across multiple fields, each card at most once",
  );

  // No save CTAs
  assertEquals(
    countExplicitSaveCTAs([
      {
        cta: "What do you think?",
        script: "A reflective script.",
        caption: "Nice caption.",
        on_screen_text: ["Back in routine"],
        backup_story: "A story backup.",
        backup_caption_only: "",
        caption_backup_detail: "",
      } as never,
      {
        cta: "Try this cue in your next session.",
        script: "A practical script.",
        caption: "A helpful caption.",
        on_screen_text: [],
        backup_story: "",
        backup_caption_only: "",
        caption_backup_detail: "",
      } as never,
    ]),
    0,
    "should count 0 when no save CTAs present",
  );
});

Deno.test("countExplicitSaveCTAs counts save text appearing in scripts and backup copy, not just cta", () => {
  // Save CTA in script
  assertEquals(
    countExplicitSaveCTAs([
      {
        cta: "What do you think?",
        script: "Try this setup and save this for your next session.",
        caption: "Good caption.",
        on_screen_text: [],
        backup_story: "",
        backup_caption_only: "",
        caption_backup_detail: "",
      } as never,
    ]),
    1,
    "save this for in script should count",
  );

  // Save CTA in backup_story
  assertEquals(
    countExplicitSaveCTAs([
      {
        cta: "Any thoughts?",
        script: "Good script.",
        caption: "Nice caption.",
        on_screen_text: [],
        backup_story: "Save this for a quick reset when you are short on time.",
        backup_caption_only: "",
        caption_backup_detail: "",
      } as never,
    ]),
    1,
    "save this for in backup_story should count",
  );

  // Save CTA in on_screen_text
  assertEquals(
    countExplicitSaveCTAs([
      {
        cta: "Share your thoughts.",
        script: "Good script.",
        caption: "Nice caption.",
        on_screen_text: ["Save this for later"],
        backup_story: "",
        backup_caption_only: "",
        caption_backup_detail: "",
      } as never,
    ]),
    1,
    "save this for in on_screen_text should count",
  );
});

Deno.test("countExplicitSaveCTAs does not count ordinary 'save time' or 'saved my breakfast' or 'I save this kind of'", () => {
  assertEquals(
    countExplicitSaveCTAs([
      {
        cta: "Share your morning routine!",
        script: "This will save time in the morning.",
        caption: "I saved my breakfast for later.",
        on_screen_text: ["Save time", "Morning reset"],
        backup_story: "Saving a few minutes helps.",
        backup_caption_only: "",
        caption_backup_detail: "",
      } as never,
      {
        cta: "What do you think?",
        script: "I save this kind of energy for the moments that matter.",
        caption: "Save your energy.",
        on_screen_text: [],
        backup_story: "",
        backup_caption_only: "",
        caption_backup_detail: "",
      } as never,
    ]),
    0,
    "ordinary non-CTA uses of 'save' should not count",
  );
});

// ── AI request timeout resolution ──

Deno.test("resolveAIRequestTimeoutMs returns 240_000 as default", () => {
  assertEquals(resolveAIRequestTimeoutMs(undefined), 240_000);
});

Deno.test("resolveAIRequestTimeoutMs accepts valid override", () => {
  assertEquals(resolveAIRequestTimeoutMs("60000"), 60_000);
});

Deno.test("resolveAIRequestTimeoutMs falls back to default when override is not a number", () => {
  assertEquals(resolveAIRequestTimeoutMs("abc"), 240_000);
});

Deno.test("resolveAIRequestTimeoutMs falls back to default below 5_000 ms minimum", () => {
  assertEquals(resolveAIRequestTimeoutMs("4000"), 240_000);
});

Deno.test("resolveAIRequestTimeoutMs applies maximum cap of 240_000 ms", () => {
  assertEquals(resolveAIRequestTimeoutMs("999999"), 240_000);
});

Deno.test("resolveAIDayRequestTimeoutMs inherits the general timeout by default", () => {
  assertEquals(resolveAIDayRequestTimeoutMs(undefined, "180000"), 180_000);
});

Deno.test("resolveAIDayRequestTimeoutMs accepts a day-specific override", () => {
  assertEquals(resolveAIDayRequestTimeoutMs("150000", "240000"), 150_000);
});

Deno.test("resolveAIDayRequestTimeoutMs keeps the 240_000 cap", () => {
  assertEquals(resolveAIDayRequestTimeoutMs("999999", "180000"), 240_000);
});

// ── Four pillars preserved ──

Deno.test("per-day prompt includes concise 40-70 word caption rule", () => {
  const request = buildDeepSeekDayChatRequest(
    fixtureInput(),
    "deepseek-v4-pro",
    "2026-06-10",
    2,
  );
  const messages = request.messages as Record<string, string>[];
  const systemPrompt = messages[0].content as string;
  const userContent = messages[1].content as string;

  assert(
    systemPrompt.includes("40-70 words"),
    "system prompt should include 40-70 word caption target",
  );
  assert(
    systemPrompt.includes("concise Instagram caption"),
    "system prompt should instruct for concise caption",
  );

  const userPayload = JSON.parse(userContent.split("\n")[0]);
  const template = recordValue(userPayload.required_contract)
    .daily_card_template as Record<string, unknown>;
  assert(
    (template.caption as string).includes("40-70 word"),
    "template caption should specify 40-70 word target",
  );
});

Deno.test("per-day prompt includes day_guidance scoped to target scheduled date", () => {
  const input = {
    ...fixtureInput(),
    day_guidance:
      "Thursday brand brief: highlight the new recovery product launch.",
  };
  const request = buildDeepSeekDayChatRequest(
    input,
    "deepseek-v4-pro",
    "2026-06-11",
    3,
  );
  const messages = request.messages as Record<string, string>[];
  const userContent = messages[1].content as string;

  assert(
    userContent.includes(
      "Thursday brand brief: highlight the new recovery product launch.",
    ),
    "per-day prompt should include day_guidance text",
  );
  assert(
    userContent.includes(
      "Creator/admin instruction for 2026-06-11 ONLY (not week-wide)",
    ),
    "day_guidance should be labeled as scoped to the target date only",
  );
  assert(
    userContent.includes("not week-wide"),
    "day_guidance should explicitly state it is NOT week-wide",
  );
});

Deno.test("per-day prompt guidance does not become week-wide instruction", () => {
  const input = {
    ...fixtureInput(),
    day_guidance: "Brand collab: feature the hydration brand.",
  };
  const wednesdayRequest = buildDeepSeekDayChatRequest(
    input,
    "deepseek-v4-pro",
    "2026-06-10",
    2,
  );
  const wednesdayContent =
    (wednesdayRequest.messages as Record<string, string>[])[1]
      .content as string;

  assert(
    wednesdayContent.includes("Brand collab: feature the hydration brand."),
    "Wednesday should have the day_guidance",
  );

  const fridayRequest = buildDeepSeekDayChatRequest(
    input,
    "deepseek-v4-pro",
    "2026-06-12",
    4,
  );
  const fridayContent = (fridayRequest.messages as Record<string, string>[])[1]
    .content as string;

  assert(
    fridayContent.includes(
      "Creator/admin instruction for 2026-06-12 ONLY (not week-wide)",
    ),
    "Friday scoping label should reference Friday's date, not inherit Wednesday's",
  );
});

Deno.test("week-wide prompt does not include day_guidance", () => {
  const input = {
    ...fixtureInput(),
    day_guidance: "This should not appear in week-wide prompts.",
  };
  const prompt = buildPromptMessages(input);

  assert(
    !prompt.user.includes("Creator/admin instruction"),
    "week-wide prompt must not include day_guidance instruction labels",
  );
  assert(
    !prompt.system.includes("day_guidance"),
    "week-wide system prompt must not include day_guidance references",
  );
});

Deno.test("per-day prompt without day_guidance omits the instruction block", () => {
  const request = buildDeepSeekDayChatRequest(
    fixtureInput(),
    "deepseek-v4-pro",
    "2026-06-10",
    2,
  );
  const messages = request.messages as Record<string, string>[];
  const userContent = messages[1].content as string;

  assert(
    !userContent.includes("Creator/admin instruction for"),
    "prompt without day_guidance should not include the instruction block",
  );
});

Deno.test("daily card template caption is 40-70 words, not 80-140", () => {
  const request = buildDeepSeekDayChatRequest(
    fixtureInput(),
    "deepseek-v4-pro",
    "2026-06-10",
    2,
  );
  const requestText = JSON.stringify(request);

  assert(
    requestText.includes("40-70 word"),
    "template caption should specify 40-70 words",
  );
  assert(
    !requestText.includes("80-140"),
    "daily card prompt must not reference the old 80-140 word range",
  );
});

Deno.test("instagram_defaults guidance uses concise 40-70 caption target", () => {
  const prompt = buildPromptMessages(fixtureInput());
  const guidance = `${prompt.system}\n${prompt.user}`;

  assertIncludesAll(guidance, [
    "40-70 words",
    "half the length",
    "one natural CTA",
  ]);
  assert(
    !guidance.includes("80-140"),
    "generation guidance must not reference the old 80-140 word range",
  );
});

function dayIntentFromPrompt(
  input: GenerationInputSnapshot,
  scheduledDate: string,
): string {
  const request = buildDeepSeekDayChatRequest(
    input,
    "deepseek-v4-pro",
    scheduledDate,
    0,
  );
  const messages = request.messages as Record<string, string>[];
  const userContent = messages[1].content as string;
  const userPayload = JSON.parse(userContent.split("\n")[0]);
  return userPayload.target.day_intent as string;
}

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

function openAIResponse(
  config: {
    outputText: string;
    inputTokens: number;
    outputTokens: number;
    totalTokens: number;
    finishReason: string;
  },
): Response {
  return new Response(
    JSON.stringify({
      output_text: config.outputText,
      output: [{
        finish_reason: config.finishReason,
        content: [{ text: config.outputText }],
      }],
      usage: {
        input_tokens: config.inputTokens,
        output_tokens: config.outputTokens,
        total_tokens: config.totalTokens,
      },
    }),
    { status: 200 },
  );
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

function recordValueArray(value: unknown): Record<string, unknown>[] {
  assert(Array.isArray(value), `Expected array, got ${JSON.stringify(value)}`);
  return value.map(recordValue);
}
