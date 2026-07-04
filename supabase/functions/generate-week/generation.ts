export type GenerateWeekMode = "generate_draft" | "regenerate_draft";
export type GenerateWeekResponseMode = "sync" | "async";

/**
 * Creator content pillars. The creator is a lifestyle creator documenting a
 * rounded healthy life, NOT a gym instructor. Gym is one of four pillars, not
 * the whole identity. Each generated day must map to exactly one of these.
 */
export const CONTENT_PILLARS = [
  "gym",
  "lifestyle",
  "eating",
  "recovery",
] as const;
export type ContentPillar = (typeof CONTENT_PILLARS)[number];

/** Maximum gym-primary days in a 7-day week unless the brief explicitly narrows scope. */
export const GYM_PRIMARY_DAY_CAP = 2;

export function normalizeContentPillar(value: unknown): ContentPillar | null {
  const normalized = stringValue(value)?.trim().toLowerCase() ?? "";
  if (CONTENT_PILLARS.includes(normalized as ContentPillar)) {
    return normalized as ContentPillar;
  }
  // Lenient aliases so legacy values still map to the four-pillar model.
  if (
    normalized === "fitness" || normalized === "training" ||
    normalized === "strength" || normalized === "workout"
  ) {
    return "gym";
  }
  if (
    normalized === "healthy lifestyle" || normalized === "wellness" ||
    normalized === "habit" || normalized === "habits" || normalized === "family"
  ) {
    return "lifestyle";
  }
  if (
    normalized === "food" || normalized === "nutrition" ||
    normalized === "meal" || normalized === "healthy eating"
  ) {
    return "eating";
  }
  if (
    normalized === "rest" || normalized === "sleep" ||
    normalized === "mobility" || normalized === "stretch"
  ) {
    return "recovery";
  }
  return null;
}

/**
 * Phrases that make the creator sound like a coach/instructor rather than a
 * creator documenting her own life. These must not appear as the main angle.
 */
export const INSTRUCTOR_ISH_PHRASES = [
  "do this exercise",
  "fix your form",
  "your client",
  "my clients",
  "training clients",
  "upper body cue",
  "training angle",
  "do this workout",
  "try this workout",
  "here's how to train",
  "here is how to train",
];

/**
 * Instructor endings observed in live output that must be rejected.
 * These turn the creator into a coach delivering a closing instruction
 * rather than a human ending with an observation, punchline, or question.
 */
export const BANNED_INSTRUCTOR_ENDINGS = [
  "just start",
  "one set, then the next",
  "if you needed a reminder",
  "the real win",
  "you can do this",
  "you got this",
  "no excuses",
  "start today",
  "you're stronger than you think",
];

/**
 * Banned CTA templates that make every script end the same way.
 * No more than 2 explicit save CTAs across a 7-day week.
 */
export const BANNED_CTA_TEMPLATES = [
  "save this for",
  "save this reel",
  "save this post",
  "save this to",
  "tell me in the comments",
  "tell me what you think",
  "send this to a friend",
  "send to a friend who",
  "tag someone who",
  "share this with",
  "comment below",
  "follow for more",
  "like and save",
  "dm me",
];

export const CREATOR_NO_GO_PHRASES = [
  "age is just a number",
  "no excuses",
  "crush it",
  "beast mode",
  "discipline beats motivation",
  "strong women rise",
  "queen energy",
  "unstoppable",
  "fitness is my therapy",
  "this is your sign",
];

const CREATOR_SIGNATURE_SERIES = [
  "Today's Hyrox Homework",
  "The Set I Did Not Ask For",
  "Things I Do When My Gym Is Missing Equipment",
  "Rich In Life Because...",
  "What's In My Gym Bag",
  "Food That Supports Training",
  "Stop Telling Your Kids...",
  "Things I Did Not Expect To Do In My 60s",
  "Training While Life Is Still Happening",
  "Brand In My Real Routine",
];

const CREATOR_REALISTIC_CAPTURE_BANK = [
  "walking into gym",
  "mirror shot",
  "warm-up",
  "sled push or pull",
  "battle ropes",
  "wall balls",
  "lunges",
  "strength sets",
  "coach instructions",
  "sweat close-up",
  "tired smile",
  "gym bag",
  "shoes",
  "bottle",
  "salts or hydration",
  "breakfast",
  "haldi jeera water",
  "kanji",
  "chia pudding",
  "lunch",
  "dinner prep",
  "cooking for husband",
  "plants",
  "rest",
  "evening wind-down",
  "daughter voice note",
  "race registration",
  "walking outside",
  "errands",
];

export function containsInstructorPhrasing(text: string): boolean {
  const normalized = text.toLowerCase();
  return INSTRUCTOR_ISH_PHRASES.some((phrase) => normalized.includes(phrase));
}

export function containsInstructorEnding(text: string): boolean {
  const normalized = text.toLowerCase();
  return BANNED_INSTRUCTOR_ENDINGS.some((phrase) =>
    normalized.includes(phrase)
  );
}

/**
 * Count cards that carry an explicit save CTA across any audience-facing
 * text field. Each card is counted at most once regardless of how many
 * fields contain the pattern. Ordinary uses of "save" (save time, saved
 * my breakfast, I save this kind of energy) are not counted — the pattern
 * requires "save this" followed by for/reel/post/to, sentence-ending
 * punctuation, or end-of-text.
 */
export function countExplicitSaveCTAs(
  cards: GeneratedDailyCard[],
): number {
  const saveCTAPattern = /\bsave this\b\s*(?:for|reel|post|to|[.!?,;]|$)/i;

  return cards.filter((card) => {
    const texts = [
      card.cta,
      card.script,
      card.caption,
      card.backup_story,
      card.backup_caption_only,
      card.caption_backup_detail,
      ...card.on_screen_text,
    ];
    return texts.some((text) => saveCTAPattern.test(text));
  }).length;
}

export type RegenerateDayRequest = {
  action: "regenerate_day";
  creator_id: string;
  weekly_plan_id: string;
  scheduled_date: string;
  preserve_manual_edits: boolean;
  mock: boolean;
  response_mode: GenerateWeekResponseMode;
  input_overrides?: Record<string, unknown>;
  day_guidance?: string;
};

export type GenerateWeekRequest = {
  creator_id: string;
  week_start_date: string;
  weekly_setup_id?: string;
  mode: GenerateWeekMode;
  preserve_manual_edits: boolean;
  mock: boolean;
  response_mode: GenerateWeekResponseMode;
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
  existing_week_cards?: Record<string, unknown>[];
  day_guidance?: string;
  day_retry_context?: Record<string, unknown>;
};

const DEFAULT_AI_REQUEST_TIMEOUT_MS = 240_000;

export type GeneratedScene = {
  number: number;
  title: string;
  duration: string;
  symbol: string;
};

export type GeneratedTimelineItem = {
  timestamp: string;
  detail: string;
};

export type GeneratedVoiceoverTimelineItem = {
  timestamp: string;
  video_portion: string;
  voiceover: string;
};

export type GeneratedOnScreenTextTimelineItem = {
  timestamp: string;
  text: string;
  placement: string;
};

