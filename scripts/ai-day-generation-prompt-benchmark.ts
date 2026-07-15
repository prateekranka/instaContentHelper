import {
  buildDeepSeekDayChatRequest,
  type GeneratedDailyCard,
  type GeneratedDayOutput,
  type GenerationInputSnapshot,
  validateGeneratedDayOutput,
} from "../supabase/functions/generate-week/generation.ts";

type PromptVariant = {
  name: string;
  changedPromptFactors: string[];
  contextLevel: "full" | "focused" | "minimal";
  contractLevel: "current" | "typed" | "template" | "compact";
  growthReferences: "full" | "compact" | "none";
  includeExample: boolean;
  includeIdeaBank: boolean;
  focus:
    | "baseline"
    | "schema"
    | "speed"
    | "brief_proof"
    | "shoot_detail"
    | "final";
};

type IterationMetric = {
  iteration: number;
  variant_name: string;
  scheduled_date: string;
  day_index: number;
  day_intent: string;
  provider: "glm_proxy";
  model: string;
  prompt_chars: number;
  response_chars: number;
  duration_ms: number;
  timed_out: boolean;
  validation_passed: boolean;
  quality_score: number;
  failure_code: string;
  changed_prompt_factors: string[];
  notes: string;
};

type RunResult = {
  stdout: string;
  stderr: string;
  exitCode: number | null;
  timedOut: boolean;
  durationMs: number;
};

const decoder = new TextDecoder();
const homeDir = Deno.env.get("HOME")?.trim();
const opencodeBin = Deno.env.get("OPENCODE_BIN")?.trim() ||
  (homeDir ? `${homeDir}/.opencode/bin/opencode` : "opencode");
const model = Deno.env.get("OPENCODE_MODEL")?.trim() ||
  "opencode-go/glm-5.2";
const modelVariant = Deno.env.get("OPENCODE_VARIANT")?.trim() || "max";
const outputDir = Deno.env.get("PROMPT_BENCH_OUTPUT_DIR")?.trim() ||
  "build-logs/prompt-optimization";
const maxIterations =
  parsePositiveInt(Deno.env.get("PROMPT_BENCH_ITERATIONS")) ??
    20;
const startVariantIndex =
  parseNonNegativeInt(Deno.env.get("PROMPT_BENCH_START_VARIANT")) ??
    0;
const timeoutMs = parsePositiveInt(Deno.env.get("PROMPT_BENCH_TIMEOUT_MS")) ??
  180_000;
const disableAdaptiveFeedback =
  Deno.env.get("PROMPT_BENCH_DISABLE_ADAPTIVE_FEEDBACK") === "1";

const weekDates = [
  "2026-08-24",
  "2026-08-25",
  "2026-08-26",
  "2026-08-27",
  "2026-08-28",
  "2026-08-29",
  "2026-08-30",
];

const dayIntents = [
  "Monday: light full-body gym reset and mobility after travel.",
  "Tuesday: lower-body strength with one simple form cue.",
  "Wednesday: active recovery, walking, stretching, or easy movement.",
  "Thursday: upper-body strength with one beginner-friendly tip.",
  "Friday: short core and conditioning, controlled and doable.",
  "Saturday: slower recovery, foam rolling, a long walk, or family rhythm.",
  "Sunday: plan next week, prep gym bag, meals, schedule, and podcast reflection.",
];

