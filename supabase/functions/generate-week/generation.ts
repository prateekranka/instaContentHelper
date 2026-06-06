export type GenerateWeekMode = "generate_draft" | "regenerate_draft";

export type GenerateWeekRequest = {
  creator_id: string;
  week_start_date: string;
  weekly_setup_id?: string;
  mode: GenerateWeekMode;
  preserve_manual_edits: boolean;
  mock: boolean;
  input_overrides?: Record<string, unknown>;
};

export type GenerationInputSnapshot = {
  creator_id: string;
  week_start_date: string;
  creator_profile: Record<string, unknown> | null;
  weekly_setup: Record<string, unknown> | null;
  confirmed_references: Record<string, unknown>[];
  reference_extractions: Record<string, unknown>[];
  recent_archive: Record<string, unknown>[];
  idea_bank: Record<string, unknown>[];
  patterns: Record<string, unknown>[];
  trends: Record<string, unknown>[];
  audio_options: Record<string, unknown>[];
  brand_briefs: Record<string, unknown>[];
  key_moments: Record<string, unknown>[];
};

export type GeneratedScene = {
  number: number;
  title: string;
  duration: string;
  symbol: string;
};

export type GeneratedDailyCard = {
  id?: string;
  scheduled_date: string;
  title: string;
  why_today: string;
  growth_job: string;
  content_pillar: string;
  shootability: string;
  estimated_shoot_minutes: number;
  energy_required: string;
  language_mode: string;
  scene_list: GeneratedScene[];
  script: string;
  no_voiceover_version: string;
  on_screen_text: string[];
  caption: string;
  cta: string;
  hashtags: string[];
  cover_text: string;
  post_instructions: string;
  brand_event_notes: string;
  backup_story: string;
  backup_caption_only: string;
  audio_option_notes: string;
  mamta_fit_score: number;
  risk_notes: string[];
  assumptions: string[];
  source_note: string;
  source_reference_ids: string[];
};

export type GeneratedIdea = {
  title: string;
  summary: string;
  suggested_use: string;
  shootability: string;
  tags: string[];
  fit_score: number;
  source_note: string;
  status: "saved" | "scheduled";
};

export type GeneratedWeekOutput = {
  strategy_summary: string;
  warnings: string[];
  assumptions: string[];
  daily_cards: GeneratedDailyCard[];
  idea_bank: GeneratedIdea[];
  source_summary: string;
};

export type AIProviderName = "deepseek" | "openai";

export type AIProviderConfig = {
  provider: AIProviderName;
  model: string;
  apiKey: string;
  baseURL?: string;
};

export function preserveManualDailyCardEdits(
  card: GeneratedDailyCard,
  existing: Record<string, unknown> | undefined,
): GeneratedDailyCard {
  if (!existing) {
    return card;
  }

  return {
    ...card,
    title: optionalNonBlankString(existing.title) ?? card.title,
    why_today: optionalNonBlankString(existing.why_today) ?? card.why_today,
    shootability: optionalNonBlankString(existing.shootability) ??
      card.shootability,
    estimated_shoot_minutes: optionalNonNegativeInteger(
      existing.estimated_shoot_minutes,
    ) ??
      card.estimated_shoot_minutes,
    scene_list: optionalSceneList(existing.scene_list) ?? card.scene_list,
    caption: optionalNonBlankString(existing.caption) ?? card.caption,
    backup_story: storedBackupLine(existing.backup_story) ??
      card.backup_story,
    backup_caption_only: storedBackupLine(existing.backup_caption_only) ??
      card.backup_caption_only,
  };
}

export type GenerateWeekValidationCode =
  | "invalid_generation_payload"
  | "invalid_ai_json"
  | "invalid_generated_week";

export class GenerateWeekValidationError extends Error {
  constructor(readonly code: GenerateWeekValidationCode, message: string) {
    super(message);
    this.name = "GenerateWeekValidationError";
  }
}

