import {
  AIGenerationAttemptLog,
  AIGenerationInstrumentation,
  AIOutputQualityMetrics,
  AIProviderConfig,
  callAIProvidersForSplitWeek,
  GeneratedDailyCard,
  GeneratedWeekOutput,
  GenerationInputSnapshot,
} from "../supabase/functions/generate-week/generation.ts";

type AttemptStatus = "success" | "failure";

type ExperimentVariant = {
  name: string;
  description: string;
  changed_factors: string[];
  risk: "baseline" | "local_input_only";
  complexity_cost: number;
  mutateInput: (input: GenerationInputSnapshot) => GenerationInputSnapshot;
};

type RunConfig = {
  label: string;
  attempts_per_variant: number;
  output_dir: string;
  provider_order: string[];
  providers: Array<{ provider: string; model: string; base_url?: string }>;
  variants: Array<{
    name: string;
    description: string;
    changed_factors: string[];
    risk: string;
    complexity_cost: number;
  }>;
  objective:
    "success_rate_quality_latency_token_weighted_v1_local_experiment_only";
  min_improvement_delta: number;
  week_start_date: string;
  created_at: string;
};

type AttemptSummary = {
  attempt_number: number;
  variant_attempt_number: number;
  attempt_id: string;
  generation_id: string;
  label: string;
  variant_name: string;
  variant_description: string;
  status: AttemptStatus;
  started_at: string;
  ended_at: string;
  duration_ms: number;
  provider_attempt_logs: number;
  successful_day_logs: number;
  failed_day_logs: number;
  output_daily_cards: number;
  avg_quality_score: number | null;
  min_quality_score: number | null;
  max_quality_score: number | null;
  input_tokens: number | null;
  output_tokens: number | null;
  total_tokens: number | null;
  output_text_chars: number | null;
  error_category: string | null;
  error_message: string | null;
};

type VariantSummary = {
  variant_name: string;
  description: string;
  changed_factors: string[];
  risk: string;
  complexity_cost: number;
  attempt_count: number;
  successful_attempt_count: number;
  failed_attempt_count: number;
  success_rate: number;
  failed_provider_log_count: number;
  retry_or_failure_rate: number;
  length_finish_count: number;
  avg_quality_score: number | null;
  avg_attempt_duration_ms: number | null;
  avg_successful_day_total_tokens: number | null;
  objective_score: number | null;
  decision: string;
};

type LoggedAttempt = {
  attempt_number: number;
  variant_attempt_number: number;
  variant_name: string;
  attempt_id: string;
  log: AIGenerationAttemptLog;
};

type SuccessfulOutputEntry = {
  attempt_number: number;
  variant_attempt_number: number;
  variant_name: string;
  attempt_id: string;
  output: GeneratedWeekOutput;
  summary: AttemptSummary;
};

type BlockedConfig = {
  blocked: true;
  reason: string;
  missing_env: string[];
  accepted_provider_order: string[];
  optional_env: string[];
};

const DEFAULT_OPENAI_MODEL = "gpt-4.1-mini";
const DEFAULT_DEEPSEEK_MODEL = "deepseek-v4-pro";
const DEFAULT_DEEPSEEK_BASE_URL = "https://api.deepseek.com";
const defaultOutputRoot = `build-logs/generation-quality-loop/${
  timestampSlug(new Date())
}`;

const label = Deno.env.get("QUALITY_LOOP_LABEL")?.trim() || "baseline";
const outputDir = Deno.env.get("QUALITY_LOOP_OUTPUT_DIR")?.trim() ||
  defaultOutputRoot;
const attempts = parsePositiveInt(Deno.env.get("QUALITY_LOOP_ATTEMPTS")) ?? 3;
const fixturePath = Deno.env.get("QUALITY_LOOP_INPUT_PATH")?.trim();
const minImprovementDelta =
  parsePositiveFloat(Deno.env.get("QUALITY_LOOP_MIN_IMPROVEMENT_DELTA")) ?? 1;

const booleanQualityMetricKeys = [
  "hook_first_3s_present",
  "first_frame_text_hook_present",
  "opening_visual_motion_present",
  "clear_payoff_or_curiosity_gap_present",
  "watch_without_sound_ready",
  "on_screen_text_present",
  "caption_or_subtitle_support_present",
  "on_screen_text_density_ok",
  "visual_variety_present",
  "audio_or_silent_strategy_present",
  "shareability_reason_present",
  "save_or_share_value_present",
  "clear_cta_present",
  "creator_lived_detail_present",
  "specific_context_anchor_present",
  "story_interactive_sticker_present",
  "story_reply_prompt_present",
  "story_slide_count_fit",
  "post_first_slide_promise_present",
  "post_one_clear_idea_present",
  "post_final_cta_present",
  "post_saveable_value_present",
] as const satisfies readonly (keyof AIOutputQualityMetrics)[];

const perDayCSVHeaders = [
  "attempt_number",
  "variant_attempt_number",
  "attempt_id",
  "label",
  "variant_name",
  "generation_id",
  "generation_scope",
  "phase",
  "week_start_date",
  "scheduled_date",
  "day_index",
  "provider",
  "model",
  "provider_attempt",
  "status",
  "duration_ms",
  "input_tokens",
  "output_tokens",
  "total_tokens",
  "finish_reason",
  "output_text_chars",
  "output_text_bytes",
  "prompt_total_chars",
  "prompt_estimated_tokens",
  "provider_request_body_chars",
  "provider_request_body_bytes",
  "reference_context_chars",
  "reference_context_estimated_tokens",
  "confirmed_reference_count",
  "reference_extraction_count",
  "recent_archive_count",
  "idea_bank_count",
  "quality_score",
  "quality_version",
  "pillar_count",
  "instructor_phrase_count",
  "instructor_ending_count",
  "source_reference_link_count",
  "cards_with_source_reference_count",
  "duration_fit",
  "scene_variety_count",
  "cta_type",
  "generic_template_risk_count",
  ...booleanQualityMetricKeys,
  "error_category",
  "error_message",
  "validation_stage",
  "validation_rule",
  "validation_path",
  "validation_retryable",
];

