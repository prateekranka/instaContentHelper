export type GenerateWeekMode = "generate_draft" | "regenerate_draft";
export type GenerateWeekResponseMode = "sync" | "async";

export type RegenerateDayRequest = {
  action: "regenerate_day";
  creator_id: string;
  weekly_plan_id: string;
  scheduled_date: string;
  preserve_manual_edits: boolean;
  mock: boolean;
  response_mode: GenerateWeekResponseMode;
  input_overrides?: Record<string, unknown>;
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
};

const DEFAULT_AI_REQUEST_TIMEOUT_MS = 150_000;

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
      "Use only the provided creator profile, weekly setup, confirmed references and extractions, brand obligations, key moments, archive feedback, and idea bank.",
      "Apply the generation guidance silently; resolve source conflicts by precedence without asking the admin.",
      "Generate exactly seven daily cards for the requested week.",
      "Prioritize shootability, calm practical tone, and creator safety over trend chasing.",
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
  const generationGuidance = buildGenerationGuidance(
    input,
    scheduledDate,
    dayIndex,
  );
  const targetWeekday = weekdayName(scheduledDate);
  return {
    system: [
      "You generate Creator Content OS daily content as strict JSON.",
      "Use only the provided creator profile, weekly setup, confirmed references and extractions, brand obligations, key moments, archive feedback, and idea bank.",
      "Apply the generation guidance silently; resolve source conflicts by precedence without asking the admin.",
      "Generate exactly one daily card for the requested scheduled_date.",
      "All day-of-week language must match the requested scheduled_date.",
      "Prioritize shootability, calm practical tone, and creator safety over trend chasing.",
      "Avoid all no-go topics and surface assumptions or risks instead of inventing facts.",
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
        week_start_date: input.week_start_date,
        day_intent: generationGuidance.day_specific_intent,
      },
      required_contract: generatedDayOutputContract(scheduledDate),
      generation_guidance: generationGuidance,
      input,
    }),
  };
}

function buildGenerationGuidance(
  input: GenerationInputSnapshot,
  scheduledDate?: string,
  dayIndex?: number,
): Record<string, unknown> {
  const dayIntent = typeof scheduledDate === "string"
    ? dayIntentForScheduledDate(input, scheduledDate, dayIndex)
    : undefined;

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
    weekly_diversity: {
      avoid_repetition:
        "Do not repeat the same walk, gentle recovery, or low-effort card across the week unless the weekly brief explicitly asks for that repetition.",
      preferred_arc: weekDates(input.week_start_date).map((date, index) =>
        `${weekdayName(date)} ${date}: ${
          dayIntentForScheduledDate(input, date, index)
        }`
      ),
    },
    instagram_defaults: [
      "Plan each day as Instagram-first content. Default to format Reel and primary_surface Instagram Reels for growth unless the weekly brief explicitly requests Post or Story.",
      "State the planned format as Reel, Post, or Story. For Reels, include duration_seconds and timestamped production guidance for shots, voiceover, on-screen text, and the silent version.",
      "Make every scene and timeline item specific enough to shoot: location/detail, action, camera framing, useful fitness cue, and the exact video portion the voiceover belongs to.",
      "Scene titles must stay short, but shot_timeline.detail must be production-ready: include where Mamta can shoot it, what the frame contains, the movement/action, and why that location fits the creator context.",
      "When context includes Bombay/Mumbai, gym return, home rhythm, society garden, or family routine, give context-specific capture examples such as home, society garden, building gym, or nearby gym; do not leave scenes as generic labels.",
      "Scripts must be long enough to record as usable voiceover, usually 45-90 words for a short Reel, with a clear opening, practical middle, and grounded close.",
      "Captions must be longer than a stub, usually 80-140 words, with the creator's context, a useful takeaway, and one natural CTA.",
      "Do not include vague support/supports language. Use what_to_capture style guidance in shot_timeline and exact text in on_screen_text_timeline.",
      "When the weekly brief says Bombay, Mumbai, India, travel, gym return, or podcast, make that current context visible where relevant and let it outrank stale stored setup or archive context.",
      "Avoid weight-loss, transformation, punishment, extreme intensity, medical, or guaranteed outcome claims.",
      "Do not output placeholder text, TBD, lorem ipsum, generic assumptions, or fabricated details. If needed details are absent, surface the limitation in risk_notes or assumptions using the provided facts only.",
    ],
    growth_references: mamtaFitnessGrowthReferences(),
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
  const weekday = weekdayName(scheduledDate).toLowerCase();
  const fallbackDay = typeof dayIndex === "number"
    ? `Day ${dayIndex + 1}`
    : "This day";

  const weekdayIntents: Record<string, string> = {
    monday:
      "Monday: upper-body or re-entry routine, kept low-pressure and shootable; if the brief mentions returning after travel, make this the calm restart.",
    tuesday:
      "Tuesday: lower-body strength or legs with one practical form cue; keep it useful without turning it into a full workout tutorial.",
    wednesday:
      "Wednesday: floor work, abs, mobility, or HYROX-simulation only when the weekly brief supports that intensity; otherwise make it a gentle midweek reset.",
    thursday:
      "Thursday: compound or full-body strength with one beginner-friendly cue and easy camera setup.",
    friday:
      "Friday: shoulders/back, posture, pulling strength, or a short conditioning cue; keep the effort controlled and creator-safe.",
    saturday:
      "Saturday: running, abs, hydration, friends, errands, or relaxed movement; make it feel like weekend life rather than a staged workout.",
    sunday:
      "Sunday: recovery, family, food, friends, errands, reflection, or weekly reset; do not force Monday gym-start language onto this day.",
  };

  return `${
    weekdayIntents[weekday] ??
      `${fallbackDay}: keep this day distinct and tied to its actual date.`
  }${contextLine}${injuryLine}${podcastLine}`;
}

