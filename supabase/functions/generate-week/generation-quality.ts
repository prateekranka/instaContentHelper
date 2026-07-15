import type {
  GeneratedDailyCard,
  GeneratedDayOutput,
  GeneratedWeekOutput,
  GenerationInputSnapshot,
} from "./generation.ts";

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

export function scoreGeneratedWeekOutputQuality(
  input: GenerationInputSnapshot,
  output: GeneratedWeekOutput,
): AIOutputQualityMetrics {
  return scoreGeneratedCardsQuality(input, output.daily_cards);
}

export function scoreGeneratedDayOutputQuality(
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