export type GeneratedDailyCard = {
  id?: string;
  scheduled_date: string;
  format: "Reel" | "Post" | "Story";
  primary_surface: string;
  duration_seconds: number;
  title: string;
  hook: string;
  weekly_brief_anchor: string;
  brief_alignment: string;
  brief_context_tags: string[];
  why_today: string;
  growth_job: string;
  save_share_reason: string;
  content_pillar: string;
  shootability: string;
  estimated_shoot_minutes: number;
  energy_required: string;
  language_mode: string;
  scene_list: GeneratedScene[];
  shot_timeline: GeneratedTimelineItem[];
  script: string;
  voiceover_timeline: GeneratedVoiceoverTimelineItem[];
  no_voiceover_version: string;
  silent_version_timeline: GeneratedTimelineItem[];
  on_screen_text: string[];
  on_screen_text_timeline: GeneratedOnScreenTextTimelineItem[];
  caption: string;
  cta: string;
  hashtags: string[];
  cover_text: string;
  post_instructions: string;
  brand_event_notes: string;
  backup_story: string;
  backup_story_detail: GeneratedTimelineItem[];
  backup_caption_only: string;
  caption_backup_detail: string;
  audio_option_notes: string;
  creator_fit_score: number;
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

export type GeneratedDayOutput = {
  strategy_note: string;
  warnings: string[];
  assumptions: string[];
  daily_card: GeneratedDailyCard;
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

export type AIGenerationPhase =
  | "full_week_generation"
  | "split_week_day_generation"
  | "async_day_generation"
  | "parallel_day_generation"
  | "regenerate_day_generation";

export type AIGenerationScope = "week" | "day";

export type AIGenerationRequestSizeMetrics = {
  prompt_system_chars: number;
  prompt_user_chars: number;
  prompt_total_chars: number;
  prompt_total_bytes: number;
  prompt_estimated_tokens: number;
  provider_request_body_chars: number;
  provider_request_body_bytes: number;
  request_timeout_ms: number;
  request_input_version: string | null;
  input_snapshot_chars: number;
  input_snapshot_bytes: number;
  input_snapshot_estimated_tokens: number;
  raw_input_snapshot_chars: number;
  raw_input_snapshot_bytes: number;
  raw_input_snapshot_estimated_tokens: number;
  reference_context_chars: number;
  reference_context_bytes: number;
  reference_context_estimated_tokens: number;
  raw_reference_context_chars: number;
  dropped_reference_context_chars: number;
  creator_profile_chars: number;
  weekly_setup_chars: number;
  confirmed_reference_count: number;
  raw_confirmed_reference_count: number;
  dropped_confirmed_reference_count: number;
  confirmed_reference_chars: number;
  reference_extraction_count: number;
  raw_reference_extraction_count: number;
  dropped_reference_extraction_count: number;
  reference_extraction_chars: number;
  recent_archive_count: number;
  raw_recent_archive_count: number;
  dropped_recent_archive_count: number;
  recent_archive_chars: number;
  idea_bank_count: number;
  raw_idea_bank_count: number;
  dropped_idea_bank_count: number;
  idea_bank_chars: number;
  pattern_count: number;
  raw_pattern_count: number;
  dropped_pattern_count: number;
  pattern_chars: number;
  trend_count: number;
  raw_trend_count: number;
  dropped_trend_count: number;
  trend_chars: number;
  audio_option_count: number;
  raw_audio_option_count: number;
  dropped_audio_option_count: number;
  audio_option_chars: number;
  brand_brief_count: number;
  raw_brand_brief_count: number;
  dropped_brand_brief_count: number;
  brand_brief_chars: number;
  key_moment_count: number;
  raw_key_moment_count: number;
  dropped_key_moment_count: number;
  key_moment_chars: number;
  existing_week_card_count: number;
  raw_existing_week_card_count: number;
  dropped_existing_week_card_count: number;
  existing_week_card_chars: number;
};

export type AIGenerationValidationFailureDetail = {
  code: string;
  stage: "request_validation" | "json_parse" | "output_validation";
  rule: string;
  path: string | null;
  retryable: boolean;
  message: string;
};

export type AIGenerationAttemptLog = {
  event: "generation_ai_attempt";
  generation_id: string | null;
  generation_scope: AIGenerationScope;
  phase: AIGenerationPhase;
  week_start_date: string;
  scheduled_date: string | null;
  day_index: number | null;
  provider: AIProviderName;
  model: string;
  provider_attempt: number;
  started_at: string;
  ended_at: string;
  duration_ms: number;
  status: "success" | "failure";
  input_tokens: number | null;
  output_tokens: number | null;
  total_tokens: number | null;
  finish_reason: string | null;
  output_text_chars: number | null;
  output_text_bytes: number | null;
  request_metrics: AIGenerationRequestSizeMetrics | null;
  quality_score: number | null;
  quality_version: "instagram_content_quality_v2" | null;
  quality_metrics: AIOutputQualityMetrics | null;
  error_category: string | null;
  error_message: string | null;
  validation_error: AIGenerationValidationFailureDetail | null;
};

export type AIGenerationAttemptLogger = (
  log: AIGenerationAttemptLog,
) => void;

export type AIGenerationInstrumentation = {
  generationID?: string;
  generationScope: AIGenerationScope;
  phase: AIGenerationPhase;
  logger: AIGenerationAttemptLogger;
};

type AIGenerationProviderAttemptContext = AIGenerationInstrumentation & {
  provider: AIProviderName;
  model: string;
  providerAttempt: number;
  weekStartDate: string;
  scheduledDate?: string;
  dayIndex?: number;
};

type AIResponseMetadata = {
  inputTokens: number | null;
  outputTokens: number | null;
  totalTokens: number | null;
  finishReason: string | null;
  outputTextChars: number | null;
  outputTextBytes: number | null;
};

export type AIOutputQualityMetrics = {
  version: "instagram_content_quality_v2";
  score: number;
  pillar_count: number;
  instructor_phrase_count: number;
  instructor_ending_count: number;
  source_reference_link_count: number;
  cards_with_source_reference_count: number;
  hook_first_3s_present: boolean;
  first_frame_text_hook_present: boolean;
  opening_visual_motion_present: boolean;
  clear_payoff_or_curiosity_gap_present: boolean;
  watch_without_sound_ready: boolean;
  on_screen_text_present: boolean;
  caption_or_subtitle_support_present: boolean;
  on_screen_text_density_ok: boolean;
  duration_fit:
    | "ideal"
    | "acceptable"
    | "too_short"
    | "too_long"
    | "not_applicable";
  scene_variety_count: number;
  visual_variety_present: boolean;
  audio_or_silent_strategy_present: boolean;
  shareability_reason_present: boolean;
  save_or_share_value_present: boolean;
  clear_cta_present: boolean;
  cta_type: "save" | "share" | "reply" | "comment" | "profile" | "none";
  creator_lived_detail_present: boolean;
  specific_context_anchor_present: boolean;
  generic_template_risk_count: number;
  story_interactive_sticker_present: boolean | null;
  story_reply_prompt_present: boolean | null;
  story_slide_count_fit: boolean | null;
  post_first_slide_promise_present: boolean | null;
  post_one_clear_idea_present: boolean | null;
  post_final_cta_present: boolean | null;
  post_saveable_value_present: boolean | null;
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
  const responseMode = stringValue(body.response_mode) ?? "sync";
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

  if (responseMode !== "sync" && responseMode !== "async") {
    throw new GenerateWeekValidationError(
      "invalid_generation_payload",
      "response_mode must be sync or async.",
    );
  }

  return {
    creator_id: creatorID,
    week_start_date: weekStartDate,
    weekly_setup_id: weeklySetupID,
    mode: requestedMode,
    preserve_manual_edits: preserveManualEdits,
    mock,
    response_mode: responseMode,
    input_overrides: inputOverrides,
  };
}

const MAX_DAY_GUIDANCE_LENGTH = 500;

export function normalizeRegenerateDayRequest(
  body: unknown,
): RegenerateDayRequest {
  if (!isRecord(body) || body.action !== "regenerate_day") {
    throw new GenerateWeekValidationError(
      "invalid_generation_payload",
      "action must be regenerate_day.",
    );
  }

  const creatorID = stringValue(body.creator_id);
  const weeklyPlanID = stringValue(body.weekly_plan_id);
  const scheduledDate = stringValue(body.scheduled_date);
  const responseMode = stringValue(body.response_mode) ?? "sync";
  const rawGuidance = stringValue(body.day_guidance) ?? undefined;
  const dayGuidance = rawGuidance
    ? rawGuidance.trim().slice(0, MAX_DAY_GUIDANCE_LENGTH)
    : undefined;

  if (
    !isUUID(creatorID) || !isUUID(weeklyPlanID) ||
    !isDateString(scheduledDate)
  ) {
    throw new GenerateWeekValidationError(
      "invalid_generation_payload",
      "creator_id, weekly_plan_id, and scheduled_date are required.",
    );
  }
  if (responseMode !== "sync" && responseMode !== "async") {
    throw new GenerateWeekValidationError(
      "invalid_generation_payload",
      "response_mode must be sync or async.",
    );
  }

  return {
    action: "regenerate_day",
    creator_id: creatorID,
    weekly_plan_id: weeklyPlanID,
    scheduled_date: scheduledDate,
    preserve_manual_edits: body.preserve_manual_edits !== false,
    mock: body.mock === true,
    response_mode: responseMode,
    input_overrides: isRecord(body.input_overrides)
      ? body.input_overrides
      : undefined,
    day_guidance: dayGuidance,
  };
}

export function buildPromptMessages(input: GenerationInputSnapshot): {
  system: string;
  user: string;
} {
  const generationGuidance = buildGenerationGuidance(input);
  return {
    system: [
      "You generate Creator Content OS weekly content as strict JSON.",
      "The creator is a lifestyle creator documenting her own rounded healthy life, NOT a gym instructor or online coach. Gym is one of four pillars (gym, lifestyle, eating, recovery), not her whole identity.",
      "Stable creator brief: Indian mother, wife, and HYROX athlete building a second-half-of-life fitness brand; age is context, not the whole personality.",
      "Use only the provided creator profile, weekly setup, confirmed references and extractions, brand obligations, key moments, archive feedback, and idea bank.",
      "Apply the generation guidance silently; resolve source conflicts by precedence without asking the admin.",
      "Generate exactly seven daily cards for the requested week.",
      "Each day must set content_pillar to one of gym, lifestyle, eating, or recovery, and the week must represent at least 3 of the 4 pillars unless the weekly brief explicitly narrows scope. Default to exactly 2 training/HYROX-led concepts unless the brief explicitly asks for a gym-focused week. Day routines may anchor non-training lifestyle, eating, or recovery concepts.",
      "Frame everything in first person as what the creator is doing, noticing, or trying — never as instruction for followers. Ban coach language like 'do this exercise', 'fix your form', 'my clients', 'your clients', 'training clients', 'upper body cue' as the main angle, or generic 'training angle'.",
      "Prioritize shootability, retention-first hooks, and creator safety. Creative stakes win over trend chasing.",
      "Use only supplied profile, brief, and confirmed reference facts. Never invent biography, quotes, family reactions, exact durations, locations not in the brief, history, equipment failures, or dialogue. Place any uncertainty in assumptions or risk_notes.",
      "Use at most 2 explicit save CTAs across the week. Do not end every script by instructing the audience — use punchlines, observations, or genuinely earned questions. Ban 'save this/tell me/send to a friend' templates.",
      "Reject instructor endings: 'just start', 'one set, then the next', 'if you needed a reminder', 'the real win', and follower-directed workout permission sentences.",
      "Mention age in at most one card per ordinary week unless the brief explicitly centers age or milestones.",
      "Every non-training card must have a genuinely non-training center — never relabel a gym script as lifestyle, eating, or recovery.",
      "Avoid all no-go topics and surface assumptions or risks instead of inventing facts.",
    ].join(" "),
    user: JSON.stringify({
      task: "Generate one draft weekly plan for review before publishing.",
      required_output:
        "JSON only. Match the supplied contract exactly. Required string fields must be non-empty; use empty arrays for optional lists. Do not return idea stubs.",
      required_contract: generatedWeekOutputContract(input.week_start_date),
      generation_guidance: generationGuidance,
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
        name: "creator_weekly_generation",
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
          "Every daily_cards item must include scheduled_date, format, primary_surface, duration_seconds, title, hook, weekly_brief_anchor, brief_alignment, brief_context_tags, why_today, growth_job, save_share_reason, content_pillar, shootability, estimated_shoot_minutes, energy_required, language_mode, scene_list, shot_timeline, script, voiceover_timeline, no_voiceover_version, silent_version_timeline, on_screen_text, on_screen_text_timeline, caption, cta, hashtags, cover_text, post_instructions, brand_event_notes, backup_story, backup_story_detail, backup_caption_only, caption_backup_detail, audio_option_notes, creator_fit_score, risk_notes, assumptions, source_note, and source_reference_ids.",
          "Every required string field must contain specific non-empty text; do not use empty strings, TBD, placeholders, or null.",
          "Use timestamp ranges like 0:00-0:03 in shot_timeline, voiceover_timeline, on_screen_text_timeline, silent_version_timeline, and backup_story_detail.",
          "Never use day_of_week instead of scheduled_date.",
        ].join("\n"),
      },
    ],
    response_format: { type: "json_object" },
    thinking: { type: "enabled" },
    reasoning_effort: "max",
    max_tokens: 12000,
    temperature: 0.2,
  };
}

function buildDayPromptMessages(
  input: GenerationInputSnapshot,
  scheduledDate: string,
  dayIndex: number,
): { system: string; user: string } {
  const promptInput = scopeInputForDayPrompt(input, scheduledDate, dayIndex);
  const compactPromptInput = compactDayPromptInput(
    promptInput,
    scheduledDate,
    dayIndex,
  );
  const generationGuidance = buildDailyGenerationGuidance(
    promptInput,
    scheduledDate,
    dayIndex,
  );
  const targetWeekday = weekdayName(scheduledDate);
  const dayGuidanceNote = promptInput.day_guidance
    ? `\nCreator/admin instruction for ${scheduledDate} ONLY (not week-wide): ${promptInput.day_guidance}`
    : "";
  return {
    system: [
      "You generate Creator Content OS daily content as strict JSON.",
      "Creator: Indian mother, wife, HYROX athlete, and rounded lifestyle creator; not a gym instructor or online coach. Gym is one pillar beside lifestyle, eating, and recovery.",
      "Use only supplied profile, weekly setup, day-scoped references, brand obligations, key moments, archive feedback, idea bank, and admin guidance.",
      "Apply precedence silently: weekly brief > profile > day-scoped references > older context.",
      "Generate exactly one daily card for the requested scheduled_date.",
      "Set content_pillar to gym, lifestyle, eating, or recovery. Frame first-person lived observation, never follower instruction.",
      "Ban coach language: 'do this exercise', 'fix your form', 'my clients', 'your clients', 'training clients', 'upper body cue' as the main angle, generic 'training angle', and coach-like imperatives.",
      "All day-of-week language must match the requested scheduled_date.",
      "Prioritize shootability, retention-first hooks, creator safety, and one clear creative turn.",
      "Never invent biography, quotes, family reactions, exact durations, locations, history, equipment failures, or dialogue. Place any uncertainty in assumptions or risk_notes.",
      "Explicit save CTA is allowed on at most two named weekdays; do NOT end every script with a save CTA. Follow day_intent for pillar, footage, CTA eligibility, and age eligibility.",
      "Mention age on at most one named weekday. Never default to age as a hook. end with punchline, observation, or earned question unless save CTA is explicitly eligible.",
      "Every non-training card needs a genuinely non-training center. Never relabel a gym script as lifestyle, eating, or recovery.",
      "Reject instructor endings: 'just start', 'one set, then the next', 'if you needed a reminder', 'the real win', 'you can do this', 'you got this', 'no excuses', 'start today', and follower-directed workout permission sentences.",
      "Write a concise Instagram caption: 40-70 words, tight and scannable, with context, one takeaway, and a natural CTA.",
    ].join(" "),
    user: JSON.stringify({
      task:
        "Generate one draft daily card that will be combined into a seven-day weekly plan.",
      required_output:
        "JSON only. Match the supplied contract exactly. Required string fields must be non-empty; use empty arrays for optional lists. Do not return markdown.",
      target: {
        scheduled_date: scheduledDate,
        weekday: targetWeekday,
        day_index: dayIndex + 1,
        week_start_date: promptInput.week_start_date,
        day_intent: generationGuidance.day_specific_intent,
      },
      repair_context: promptInput.day_retry_context ?? undefined,
      required_contract: generatedDayOutputContract(scheduledDate),
      generation_guidance: generationGuidance,
      input: compactPromptInput,
    }) + dayGuidanceNote,
  };
}

function buildDailyGenerationGuidance(
  input: GenerationInputSnapshot,
  scheduledDate: string,
  dayIndex: number,
): Record<string, unknown> {
  const dayIntent = dayIntentForScheduledDate(input, scheduledDate, dayIndex);
  const creatorDisplayName = stringValue(
    isRecord(input.creator_profile)
      ? input.creator_profile.display_name
      : undefined,
  ) ?? "the creator";

  return {
    compact_guidance_version: "creator_daily_generation_compact_v3",
    precedence: [
      "Weekly brief > creator profile > day-scoped references.",
      "Use references only when they fit the target date and brief.",
    ],
    day_specific_intent: dayIntent,
    creator_voice_compact: {
      identity:
        "Indian mother, wife, HYROX athlete in her early 60s; rounded lifestyle creator, not an instructor.",
      tone:
        "First-person, warm, witty, self-aware, Indian without caricature, strong without preaching.",
      writing_test:
        `If another creator could say a line unchanged, rewrite it with ${creatorDisplayName}'s lived detail, opinion, home/family texture, or dry humour.`,
      never_sound_like: ["gym bro", "online coach", "generic brand ambassador"],
    },
    daily_quality_rules: [
      "Open with tension, contradiction, recognition, joke setup, confession, or strongest visual.",
      "Include one unmistakable opinion, contradiction, confession, or comic observation.",
      "Include one current-brief/profile detail: food, family/home, gym bag, kitchen, location, routine, or brand constraint.",
      "End with punchline, observation, or earned question; no generic advice ending.",
      "Storyboard must be simple, specific, and realistic to film today.",
    ],
    quota_rules: {
      content_pillar: CONTENT_PILLARS.join(", "),
      cta:
        "At most 2 explicit save CTAs/week; use save language only if day_intent allows it.",
      age:
        "Mention age at most once/week and only if day_intent or brief supports it.",
      non_training:
        "Lifestyle/eating/recovery cards need a genuinely non-training center.",
    },
    banned:
      "No coach phrasing, follower workout commands, generic save-this endings, age cliches, or luxury-wellness cliches.",
    weekly_diversity: input.day_retry_context ? undefined : {
      target_day: `${
        weekdayName(scheduledDate)
      } ${scheduledDate}: ${dayIntent}`,
      avoid:
        "Do not repeat hook engines or generic reset/recovery/product-led concepts.",
    },
    factual_discipline:
      "Use supplied profile, brief, and day-scoped facts only; put gaps in risk_notes.",
    instagram_defaults: {
      caption:
        "40-70 word caption; tight, scannable, one takeaway, natural CTA.",
      timelines: "Use timestamp ranges like 0:00-0:03 in every timeline field.",
      storyboard:
        "Storyboard rows pair time, visual/shot, what to show, dialogue/script, and caption placement.",
    },
    repair_instruction: input.day_retry_context
      ? "This is a repair retry for the same scheduled_date. Do not broaden the idea. Fix the stated issue, simplify the concept if needed, and return one complete valid daily card."
      : undefined,
  };
}

function compactDayPromptInput(
  input: GenerationInputSnapshot,
  scheduledDate: string,
  dayIndex: number,
): Record<string, unknown> {
  const isRepair = isRecord(input.day_retry_context);
  const needsSourceContext = isRepair &&
    repairNeedsSourceContext(input.day_retry_context);
  const compactOptions = isRepair
    ? DAY_REPAIR_COMPACT_OPTIONS
    : DAY_COMPACT_OPTIONS;
  const creatorProfileKeys = isRepair
    ? [
      "display_name",
      "positioning",
      "voice_rules",
      "caption_style",
      "never_say",
      "language_preferences",
    ]
    : [
      "display_name",
      "positioning",
      "voice_rules",
      "caption_style",
      "never_say",
      "weekly_routine",
      "family_race_travel_context",
      "language_preferences",
    ];
  const weeklySetupKeys = isRepair
    ? [
      "location",
      "workout_race_schedule",
      "shooting_constraints",
      "no_go_topics",
      "notes",
    ]
    : [
      "location",
      "workout_race_schedule",
      "family_travel_moments",
      "energy_constraints",
      "shooting_constraints",
      "no_go_topics",
      "notes",
    ];
  const base: Record<string, unknown> = {
    compact_input_version: isRepair
      ? "creator_day_prompt_repair_input_v2"
      : "creator_day_prompt_input_v2",
    creator_id: input.creator_id,
    week_start_date: input.week_start_date,
    target: {
      scheduled_date: scheduledDate,
      weekday: weekdayName(scheduledDate),
      day_index: dayIndex + 1,
    },
    creator_profile: compactRecord(
      input.creator_profile ?? {},
      creatorProfileKeys,
      compactOptions,
    ),
    weekly_setup: compactRecord(
      input.weekly_setup ?? {},
      weeklySetupKeys,
      compactOptions,
    ),
    day_guidance: input.day_guidance,
    existing_day_card: compactRecords(
      input.existing_week_cards ?? [],
      1,
      compactOptions,
    ),
    confirmed_references: compactRecords(
      input.confirmed_references,
      isRepair ? (needsSourceContext ? 1 : 0) : 2,
      compactOptions,
    ),
    reference_extractions: compactRecords(
      input.reference_extractions,
      isRepair ? (needsSourceContext ? 1 : 0) : 2,
      compactOptions,
    ),
    brand_briefs: compactRecords(input.brand_briefs, isRepair ? 0 : 1),
    key_moments: compactRecords(input.key_moments, isRepair ? 0 : 1),
  };

  if (isRepair) {
    return {
      ...base,
      repair_mode: true,
      repair_context: compactRecord(
        input.day_retry_context ?? {},
        [
          "retry_kind",
          "retry_reason",
          "scheduled_date",
          "day_index",
          "provider_attempt",
          "validation_error",
          "error_message",
          "instruction",
        ],
        compactOptions,
      ),
    };
  }

  return {
    ...base,
    recent_archive: compactRecords(input.recent_archive, 1),
    idea_bank: compactRecords(input.idea_bank, 2),
    patterns: compactRecords(input.patterns, 1),
    trends: compactRecords(input.trends, 1),
    audio_options: compactRecords(input.audio_options, 1),
  };
}

function repairNeedsSourceContext(value: unknown): boolean {
  if (!isRecord(value)) {
    return false;
  }
  const text = safeJSONStringify({
    retry_reason: value.retry_reason,
    validation_error: value.validation_error,
    error_message: value.error_message,
  }).toLowerCase();
  return /source_reference|confirmed_reference|reference_extraction|source_note/
    .test(text);
}

type CompactOptions = {
  stringLimit: number;
  arrayItemLimit: number;
  objectKeyLimit: number;
};

const DAY_COMPACT_OPTIONS: CompactOptions = {
  stringLimit: 280,
  arrayItemLimit: 5,
  objectKeyLimit: 8,
};

const DAY_REPAIR_COMPACT_OPTIONS: CompactOptions = {
  stringLimit: 180,
  arrayItemLimit: 3,
  objectKeyLimit: 6,
};

function compactRecords(
  records: Record<string, unknown>[],
  max: number,
  options: CompactOptions = DAY_COMPACT_OPTIONS,
): Record<string, unknown>[] {
  return records.slice(0, max).map((record) =>
    compactRecord(record, [
      "id",
      "source_reference_id",
      "source_type",
      "source_url",
      "title",
      "name",
      "label",
      "brand_name",
      "campaign_title",
      "deliverable",
      "post_date",
      "due_date",
      "review_deadline",
      "moment_date",
      "scheduled_date",
      "content_pillar",
      "format",
      "summary",
      "suggested_use",
      "manual_notes",
      "notes",
      "extraction_kind",
      "extracted_payload",
      "required_scenes",
      "mandatory_points",
      "must_avoid",
      "disclosure_requirement",
      "status",
      "decision",
      "output_line",
    ], options)
  );
}

function compactRecord(
  record: Record<string, unknown>,
  allowedKeys: string[],
  options: CompactOptions = DAY_COMPACT_OPTIONS,
): Record<string, unknown> {
  const compact: Record<string, unknown> = {};
  for (const key of allowedKeys) {
    const value = record[key];
    if (value === undefined || value === null) continue;
    compact[key] = compactValue(value, options);
  }
  return compact;
}

function compactValue(value: unknown, options: CompactOptions): unknown {
  if (typeof value === "string") {
    return value.length > options.stringLimit
      ? `${value.slice(0, options.stringLimit - 3)}...`
      : value;
  }
  if (Array.isArray(value)) {
    return value.slice(0, options.arrayItemLimit).map((item) =>
      compactValue(item, options)
    );
  }
  if (isRecord(value)) {
    const entries = Object.entries(value).slice(0, options.objectKeyLimit);
    return Object.fromEntries(
      entries.map((
        [key, childValue],
      ) => [key, compactValue(childValue, options)]),
    );
  }
  return value;
}

export function scopeInputForDayPrompt(
  input: GenerationInputSnapshot,
  scheduledDate: string,
  dayIndex: number,
): GenerationInputSnapshot {
  const dayIntent = dayIntentForScheduledDate(input, scheduledDate, dayIndex);
  const tokens = dayScopeTokens(input, scheduledDate, dayIntent);
  const isRepair = isRecord(input.day_retry_context);
  const maxReferenceCount = isRepair ? 1 : 2;
  const maxExtractionCount = isRepair ? 1 : 3;
  const confirmedReferences = rankedRelevantRecords(
    input.confirmed_references,
    tokens,
    { max: maxReferenceCount, fallback: 0 },
  );
  const selectedReferenceIDs = new Set(
    confirmedReferences.flatMap((reference) => [
      stringValue(reference.id) ?? "",
      stringValue(reference.source_reference_id) ?? "",
    ]).filter(Boolean),
  );

  const linkedExtractions = input.reference_extractions.filter((extraction) =>
    selectedReferenceIDs.has(stringValue(extraction.source_reference_id) ?? "")
  );
  const rankedExtractions = rankedRelevantRecords(
    input.reference_extractions.filter((extraction) =>
      !linkedExtractions.includes(extraction)
    ),
    tokens,
    { max: maxExtractionCount, fallback: 0 },
  );

  return {
    ...input,
    confirmed_references: confirmedReferences,
    reference_extractions: uniqueRecordsByStableKey([
      ...linkedExtractions,
      ...rankedExtractions,
    ]).slice(0, maxExtractionCount),
    recent_archive: rankedRelevantRecords(input.recent_archive, tokens, {
      max: isRepair ? 0 : 1,
      fallback: 0,
    }),
    idea_bank: rankedRelevantRecords(input.idea_bank, tokens, {
      max: isRepair ? 0 : 2,
      fallback: 0,
    }),
    patterns: rankedRelevantRecords(input.patterns, tokens, {
      max: isRepair ? 0 : 1,
      fallback: 0,
    }),
    trends: rankedRelevantRecords(input.trends, tokens, {
      max: isRepair ? 0 : 1,
      fallback: 0,
    }),
    audio_options: rankedRelevantRecords(input.audio_options, tokens, {
      max: 1,
      fallback: 0,
    }),
    brand_briefs: rankedRelevantRecords(input.brand_briefs, tokens, {
      max: 2,
      fallback: 0,
    }),
    key_moments: rankedRelevantRecords(input.key_moments, tokens, {
      max: 2,
      fallback: 0,
    }),
    existing_week_cards: (input.existing_week_cards ?? []).filter((card) =>
      stringValue(card.scheduled_date) === scheduledDate
    ),
  };
}

function dayScopeTokens(
  input: GenerationInputSnapshot,
  scheduledDate: string,
  dayIntent: string,
): string[] {
  const tokens = new Set<string>();
  const add = (value: unknown) => {
    for (const token of textTokens(value)) {
      tokens.add(token);
    }
  };

  add(scheduledDate);
  add(weekdayName(scheduledDate));
  add(dayIntent);
  add(weeklyBriefContextTags(input).join(" "));
  add(input.day_guidance ?? "");

  return [...tokens].filter((token) => token.length >= 3);
}

function rankedRelevantRecords(
  records: Record<string, unknown>[],
  tokens: string[],
  options: { max: number; fallback: number },
): Record<string, unknown>[] {
  if (records.length === 0 || options.max <= 0) {
    return [];
  }

  const targetDate = tokens.find((token) => /^\d{4}-\d{2}-\d{2}$/.test(token));
  const ranked = records.map((record, index) => ({
    record,
    index,
    score: dayRecordRelevanceScore(record, tokens, targetDate),
  })).sort((left, right) =>
    right.score - left.score || left.index - right.index
  );
  const relevant = ranked.filter((item) => item.score > 0);
  const selected = relevant.length > 0
    ? relevant.slice(0, options.max)
    : ranked.slice(0, options.fallback);

  return selected.map((item) => item.record);
}

function dayRecordRelevanceScore(
  record: Record<string, unknown>,
  tokens: string[],
  targetDate?: string,
): number {
  const text = safeJSONStringify(record).toLowerCase();
  const recordTokens = new Set(textTokens(text));
  let score = dateRelevanceScore(record, targetDate);

  for (const token of tokens) {
    if (
      recordTokens.has(token) ||
      (/^\d{4}-\d{2}-\d{2}$/.test(token) && text.includes(token))
    ) {
      score += token.length > 8 ? 8 : 4;
    }
  }

  return score;
}

function dateRelevanceScore(
  record: Record<string, unknown>,
  targetDate?: string,
): number {
  if (!targetDate) {
    return 0;
  }
  const dateValues = [
    "scheduled_date",
    "post_date",
    "due_date",
    "review_deadline",
    "moment_date",
    "archive_date",
  ].flatMap((key) => {
    const value = stringValue(record[key]);
    return value ? [value.slice(0, 10)] : [];
  });
  if (dateValues.length === 0) {
    return 0;
  }

  return Math.max(
    ...dateValues.map((value) => {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
        return 0;
      }
      const daysApart = Math.abs(daysBetweenISODates(targetDate, value));
      if (daysApart === 0) {
        return 40;
      }
      if (daysApart <= 1) {
        return 20;
      }
      return 0;
    }),
  );
}

function daysBetweenISODates(left: string, right: string): number {
  const leftMs = Date.parse(`${left}T00:00:00Z`);
  const rightMs = Date.parse(`${right}T00:00:00Z`);
  if (Number.isNaN(leftMs) || Number.isNaN(rightMs)) {
    return Number.POSITIVE_INFINITY;
  }
  return Math.round((rightMs - leftMs) / 86_400_000);
}

function textTokens(value: unknown): string[] {
  const text = String(value ?? "").toLowerCase();
  return Array.from(text.matchAll(/[a-z0-9][a-z0-9-]{2,}/g)).map((match) =>
    match[0]
  ).filter((token) => !DAY_SCOPE_STOPWORDS.has(token));
}

const DAY_SCOPE_STOPWORDS = new Set([
  "the",
  "and",
  "for",
  "with",
  "this",
  "that",
  "only",
  "not",
  "use",
  "uses",
  "using",
  "day",
  "week",
  "weekly",
  "brief",
  "content",
  "pillar",
  "ending",
  "rule",
  "eligible",
  "routine",
  "default",
  "creator",
  "card",
  "reel",
  "post",
  "story",
  "unless",
  "explicitly",
  "context",
  "when",
  "where",
  "from",
  "into",
  "after",
  "before",
  "about",
  "around",
  "never",
  "must",
]);

function uniqueRecordsByStableKey(
  records: Record<string, unknown>[],
): Record<string, unknown>[] {
  const seen = new Set<string>();
  return records.filter((record, index) => {
    const key = stringValue(record.id) ??
      stringValue(record.source_reference_id) ??
      safeJSONStringify(record) ??
      String(index);
    if (seen.has(key)) {
      return false;
    }
    seen.add(key);
    return true;
  });
}