export function normalizeGenerateWeekRequest(
  body: unknown,
): GenerateWeekRequest {
  if (!isRecord(body)) {
    throw new GenerateWeekValidationError(
      "invalid_generation_payload",
      "Request body must be an object.",
    );
  }

  const creatorID = stringValue(body.creator_id);
  const weekStartDate = stringValue(body.week_start_date);
  const weeklySetupID = stringValue(body.weekly_setup_id);
  const requestedMode = stringValue(body.mode) ?? "generate_draft";
  const preserveManualEdits = body.preserve_manual_edits === true;
  const mock = body.mock === true;
  const inputOverrides = isRecord(body.input_overrides)
    ? body.input_overrides
    : undefined;

  if (!isUUID(creatorID) || !isDateString(weekStartDate)) {
    throw new GenerateWeekValidationError(
      "invalid_generation_payload",
      "creator_id and week_start_date are required.",
    );
  }

  if (weeklySetupID !== undefined && !isUUID(weeklySetupID)) {
    throw new GenerateWeekValidationError(
      "invalid_generation_payload",
      "weekly_setup_id must be a UUID.",
    );
  }

  if (
    requestedMode !== "generate_draft" &&
    requestedMode !== "regenerate_draft"
  ) {
    throw new GenerateWeekValidationError(
      "invalid_generation_payload",
      "mode must be generate_draft or regenerate_draft.",
    );
  }

  return {
    creator_id: creatorID,
    week_start_date: weekStartDate,
    weekly_setup_id: weeklySetupID,
    mode: requestedMode,
    preserve_manual_edits: preserveManualEdits,
    mock,
    input_overrides: inputOverrides,
  };
}

export function buildPromptMessages(input: GenerationInputSnapshot): {
  system: string;
  user: string;
} {
  return {
    system: [
      "You generate Mamta Content OS weekly content as strict JSON.",
      "Use only the provided creator profile, weekly setup, confirmed references and extractions, brand obligations, key moments, archive feedback, and idea bank.",
      "Generate exactly seven daily cards for the requested week.",
      "Prioritize shootability, calm practical tone, and creator safety over trend chasing.",
      "Avoid all no-go topics and surface assumptions or risks instead of inventing facts.",
    ].join(" "),
    user: JSON.stringify({
      task: "Generate one draft weekly plan for review before publishing.",
      required_output:
        "JSON only. Match the supplied contract exactly. Do not return idea stubs.",
      required_contract: generatedWeekOutputContract(input.week_start_date),
      input,
    }),
  };
}

export function buildOpenAIResponsesRequest(
  input: GenerationInputSnapshot,
  model: string,
): Record<string, unknown> {
  const messages = buildPromptMessages(input);
  return {
    model,
    input: [
      { role: "system", content: messages.system },
      { role: "user", content: messages.user },
    ],
    text: {
      format: {
        type: "json_schema",
        name: "mamta_weekly_generation",
        strict: true,
        schema: generatedWeekJSONSchema,
      },
    },
  };
}

export function buildDeepSeekChatRequest(
  input: GenerationInputSnapshot,
  model: string,
): Record<string, unknown> {
  const messages = buildPromptMessages(input);
  return {
    model,
    messages: [
      { role: "system", content: messages.system },
      {
        role: "user",
        content: [
          messages.user,
          "Return one valid JSON object only. Do not wrap the JSON in Markdown.",
          "Every daily_cards item must include scheduled_date, title, why_today, growth_job, content_pillar, shootability, estimated_shoot_minutes, energy_required, language_mode, scene_list, script, no_voiceover_version, on_screen_text, caption, cta, hashtags, cover_text, post_instructions, brand_event_notes, backup_story, backup_caption_only, audio_option_notes, mamta_fit_score, risk_notes, assumptions, source_note, and source_reference_ids.",
          "Never use day_of_week instead of scheduled_date.",
        ].join("\n"),
      },
    ],
    response_format: { type: "json_object" },
    max_tokens: 8192,
    temperature: 0.2,
  };
}