const variants: PromptVariant[] = [
  {
    name: "00_current_deepseek_payload",
    changedPromptFactors: ["current production-style day payload"],
    contextLevel: "full",
    contractLevel: "current",
    growthReferences: "full",
    includeExample: true,
    includeIdeaBank: true,
    focus: "baseline",
  },
  {
    name: "01_remove_large_example",
    changedPromptFactors: [
      "remove full example card",
      "keep complete field list",
    ],
    contextLevel: "full",
    contractLevel: "typed",
    growthReferences: "full",
    includeExample: false,
    includeIdeaBank: true,
    focus: "schema",
  },
  {
    name: "02_compact_context",
    changedPromptFactors: ["summarize input snapshot", "keep typed contract"],
    contextLevel: "focused",
    contractLevel: "typed",
    growthReferences: "full",
    includeExample: false,
    includeIdeaBank: true,
    focus: "schema",
  },
  {
    name: "03_compact_growth_refs",
    changedPromptFactors: ["compress growth references", "keep focused brief"],
    contextLevel: "focused",
    contractLevel: "typed",
    growthReferences: "compact",
    includeExample: false,
    includeIdeaBank: true,
    focus: "brief_proof",
  },
  {
    name: "04_no_idea_bank",
    changedPromptFactors: ["drop idea bank", "use references only"],
    contextLevel: "focused",
    contractLevel: "typed",
    growthReferences: "compact",
    includeExample: false,
    includeIdeaBank: false,
    focus: "brief_proof",
  },
  {
    name: "05_template_output_shape",
    changedPromptFactors: ["use output template", "short field descriptions"],
    contextLevel: "focused",
    contractLevel: "compact",
    growthReferences: "compact",
    includeExample: false,
    includeIdeaBank: false,
    focus: "schema",
  },
  {
    name: "06_minimal_context_schema",
    changedPromptFactors: ["minimal context", "template contract"],
    contextLevel: "minimal",
    contractLevel: "compact",
    growthReferences: "compact",
    includeExample: false,
    includeIdeaBank: false,
    focus: "speed",
  },
  {
    name: "07_add_shoot_specificity",
    changedPromptFactors: ["restore shoot detail rubric", "keep short context"],
    contextLevel: "minimal",
    contractLevel: "compact",
    growthReferences: "compact",
    includeExample: false,
    includeIdeaBank: false,
    focus: "shoot_detail",
  },
  {
    name: "08_timeline_guardrails",
    changedPromptFactors: ["emphasize timestamp completeness", "no example"],
    contextLevel: "focused",
    contractLevel: "compact",
    growthReferences: "compact",
    includeExample: false,
    includeIdeaBank: false,
    focus: "shoot_detail",
  },
  {
    name: "09_brief_proof_first",
    changedPromptFactors: ["put weekly brief proof before schema"],
    contextLevel: "focused",
    contractLevel: "compact",
    growthReferences: "compact",
    includeExample: false,
    includeIdeaBank: false,
    focus: "brief_proof",
  },
  {
    name: "10_no_growth_refs",
    changedPromptFactors: ["remove growth refs", "test pure brief/profile"],
    contextLevel: "focused",
    contractLevel: "template",
    growthReferences: "none",
    includeExample: false,
    includeIdeaBank: false,
    focus: "speed",
  },
  {
    name: "11_compact_schema_only",
    changedPromptFactors: ["compact field list", "strict validation warnings"],
    contextLevel: "focused",
    contractLevel: "compact",
    growthReferences: "compact",
    includeExample: false,
    includeIdeaBank: false,
    focus: "schema",
  },
  {
    name: "12_reel_growth_defaults",
    changedPromptFactors: ["reels default up front", "one idea only"],
    contextLevel: "focused",
    contractLevel: "compact",
    growthReferences: "compact",
    includeExample: false,
    includeIdeaBank: false,
    focus: "brief_proof",
  },
  {
    name: "13_shoot_folio_first",
    changedPromptFactors: ["scene and shot plan before caption needs"],
    contextLevel: "focused",
    contractLevel: "compact",
    growthReferences: "compact",
    includeExample: false,
    includeIdeaBank: false,
    focus: "shoot_detail",
  },
  {
    name: "14_voiceover_timeline_first",
    changedPromptFactors: ["voiceover portions and timestamps emphasized"],
    contextLevel: "focused",
    contractLevel: "compact",
    growthReferences: "compact",
    includeExample: false,
    includeIdeaBank: false,
    focus: "shoot_detail",
  },
  {
    name: "15_safety_compact",
    changedPromptFactors: ["compact no-go rules", "avoid stale context"],
    contextLevel: "minimal",
    contractLevel: "compact",
    growthReferences: "compact",
    includeExample: false,
    includeIdeaBank: false,
    focus: "speed",
  },
  {
    name: "16_best_plus_quality_guard",
    changedPromptFactors: ["use previous winner pattern", "add quality guard"],
    contextLevel: "focused",
    contractLevel: "compact",
    growthReferences: "compact",
    includeExample: false,
    includeIdeaBank: false,
    focus: "final",
  },
  {
    name: "17_best_plus_context_guard",
    changedPromptFactors: [
      "require exact brief tags",
      "protect Bombay/gym/podcast",
    ],
    contextLevel: "focused",
    contractLevel: "compact",
    growthReferences: "compact",
    includeExample: false,
    includeIdeaBank: false,
    focus: "final",
  },
  {
    name: "18_best_plus_scene_detail",
    changedPromptFactors: [
      "tighten shoot folio detail",
      "shorten strategy text",
    ],
    contextLevel: "focused",
    contractLevel: "compact",
    growthReferences: "compact",
    includeExample: false,
    includeIdeaBank: false,
    focus: "final",
  },
  {
    name: "19_final_candidate",
    changedPromptFactors: [
      "final balanced candidate",
      "compact schema",
      "brief proof",
    ],
    contextLevel: "focused",
    contractLevel: "compact",
    growthReferences: "compact",
    includeExample: false,
    includeIdeaBank: false,
    focus: "final",
  },
];