function buildGenerationGuidance(
  input: GenerationInputSnapshot,
  scheduledDate?: string,
  dayIndex?: number,
): Record<string, unknown> {
  const dayIntent = typeof scheduledDate === "string"
    ? dayIntentForScheduledDate(input, scheduledDate, dayIndex)
    : undefined;

  const creatorDisplayName = stringValue(
    isRecord(input.creator_profile)
      ? input.creator_profile.display_name
      : undefined,
  ) ?? "the creator";

  return {
    precedence: [
      "Weekly brief and weekly setup notes win for this week's situational facts, including current city, travel, training status, energy, events, and podcast/admin focus.",
      "Creator profile wins for stable identity, tone, positioning, boundaries, no-go topics, and recurring voice.",
      "Confirmed references, reference extractions, and idea bank are optional inspiration; adapt only when they fit the weekly brief.",
      "Archive, prior weeks, older patterns, and past feedback are lowest priority and must not override this week's brief.",
    ],
    conflict_resolution: [
      "Silently exclude stale lower-priority context when it conflicts with the weekly brief; do not ask the admin to choose.",
      "When uncertain, choose the fact from the weekly brief/setup notes and mention only real output risks, not internal source conflicts.",
    ],
    inferred_exclusions: inferStaleContextExclusions(input),
    creator_positioning: {
      identity:
        "The creator is an Indian mother, wife, and HYROX athlete in her early 60s building a second-half-of-life fitness brand. She is a rounded lifestyle creator documenting her own healthy life - NOT a gym instructor or online coach. Gym is one of four production pillars, not her whole identity.",
      brand_essence:
        "Proof that life does not shrink with age - it gets stronger, fuller, and more intentional.",
      positioning_rule:
        "Show women that the second half of life can be strong, funny, feminine, ambitious, and deeply alive. She is not trying to look younger; she is making 60 feel like something to look forward to.",
      audience: [
        "Women 35+",
        "Indian women and mothers",
        "Women restarting fitness later",
        "People who want fitness to feel real",
        "Fitness, activewear, wellness, hydration, recovery, food, and lifestyle brands",
      ],
      voice_rules: [
        "Conversational, warm, witty, slightly sarcastic, self-aware.",
        "Indian but not caricatured; strong but not intimidating.",
        "Proud but not show-offy; wise without preaching.",
        "Sounds like a woman who has lived enough life to know what matters and is still curious enough to try hard things.",
      ],
      age_rule: [
        "Do not mention the creator's age in every post.",
        "Mention age in at most one card per ordinary week. Use age only when the weekly brief explicitly centers age, milestones, or a milestone event (birthday, HYROX age group, decade reflection).",
        "Use age only when it adds emotional weight, contrast, or context: restarting fitness later, HYROX in her 60s, women ageing well, mother/children contrast, or major milestones.",
        "Avoid age as a default hook for ordinary workouts, meals, brand integrations, captions, or daily routine posts.",
      ],
      never_sound_like: [
        "a 25-year-old fitness influencer",
        "a gym bro",
        "a motivational speaker",
        "a preachy parent",
        "a generic brand ambassador",
        "a luxury wellness cliche",
        "a look-at-me-I-am-62 account",
      ],
      pillars: CONTENT_PILLARS,
      four_pillar_contract:
        "Output content_pillar must remain one of gym, lifestyle, eating, or recovery. The broader creator brand model is guidance only and must be mapped back into those four production values.",
      six_pillar_brand_lens: [
        {
          brand_pillar: "HYROX and serious training",
          production_pillar: "gym",
        },
        {
          brand_pillar: "Strength for the second half of life",
          production_pillar: "gym or lifestyle",
        },
        {
          brand_pillar: "Real routine: food, hydration, recovery, home",
          production_pillar: "eating, recovery, or lifestyle",
        },
        {
          brand_pillar: "Family and Indian home life",
          production_pillar: "lifestyle",
        },
        {
          brand_pillar: "Funny gym realities",
          production_pillar: "gym or lifestyle",
        },
        {
          brand_pillar: "Brand-friendly lifestyle",
          production_pillar:
            "lifestyle, eating, recovery, or gym depending on the real routine moment",
        },
      ],
      pillar_guidance: {
        gym:
          "Frame as what the creator is doing, noticing, or trying herself - never 'here is how to train'. First-person observation, not instruction. HYROX/serious training belongs here only when current-week context supports it.",
        lifestyle:
          "Routines, habits, mindset, family rhythm, Indian home life, travel, humour, and real life. This is the connective tissue of the week.",
        eating:
          "Healthy eating as part of a real life - meals that make gym days easier, recovery food, hydration, simple everyday choices, not a diet plan.",
        recovery:
          "Recovery is not a background state; it is content with a point of view. Show one specific recovery choice with a sharp angle — a comic observation about what rest actually looks like, a surprising truth about soreness, a mobility move that solved a specific problem, or a reset ritual with emotional stakes. Never produce a generic 'rest day' montage or a passive 'here is what I do on recovery days' post. Every recovery Reel must carry the same creative ambition as a gym Reel.",
      },
      weekly_balance: [
        `Set content_pillar for every day to one of: ${
          CONTENT_PILLARS.join(", ")
        }.`,
        `Represent at least 3 of the 4 pillars across a 7-day week unless the weekly brief explicitly narrows scope.`,
        `Default cap: no more than ${GYM_PRIMARY_DAY_CAP} gym-primary days unless the brief explicitly asks for a gym-focused week. Default to exactly 2 training/HYROX-led concepts; day routines may anchor non-training lifestyle, eating, or recovery concepts.`,
        `Every non-training card (lifestyle, eating, recovery) must have a genuinely non-training center. Never relabel a gym script as lifestyle — the content must earn its pillar. A lifestyle card about an 'upper body cue' or a recovery card built around a gym workout is invalid.`,
      ],
      banned_instructor_phrasing: INSTRUCTOR_ISH_PHRASES,
      banned_instructor_endings: BANNED_INSTRUCTOR_ENDINGS,
      banned_framing:
        "Do NOT write like a coach. Ban: 'do this exercise', 'fix your form', 'my clients', 'your clients', 'training clients', 'upper body cue' as the main angle, generic 'training angle', and coach-like imperatives. Also ban instructor endings like 'just start', 'one set, then the next', 'if you needed a reminder', 'the real win', and follower-directed workout permission. Never end a script by instructing the audience what to do. No teaching followers how to train.",
      banned_creator_framing:
        "Avoid phrases like age is just a number, no excuses, crush it, beast mode, discipline beats motivation, queen energy, unstoppable, fitness is my therapy, and this is your sign.",
      banned_creator_phrases: CREATOR_NO_GO_PHRASES,
      creator_native_hooks: [
        "The tiny thing I changed today…",
        "What I'm doing when I don't want a full workout…",
        "My recovery reset after a heavy week…",
        "The meal that makes gym days easier…",
        "One habit I keep coming back to…",
      ],
      creator_style_lines: [
        "I came to the gym for strength. I did not come to negotiate with a sled, but here we are.",
        "My friends think my breakfast sounds sad. My gut disagrees.",
        "Warm-up is not optional. It is a legal requirement.",
        "Everything hurts, but in a very successful way.",
        "I don't train to look young. I train so getting up from the floor is not a family event.",
        "The set I did not ask for, did not want, and will still do again next week.",
        "No wall ball station? Fine. We improvise.",
      ],
      signature_series: CREATOR_SIGNATURE_SERIES,
    },
    creator_voice: {
      title: "Creator Voice",
      voice_essence:
        "The creator sounds like a woman who has lived enough life to know what matters and is still curious enough to try hard things. Warm, witty, slightly sarcastic, self-aware. Indian but not caricatured; strong but not intimidating. Proud but not show-offy; wise without preaching. Conversational tone that feels like a voice note from a friend, not a caption from a brand.",
      point_of_view:
        "She is not trying to look younger; she is making 60 feel like something to look forward to. She documents her own healthy life — gym, food, family, rest — as lived experience, never as instruction. Her point of view is: 'This is what I'm doing, noticing, or trying. Take what works for you.' Show women that the second half of life can be strong, funny, feminine, ambitious, and deeply alive.",
      sounds_like_creator: [
        "I came to the gym for strength. I did not come to negotiate with a sled, but here we are.",
        "My friends think my breakfast sounds sad. My gut disagrees.",
        "Warm-up is not optional. It is a legal requirement.",
        "Everything hurts, but in a very successful way.",
        "I don't train to look young. I train so getting up from the floor is not a family event.",
        "The set I did not ask for, did not want, and will still do again next week.",
        "No wall ball station? Fine. We improvise.",
        "The tiny thing I changed today…",
        "What I'm doing when I don't want a full workout…",
        "The meal that makes gym days easier…",
        "One habit I keep coming back to…",
      ],
      never_sounds_like: [
        "a 25-year-old fitness influencer",
        "a gym bro",
        "a motivational speaker",
        "a preachy parent",
        "a generic brand ambassador",
        "a luxury wellness cliché",
        "a look-at-me-I-am-62 account",
        "a coach teaching followers how to train",
        "age is just a number",
        "no excuses",
        "crush it",
        "beast mode",
        "discipline beats motivation",
        "strong women rise",
        "queen energy",
        "unstoppable",
        "fitness is my therapy",
        "this is your sign",
      ],
      banned_trainer_wording: [
        "one useful cue",
        "one simple cue",
        "restart your routine",
        "protect your joints",
        "save this reel",
        "try this at home",
        "here's what you need to know",
        "the one exercise you should",
        "fix your form",
        "do this exercise",
        "do this workout",
        "try this workout",
        "here's how to train",
        "upper body cue",
        "training angle",
        "my clients",
        "your client",
        "training clients",
      ],
      age_rule: [
        "Do not mention the creator's age in every post.",
        "Mention age in at most one card per ordinary week unless the weekly brief explicitly centers age, milestones, or a milestone event.",
        "Use age only when it adds emotional weight, contrast, or context: restarting fitness later, HYROX in her 60s, women ageing well, mother/children contrast, or major milestones.",
        "Avoid age as a default hook for ordinary workouts, meals, brand integrations, captions, or daily routine posts.",
        "Age is context, not the whole personality. Do not lead with it unless the moment earns it.",
      ],
      writing_test:
        `Before finalizing any line, ask: could another creator say this unchanged? If yes, rewrite it with ${creatorDisplayName}'s lived detail, opinion, family/home context, or dry humour. Generic creator lines fail. Specific, first-person moments pass. If a line would work identically on another creator's account, it has not earned the ${creatorDisplayName} voice.`,
      prefer_instead:
        `First-person lived moments, observations, opinions, dry humour, family/home texture, and specific real situations. Show what ${creatorDisplayName} is doing, noticing, or trying — never instruct the viewer. Replace follower-directed teaching ('you should', 'try this', 'here's how') with personal narration ('I noticed', 'I tried', 'this worked for me', 'my body felt'). Use ordinary detail from Indian home life, kitchen, cooking for family, gym-bag chaos, daughter moments, society garden, or building-gym realities.`,
    },
    retention_first_rules: {
      summary:
        "Every one of the seven Reels must be built for high retention and sharing. These are non-negotiable craft requirements for every Reel, regardless of pillar.",
      "0:00-0:02_hook":
        "The first two seconds must create immediate tension, curiosity, contradiction, or recognition — never a slow fade-in, generic setup, or calm disclaimer. Start with the surprising fact, the joke setup, the confession, or the most visually arresting frame.",
      creator_moment:
        `Each Reel must contain at least one unmistakable creator moment: a personal opinion, contradiction, confession, or comic observation that only ${creatorDisplayName} could make. This is the spine of the Reel — without it the script is generic.`,
      lived_detail:
        `Every script must include at least one ${creatorDisplayName}-specific lived detail drawn from the creator profile and current brief: a food preference, relationship moment, gym-bag reality, location quirk, kitchen scene, home texture, or other real-world detail.`,
      turn_or_payoff:
        "Every Reel needs a satisfying turn or payoff: a joke that lands, a revelation, a contradiction that resolves, or a shift in perspective. Scripts that end with a generic summary line or 'that's it' have not earned their runtime.",
      trigger:
        "End with a natural comment, share, or save trigger that feels organic to the story. The CTA must be the logical next sentence after the payoff — not a tacked-on 'save this' or 'share with a friend.'",
    },
    no_chill_days_rule: {
      summary:
        "No chill days. Every day in the seven-day plan must carry real creative weight. A 'chill day' is any of the following — actively avoid all of them.",
      banned_fillers: [
        "Low-stakes filler concepts with no specific angle, tension, or point of view.",
        "Generic reset/reminder posts ('Monday reset', 'gentle reminder to move').",
        "Passive recovery montages with no opinion ('here's what rest looks like').",
        "Repeated 'one tiny thing I changed' across multiple days of the same week.",
        "Repeated recovery ritual cards that differ only in time-of-day framing.",
        "Generic 'save this for later' endings with no prior narrative reason to save.",
        "Product-led concepts where the brand sits at the centre of the Reel.",
      ],
      recovery_eating_family_rule:
        "Recovery, eating, and family days stay in the four-pillar mix. They must earn their place with sharp creative stakes: a comic observation about recovery, a surprising meal truth, an unexpected family moment with tension, or a recovery story that lands on a real realisation. Do not prescribe intense workouts or compromise safety. Do not default to 'gentle' or 'calm' as an excuse for low creative ambition.",
      litmus_test:
        `If a concept could be any creator's calm Monday, it has not earned ${creatorDisplayName}'s schedule. If a recovery Reel could be posted by anyone who owns a foam roller, rewrite it with a specific ${creatorDisplayName} observation.`,
    },
    virality_stance:
      "Treat virality as an ambition embedded in craft — never a guarantee, never a claim. Do not use words like viral, trending, algorithm-friendly, or guaranteed to blow up. Build retention and sharing into the concept through tension, specificity, and emotional truth, not through format-chasing language.",
    cta_diversity_rules: {
      summary:
        "CTA diversity across the week is non-negotiable. No more than 2 explicit save CTAs across all seven cards.",
      rules: [
        `Use at most 2 explicit save CTAs across the seven-day week.`,
        "Do not end every script by instructing the audience. Include endings such as punchline, natural observation, or a genuinely earned question.",
        "Share or send-to-a-friend CTAs must be earned by the content — never use them as a template filler.",
        "Do NOT lead or end every card with save-this. The CTA must be the logical next sentence after the payoff, not a generic save-this/share-this/tag-someone tack-on.",
        "Use natural, content-earned CTAs: a question the viewer actually wants to answer, a quiet observation that lands, or a punchline that stands on its own.",
      ],
      banned_cta_templates: BANNED_CTA_TEMPLATES,
    },
    factual_discipline_rules: {
      summary:
        "All facts must come from supplied profile, weekly brief, or confirmed references. Invented facts poison trust.",
      rules: [
        "Use only supplied profile, weekly brief, confirmed reference facts, and known capture-bank scenarios.",
        "Never invent: biography details, exact quotes the creator never said, family reactions, exact durations/times, locations not in the brief, personal history, equipment failures, or dialogue.",
        "Capture-bank examples (walking into gym, mirror shot, warm-up, etc.) are real possibilities — not permission to claim they happened.",
        "Place any uncertainty in assumptions or risk_notes. Do not fabricate facts to fill gaps.",
        "If a needed detail is absent from the brief or profile, surface the gap in risk_notes rather than inventing it.",
      ],
    },
    weekly_diversity: {
      avoid_repetition:
        "Do not repeat the same walk, gentle recovery, or low-effort card across the week unless the weekly brief explicitly asks for that repetition. Spread the four pillars across the week.",
      seven_day_mix_rule:
        "For a full seven-day plan, aim for the creator operational mix: exactly 2 training/HYROX reels (unless the brief explicitly asks for more gym), 1 family/home humour reel, 1 food/routine reel, 1 brand-friendly reel, 1 recovery/consistency reel, and 1 experimental/trend-inspired reel. Map each idea back to the four production content_pillar values.",
      seven_day_distinctiveness:
        "Each of the seven days must use a different hook mechanism from the others. Options include: surprise/contradiction, comic observation, confession, useful detail with tension, emotional reflection, aspirational framing, and unexpected opinion. Each day must also draw from a different comic or emotional engine: wry observation, self-deprecation, quiet pride, curiosity, defiance, warmth, or deadpan humour. Brand obligations must not make all seven scripts product-centered. The seven-day arc should feel like a variety show, not a monotone wellness feed.",
      not_every_post:
        "Do not make every post inspirational. Balance humour, utility, routine, emotion, and ordinary real-life specificity.",
      preferred_arc: weekDates(input.week_start_date).map((date, index) =>
        `${weekdayName(date)} ${date}: ${
          dayIntentForScheduledDate(input, date, index)
        }`
      ),
    },
    content_package_rules: {
      shoot_first_rule:
        "Shoot-first: decide what the creator can realistically capture today from the day-of-week routine and current weekly brief before writing the script.",
      routine_override_rule:
        "The day-of-week routine is only the default. If the weekly brief or user input gives a different workout, location, injury, family constraint, brand deliverable, or shoot window, that current input wins.",
      daily_8am_package_expectations: [
        "Write the exact message/content package the creator should receive, but never claim it was sent unless messaging or scheduling is actually connected.",
        "Include today's idea, series, format, why it works, five hooks, exact videos to shoot, VO or text-only script, on-screen text, caption, CTA, editing notes, and a backup idea.",
      ],
      reel_package_shape: [
        "Reel concept",
        "Series",
        "5 hooks",
        "Recommended format",
        "VO or text-only script",
        "Shot list",
        "On-screen text",
        "Caption",
        "CTA",
        "Filming notes",
        "Editing notes",
        "Why this fits the creator's brand",
      ],
      format_guidance: [
        "Use VO when there is a story, emotional context, brand integration, transformation, or trust-building moment.",
        "Use text-only/no VO when the visual is strong, it is a gym hack, trend-style Reel, workout movement, or fast shareable post.",
        "Use direct-to-camera when the creator is sharing a personal hook, opinion, motherhood/family point, or ageing reflection.",
      ],
      realistic_capture_bank: CREATOR_REALISTIC_CAPTURE_BANK,
    },
    brand_collab_rules: [
      "Brand integrations should feel like part of the creator's real routine, not an ad pasted onto a Reel.",
      "Use this structure: real-life moment -> training/routine problem -> product naturally appears -> proof/use moment -> the creator continues with her day.",
      "Never lead with the product unless the weekly brief explicitly asks for that.",
      "For brand content include product/problem angle, natural creator-style VO, shot list, brand-safe caption, disclosure reminder, softer version, and funnier version when the contract fields allow.",
    ],
    instagram_defaults: [
      "Plan each day as Instagram-first content. Default to format Reel and primary_surface Instagram Reels for growth unless the weekly brief explicitly requests Post or Story.",
      "State the planned format as Reel, Post, or Story. For Reels, include duration_seconds and timestamped production guidance for shots, voiceover, on-screen text, and the silent version.",
      "Make every scene and timeline item specific enough to shoot: location/detail, action, camera framing, and the exact video portion the voiceover belongs to.",
      "Every scene, timeline, script line, caption, hook, and backup must align to the SAME content_pillar and the same single idea for that day. Do not mix pillars within one card.",
      "Scene titles must stay short, but shot_timeline.detail must be production-ready: include where the creator can shoot it, what the frame contains, the movement/action, and why that location fits the creator context.",
      "When context includes Bombay/Mumbai, gym return, home rhythm, society garden, or family routine, give context-specific capture examples such as home, society garden, building gym, or nearby gym; do not leave scenes as generic labels.",
      "Scripts must be long enough to record as usable voiceover, usually 45-90 words for a short Reel, with a clear opening, practical middle, and grounded close.",
      "Captions must be concise Instagram captions, usually 40-70 words, with the creator's context, one useful takeaway, and one natural CTA. Keep them tight, scannable, and about half the length of the previous long-form caption target.",
      "Do not include vague support/supports language. Use what_to_capture style guidance in shot_timeline and exact text in on_screen_text_timeline.",
      "When the weekly brief says Bombay, Mumbai, India, travel, gym return, or podcast, make that current context visible where relevant and let it outrank stale stored setup or archive context.",
      "Avoid weight-loss, transformation, punishment, extreme intensity, medical, or guaranteed outcome claims.",
      "Do not output placeholder text, TBD, lorem ipsum, generic assumptions, or fabricated details. If needed details are absent, surface the limitation in risk_notes or assumptions using the provided facts only.",
      "Never claim live Instagram data was pulled unless metrics or live data are explicitly provided in the input.",
    ],
    growth_references: creatorLifestyleGrowthReferences(),
    brief_evidence_rubric: [
      "Every daily card must prove it used the current weekly brief, not just evergreen fitness advice.",
      "Set weekly_brief_anchor to one concrete fact from the weekly setup/brief, such as current city, gym-return routine, family rhythm, brand/collab note, podcast ask, travel status, or explicit avoid list.",
      "Set brief_alignment to one sentence explaining how this specific Reel/Post/Story uses that anchor today.",
      "Set brief_context_tags to 1-4 exact short phrases from the weekly brief/setup notes. Prefer phrases like Bombay, back to gym, podcast, family rhythm, or brand/collab when those appear.",
      "At least five of the seven cards should use the strongest current-week anchors, and the final weekly arc must not drop unusual brief details such as podcast asks or city changes.",
    ],
    day_specific_intent: dayIntent,
  };
}

function dayIntentForScheduledDate(
  input: GenerationInputSnapshot,
  scheduledDate: string,
  dayIndex?: number,
): string {
  const setupText = weeklySetupText(input.weekly_setup).toLowerCase();
  const tags = weeklyBriefContextTags(input);
  const contextLine = tags.length > 0
    ? ` Anchor the idea in: ${tags.join(", ")}.`
    : "";
  const injuryLine =
    /\b(injury|injured|wound|cut|hurt|bandage|stitch|wall ball|wall balls)\b/
        .test(setupText)
      ? " Respect the hand/wound context: avoid grip-heavy filming, medical advice, or dramatic injury framing unless the weekly brief asks for it."
      : "";
  const podcastLine = /\bpodcast\b/.test(setupText)
    ? " Leave room for one reflective podcast-adjacent line only when it fits the day naturally."
    : "";
  const gymFocusWeek =
    /\b(gym week|training block|gym focus|gym-focus|all gym|gym-only|gym focused week)\b/
      .test(setupText);
  const weekday = weekdayName(scheduledDate).toLowerCase();
  const fallbackDay = typeof dayIndex === "number"
    ? `Day ${dayIndex + 1}`
    : "This day";

  // Deterministic normal-week role mix. A weekly brief that explicitly asks
  // for a gym-focused week overrides the non-training roles (training-led days
  // stay training-led but Tuesday/Thursday/Friday/Saturday/Sunday may shift).
  const weekdayIntents: Record<string, string> = {
    monday:
      "Monday: training-led upper body. Pillar gym. Likely footage: gym entry, warm-up, mirror, one strength set. save CTA eligible if earned. Age eligible if the weekly brief supports it; never required.",
    tuesday: gymFocusWeek
      ? "Tuesday: training-led legs. Pillar gym. Likely footage: lunges, sled, leg set, tired smile. save CTA NOT eligible. Age NOT eligible on this day."
      : "Tuesday: recovery/eating/lifestyle around leg-day context. Pillar recovery, eating, or lifestyle - NOT gym. Use recovery food, hydration, sore-leg humour, or practical meal. save CTA NOT eligible. Age NOT eligible on this day.",
    wednesday:
      "Wednesday: training-led floor/abs/HYROX simulation. Pillar gym. Use floor work, wall balls, battle ropes, sled push/pull, or improvisation. save CTA eligible if earned. Age NOT eligible on this day.",
    thursday: gymFocusWeek
      ? "Thursday: training-led compounds. Pillar gym. save CTA NOT eligible. Age NOT eligible on this day."
      : "Thursday: eating. Pillar eating - NOT gym. Use meal prep, plating, ingredient close-ups, hydration, or food observation tied to training rhythm. save CTA NOT eligible. Age NOT eligible on this day.",
    friday: gymFocusWeek
      ? "Friday: training-led shoulder/back. Pillar gym. save CTA NOT eligible. Age NOT eligible on this day."
      : "Friday: lifestyle / funny gym reality. Pillar lifestyle. Shoulder/back footage can be backdrop only; center gym-bag chaos, end-of-week home/family humour, or dry gym-life observation. save CTA NOT eligible. Age NOT eligible on this day.",
    saturday: gymFocusWeek
      ? "Saturday: training-led running/abs. Pillar gym. save CTA NOT eligible. Age NOT eligible on this day."
      : "Saturday: experimental lifestyle. Pillar lifestyle or recovery - NOT gym. Run clip may be backdrop; center weekend, family, hydration, routine, walking, shoes, or unexpected activity. save CTA NOT eligible. Age NOT eligible on this day.",
    sunday:
      "Sunday: recovery/family. Pillar recovery or lifestyle - NOT gym. Use home, plants, cooking, rest, errands, reflection, wind-down, or gym-bag prep. save CTA NOT eligible. Age NOT eligible on this day. Do not force Monday gym-start language.",
  };

  return `${
    weekdayIntents[weekday] ??
      `${fallbackDay}: keep this day distinct and tied to its actual date.`
  }${contextLine}${injuryLine}${podcastLine}`;
}

function creatorLifestyleGrowthReferences(): Record<string, unknown>[] {
  return [
    {
      id: "creator-tiny-change-hook",
      name: "Tiny Thing I Changed Hook",
      use_for:
        "First-person lifestyle Reels about one small change the creator is trying or noticing across any of the four pillars.",
      hook_patterns: [
        "The tiny thing I changed today…",
        "One habit I keep coming back to…",
        "What I'm doing when I don't want a full workout…",
      ],
      production_rule:
        "Open on the small real action (a meal, a stretch, a habit), then one honest line about why it stuck. Never frame it as advice for the viewer.",
      creator_fit:
        "Core lifestyle voice. Works for any pillar; keeps the creator as observer, not instructor.",
    },
    {
      id: "creator-real-life-contradiction-hook",
      name: "Real-Life Contradiction Hook",
      use_for:
        "Relatable Reels about eating out, travel, family rhythm, missed workouts, and staying consistent without guilt.",
      hook_patterns: [
        "I eat out. I drink sometimes. I still keep my routine.",
        "I missed the perfect plan, so I did this instead.",
        "This is how I restart after travel without guilt.",
      ],
      production_rule:
        "Show one normal-life clip, one recovery/movement clip, and one practical consistency rule.",
      creator_fit:
        "High fit for lifestyle and recovery pillars, family rhythm, travel return, and brand/collab weeks.",
    },
    {
      id: "creator-doing-not-teaching",
      name: "What I'm Doing, Not How To Train",
      use_for:
        "Gym-pillar Reels that show the creator doing/noticing her own training without becoming a tutorial.",
      hook_patterns: [
        "One thing I'm noticing in my own training right now…",
        "The lift I keep coming back to this week…",
        "What I do on a gym day when I'm short on energy…",
      ],
      production_rule:
        "The first 0:00-0:03 must be the creator in motion, not a talking-head explanation. Never 'do this exercise' or 'fix your form'.",
      creator_fit:
        "Gym pillar only. Keeps gym as one part of a rounded life, never as coaching.",
    },
    {
      id: "creator-recovery-reset",
      name: "Recovery Reset Hook",
      use_for:
        "Recovery-pillar Reels about rest, sleep, mobility, and resets after a heavy week.",
      hook_patterns: [
        "My recovery reset after a heavy week…",
        "The 10 minutes that change how tomorrow feels…",
        "What rest actually looks like for me…",
      ],
      production_rule:
        "Show the recovery action (stretch, stillness, food, sleep setup) with one grounding line. Position recovery as active and visible.",
      creator_fit:
        "Recovery pillar. Balances gym-heavy weeks and prevents the all-gym instructor drift.",
    },
    {
      id: "creator-meal-that-helps",
      name: "The Meal That Helps Hook",
      use_for:
        "Healthy-eating-pillar Reels that connect food to the rest of the lifestyle (gym energy, recovery, routine).",
      hook_patterns: [
        "The meal that makes gym days easier…",
        "What I actually eat on a recovery day…",
        "One simple swap I keep making…",
      ],
      production_rule:
        "Show the real meal and one honest reason it fits the day. Keep it ordinary and repeatable, not a diet plan.",
      creator_fit:
        "Eating pillar. Connects nutrition to gym/recovery without preaching a diet.",
    },
    {
      id: "creator-instagram-reels-default",
      name: "Instagram Reels Default",
      use_for:
        "Default growth format: short, original, retention-first Reels with one idea and a clear CTA.",
      hook_patterns: [
        "0:00-0:02: motion plus bold text.",
        "0:03-0:08: one real context line.",
        "0:09-0:25: one useful takeaway.",
      ],
      production_rule:
        "For growth cards, default to 15-45 second Reels, one idea, timestamped shot/voiceover/on-screen text, and save/share CTA.",
      creator_fit:
        "System rule for weekly generation unless the brief explicitly asks for Post or Story.",
    },
  ];
}