const variantResultsTSVHeaders = [
  "variant_name",
  "decision",
  "attempts",
  "successes",
  "success_rate",
  "avg_quality_score",
  "avg_attempt_duration_ms",
  "avg_successful_day_total_tokens",
  "failed_provider_log_count",
  "retry_or_failure_rate",
  "length_finish_count",
  "complexity_cost",
  "objective_score",
  "changed_factors",
];

async function main(): Promise<void> {
  await Deno.mkdir(outputDir, { recursive: true });

  const baseInput = await loadInputSnapshot();
  const variants = selectedExperimentVariants();
  const providerSetup = providerConfigs();
  const runConfig: RunConfig = {
    label,
    attempts_per_variant: attempts,
    output_dir: outputDir,
    provider_order: providerSetup.order,
    providers: providerSetup.providers.map((provider) => ({
      provider: provider.provider,
      model: provider.model,
      base_url: provider.provider === "deepseek" ? provider.baseURL : undefined,
    })),
    variants: variants.map((variant) => ({
      name: variant.name,
      description: variant.description,
      changed_factors: variant.changed_factors,
      risk: variant.risk,
      complexity_cost: variant.complexity_cost,
    })),
    objective:
      "success_rate_quality_latency_token_weighted_v1_local_experiment_only",
    min_improvement_delta: minImprovementDelta,
    week_start_date: baseInput.week_start_date,
    created_at: new Date().toISOString(),
  };
  await writeJSON(`${outputDir}/run-config.json`, runConfig);
  await Deno.writeTextFile(
    `${outputDir}/per-day-metrics.csv`,
    perDayCSVHeaders.map(csvCell).join(",") + "\n",
  );
  await Deno.writeTextFile(`${outputDir}/raw-attempt-logs.ndjson`, "");
  await Deno.writeTextFile(`${outputDir}/full-week-outputs.jsonl`, "");
  await Deno.writeTextFile(
    `${outputDir}/variant-results.tsv`,
    `${variantResultsTSVHeaders.join("\t")}\n`,
  );

  if (providerSetup.providers.length === 0) {
    const blocked: BlockedConfig = {
      blocked: true,
      reason: "missing_provider_config",
      missing_env: providerSetup.missingEnv,
      accepted_provider_order: providerSetup.order,
      optional_env: [
        "MCO_OPENAI_MODEL",
        "MCO_DEEPSEEK_MODEL",
        "MCO_DEEPSEEK_BASE_URL",
        "MCO_AI_PROVIDER_ORDER",
        "QUALITY_LOOP_PROVIDER_ORDER",
        "QUALITY_LOOP_VARIANTS",
        "QUALITY_LOOP_MIN_IMPROVEMENT_DELTA",
        "MCO_PARALLEL_WEEK_GENERATION_CONCURRENCY",
        "MCO_AI_REQUEST_TIMEOUT_MS",
      ],
    };
    await writeJSON(`${outputDir}/blocked-provider-config.json`, blocked);
    await Deno.writeTextFile(
      `${outputDir}/summary.md`,
      blockedSummary(runConfig, blocked),
    );
    console.error(
      `Blocked: missing provider config. Set at least one of ${
        providerSetup.missingEnv.join(", ")
      }. Artifacts: ${outputDir}`,
    );
    Deno.exit(2);
  }

  const attemptSummaries: AttemptSummary[] = [];
  const allLogs: LoggedAttempt[] = [];
  const successfulOutputs: SuccessfulOutputEntry[] = [];
  let globalAttemptNumber = 0;

  for (const variant of variants) {
    const input = variant.mutateInput(cloneInputSnapshot(baseInput));
    await writeJSON(`${outputDir}/input-${variant.name}.json`, input);

    for (let index = 0; index < attempts; index += 1) {
      globalAttemptNumber += 1;
      const variantAttemptNumber = index + 1;
      const attemptID =
        `${label}-${variant.name}-${variantAttemptNumber}-${crypto.randomUUID()}`;
      const generationID = `quality-loop-${attemptID}`;
      const logs: AIGenerationAttemptLog[] = [];
      const instrumentation: AIGenerationInstrumentation = {
        generationID,
        generationScope: "day",
        phase: "split_week_day_generation",
        logger: (log) => logs.push(log),
      };
      const startedAt = new Date();
      const startedMs = performance.now();
      let output: GeneratedWeekOutput | null = null;
      let error: unknown = null;

      console.log(
        `Starting ${label}/${variant.name} attempt ${variantAttemptNumber}/${attempts} for ${input.week_start_date}`,
      );

      try {
        output = await callAIProvidersForSplitWeek(
          input,
          providerSetup.providers,
          undefined,
          instrumentation,
        );
      } catch (caught) {
        error = caught;
      }

      const endedAt = new Date();
      const summary = summarizeAttempt({
        attemptNumber: globalAttemptNumber,
        variantAttemptNumber,
        attemptID,
        generationID,
        label,
        variant,
        startedAt,
        endedAt,
        durationMs: Math.round(performance.now() - startedMs),
        logs,
        output,
        error,
      });

      attemptSummaries.push(summary);
      for (const log of logs) {
        allLogs.push({
          attempt_number: globalAttemptNumber,
          variant_attempt_number: variantAttemptNumber,
          variant_name: variant.name,
          attempt_id: attemptID,
          log,
        });
        await appendJSONLine(`${outputDir}/raw-attempt-logs.ndjson`, {
          attempt_number: globalAttemptNumber,
          variant_attempt_number: variantAttemptNumber,
          attempt_id: attemptID,
          label,
          variant_name: variant.name,
          log,
        });
        await appendCSVLine(
          `${outputDir}/per-day-metrics.csv`,
          perDayCSVRow(
            globalAttemptNumber,
            variantAttemptNumber,
            attemptID,
            label,
            variant.name,
            generationID,
            log,
          ),
        );
      }

      await appendJSONLine(`${outputDir}/attempt-summaries.jsonl`, summary);
      if (output) {
        successfulOutputs.push({
          attempt_number: globalAttemptNumber,
          variant_attempt_number: variantAttemptNumber,
          variant_name: variant.name,
          attempt_id: attemptID,
          output,
          summary,
        });
        await appendJSONLine(`${outputDir}/full-week-outputs.jsonl`, {
          attempt_number: globalAttemptNumber,
          variant_attempt_number: variantAttemptNumber,
          attempt_id: attemptID,
          label,
          variant_name: variant.name,
          generation_id: generationID,
          output,
        });
      }

      console.log(
        `Finished ${label}/${variant.name} attempt ${variantAttemptNumber}/${attempts}: ${summary.status}`,
      );
    }
  }

  const variantReport = variantSummaries(
    variants,
    attemptSummaries,
    allLogs,
    minImprovementDelta,
  );
  await Deno.writeTextFile(
    `${outputDir}/variant-results.tsv`,
    variantResultsTSV(variantReport),
  );
  await writeJSON(`${outputDir}/aggregate-report.json`, {
    run_config: runConfig,
    aggregate: aggregateAttempts(attemptSummaries, allLogs, successfulOutputs),
    variant_summaries: variantReport,
    attempts: attemptSummaries,
  });
  await Deno.writeTextFile(
    `${outputDir}/summary.md`,
    buildSummary(
      runConfig,
      attemptSummaries,
      allLogs,
      successfulOutputs,
      variantReport,
    ),
  );
}