const fixture: GenerationInputSnapshot = {
  creator_id: "dbc7452d-c2ff-4d52-976f-734fad55f86b",
  week_start_date: weekDates[0],
  creator_profile: {
    display_name: "Creator",
    positioning:
      "The creator is a grounded fitness and family creator who makes practical, low-drama content for women who want consistency without overproduction.",
    voice_rules: [
      "warm",
      "direct",
      "no hype",
      "no guilt",
      "keep captions simple",
    ],
    content_pillars: ["routine", "fitness", "family", "useful habits"],
    caption_style: "Short, clear, and human. One practical point per post.",
    no_go_topics: [
      "weight talk",
      "politics",
      "shaming",
      "medical claims",
      "extreme fitness claims",
    ],
    recurring_formats: [
      "shoe check",
      "morning routine",
      "family moment",
      "caption-only backup",
    ],
  },
  weekly_setup: {
    location: "Bombay / Mumbai",
    notes:
      "The creator is back in Bombay this week and settling into regular life again after travel. The week should feel like a calm return to routine: home, gym, food, recovery, family rhythm, and getting back into a sustainable wellness groove. She is restarting her gym routine with a practical, low-pressure week. She has also been asked about a podcast she might like to be on, so leave room for one reflective or conversational post about what she is learning and why consistency matters more than intensity.",
    routine:
      "Monday light full-body reset and mobility. Tuesday lower-body strength. Wednesday active recovery. Thursday upper-body strength. Friday core and conditioning. Saturday recovery or family rhythm. Sunday prep the next week and reflect on the podcast ask.",
    brand_collab:
      "Keep room for one possible brand/collab mention only if it fits naturally. Do not make the whole week feel sponsored.",
    avoid:
      "Avoid weight-loss framing, guilt, extreme fitness claims, politics, negativity, over-polished advice, or making the podcast feel like an announcement unless it fits naturally.",
  },
  confirmed_references: [
    {
      id: "0ef4e778-9931-4e58-b2e4-910b389f6d12",
      type: "growth_reference",
      title: "Proof before advice",
      manual_notes:
        "Start Reels with movement proof in the first 2 seconds, then explain the lesson.",
      source_url: "https://example.invalid/proof-before-advice",
      tags: ["reels", "hook", "movement"],
    },
    {
      id: "5f8441bb-3878-4a6d-a25c-f2fc15fe3d09",
      type: "growth_reference",
      title: "Saveable single cue",
      manual_notes:
        "One practical fitness cue per Reel increases save value and keeps the shoot simple.",
      source_url: "https://example.invalid/saveable-cue",
      tags: ["reels", "saves", "fitness cue"],
    },
    {
      id: "9ad60f42-cbe3-4ea8-81ad-e065e64828e5",
      type: "growth_reference",
      title: "Real-life contradiction hook",
      manual_notes:
        "Pair normal life with consistency: missed routine, family day, or travel return plus a practical reset.",
      source_url: "https://example.invalid/real-life-contradiction",
      tags: ["relatable", "routine", "travel"],
    },
  ],
  reference_extractions: [
    {
      reference_id: "0ef4e778-9931-4e58-b2e4-910b389f6d12",
      extraction:
        "0:00-0:02 should show proof or motion before the advice starts.",
    },
    {
      reference_id: "5f8441bb-3878-4a6d-a25c-f2fc15fe3d09",
      extraction:
        "Keep the idea to one movement cue, one caption takeaway, and one save CTA.",
    },
  ],
  recent_archive: [
    {
      scheduled_date: "2026-08-17",
      title: "Travel reset without guilt",
      status: "posted",
      feedback: "Worked when it felt specific and not over-produced.",
    },
    {
      scheduled_date: "2026-08-19",
      title: "Lower-body form cue",
      status: "backup",
      feedback: "Useful but too generic. Needs more exact shot direction.",
    },
  ],
  idea_bank: [
    {
      title: "Gym bag reset",
      summary:
        "Use the packed gym bag as the visual cue for getting back to routine.",
      tags: ["routine", "gym", "Bombay"],
    },
    {
      title: "Podcast reflection",
      summary: "A reflective note about consistency over intensity.",
      tags: ["podcast", "reflection"],
    },
  ],
  patterns: [
    {
      name: "Single-cue Reel",
      instruction: "One hook, one movement cue, one saveable takeaway.",
    },
  ],
  trends: [
    {
      name: "Original audio voiceover",
      instruction:
        "Use the creator's own voice when the content is reflective or instructive.",
    },
  ],
  audio_options: [
    {
      name: "Calm low-volume trending audio",
      instruction: "Use only under silent text or very short voiceover.",
    },
  ],
  brand_briefs: [],
  key_moments: [
    {
      title: "Podcast ask",
      date: "2026-08-30",
      note: "Mention only as reflection, not as an announcement.",
    },
  ],
  existing_week_cards: [],
};

await main();