function mamtaFitnessGrowthReferences(): Record<string, unknown>[] {
  return [
    {
      id: "mamta-age-myth-reversal",
      name: "Age Myth Reversal",
      use_for:
        "Belief-shift Reels that challenge the idea women should slow down after 60.",
      hook_patterns: [
        "They told women my age to slow down. I started lifting.",
        "At 62, this is what I refuse to give up.",
        "Fitness after 60 is not about looking young.",
      ],
      production_rule:
        "Open with real movement proof before advice: lifting, shoes, gym entry, HYROX/race proof, or a sweaty post-set reset.",
      mamta_fit:
        "Highest fit when the weekly brief includes strength, race proof, confidence, gym return, or discipline.",
    },
    {
      id: "mamta-real-life-contradiction-hook",
      name: "Real-Life Contradiction Hook",
      use_for:
        "Relatable Reels about eating out, travel, family rhythm, missed workouts, and staying consistent without guilt.",
      hook_patterns: [
        "I eat out. I drink sometimes. I still stay fit at 62.",
        "I missed the perfect routine, so I did this instead.",
        "This is how I restart after travel without guilt.",
      ],
      production_rule:
        "Show one normal-life clip, one fitness/recovery clip, and one practical consistency rule.",
      mamta_fit:
        "High fit for Bombay routine, travel return, family plans, brand/collab weeks, and low-pressure gym weeks.",
    },
    {
      id: "mamta-proof-before-advice",
      name: "Proof Before Advice",
      use_for:
        "Reels where the viewer sees Mamta doing the work before hearing the lesson.",
      hook_patterns: [
        "One thing I learned after showing up for years...",
        "This is why you do the boring work.",
        "Before I give advice, let me show you the part nobody sees.",
      ],
      production_rule:
        "The first 0:00-0:03 must be a visual action, not a talking-head explanation.",
      mamta_fit:
        "High fit for gym, mobility, HYROX, run, walk, routine reset, and recovery cards.",
    },
    {
      id: "mamta-saveable-practical-cue",
      name: "Saveable Practical Cue",
      use_for:
        "Utility Reels designed for saves/shares with exactly one movement cue or recovery action.",
      hook_patterns: [
        "Save this before your next lower-body day.",
        "One warm-up I do before lifting.",
        "If your back feels stiff, try this first.",
      ],
      production_rule:
        "Keep the Reel to one cue. Include exact shot timing, on-screen cue text, and a save/share CTA.",
      mamta_fit:
        "High fit for strength, mobility, stiffness relief, recovery, and gym-return cards.",
    },
    {
      id: "mamta-hyrox-hybrid-proof",
      name: "HYROX / Hybrid Proof",
      use_for:
        "Authority-building Reels that connect HYROX/running/strength proof back to everyday routine.",
      hook_patterns: [
        "HYROX taught me this, but it applies to regular gym days.",
        "You do not train for events. You train for the life you want.",
        "The race is over. The routine is the real win.",
      ],
      production_rule:
        "Use HYROX only when the weekly brief supports it; do not override a current non-race week with stale race context.",
      mamta_fit:
        "Conditional fit for race reflection, hybrid conditioning, event proof, and confidence arcs.",
    },
    {
      id: "mamta-instagram-reels-default",
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
      mamta_fit:
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
          "non-empty array of { timestamp, detail } using timestamp ranges like 0:00-0:03; detail must say exactly what to shoot with context-specific examples, such as Mamta's home, society garden, building gym, or gym when supported by the brief.",
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
    content_pillar: "routine",
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
    on_screen_text: ["Back in routine", "One steady cue", "Save this"],
    on_screen_text_timeline: [{
      timestamp: "0:00-0:03",
      text: "Back in routine",
      placement: "Upper third over motion",
    }],
    caption:
      "An 80-140 word caption with context, practical takeaway, and natural CTA.",
    cta: "Save this for your next low-pressure gym day.",
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
      "Use calm low-volume audio only if it does not fight the voiceover.",
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
      "The Reel turns the weekly brief's Bombay gym-return context into a low-pressure Monday reset.",
    brief_context_tags: ["Bombay", "back to gym", "regular routine"],
    why_today: "A practical start to the week that is easy to shoot.",
    growth_job: "Build consistency with useful, low-drama fitness content.",
    save_share_reason:
      "Saveable restart cue for anyone easing back into training after travel or a busy week.",
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
    audio_option_notes: "Use calm audio only if it fits.",
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

export async function callAIProvidersForSplitWeek(
  input: GenerationInputSnapshot,
  providers: AIProviderConfig[],
  invokeProvider: (
    input: GenerationInputSnapshot,
    provider: AIProviderConfig,
    scheduledDate: string,
    dayIndex: number,
  ) => Promise<GeneratedDayOutput> = callAIProviderForDay,
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
      "A calm, shootable recovery week with one practical daily content card.",
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
  ) => Promise<GeneratedDayOutput> = callAIProviderForDay,
): Promise<GeneratedDayOutput> {
  let lastError: unknown = new Error("ai_provider_request_failed");
  for (const provider of providers) {
    for (let attempt = 0; attempt < 2; attempt += 1) {
      try {
        return await invokeProvider(input, provider, scheduledDate, dayIndex);
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

export async function callAIProviderForDay(
  input: GenerationInputSnapshot,
  provider: AIProviderConfig,
  scheduledDate: string,
  dayIndex: number,
): Promise<GeneratedDayOutput> {
  if (provider.provider === "deepseek") {
    return await callDeepSeekDayChatCompletions(
      input,
      provider.model,
      provider.apiKey,
      scheduledDate,
      dayIndex,
      provider.baseURL,
    );
  }
  return await callOpenAIDayResponses(
    input,
    provider.model,
    provider.apiKey,
    scheduledDate,
    dayIndex,
  );
}

export async function callDeepSeekChatCompletions(
  input: GenerationInputSnapshot,
  model: string,
  apiKey: string,
  baseURL = "https://api.deepseek.com",
): Promise<GeneratedWeekOutput> {
  const response = await fetchWithAIRequestTimeout(
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

async function callDeepSeekDayChatCompletions(
  input: GenerationInputSnapshot,
  model: string,
  apiKey: string,
  scheduledDate: string,
  dayIndex: number,
  baseURL = "https://api.deepseek.com",
): Promise<GeneratedDayOutput> {
  const response = await fetchWithAIRequestTimeout(
    `${baseURL.replace(/\/+$/, "")}/chat/completions`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(
        buildDeepSeekDayChatRequest(input, model, scheduledDate, dayIndex),
      ),
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

  return parseGeneratedDayJSON(rawJSON, scheduledDate, dayIndex);
}

export async function callOpenAIResponses(
  input: GenerationInputSnapshot,
  model: string,
  apiKey: string,
): Promise<GeneratedWeekOutput> {
  const response = await fetchWithAIRequestTimeout(
    "https://api.openai.com/v1/responses",
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(buildOpenAIResponsesRequest(input, model)),
    },
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

  return parseGeneratedWeekJSON(rawJSON, input.week_start_date);
}

async function callOpenAIDayResponses(
  input: GenerationInputSnapshot,
  model: string,
  apiKey: string,
  scheduledDate: string,
  dayIndex: number,
): Promise<GeneratedDayOutput> {
  const response = await fetchWithAIRequestTimeout(
    "https://api.openai.com/v1/responses",
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(
        buildOpenAIDayResponsesRequest(input, model, scheduledDate, dayIndex),
      ),
    },
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

  return parseGeneratedDayJSON(rawJSON, scheduledDate, dayIndex);
}

async function fetchWithAIRequestTimeout(
  input: string,
  init: RequestInit,
): Promise<Response> {
  const timeoutMS = aiRequestTimeoutMS();
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

function aiRequestTimeoutMS(): number {
  const configured = Deno.env.get("MCO_AI_REQUEST_TIMEOUT_MS")?.trim();
  if (!configured) {
    return DEFAULT_AI_REQUEST_TIMEOUT_MS;
  }

  const parsed = Number(configured);
  if (!Number.isFinite(parsed) || parsed < 5_000) {
    return DEFAULT_AI_REQUEST_TIMEOUT_MS;
  }
  return Math.min(parsed, 180_000);
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
        }: open with the clearest context detail in Mamta's home, society garden, building gym, or gym, using a steady vertical frame that explains where the day is happening.`,
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
        }: finish with a calm close-up, cover-safe framing, and no extreme claim.`,
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
      "Use calm audio if available. Keep cover text large and readable.",
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
      "Use a confirmed calm audio option if it fits; otherwise post without audio dependence.",
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
        `Start the week by showing the return to regular life and a low-pressure ${gymPhrase}.`,
      growth_job:
        "Rebuild trust around consistency without making the reset feel intense.",
      save_share_reason:
        "Followers can save it as a simple first-day-back gym reset after travel.",
      content_pillar: "routine",
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
        "Silent Reel version: show shoes or gym bag, one light movement, and a calm post-workout clip with timed text overlays.",
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
        "A saveable form cue viewers can try in their next lower-body session.",
      content_pillar: "training",
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
      content_pillar: "mobility",
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
      title: "Upper-body strength: one useful pull",
      hook: "One pulling cue that makes the set cleaner.",
      weekly_brief_anchor: gymFrame
        ? "back to the gym routine"
        : "upper-body routine",
      brief_alignment:
        "This Reel keeps the gym week moving with a distinct upper-body cue from the brief's routine arc.",
      brief_context_tags: contextTags,
      why_today:
        "A beginner-friendly upper-body cue gives the week a clear training progression.",
      growth_job:
        "Offer strength content that feels doable and technically useful.",
      save_share_reason:
        "A simple upper-body cue viewers can save before their next pull day.",
      content_pillar: "training",
      scene_titles: [
        "Pick the movement",
        "Pull with control",
        "Posture note",
      ] as [string, string, string],
      script:
        "Upper-body day: choose one pulling movement and keep it clean. Pull toward the hip, pause for a second, and avoid rushing the set.",
      voiceover_lines: [
        "For upper body today, keep one pulling movement clean.",
        "Pull toward the hip and pause for a second before you reset.",
        "That small pause can make the set more useful.",
      ] as [string, string, string],
      no_voiceover_version:
        "Silent Reel version: film the dumbbell or cable setup, one controlled rep, and a timed text cue over the pause.",
      on_screen_text: [
        "Upper-body day",
        "Pull to the hip",
        "Pause, then reset",
      ],
      caption:
        "One upper-body reminder I like: don't rush the pull. A tiny pause can make the whole set more useful.",
      cta: "Send this to someone restarting strength training.",
      hashtags: ["upperbodyworkout", "strengthcue", "fitafter40"],
    },
    {
      title: "Short core finisher, not a punishment",
      hook: "Core work can be short without becoming punishment.",
      weekly_brief_anchor: gymFrame
        ? "Friday core and conditioning"
        : "busy-day routine",
      brief_alignment:
        "This Reel uses the brief's short, doable Friday conditioning idea without pushing extreme intensity.",
      brief_context_tags: contextTags,
      why_today:
        "Friday needs a contained effort that fits a busy routine and avoids extreme framing.",
      growth_job: "Separate core training from guilt-based fitness language.",
      save_share_reason:
        "A repeatable core framing viewers can save for busy gym days.",
      content_pillar: "training",
      scene_titles: [
        "Set a short timer",
        "One core move",
        "Stop while form is good",
      ] as [string, string, string],
      script:
        "Core today, but short and controlled. Pick one move, set a small timer, and stop before your form starts falling apart.",
      voiceover_lines: [
        "Core today, but keep it short and controlled.",
        "Pick one move and stop before your form starts falling apart.",
        "Useful beats punishing every time.",
      ] as [string, string, string],
      no_voiceover_version:
        "Silent Reel version: show timer, one clean core movement, and a final water/rest clip with timed text.",
      on_screen_text: ["Short core", "Good form only", "Stop before sloppy"],
      caption:
        "Core does not have to mean punishment. Keep it short, controlled, and useful enough to repeat next week.",
      cta: "Save this for a busy gym day.",
      hashtags: ["coreworkout", "busyroutine", "sustainablefitness"],
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
      content_pillar: "family",
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
      content_pillar: "reflection",
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
    content_pillar: requiredString(value.content_pillar, "content_pillar"),
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
    content_pillar: { type: "string" },
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