async function loadInputSnapshot(): Promise<GenerationInputSnapshot> {
  if (!fixturePath) {
    return fixture;
  }
  const text = await Deno.readTextFile(fixturePath);
  const parsed = JSON.parse(text);
  if (!isRecord(parsed)) {
    throw new Error("QUALITY_LOOP_INPUT_PATH must contain a JSON object.");
  }
  return parsed as GenerationInputSnapshot;
}

function selectedExperimentVariants(): ExperimentVariant[] {
  const requested = (env("QUALITY_LOOP_VARIANTS") ?? "baseline")
    .split(",")
    .map((name) => name.trim())
    .filter((name) => name.length > 0);
  const variantsByName = new Map(
    allExperimentVariants().map((variant) => [variant.name, variant]),
  );
  const selected = uniqueStrings(requested).map((name) => {
    const variant = variantsByName.get(name);
    if (!variant) {
      throw new Error(
        `Unknown QUALITY_LOOP_VARIANTS entry "${name}". Available: ${
          [...variantsByName.keys()].join(", ")
        }`,
      );
    }
    return variant;
  });
  return selected.some((variant) => variant.name === "baseline")
    ? selected
    : [variantsByName.get("baseline")!, ...selected];
}

function allExperimentVariants(): ExperimentVariant[] {
  return [
    {
      name: "baseline",
      description:
        "Unmodified production split-week generation against the fixed input snapshot.",
      changed_factors: ["none"],
      risk: "baseline",
      complexity_cost: 0,
      mutateInput: (input) => input,
    },
    {
      name: "compact_references",
      description:
        "Local-only input transform that keeps reference IDs and core facts but trims verbose reference fields.",
      changed_factors: [
        "confirmed references compacted",
        "reference extractions compacted",
      ],
      risk: "local_input_only",
      complexity_cost: 1,
      mutateInput: compactReferencesInput,
    },
    {
      name: "focused_context",
      description:
        "Local-only input transform that keeps current-week context prominent and removes lower-priority archive/trend bulk.",
      changed_factors: [
        "recent archive trimmed to one entry",
        "patterns/trends/audio options compacted",
      ],
      risk: "local_input_only",
      complexity_cost: 2,
      mutateInput: focusedContextInput,
    },
    {
      name: "brief_quality_tags",
      description:
        "Local-only input transform that adds one saved pattern carrying explicit retention, sound-off, and lived-detail goals.",
      changed_factors: [
        "adds local quality pattern",
        "does not change production prompt/request code",
      ],
      risk: "local_input_only",
      complexity_cost: 3,
      mutateInput: briefQualityTagsInput,
    },
  ];
}

function compactReferencesInput(
  input: GenerationInputSnapshot,
): GenerationInputSnapshot {
  return {
    ...input,
    confirmed_references: input.confirmed_references.map((reference) => ({
      id: reference.id,
      type: reference.type,
      title: reference.title,
      manual_notes: reference.manual_notes,
      tags: Array.isArray(reference.tags) ? reference.tags.slice(0, 4) : [],
    })),
    reference_extractions: input.reference_extractions.map((extraction) => ({
      reference_id: extraction.reference_id,
      extraction: extraction.extraction,
    })),
  };
}

function focusedContextInput(
  input: GenerationInputSnapshot,
): GenerationInputSnapshot {
  return {
    ...compactReferencesInput(input),
    recent_archive: input.recent_archive.slice(0, 1).map((archive) => ({
      scheduled_date: archive.scheduled_date,
      title: archive.title,
      feedback: archive.feedback,
    })),
    patterns: input.patterns.slice(0, 1).map((pattern) => ({
      name: pattern.name,
      instruction: pattern.instruction,
    })),
    trends: [],
    audio_options: input.audio_options.slice(0, 1).map((audio) => ({
      name: audio.name,
      instruction: audio.instruction,
    })),
  };
}

function briefQualityTagsInput(
  input: GenerationInputSnapshot,
): GenerationInputSnapshot {
  const focused = focusedContextInput(input);
  return {
    ...focused,
    patterns: [
      ...focused.patterns,
      {
        name: "Quality metric guard",
        instruction:
          "Each Reel needs a visible first-frame hook, motion in 0:00-0:03, a sound-off version, one specific lived detail from this week, and an earned save/share reason.",
      },
    ],
  };
}

function cloneInputSnapshot(
  input: GenerationInputSnapshot,
): GenerationInputSnapshot {
  return JSON.parse(JSON.stringify(input)) as GenerationInputSnapshot;
}