async function main(): Promise<void> {
  await Deno.mkdir(outputDir, { recursive: true });
  await Deno.writeTextFile(progressPath(), "");
  await Deno.writeTextFile(outputsPath(), "");
  await Deno.writeTextFile(
    metricsPath(),
    [
      "iteration",
      "variant_name",
      "scheduled_date",
      "day_index",
      "day_intent",
      "provider",
      "model",
      "prompt_chars",
      "response_chars",
      "duration_ms",
      "timed_out",
      "validation_passed",
      "quality_score",
      "failure_code",
      "changed_prompt_factors",
      "notes",
    ].join(",") + "\n",
  );

  const metrics: IterationMetric[] = [];
  let previousMetric: IterationMetric | null = null;
  let previousOutput: GeneratedDayOutput | null = null;

  for (let iteration = 0; iteration < maxIterations; iteration += 1) {
    const variant = variants[
      Math.min(startVariantIndex + iteration, variants.length - 1)
    ];
    const dayIndex = iteration % weekDates.length;
    const scheduledDate = weekDates[dayIndex];
    const prompt = buildPrompt(
      variant,
      scheduledDate,
      dayIndex,
      disableAdaptiveFeedback ? null : previousMetric,
      disableAdaptiveFeedback ? null : previousOutput,
    );

    const startedAt = Date.now();
    const run = await runOpenCode(prompt);
    const responseText = extractOpenCodeText(run.stdout);
    const parsed = parseGeneratedJSON(responseText);
    let validationPassed = false;
    let validated: GeneratedDayOutput | null = null;
    let failureCode = "";

    if (!parsed) {
      failureCode = run.timedOut
        ? "timeout"
        : run.exitCode !== 0
        ? `opencode_exit_${run.exitCode ?? "unknown"}`
        : "no_json_object";
    } else {
      try {
        validated = validateGeneratedDayOutput(parsed, scheduledDate, dayIndex);
        validationPassed = true;
      } catch (error) {
        failureCode = shortError(error);
      }
    }

    const qualityScore = validationPassed && validated
      ? scoreQuality(validated, dayIndex)
      : 0;

    const metric: IterationMetric = {
      iteration: iteration + 1,
      variant_name: variant.name,
      scheduled_date: scheduledDate,
      day_index: dayIndex + 1,
      day_intent: dayIntents[dayIndex],
      provider: "glm_proxy",
      model,
      prompt_chars: prompt.length,
      response_chars: responseText.length,
      duration_ms: run.durationMs || (Date.now() - startedAt),
      timed_out: run.timedOut,
      validation_passed: validationPassed,
      quality_score: qualityScore,
      failure_code: failureCode,
      changed_prompt_factors: variant.changedPromptFactors,
      notes: summarizeIteration(run, validated, failureCode, qualityScore),
    };

    metrics.push(metric);
    await appendJSONLine(progressPath(), metric);
    await appendJSONLine(outputsPath(), {
      metric,
      parsed,
      validated,
      response_text: responseText,
      stderr_tail: tail(run.stderr, 1200),
    });
    await appendCSV(metricsPath(), metric);

    previousMetric = metric;
    previousOutput = validated;
  }

  await Deno.writeTextFile(summaryPath(), buildSummary(metrics));
  await Deno.writeTextFile(chartPath(), buildDurationChart(metrics));
}

function buildPrompt(
  variant: PromptVariant,
  scheduledDate: string,
  dayIndex: number,
  previousMetric: IterationMetric | null,
  previousOutput: GeneratedDayOutput | null,
): string {
  if (variant.contractLevel === "current") {
    const request = buildDeepSeekDayChatRequest(
      fixture,
      "deepseek-reasoner",
      scheduledDate,
      dayIndex,
    );
    return [
      "You are standing in for the production AI provider.",
      "Return the assistant response for this chat-completions request.",
      "Return JSON only. Do not wrap in Markdown.",
      JSON.stringify(request),
    ].join("\n\n");
  }

  const feedback = buildAdaptiveFeedback(previousMetric, previousOutput);
  const context = buildContextBlock(variant, scheduledDate, dayIndex);
  const schema = buildSchemaBlock(variant, scheduledDate);
  const quality = buildQualityBlock(variant);

  return [
    "Generate one Creator Content OS day card as JSON only.",
    "Do not use markdown, comments, prose outside JSON, nulls, placeholders, TBD, or invented facts.",
    "Use the weekly brief as highest-priority truth if it conflicts with profile, archive, or older references.",
    feedback,
    context,
    quality,
    schema,
  ].filter(Boolean).join("\n\n");
}

function buildAdaptiveFeedback(
  metric: IterationMetric | null,
  output: GeneratedDayOutput | null,
): string {
  if (!metric) {
    return "Iteration feedback: none yet. Prioritize valid JSON and specific shoot guidance.";
  }
  const advice: string[] = [
    `Previous variant ${metric.variant_name}: ${metric.duration_ms}ms, quality ${metric.quality_score}, validation ${
      metric.validation_passed ? "passed" : "failed"
    }.`,
  ];
  if (!metric.validation_passed) {
    advice.push(
      `Fix validation failure: ${metric.failure_code}. Return every required field with valid timestamp ranges like 0:00-0:03.`,
    );
  }
  if (metric.quality_score < 75) {
    advice.push(
      "Improve quality: prove the weekly brief was used, make scenes shootable, and include concrete Bombay/gym/podcast context where relevant.",
    );
  }
  if (metric.prompt_chars > 20_000) {
    advice.push(
      "Reduce prompt length by keeping context compact and avoiding repeated field descriptions.",
    );
  }
  if (output?.daily_card?.title) {
    advice.push(
      `Avoid duplicating the previous title exactly: ${output.daily_card.title}`,
    );
  }
  return `Iteration feedback:\n- ${advice.join("\n- ")}`;
}