function generatedWeekOutputContract(
  weekStartDate: string,
): Record<string, unknown> {
  return {
    top_level_required: [
      "strategy_summary",
      "warnings",
      "assumptions",
      "daily_cards",
      "idea_bank",
      "source_summary",
    ],
    daily_cards: {
      length: 7,
      scheduled_dates_in_order: weekDates(weekStartDate),
      example_daily_card: generatedDailyCardExample(weekStartDate),
      required_fields: [
        "scheduled_date",
        "title",
        "why_today",
        "growth_job",
        "content_pillar",
        "shootability",
        "estimated_shoot_minutes",
        "energy_required",
        "language_mode",
        "scene_list",
        "script",
        "no_voiceover_version",
        "on_screen_text",
        "caption",
        "cta",
        "hashtags",
        "cover_text",
        "post_instructions",
        "brand_event_notes",
        "backup_story",
        "backup_caption_only",
        "audio_option_notes",
        "mamta_fit_score",
        "risk_notes",
        "assumptions",
        "source_note",
        "source_reference_ids",
      ],
      field_types: {
        scheduled_date: "YYYY-MM-DD string from scheduled_dates_in_order",
        estimated_shoot_minutes: "non-negative integer",
        scene_list:
          "non-empty array of objects with number, title, duration, symbol. duration should be a string such as '5 sec'.",
        on_screen_text: "non-empty string array",
        hashtags: "non-empty string array without # characters preferred",
        mamta_fit_score: "number from 0 to 100",
        risk_notes: "string array; empty array when no risks",
        assumptions: "string array; empty array when none",
        source_reference_ids:
          "array of confirmed source reference UUID strings when available; otherwise empty array",
      },
    },
    idea_bank_item_required: [
      "title",
      "summary",
      "suggested_use",
      "shootability",
      "tags",
      "fit_score",
      "source_note",
      "status",
    ],
  };
}

function generatedDailyCardExample(
  weekStartDate: string,
): Record<string, unknown> {
  return {
    scheduled_date: weekStartDate,
    title: "Monday reset without drama",
    why_today: "A practical start to the week that is easy to shoot.",
    growth_job: "Build consistency with useful, low-drama fitness content.",
    content_pillar: "routine",
    shootability: "easy",
    estimated_shoot_minutes: 12,
    energy_required: "medium",
    language_mode: "English with light Hinglish if natural",
    scene_list: [
      {
        number: 1,
        title: "One honest opening detail",
        duration: "3 sec",
        symbol: "sparkles",
      },
    ],
    script: "Keep it simple today. One useful detail is enough.",
    no_voiceover_version:
      "Use three quiet clips with on-screen text and let the caption carry the point.",
    on_screen_text: ["Simple today", "One useful detail"],
    caption:
      "Keeping it simple today. One useful detail is enough when the week is full.",
    cta: "Save this for a low-energy training day.",
    hashtags: ["fitnessover60", "routine", "steady"],
    cover_text: "Simple today",
    post_instructions: "Keep cover text large and readable.",
    brand_event_notes: "",
    backup_story: "A 10-second story: one clip, one line, done.",
    backup_caption_only: "Caption-only backup: keeping the routine steady.",
    audio_option_notes: "Use calm audio only if it fits.",
    mamta_fit_score: 88,
    risk_notes: [],
    assumptions: ["No extra shoot support available."],
    source_note: "Adapted from confirmed Inspiration references.",
    source_reference_ids: [],
  };
}