function providerConfigs(): {
  providers: AIProviderConfig[];
  order: string[];
  missingEnv: string[];
} {
  const deepSeekKey = env("DEEPSEEK_API_KEY");
  const openAIKey = env("OPENAI_API_KEY");
  const deepSeekModel = env("MCO_DEEPSEEK_MODEL") ?? DEFAULT_DEEPSEEK_MODEL;
  const openAIModel = env("MCO_OPENAI_MODEL") ?? DEFAULT_OPENAI_MODEL;
  const deepSeekBaseURL = env("MCO_DEEPSEEK_BASE_URL") ??
    DEFAULT_DEEPSEEK_BASE_URL;
  const order = (env("QUALITY_LOOP_PROVIDER_ORDER") ??
    env("MCO_AI_PROVIDER_ORDER") ?? "openai,deepseek")
    .split(",")
    .map((name) => name.trim().toLowerCase())
    .filter((name) => name.length > 0);

  const providersByName: Record<string, AIProviderConfig | undefined> = {
    openai: openAIKey
      ? { provider: "openai", model: openAIModel, apiKey: openAIKey }
      : undefined,
    deepseek: deepSeekKey
      ? {
        provider: "deepseek",
        model: deepSeekModel,
        apiKey: deepSeekKey,
        baseURL: deepSeekBaseURL,
      }
      : undefined,
  };

  const providers = uniqueStrings(order)
    .map((name) => providersByName[name])
    .filter((provider): provider is AIProviderConfig => Boolean(provider));
  const missingEnv = uniqueStrings(
    order.flatMap((name) => {
      if (name === "openai" && !openAIKey) {
        return ["OPENAI_API_KEY"];
      }
      if (name === "deepseek" && !deepSeekKey) {
        return ["DEEPSEEK_API_KEY"];
      }
      return [];
    }),
  );

  return {
    providers,
    order,
    missingEnv: providers.length === 0
      ? missingEnv.length > 0
        ? missingEnv
        : ["OPENAI_API_KEY", "DEEPSEEK_API_KEY"]
      : [],
  };
}

function summarizeAttempt(args: {
  attemptNumber: number;
  variantAttemptNumber: number;
  attemptID: string;
  generationID: string;
  label: string;
  variant: ExperimentVariant;
  startedAt: Date;
  endedAt: Date;
  durationMs: number;
  logs: AIGenerationAttemptLog[];
  output: GeneratedWeekOutput | null;
  error: unknown;
}): AttemptSummary {
  const successfulLogs = args.logs.filter((log) => log.status === "success");
  const failedLogs = args.logs.filter((log) => log.status === "failure");
  const qualityScores = successfulLogs
    .map((log) => log.quality_score)
    .filter(isNumber);
  const inputTokens = sumNullable(
    successfulLogs.map((log) => log.input_tokens),
  );
  const outputTokens = sumNullable(
    successfulLogs.map((log) => log.output_tokens),
  );
  const totalTokens = sumNullable(
    successfulLogs.map((log) => log.total_tokens),
  );
  const outputTextChars = sumNullable(
    successfulLogs.map((log) => log.output_text_chars),
  );
  const failureLog = failedLogs[failedLogs.length - 1];
  return {
    attempt_number: args.attemptNumber,
    variant_attempt_number: args.variantAttemptNumber,
    attempt_id: args.attemptID,
    generation_id: args.generationID,
    label: args.label,
    variant_name: args.variant.name,
    variant_description: args.variant.description,
    status: args.output ? "success" : "failure",
    started_at: args.startedAt.toISOString(),
    ended_at: args.endedAt.toISOString(),
    duration_ms: args.durationMs,
    provider_attempt_logs: args.logs.length,
    successful_day_logs: successfulLogs.length,
    failed_day_logs: failedLogs.length,
    output_daily_cards: args.output?.daily_cards.length ?? 0,
    avg_quality_score: averageNullable(qualityScores),
    min_quality_score: minNullable(qualityScores),
    max_quality_score: maxNullable(qualityScores),
    input_tokens: inputTokens,
    output_tokens: outputTokens,
    total_tokens: totalTokens,
    output_text_chars: outputTextChars,
    error_category: failureLog?.error_category ?? errorCategory(args.error),
    error_message: failureLog?.error_message ?? errorMessage(args.error),
  };
}

function aggregateAttempts(
  attemptsForRun: AttemptSummary[],
  logs: LoggedAttempt[],
  outputs: SuccessfulOutputEntry[],
): Record<string, unknown> {
  const successfulAttempts = attemptsForRun.filter((attempt) =>
    attempt.status === "success"
  );
  const successfulLogs = logs
    .map((entry) => entry.log)
    .filter((log) => log.status === "success");
  const allQualityScores = successfulLogs
    .map((log) => log.quality_score)
    .filter(isNumber);

  return {
    attempt_count: attemptsForRun.length,
    successful_attempt_count: successfulAttempts.length,
    failed_attempt_count: attemptsForRun.length - successfulAttempts.length,
    duration_ms: distribution(
      attemptsForRun.map((attempt) => attempt.duration_ms),
    ),
    successful_attempt_duration_ms: distribution(
      successfulAttempts.map((attempt) => attempt.duration_ms),
    ),
    successful_day_duration_ms: distribution(
      successfulLogs.map((log) => log.duration_ms),
    ),
    total_tokens: distribution(
      successfulLogs.map((log) => log.total_tokens).filter(isNumber),
    ),
    input_tokens: distribution(
      successfulLogs.map((log) => log.input_tokens).filter(isNumber),
    ),
    output_tokens: distribution(
      successfulLogs.map((log) => log.output_tokens).filter(isNumber),
    ),
    output_text_chars: distribution(
      successfulLogs.map((log) => log.output_text_chars).filter(isNumber),
    ),
    quality_score: distribution(allQualityScores),
    failure_breakdown: countBy(
      logs.map((entry) => entry.log.error_category).filter(isString),
    ),
    validation_failure_breakdown: countBy(
      logs
        .map((entry) => entry.log.validation_error?.rule)
        .filter(isString),
    ),
    finish_reason_breakdown: countBy(
      logs.map((entry) => entry.log.finish_reason).filter(isString),
    ),
    weak_quality_metrics: weakQualityMetrics(successfulLogs),
    sampled_outputs: outputs.slice(0, 2).map((entry) => ({
      attempt_number: entry.attempt_number,
      variant_name: entry.variant_name,
      avg_quality_score: entry.summary.avg_quality_score,
      cards: entry.output.daily_cards.map(cardSnapshot),
    })),
  };
}