function buildContextBlock(
  variant: PromptVariant,
  scheduledDate: string,
  dayIndex: number,
): string {
  const profile = fixture.creator_profile as Record<string, unknown>;
  const setup = fixture.weekly_setup as Record<string, unknown>;
  const lines = [
    "Context:",
    `- Creator: Creator.`,
    `- Profile: ${profile.positioning}`,
    `- Voice: ${(profile.voice_rules as string[]).join(", ")}.`,
    `- Weekly truth: ${setup.notes}`,
    `- Weekly routine: ${setup.routine}`,
    `- Avoid: ${setup.avoid}`,
    `- Target date: ${scheduledDate}.`,
    `- Day intent: ${dayIntents[dayIndex]}`,
  ];

  if (variant.contextLevel !== "minimal") {
    lines.push(
      `- Brand/collab rule: ${setup.brand_collab}`,
      "- Current anchors that should beat stale context: Bombay/Mumbai, regular life, back to gym, family rhythm, possible podcast reflection.",
    );
  }

  if (variant.contextLevel === "full") {
    lines.push(
      `- Recent archive: ${
        fixture.recent_archive.map((item) => JSON.stringify(item)).join("; ")
      }`,
      `- Patterns: ${
        fixture.patterns.map((item) => JSON.stringify(item)).join("; ")
      }`,
      `- Trends/audio: ${
        fixture.trends.concat(fixture.audio_options).map((item) =>
          JSON.stringify(item)
        ).join("; ")
      }`,
    );
  }

  if (variant.includeIdeaBank) {
    lines.push(
      `- Idea bank options: ${
        fixture.idea_bank.map((item) => JSON.stringify(item)).join("; ")
      }`,
    );
  }

  if (variant.growthReferences === "compact") {
    lines.push(
      "- Growth references: proof before advice in first 2 seconds; one saveable movement cue; real-life contradiction hook; original voiceover can work for reflective fitness.",
    );
  } else if (variant.growthReferences === "full") {
    lines.push(
      `- Growth references: ${
        fixture.confirmed_references.map((item) => JSON.stringify(item)).join(
          "; ",
        )
      }`,
      `- Reference extractions: ${
        fixture.reference_extractions.map((item) => JSON.stringify(item)).join(
          "; ",
        )
      }`,
    );
  }

  return lines.join("\n");
}

function buildQualityBlock(variant: PromptVariant): string {
  const rules = [
    "Quality rules:",
    "- Default to Instagram Reel unless the day intent strongly calls for a Story/Post.",
    "- First 0:00-0:03 must be retention-first: motion/proof before advice, not generic talking head.",
    "- The card must be specific to this week, not generic fitness advice.",
    "- Scenes must say what to shoot, where to shoot it, the action, framing, and why it fits the creator's context.",
    "- Include voiceover_timeline with video_portion for each timestamp.",
    "- Include on_screen_text_timeline and silent_version_timeline with matching timestamps.",
    "- Keep no-go topics out: weight loss, guilt, shaming, politics, medical claims, extreme intensity.",
  ];

  if (variant.focus === "brief_proof" || variant.focus === "final") {
    rules.push(
      "- weekly_brief_anchor must name a concrete brief fact: Bombay/Mumbai, back to gym, family rhythm, or podcast reflection.",
      "- brief_context_tags must include exact short phrases from the brief.",
    );
  }

  if (variant.focus === "shoot_detail" || variant.focus === "final") {
    rules.push(
      "- shot_timeline must be production-ready enough that the creator can shoot without asking follow-up questions.",
      "- Include 3-5 timestamped shots, not abstract scene labels.",
    );
  }

  if (variant.focus === "speed") {
    rules.push(
      "- Be concise. Do not over-explain strategy. Spend tokens on the daily_card fields.",
    );
  }

  return rules.join("\n");
}

function buildSchemaBlock(
  variant: PromptVariant,
  scheduledDate: string,
): string {
  const fields = [
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
  ];

  if (variant.contractLevel === "compact") {
    return [
      "Return this JSON object. Copy the exact key structure. Replace sample values with specific content. Fields shown as arrays must remain arrays.",
      `{"strategy_note":"...","warnings":[],"assumptions":[],"daily_card":{${
        fields.map((field) =>
          `"${field}":${compactValueHint(field, scheduledDate)}`
        ).join(",")
      }},"idea_bank":[],"source_summary":"..."}`,
      "Arrays must have the right object shape. Timestamps must be ranges like 0:00-0:03. source_reference_ids can be [].",
    ].join("\n");
  }

  const block = [
    "Return JSON with top-level keys: strategy_note, warnings, assumptions, daily_card, idea_bank, source_summary.",
    "Set top-level idea_bank to [] for this benchmark; do not create idea bank items.",
    `daily_card.scheduled_date must be "${scheduledDate}".`,
    `daily_card required fields: ${fields.join(", ")}.`,
    "scene_list items: {number positive integer, title, duration like '3 sec', symbol}.",
    "shot_timeline, silent_version_timeline, backup_story_detail items: {timestamp, detail}.",
    "voiceover_timeline items: {timestamp, video_portion, voiceover}.",
    "on_screen_text_timeline items: {timestamp, text, placement}.",
    "format must be Reel, Post, or Story. duration_seconds must be positive integer. creator_fit_score 0-100.",
  ];

  if (variant.contractLevel === "template") {
    block.push(
      "Use 3-5 shot_timeline items, 3-5 voiceover_timeline items, 3-5 on_screen_text_timeline items, and 2 backup_story_detail items.",
    );
  }

  if (variant.includeExample) {
    block.push(
      'Example title style: "Simple gym reset after travel". Do not copy it.',
    );
  }

  return block.join("\n");
}