export async function callAIProviders(
  input: GenerationInputSnapshot,
  providers: AIProviderConfig[],
  invokeProvider: (
    input: GenerationInputSnapshot,
    provider: AIProviderConfig,
  ) => Promise<GeneratedWeekOutput> = callAIProvider,
): Promise<GeneratedWeekOutput> {
  let lastError: unknown = new Error("ai_provider_request_failed");
  for (const provider of providers) {
    try {
      return await invokeProvider(input, provider);
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}

export async function callAIProvider(
  input: GenerationInputSnapshot,
  provider: AIProviderConfig,
): Promise<GeneratedWeekOutput> {
  if (provider.provider === "deepseek") {
    return await callDeepSeekChatCompletions(
      input,
      provider.model,
      provider.apiKey,
      provider.baseURL,
    );
  }
  return await callOpenAIResponses(input, provider.model, provider.apiKey);
}

export async function callDeepSeekChatCompletions(
  input: GenerationInputSnapshot,
  model: string,
  apiKey: string,
  baseURL = "https://api.deepseek.com",
): Promise<GeneratedWeekOutput> {
  const response = await fetch(
    `${baseURL.replace(/\/+$/, "")}/chat/completions`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(buildDeepSeekChatRequest(input, model)),
    },
  );

  if (!response.ok) {
    throw new Error(`deepseek_request_failed:${response.status}`);
  }

  const json = await response.json();
  const rawJSON = extractChatCompletionOutputText(json);
  if (!rawJSON) {
    throw new GenerateWeekValidationError(
      "invalid_ai_json",
      "DeepSeek response did not include output JSON.",
    );
  }

  return parseGeneratedWeekJSON(rawJSON, input.week_start_date);
}

export async function callOpenAIResponses(
  input: GenerationInputSnapshot,
  model: string,
  apiKey: string,
): Promise<GeneratedWeekOutput> {
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(buildOpenAIResponsesRequest(input, model)),
  });

  if (!response.ok) {
    throw new Error(`openai_request_failed:${response.status}`);
  }

  const json = await response.json();
  const rawJSON = extractOpenAIOutputText(json);
  if (!rawJSON) {
    throw new GenerateWeekValidationError(
      "invalid_ai_json",
      "OpenAI response did not include output JSON.",
    );
  }

  return parseGeneratedWeekJSON(rawJSON, input.week_start_date);
}

export function extractChatCompletionOutputText(
  response: unknown,
): string | null {
  if (!isRecord(response) || !Array.isArray(response.choices)) {
    return null;
  }

  for (const choice of response.choices) {
    if (!isRecord(choice) || !isRecord(choice.message)) {
      continue;
    }
    const content = stringValue(choice.message.content);
    if (content) {
      return content;
    }
  }
  return null;
}

export function extractOpenAIOutputText(response: unknown): string | null {
  if (!isRecord(response)) {
    return null;
  }

  const direct = stringValue(response.output_text);
  if (direct) {
    return direct;
  }

  if (!Array.isArray(response.output)) {
    return null;
  }

  const textParts: string[] = [];
  for (const outputItem of response.output) {
    if (!isRecord(outputItem) || !Array.isArray(outputItem.content)) {
      continue;
    }

    for (const contentItem of outputItem.content) {
      if (!isRecord(contentItem)) {
        continue;
      }
      const text = stringValue(contentItem.text);
      if (text) {
        textParts.push(text);
      }
    }
  }

  return textParts.length > 0 ? textParts.join("") : null;
}

export function parseGeneratedWeekJSON(
  rawJSON: string,
  weekStartDate: string,
): GeneratedWeekOutput {
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawJSON);
  } catch {
    throw new GenerateWeekValidationError(
      "invalid_ai_json",
      "Generated output was not valid JSON.",
    );
  }

  return validateGeneratedWeek(parsed, weekStartDate);
}

export function validateGeneratedWeek(
  value: unknown,
  weekStartDate: string,
): GeneratedWeekOutput {
  if (!isRecord(value)) {
    throw invalidWeek("Generated week must be an object.");
  }

  const strategySummary = requiredString(
    value.strategy_summary,
    "strategy_summary",
  );
  const warnings = requiredStringArray(value.warnings, "warnings");
  const assumptions = requiredStringArray(value.assumptions, "assumptions");
  const sourceSummary = requiredString(value.source_summary, "source_summary");

  if (!Array.isArray(value.daily_cards) || value.daily_cards.length !== 7) {
    throw invalidWeek("Generated week must contain exactly seven daily cards.");
  }

  const expectedDates = new Set(weekDates(weekStartDate));
  const seenDates = new Set<string>();
  const dailyCards = value.daily_cards.map((card, index) => {
    const normalized = validateGeneratedDailyCard(card, index);
    if (!expectedDates.has(normalized.scheduled_date)) {
      throw invalidWeek("Generated card date is outside the requested week.");
    }
    if (seenDates.has(normalized.scheduled_date)) {
      throw invalidWeek("Generated card dates must be unique.");
    }
    seenDates.add(normalized.scheduled_date);
    return normalized;
  });

  if (!Array.isArray(value.idea_bank)) {
    throw invalidWeek("idea_bank must be an array.");
  }
  const ideaBank = value.idea_bank.map(validateGeneratedIdea);

  return {
    strategy_summary: strategySummary,
    warnings,
    assumptions,
    daily_cards: dailyCards,
    idea_bank: ideaBank,
    source_summary: sourceSummary,
  };
}