function variantSummaries(
  variants: ExperimentVariant[],
  attemptsForRun: AttemptSummary[],
  logs: LoggedAttempt[],
  minDelta: number,
): VariantSummary[] {
  const summariesWithoutDecision = variants.map((variant) => {
    const variantAttempts = attemptsForRun.filter((attempt) =>
      attempt.variant_name === variant.name
    );
    const variantLogs = logs.filter((entry) =>
      entry.variant_name === variant.name
    );
    const successfulAttempts = variantAttempts.filter((attempt) =>
      attempt.status === "success"
    );
    const successfulDayLogs = variantLogs
      .map((entry) => entry.log)
      .filter((log) => log.status === "success");
    const failedProviderLogCount = variantLogs.filter((entry) =>
      entry.log.status === "failure"
    ).length;
    const qualityScores = successfulDayLogs
      .map((log) => log.quality_score)
      .filter(isNumber);
    const avgQuality = averageNullable(qualityScores);
    const avgDuration = averageNullable(
      variantAttempts.map((attempt) => attempt.duration_ms),
    );
    const avgTokens = averageNullable(
      successfulDayLogs.map((log) => log.total_tokens).filter(isNumber),
    );
    const successRate = variantAttempts.length === 0
      ? 0
      : successfulAttempts.length / variantAttempts.length;
    const retryOrFailureRate = variantLogs.length === 0
      ? 0
      : failedProviderLogCount / variantLogs.length;
    const lengthFinishCount = variantLogs.filter((entry) =>
      entry.log.finish_reason === "length" ||
      entry.log.finish_reason === "max_output_tokens"
    ).length;

    return {
      variant_name: variant.name,
      description: variant.description,
      changed_factors: variant.changed_factors,
      risk: variant.risk,
      complexity_cost: variant.complexity_cost,
      attempt_count: variantAttempts.length,
      successful_attempt_count: successfulAttempts.length,
      failed_attempt_count: variantAttempts.length - successfulAttempts.length,
      success_rate: round(successRate, 3),
      failed_provider_log_count: failedProviderLogCount,
      retry_or_failure_rate: round(retryOrFailureRate, 3),
      length_finish_count: lengthFinishCount,
      avg_quality_score: avgQuality,
      avg_attempt_duration_ms: avgDuration,
      avg_successful_day_total_tokens: avgTokens,
      objective_score: objectiveScore({
        successRate,
        avgQuality,
        avgAttemptDurationMs: avgDuration,
        avgSuccessfulDayTotalTokens: avgTokens,
        retryOrFailureRate,
        lengthFinishCount,
        complexityCost: variant.complexity_cost,
      }),
      decision: "",
    } satisfies VariantSummary;
  });

  const baseline =
    summariesWithoutDecision.find((summary) =>
      summary.variant_name === "baseline"
    ) ?? summariesWithoutDecision[0];

  return summariesWithoutDecision.map((summary) => ({
    ...summary,
    decision: variantDecision(summary, baseline, minDelta),
  }));
}

function objectiveScore(args: {
  successRate: number;
  avgQuality: number | null;
  avgAttemptDurationMs: number | null;
  avgSuccessfulDayTotalTokens: number | null;
  retryOrFailureRate: number;
  lengthFinishCount: number;
  complexityCost: number;
}): number | null {
  if (args.avgQuality === null) {
    return null;
  }
  const durationPenalty = Math.min(
    (args.avgAttemptDurationMs ?? 0) / 60_000,
    8,
  );
  const tokenPenalty = Math.min(
    (args.avgSuccessfulDayTotalTokens ?? 0) / 2500,
    8,
  );
  const score = args.successRate * 30 +
    args.avgQuality * 0.7 -
    args.retryOrFailureRate * 12 -
    args.lengthFinishCount * 4 -
    durationPenalty -
    tokenPenalty -
    args.complexityCost;
  return round(score, 2);
}

function variantDecision(
  summary: VariantSummary,
  baseline: VariantSummary,
  minDelta: number,
): string {
  if (summary.variant_name === baseline.variant_name) {
    return "baseline_reference";
  }
  if (summary.objective_score === null) {
    return "discard_no_valid_outputs";
  }
  if (baseline.objective_score === null) {
    return "candidate_keep_for_user_review_no_baseline_score";
  }
  if (summary.success_rate < baseline.success_rate) {
    return "discard_success_rate_regression";
  }
  if (summary.objective_score >= baseline.objective_score + minDelta) {
    return "candidate_keep_for_user_review";
  }
  return "discard_no_evidence_gain";
}

function variantResultsTSV(summaries: VariantSummary[]): string {
  return [
    variantResultsTSVHeaders.join("\t"),
    ...summaries.map((summary) =>
      [
        summary.variant_name,
        summary.decision,
        summary.attempt_count,
        summary.successful_attempt_count,
        summary.success_rate,
        summary.avg_quality_score,
        summary.avg_attempt_duration_ms,
        summary.avg_successful_day_total_tokens,
        summary.failed_provider_log_count,
        summary.retry_or_failure_rate,
        summary.length_finish_count,
        summary.complexity_cost,
        summary.objective_score,
        summary.changed_factors.join("; "),
      ].map(tsvCell).join("\t")
    ),
  ].join("\n") + "\n";
}