function inferStaleContextExclusions(input: GenerationInputSnapshot): string[] {
  const setupText = weeklySetupText(input.weekly_setup).toLowerCase();
  const exclusions: string[] = [];

  if (/\b(bombay|mumbai)\b/.test(setupText)) {
    exclusions.push(
      "Exclude New Jersey as current location unless the weekly brief also explicitly says New Jersey for this week.",
    );
  }
  if (
    /\b(back to gym|back in the gym|return(?:ing)? to gym|gym reset|gym)\b/
      .test(setupText)
  ) {
    exclusions.push(
      "Exclude HYROX, race week, and race recovery as the active training frame unless the weekly brief explicitly includes them.",
    );
  }
  if (/\bpodcast\b/.test(setupText)) {
    exclusions.push(
      "Prefer podcast planning/reflection when relevant; do not replace it with older race-recovery context.",
    );
  }

  return exclusions;
}

function weeklySetupText(value: unknown): string {
  if (typeof value === "string") {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map(weeklySetupText).join(" ");
  }
  if (!isRecord(value)) {
    return "";
  }
  return Object.values(value).map(weeklySetupText).join(" ");
}

function weeklyBriefContextTags(input: GenerationInputSnapshot): string[] {
  const setupText = weeklySetupText(input.weekly_setup).toLowerCase();
  const tags: string[] = [];

  if (/\b(bombay|mumbai)\b/.test(setupText)) {
    tags.push("Bombay");
  }
  if (
    /\b(back to gym|back in the gym|gym|strength|training)\b/.test(setupText)
  ) {
    tags.push("back to gym");
  }
  if (/\bregular life|routine|sustainable\b/.test(setupText)) {
    tags.push("regular routine");
  }
  if (/\bfamily|home\b/.test(setupText)) {
    tags.push("family rhythm");
  }
  if (/\bbrand|collab|sponsor\b/.test(setupText)) {
    tags.push("brand/collab");
  }
  if (/\bpodcast\b/.test(setupText)) {
    tags.push("podcast");
  }

  return tags.length > 0 ? tags.slice(0, 4) : ["weekly routine"];
}

export function buildOpenAIDayResponsesRequest(
  input: GenerationInputSnapshot,
  model: string,
  scheduledDate: string,
  dayIndex: number,
): Record<string, unknown> {
  const messages = buildDayPromptMessages(input, scheduledDate, dayIndex);
  return {
    model,
    input: [
      { role: "system", content: messages.system },
      { role: "user", content: messages.user },
    ],
    text: {
      format: {
        type: "json_schema",
        name: "creator_daily_generation",
        strict: true,
        schema: generatedDayJSONSchema,
      },
    },
    max_output_tokens: 12000,
  };
}