export function makeMockGeneratedWeek(
  input: GenerationInputSnapshot,
): GeneratedWeekOutput {
  const dates = weekDates(input.week_start_date);
  const profileName = stringValue(input.creator_profile?.display_name) ??
    "Mamta";
  const setupLocation = stringValue(input.weekly_setup?.location) ?? "home";
  const firstIdea = stringValue(input.idea_bank[0]?.title) ??
    "One steady routine detail";
  const referenceNote =
    stringValue(input.confirmed_references[0]?.manual_notes) ??
      stringValue(input.confirmed_references[0]?.source_url) ??
      "confirmed Inspiration reference";
  const sourceReferenceIDs = input.confirmed_references
    .map((reference) => stringValue(reference.id))
    .filter((id): id is string => isUUID(id))
    .slice(0, 1);

  return {
    strategy_summary:
      `${profileName} gets a calm, shootable week anchored in ${setupLocation}, one practical reel per day, and backup paths for low-energy days.`,
    warnings: input.confirmed_references.length === 0
      ? [
        "No confirmed Inspiration references were available; mock used fixture-safe routine angles.",
      ]
      : [],
    assumptions: [
      "Keep each shoot under 15 minutes unless a brand/key moment requires more.",
      "Use Hinglish only when it sounds natural.",
    ],
    daily_cards: dates.map((date, index) =>
      mockCard(date, index, firstIdea, referenceNote, sourceReferenceIDs)
    ),
    idea_bank: [
      {
        title: "Caption-only calm reset",
        summary: "A saved backup for days when shooting is not possible.",
        suggested_use: "Use as a low-effort backup story or caption.",
        shootability: "easy",
        tags: ["backup", "routine"],
        fit_score: 86,
        source_note: "Generated from weekly mock context.",
        status: "saved",
      },
      {
        title: "Reference-inspired shoe detail",
        summary: "A simple visual pattern adapted from confirmed references.",
        suggested_use: "Schedule when a training day needs a quick visual.",
        shootability: "easy",
        tags: ["reference", "training"],
        fit_score: 88,
        source_note: referenceNote,
        status: "saved",
      },
    ],
    source_summary:
      `Used ${input.confirmed_references.length} confirmed references, ${input.recent_archive.length} archive entries, and ${input.idea_bank.length} saved ideas.`,
  };
}

export function weekDates(weekStartDate: string): string[] {
  const [year, month, day] = weekStartDate.split("-").map(Number);
  const start = new Date(Date.UTC(year, month - 1, day));
  return Array.from({ length: 7 }, (_, index) => {
    const date = new Date(start);
    date.setUTCDate(start.getUTCDate() + index);
    return date.toISOString().slice(0, 10);
  });
}

export function isDateString(value: string | undefined): value is string {
  return /^\d{4}-\d{2}-\d{2}$/.test(value ?? "");
}

export function isUUID(value: string | undefined): value is string {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value ?? "");
}