function compactValueHint(field: string, scheduledDate: string): string {
  switch (field) {
    case "scheduled_date":
      return JSON.stringify(scheduledDate);
    case "format":
      return '"Reel"';
    case "primary_surface":
      return '"Instagram Reels"';
    case "duration_seconds":
      return "24";
    case "estimated_shoot_minutes":
      return "12";
    case "creator_fit_score":
      return "88";
    case "brief_context_tags":
      return '["Bombay","back to gym","weekly routine"]';
    case "on_screen_text":
      return '["Back in Bombay","One steady cue","Save this"]';
    case "hashtags":
      return '["fitnessover60","gymroutine","consistency"]';
    case "risk_notes":
      return "[]";
    case "assumptions":
      return '["No extra shoot support available."]';
    case "source_reference_ids":
      return '["0ef4e778-9931-4e58-b2e4-910b389f6d12"]';
    case "scene_list":
      return '[{"number":1,"title":"Proof-first opening","duration":"3 sec","symbol":"dumbbell"}]';
    case "shot_timeline":
    case "silent_version_timeline":
    case "backup_story_detail":
      return '[{"timestamp":"0:00-0:03","detail":"Specific shot direction with location, action, framing, and why it fits this week."}]';
    case "voiceover_timeline":
      return '[{"timestamp":"0:00-0:03","video_portion":"The exact clip this line belongs to","voiceover":"A specific voiceover line for this portion of the Reel."}]';
    case "on_screen_text_timeline":
      return '[{"timestamp":"0:00-0:03","text":"Back in Bombay","placement":"Upper third over motion"}]';
    case "title":
      return '"Specific daily title"';
    case "hook":
      return '"A retention-first hook tied to the first 2 seconds of video."';
    case "weekly_brief_anchor":
      return '"A concrete weekly brief fact such as Bombay, back to gym, family rhythm, or podcast reflection."';
    case "brief_alignment":
      return '"One sentence explaining how this day uses that weekly brief fact."';
    case "why_today":
      return '"Why this idea fits the selected day of the week."';
    case "growth_job":
      return '"The Instagram growth job this Reel performs."';
    case "save_share_reason":
      return '"Why a viewer would save or share this practical cue."';
    case "content_pillar":
      return '"routine"';
    case "shootability":
      return '"easy"';
    case "energy_required":
      return '"medium"';
    case "language_mode":
      return '"English with light Hinglish if natural"';
    case "script":
      return '"A 45-90 word voiceover script with opening, practical middle, and grounded close."';
    case "no_voiceover_version":
      return '"How to edit the Reel if there is no voiceover, using the same clips and timed text."';
    case "caption":
      return '"An 80-140 word caption with context, practical takeaway, and natural CTA."';
    case "cta":
      return '"Save this for your next low-pressure gym day."';
    case "cover_text":
      return '"Simple gym reset"';
    case "post_instructions":
      return '"Cover text large and readable; keep cuts simple and original audio low."';
    case "brand_event_notes":
      return '""';
    case "backup_story":
      return '"A clickable Story backup with one clip, one text sticker, and one reply prompt."';
    case "backup_caption_only":
      return '"Caption-only backup summary for days when no video is usable."';
    case "caption_backup_detail":
      return '"If no video is usable, post a short caption about the same day-specific cue and ask a question."';
    case "audio_option_notes":
      return '"Use calm low-volume audio only if it does not fight the voiceover."';
    case "source_note":
      return '"Used weekly brief and confirmed growth references."';
    default:
      return '"Specific non-placeholder text."';
  }
}

async function runOpenCode(prompt: string): Promise<RunResult> {
  const started = performance.now();
  let child: Deno.ChildProcess | null = null;
  let timedOut = false;
  let timeoutId: ReturnType<typeof setTimeout> | undefined;

  try {
    const command = new Deno.Command(opencodeBin, {
      args: [
        "run",
        "--model",
        model,
        "--variant",
        modelVariant,
        "--format",
        "json",
        "--pure",
        "--dir",
        Deno.cwd(),
        prompt,
      ],
      stdout: "piped",
      stderr: "piped",
    });
    child = command.spawn();
    timeoutId = setTimeout(() => {
      timedOut = true;
      try {
        child?.kill("SIGTERM");
      } catch {
        // The process may already have exited.
      }
    }, timeoutMs);
    const output = await child.output();
    return {
      stdout: decoder.decode(output.stdout),
      stderr: decoder.decode(output.stderr),
      exitCode: output.code,
      timedOut,
      durationMs: Math.round(performance.now() - started),
    };
  } catch (error) {
    return {
      stdout: "",
      stderr: shortError(error),
      exitCode: null,
      timedOut,
      durationMs: Math.round(performance.now() - started),
    };
  } finally {
    if (timeoutId !== undefined) {
      clearTimeout(timeoutId);
    }
  }
}