export function buildDeepSeekDayChatRequest(
  input: GenerationInputSnapshot,
  model: string,
  scheduledDate: string,
  dayIndex: number,
): Record<string, unknown> {
  const messages = buildDayPromptMessages(input, scheduledDate, dayIndex);
  return {
    model,
    messages: [
      { role: "system", content: messages.system },
      {
        role: "user",
        content: [
          messages.user,
          "Return one valid JSON object only. Do not wrap the JSON in Markdown.",
          `Hard day/date lock: this output is only for scheduled_date ${scheduledDate}, day ${
            dayIndex + 1
          }. Do not mention another weekday unless the weekly brief explicitly names it as context.`,
          "Copy the exact required_contract.daily_card_template key structure. Replace sample values with specific content. Fields shown as arrays must remain arrays.",
          "Set top-level idea_bank to [] unless the brief explicitly asks for extra saved ideas.",
          "Every required string field must contain specific non-empty text; do not use empty strings, TBD, placeholders, null, or undefined.",
          "Use timestamp ranges like 0:00-0:03 in every timeline field.",
          "Never use day_of_week instead of scheduled_date.",
        ].join("\n"),
      },
    ],
    response_format: { type: "json_object" },
    thinking: { type: "enabled" },
    reasoning_effort: "max",
    max_tokens: 12000,
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
        "format",
        "primary_surface",
        "duration_seconds",
        "title",
        "hook",
        "weekly_brief_anchor",
        "brief_alignment",
        "brief_context_tags",
        "why_today",
        "growth_job",
        "save_share_reason",
        "content_pillar",
        "shootability",
        "estimated_shoot_minutes",
        "energy_required",
        "language_mode",
        "scene_list",
        "shot_timeline",
        "script",
        "voiceover_timeline",
        "no_voiceover_version",
        "silent_version_timeline",
        "on_screen_text",
        "on_screen_text_timeline",
        "caption",
        "cta",
        "hashtags",
        "cover_text",
        "post_instructions",
        "brand_event_notes",
        "backup_story",
        "backup_story_detail",
        "backup_caption_only",
        "caption_backup_detail",
        "audio_option_notes",
        "creator_fit_score",
        "risk_notes",
        "assumptions",
        "source_note",
        "source_reference_ids",
      ],
      field_types: {
        scheduled_date: "YYYY-MM-DD string from scheduled_dates_in_order",
        format:
          "Reel, Post, or Story. Default to Reel unless the weekly brief explicitly asks otherwise.",
        primary_surface:
          "Instagram surface such as Instagram Reels, Instagram Feed, or Instagram Stories.",
        duration_seconds:
          "positive integer; for Reels usually 12-30 seconds unless brief requires otherwise",
        weekly_brief_anchor:
          "one concrete fact from the weekly brief/setup notes that this card uses",
        brief_alignment:
          "one sentence explaining how this card uses weekly_brief_anchor today",
        brief_context_tags:
          "non-empty string array of 1-4 exact short phrases from the weekly brief/setup notes",
        estimated_shoot_minutes: "non-negative integer",
        scene_list:
          "non-empty array of objects with number, title, duration, symbol. duration should be a string such as '5 sec'.",
        shot_timeline:
          "non-empty array of { timestamp, detail } using timestamp ranges like 0:00-0:03; detail must say exactly what to shoot with context-specific examples, such as the creator's home, society garden, building gym, or gym when supported by the brief.",
        voiceover_timeline:
          "non-empty array of { timestamp, video_portion, voiceover } using timestamp ranges like 0:00-0:03.",
        on_screen_text: "non-empty string array",
        on_screen_text_timeline:
          "non-empty array of { timestamp, text, placement } using timestamp ranges like 0:00-0:03.",
        silent_version_timeline:
          "non-empty array of { timestamp, detail } for the no-voiceover/silent Reel edit.",
        backup_story_detail:
          "non-empty array of { timestamp, detail } describing a clickable Story backup with sticker/link/poll/tap target where useful.",
        caption_backup_detail:
          "specific text/caption backup guidance, not a placeholder or abbreviated stub",
        hashtags: "non-empty string array without # characters preferred",
        creator_fit_score: "number from 0 to 100",
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

function generatedDayOutputContract(
  scheduledDate: string,
): Record<string, unknown> {
  return {
    top_level_required: [
      "strategy_note",
      "warnings",
      "assumptions",
      "daily_card",
      "idea_bank",
      "source_summary",
    ],
    output_rule:
      "Copy the exact daily_card_template key structure. Replace sample values with specific content. Fields shown as arrays must remain arrays.",
    day_date_lock:
      `daily_card.scheduled_date must be exactly ${scheduledDate}; all copy, title, why_today, timelines, backup story, and caption must describe only that scheduled date's day intent.`,
    daily_card_template: generatedDailyCardCompactTemplate(scheduledDate),
    array_shapes: {
      scene_list:
        "array of { number, title, duration, symbol }; use at least 1 item",
      shot_timeline:
        "array of { timestamp, detail }; timestamp must look like 0:00-0:03; use 3-5 items",
      voiceover_timeline:
        "array of { timestamp, video_portion, voiceover }; use 3-5 items",
      silent_version_timeline: "array of { timestamp, detail }; use 3-5 items",
      on_screen_text: "array of short overlay strings",
      on_screen_text_timeline:
        "array of { timestamp, text, placement }; use 3-5 items",
      backup_story_detail:
        "array of { timestamp, detail }; use at least 1 item",
      source_reference_ids:
        "array of confirmed source UUID strings when available; otherwise []",
    },
    idea_bank:
      "Set [] unless this day creates a genuinely useful extra saved idea.",
  };
}

function generatedDailyCardCompactTemplate(
  scheduledDate: string,
): Record<string, unknown> {
  return {
    scheduled_date: scheduledDate,
    format: "Reel",
    primary_surface: "Instagram Reels",
    duration_seconds: 24,
    title: "Specific daily title",
    hook: "A retention-first hook tied to the first 2 seconds of video.",
    weekly_brief_anchor:
      "A concrete weekly brief fact such as current city, back to gym, family rhythm, brand/collab, travel status, or podcast reflection.",
    brief_alignment:
      "One sentence explaining how this day uses that weekly brief fact.",
    brief_context_tags: ["weekly brief phrase", "current routine"],
    why_today: "Why this idea fits the selected day of the week.",
    growth_job: "The Instagram growth job this Reel performs.",
    save_share_reason: "Why a viewer would save or share this practical cue.",
    content_pillar: "lifestyle",
    shootability: "easy",
    estimated_shoot_minutes: 12,
    energy_required: "medium",
    language_mode: "English with light Hinglish if natural",
    scene_list: [{
      number: 1,
      title: "Proof-first opening",
      duration: "3 sec",
      symbol: "dumbbell",
    }],
    shot_timeline: [{
      timestamp: "0:00-0:03",
      detail:
        "Specific shot direction with location, action, framing, and why it fits this week.",
    }],
    script:
      "A 45-90 word voiceover script with opening, practical middle, and grounded close.",
    voiceover_timeline: [{
      timestamp: "0:00-0:03",
      video_portion: "The exact clip this line belongs to",
      voiceover: "A specific voiceover line for this portion of the Reel.",
    }],
    no_voiceover_version:
      "How to edit the Reel if there is no voiceover, using the same clips and timed text.",
    silent_version_timeline: [{
      timestamp: "0:00-0:03",
      detail:
        "Specific silent edit direction with readable timed text and the same footage.",
    }],
    on_screen_text: ["Back in routine", "One steady cue", "Your next session"],
    on_screen_text_timeline: [{
      timestamp: "0:00-0:03",
      text: "Back in routine",
      placement: "Upper third over motion",
    }],
    caption:
      "A concise 40-70 word Instagram caption with the creator's context, one practical takeaway, and a natural CTA.",
    cta: "Save this for your next practical gym day.",
    hashtags: ["fitnessover60", "gymroutine", "consistency"],
    cover_text: "Simple gym reset",
    post_instructions:
      "Cover text large and readable; keep cuts simple and original audio low.",
    brand_event_notes: "",
    backup_story:
      "A clickable Story backup with one clip, one text sticker, and one reply prompt.",
    backup_story_detail: [{
      timestamp: "0:00-0:05",
      detail:
        "Specific Story frame, sticker, and reply prompt for this same day idea.",
    }],
    backup_caption_only:
      "Caption-only backup summary for days when no video is usable.",
    caption_backup_detail:
      "If no video is usable, post a short caption about the same day-specific cue and ask a question.",
    audio_option_notes:
      "Use clean low-volume audio only if it does not fight the voiceover.",
    creator_fit_score: 88,
    risk_notes: [],
    assumptions: ["No extra shoot support available."],
    source_note: "Used weekly brief and confirmed growth references.",
    source_reference_ids: [],
  };
}

function generatedDailyCardExample(
  weekStartDate: string,
): Record<string, unknown> {
  return {
    scheduled_date: weekStartDate,
    format: "Reel",
    primary_surface: "Instagram Reels",
    duration_seconds: 15,
    title: "Monday reset without drama",
    hook: "First day back? Start smaller than your ego wants.",
    weekly_brief_anchor: "back in Bombay and returning to the gym routine",
    brief_alignment:
      "The Reel turns the weekly brief's Bombay gym-return context into an energy-conscious Monday reset.",
    brief_context_tags: ["Bombay", "back to gym", "regular routine"],
    why_today: "A practical start to the week that is easy to shoot.",
    growth_job: "Build consistency with useful, low-drama fitness content.",
    save_share_reason:
      "Saveable restart cue for anyone easing back into training after travel or a busy week.",
    content_pillar: "lifestyle",
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
    shot_timeline: [
      {
        timestamp: "0:00-0:03",
        detail:
          "Open on gym shoes by the Bombay doorway, then tilt up to the packed bag.",
      },
      {
        timestamp: "0:03-0:10",
        detail:
          "Show one slow mobility rep and one light set; keep framing waist-up and steady.",
      },
      {
        timestamp: "0:10-0:15",
        detail: "End on towel and water bottle with a relaxed nod to camera.",
      },
    ],
    script:
      "First day back does not need a dramatic restart. Today I am keeping it very practical: one small setup, one controlled movement, and one cue I can repeat tomorrow. If your routine has been interrupted by travel, family, or just a full week, start with the version you can actually do. Light weight, clean form, slow reps. The win is not intensity today. The win is making the routine easy to enter again.",
    voiceover_timeline: [
      {
        timestamp: "0:00-0:03",
        video_portion: "Gym shoes and packed bag",
        voiceover: "First day back does not need a dramatic restart.",
      },
      {
        timestamp: "0:03-0:10",
        video_portion: "Light mobility and controlled set",
        voiceover:
          "Pick one cue, move slowly, and leave some energy for tomorrow.",
      },
      {
        timestamp: "0:10-0:15",
        video_portion: "Water and towel close",
        voiceover: "Simple is still a plan.",
      },
    ],
    no_voiceover_version:
      "Silent Reel version: use the same three clips with readable timed text and let the caption carry the coaching point.",
    silent_version_timeline: [
      {
        timestamp: "0:00-0:03",
        detail: "Text hook over gym shoes; no talking head needed.",
      },
      {
        timestamp: "0:03-0:10",
        detail: "Use text labels for the mobility cue and controlled set.",
      },
      {
        timestamp: "0:10-0:15",
        detail: "End with save prompt on the towel/water close-up.",
      },
    ],
    on_screen_text: ["Simple today", "One useful detail"],
    on_screen_text_timeline: [
      {
        timestamp: "0:00-0:03",
        text: "First day back?",
        placement: "Upper third",
      },
      {
        timestamp: "0:03-0:10",
        text: "One useful cue",
        placement: "Lower third beside movement",
      },
      {
        timestamp: "0:10-0:15",
        text: "Save this reset",
        placement: "Center over static close-up",
      },
    ],
    caption:
      "Back to routine does not have to look dramatic. I am keeping today intentionally simple: one setup I can manage, one movement I can do well, and one cue I can carry into the next session. If you are also restarting after travel, family days, or a crowded week, do not make the first workout a test. Make it an entry point. Keep the weight sensible, move slowly, and leave with enough energy to come back tomorrow. Save this for the next time you need a practical reset.",
    cta: "Save this for a low-energy training day.",
    hashtags: ["fitnessover60", "routine", "steady"],
    cover_text: "Simple today",
    post_instructions: "Keep cover text large and readable.",
    brand_event_notes: "",
    backup_story:
      "Story backup: one clip of the gym bag, one form-cue text sticker, and a tap-to-reply question.",
    backup_story_detail: [
      {
        timestamp: "0:00-0:05",
        detail:
          "Post the gym bag clip with text sticker: 'Back to routine, keeping it light.'",
      },
      {
        timestamp: "0:05-0:10",
        detail: "Add question sticker: 'What helps you restart after travel?'",
      },
    ],
    backup_caption_only:
      "Text/caption backup: keeping the routine steady with one small reset cue today.",
    caption_backup_detail:
      "If no video is usable, publish a caption-only note about restarting with one light cue and ask followers what helps them restart after travel.",
    audio_option_notes: "Use clean audio only if it fits.",
    creator_fit_score: 88,
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
    attempt?: AIGenerationProviderAttemptContext,
  ) => Promise<GeneratedWeekOutput> = callAIProvider,
  instrumentation?: AIGenerationInstrumentation,
): Promise<GeneratedWeekOutput> {
  let lastError: unknown = new Error("ai_provider_request_failed");
  for (const provider of providers) {
    try {
      return await invokeProvider(
        input,
        provider,
        makeAIProviderAttemptContext(input, provider, 1, instrumentation),
      );
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}

export async function callAIProvidersForSplitWeek(
  input: GenerationInputSnapshot,
  providers: AIProviderConfig[],
  invokeProvider: (
    input: GenerationInputSnapshot,
    provider: AIProviderConfig,
    scheduledDate: string,
    dayIndex: number,
    attempt?: AIGenerationProviderAttemptContext,
  ) => Promise<GeneratedDayOutput> = callAIProviderForDay,
  instrumentation?: AIGenerationInstrumentation,
): Promise<GeneratedWeekOutput> {
  const dates = weekDates(input.week_start_date);
  const dayOutputs: GeneratedDayOutput[] = [];
  const concurrency = splitWeekGenerationConcurrency();
  for (let start = 0; start < dates.length; start += concurrency) {
    const batch = dates.slice(start, start + concurrency);
    const batchOutputs = await Promise.all(
      batch.map((scheduledDate, offset) =>
        callAIProvidersForDay(
          input,
          providers,
          scheduledDate,
          start + offset,
          invokeProvider,
          instrumentation,
        )
      ),
    );
    dayOutputs.push(...batchOutputs);
  }

  return combineGeneratedDayOutputs(input, dayOutputs);
}

function splitWeekGenerationConcurrency(): number {
  const configured = Deno.env.get("MCO_PARALLEL_WEEK_GENERATION_CONCURRENCY")
    ?.trim();
  const parsed = configured ? Number(configured) : 2;
  if (!Number.isFinite(parsed)) {
    return 2;
  }
  return Math.max(1, Math.min(Math.trunc(parsed), 7));
}

export function combineGeneratedDayOutputs(
  input: GenerationInputSnapshot,
  dayOutputs: GeneratedDayOutput[],
): GeneratedWeekOutput {
  return validateGeneratedWeek({
    strategy_summary: combineText(
      dayOutputs.map((output) => output.strategy_note),
      "A sharp, shootable recovery week with one practical daily content card.",
    ),
    warnings: uniqueStrings(dayOutputs.flatMap((output) => output.warnings)),
    assumptions: uniqueStrings(
      dayOutputs.flatMap((output) => output.assumptions),
    ),
    daily_cards: dayOutputs.map((output) => output.daily_card),
    idea_bank: dayOutputs.flatMap((output) => output.idea_bank).slice(0, 14),
    source_summary: combineText(
      dayOutputs.map((output) => output.source_summary),
      `Used ${input.confirmed_references.length} confirmed references, ${input.recent_archive.length} archive entries, and ${input.idea_bank.length} saved ideas.`,
    ),
  }, input.week_start_date);
}

export async function callAIProvidersForDay(
  input: GenerationInputSnapshot,
  providers: AIProviderConfig[],
  scheduledDate: string,
  dayIndex: number,
  invokeProvider: (
    input: GenerationInputSnapshot,
    provider: AIProviderConfig,
    scheduledDate: string,
    dayIndex: number,
    attempt?: AIGenerationProviderAttemptContext,
  ) => Promise<GeneratedDayOutput> = callAIProviderForDay,
  instrumentation?: AIGenerationInstrumentation,
): Promise<GeneratedDayOutput> {
  let lastError: unknown = new Error("ai_provider_request_failed");
  for (const provider of providers) {
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const attemptInput = attempt === 0 ? input : withDayRetryContext(
        input,
        dayRepairRetryContext(lastError, scheduledDate, dayIndex, attempt + 1),
      );
      try {
        return await invokeProvider(
          attemptInput,
          provider,
          scheduledDate,
          dayIndex,
          makeAIProviderAttemptContext(
            attemptInput,
            provider,
            attempt + 1,
            instrumentation,
            scheduledDate,
            dayIndex,
          ),
        );
      } catch (error) {
        lastError = error;
        if (!isRetryableGeneratedJSONError(error)) {
          break;
        }
      }
    }
  }
  throw lastError;
}

function withDayRetryContext(
  input: GenerationInputSnapshot,
  retryContext: Record<string, unknown>,
): GenerationInputSnapshot {
  return {
    ...input,
    day_retry_context: {
      ...(isRecord(input.day_retry_context) ? input.day_retry_context : {}),
      ...retryContext,
    },
  };
}

function dayRepairRetryContext(
  error: unknown,
  scheduledDate: string,
  dayIndex: number,
  providerAttempt: number,
): Record<string, unknown> {
  const sanitized = sanitizeAIGenerationError(error);
  return {
    retry_kind: "validation_repair",
    retry_reason: sanitized.category,
    scheduled_date: scheduledDate,
    day_index: dayIndex + 1,
    provider_attempt: providerAttempt,
    validation_error: sanitized.validationError,
    error_message: sanitized.message,
    instruction:
      "Repair only the failed daily card for this scheduled_date. Keep the same idea if possible, fix the validation issue, and return the full daily-card JSON contract.",
  };
}

export async function callAIProvider(
  input: GenerationInputSnapshot,
  provider: AIProviderConfig,
  attempt?: AIGenerationProviderAttemptContext,
): Promise<GeneratedWeekOutput> {
  if (provider.provider === "deepseek") {
    return await callDeepSeekChatCompletions(
      input,
      provider.model,
      provider.apiKey,
      provider.baseURL,
      attempt,
    );
  }
  return await callOpenAIResponses(
    input,
    provider.model,
    provider.apiKey,
    attempt,
  );
}

export async function callAIProviderForDay(
  input: GenerationInputSnapshot,
  provider: AIProviderConfig,
  scheduledDate: string,
  dayIndex: number,
  attempt?: AIGenerationProviderAttemptContext,
): Promise<GeneratedDayOutput> {
  if (provider.provider === "deepseek") {
    return await callDeepSeekDayChatCompletions(
      input,
      provider.model,
      provider.apiKey,
      scheduledDate,
      dayIndex,
      provider.baseURL,
      attempt,
    );
  }
  return await callOpenAIDayResponses(
    input,
    provider.model,
    provider.apiKey,
    scheduledDate,
    dayIndex,
    attempt,
  );
}

export async function callDeepSeekChatCompletions(
  input: GenerationInputSnapshot,
  model: string,
  apiKey: string,
  baseURL = "https://api.deepseek.com",
  attempt?: AIGenerationProviderAttemptContext,
): Promise<GeneratedWeekOutput> {
  return await runInstrumentedAIRequest(
    attempt,
    async (recordMetadata, recordQuality, recordRequestMetrics) => {
      const request = buildDeepSeekChatRequest(input, model);
      const requestBody = JSON.stringify(request);
      const timeoutMS = aiRequestTimeoutMS();
      recordRequestMetrics(
        aiGenerationRequestSizeMetrics(input, request, requestBody, timeoutMS),
      );
      const response = await fetchWithAIRequestTimeout(
        `${baseURL.replace(/\/+$/, "")}/chat/completions`,
        {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${apiKey}`,
            "Content-Type": "application/json",
          },
          body: requestBody,
        },
        timeoutMS,
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

      recordMetadata(
        withAIOutputTextSize(
          extractChatCompletionResponseMetadata(json),
          rawJSON,
        ),
      );
      const output = parseGeneratedWeekJSON(rawJSON, input.week_start_date);
      recordQuality(scoreGeneratedWeekOutputQuality(input, output));
      return output;
    },
  );
}

async function callDeepSeekDayChatCompletions(
  input: GenerationInputSnapshot,
  model: string,
  apiKey: string,
  scheduledDate: string,
  dayIndex: number,
  baseURL = "https://api.deepseek.com",
  attempt?: AIGenerationProviderAttemptContext,
): Promise<GeneratedDayOutput> {
  return await runInstrumentedAIRequest(
    attempt,
    async (recordMetadata, recordQuality, recordRequestMetrics) => {
      const request = buildDeepSeekDayChatRequest(
        input,
        model,
        scheduledDate,
        dayIndex,
      );
      const requestBody = JSON.stringify(request);
      const timeoutMS = aiDayRequestTimeoutMS();
      recordRequestMetrics(
        aiGenerationRequestSizeMetrics(input, request, requestBody, timeoutMS),
      );
      const response = await fetchWithAIRequestTimeout(
        `${baseURL.replace(/\/+$/, "")}/chat/completions`,
        {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${apiKey}`,
            "Content-Type": "application/json",
          },
          body: requestBody,
        },
        timeoutMS,
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

      recordMetadata(
        withAIOutputTextSize(
          extractChatCompletionResponseMetadata(json),
          rawJSON,
        ),
      );
      const output = parseGeneratedDayJSON(rawJSON, scheduledDate, dayIndex);
      recordQuality(
        scoreGeneratedDayOutputQuality(input, output, scheduledDate),
      );
      return output;
    },
  );
}

export async function callOpenAIResponses(
  input: GenerationInputSnapshot,
  model: string,
  apiKey: string,
  attempt?: AIGenerationProviderAttemptContext,
): Promise<GeneratedWeekOutput> {
  return await runInstrumentedAIRequest(
    attempt,
    async (recordMetadata, recordQuality, recordRequestMetrics) => {
      const request = buildOpenAIResponsesRequest(input, model);
      const requestBody = JSON.stringify(request);
      const timeoutMS = aiRequestTimeoutMS();
      recordRequestMetrics(
        aiGenerationRequestSizeMetrics(input, request, requestBody, timeoutMS),
      );
      const response = await fetchWithAIRequestTimeout(
        "https://api.openai.com/v1/responses",
        {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${apiKey}`,
            "Content-Type": "application/json",
          },
          body: requestBody,
        },
        timeoutMS,
      );

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

      recordMetadata(
        withAIOutputTextSize(extractOpenAIResponseMetadata(json), rawJSON),
      );
      const output = parseGeneratedWeekJSON(rawJSON, input.week_start_date);
      recordQuality(scoreGeneratedWeekOutputQuality(input, output));
      return output;
    },
  );
}

async function callOpenAIDayResponses(
  input: GenerationInputSnapshot,
  model: string,
  apiKey: string,
  scheduledDate: string,
  dayIndex: number,
  attempt?: AIGenerationProviderAttemptContext,
): Promise<GeneratedDayOutput> {
  return await runInstrumentedAIRequest(
    attempt,
    async (recordMetadata, recordQuality, recordRequestMetrics) => {
      const request = buildOpenAIDayResponsesRequest(
        input,
        model,
        scheduledDate,
        dayIndex,
      );
      const requestBody = JSON.stringify(request);
      const timeoutMS = aiDayRequestTimeoutMS();
      recordRequestMetrics(
        aiGenerationRequestSizeMetrics(input, request, requestBody, timeoutMS),
      );
      const response = await fetchWithAIRequestTimeout(
        "https://api.openai.com/v1/responses",
        {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${apiKey}`,
            "Content-Type": "application/json",
          },
          body: requestBody,
        },
        timeoutMS,
      );

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

      recordMetadata(
        withAIOutputTextSize(extractOpenAIResponseMetadata(json), rawJSON),
      );
      const output = parseGeneratedDayJSON(rawJSON, scheduledDate, dayIndex);
      recordQuality(
        scoreGeneratedDayOutputQuality(input, output, scheduledDate),
      );
      return output;
    },
  );
}

function makeAIProviderAttemptContext(
  input: GenerationInputSnapshot,
  provider: AIProviderConfig,
  providerAttempt: number,
  instrumentation?: AIGenerationInstrumentation,
  scheduledDate?: string,
  dayIndex?: number,
): AIGenerationProviderAttemptContext | undefined {
  if (!instrumentation) {
    return undefined;
  }

  return {
    ...instrumentation,
    provider: provider.provider,
    model: provider.model,
    providerAttempt,
    weekStartDate: input.week_start_date,
    scheduledDate,
    dayIndex,
  };
}

async function runInstrumentedAIRequest<T>(
  attempt: AIGenerationProviderAttemptContext | undefined,
  invoke: (
    recordMetadata: (metadata: AIResponseMetadata) => void,
    recordQuality: (quality: AIOutputQualityMetrics) => void,
    recordRequestMetrics: (metrics: AIGenerationRequestSizeMetrics) => void,
  ) => Promise<T>,
): Promise<T> {
  const startedAt = new Date();
  const startedAtMS = performance.now();
  let metadata = emptyAIResponseMetadata();
  let quality: AIOutputQualityMetrics | null = null;
  let requestMetrics: AIGenerationRequestSizeMetrics | null = null;

  try {
    const output = await invoke(
      (responseMetadata) => {
        metadata = responseMetadata;
      },
      (outputQuality) => {
        quality = outputQuality;
      },
      (metrics) => {
        requestMetrics = metrics;
      },
    );
    emitAIGenerationAttemptLog(
      attempt,
      startedAt,
      startedAtMS,
      "success",
      metadata,
      requestMetrics,
      quality,
    );
    return output;
  } catch (error) {
    emitAIGenerationAttemptLog(
      attempt,
      startedAt,
      startedAtMS,
      "failure",
      metadata,
      requestMetrics,
      quality,
      error,
    );
    throw error;
  }
}

function emitAIGenerationAttemptLog(
  attempt: AIGenerationProviderAttemptContext | undefined,
  startedAt: Date,
  startedAtMS: number,
  status: "success" | "failure",
  metadata: AIResponseMetadata,
  requestMetrics: AIGenerationRequestSizeMetrics | null,
  quality: AIOutputQualityMetrics | null,
  error?: unknown,
): void {
  if (!attempt) {
    return;
  }

  const endedAt = new Date();
  const sanitizedError = error === undefined
    ? { category: null, message: null, validationError: null }
    : sanitizeAIGenerationError(error);
  attempt.logger({
    event: "generation_ai_attempt",
    generation_id: attempt.generationID ?? null,
    generation_scope: attempt.generationScope,
    phase: attempt.phase,
    week_start_date: attempt.weekStartDate,
    scheduled_date: attempt.scheduledDate ?? null,
    day_index: attempt.dayIndex ?? null,
    provider: attempt.provider,
    model: attempt.model,
    provider_attempt: attempt.providerAttempt,
    started_at: startedAt.toISOString(),
    ended_at: endedAt.toISOString(),
    duration_ms: Math.max(0, Math.round(performance.now() - startedAtMS)),
    status,
    input_tokens: metadata.inputTokens,
    output_tokens: metadata.outputTokens,
    total_tokens: metadata.totalTokens,
    finish_reason: metadata.finishReason,
    output_text_chars: metadata.outputTextChars,
    output_text_bytes: metadata.outputTextBytes,
    request_metrics: requestMetrics,
    quality_score: quality?.score ?? null,
    quality_version: quality?.version ?? null,
    quality_metrics: quality,
    error_category: sanitizedError.category,
    error_message: sanitizedError.message,
    validation_error: sanitizedError.validationError,
  });
}

function sanitizeAIGenerationError(
  error: unknown,
): {
  category: string;
  message: string;
  validationError: AIGenerationValidationFailureDetail | null;
} {
  if (error instanceof GenerateWeekValidationError) {
    return {
      category: error.code,
      message: error.message.slice(0, 240),
      validationError: validationFailureDetail(error),
    };
  }

  if (error instanceof Error) {
    if (error.message.startsWith("openai_request_failed:")) {
      return {
        category: "openai_request_failed",
        message: sanitizeStableErrorMessage(error.message),
        validationError: null,
      };
    }
    if (error.message.startsWith("deepseek_request_failed:")) {
      return {
        category: "deepseek_request_failed",
        message: sanitizeStableErrorMessage(error.message),
        validationError: null,
      };
    }
    if (error.message.startsWith("ai_provider_request_failed:")) {
      return {
        category: "ai_provider_request_failed",
        message: sanitizeStableErrorMessage(error.message),
        validationError: null,
      };
    }
    return {
      category: error.name || "error",
      message: "generation_attempt_failed",
      validationError: null,
    };
  }

  if (typeof error === "string") {
    return {
      category: "error",
      message: sanitizeStableErrorMessage(error),
      validationError: null,
    };
  }

  return {
    category: "unknown_error",
    message: "generation_attempt_failed",
    validationError: null,
  };
}

function sanitizeStableErrorMessage(message: string): string {
  return message.replace(/[^a-zA-Z0-9_:\-.]/g, "_").slice(0, 240);
}

function validationFailureDetail(
  error: GenerateWeekValidationError,
): AIGenerationValidationFailureDetail {
  return {
    code: error.code,
    stage: validationFailureStage(error.code),
    rule: validationFailureRule(error.message),
    path: validationFailurePath(error.message),
    retryable: isRetryableGeneratedJSONError(error),
    message: error.message.slice(0, 240),
  };
}

function validationFailureStage(
  code: GenerateWeekValidationCode,
): AIGenerationValidationFailureDetail["stage"] {
  if (code === "invalid_generation_payload") {
    return "request_validation";
  }
  if (code === "invalid_ai_json") {
    return "json_parse";
  }
  return "output_validation";
}

function validationFailureRule(message: string): string {
  if (message.includes("not valid JSON")) {
    return "invalid_json";
  }
  if (message.includes("did not include output JSON")) {
    return "missing_output_json";
  }
  if (message.includes("must contain exactly seven daily cards")) {
    return "daily_card_count";
  }
  if (message.includes("outside the requested week")) {
    return "scheduled_date_outside_week";
  }
  if (message.includes("outside the requested day")) {
    return "scheduled_date_outside_day";
  }
  if (message.includes("Generated card dates must be unique")) {
    return "duplicate_scheduled_date";
  }
  if (message.includes("explicit save CTAs")) {
    return "save_cta_cap";
  }
  if (message.includes("must be a non-empty timeline array")) {
    return "required_timeline";
  }
  if (message.includes("at least one scene")) {
    return "scene_count";
  }
  if (message.includes("must use a timestamp range")) {
    return "timestamp_format";
  }
  if (message.includes("must contain at least one non-empty string")) {
    return "required_non_empty_string_array";
  }
  if (message.includes("must contain only strings")) {
    return "string_array_items";
  }
  if (message.includes("must be an array")) {
    return "array_type";
  }
  if (message.includes("is required")) {
    return "required_string";
  }
  if (message.includes("placeholder content")) {
    return "placeholder_content";
  }
  if (message.includes("content_pillar must be one of")) {
    return "content_pillar_enum";
  }
  if (message.includes("format must be Reel, Post, or Story")) {
    return "format_enum";
  }
  if (message.includes("creator_fit_score must be between")) {
    return "creator_fit_score_range";
  }
  if (message.includes("duration_seconds must be")) {
    return "duration_seconds_range";
  }
  if (message.includes("estimated_shoot_minutes must be")) {
    return "estimated_shoot_minutes_range";
  }
  if (message.includes("must be an object")) {
    return "object_type";
  }
  return "validation_failed";
}

function validationFailurePath(message: string): string | null {
  const bracketPath = message.match(/^([a-zA-Z0-9_.\[\]]+)/)?.[1];
  if (
    bracketPath &&
    (message.includes(" must ") ||
      message.includes(" is required") ||
      message.includes(" contains placeholder"))
  ) {
    return bracketPath;
  }

  const requiredField = message.match(/^([a-zA-Z0-9_.]+) is required\./)?.[1];
  if (requiredField) {
    return requiredField;
  }

  const placeholderField = message.match(
    /^([a-zA-Z0-9_.]+) contains placeholder/,
  )
    ?.[1];
  if (placeholderField) {
    return placeholderField;
  }

  if (message.includes("daily cards")) {
    return "daily_cards";
  }
  if (message.includes("idea_bank")) {
    return "idea_bank";
  }
  if (message.includes("scene")) {
    return "scene_list";
  }
  if (message.includes("scheduled_date") || message.includes("date")) {
    return "scheduled_date";
  }
  return null;
}

function aiGenerationRequestSizeMetrics(
  input: GenerationInputSnapshot,
  request: Record<string, unknown>,
  requestBody: string,
  requestTimeoutMS: number = aiRequestTimeoutMS(),
): AIGenerationRequestSizeMetrics {
  const prompts = providerPromptText(request);
  const requestInput = requestInputSnapshot(request) ?? input;
  const inputSnapshot = safeJSONStringify(requestInput);
  const rawInputSnapshot = safeJSONStringify(input);
  const confirmedReferences = requestRecordArray(
    requestInput,
    "confirmed_references",
  );
  const rawConfirmedReferences = input.confirmed_references;
  const referenceExtractions = requestRecordArray(
    requestInput,
    "reference_extractions",
  );
  const rawReferenceExtractions = input.reference_extractions;
  const recentArchive = requestRecordArray(requestInput, "recent_archive");
  const ideaBank = requestRecordArray(requestInput, "idea_bank");
  const patterns = requestRecordArray(requestInput, "patterns");
  const trends = requestRecordArray(requestInput, "trends");
  const audioOptions = requestRecordArray(requestInput, "audio_options");
  const brandBriefs = requestRecordArray(requestInput, "brand_briefs");
  const keyMoments = requestRecordArray(requestInput, "key_moments");
  const existingWeekCards = requestRecordArray(
    requestInput,
    "existing_week_cards",
  );
  const existingDayCard = requestRecordArray(requestInput, "existing_day_card");
  const sentExistingCards = existingWeekCards.length > 0
    ? existingWeekCards
    : existingDayCard;
  const referenceContext = safeJSONStringify({
    confirmed_references: confirmedReferences,
    reference_extractions: referenceExtractions,
  });
  const rawReferenceContext = safeJSONStringify({
    confirmed_references: rawConfirmedReferences,
    reference_extractions: rawReferenceExtractions,
  });
  const rawExistingWeekCards = input.existing_week_cards ?? [];

  return {
    prompt_system_chars: prompts.system.length,
    prompt_user_chars: prompts.user.length,
    prompt_total_chars: prompts.total.length,
    prompt_total_bytes: utf8ByteLength(prompts.total),
    prompt_estimated_tokens: estimatedTokenCount(prompts.total),
    provider_request_body_chars: requestBody.length,
    provider_request_body_bytes: utf8ByteLength(requestBody),
    request_timeout_ms: requestTimeoutMS,
    request_input_version: requestInputVersion(requestInput),
    input_snapshot_chars: inputSnapshot.length,
    input_snapshot_bytes: utf8ByteLength(inputSnapshot),
    input_snapshot_estimated_tokens: estimatedTokenCount(inputSnapshot),
    raw_input_snapshot_chars: rawInputSnapshot.length,
    raw_input_snapshot_bytes: utf8ByteLength(rawInputSnapshot),
    raw_input_snapshot_estimated_tokens: estimatedTokenCount(rawInputSnapshot),
    reference_context_chars: referenceContext.length,
    reference_context_bytes: utf8ByteLength(referenceContext),
    reference_context_estimated_tokens: estimatedTokenCount(referenceContext),
    raw_reference_context_chars: rawReferenceContext.length,
    dropped_reference_context_chars: Math.max(
      0,
      rawReferenceContext.length - referenceContext.length,
    ),
    creator_profile_chars: safeJSONStringify(
      requestRecord(requestInput, "creator_profile"),
    ).length,
    weekly_setup_chars:
      safeJSONStringify(requestRecord(requestInput, "weekly_setup"))
        .length,
    confirmed_reference_count: confirmedReferences.length,
    raw_confirmed_reference_count: rawConfirmedReferences.length,
    dropped_confirmed_reference_count: Math.max(
      0,
      rawConfirmedReferences.length - confirmedReferences.length,
    ),
    confirmed_reference_chars: safeJSONStringify(confirmedReferences).length,
    reference_extraction_count: referenceExtractions.length,
    raw_reference_extraction_count: rawReferenceExtractions.length,
    dropped_reference_extraction_count: Math.max(
      0,
      rawReferenceExtractions.length - referenceExtractions.length,
    ),
    reference_extraction_chars: safeJSONStringify(referenceExtractions).length,
    recent_archive_count: recentArchive.length,
    raw_recent_archive_count: input.recent_archive.length,
    dropped_recent_archive_count: Math.max(
      0,
      input.recent_archive.length - recentArchive.length,
    ),
    recent_archive_chars: safeJSONStringify(recentArchive).length,
    idea_bank_count: ideaBank.length,
    raw_idea_bank_count: input.idea_bank.length,
    dropped_idea_bank_count: Math.max(
      0,
      input.idea_bank.length - ideaBank.length,
    ),
    idea_bank_chars: safeJSONStringify(ideaBank).length,
    pattern_count: patterns.length,
    raw_pattern_count: input.patterns.length,
    dropped_pattern_count: Math.max(0, input.patterns.length - patterns.length),
    pattern_chars: safeJSONStringify(patterns).length,
    trend_count: trends.length,
    raw_trend_count: input.trends.length,
    dropped_trend_count: Math.max(0, input.trends.length - trends.length),
    trend_chars: safeJSONStringify(trends).length,
    audio_option_count: audioOptions.length,
    raw_audio_option_count: input.audio_options.length,
    dropped_audio_option_count: Math.max(
      0,
      input.audio_options.length - audioOptions.length,
    ),
    audio_option_chars: safeJSONStringify(audioOptions).length,
    brand_brief_count: brandBriefs.length,
    raw_brand_brief_count: input.brand_briefs.length,
    dropped_brand_brief_count: Math.max(
      0,
      input.brand_briefs.length - brandBriefs.length,
    ),
    brand_brief_chars: safeJSONStringify(brandBriefs).length,
    key_moment_count: keyMoments.length,
    raw_key_moment_count: input.key_moments.length,
    dropped_key_moment_count: Math.max(
      0,
      input.key_moments.length - keyMoments.length,
    ),
    key_moment_chars: safeJSONStringify(keyMoments).length,
    existing_week_card_count: sentExistingCards.length,
    raw_existing_week_card_count: rawExistingWeekCards.length,
    dropped_existing_week_card_count: Math.max(
      0,
      rawExistingWeekCards.length - sentExistingCards.length,
    ),
    existing_week_card_chars: safeJSONStringify(sentExistingCards).length,
  };
}

function requestInputSnapshot(
  request: Record<string, unknown>,
): Record<string, unknown> | null {
  const user = providerPromptText(request).user;
  const firstLine = user.split("\n", 1)[0]?.trim();
  if (!firstLine) {
    return null;
  }
  try {
    const payload = JSON.parse(firstLine);
    if (isRecord(payload) && isRecord(payload.input)) {
      return payload.input;
    }
  } catch {
    return null;
  }
  return null;
}

function requestInputVersion(input: Record<string, unknown>): string | null {
  return stringValue(input.compact_input_version) ??
    stringValue(input.input_version) ??
    null;
}

function requestRecord(
  input: Record<string, unknown>,
  key: string,
): Record<string, unknown> {
  const value = input[key];
  return isRecord(value) ? value : {};
}

function requestRecordArray(
  input: Record<string, unknown>,
  key: string,
): Record<string, unknown>[] {
  const value = input[key];
  if (!Array.isArray(value)) {
    return [];
  }
  return value.filter(isRecord);
}

function providerPromptText(
  request: Record<string, unknown>,
): { system: string; user: string; total: string } {
  const messages = Array.isArray(request.messages)
    ? request.messages
    : Array.isArray(request.input)
    ? request.input
    : [];
  const system: string[] = [];
  const user: string[] = [];

  for (const message of messages) {
    if (!isRecord(message)) {
      continue;
    }
    const content = stringValue(message.content) ?? "";
    if (message.role === "system") {
      system.push(content);
    } else if (message.role === "user") {
      user.push(content);
    }
  }

  const systemText = system.join("\n");
  const userText = user.join("\n");
  return {
    system: systemText,
    user: userText,
    total: [systemText, userText].filter((value) => value.length > 0).join(
      "\n",
    ),
  };
}

function withAIOutputTextSize(
  metadata: AIResponseMetadata,
  outputText: string,
): AIResponseMetadata {
  return {
    ...metadata,
    outputTextChars: outputText.length,
    outputTextBytes: utf8ByteLength(outputText),
  };
}

function safeJSONStringify(value: unknown): string {
  try {
    return JSON.stringify(value) ?? "";
  } catch {
    return "";
  }
}

function utf8ByteLength(value: string): number {
  return new TextEncoder().encode(value).length;
}

function estimatedTokenCount(value: string): number {
  return Math.ceil(value.length / 4);
}

function extractOpenAIResponseMetadata(response: unknown): AIResponseMetadata {
  if (!isRecord(response)) {
    return emptyAIResponseMetadata();
  }

  const usage = isRecord(response.usage) ? response.usage : undefined;
  const incompleteDetails = isRecord(response.incomplete_details)
    ? response.incomplete_details
    : undefined;
  return {
    inputTokens: optionalTokenCount(usage?.input_tokens),
    outputTokens: optionalTokenCount(usage?.output_tokens),
    totalTokens: optionalTokenCount(usage?.total_tokens),
    finishReason: stringValue(incompleteDetails?.reason) ??
      findOpenAIFinishReason(response.output),
    outputTextChars: null,
    outputTextBytes: null,
  };
}

function extractChatCompletionResponseMetadata(
  response: unknown,
): AIResponseMetadata {
  if (!isRecord(response)) {
    return emptyAIResponseMetadata();
  }

  const usage = isRecord(response.usage) ? response.usage : undefined;
  return {
    inputTokens: optionalTokenCount(usage?.prompt_tokens),
    outputTokens: optionalTokenCount(usage?.completion_tokens),
    totalTokens: optionalTokenCount(usage?.total_tokens),
    finishReason: firstChatCompletionFinishReason(response.choices),
    outputTextChars: null,
    outputTextBytes: null,
  };
}

function emptyAIResponseMetadata(): AIResponseMetadata {
  return {
    inputTokens: null,
    outputTokens: null,
    totalTokens: null,
    finishReason: null,
    outputTextChars: null,
    outputTextBytes: null,
  };
}

function optionalTokenCount(value: unknown): number | null {
  const parsed = numberValue(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function firstChatCompletionFinishReason(choices: unknown): string | null {
  if (!Array.isArray(choices)) {
    return null;
  }

  for (const choice of choices) {
    if (!isRecord(choice)) {
      continue;
    }
    const finishReason = stringValue(choice.finish_reason);
    if (finishReason) {
      return finishReason;
    }
  }
  return null;
}

function findOpenAIFinishReason(output: unknown): string | null {
  if (!Array.isArray(output)) {
    return null;
  }

  for (const outputItem of output) {
    if (!isRecord(outputItem)) {
      continue;
    }
    const finishReason = stringValue(outputItem.finish_reason) ??
      stringValue(outputItem.stop_reason);
    if (finishReason) {
      return finishReason;
    }
  }
  return null;
}

function scoreGeneratedWeekOutputQuality(
  input: GenerationInputSnapshot,
  output: GeneratedWeekOutput,
): AIOutputQualityMetrics {
  return scoreGeneratedCardsQuality(input, output.daily_cards);
}

function scoreGeneratedDayOutputQuality(
  input: GenerationInputSnapshot,
  output: GeneratedDayOutput,
  scheduledDate: string,
): AIOutputQualityMetrics {
  return scoreGeneratedCardsQuality(input, [output.daily_card]);
}

function scoreGeneratedCardsQuality(
  _input: GenerationInputSnapshot,
  cards: GeneratedDailyCard[],
): AIOutputQualityMetrics {
  const snapshots = cards.map(cardQualitySnapshot);
  const pillarCount = new Set(
    cards.map((card) => card.content_pillar).filter((pillar) =>
      pillar.length > 0
    ),
  ).size;
  const storySnapshots = snapshots.filter((snapshot) => snapshot.isStory);
  const postSnapshots = snapshots.filter((snapshot) => snapshot.isPost);
  const metricsWithoutScore = {
    version: "instagram_content_quality_v2" as const,
    pillar_count: pillarCount,
    instructor_phrase_count:
      cards.filter((card) =>
        containsInstructorPhrasing(generatedCardQualityText(card))
      ).length,
    instructor_ending_count:
      cards.filter((card) =>
        containsInstructorEnding(generatedCardQualityText(card))
      ).length,
    source_reference_link_count: cards.reduce(
      (sum, card) => sum + card.source_reference_ids.length,
      0,
    ),
    cards_with_source_reference_count:
      cards.filter((card) => card.source_reference_ids.length > 0).length,
    hook_first_3s_present: allSnapshotsPass(
      snapshots,
      (snapshot) => snapshot.hookFirst3SPresent,
    ),
    first_frame_text_hook_present: allSnapshotsPass(
      snapshots,
      (snapshot) => snapshot.firstFrameTextHookPresent,
    ),
    opening_visual_motion_present: allSnapshotsPass(
      snapshots,
      (snapshot) => snapshot.openingVisualMotionPresent,
    ),
    clear_payoff_or_curiosity_gap_present: allSnapshotsPass(
      snapshots,
      (snapshot) => snapshot.clearPayoffOrCuriosityGapPresent,
    ),
    watch_without_sound_ready: allSnapshotsPass(
      snapshots,
      (snapshot) => snapshot.watchWithoutSoundReady,
    ),
    on_screen_text_present: allSnapshotsPass(
      snapshots,
      (snapshot) => snapshot.onScreenTextPresent,
    ),
    caption_or_subtitle_support_present: allSnapshotsPass(
      snapshots,
      (snapshot) => snapshot.captionOrSubtitleSupportPresent,
    ),
    on_screen_text_density_ok: allSnapshotsPass(
      snapshots,
      (snapshot) => snapshot.onScreenTextDensityOK,
    ),
    duration_fit: combinedDurationFit(snapshots),
    scene_variety_count: averageSceneVarietyCount(snapshots),
    visual_variety_present: allSnapshotsPass(
      snapshots,
      (snapshot) => snapshot.visualVarietyPresent,
    ),
    audio_or_silent_strategy_present: allSnapshotsPass(
      snapshots,
      (snapshot) => snapshot.audioOrSilentStrategyPresent,
    ),
    shareability_reason_present: allSnapshotsPass(
      snapshots,
      (snapshot) => snapshot.shareabilityReasonPresent,
    ),
    save_or_share_value_present: allSnapshotsPass(
      snapshots,
      (snapshot) => snapshot.saveOrShareValuePresent,
    ),
    clear_cta_present: allSnapshotsPass(
      snapshots,
      (snapshot) => snapshot.clearCTAPresent,
    ),
    cta_type: dominantCTAType(snapshots),
    creator_lived_detail_present: allSnapshotsPass(
      snapshots,
      (snapshot) => snapshot.creatorLivedDetailPresent,
    ),
    specific_context_anchor_present: allSnapshotsPass(
      snapshots,
      (snapshot) => snapshot.specificContextAnchorPresent,
    ),
    generic_template_risk_count:
      snapshots.filter((snapshot) => snapshot.genericTemplateRiskPresent)
        .length,
    story_interactive_sticker_present: nullableAllSnapshotsPass(
      storySnapshots,
      (snapshot) => snapshot.storyInteractiveStickerPresent,
    ),
    story_reply_prompt_present: nullableAllSnapshotsPass(
      storySnapshots,
      (snapshot) => snapshot.storyReplyPromptPresent,
    ),
    story_slide_count_fit: nullableAllSnapshotsPass(
      storySnapshots,
      (snapshot) => snapshot.storySlideCountFit,
    ),
    post_first_slide_promise_present: nullableAllSnapshotsPass(
      postSnapshots,
      (snapshot) => snapshot.postFirstSlidePromisePresent,
    ),
    post_one_clear_idea_present: nullableAllSnapshotsPass(
      postSnapshots,
      (snapshot) => snapshot.postOneClearIdeaPresent,
    ),
    post_final_cta_present: nullableAllSnapshotsPass(
      postSnapshots,
      (snapshot) => snapshot.clearCTAPresent,
    ),
    post_saveable_value_present: nullableAllSnapshotsPass(
      postSnapshots,
      (snapshot) => snapshot.saveOrShareValuePresent,
    ),
  };

  return {
    ...metricsWithoutScore,
    score: generationQualityScore(metricsWithoutScore),
  };
}

function generationQualityScore(
  metrics: Omit<AIOutputQualityMetrics, "score">,
): number {
  const retentionScore = averageScore([
    metrics.hook_first_3s_present,
    metrics.first_frame_text_hook_present,
    metrics.opening_visual_motion_present,
    metrics.clear_payoff_or_curiosity_gap_present,
  ]) * 30;
  const formatFitScore = averageScore([
    durationFitScore(metrics.duration_fit),
    metrics.visual_variety_present,
    metrics.audio_or_silent_strategy_present,
  ]) * 20;
  const accessibilityScore = averageScore([
    metrics.watch_without_sound_ready,
    metrics.on_screen_text_present,
    metrics.caption_or_subtitle_support_present,
    metrics.on_screen_text_density_ok,
  ]) * 15;
  const saveShareScore = averageScore([
    metrics.shareability_reason_present,
    metrics.save_or_share_value_present,
    metrics.clear_cta_present,
  ]) * 15;
  const authenticityScore = Math.max(
    0,
    averageScore([
          metrics.creator_lived_detail_present,
          metrics.specific_context_anchor_present,
        ]) * 10 - Math.min(metrics.generic_template_risk_count * 3, 6),
  );
  const safetyScore = Math.max(
    0,
    averageScore([
      metrics.pillar_count >= 3 || metrics.pillar_count === 1,
      metrics.instructor_phrase_count === 0,
      metrics.instructor_ending_count === 0,
      metrics.source_reference_link_count > 0 ||
      metrics.cards_with_source_reference_count === 0,
    ]) * 10,
  );
  const score = retentionScore + formatFitScore + accessibilityScore +
    saveShareScore + authenticityScore + safetyScore;
  return Math.max(0, Math.min(100, Math.round(score)));
}

type CardQualitySnapshot = {
  hookFirst3SPresent: boolean;
  firstFrameTextHookPresent: boolean;
  openingVisualMotionPresent: boolean;
  clearPayoffOrCuriosityGapPresent: boolean;
  watchWithoutSoundReady: boolean;
  onScreenTextPresent: boolean;
  captionOrSubtitleSupportPresent: boolean;
  onScreenTextDensityOK: boolean;
  durationFit: AIOutputQualityMetrics["duration_fit"];
  sceneVarietyCount: number;
  visualVarietyPresent: boolean;
  audioOrSilentStrategyPresent: boolean;
  shareabilityReasonPresent: boolean;
  saveOrShareValuePresent: boolean;
  clearCTAPresent: boolean;
  ctaType: AIOutputQualityMetrics["cta_type"];
  creatorLivedDetailPresent: boolean;
  specificContextAnchorPresent: boolean;
  genericTemplateRiskPresent: boolean;
  isStory: boolean;
  isPost: boolean;
  storyInteractiveStickerPresent: boolean;
  storyReplyPromptPresent: boolean;
  storySlideCountFit: boolean;
  postFirstSlidePromisePresent: boolean;
  postOneClearIdeaPresent: boolean;
};

function cardQualitySnapshot(card: GeneratedDailyCard): CardQualitySnapshot {
  const allText = generatedCardQualityText(card);
  const firstFrameText = firstNonBlank([
    card.on_screen_text[0],
    card.on_screen_text_timeline[0]?.text,
    card.cover_text,
  ]);
  const openingText = [
    card.hook,
    card.title,
    firstFrameText,
    card.shot_timeline[0]?.detail,
    card.scene_list[0]?.title,
  ].filter(Boolean).join(" ");
  const ctaType = classifyCTA(card.cta);
  const isStory = card.format === "Story" ||
    /story/i.test(card.primary_surface);
  const isPost = card.format === "Post" ||
    /post|carousel/i.test(card.primary_surface);
  const storyText = [
    card.backup_story,
    card.backup_caption_only,
    card.caption_backup_detail,
    ...card.backup_story_detail.map((item) => item.detail),
  ].join(" ");
  const postText = [card.title, card.hook, card.cover_text, card.caption].join(
    " ",
  );

  return {
    hookFirst3SPresent: hasHookInOpening(openingText),
    firstFrameTextHookPresent: hasHookInOpening(firstFrameText),
    openingVisualMotionPresent: hasOpeningVisualMotion(card),
    clearPayoffOrCuriosityGapPresent: hasPayoffOrCuriosityGap(openingText),
    watchWithoutSoundReady: card.on_screen_text.length > 0 &&
      card.silent_version_timeline.length > 0 &&
      card.no_voiceover_version.trim().length > 0,
    onScreenTextPresent: card.on_screen_text.length > 0 ||
      card.on_screen_text_timeline.length > 0,
    captionOrSubtitleSupportPresent: card.caption.trim().length > 0 ||
      card.voiceover_timeline.length > 0,
    onScreenTextDensityOK: onScreenTextDensityOK(card),
    durationFit: durationFit(card),
    sceneVarietyCount: sceneVarietyCount(card),
    visualVarietyPresent: sceneVarietyCount(card) >= 3,
    audioOrSilentStrategyPresent: card.audio_option_notes.trim().length > 0 ||
      card.no_voiceover_version.trim().length > 0 ||
      card.silent_version_timeline.length > 0,
    shareabilityReasonPresent: card.save_share_reason.trim().length > 0,
    saveOrShareValuePresent: hasSaveOrShareValue(card),
    clearCTAPresent: ctaType !== "none",
    ctaType,
    creatorLivedDetailPresent: hasCreatorLivedDetail(allText),
    specificContextAnchorPresent: hasSpecificContextAnchor(card),
    genericTemplateRiskPresent: hasGenericTemplateRisk(allText),
    isStory,
    isPost,
    storyInteractiveStickerPresent: /poll|quiz|question|reply|sticker|tap/i
      .test(storyText),
    storyReplyPromptPresent: /reply|question|tell me|dm|tap/i.test(storyText),
    storySlideCountFit: card.backup_story_detail.length >= 1 &&
      card.backup_story_detail.length <= 5,
    postFirstSlidePromisePresent: hasHookInOpening(postText),
    postOneClearIdeaPresent: hasOneClearIdea(card),
  };
}

function allSnapshotsPass(
  snapshots: CardQualitySnapshot[],
  predicate: (snapshot: CardQualitySnapshot) => boolean,
): boolean {
  return snapshots.length > 0 && snapshots.every(predicate);
}

function nullableAllSnapshotsPass(
  snapshots: CardQualitySnapshot[],
  predicate: (snapshot: CardQualitySnapshot) => boolean,
): boolean | null {
  return snapshots.length === 0 ? null : snapshots.every(predicate);
}

function averageSceneVarietyCount(snapshots: CardQualitySnapshot[]): number {
  if (snapshots.length === 0) {
    return 0;
  }
  const total = snapshots.reduce(
    (sum, snapshot) => sum + snapshot.sceneVarietyCount,
    0,
  );
  return Math.round(total / snapshots.length);
}

function combinedDurationFit(
  snapshots: CardQualitySnapshot[],
): AIOutputQualityMetrics["duration_fit"] {
  if (snapshots.length === 0) {
    return "not_applicable";
  }
  const fits = snapshots.map((snapshot) => snapshot.durationFit);
  if (fits.includes("too_long")) {
    return "too_long";
  }
  if (fits.includes("too_short")) {
    return "too_short";
  }
  if (fits.includes("acceptable")) {
    return "acceptable";
  }
  if (fits.every((fit) => fit === "not_applicable")) {
    return "not_applicable";
  }
  return "ideal";
}

function dominantCTAType(
  snapshots: CardQualitySnapshot[],
): AIOutputQualityMetrics["cta_type"] {
  const counts: Record<AIOutputQualityMetrics["cta_type"], number> = {
    save: 0,
    share: 0,
    reply: 0,
    comment: 0,
    profile: 0,
    none: 0,
  };
  for (const snapshot of snapshots) {
    counts[snapshot.ctaType] += 1;
  }
  return (Object.entries(counts).sort((a, b) => b[1] - a[1])[0]?.[0] ??
    "none") as AIOutputQualityMetrics["cta_type"];
}

function averageScore(values: Array<boolean | number>): number {
  if (values.length === 0) {
    return 0;
  }
  const total = values.reduce((sum: number, value) => {
    const score = typeof value === "number" ? value : value ? 1 : 0;
    return sum + score;
  }, 0);
  return total / values.length;
}

function durationFitScore(
  fit: AIOutputQualityMetrics["duration_fit"],
): number {
  switch (fit) {
    case "ideal":
      return 1;
    case "acceptable":
      return 0.7;
    case "not_applicable":
      return 0.8;
    case "too_short":
    case "too_long":
      return 0;
  }
}

function durationFit(
  card: GeneratedDailyCard,
): AIOutputQualityMetrics["duration_fit"] {
  if (card.format !== "Reel" && !/reel/i.test(card.primary_surface)) {
    return "not_applicable";
  }
  if (card.duration_seconds < 3) {
    return "too_short";
  }
  if (card.duration_seconds <= 6) {
    return "acceptable";
  }
  if (card.duration_seconds <= 45) {
    return "ideal";
  }
  if (card.duration_seconds <= 90) {
    return "acceptable";
  }
  return "too_long";
}

function sceneVarietyCount(card: GeneratedDailyCard): number {
  return Math.max(
    card.scene_list.length,
    card.shot_timeline.length,
    card.on_screen_text_timeline.length,
  );
}

function hasHookInOpening(text: string | undefined): boolean {
  const normalized = text?.trim() ?? "";
  if (normalized.length === 0) {
    return false;
  }
  return /\?|why\b|what\b|how\b|before\b|after\b|mistake\b|thing\b|changed\b|truth\b|stop\b|start\b|simple\b|tiny\b|today\b|first\b|reset\b|unexpected\b/i
    .test(normalized);
}

function hasPayoffOrCuriosityGap(text: string): boolean {
  return /\?|why\b|what\b|how\b|because\b|but\b|instead\b|thing\b|changed\b|truth\b|mistake\b|reason\b|learned\b|worth\b|useful\b/i
    .test(text);
}

function hasOpeningVisualMotion(card: GeneratedDailyCard): boolean {
  const openingVisual = [
    card.scene_list[0]?.title,
    card.shot_timeline[0]?.detail,
    card.voiceover_timeline[0]?.video_portion,
  ].filter(Boolean).join(" ");
  return /walk|push|pull|lift|move|open|enter|show|clip|shot|close|cut|transition|mirror|bag|set|rep|text over|camera/i
    .test(openingVisual);
}

function onScreenTextDensityOK(card: GeneratedDailyCard): boolean {
  const textItems = [
    ...card.on_screen_text,
    ...card.on_screen_text_timeline.map((item) => item.text),
  ];
  return textItems.length > 0 &&
    textItems.every((text) => text.trim().length <= 90);
}

function classifyCTA(
  cta: string,
): AIOutputQualityMetrics["cta_type"] {
  if (/\bsave\b/i.test(cta)) {
    return "save";
  }
  if (/\bshare|send|tag\b/i.test(cta)) {
    return "share";
  }
  if (/\breply|dm\b/i.test(cta)) {
    return "reply";
  }
  if (/\bcomment|tell me\b/i.test(cta)) {
    return "comment";
  }
  if (/\blink|profile|bio\b/i.test(cta)) {
    return "profile";
  }
  return cta.trim().length > 0 ? "comment" : "none";
}

function hasSaveOrShareValue(card: GeneratedDailyCard): boolean {
  const valueText = [
    card.save_share_reason,
    card.cta,
    card.caption,
    card.backup_caption_only,
  ].join(" ");
  return /save|share|send|useful|later|next time|routine|reset|checklist|reminder|reference|try/i
    .test(valueText);
}

function hasCreatorLivedDetail(text: string): boolean {
  return /\bI\b|\bmy\b|\bme\b|\bfamily\b|\bdaughter\b|\bhusband\b|\bhome\b|\bIndian\b|\bHYROX\b|\bgym\b|\broutine\b|\btoday\b/i
    .test(text);
}

function hasSpecificContextAnchor(card: GeneratedDailyCard): boolean {
  return card.weekly_brief_anchor.trim().length > 0 ||
    card.brief_alignment.trim().length > 0 ||
    card.brief_context_tags.length > 0 ||
    card.source_note.trim().length > 0 ||
    card.source_reference_ids.length > 0;
}

function hasGenericTemplateRisk(text: string): boolean {
  const normalized = text.toLowerCase();
  return CREATOR_NO_GO_PHRASES.some((phrase) =>
    normalized.includes(phrase.toLowerCase())
  ) ||
    BANNED_CTA_TEMPLATES.filter((phrase) =>
        normalized.includes(phrase.toLowerCase())
      ).length > 1;
}

function hasOneClearIdea(card: GeneratedDailyCard): boolean {
  const anchors = [
    card.title,
    card.hook,
    card.weekly_brief_anchor,
    card.why_today,
    card.growth_job,
  ].filter((value) => value.trim().length > 0);
  return anchors.length >= 3 && new Set([
        card.content_pillar,
        card.growth_job,
      ]).size >= 1;
}

function firstNonBlank(values: Array<string | undefined>): string {
  return values.find((value) => value && value.trim().length > 0) ?? "";
}

function generatedCardQualityText(card: GeneratedDailyCard): string {
  return [
    card.title,
    card.hook,
    card.weekly_brief_anchor,
    card.brief_alignment,
    card.why_today,
    card.growth_job,
    card.save_share_reason,
    card.script,
    card.no_voiceover_version,
    ...card.on_screen_text,
    card.caption,
    card.cta,
    card.cover_text,
    card.post_instructions,
    card.brand_event_notes,
    card.backup_story,
    card.backup_caption_only,
    card.caption_backup_detail,
    card.audio_option_notes,
    card.source_note,
  ].join(" ");
}

async function fetchWithAIRequestTimeout(
  input: string,
  init: RequestInit,
  timeoutMS: number = aiRequestTimeoutMS(),
): Promise<Response> {
  const controller = new AbortController();
  const timeoutID = setTimeout(() => controller.abort(), timeoutMS);
  try {
    return await fetch(input, {
      ...init,
      signal: controller.signal,
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new Error(`ai_provider_request_failed:timeout:${timeoutMS}`);
    }
    throw error;
  } finally {
    clearTimeout(timeoutID);
  }
}

export function resolveAIRequestTimeoutMs(
  configured: string | undefined,
): number {
  if (!configured) {
    return DEFAULT_AI_REQUEST_TIMEOUT_MS;
  }

  const parsed = Number(configured);
  if (!Number.isFinite(parsed) || parsed < 5_000) {
    return DEFAULT_AI_REQUEST_TIMEOUT_MS;
  }
  return Math.min(parsed, 240_000);
}

function aiRequestTimeoutMS(): number {
  return resolveAIRequestTimeoutMs(
    Deno.env.get("MCO_AI_REQUEST_TIMEOUT_MS")?.trim(),
  );
}

export function resolveAIDayRequestTimeoutMs(
  configured: string | undefined,
  generalConfigured?: string,
): number {
  if (!configured) {
    return resolveAIRequestTimeoutMs(generalConfigured);
  }
  return resolveAIRequestTimeoutMs(configured);
}

function aiDayRequestTimeoutMS(): number {
  return resolveAIDayRequestTimeoutMs(
    Deno.env.get("MCO_AI_DAY_REQUEST_TIMEOUT_MS")?.trim(),
    Deno.env.get("MCO_AI_REQUEST_TIMEOUT_MS")?.trim(),
  );
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
  const parsed = parseJSONResponse(rawJSON);
  return validateGeneratedWeek(parsed, weekStartDate);
}

function parseGeneratedDayJSON(
  rawJSON: string,
  scheduledDate: string,
  dayIndex: number,
): GeneratedDayOutput {
  const parsed = parseJSONResponse(rawJSON);
  return validateGeneratedDayOutput(parsed, scheduledDate, dayIndex);
}

function parseJSONResponse(rawJSON: string): unknown {
  const normalized = stripMarkdownFence(rawJSON.trim());
  try {
    return JSON.parse(normalized);
  } catch {
    const extracted = extractFirstJSONObject(normalized);
    if (extracted) {
      try {
        return JSON.parse(extracted);
      } catch {
        // Fall through to the stable error below.
      }
    }
  }

  throw new GenerateWeekValidationError(
    "invalid_ai_json",
    "Generated output was not valid JSON.",
  );
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

  assertWeekPillarBalance(dailyCards, value);

  const saveCTACount = countExplicitSaveCTAs(dailyCards);
  if (saveCTACount > 2) {
    throw invalidWeek(
      `Week contains ${saveCTACount} explicit save CTAs; at most 2 are allowed across the seven-day week.`,
    );
  }

  dailyCards.forEach((card) => assertCreatorNotInstructor(card));

  return {
    strategy_summary: strategySummary,
    warnings,
    assumptions,
    daily_cards: dailyCards,
    idea_bank: ideaBank,
    source_summary: sourceSummary,
  };
}

export function validateGeneratedDayOutput(
  value: unknown,
  scheduledDate: string,
  dayIndex: number,
): GeneratedDayOutput {
  if (!isRecord(value)) {
    throw invalidWeek("Generated day must be an object.");
  }

  const cardValue = value.daily_card ??
    (Array.isArray(value.daily_cards) ? value.daily_cards[0] : undefined);
  const dailyCard = validateGeneratedDailyCard(cardValue, dayIndex);
  if (dailyCard.scheduled_date !== scheduledDate) {
    throw invalidWeek("Generated card date is outside the requested day.");
  }
  assertNoConflictingWeekdayLanguage(dailyCard, scheduledDate);

  const ideaBank = Array.isArray(value.idea_bank)
    ? value.idea_bank.map(validateGeneratedIdea)
    : [];

  return {
    strategy_note: stringValue(value.strategy_note) ??
      `Day ${dayIndex + 1} is planned as a practical, shootable card.`,
    warnings: Array.isArray(value.warnings)
      ? requiredStringArray(value.warnings, "warnings")
      : [],
    assumptions: Array.isArray(value.assumptions)
      ? requiredStringArray(value.assumptions, "assumptions")
      : dailyCard.assumptions,
    daily_card: dailyCard,
    idea_bank: ideaBank,
    source_summary: stringValue(value.source_summary) ??
      dailyCard.source_note,
  };
}

function assertNoConflictingWeekdayLanguage(
  dailyCard: GeneratedDailyCard,
  scheduledDate: string,
) {
  const expectedWeekday = weekdayName(scheduledDate).toLowerCase();
  const text = [
    dailyCard.title,
    dailyCard.why_today,
    dailyCard.weekly_brief_anchor,
    dailyCard.brief_alignment,
    dailyCard.growth_job,
    dailyCard.post_instructions,
    dailyCard.source_note,
  ].join(" ").toLowerCase();
  const weekdays = [
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
    "sunday",
  ];
  const conflicting = weekdays.find((weekday) =>
    weekday !== expectedWeekday &&
    new RegExp(`\\b${weekday}\\b`, "i").test(text)
  );
  if (conflicting) {
    throw invalidWeek(
      `Generated card mentions ${conflicting} for ${expectedWeekday}.`,
    );
  }
}

/**
 * Enforces creator positioning across the week: gym is one pillar among four,
 * not the whole identity. Unless the weekly brief explicitly narrows scope, a
 * seven-day week must touch at least three of the four pillars and must not
 * exceed the gym-primary day cap.
 */
function assertWeekPillarBalance(
  dailyCards: GeneratedDailyCard[],
  weekValue: unknown,
) {
  const pillarCounts = new Map<ContentPillar, number>();
  for (const card of dailyCards) {
    const pillar = normalizeContentPillar(card.content_pillar) ?? "gym";
    pillarCounts.set(pillar, (pillarCounts.get(pillar) ?? 0) + 1);
  }

  const distinctPillars = pillarCounts.size;
  const gymDays = pillarCounts.get("gym") ?? 0;

  // The brief can explicitly narrow scope (e.g. a gym-heavy week). Detect that
  // signal from the strategy summary and weekly setup notes ONLY — not from
  // card copy, which legitimately mentions "gym" throughout.
  const briefText = extractBriefScopeText(weekValue);
  const briefNarrowsScope = briefText.includes("gym week") ||
    briefText.includes("training block") ||
    briefText.includes("gym focus") ||
    briefText.includes("gym-focus") ||
    briefText.includes("all gym") ||
    briefText.includes("gym-only") ||
    briefText.includes("gym focused week");

  if (dailyCards.length >= 7 && distinctPillars < 3 && !briefNarrowsScope) {
    throw invalidWeek(
      `Week must represent at least 3 of 4 content pillars; found ${distinctPillars}.`,
    );
  }

  if (
    dailyCards.length >= 7 && gymDays > GYM_PRIMARY_DAY_CAP &&
    !briefNarrowsScope
  ) {
    throw invalidWeek(
      `No more than ${GYM_PRIMARY_DAY_CAP} gym-primary days in a 7-day week unless the brief explicitly narrows scope; found ${gymDays}.`,
    );
  }
}

/** Extracts only the brief-level scope text (strategy summary + setup notes),
 * excluding per-card copy, so narrow-scope detection is not fooled by routine
 * mentions of "gym" inside card bodies. */
function extractBriefScopeText(weekValue: unknown): string {
  if (!isRecord(weekValue)) {
    return "";
  }
  const parts: string[] = [];
  const strategySummary = stringValue(weekValue.strategy_summary);
  if (strategySummary) {
    parts.push(strategySummary);
  }
  // Weekly setup notes can be nested under input/weekly_setup in the prompt
  // payload, but validateGeneratedWeek receives the top-level output object.
  const notes = stringValue(weekValue.weekly_brief) ??
    stringValue(weekValue.brief);
  if (notes) {
    parts.push(notes);
  }
  return parts.join(" ").toLowerCase();
}

/**
 * Rejects instructor/coach framing. The creator documents her own lifestyle —
 * she does not train clients or teach people how to lift. Catches banned
 * phrases like "upper body cue", "training angle", "clients", "fix your form".
 */
function assertCreatorNotInstructor(card: GeneratedDailyCard) {
  const text = JSON.stringify({
    title: card.title,
    hook: card.hook,
    why_today: card.why_today,
    growth_job: card.growth_job,
    save_share_reason: card.save_share_reason,
    cover_text: card.cover_text,
    source_note: card.source_note,
    caption: card.caption,
    script: card.script,
    no_voiceover_version: card.no_voiceover_version,
    scene_list: card.scene_list,
    shot_timeline: card.shot_timeline,
    voiceover_timeline: card.voiceover_timeline,
    on_screen_text: card.on_screen_text,
    on_screen_text_timeline: card.on_screen_text_timeline,
    post_instructions: card.post_instructions,
    backup_story: card.backup_story,
    backup_story_detail: card.backup_story_detail,
    backup_caption_only: card.backup_caption_only,
    caption_backup_detail: card.caption_backup_detail,
  });
  if (containsInstructorPhrasing(text)) {
    throw invalidWeek(
      `Generated card for ${card.scheduled_date} uses coach/instructor framing. The creator documents her own life; she does not train clients.`,
    );
  }
  if (containsInstructorEnding(text)) {
    throw invalidWeek(
      `Generated card for ${card.scheduled_date} uses a banned instructor ending. End with punchline, observation, or earned question — never 'just start', 'one set, then the next', 'the real win', or follower-directed workout permission.`,
    );
  }
}

function weekdayName(dateString: string): string {
  const date = new Date(`${dateString}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) {
    return "day";
  }
  return new Intl.DateTimeFormat("en-US", {
    weekday: "long",
    timeZone: "UTC",
  }).format(date);
}

export function makeMockGeneratedWeek(
  input: GenerationInputSnapshot,
): GeneratedWeekOutput {
  const dates = weekDates(input.week_start_date);
  const profileName = stringValue(input.creator_profile?.display_name) ??
    "Creator";
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
      `${profileName} gets a sharp, shootable week anchored in ${setupLocation}, one practical reel per day, and backup paths for low-energy days.`,
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
      mockCard(
        input,
        date,
        index,
        firstIdea,
        referenceNote,
        sourceReferenceIDs,
      )
    ),
    idea_bank: [
      {
        title: "Caption-only sharp reset",
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
  input: GenerationInputSnapshot,
  scheduledDate: string,
  index: number,
  firstIdea: string,
  referenceNote: string,
  sourceReferenceIDs: string[],
): GeneratedDailyCard {
  const plan = fallbackDayPlan(input, index);
  const title = plan.title;
  const shootability = index === 6 ? "backup" : "easy";

  return {
    scheduled_date: scheduledDate,
    format: "Reel",
    primary_surface: "Instagram Reels",
    duration_seconds: 18,
    title,
    hook: plan.hook,
    weekly_brief_anchor: plan.weekly_brief_anchor,
    brief_alignment: plan.brief_alignment,
    brief_context_tags: plan.brief_context_tags,
    why_today: plan.why_today ||
      `This keeps ${firstIdea.toLowerCase()} visible without asking for a heavy shoot.`,
    growth_job: plan.growth_job,
    save_share_reason: plan.save_share_reason,
    content_pillar: plan.content_pillar,
    shootability,
    estimated_shoot_minutes: index === 6 ? 6 : 12,
    energy_required: index === 6 ? "low" : "medium",
    language_mode: "English with light Hinglish if natural",
    scene_list: [
      {
        number: 1,
        title: plan.scene_titles[0],
        duration: "3 sec",
        symbol: "sparkles",
      },
      {
        number: 2,
        title: plan.scene_titles[1],
        duration: "5 sec",
        symbol: "figure.run",
      },
      {
        number: 3,
        title: plan.scene_titles[2],
        duration: "4 sec",
        symbol: "text.quote",
      },
    ],
    shot_timeline: [
      {
        timestamp: "0:00-0:03",
        detail: `${
          plan.scene_titles[0]
        }: open with the clearest context detail in the creator's home, society garden, building gym, or gym, using a steady vertical frame that explains where the day is happening.`,
      },
      {
        timestamp: "0:03-0:12",
        detail: `${
          plan.scene_titles[1]
        }: show the practical fitness cue slowly enough that viewers can copy the idea safely; choose the location that makes the movement easiest to film without clutter.`,
      },
      {
        timestamp: "0:12-0:18",
        detail: `${
          plan.scene_titles[2]
        }: finish with an intentional close-up, cover-safe framing, and no extreme claim.`,
      },
    ],
    script: plan.script,
    voiceover_timeline: [
      {
        timestamp: "0:00-0:03",
        video_portion: plan.scene_titles[0],
        voiceover: plan.voiceover_lines[0],
      },
      {
        timestamp: "0:03-0:12",
        video_portion: plan.scene_titles[1],
        voiceover: plan.voiceover_lines[1],
      },
      {
        timestamp: "0:12-0:18",
        video_portion: plan.scene_titles[2],
        voiceover: plan.voiceover_lines[2],
      },
    ],
    no_voiceover_version: plan.no_voiceover_version,
    silent_version_timeline: [
      {
        timestamp: "0:00-0:03",
        detail: `Silent edit opens with text hook: ${plan.on_screen_text[0]}.`,
      },
      {
        timestamp: "0:03-0:12",
        detail: `Keep movement audio-free and use the cue text: ${
          plan.on_screen_text[1]
        }.`,
      },
      {
        timestamp: "0:12-0:18",
        detail: `End with a save/share prompt over the final clip: ${
          plan.on_screen_text.at(-1) ?? title
        }.`,
      },
    ],
    on_screen_text: plan.on_screen_text,
    on_screen_text_timeline: [
      {
        timestamp: "0:00-0:03",
        text: plan.on_screen_text[0],
        placement: "Upper third with face or object unobstructed",
      },
      {
        timestamp: "0:03-0:12",
        text: plan.on_screen_text[1],
        placement: "Lower third beside the movement cue",
      },
      {
        timestamp: "0:12-0:18",
        text: plan.on_screen_text.at(-1) ?? title,
        placement: "Center over the final steady frame",
      },
    ],
    caption: plan.caption,
    cta: plan.cta,
    hashtags: plan.hashtags,
    cover_text: title,
    post_instructions:
      "Use clean audio if available. Keep cover text large and readable.",
    brand_event_notes: "",
    backup_story:
      "Story backup: one vertical clip, one useful cue sticker, and one tap-to-reply prompt.",
    backup_story_detail: [
      {
        timestamp: "0:00-0:05",
        detail: `Post ${
          plan.scene_titles[0].toLowerCase()
        } with a text sticker summarizing today's cue.`,
      },
      {
        timestamp: "0:05-0:10",
        detail: `Add a question sticker tied to the Reel cue: ${plan.cta}`,
      },
    ],
    backup_caption_only:
      "Text/caption backup: keeping the routine steady today with one practical cue from the planned Reel.",
    caption_backup_detail:
      "If the Reel cannot be shot, publish the caption as a text-first update with the same useful cue, no fabricated footage, and a reply question.",
    audio_option_notes:
      "Use a confirmed clean audio option if it fits; otherwise post without audio dependence.",
    creator_fit_score: 88,
    risk_notes: [],
    assumptions: [],
    source_note: referenceNote,
    source_reference_ids: sourceReferenceIDs,
  };
}

function fallbackDayPlan(
  input: GenerationInputSnapshot,
  index: number,
): {
  title: string;
  hook: string;
  weekly_brief_anchor: string;
  brief_alignment: string;
  brief_context_tags: string[];
  why_today: string;
  growth_job: string;
  save_share_reason: string;
  content_pillar: string;
  scene_titles: [string, string, string];
  script: string;
  voiceover_lines: [string, string, string];
  no_voiceover_version: string;
  on_screen_text: string[];
  caption: string;
  cta: string;
  hashtags: string[];
} {
  const setupText = weeklySetupText(input.weekly_setup).toLowerCase();
  const location = /\b(bombay|mumbai)\b/.test(setupText) ? "Bombay" : "home";
  const gymFrame = /\b(gym|strength|training|routine|regular life)\b/.test(
    setupText,
  );
  const podcastFrame = /\bpodcast\b/.test(setupText);
  const contextTags = weeklyBriefContextTags(input);
  const gymPhrase = gymFrame ? "gym routine" : "routine";
  const podcastLine = podcastFrame
    ? " Leave one reflective line open for the podcast conversation."
    : "";
  const plans = [
    {
      title: `Back in ${location}: light reset day`,
      hook:
        `Back in ${location}: restart with a light reset, not a big promise.`,
      weekly_brief_anchor: gymFrame
        ? "back to gym"
        : contextTags[0] ?? "weekly routine",
      brief_alignment: gymFrame
        ? "This Reel uses the brief's gym-return context to frame Monday as a practical re-entry day."
        : "This Reel uses the weekly brief's routine context to keep Monday specific and shootable.",
      brief_context_tags: contextTags,
      why_today:
        `Start the week by showing the return to regular life and a practical ${gymPhrase}.`,
      growth_job:
        "Rebuild trust around consistency without making the reset feel intense.",
      save_share_reason:
        "Followers can save it as a simple first-day-back lifestyle reset after travel.",
      content_pillar: "gym",
      scene_titles: [
        "Gym bag or shoes",
        "Light full-body reset",
        "Done is enough",
      ] as [string, string, string],
      script:
        `First day back in routine does not need a dramatic restart. I am keeping it light: a little mobility, a few easy sets, and one small win I can repeat tomorrow. If you are also coming back after travel or a full week, do not make the first session a test. Make it an entry point. Move well, leave some energy, and come back again.${podcastLine}`,
      voiceover_lines: [
        `Back in ${location}, and today is just about restarting.`,
        "Keep the first session light: mobility, a few easy sets, and one clean cue.",
        "The win is getting the rhythm back without overdoing it.",
      ] as [string, string, string],
      no_voiceover_version:
        "Silent Reel version: show shoes or gym bag, one light movement, and a clean post-workout clip with timed text overlays.",
      on_screen_text: [
        "Back to routine",
        "Light reset",
        "Restart, don't overdo",
      ],
      caption:
        `Back in ${location} and easing into the week with a light reset. I am not trying to prove anything on the first day back. The goal is to move a little, get the rhythm back, and leave enough energy to show up again tomorrow. If your routine also gets interrupted by travel, family, or just regular life, keep the first session simple. One setup, one cue, one small win. Save this for your next restart day.`,
      cta: "Save this for your first day back after travel.",
      hashtags: ["backtoroutine", "gymroutine", "practicalwellness"],
    },
    {
      title: "Lower-body day: one form cue",
      hook: "One lower-body cue before you add more load.",
      weekly_brief_anchor: gymFrame ? "gym routine" : "lower-body routine",
      brief_alignment:
        "This Reel turns the weekly routine into one safe lower-body cue viewers can copy.",
      brief_context_tags: contextTags,
      why_today:
        "The second day can carry one specific strength detail without becoming a full workout tutorial.",
      growth_job:
        "Make training advice practical enough for busy women to use immediately.",
      save_share_reason:
        "A saveable note viewers can use in their next lower-body session.",
      content_pillar: "gym",
      scene_titles: [
        "Set up the movement",
        "Show the cue",
        "Quick reminder",
      ] as [string, string, string],
      script:
        "Lower-body day, but I am keeping the focus on one cue instead of ten. Before adding more load, slow the first rep down and notice where the work is happening. If the setup feels rushed, the set usually feels rushed too. So today is simple: set the feet, move with control, and let the first rep tell you whether the weight is right. Better control before heavier weight.",
      voiceover_lines: [
        "Lower-body day does not need ten tips.",
        "Slow the first rep down and notice where the work is happening.",
        "Better control comes before adding more load.",
      ] as [string, string, string],
      no_voiceover_version:
        "Silent Reel version: film one setup shot, one controlled rep, and one close-up of the cue as timed text.",
      on_screen_text: [
        "Lower body day",
        "Slow first rep",
        "Control before load",
      ],
      caption:
        "A practical lower-body cue for the week: slow down the first rep. It tells you more than adding weight too quickly. If you feel the movement in the wrong place, or the setup feels messy, that first rep is giving you useful information. Reset, reduce the load if needed, and make the next rep cleaner. This is the kind of small cue that makes training feel easier to return to. Save it for your next lower-body day.",
      cta: "Try this cue in your next strength session.",
      hashtags: ["strengthtraining", "gymroutine", "formcue"],
    },
    {
      title: "Midweek mobility: 5-minute reset",
      hook: "Five minutes to feel less stuck before the next session.",
      weekly_brief_anchor: gymFrame
        ? "sustainable wellness groove"
        : "mobility",
      brief_alignment:
        "This Reel uses the weekly brief's sustainable-routine frame to make midweek mobility practical.",
      brief_context_tags: contextTags,
      why_today:
        "A mobility day creates contrast between strength days and keeps the week sustainable.",
      growth_job:
        "Position recovery as part of regular training, not a fallback.",
      save_share_reason:
        "A short mobility reset viewers can save for a stiff midweek day.",
      content_pillar: "recovery",
      scene_titles: [
        "Stiff spot check",
        "Three gentle moves",
        "Walk out easier",
      ] as [string, string, string],
      script:
        "Midweek check-in: five minutes for the places that feel stuck before the next session. I like to keep this very simple: hips, shoulders, ankles, and a little breathing room between each move. This is not a workout pretending to be recovery. It is just enough movement to make the next session feel less stiff and more doable.",
      voiceover_lines: [
        "Midweek is a good time to check what feels stiff.",
        "Give hips, shoulders, and ankles a few quiet minutes.",
        "It is not fancy; it just makes the next session feel better.",
      ] as [string, string, string],
      no_voiceover_version:
        "Silent Reel version: use three short movement clips with timed labels for hips, shoulders, and ankles.",
      on_screen_text: ["5-minute mobility", "Hips", "Shoulders", "Ankles"],
      caption:
        "Midweek mobility does not need to be a production. Five quiet minutes can make the next workout feel better, especially when the week is already full. Pick the areas that feel most stuck, move slowly, and stop before it turns into another intense session. For me, this is about making the routine sustainable, not adding more pressure. Save this for a day when your body needs a small reset.",
      cta: "Save this for an active recovery day.",
      hashtags: ["mobility", "activerecovery", "movewell"],
    },
    {
      title: "The meal that makes gym days easier",
      hook: "The meal that makes gym days easier to repeat.",
      weekly_brief_anchor: gymFrame
        ? "fuel the gym routine"
        : "easy weekday meal",
      brief_alignment:
        "This Reel uses the week's training rhythm to show one ordinary meal that supports gym and recovery days.",
      brief_context_tags: contextTags,
      why_today:
        "Thursday is a good point in the week to show food as part of the routine, not as a separate diet identity.",
      growth_job:
        "Make healthy eating feel ordinary, repeatable, and tied to real life.",
      save_share_reason:
        "A simple meal idea viewers can save for a busy gym-or-recovery day.",
      content_pillar: "eating",
      scene_titles: [
        "Prep the meal",
        "Plate it simply",
        "Why it fits today",
      ] as [string, string, string],
      script:
        "Today is about one simple meal that makes the rest of the week easier. I am keeping it ordinary: protein, something green, and a carb that actually fuels the next session. This is not a diet plan. It is just the food I keep coming back to because it is easy and it works for a training or recovery day. Make it once, repeat it, and let the routine carry you.",
      voiceover_lines: [
        "One meal I keep coming back to on busy weeks.",
        "Protein, something green, and a carb that fuels the next session.",
        "Ordinary and repeatable beats complicated every time.",
      ] as [string, string, string],
      no_voiceover_version:
        "Silent Reel version: film the prep, the plated meal, and one close-up of the ingredients as timed text.",
      on_screen_text: [
        "Easy gym-day meal",
        "Protein + green + carb",
        "Repeat it all week",
      ],
      caption:
        "The meal that makes gym days easier does not need to be fancy. Protein, something green, and a carb that actually fuels the next session is the combo I keep returning to. It is ordinary, it repeats, and it takes the decision load off a busy week. If you are also juggling training, recovery, and regular life, keep one meal like this in rotation. What meal keeps your training week going?",
      cta: "What meal keeps your training week going?",
      hashtags: ["easymealprep", "healthyeating", "fuelyourweek"],
    },
    {
      title: "One habit I keep coming back to on busy Fridays",
      hook: "One habit I keep coming back to when the week feels full.",
      weekly_brief_anchor: gymFrame ? "Friday rhythm" : "busy-day routine",
      brief_alignment:
        "This Reel uses the brief's busy-Friday reality to show one repeatable habit that keeps the week together.",
      brief_context_tags: contextTags,
      why_today:
        "Friday should feel like real life: one small habit that keeps the routine steady without adding pressure.",
      growth_job:
        "Make consistency feel grounded in lifestyle rhythm rather than perfect execution.",
      save_share_reason:
        "A repeatable Friday habit viewers can save for busy weeks.",
      content_pillar: "lifestyle",
      scene_titles: [
        "End-of-week reality",
        "One small reset habit",
        "Leave it easy to repeat",
      ] as [string, string, string],
      script:
        "By Friday I do not need a big reset. I need one small habit that helps the week end cleanly and makes Monday easier. For me that can be laying out the next gym set, prepping one simple meal, or taking ten quiet minutes before the evening gets busy. Tiny habits are easier to repeat than dramatic promises.",
      voiceover_lines: [
        "By Friday I look for one small habit that still fits real life.",
        "Lay out the next step, prep one easy thing, or take ten quiet minutes.",
        "Small and repeatable works better than dramatic.",
      ] as [string, string, string],
      no_voiceover_version:
        "Silent Reel version: show one end-of-week habit, one prep detail, and a clean closing clip with timed text.",
      on_screen_text: [
        "Friday habit",
        "Keep it small",
        "Make Monday easier",
      ],
      caption:
        "The end of the week does not need a dramatic reset. One small habit can do more for consistency than a big promise you cannot repeat. On busy Fridays I come back to the simplest things: set up tomorrow, prep one easy meal, leave ten quiet minutes, and keep the rhythm going. What is one thing you keep coming back to on busy weeks?",
      cta: "What is one thing you keep coming back to on busy weeks?",
      hashtags: ["busyroutine", "lifestylerhythm", "sustainablewellness"],
    },
    {
      title: "Saturday recovery at home",
      hook: "Recovery can fit inside normal Saturday life.",
      weekly_brief_anchor: /family|home/.test(setupText)
        ? "family rhythm"
        : contextTags[0] ?? "weekend routine",
      brief_alignment: /family|home/.test(setupText)
        ? "This Reel turns the brief's family context into a small wellness rhythm rather than staged family content."
        : "This Reel uses the weekly brief's weekend rhythm to keep Saturday light and realistic.",
      brief_context_tags: contextTags,
      why_today:
        "The weekend should show regular life and family rhythm without staging family content.",
      growth_job:
        "Make recovery feel like part of life, not a separate wellness performance.",
      save_share_reason:
        "A realistic recovery reminder viewers can share with someone who overcomplicates rest days.",
      content_pillar: "recovery",
      scene_titles: ["Home rhythm", "One recovery habit", "Keep it real"] as [
        string,
        string,
        string,
      ],
      script:
        "Saturday is for keeping the body moving without making it a project: a walk, a stretch, or ten minutes of foam rolling between normal home things.",
      voiceover_lines: [
        "Saturday recovery can happen inside regular home life.",
        "Choose a walk, a stretch, or ten minutes with the foam roller.",
        "It counts even when it is not a full production.",
      ] as [string, string, string],
      no_voiceover_version:
        "Silent Reel version: use home detail, recovery tool or walking shoes, and one quiet reset clip with timed text.",
      on_screen_text: ["Weekend recovery", "No big setup", "Keep it real"],
      caption:
        "Saturday recovery can be very normal: a walk, a stretch, a little reset between everything else happening at home.",
      cta: "What is your easiest weekend recovery habit?",
      hashtags: ["weekendrecovery", "familyroutine", "realwellness"],
    },
    {
      title: podcastFrame
        ? "Sunday planning + podcast reflection"
        : "Sunday planning for next week",
      hook: podcastFrame
        ? "A Sunday reset plus one podcast thought."
        : "Make Monday easier before Monday arrives.",
      weekly_brief_anchor: podcastFrame
        ? "podcast"
        : contextTags[0] ?? "Sunday prep",
      brief_alignment: podcastFrame
        ? "This Reel uses the brief's podcast ask as a reflective Sunday planning prompt."
        : "This Reel uses the weekly brief's planning frame to make Sunday prep useful.",
      brief_context_tags: contextTags,
      why_today:
        "Sunday closes the arc by turning the week into a practical plan for the next one.",
      growth_job:
        "Invite reflective engagement while keeping the content easy to film.",
      save_share_reason:
        "A planning checklist viewers can save before the next week starts.",
      content_pillar: "lifestyle",
      scene_titles: [
        "Open notes",
        "Pick next week's anchors",
        "One reflection",
      ] as [string, string, string],
      script: podcastFrame
        ? "Sunday planning: gym bag, meals, calendar, and one thought for the podcast question: consistency matters because real life keeps changing."
        : "Sunday planning: gym bag, meals, calendar, and one small anchor for the week ahead. Make the next restart easier.",
      voiceover_lines: podcastFrame
        ? [
          "Sunday planning is just a few simple anchors.",
          "Gym bag, meals, calendar, and one thought for the podcast.",
          "Consistency matters because real life keeps changing.",
        ] as [string, string, string]
        : [
          "Sunday planning can make Monday less dramatic.",
          "Set up the gym bag, meals, calendar, and one small anchor.",
          "The goal is to make the next restart easier.",
        ] as [string, string, string],
      no_voiceover_version:
        "Silent Reel version: film notes app or notebook, gym bag prep, and one quiet coffee or home planning shot with timed text.",
      on_screen_text: podcastFrame
        ? ["Sunday plan", "Gym bag", "Meals", "Podcast thought"]
        : ["Sunday plan", "Gym bag", "Meals", "Next week's anchor"],
      caption: podcastFrame
        ? "Sunday reset: prep the simple things and leave space for the bigger reflection. The podcast question has me thinking about consistency over intensity."
        : "Sunday reset: prep the simple things so Monday does not need a dramatic restart.",
      cta: podcastFrame
        ? "What would you ask on a wellness podcast?"
        : "What is one thing you prep before Monday?",
      hashtags: ["sundayreset", "weeklyroutine", "wellnessreflection"],
    },
  ];
  return plans[index] ?? plans[0];
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

  const format = requiredFormat(value.format);
  const durationSeconds = numberValue(value.duration_seconds);
  if (!Number.isInteger(durationSeconds) || durationSeconds <= 0) {
    throw invalidWeek("duration_seconds must be a positive integer.");
  }

  const shotTimeline = requiredTimeline(
    value.shot_timeline,
    "shot_timeline",
  );
  const voiceoverTimeline = requiredVoiceoverTimeline(
    value.voiceover_timeline,
  );
  const silentVersionTimeline = requiredTimeline(
    value.silent_version_timeline,
    "silent_version_timeline",
  );
  const onScreenTextTimeline = requiredOnScreenTextTimeline(
    value.on_screen_text_timeline,
  );
  const backupStoryDetail = requiredTimeline(
    value.backup_story_detail,
    "backup_story_detail",
  );

  const score = numberValue(value.creator_fit_score);
  if (!Number.isFinite(score) || score < 0 || score > 100) {
    throw invalidWeek("creator_fit_score must be between 0 and 100.");
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
    format,
    primary_surface: requiredString(value.primary_surface, "primary_surface"),
    duration_seconds: durationSeconds,
    title: requiredString(value.title, "title"),
    hook: requiredString(value.hook, "hook"),
    weekly_brief_anchor: requiredString(
      value.weekly_brief_anchor,
      "weekly_brief_anchor",
    ),
    brief_alignment: requiredString(
      value.brief_alignment,
      "brief_alignment",
    ),
    brief_context_tags: requiredNonEmptyStringArray(
      value.brief_context_tags,
      "brief_context_tags",
    ).slice(0, 4),
    why_today: requiredString(value.why_today, "why_today"),
    growth_job: requiredString(value.growth_job, "growth_job"),
    save_share_reason: requiredString(
      value.save_share_reason,
      "save_share_reason",
    ),
    content_pillar: requiredContentPillar(value.content_pillar),
    shootability: requiredString(value.shootability, "shootability"),
    estimated_shoot_minutes: minutes,
    energy_required: requiredString(value.energy_required, "energy_required"),
    language_mode: requiredString(value.language_mode, "language_mode"),
    scene_list: scenes,
    shot_timeline: shotTimeline,
    script: requiredString(value.script, "script"),
    voiceover_timeline: voiceoverTimeline,
    no_voiceover_version: requiredString(
      value.no_voiceover_version,
      "no_voiceover_version",
    ),
    silent_version_timeline: silentVersionTimeline,
    on_screen_text: requiredStringArray(value.on_screen_text, "on_screen_text"),
    on_screen_text_timeline: onScreenTextTimeline,
    caption: requiredString(value.caption, "caption"),
    cta: requiredString(value.cta, "cta"),
    hashtags: requiredStringArray(value.hashtags, "hashtags"),
    cover_text: requiredString(value.cover_text, "cover_text"),
    post_instructions: requiredString(
      value.post_instructions,
      "post_instructions",
    ),
    brand_event_notes: optionalCleanString(
      value.brand_event_notes,
      "brand_event_notes",
    ) ?? "",
    backup_story: requiredString(value.backup_story, "backup_story"),
    backup_story_detail: backupStoryDetail,
    backup_caption_only: requiredString(
      value.backup_caption_only,
      "backup_caption_only",
    ),
    caption_backup_detail: requiredString(
      value.caption_backup_detail,
      "caption_backup_detail",
    ),
    audio_option_notes: optionalCleanString(
      value.audio_option_notes,
      "audio_option_notes",
    ) ?? "",
    creator_fit_score: score,
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
  rejectPlaceholderContent(normalized, field);
  return normalized;
}

function requiredFormat(value: unknown): "Reel" | "Post" | "Story" {
  const normalized = requiredString(value, "format");
  if (
    normalized !== "Reel" && normalized !== "Post" && normalized !== "Story"
  ) {
    throw invalidWeek("format must be Reel, Post, or Story.");
  }
  return normalized;
}

function requiredContentPillar(value: unknown): ContentPillar {
  const pillar = normalizeContentPillar(value);
  if (!pillar) {
    throw invalidWeek(
      `content_pillar must be one of: ${CONTENT_PILLARS.join(", ")}.`,
    );
  }
  return pillar;
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
    rejectPlaceholderContent(normalized, "scene.duration");
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
    const normalized = item.trim();
    if (normalized) {
      rejectPlaceholderContent(normalized, field);
    }
    return normalized;
  }).filter((item) => item.length > 0);
}

function requiredNonEmptyStringArray(value: unknown, field: string): string[] {
  const normalized = requiredStringArray(value, field);
  if (normalized.length === 0) {
    throw invalidWeek(`${field} must contain at least one non-empty string.`);
  }
  return normalized;
}

function requiredTimestamp(value: unknown, field: string): string {
  const normalized = requiredString(value, field).replace(/\s+/g, "");
  if (!/^\d{1,2}:\d{2}-\d{1,2}:\d{2}$/.test(normalized)) {
    throw invalidWeek(`${field} must use a timestamp range like 0:00-0:03.`);
  }
  return normalized;
}

function requiredTimeline(
  value: unknown,
  field: string,
): GeneratedTimelineItem[] {
  if (!Array.isArray(value) || value.length === 0) {
    throw invalidWeek(`${field} must be a non-empty timeline array.`);
  }
  return value.map((item, index) => {
    if (!isRecord(item)) {
      throw invalidWeek(`${field}[${index}] must be an object.`);
    }
    return {
      timestamp: requiredTimestamp(
        item.timestamp,
        `${field}[${index}].timestamp`,
      ),
      detail: requiredString(item.detail, `${field}[${index}].detail`),
    };
  });
}

function requiredVoiceoverTimeline(
  value: unknown,
): GeneratedVoiceoverTimelineItem[] {
  if (!Array.isArray(value) || value.length === 0) {
    throw invalidWeek("voiceover_timeline must be a non-empty timeline array.");
  }
  return value.map((item, index) => {
    if (!isRecord(item)) {
      throw invalidWeek(`voiceover_timeline[${index}] must be an object.`);
    }
    return {
      timestamp: requiredTimestamp(
        item.timestamp,
        `voiceover_timeline[${index}].timestamp`,
      ),
      video_portion: requiredString(
        item.video_portion,
        `voiceover_timeline[${index}].video_portion`,
      ),
      voiceover: requiredString(
        item.voiceover,
        `voiceover_timeline[${index}].voiceover`,
      ),
    };
  });
}

function requiredOnScreenTextTimeline(
  value: unknown,
): GeneratedOnScreenTextTimelineItem[] {
  if (!Array.isArray(value) || value.length === 0) {
    throw invalidWeek(
      "on_screen_text_timeline must be a non-empty timeline array.",
    );
  }
  return value.map((item, index) => {
    if (!isRecord(item)) {
      throw invalidWeek(`on_screen_text_timeline[${index}] must be an object.`);
    }
    return {
      timestamp: requiredTimestamp(
        item.timestamp,
        `on_screen_text_timeline[${index}].timestamp`,
      ),
      text: requiredString(item.text, `on_screen_text_timeline[${index}].text`),
      placement: requiredString(
        item.placement,
        `on_screen_text_timeline[${index}].placement`,
      ),
    };
  });
}

function optionalCleanString(
  value: unknown,
  field: string,
): string | undefined {
  const normalized = stringValue(value)?.trim();
  if (!normalized) {
    return undefined;
  }
  rejectPlaceholderContent(normalized, field);
  return normalized;
}

function rejectPlaceholderContent(value: string, field: string): void {
  if (/\b(?:placeholder|tbd|lorem)\b/i.test(value)) {
    throw invalidWeek(`${field} contains placeholder content.`);
  }
}

function combineText(values: string[], fallback: string): string {
  const combined = uniqueStrings(values)
    .filter((value) => value.trim().length > 0)
    .join(" ");
  return combined.trim().length > 0 ? combined : fallback;
}

function uniqueStrings(values: string[]): string[] {
  const seen = new Set<string>();
  return values.flatMap((value) => {
    const normalized = value.trim();
    const key = normalized.toLowerCase();
    if (!normalized || seen.has(key)) {
      return [];
    }
    seen.add(key);
    return [normalized];
  });
}

function stripMarkdownFence(value: string): string {
  const match = value.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  return match?.[1]?.trim() ?? value;
}

function extractFirstJSONObject(value: string): string | null {
  const start = value.indexOf("{");
  if (start < 0) {
    return null;
  }

  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let index = start; index < value.length; index += 1) {
    const char = value[index];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char === "\\") {
      escaped = true;
      continue;
    }
    if (char === '"') {
      inString = !inString;
      continue;
    }
    if (inString) {
      continue;
    }
    if (char === "{") {
      depth += 1;
    } else if (char === "}") {
      depth -= 1;
      if (depth === 0) {
        return value.slice(start, index + 1);
      }
    }
  }

  return null;
}