function mockCard(
  scheduledDate: string,
  index: number,
  firstIdea: string,
  referenceNote: string,
  sourceReferenceIDs: string[],
): GeneratedDailyCard {
  const weekdayTitles = [
    "Monday reset without drama",
    "Tuesday steady training note",
    "Wednesday fuel and recovery check",
    "Thursday simple kit detail",
    "Friday calm race-week reminder",
    "Saturday family walk moment",
    "Sunday caption-only backup",
  ];
  const title = weekdayTitles[index] ?? `Day ${index + 1} routine`;
  const shootability = index === 6 ? "backup" : "easy";

  return {
    scheduled_date: scheduledDate,
    title,
    why_today:
      `This keeps ${firstIdea.toLowerCase()} visible without asking for a heavy shoot.`,
    growth_job: "Build consistency with practical, low-drama fitness content.",
    content_pillar: index === 5 ? "family" : "routine",
    shootability,
    estimated_shoot_minutes: index === 6 ? 6 : 12,
    energy_required: index === 6 ? "low" : "medium",
    language_mode: "English with light Hinglish if natural",
    scene_list: [
      {
        number: 1,
        title: "One honest opening detail",
        duration: "3 sec",
        symbol: "sparkles",
      },
      {
        number: 2,
        title,
        duration: "5 sec",
        symbol: "figure.run",
      },
      {
        number: 3,
        title: "One useful closing line",
        duration: "4 sec",
        symbol: "text.quote",
      },
    ],
    script:
      "Keep it simple today. One useful detail, one steady habit, no overthinking.",
    no_voiceover_version:
      "Use three quiet clips with on-screen text and the caption carrying the point.",
    on_screen_text: ["Simple today", "One useful detail", "Done without drama"],
    caption:
      "Keeping it simple today. One useful detail is enough when the week is full.",
    cta: "Save this for your low-energy training day.",
    hashtags: ["fitnessover60", "routine", "steady"],
    cover_text: title,
    post_instructions:
      "Use calm audio if available. Keep cover text large and readable.",
    brand_event_notes: "",
    backup_story: "A 10-second story: one clip, one line, done.",
    backup_caption_only:
      "Caption-only backup: keeping the routine steady today.",
    audio_option_notes:
      "Use a confirmed calm audio option if it fits; otherwise post without audio dependence.",
    mamta_fit_score: 88,
    risk_notes: [],
    assumptions: ["Mock generation used deterministic local context."],
    source_note: referenceNote,
    source_reference_ids: sourceReferenceIDs,
  };
}

function validateGeneratedDailyCard(
  value: unknown,
  index: number,
): GeneratedDailyCard {
  if (!isRecord(value)) {
    throw invalidWeek(`daily_cards[${index}] must be an object.`);
  }

  const scenes = Array.isArray(value.scene_list)
    ? value.scene_list.map((scene, sceneIndex) => {
      if (!isRecord(scene)) {
        throw invalidWeek(`scene_list[${sceneIndex}] must be an object.`);
      }
      const number = numberValue(scene.number);
      if (!Number.isInteger(number) || number <= 0) {
        throw invalidWeek("Scene numbers must be positive integers.");
      }
      return {
        number,
        title: requiredString(scene.title, "scene.title"),
        duration: requiredSceneDuration(scene.duration),
        symbol: requiredString(scene.symbol, "scene.symbol"),
      };
    })
    : [];

  if (scenes.length === 0) {
    throw invalidWeek("Each daily card needs at least one scene.");
  }

  const score = numberValue(value.mamta_fit_score);
  if (!Number.isFinite(score) || score < 0 || score > 100) {
    throw invalidWeek("mamta_fit_score must be between 0 and 100.");
  }

  const minutes = numberValue(value.estimated_shoot_minutes);
  if (!Number.isInteger(minutes) || minutes < 0) {
    throw invalidWeek(
      "estimated_shoot_minutes must be a non-negative integer.",
    );
  }

  return {
    id: isUUID(stringValue(value.id)) ? stringValue(value.id) : undefined,
    scheduled_date: requiredDate(value.scheduled_date, "scheduled_date"),
    title: requiredString(value.title, "title"),
    why_today: requiredString(value.why_today, "why_today"),
    growth_job: requiredString(value.growth_job, "growth_job"),
    content_pillar: requiredString(value.content_pillar, "content_pillar"),
    shootability: requiredString(value.shootability, "shootability"),
    estimated_shoot_minutes: minutes,
    energy_required: requiredString(value.energy_required, "energy_required"),
    language_mode: requiredString(value.language_mode, "language_mode"),
    scene_list: scenes,
    script: requiredString(value.script, "script"),
    no_voiceover_version: requiredString(
      value.no_voiceover_version,
      "no_voiceover_version",
    ),
    on_screen_text: requiredStringArray(value.on_screen_text, "on_screen_text"),
    caption: requiredString(value.caption, "caption"),
    cta: requiredString(value.cta, "cta"),
    hashtags: requiredStringArray(value.hashtags, "hashtags"),
    cover_text: requiredString(value.cover_text, "cover_text"),
    post_instructions: requiredString(
      value.post_instructions,
      "post_instructions",
    ),
    brand_event_notes: stringValue(value.brand_event_notes) ?? "",
    backup_story: requiredString(value.backup_story, "backup_story"),
    backup_caption_only: requiredString(
      value.backup_caption_only,
      "backup_caption_only",
    ),
    audio_option_notes: stringValue(value.audio_option_notes) ?? "",
    mamta_fit_score: score,
    risk_notes: requiredStringArray(value.risk_notes, "risk_notes"),
    assumptions: requiredStringArray(value.assumptions, "assumptions"),
    source_note: requiredString(value.source_note, "source_note"),
    source_reference_ids: requiredStringArray(
      value.source_reference_ids,
      "source_reference_ids",
    ).filter((id) => isUUID(id)),
  };
}