function extractOpenCodeText(stdout: string): string {
  const chunks: string[] = [];
  for (const line of stdout.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed) {
      continue;
    }
    try {
      const event = JSON.parse(trimmed);
      collectText(event, chunks);
    } catch {
      chunks.push(trimmed);
    }
  }
  return chunks.join("\n").trim();
}

function collectText(value: unknown, chunks: string[]): void {
  if (!value || typeof value !== "object") {
    return;
  }
  const record = value as Record<string, unknown>;
  const type = typeof record.type === "string" ? record.type : "";
  if (
    typeof record.text === "string" &&
    (type === "text" || type.includes("text") || type === "part")
  ) {
    chunks.push(record.text);
  }
  if (isRecord(record.part)) {
    const part = record.part as Record<string, unknown>;
    if (typeof part.text === "string") {
      chunks.push(part.text);
    }
  }
  for (const nested of Object.values(record)) {
    if (nested && typeof nested === "object") {
      collectText(nested, chunks);
    }
  }
}

function parseGeneratedJSON(text: string): unknown | null {
  const stripped = stripFence(text.trim());
  const jsonText = extractFirstJSONObject(stripped);
  if (!jsonText) {
    return null;
  }
  try {
    return JSON.parse(jsonText);
  } catch {
    return null;
  }
}