function isRetryableGeneratedJSONError(error: unknown): boolean {
  return error instanceof GenerateWeekValidationError &&
    (error.code === "invalid_ai_json" ||
      error.code === "invalid_generated_week");
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

const generatedTimelineItemJSONSchema = {
  type: "object",
  additionalProperties: false,
  required: ["timestamp", "detail"],
  properties: {
    timestamp: { type: "string" },
    detail: { type: "string" },
  },
};

const generatedVoiceoverTimelineItemJSONSchema = {
  type: "object",
  additionalProperties: false,
  required: ["timestamp", "video_portion", "voiceover"],
  properties: {
    timestamp: { type: "string" },
    video_portion: { type: "string" },
    voiceover: { type: "string" },
  },
};

const generatedOnScreenTextTimelineItemJSONSchema = {
  type: "object",
  additionalProperties: false,
  required: ["timestamp", "text", "placement"],
  properties: {
    timestamp: { type: "string" },
    text: { type: "string" },
    placement: { type: "string" },
  },
};

const generatedCardJSONSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "scheduled_date",
    "format",
    "primary_surface",
    "duration_seconds",
    "title",
    "hook",
    "weekly_brief_anchor",
    "brief_alignment",
    "brief_context_tags",
    "why_today",
    "growth_job",
    "save_share_reason",
    "content_pillar",
    "shootability",
    "estimated_shoot_minutes",
    "energy_required",
    "language_mode",
    "scene_list",
    "shot_timeline",
    "script",
    "voiceover_timeline",
    "no_voiceover_version",
    "silent_version_timeline",
    "on_screen_text",
    "on_screen_text_timeline",
    "caption",
    "cta",
    "hashtags",
    "cover_text",
    "post_instructions",
    "brand_event_notes",
    "backup_story",
    "backup_story_detail",
    "backup_caption_only",
    "caption_backup_detail",
    "audio_option_notes",
    "creator_fit_score",
    "risk_notes",
    "assumptions",
    "source_note",
    "source_reference_ids",
  ],
  properties: {
    scheduled_date: { type: "string", format: "date" },
    format: { type: "string", enum: ["Reel", "Post", "Story"] },
    primary_surface: { type: "string" },
    duration_seconds: { type: "integer", minimum: 1 },
    title: { type: "string" },
    hook: { type: "string" },
    weekly_brief_anchor: { type: "string" },
    brief_alignment: { type: "string" },
    brief_context_tags: {
      type: "array",
      minItems: 1,
      maxItems: 4,
      items: { type: "string" },
    },
    why_today: { type: "string" },
    growth_job: { type: "string" },
    save_share_reason: { type: "string" },
    content_pillar: {
      type: "string",
      enum: [...CONTENT_PILLARS],
      description:
        "One of the four creator pillars: gym, lifestyle, eating, or recovery. Gym is one pillar, not the whole identity.",
    },
    shootability: { type: "string" },
    estimated_shoot_minutes: { type: "integer", minimum: 0 },
    energy_required: { type: "string" },
    language_mode: { type: "string" },
    scene_list: {
      type: "array",
      minItems: 1,
      items: generatedSceneJSONSchema,
    },
    shot_timeline: {
      type: "array",
      minItems: 1,
      items: generatedTimelineItemJSONSchema,
    },
    script: { type: "string" },
    voiceover_timeline: {
      type: "array",
      minItems: 1,
      items: generatedVoiceoverTimelineItemJSONSchema,
    },
    no_voiceover_version: { type: "string" },
    silent_version_timeline: {
      type: "array",
      minItems: 1,
      items: generatedTimelineItemJSONSchema,
    },
    on_screen_text: {
      type: "array",
      minItems: 1,
      items: { type: "string" },
    },
    on_screen_text_timeline: {
      type: "array",
      minItems: 1,
      items: generatedOnScreenTextTimelineItemJSONSchema,
    },
    caption: { type: "string" },
    cta: { type: "string" },
    hashtags: { type: "array", items: { type: "string" } },
    cover_text: { type: "string" },
    post_instructions: { type: "string" },
    brand_event_notes: { type: "string" },
    backup_story: { type: "string" },
    backup_story_detail: {
      type: "array",
      minItems: 1,
      items: generatedTimelineItemJSONSchema,
    },
    backup_caption_only: { type: "string" },
    caption_backup_detail: { type: "string" },
    audio_option_notes: { type: "string" },
    creator_fit_score: { type: "number", minimum: 0, maximum: 100 },
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

export const generatedDayJSONSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "strategy_note",
    "warnings",
    "assumptions",
    "daily_card",
    "idea_bank",
    "source_summary",
  ],
  properties: {
    strategy_note: { type: "string" },
    warnings: { type: "array", items: { type: "string" } },
    assumptions: { type: "array", items: { type: "string" } },
    daily_card: generatedCardJSONSchema,
    idea_bank: { type: "array", items: generatedIdeaJSONSchema },
    source_summary: { type: "string" },
  },
};