function validateGeneratedIdea(value: unknown): GeneratedIdea {
  if (!isRecord(value)) {
    throw invalidWeek("Generated idea must be an object.");
  }
  const fitScore = numberValue(value.fit_score);
  if (!Number.isFinite(fitScore) || fitScore < 0 || fitScore > 100) {
    throw invalidWeek("Generated idea fit_score must be between 0 and 100.");
  }
  const status = stringValue(value.status) === "scheduled"
    ? "scheduled"
    : "saved";
  return {
    title: requiredString(value.title, "idea.title"),
    summary: requiredString(value.summary, "idea.summary"),
    suggested_use: requiredString(value.suggested_use, "idea.suggested_use"),
    shootability: requiredString(value.shootability, "idea.shootability"),
    tags: requiredStringArray(value.tags, "idea.tags"),
    fit_score: fitScore,
    source_note: stringValue(value.source_note) ?? "",
    status,
  };
}

function requiredString(value: unknown, field: string): string {
  const normalized = stringValue(value)?.trim();
  if (!normalized) {
    throw invalidWeek(`${field} is required.`);
  }
  return normalized;
}

function requiredDate(value: unknown, field: string): string {
  const normalized = requiredString(value, field);
  if (!isDateString(normalized)) {
    throw invalidWeek(`${field} must be YYYY-MM-DD.`);
  }
  return normalized;
}

function requiredSceneDuration(value: unknown): string {
  const normalized = stringValue(value)?.trim();
  if (normalized) {
    return normalized;
  }

  const numericDuration = numberValue(value);
  if (Number.isFinite(numericDuration) && numericDuration > 0) {
    return `${numericDuration} sec`;
  }

  throw invalidWeek("scene.duration is required.");
}

function requiredStringArray(value: unknown, field: string): string[] {
  if (!Array.isArray(value)) {
    throw invalidWeek(`${field} must be an array.`);
  }
  return value.map((item) => {
    if (typeof item !== "string") {
      throw invalidWeek(`${field} must contain only strings.`);
    }
    return item.trim();
  }).filter((item) => item.length > 0);
}