function stripFence(value: string): string {
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
      escaped = inString;
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

function scoreQuality(output: GeneratedDayOutput, dayIndex: number): number {
  const card = output.daily_card;
  const text = JSON.stringify(output).toLowerCase();
  let score = 0;

  score += hasAny(text, ["bombay", "mumbai"]) ? 8 : 0;
  score += hasAny(text, ["gym", "strength", "mobility", "conditioning"])
    ? 8
    : 0;
  score += hasAny(text, ["podcast", "reflection"]) && dayIndex >= 5 ? 6 : 0;
  score += card.format === "Reel" ? 5 : 0;
  score += card.hook.length >= 35 && card.hook.length <= 140 ? 8 : 3;
  score += card.weekly_brief_anchor.length >= 18 ? 8 : 0;
  score += card.brief_context_tags.length >= 2 ? 6 : 0;
  score += card.shot_timeline.length >= 3 ? 10 : 4;
  score += avgTextLength(card.shot_timeline.map((item) => item.detail)) >= 70
    ? 10
    : 4;
  score += card.voiceover_timeline.length >= 3 ? 8 : 3;
  score +=
    avgTextLength(card.voiceover_timeline.map((item) => item.voiceover)) >=
        20
      ? 7
      : 3;
  score += card.on_screen_text_timeline.length >= 3 ? 6 : 2;
  score += card.caption.length >= 350 ? 8 : card.caption.length >= 180 ? 5 : 2;
  score += card.cta.toLowerCase().includes("save") ? 4 : 2;
  score += noBannedClaims(text) ? 6 : -12;
  score += noPlaceholder(text) ? 6 : -12;

  return Math.max(0, Math.min(100, score));
}

function hasAny(value: string, needles: string[]): boolean {
  return needles.some((needle) => value.includes(needle));
}

function avgTextLength(values: string[]): number {
  if (values.length === 0) {
    return 0;
  }
  return values.reduce((sum, value) => sum + value.length, 0) / values.length;
}

function noBannedClaims(value: string): boolean {
  return !/\b(weight loss|fat loss|guaranteed|cure|medical|punish|shame)\b/i
    .test(value);
}

function noPlaceholder(value: string): boolean {
  return !/\b(tbd|placeholder|lorem|null|undefined)\b/i.test(value);
}

function summarizeIteration(
  run: RunResult,
  output: GeneratedDayOutput | null,
  failureCode: string,
  qualityScore: number,
): string {
  if (!output) {
    return failureCode || tail(run.stderr, 160);
  }
  const card = output.daily_card;
  return `${card.format} "${card.title}" scored ${qualityScore}. ${card.weekly_brief_anchor}`;
}

function buildSummary(metrics: IterationMetric[]): string {
  const completed = metrics.filter((metric) => metric.validation_passed);
  const best =
    [...completed].sort((a, b) =>
      b.quality_score - a.quality_score || a.duration_ms - b.duration_ms
    )[0];
  const fastestValid =
    [...completed].sort((a, b) => a.duration_ms - b.duration_ms)[0];
  const averageDayMs = completed.length === 0 ? 0 : Math.round(
    completed.reduce((sum, metric) => sum + metric.duration_ms, 0) /
      completed.length,
  );
  const averageQuality = completed.length === 0 ? 0 : Math.round(
    completed.reduce((sum, metric) => sum + metric.quality_score, 0) /
      completed.length,
  );

  return [
    "# AI Day Generation Prompt Benchmark",
    "",
    `Run finished: ${new Date().toISOString()}`,
    `Model: ${model}`,
    `Model variant: ${modelVariant}`,
    `Provider path: GLM proxy through local OpenCode`,
    "",
    "## Summary",
    "",
    `- Iterations requested: ${maxIterations}`,
    `- Start variant index: ${startVariantIndex}`,
    `- Valid outputs: ${completed.length} of ${metrics.length}`,
    `- Average valid generation time: ${formatMs(averageDayMs)}`,
    `- Average valid quality score: ${averageQuality}`,
    best
      ? `- Best quality variant: ${best.variant_name} (${best.quality_score}/100, ${
        formatMs(best.duration_ms)
      }, ${best.prompt_chars} prompt chars)`
      : "- Best quality variant: none",
    fastestValid
      ? `- Fastest valid variant: ${fastestValid.variant_name} (${
        formatMs(fastestValid.duration_ms)
      }, quality ${fastestValid.quality_score}/100)`
      : "- Fastest valid variant: none",
    "",
    "## Metrics",
    "",
    "| Iteration | Variant | Prompt chars | Time | Valid | Quality | Failure |",
    "| --- | --- | ---: | ---: | --- | ---: | --- |",
    ...metrics.map((metric) =>
      `| ${metric.iteration} | ${metric.variant_name} | ${metric.prompt_chars} | ${
        formatMs(metric.duration_ms)
      } | ${
        metric.validation_passed ? "yes" : "no"
      } | ${metric.quality_score} | ${metric.failure_code || ""} |`
    ),
    "",
    "## Recommendation",
    "",
    best
      ? `Use ${best.variant_name} as the starting point for the production prompt rewrite, then smoke test against the real provider before TestFlight.`
      : "No production prompt change is recommended because no valid output was produced.",
    "",
    "## Artifacts",
    "",
    `- Progress: ${progressPath()}`,
    `- Outputs: ${outputsPath()}`,
    `- Metrics: ${metricsPath()}`,
    `- Duration chart: ${chartPath()}`,
    "",
  ].join("\n");
}

function buildDurationChart(metrics: IterationMetric[]): string {
  const width = 900;
  const height = 360;
  const padding = 44;
  const maxMs = Math.max(1, ...metrics.map((metric) => metric.duration_ms));
  const points = metrics.map((metric, index) => {
    const x = padding +
      (metrics.length === 1
        ? 0
        : index * ((width - padding * 2) / (metrics.length - 1)));
    const y = height - padding -
      (metric.duration_ms / maxMs) * (height - padding * 2);
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  }).join(" ");
  const labels = metrics.map((metric, index) => {
    const x = padding +
      (metrics.length === 1
        ? 0
        : index * ((width - padding * 2) / (metrics.length - 1)));
    return `<text x="${x.toFixed(1)}" y="${
      height - 12
    }" text-anchor="middle" font-size="10">${metric.iteration}</text>`;
  }).join("\n");

  return [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">`,
    `<rect width="100%" height="100%" fill="#fbf7ef"/>`,
    `<text x="${padding}" y="24" font-size="18" font-family="Arial" fill="#26342f">Generation duration by iteration</text>`,
    `<line x1="${padding}" y1="${height - padding}" x2="${
      width - padding
    }" y2="${height - padding}" stroke="#cbbda9"/>`,
    `<line x1="${padding}" y1="${padding}" x2="${padding}" y2="${
      height - padding
    }" stroke="#cbbda9"/>`,
    `<polyline fill="none" stroke="#9f2f31" stroke-width="3" points="${points}"/>`,
    labels,
    `</svg>`,
  ].join("\n");
}

function progressPath(): string {
  return `${outputDir}/progress.ndjson`;
}

function outputsPath(): string {
  return `${outputDir}/outputs.jsonl`;
}

function metricsPath(): string {
  return `${outputDir}/metrics.csv`;
}

function summaryPath(): string {
  return `${outputDir}/summary.md`;
}

function chartPath(): string {
  return `${outputDir}/duration-chart.svg`;
}

async function appendJSONLine(path: string, value: unknown): Promise<void> {
  await Deno.writeTextFile(path, `${JSON.stringify(value)}\n`, {
    append: true,
  });
}

async function appendCSV(
  path: string,
  metric: IterationMetric,
): Promise<void> {
  const values = [
    metric.iteration,
    metric.variant_name,
    metric.scheduled_date,
    metric.day_index,
    metric.day_intent,
    metric.provider,
    metric.model,
    metric.prompt_chars,
    metric.response_chars,
    metric.duration_ms,
    metric.timed_out,
    metric.validation_passed,
    metric.quality_score,
    metric.failure_code,
    metric.changed_prompt_factors.join("; "),
    metric.notes,
  ].map(csvCell);
  await Deno.writeTextFile(path, `${values.join(",")}\n`, { append: true });
}

function csvCell(value: unknown): string {
  const text = String(value ?? "");
  return `"${text.replaceAll('"', '""')}"`;
}

function parsePositiveInt(value: string | undefined): number | null {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return null;
  }
  return Math.trunc(parsed);
}

function parseNonNegativeInt(value: string | undefined): number | null {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) {
    return null;
  }
  return Math.trunc(parsed);
}

function shortError(error: unknown): string {
  if (error instanceof Error) {
    return error.message.slice(0, 240);
  }
  return String(error).slice(0, 240);
}

function tail(value: string, maxLength: number): string {
  if (value.length <= maxLength) {
    return value;
  }
  return value.slice(value.length - maxLength);
}

function formatMs(ms: number): string {
  if (ms < 1000) {
    return `${ms}ms`;
  }
  return `${(ms / 1000).toFixed(1)}s`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}