function buildSummary(
  config: RunConfig,
  attemptsForRun: AttemptSummary[],
  logs: LoggedAttempt[],
  outputs: SuccessfulOutputEntry[],
  variantsForRun: VariantSummary[],
): string {
  const aggregate = aggregateAttempts(attemptsForRun, logs, outputs);
  const successfulAttempts = attemptsForRun.filter((attempt) =>
    attempt.status === "success"
  );
  const failedAttempts = attemptsForRun.filter((attempt) =>
    attempt.status === "failure"
  );
  const successfulLogs = logs
    .map((entry) => entry.log)
    .filter((log) => log.status === "success");
  const weakMetrics = weakQualityMetrics(successfulLogs).slice(0, 12);
  const failureRows = failureDiagnosis(logs).slice(0, 12);

  return [
    "# ContentHelper Full-Week Generation Quality Loop",
    "",
    `Run finished: ${new Date().toISOString()}`,
    `Label: ${config.label}`,
    `Week start: ${config.week_start_date}`,
    `Providers: ${
      config.providers.map((p) => `${p.provider}:${p.model}`).join(" -> ")
    }`,
    `Objective: ${config.objective}`,
    `Minimum improvement delta: ${config.min_improvement_delta}`,
    "",
    "## Variant Ratchet",
    "",
    variantsForRun.length === 0 ? "- No variants were evaluated." : [
      "| Variant | Decision | Attempts | Successes | Success Rate | Avg Quality | Avg Duration | Avg Tokens | Objective |",
      "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
      ...variantsForRun.map((variant) =>
        `| ${variant.variant_name} | ${variant.decision} | ${variant.attempt_count} | ${variant.successful_attempt_count} | ${variant.success_rate} | ${
          formatNullable(variant.avg_quality_score)
        } | ${formatNullable(variant.avg_attempt_duration_ms)} | ${
          formatNullable(variant.avg_successful_day_total_tokens)
        } | ${formatNullable(variant.objective_score)} |`
      ),
    ].join("\n"),
    "",
    "## Aggregate Metrics",
    "",
    `- Attempts: ${attemptsForRun.length}`,
    `- Successful full-week outputs: ${successfulAttempts.length}`,
    `- Failed full-week outputs: ${failedAttempts.length}`,
    `- Attempt duration: ${formatDistribution(aggregate.duration_ms)}`,
    `- Successful day duration: ${
      formatDistribution(aggregate.successful_day_duration_ms)
    }`,
    `- Quality score: ${formatDistribution(aggregate.quality_score)}`,
    `- Total tokens per successful day: ${
      formatDistribution(aggregate.total_tokens)
    }`,
    `- Output chars per successful day: ${
      formatDistribution(aggregate.output_text_chars)
    }`,
    "",
    "## Attempts",
    "",
    "| Attempt | Variant | Variant Run | Status | Days OK | Days Failed | Duration | Avg Quality | Tokens | Error |",
    "| ---: | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- |",
    ...attemptsForRun.map((attempt) =>
      `| ${attempt.attempt_number} | ${attempt.variant_name} | ${attempt.variant_attempt_number} | ${attempt.status} | ${attempt.successful_day_logs} | ${attempt.failed_day_logs} | ${
        formatMs(attempt.duration_ms)
      } | ${formatNullable(attempt.avg_quality_score)} | ${
        formatNullable(attempt.total_tokens)
      } | ${attempt.error_category ?? ""} |`
    ),
    "",
    "## Failure And Validation Breakdown",
    "",
    Object.keys(aggregate.failure_breakdown as Record<string, number>)
        .length ===
        0
      ? "- No provider or validation failures logged."
      : tableFromCounts(aggregate.failure_breakdown as Record<string, number>),
    "",
    failureRows.length === 0
      ? "- No validation failure diagnosis available."
      : [
        "| Stage | Rule | Path | Count | Likely bottleneck |",
        "| --- | --- | --- | ---: | --- |",
        ...failureRows.map((row) =>
          `| ${row.stage} | ${row.rule} | ${row.path} | ${row.count} | ${row.bottleneck} |`
        ),
      ].join("\n"),
    "",
    "## Weak Or Inconsistent Quality Metrics",
    "",
    weakMetrics.length === 0
      ? "- No weak quality metrics among successful day logs."
      : [
        "| Metric | Failing or missing logs | Total logs |",
        "| --- | ---: | ---: |",
        ...weakMetrics.map((metric) =>
          `| ${metric.metric} | ${metric.weak_count} | ${metric.total} |`
        ),
      ].join("\n"),
    "",
    "## Qualitative Sample",
    "",
    outputs.length === 0
      ? "- No valid full-week output was available for qualitative sampling."
      : sampledOutputMarkdown(outputs[0].output),
    "",
    "## Recommendation",
    "",
    recommendation(
      successfulAttempts,
      weakMetrics,
      failureRows,
      variantsForRun,
    ),
    "",
    "## Artifacts",
    "",
    `- Run config: ${outputDir}/run-config.json`,
    `- Raw structured logs: ${outputDir}/raw-attempt-logs.ndjson`,
    `- Per-day metrics CSV: ${outputDir}/per-day-metrics.csv`,
    `- Variant results TSV: ${outputDir}/variant-results.tsv`,
    `- Attempt summaries: ${outputDir}/attempt-summaries.jsonl`,
    `- Full-week outputs: ${outputDir}/full-week-outputs.jsonl`,
    `- Aggregate report: ${outputDir}/aggregate-report.json`,
    "",
  ].join("\n");
}

function blockedSummary(config: RunConfig, blocked: BlockedConfig): string {
  return [
    "# ContentHelper Full-Week Generation Quality Loop",
    "",
    "Blocked: missing provider config.",
    "",
    `Run config was written at: ${new Date().toISOString()}`,
    `Label: ${config.label}`,
    `Week start: ${config.week_start_date}`,
    `Variants requested: ${
      config.variants.map((variant) => variant.name).join(", ")
    }`,
    "",
    "Set at least one provider key before running live generation:",
    ...blocked.missing_env.map((name) => `- ${name}`),
    "",
    "Optional env:",
    ...blocked.optional_env.map((name) => `- ${name}`),
    "",
    "No provider request was sent and no hosted ContentHelper data was mutated.",
    "",
    "Artifacts:",
    `- Run config: ${outputDir}/run-config.json`,
    `- Blocked config: ${outputDir}/blocked-provider-config.json`,
    `- Variant results: ${outputDir}/variant-results.tsv`,
    `- Summary: ${outputDir}/summary.md`,
    "",
  ].join("\n");
}