function invalidWeek(message: string): GenerateWeekValidationError {
  return new GenerateWeekValidationError("invalid_generated_week", message);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function numberValue(value: unknown): number {
  return typeof value === "number" ? value : Number.NaN;
}

function optionalNonBlankString(value: unknown): string | undefined {
  const normalized = stringValue(value)?.trim();
  return normalized ? normalized : undefined;
}

function optionalNonNegativeInteger(value: unknown): number | undefined {
  const number = numberValue(value);
  return Number.isInteger(number) && number >= 0 ? number : undefined;
}

function optionalSceneList(value: unknown): GeneratedScene[] | undefined {
  if (!Array.isArray(value)) {
    return undefined;
  }

  const scenes: GeneratedScene[] = [];
  for (const scene of value) {
    if (!isRecord(scene)) {
      return undefined;
    }
    const number = optionalNonNegativeInteger(scene.number);
    const title = optionalNonBlankString(scene.title);
    const duration = optionalNonBlankString(scene.duration);
    const symbol = optionalNonBlankString(scene.symbol);
    if (!number || !title || !duration || !symbol) {
      return undefined;
    }
    scenes.push({ number, title, duration, symbol });
  }

  return scenes.length > 0 ? scenes : undefined;
}

function storedBackupLine(value: unknown): string | undefined {
  if (typeof value === "string") {
    return optionalNonBlankString(value);
  }
  if (!isRecord(value)) {
    return undefined;
  }
  return optionalNonBlankString(value.line) ??
    optionalNonBlankString(value.text) ??
    optionalNonBlankString(value.caption);
}

const generatedSceneJSONSchema = {
  type: "object",
  additionalProperties: false,
  required: ["number", "title", "duration", "symbol"],
  properties: {
    number: { type: "integer", minimum: 1 },
    title: { type: "string" },
    duration: { type: "string" },
    symbol: { type: "string" },
  },
};

const generatedCardJSONSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "scheduled_date",
    "title",
    "why_today",
    "growth_job",
    "content_pillar",
    "shootability",
    "estimated_shoot_minutes",
    "energy_required",
    "language_mode",
    "scene_list",
    "script",
    "no_voiceover_version",
    "on_screen_text",
    "caption",
    "cta",
    "hashtags",
    "cover_text",
    "post_instructions",
    "brand_event_notes",
    "backup_story",
    "backup_caption_only",
    "audio_option_notes",
    "mamta_fit_score",
    "risk_notes",
    "assumptions",
    "source_note",
    "source_reference_ids",
  ],
  properties: {
    scheduled_date: { type: "string", format: "date" },
    title: { type: "string" },
    why_today: { type: "string" },
    growth_job: { type: "string" },
    content_pillar: { type: "string" },
    shootability: { type: "string" },
    estimated_shoot_minutes: { type: "integer", minimum: 0 },
    energy_required: { type: "string" },
    language_mode: { type: "string" },
    scene_list: { type: "array", items: generatedSceneJSONSchema },
    script: { type: "string" },
    no_voiceover_version: { type: "string" },
    on_screen_text: { type: "array", items: { type: "string" } },
    caption: { type: "string" },
    cta: { type: "string" },
    hashtags: { type: "array", items: { type: "string" } },
    cover_text: { type: "string" },
    post_instructions: { type: "string" },
    brand_event_notes: { type: "string" },
    backup_story: { type: "string" },
    backup_caption_only: { type: "string" },
    audio_option_notes: { type: "string" },
    mamta_fit_score: { type: "number", minimum: 0, maximum: 100 },
    risk_notes: { type: "array", items: { type: "string" } },
    assumptions: { type: "array", items: { type: "string" } },
    source_note: { type: "string" },
    source_reference_ids: {
      type: "array",
      items: { type: "string", format: "uuid" },
    },
  },
};

const generatedIdeaJSONSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "title",
    "summary",
    "suggested_use",
    "shootability",
    "tags",
    "fit_score",
    "source_note",
    "status",
  ],
  properties: {
    title: { type: "string" },
    summary: { type: "string" },
    suggested_use: { type: "string" },
    shootability: { type: "string" },
    tags: { type: "array", items: { type: "string" } },
    fit_score: { type: "number", minimum: 0, maximum: 100 },
    source_note: { type: "string" },
    status: { type: "string", enum: ["saved", "scheduled"] },
  },
};

export const generatedWeekJSONSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "strategy_summary",
    "warnings",
    "assumptions",
    "daily_cards",
    "idea_bank",
    "source_summary",
  ],
  properties: {
    strategy_summary: { type: "string" },
    warnings: { type: "array", items: { type: "string" } },
    assumptions: { type: "array", items: { type: "string" } },
    daily_cards: {
      type: "array",
      minItems: 7,
      maxItems: 7,
      items: generatedCardJSONSchema,
    },
    idea_bank: { type: "array", items: generatedIdeaJSONSchema },
    source_summary: { type: "string" },
  },
};
