import {
  containsInstructorEnding,
  containsInstructorPhrasing,
  countExplicitSaveCTAs,
} from "./generation-quality.ts";
import type {
  AIGenerationValidationFailureDetail,
  GenerateDayRequest,
  GeneratedDailyCard,
  GeneratedDayOutput,
  GeneratedIdea,
  GeneratedOnScreenTextTimelineItem,
  GeneratedScene,
  GeneratedTimelineItem,
  GeneratedVoiceoverTimelineItem,
  GeneratedWeekOutput,
  GenerateWeekRequest,
  RegenerateDayRequest,
} from "./generation.ts";

export function isRecord(value: unknown): value is Record<string, unknown> {
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
export type GenerateWeekValidationCode =
  | "invalid_generation_payload"
  | "day_brief_required"
  | "invalid_ai_json"
  | "invalid_generated_week";

export class GenerateWeekValidationError extends Error {
  constructor(readonly code: GenerateWeekValidationCode, message: string) {
    super(message);
    this.name = "GenerateWeekValidationError";
  }
}

function invalidWeek(message: string): GenerateWeekValidationError {
  return new GenerateWeekValidationError("invalid_generated_week", message);
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

const MAX_DAY_GUIDANCE_LENGTH = 2000;
export const MAX_DAY_BRIEF_LENGTH = 2000;

/**
 * Monday (UTC) of the week containing the supplied ISO date. Weekly plan
 * containers are Monday-anchored, matching the day-role mix used by the
 * day prompt builders.
 */
export function weekStartDateForDate(dateStr: string): string {
  const [year, month, day] = dateStr.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  const weekday = date.getUTCDay(); // 0 = Sunday ... 6 = Saturday
  const daysSinceMonday = (weekday + 6) % 7;
  date.setUTCDate(date.getUTCDate() - daysSinceMonday);
  return date.toISOString().slice(0, 10);
}

export function normalizeGenerateDayRequest(body: unknown): GenerateDayRequest {
  if (!isRecord(body) || body.action !== "generate_day") {
    throw new GenerateWeekValidationError(
      "invalid_generation_payload",
      "action must be generate_day.",
    );
  }

  const creatorID = stringValue(body.creator_id);
  const scheduledDate = stringValue(body.scheduled_date);
  const responseMode = stringValue(body.response_mode) ?? "sync";
  const rawBrief = stringValue(body.day_brief)?.trim() ?? "";
  const dayBrief = rawBrief.slice(0, MAX_DAY_BRIEF_LENGTH);

  if (!isUUID(creatorID) || !isDateString(scheduledDate)) {
    throw new GenerateWeekValidationError(
      "invalid_generation_payload",
      "creator_id and scheduled_date are required.",
    );
  }
  if (dayBrief.length === 0) {
    throw new GenerateWeekValidationError(
      "day_brief_required",
      "day_brief must be a non-empty string.",
    );
  }
  if (responseMode !== "sync" && responseMode !== "async") {
    throw new GenerateWeekValidationError(
      "invalid_generation_payload",
      "response_mode must be sync or async.",
    );
  }

  return {
    action: "generate_day",
    creator_id: creatorID,
    scheduled_date: scheduledDate,
    day_brief: dayBrief,
    mock: body.mock === true,
    response_mode: responseMode,
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
export function validationFailureDetail(
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

export function validationFailureStage(
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

export function validationFailureRule(message: string): string {
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

export function validationFailurePath(message: string): string | null {
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
export function parseGeneratedWeekJSON(
  rawJSON: string,
  weekStartDate: string,
): GeneratedWeekOutput {
  const parsed = parseJSONResponse(rawJSON);
  return validateGeneratedWeek(parsed, weekStartDate);
}

export function parseGeneratedDayJSON(
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

export function weekdayName(dateString: string): string {
  const date = new Date(`${dateString}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) {
    return "day";
  }
  return new Intl.DateTimeFormat("en-US", {
    weekday: "long",
    timeZone: "UTC",
  }).format(date);
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

export function combineText(values: string[], fallback: string): string {
  const combined = uniqueStrings(values)
    .filter((value) => value.trim().length > 0)
    .join(" ");
  return combined.trim().length > 0 ? combined : fallback;
}

export function uniqueStrings(values: string[]): string[] {
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

export function isRetryableGeneratedJSONError(error: unknown): boolean {
  return error instanceof GenerateWeekValidationError &&
    (error.code === "invalid_ai_json" ||
      error.code === "invalid_generated_week");
}

export function optionalSceneList(
  value: unknown,
): GeneratedScene[] | undefined {
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

export function storedBackupLine(value: unknown): string | undefined {
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