function perDayCSVRow(
  attemptNumber: number,
  variantAttemptNumber: number,
  attemptID: string,
  runLabel: string,
  variantName: string,
  generationID: string,
  log: AIGenerationAttemptLog,
): string[] {
  const quality = log.quality_metrics;
  const request = log.request_metrics;
  return [
    attemptNumber,
    variantAttemptNumber,
    attemptID,
    runLabel,
    variantName,
    generationID,
    log.generation_scope,
    log.phase,
    log.week_start_date,
    log.scheduled_date,
    log.day_index,
    log.provider,
    log.model,
    log.provider_attempt,
    log.status,
    log.duration_ms,
    log.input_tokens,
    log.output_tokens,
    log.total_tokens,
    log.finish_reason,
    log.output_text_chars,
    log.output_text_bytes,
    request?.prompt_total_chars,
    request?.prompt_estimated_tokens,
    request?.provider_request_body_chars,
    request?.provider_request_body_bytes,
    request?.reference_context_chars,
    request?.reference_context_estimated_tokens,
    request?.confirmed_reference_count,
    request?.reference_extraction_count,
    request?.recent_archive_count,
    request?.idea_bank_count,
    log.quality_score,
    log.quality_version,
    quality?.pillar_count,
    quality?.instructor_phrase_count,
    quality?.instructor_ending_count,
    quality?.source_reference_link_count,
    quality?.cards_with_source_reference_count,
    quality?.duration_fit,
    quality?.scene_variety_count,
    quality?.cta_type,
    quality?.generic_template_risk_count,
    ...booleanQualityMetricKeys.map((key) => quality?.[key]),
    log.error_category,
    log.error_message,
    log.validation_error?.stage,
    log.validation_error?.rule,
    log.validation_error?.path,
    log.validation_error?.retryable,
  ].map((value) => String(value ?? ""));
}

function weakQualityMetrics(logs: AIGenerationAttemptLog[]): Array<
  { metric: string; weak_count: number; total: number }
> {
  const total = logs.length;
  if (total === 0) {
    return [];
  }
  const rows: Array<{ metric: string; weak_count: number; total: number }> = [];
  for (const key of booleanQualityMetricKeys) {
    const weakCount = logs.filter((log) => log.quality_metrics?.[key] !== true)
      .length;
    if (weakCount > 0) {
      rows.push({ metric: key, weak_count: weakCount, total });
    }
  }

  const numericChecks = [
    {
      metric: "instructor_phrase_count_gt_0",
      weak_count:
        logs.filter((log) =>
          (log.quality_metrics?.instructor_phrase_count ?? 0) > 0
        ).length,
      total,
    },
    {
      metric: "instructor_ending_count_gt_0",
      weak_count:
        logs.filter((log) =>
          (log.quality_metrics?.instructor_ending_count ?? 0) > 0
        ).length,
      total,
    },
    {
      metric: "generic_template_risk_count_gt_0",
      weak_count:
        logs.filter((log) =>
          (log.quality_metrics?.generic_template_risk_count ?? 0) > 0
        ).length,
      total,
    },
    {
      metric: "duration_fit_not_ideal",
      weak_count:
        logs.filter((log) => log.quality_metrics?.duration_fit !== "ideal")
          .length,
      total,
    },
  ].filter((row) => row.weak_count > 0);

  return rows.concat(numericChecks).sort((a, b) =>
    b.weak_count - a.weak_count || a.metric.localeCompare(b.metric)
  );
}

function failureDiagnosis(
  logs: LoggedAttempt[],
): Array<
  {
    stage: string;
    rule: string;
    path: string;
    count: number;
    bottleneck: string;
  }
> {
  const grouped = new Map<string, {
    stage: string;
    rule: string;
    path: string;
    count: number;
  }>();
  for (const entry of logs) {
    const validation = entry.log.validation_error;
    if (!validation) {
      continue;
    }
    const stage = validation.stage;
    const rule = validation.rule;
    const path = validation.path ?? "";
    const key = `${stage}\t${rule}\t${path}`;
    const current = grouped.get(key) ?? { stage, rule, path, count: 0 };
    current.count += 1;
    grouped.set(key, current);
  }
  return [...grouped.values()]
    .sort((a, b) => b.count - a.count)
    .map((row) => ({
      ...row,
      bottleneck: classifyBottleneck(row.stage, row.rule),
    }));
}

function classifyBottleneck(stage: string, rule: string): string {
  if (stage === "json_parse") {
    return "parser/model returned invalid JSON";
  }
  if (rule === "daily_card_count" || rule.endsWith("_enum")) {
    return "structural output contract";
  }
  if (rule.includes("timeline") || rule === "scene_count") {
    return "prompt/schema completeness";
  }
  if (rule.includes("date")) {
    return "date targeting";
  }
  if (rule === "save_cta_cap" || rule.includes("instructor")) {
    return "quality guardrail";
  }
  return "validator or prompt mismatch";
}

function recommendation(
  successfulAttempts: AttemptSummary[],
  weakMetrics: Array<{ metric: string; weak_count: number; total: number }>,
  failureRows: Array<{
    stage: string;
    rule: string;
    path: string;
    count: number;
    bottleneck: string;
  }>,
  variantsForRun: VariantSummary[],
): string {
  if (successfulAttempts.length === 0) {
    return [
      "No production prompt, model, retry, token, temperature, or schema change is recommended from this run.",
      "First run the baseline with provider config so quality and failure evidence exists.",
    ].join(" ");
  }
  if (failureRows.some((row) => row.rule === "daily_card_count")) {
    return [
      "Investigate output contract pressure before changing production behavior.",
      "A local-only variant should test contract compaction or split-week day generation with before/after metrics.",
      "Do not ship request/prompt changes without explicit review.",
    ].join(" ");
  }
  const winningVariant = variantsForRun.find((variant) =>
    variant.decision.startsWith("candidate_keep_for_user_review")
  );
  if (winningVariant) {
    return [
      `${winningVariant.variant_name} improved the local objective enough to keep as a review candidate.`,
      "This is not a shippable production change; prepare before/after input/prompt impact and get explicit user review before altering production generation behavior.",
    ].join(" ");
  }
  const topWeakMetric = weakMetrics[0];
  if (topWeakMetric) {
    return [
      `The weakest logged quality metric is ${topWeakMetric.metric}.`,
      "Prototype the smallest prompt clarification that targets only that metric, then compare against this baseline before considering production changes.",
    ].join(" ");
  }
  return "Baseline quality did not surface an obvious weak deterministic metric. Review sampled outputs before proposing production changes.";
}

function sampledOutputMarkdown(output: GeneratedWeekOutput): string {
  return [
    "| Date | Pillar | Format | Title | Hook |",
    "| --- | --- | --- | --- | --- |",
    ...output.daily_cards.map((card) =>
      `| ${card.scheduled_date} | ${card.content_pillar} | ${card.format} | ${
        escapeMarkdownCell(card.title)
      } | ${escapeMarkdownCell(card.hook.slice(0, 120))} |`
    ),
  ].join("\n");
}

function cardSnapshot(card: GeneratedDailyCard): Record<string, unknown> {
  return {
    scheduled_date: card.scheduled_date,
    pillar: card.content_pillar,
    format: card.format,
    title: card.title,
    hook: card.hook,
    scene_count: card.scene_list.length,
    shot_timeline_count: card.shot_timeline.length,
    voiceover_timeline_count: card.voiceover_timeline.length,
    cta: card.cta,
    source_reference_ids: card.source_reference_ids,
  };
}

function distribution(values: number[]): {
  count: number;
  avg: number | null;
  p50: number | null;
  p95: number | null;
  min: number | null;
  max: number | null;
} {
  if (values.length === 0) {
    return { count: 0, avg: null, p50: null, p95: null, min: null, max: null };
  }
  const sorted = [...values].sort((a, b) => a - b);
  return {
    count: values.length,
    avg: Math.round(
      values.reduce((sum, value) => sum + value, 0) /
        values.length,
    ),
    p50: percentile(sorted, 50),
    p95: percentile(sorted, 95),
    min: sorted[0],
    max: sorted[sorted.length - 1],
  };
}

function percentile(sortedValues: number[], percentileValue: number): number {
  if (sortedValues.length === 0) {
    return 0;
  }
  const index = Math.ceil((percentileValue / 100) * sortedValues.length) - 1;
  return sortedValues[Math.max(0, Math.min(index, sortedValues.length - 1))];
}

function formatDistribution(value: unknown): string {
  if (!isRecord(value)) {
    return "n/a";
  }
  const count = numberValue(value.count);
  if (!count) {
    return "n/a";
  }
  return `avg ${formatNullable(value.avg)}, p50 ${
    formatNullable(value.p50)
  }, p95 ${formatNullable(value.p95)}, min ${formatNullable(value.min)}, max ${
    formatNullable(value.max)
  } (n=${count})`;
}

function tableFromCounts(counts: Record<string, number>): string {
  const rows = Object.entries(counts).sort((a, b) => b[1] - a[1]);
  return [
    "| Category | Count |",
    "| --- | ---: |",
    ...rows.map(([category, count]) => `| ${category} | ${count} |`),
  ].join("\n");
}

function countBy(values: string[]): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const value of values) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  return Object.fromEntries(
    Object.entries(counts).sort((a, b) => b[1] - a[1]),
  );
}

function averageNullable(values: number[]): number | null {
  if (values.length === 0) {
    return null;
  }
  return Math.round(
    values.reduce((sum, value) => sum + value, 0) /
      values.length,
  );
}

function minNullable(values: number[]): number | null {
  return values.length === 0 ? null : Math.min(...values);
}

function maxNullable(values: number[]): number | null {
  return values.length === 0 ? null : Math.max(...values);
}

function sumNullable(values: Array<number | null>): number | null {
  const numbers = values.filter(isNumber);
  if (numbers.length === 0) {
    return null;
  }
  return numbers.reduce((sum, value) => sum + value, 0);
}

function errorCategory(error: unknown): string | null {
  if (!error) {
    return null;
  }
  if (error instanceof Error) {
    return error.name || "error";
  }
  return "unknown_error";
}

function errorMessage(error: unknown): string | null {
  if (!error) {
    return null;
  }
  if (error instanceof Error) {
    return sanitizeStableMessage(error.message);
  }
  return sanitizeStableMessage(String(error));
}

function sanitizeStableMessage(message: string): string {
  return message.replace(/[^a-zA-Z0-9_:\-.]/g, "_").slice(0, 240);
}

async function writeJSON(path: string, value: unknown): Promise<void> {
  await Deno.writeTextFile(path, `${JSON.stringify(value, null, 2)}\n`);
}

async function appendJSONLine(path: string, value: unknown): Promise<void> {
  await Deno.writeTextFile(path, `${JSON.stringify(value)}\n`, {
    append: true,
  });
}

async function appendCSVLine(path: string, values: string[]): Promise<void> {
  await Deno.writeTextFile(
    path,
    `${values.map(csvCell).join(",")}\n`,
    { append: true },
  );
}

function csvCell(value: unknown): string {
  const text = String(value ?? "");
  return `"${text.replaceAll('"', '""')}"`;
}

function tsvCell(value: unknown): string {
  return String(value ?? "").replaceAll("\t", " ").replace(/\s+/g, " ").trim();
}

function uniqueStrings(values: string[]): string[] {
  return [...new Set(values)];
}

function parsePositiveInt(value: string | undefined): number | null {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return null;
  }
  return Math.trunc(parsed);
}

function parsePositiveFloat(value: string | undefined): number | null {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return null;
  }
  return parsed;
}

function round(value: number, digits: number): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function timestampSlug(date: Date): string {
  return date.toISOString().replaceAll(":", "").replaceAll(".", "");
}

function formatMs(ms: number): string {
  if (ms < 1000) {
    return `${ms}ms`;
  }
  return `${(ms / 1000).toFixed(1)}s`;
}

function formatNullable(value: unknown): string {
  if (typeof value === "number" && Number.isFinite(value)) {
    return String(value);
  }
  return "";
}

function env(name: string): string | undefined {
  return Deno.env.get(name)?.trim() || undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function isString(value: unknown): value is string {
  return typeof value === "string" && value.length > 0;
}

function isNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function numberValue(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function escapeMarkdownCell(value: string): string {
  return value.replaceAll("|", "\\|").replace(/\s+/g, " ").trim();
}

const fixture: GenerationInputSnapshot = {
  creator_id: "dbc7452d-c2ff-4d52-976f-734fad55f86b",
  week_start_date: "2026-08-24",
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
