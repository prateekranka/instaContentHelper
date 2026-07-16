// Day Generation Reliability Experiment Harness
//
// Dry-run-first harness for planning and measuring day-at-a-time
// generation reliability experiments against the hosted `generate-week`
// Supabase Edge Function (`generate_day` / `regenerate_day` actions).
// Dry-run is the default. The live path is implemented but gated behind
// `--live` AND `EXPERIMENT_LIVE_APPROVED=1`; do not run it without
// separate user approval (see
// docs/day-generation-reliability-experiment-plan.md).
//
// Modes:
//   --mode plan-regenerate-day  Plan N regenerate-day attempts with a guidance string.
//   --mode plan-generate-day    Plan N day-at-a-time generate_day attempts with a
//                               day brief (--brief). Add --optimize-brief to run the
//                               Karpathy-style loop: after EVERY run, keep the brief
//                               if it set a new best objective, otherwise revert to
//                               the best-known brief, then append one targeted
//                               instruction for the weakest quality category.
//                               Live env: MCO_SUPABASE_URL, MCO_SUPABASE_PUBLISHABLE_KEY,
//                               MCO_LIVE_CREATOR_ID, MCO_LIVE_DEVICE_TOKEN,
//                               MCO_LIVE_GENERATE_DATE (today or future).
//   --mode summary              Compute summary stats from a results JSONL file.
//   --mode evaluate-guidance    Evaluate guidance adherence of generated content.
//
// Dry-run is the default. Add `--live` to attempt live execution. Live
// execution requires EXPERIMENT_LIVE_APPROVED=1, all MCO_LIVE_* env vars,
// and --allow-net. Secret values are never printed.
//
// Env vars are read for the live path but secret values are never
// printed. Only presence (set/unset) is reported.
//
// Run (dry-run):
//   deno run --allow-env --allow-read --allow-write \
//     scripts/day-generation-reliability-experiment.ts \
//     --mode plan-regenerate-day --runs 20 --dry-run \
//     --guidance "Keep the hook under 2 seconds. Mention Bombay. Avoid weight-loss framing." \
//     --output .../regenerate-day-dry-run.jsonl
//
//   deno run --allow-env --allow-read --allow-write \
//     scripts/day-generation-reliability-experiment.ts \
//     --mode plan-generate-day --runs 20 --dry-run \
//     --brief "Back in Bombay, restarting gym routine." \
//     --output .../generate-day-dry-run.jsonl
//
//   deno run --allow-read --allow-write \
//     scripts/day-generation-reliability-experiment.ts \
//     --mode summary --input .../regenerate-day-dry-run.jsonl
//
//   deno run --allow-read --allow-write \
//     scripts/day-generation-reliability-experiment.ts \
//     --mode evaluate-guidance --input .../regenerate-day-dry-run.outputs.jsonl \
//     --required-terms Bombay,hook --forbidden-terms "weight loss,guaranteed" \
//     --target-sections daily_card,shot_timeline,voiceover_timeline

type Mode =
  | "plan-regenerate-day"
  | "plan-generate-day"
  | "summary"
  | "evaluate-guidance";
type JsonObject = Record<string, unknown>;
type ExperimentKind = "regenerate-day" | "generate-day";
type QualityCategory =
  | "opening_attention"
  | "retention_architecture"
  | "creator_voice_specificity"
  | "audience_goal_fit"
  | "save_share_trigger"
  | "accessibility_comprehension"
  | "format_production_fit";

type QualityCategoryScore = {
  score: number;
  weight: number;
  explanation: string;
};

type ResultRow = {
  run_index: number;
  experiment: ExperimentKind;
  started_at: string;
  finished_at: string;
  mode: "dry-run" | "live";
  planned: boolean;
  executed: boolean;
  provider: string;
  model: string;
  function_name: string;
  action: string;
  generation_id: string | null;
  weekly_plan_id: string | null;
  creator_id_present: boolean;
  scheduled_date: string | null;
  weekly_plan_id_present: boolean;
  guidance: string | null;
  request_payload_shape: string;
  http_status: number | null;
  duration_ms: number;
  poll_count: number | null;
  timed_out: boolean;
  validation_passed: boolean;
  failure_code: string;
  quality_version: string;
  quality_score: number;
  quality_breakdown: Record<QualityCategory, QualityCategoryScore>;
  hard_gate_blocking_failures: number;
  hard_gate_warnings: number;
  guidance_adherence_score: number | null;
  autoresearch_objective_score: number;
  autoresearch_decision: "observe_baseline" | "reject_failure";
  notes: string;
};

type OutputRow = {
  run_index: number;
  experiment: ExperimentKind;
  generated_content: string;
};

type ExperimentRunMeasurement = {
  httpStatus: number | null;
  durationMs: number;
  timedOut: boolean;
  validationPassed: boolean;
  failureCode: string;
  qualityScore: number;
  qualityBreakdown: Record<QualityCategory, QualityCategoryScore>;
  hardGateBlockingFailures: number;
  hardGateWarnings: number;
  autoresearchObjectiveScore: number;
  generatedContent: string;
  generationID: string | null;
  weeklyPlanID: string | null;
  pollCount: number | null;
  notes: string;
};

type LiveHTTPResult = {
  httpStatus: number | null;
  ok: boolean;
  data: JsonObject | null;
  rawText: string;
  durationMs: number;
  timedOut: boolean;
  networkError: string | null;
};

type LiveTerminalResult = {
  initialData: JsonObject | null;
  response: LiveHTTPResult;
  pollCount: number;
  finalData: JsonObject | null;
  notes: string;
};

type AutoresearchObservation = {
  run_index: number;
  experiment: ExperimentKind;
  observed_after_generation: true;
  observed_at: string;
  objective_score: number;
  previous_best_objective_score: number | null;
  improved_over_previous_best: boolean | null;
  diagnosis: string;
  failure_cluster: string | null;
  weakest_quality_category: QualityCategory | null;
  suggested_next_probe: string;
  allowed_to_change_generation_behavior: boolean;
  brief_used: string | null;
  next_brief: string | null;
  hypothesis: string | null;
};

type SummaryStats = {
  input_file: string;
  total_runs: number;
  executed_runs: number;
  valid_runs: number;
  failed_runs: number;
  failure_rate: number;
  duration_ms_min: number;
  duration_ms_avg: number;
  duration_ms_p50: number;
  duration_ms_p90: number;
  duration_ms_p95: number;
  duration_ms_max: number;
  quality_score_min: number;
  quality_score_avg: number;
  quality_score_p50: number;
  quality_score_p90: number;
  quality_score_max: number;
  guidance_adherence_avg: number | null;
  failure_codes: Record<string, number>;
};

type GuidanceEvaluation = {
  input_file: string;
  run_index: number | null;
  required_terms_total: number;
  required_terms_present: number;
  required_terms_missing: string[];
  forbidden_terms_total: number;
  forbidden_terms_present: number;
  forbidden_terms_violations: string[];
  target_sections_total: number;
  target_sections_present: number;
  target_sections_missing: string[];
  adherence_score: number;
  passed: boolean;
};

type GuidanceConfig = {
  requiredTerms: string[];
  forbiddenTerms: string[];
  targetSections: string[];
};

const DEFAULT_RUNS = 20;
const DEFAULT_OUTPUT_DIR =
  "build-logs/opencode-generation-reliability/experiment-harness";
const LIVE_APPROVAL_ENV = "EXPERIMENT_LIVE_APPROVED";
const QUALITY_VERSION = "creator_pre_publish_quality_v1";
const QUALITY_WEIGHTS: Record<QualityCategory, number> = {
  opening_attention: 20,
  retention_architecture: 15,
  creator_voice_specificity: 15,
  audience_goal_fit: 15,
  save_share_trigger: 15,
  accessibility_comprehension: 10,
  format_production_fit: 10,
};

const MAX_OPTIMIZED_BRIEF_LENGTH = 2_000;

const BRIEF_ADDENDA: Record<QualityCategory, string> = {
  opening_attention:
    "Open with a concrete visual hook in the first two seconds; the first line must create a curiosity gap without clickbait.",
  retention_architecture:
    "Structure scenes so each shot sets up the next; land one clear payoff in the final scene and make the ending loopable.",
  creator_voice_specificity:
    "Use lived, specific detail from this brief — name the place, the routine, the exact object; no generic fitness-creator phrasing.",
  audience_goal_fit:
    "State plainly why this day matters to a woman rebuilding fitness later in life; match one clear content job: connect, teach, or document.",
  save_share_trigger:
    "Give one practical detail worth saving or sending to a friend; keep the CTA natural, never templated.",
  accessibility_comprehension:
    "Make the Reel fully understandable on mute: tight on-screen text, readable density, and a complete silent version.",
  format_production_fit:
    "Keep it shootable in one session with minimal setups; respect the stated duration and keep the scene count realistic.",
};

const args = parseArgs(Deno.args);
const mode = args.mode as Mode;
const runs = parsePositiveInt(args.runs) ?? DEFAULT_RUNS;
const dryRun = args.live !== "1";
const guidance = args.guidance ?? "";
const output = args.output ?? defaultOutputPath(mode, dryRun);
const input = args.input ?? "";
const requiredTerms = parseTermList(args.requiredTerms);
const forbiddenTerms = parseTermList(args.forbiddenTerms);
const targetSections = parseTermList(args.targetSections);
const outputsPath = args.outputs ?? (output ? `${output}.outputs.jsonl` : "");
const seed = parsePositiveInt(args.seed) ?? 42;
const stopAfterFailures = parsePositiveInt(args.stopAfterFailures) ?? null;

await main();

async function main(): Promise<void> {
  switch (mode) {
    case "plan-regenerate-day":
      if (!guidance) {
        fail("--guidance is required for --mode plan-regenerate-day");
      }
      await runExperimentPlan(
        "regenerate-day",
        runs,
        dryRun,
        guidance,
        output,
        outputsPath,
        seed,
        stopAfterFailures,
      );
      break;
    case "plan-generate-day": {
      const brief = args.brief ?? guidance;
      if (!brief) {
        fail("--brief is required for --mode plan-generate-day");
      }
      await runExperimentPlan(
        "generate-day",
        runs,
        dryRun,
        brief,
        output,
        outputsPath,
        seed,
        stopAfterFailures,
        args.optimizeBrief === "1",
      );
      break;
    }
    case "summary":
      if (!input) {
        fail("--input is required for --mode summary");
      }
      await summarize(input);
      break;
    case "evaluate-guidance":
      if (!input) {
        fail("--input is required for --mode evaluate-guidance");
      }
      await evaluateGuidance(input, {
        requiredTerms,
        forbiddenTerms,
        targetSections,
      });
      break;
    default:
      fail(
        `--mode must be one of: plan-regenerate-day, plan-generate-day, summary, evaluate-guidance (got "${
          String(args.mode ?? "")
        }")`,
      );
  }
}

async function runExperimentPlan(
  experiment: ExperimentKind,
  runCount: number,
  isDryRun: boolean,
  guidanceString: string,
  resultsPath: string,
  companionOutputsPath: string,
  rngSeed: number,
  stopAfterFailureCount: number | null,
  optimizeBrief = false,
): Promise<void> {
  const rng = mulberry32(rngSeed);
  const liveEnv = readLiveEnv(experiment);
  const action = experiment === "generate-day"
    ? "generate_day"
    : "regenerate_day";
  const functionName = "generate-week";
  const requestShape = describeRequestShape(experiment);

  if (!isDryRun) {
    if (Deno.env.get(LIVE_APPROVAL_ENV) !== "1") {
      fail(
        `Live mode requires ${LIVE_APPROVAL_ENV}=1 (separate user approval). This pass never sets it. Re-run with --dry-run or omit --live.`,
      );
    }
    if (!liveEnv.hasAllRequired) {
      fail(
        `Live mode requires env vars set: ${
          liveEnv.missingNames.join(", ")
        }. Values are not printed.`,
      );
    }
    const liveEnvErrors = validateLiveEnv(experiment, liveEnv);
    if (liveEnvErrors.length > 0) {
      fail(`Live mode env validation failed: ${liveEnvErrors.join("; ")}`);
    }
  }

  await ensureDir(dirname(resultsPath));
  await Deno.writeTextFile(resultsPath, "");
  if (companionOutputsPath) {
    await ensureDir(dirname(companionOutputsPath));
    await Deno.writeTextFile(companionOutputsPath, "");
  }
  const autoresearchPath = `${resultsPath}.autoresearch.jsonl`;
  await Deno.writeTextFile(autoresearchPath, "");

  console.log(
    `plan ${experiment}: runs=${runCount} mode=${
      isDryRun ? "dry-run" : "live"
    } output=${resultsPath}`,
  );

  let bestObjectiveScore: number | null = null;
  let consecutiveFailures = 0;
  let rowsWritten = 0;
  let currentBrief = guidanceString;
  let bestBrief = guidanceString;
  for (let index = 0; index < runCount; index += 1) {
    const startedAt = new Date().toISOString();
    logExperimentProgress(
      `run ${index + 1}/${runCount} starting (${experiment}, ${
        isDryRun ? "dry-run" : "live"
      })${optimizeBrief ? ` brief_chars=${currentBrief.length}` : ""}`,
    );
    const measurement = isDryRun
      ? mockRunResult(experiment, index, rng)
      : await liveRunResult(experiment, currentBrief, liveEnv, index + 1);
    const row: ResultRow = {
      run_index: index + 1,
      experiment,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      mode: isDryRun ? "dry-run" : "live",
      planned: true,
      executed: !isDryRun,
      provider: isDryRun ? "mock" : "supabase-edge-function",
      model: "managed-by-edge-function",
      function_name: functionName,
      action,
      generation_id: measurement.generationID,
      weekly_plan_id: measurement.weeklyPlanID,
      creator_id_present: liveEnv.creatorIdPresent,
      scheduled_date: liveEnv.regenerateDate ?? "2026-08-25",
      weekly_plan_id_present: liveEnv.weeklyPlanIdPresent,
      guidance: currentBrief,
      request_payload_shape: requestShape,
      http_status: measurement.httpStatus,
      duration_ms: measurement.durationMs,
      poll_count: measurement.pollCount,
      timed_out: measurement.timedOut,
      validation_passed: measurement.validationPassed,
      failure_code: measurement.failureCode,
      quality_version: QUALITY_VERSION,
      quality_score: measurement.qualityScore,
      quality_breakdown: measurement.qualityBreakdown,
      hard_gate_blocking_failures: measurement.hardGateBlockingFailures,
      hard_gate_warnings: measurement.hardGateWarnings,
      guidance_adherence_score: null,
      autoresearch_objective_score: measurement.autoresearchObjectiveScore,
      autoresearch_decision: measurement.validationPassed &&
          measurement.hardGateBlockingFailures === 0
        ? "observe_baseline"
        : "reject_failure",
      notes: measurement.notes,
    };

    await appendJsonl(resultsPath, row);
    rowsWritten += 1;
    logExperimentProgress(
      `run ${
        index + 1
      }/${runCount} result: passed=${row.validation_passed} status=${
        row.failure_code || "ok"
      } duration_ms=${row.duration_ms} generation_id=${
        row.generation_id ?? "none"
      } poll_count=${row.poll_count ?? 0}`,
    );
    // Karpathy-style per-run optimization: after every generation, keep the
    // brief when it set a new best objective, otherwise revert to the best
    // known brief, then propose exactly one new change targeting the weakest
    // rubric category. One hypothesis per run, measured on the next run.
    let briefStep: BriefOptimizationStep | null = null;
    if (optimizeBrief && experiment === "generate-day") {
      const passedRun = row.validation_passed &&
        row.hard_gate_blocking_failures === 0;
      const improvedOverBest = passedRun &&
        (bestObjectiveScore === null ||
          row.autoresearch_objective_score > bestObjectiveScore);
      if (improvedOverBest) {
        bestBrief = currentBrief;
      }
      briefStep = proposeNextBrief(bestBrief, currentBrief, row);
    }

    const observation = autoresearchAfterGeneration(
      row,
      bestObjectiveScore,
      briefStep
        ? {
          briefUsed: currentBrief,
          nextBrief: briefStep.nextBrief,
          hypothesis: briefStep.hypothesis,
        }
        : undefined,
    );
    await appendJsonl(autoresearchPath, observation);
    logExperimentProgress(
      `run ${
        index + 1
      }/${runCount} autoresearch: objective=${observation.objective_score} failure_cluster=${
        observation.failure_cluster ?? "none"
      } diagnosis=${observation.diagnosis}`,
    );
    if (briefStep) {
      logExperimentProgress(
        `run ${index + 1}/${runCount} optimize: ${briefStep.hypothesis}`,
      );
      currentBrief = briefStep.nextBrief;
    }
    if (
      row.validation_passed &&
      row.hard_gate_blocking_failures === 0 &&
      (bestObjectiveScore === null ||
        row.autoresearch_objective_score > bestObjectiveScore)
    ) {
      bestObjectiveScore = row.autoresearch_objective_score;
    }

    if (companionOutputsPath) {
      const outputRow: OutputRow = {
        run_index: index + 1,
        experiment,
        generated_content: measurement.generatedContent,
      };
      await appendJsonl(companionOutputsPath, outputRow);
      logExperimentProgress(
        `run ${index + 1}/${runCount} wrote companion output row`,
      );
    }

    consecutiveFailures = row.validation_passed ? 0 : consecutiveFailures + 1;
    if (
      stopAfterFailureCount !== null &&
      consecutiveFailures >= stopAfterFailureCount
    ) {
      console.log(
        `stopping after ${consecutiveFailures} consecutive failed run(s); requested stop-after-failures=${stopAfterFailureCount}`,
      );
      break;
    }
  }

  console.log(
    `wrote ${rowsWritten} rows to ${resultsPath}` +
      (companionOutputsPath ? `, ${companionOutputsPath}` : "") +
      ` and ${autoresearchPath}`,
  );
}

function autoresearchAfterGeneration(
  row: ResultRow,
  previousBestObjectiveScore: number | null,
  optimization?: {
    briefUsed: string;
    nextBrief: string;
    hypothesis: string;
  },
): AutoresearchObservation {
  const weakest = weakestQualityCategory(row.quality_breakdown);
  const improved = previousBestObjectiveScore === null
    ? null
    : row.autoresearch_objective_score > previousBestObjectiveScore;
  return {
    run_index: row.run_index,
    experiment: row.experiment,
    observed_after_generation: true,
    observed_at: new Date().toISOString(),
    objective_score: row.autoresearch_objective_score,
    previous_best_objective_score: previousBestObjectiveScore,
    improved_over_previous_best: improved,
    diagnosis: autoresearchDiagnosis(row, weakest),
    failure_cluster: row.validation_passed
      ? null
      : row.failure_code || "unknown_failure",
    weakest_quality_category: weakest,
    suggested_next_probe: suggestedNextProbe(row, weakest),
    allowed_to_change_generation_behavior: Boolean(optimization),
    brief_used: optimization?.briefUsed ?? null,
    next_brief: optimization?.nextBrief ?? null,
    hypothesis: optimization?.hypothesis ?? null,
  };
}

type BriefOptimizationStep = {
  nextBrief: string;
  hypothesis: string;
};

/**
 * One-hypothesis-per-run brief optimizer. The only lever the client controls
 * without redeploying the edge function is the day brief itself, so each run
 * appends a single targeted instruction for the weakest rubric category to the
 * best-known brief. Improvements are kept (the addendum stays in bestBrief on
 * the next improvement); regressions are reverted because the next step always
 * rebuilds from bestBrief. Validation failures never mutate the brief.
 */
function proposeNextBrief(
  bestBrief: string,
  currentBrief: string,
  row: ResultRow,
): BriefOptimizationStep {
  if (!row.validation_passed) {
    return {
      nextBrief: bestBrief,
      hypothesis: `Run failed validation (${
        row.failure_code || "unknown_failure"
      }); not a quality signal — reverting to best-known brief unchanged.`,
    };
  }
  if (row.hard_gate_blocking_failures > 0) {
    return {
      nextBrief: bestBrief,
      hypothesis:
        "Blocking hard gate failed; do not optimize around it — reverting to best-known brief.",
    };
  }

  const ranked = (Object.keys(row.quality_breakdown) as QualityCategory[])
    .sort((a, b) =>
      row.quality_breakdown[a].score - row.quality_breakdown[b].score
    );
  for (const category of ranked) {
    const addendum = BRIEF_ADDENDA[category];
    if (bestBrief.includes(addendum)) {
      continue;
    }
    const candidate = `${bestBrief}\n${addendum}`;
    if (candidate.length > MAX_OPTIMIZED_BRIEF_LENGTH) {
      return {
        nextBrief: bestBrief,
        hypothesis:
          `Brief is at the ${MAX_OPTIMIZED_BRIEF_LENGTH}-char cap; keeping best-known brief instead of appending for ${category}.`,
      };
    }
    return {
      nextBrief: candidate,
      hypothesis: `Weakest rubric category is ${category} (score ${
        row.quality_breakdown[category].score
      }); appending one targeted instruction for it${
        currentBrief === bestBrief
          ? ""
          : " on top of the best-known brief (previous change reverted)"
      }.`,
    };
  }

  return {
    nextBrief: bestBrief,
    hypothesis:
      "All category addenda already present in best-known brief; holding steady to collect observations.",
  };
}

function weakestQualityCategory(
  breakdown: Record<QualityCategory, QualityCategoryScore>,
): QualityCategory | null {
  let weakest: QualityCategory | null = null;
  let weakestScore = Number.POSITIVE_INFINITY;
  for (const category of Object.keys(breakdown) as QualityCategory[]) {
    if (breakdown[category].score < weakestScore) {
      weakest = category;
      weakestScore = breakdown[category].score;
    }
  }
  return weakest;
}

function autoresearchDiagnosis(
  row: ResultRow,
  weakest: QualityCategory | null,
): string {
  if (!row.validation_passed) {
    return row.timed_out
      ? "Generation timed out; diagnose latency, queue, provider, or request-size logs before tuning quality."
      : `Generation failed validation with ${
        row.failure_code || "unknown_failure"
      }; inspect validation detail logs before changing prompts.`;
  }
  if (row.hard_gate_blocking_failures > 0) {
    return "Blocking hard gate failed; safety, brand, rights, factual support, or platform eligibility must be fixed before scoring quality wins.";
  }
  if (row.quality_score < 75) {
    return `Valid generation but quality is below threshold; weakest rubric category is ${
      weakest ?? "unknown"
    }.`;
  }
  if (row.autoresearch_objective_score >= 90) {
    return "Strong valid generation; preserve current behavior and use as a positive baseline example.";
  }
  return `Acceptable generation; watch weakest rubric category ${
    weakest ?? "unknown"
  } and latency before proposing a change.`;
}

function suggestedNextProbe(
  row: ResultRow,
  weakest: QualityCategory | null,
): string {
  if (row.timed_out) {
    return "Compare hosted lifecycle/request-size logs for this run against faster successful runs.";
  }
  if (!row.validation_passed) {
    return "Inspect validation failure detail and output shape before proposing any generation change.";
  }
  if (row.hard_gate_blocking_failures > 0) {
    return "Identify the blocking hard gate and rewrite the content or source support; do not optimize around it.";
  }
  switch (weakest) {
    case "opening_attention":
      return "Probe first-frame/hook packaging without changing the full prompt contract.";
    case "retention_architecture":
      return "Probe scene progression and payoff structure.";
    case "creator_voice_specificity":
      return "Probe reference selection and creator voice examples.";
    case "audience_goal_fit":
      return "Probe metric-goal and target-viewer specificity.";
    case "save_share_trigger":
      return "Probe real save/send utility and CTA naturalness.";
    case "accessibility_comprehension":
      return "Probe caption, on-screen text density, and silent-mode clarity.";
    case "format_production_fit":
      return "Probe duration, shot count, and shootability constraints.";
    default:
      return "No probe needed; keep collecting observations.";
  }
}

async function summarize(resultsPath: string): Promise<void> {
  const rows = await readJsonl<ResultRow>(resultsPath);
  const stats = computeSummary(resultsPath, rows);
  const summaryPath = `${resultsPath}.summary.md`;
  await Deno.writeTextFile(summaryPath, renderSummary(stats));
  console.log(JSON.stringify(stats, null, 2));
  console.log(`summary written to ${summaryPath}`);
}

async function evaluateGuidance(
  inputPath: string,
  config: GuidanceConfig,
): Promise<void> {
  const evaluations: GuidanceEvaluation[] = [];
  const raw = await Deno.readTextFile(inputPath);
  const lines = raw.split(/\r?\n/).filter((line) => line.trim().length > 0);

  for (const line of lines) {
    let parsed: unknown;
    try {
      parsed = JSON.parse(line);
    } catch (error) {
      fail(`failed to parse JSONL line in ${inputPath}: ${shortError(error)}`);
    }
    const content = extractContent(parsed);
    const runIndex = extractRunIndex(parsed);
    evaluations.push(evaluateContent(inputPath, runIndex, content, config));
  }

  const reportPath = `${inputPath}.guidance.jsonl`;
  await Deno.writeTextFile(reportPath, "");
  for (const evaluation of evaluations) {
    await appendJsonl(reportPath, evaluation);
  }
  const aggregatePath = `${inputPath}.guidance-summary.md`;
  await Deno.writeTextFile(aggregatePath, renderGuidanceAggregate(evaluations));
  console.log(
    JSON.stringify(
      { evaluations: evaluations.length, report: reportPath },
      null,
      2,
    ),
  );
}

function evaluateContent(
  inputFile: string,
  runIndex: number | null,
  content: string,
  config: GuidanceConfig,
): GuidanceEvaluation {
  const lower = content.toLowerCase();
  const requiredMissing: string[] = [];
  let requiredPresent = 0;
  for (const term of config.requiredTerms) {
    if (lower.includes(term.toLowerCase())) {
      requiredPresent += 1;
    } else {
      requiredMissing.push(term);
    }
  }
  const forbiddenViolations: string[] = [];
  let forbiddenPresent = 0;
  for (const term of config.forbiddenTerms) {
    if (lower.includes(term.toLowerCase())) {
      forbiddenPresent += 1;
      forbiddenViolations.push(term);
    }
  }
  const sectionsMissing: string[] = [];
  let sectionsPresent = 0;
  for (const section of config.targetSections) {
    if (
      lower.includes(`"${section.toLowerCase()}"`) ||
      lower.includes(section.toLowerCase())
    ) {
      sectionsPresent += 1;
    } else {
      sectionsMissing.push(section);
    }
  }

  const requiredRatio = config.requiredTerms.length === 0
    ? 1
    : requiredPresent / config.requiredTerms.length;
  const forbiddenRatio = config.forbiddenTerms.length === 0
    ? 1
    : 1 - forbiddenPresent / config.forbiddenTerms.length;
  const sectionRatio = config.targetSections.length === 0
    ? 1
    : sectionsPresent / config.targetSections.length;
  const adherence = Math.round(
    (requiredRatio * 0.5 + forbiddenRatio * 0.3 + sectionRatio * 0.2) * 100,
  );
  const passed = requiredMissing.length === 0 &&
    forbiddenViolations.length === 0;

  return {
    input_file: inputFile,
    run_index: runIndex,
    required_terms_total: config.requiredTerms.length,
    required_terms_present: requiredPresent,
    required_terms_missing: requiredMissing,
    forbidden_terms_total: config.forbiddenTerms.length,
    forbidden_terms_present: forbiddenPresent,
    forbidden_terms_violations: forbiddenViolations,
    target_sections_total: config.targetSections.length,
    target_sections_present: sectionsPresent,
    target_sections_missing: sectionsMissing,
    adherence_score: adherence,
    passed,
  };
}

type LiveEnv = {
  hasAllRequired: boolean;
  missingNames: string[];
  supabaseURL: string | null;
  publishableKey: string | null;
  deviceToken: string | null;
  creatorID: string | null;
  weeklyPlanID: string | null;
  creatorIdPresent: boolean;
  weeklyPlanIdPresent: boolean;
  regenerateDate: string | null;
  requestTimeoutMs: number;
  pollTimeoutMs: number;
};

function readLiveEnv(experiment: ExperimentKind): LiveEnv {
  const baseRequired = [
    "MCO_SUPABASE_URL",
    "MCO_SUPABASE_PUBLISHABLE_KEY",
    "MCO_LIVE_CREATOR_ID",
    "MCO_LIVE_DEVICE_TOKEN",
  ];
  const required = experiment === "generate-day"
    ? [...baseRequired, "MCO_LIVE_GENERATE_DATE"]
    : [
      ...baseRequired,
      "MCO_LIVE_WEEKLY_PLAN_ID",
      "MCO_LIVE_REGENERATE_DATE",
    ];
  const missing = required.filter((name) => !Deno.env.get(name));
  const requestTimeoutMs =
    parsePositiveInt(Deno.env.get("MCO_LIVE_REQUEST_TIMEOUT_MS")) ??
      240_000;
  const pollTimeoutMs =
    parsePositiveInt(Deno.env.get("MCO_LIVE_POLL_TIMEOUT_MS")) ?? 600_000;
  return {
    hasAllRequired: missing.length === 0,
    missingNames: missing,
    supabaseURL: envValue("MCO_SUPABASE_URL"),
    publishableKey: envValue("MCO_SUPABASE_PUBLISHABLE_KEY"),
    deviceToken: envValue("MCO_LIVE_DEVICE_TOKEN"),
    creatorID: envValue("MCO_LIVE_CREATOR_ID"),
    weeklyPlanID: envValue("MCO_LIVE_WEEKLY_PLAN_ID"),
    creatorIdPresent: Boolean(Deno.env.get("MCO_LIVE_CREATOR_ID")),
    weeklyPlanIdPresent: Boolean(Deno.env.get("MCO_LIVE_WEEKLY_PLAN_ID")),
    regenerateDate: experiment === "generate-day"
      ? envValue("MCO_LIVE_GENERATE_DATE")
      : envValue("MCO_LIVE_REGENERATE_DATE"),
    requestTimeoutMs,
    pollTimeoutMs,
  };
}

function describeRequestShape(
  experiment: ExperimentKind,
): string {
  if (experiment === "generate-day") {
    return '{"action":"generate_day","creator_id":uuid,"scheduled_date":YYYY-MM-DD,"day_brief":string,"response_mode":"async","client_context":{...}}';
  }
  return '{"action":"regenerate_day","creator_id":uuid,"weekly_plan_id":uuid,"scheduled_date":YYYY-MM-DD,"preserve_manual_edits":true,"response_mode":"async","day_guidance":string,"client_context":{...}}';
}

type MockResult = ExperimentRunMeasurement;

type LiveQualityAssessment = {
  qualityScore: number;
  qualityBreakdown: Record<QualityCategory, QualityCategoryScore>;
  hardGateBlockingFailures: number;
  hardGateWarnings: number;
  autoresearchObjectiveScore: number;
};

type LivePayloadOptions = {
  experiment: ExperimentKind;
  guidanceString: string;
  liveEnv: LiveEnv;
};

type LiveValidationResult = {
  passed: boolean;
  failureCode: string;
};

type LiveStatusKind =
  | "running"
  | "success"
  | "partial"
  | "failed"
  | "cancelled"
  | "unknown";

async function liveRunResult(
  experiment: ExperimentKind,
  guidanceString: string,
  liveEnv: LiveEnv,
  runIndex: number,
): Promise<ExperimentRunMeasurement> {
  const startedMs = Date.now();
  const payload = liveRequestPayload({ experiment, guidanceString, liveEnv });
  logExperimentProgress(
    `run ${runIndex} invoking generate-week action=${
      stringValue(payload.action) ??
        (experiment === "generate-day" ? "generate_day" : "regenerate_day")
    } scheduled_date=${stringValue(payload.scheduled_date) ?? "n/a"}`,
  );
  const initial = await invokeLiveGenerateWeek(liveEnv, payload);
  logExperimentProgress(
    `run ${runIndex} initial response: http=${
      initial.httpStatus ?? "none"
    } ok=${initial.ok} timed_out=${initial.timedOut} ${
      summarizeLiveStatus(initial.data)
    }`,
  );
  const terminal = await waitForLiveTerminal(
    experiment,
    initial,
    liveEnv,
    runIndex,
  );
  const durationMs = Date.now() - startedMs;
  const finalResponse = terminal.response;
  const finalData = terminal.finalData;
  const generationID = stringValue(terminal.initialData?.generation_id) ??
    stringValue(finalData?.generation_id);
  const weeklyPlanID = stringValue(terminal.initialData?.weekly_plan_id) ??
    stringValue(finalData?.weekly_plan_id);
  const validation = validateLiveGeneration(
    finalData,
    finalResponse,
  );
  logExperimentProgress(
    `run ${runIndex} terminal response: http=${
      finalResponse.httpStatus ?? "none"
    } passed=${validation.passed} failure=${
      validation.failureCode || "none"
    } polls=${terminal.pollCount} ${summarizeLiveStatus(finalData)}`,
  );
  const assessment = assessLiveQuality(
    finalData,
    validation,
    durationMs,
    finalResponse.timedOut,
  );
  const generatedContent = terminal.initialData || finalData
    ? JSON.stringify({
      initial: compactObject({
        generation_id: generationID ?? undefined,
        weekly_plan_id: weeklyPlanID ?? undefined,
        status: stringValue(terminal.initialData?.status) ?? undefined,
        poll_after_seconds:
          numberValue(terminal.initialData?.poll_after_seconds) ??
            undefined,
      }),
      final: finalData,
    })
    : finalResponse.rawText ||
      JSON.stringify({ error: finalResponse.networkError ?? "empty_response" });

  return {
    httpStatus: finalResponse.httpStatus,
    durationMs,
    timedOut: finalResponse.timedOut,
    validationPassed: validation.passed,
    failureCode: validation.failureCode,
    qualityScore: assessment.qualityScore,
    qualityBreakdown: assessment.qualityBreakdown,
    hardGateBlockingFailures: assessment.hardGateBlockingFailures,
    hardGateWarnings: assessment.hardGateWarnings,
    autoresearchObjectiveScore: assessment.autoresearchObjectiveScore,
    generatedContent,
    generationID,
    weeklyPlanID,
    pollCount: terminal.pollCount,
    notes:
      `live: ${terminal.notes}; local rubric scores returned JSON only; hosted generation_ai_attempt logs remain source of token, provider, and deterministic pre-publish quality telemetry`,
  };
}

function liveRequestPayload(options: LivePayloadOptions): JsonObject {
  const creatorID = requireLiveValue(
    "MCO_LIVE_CREATOR_ID",
    options.liveEnv.creatorID,
  );

  if (options.experiment === "generate-day") {
    const scheduledDate = requireLiveValue(
      "MCO_LIVE_GENERATE_DATE",
      options.liveEnv.regenerateDate,
    );
    return compactObject({
      action: "generate_day",
      creator_id: creatorID,
      scheduled_date: scheduledDate,
      day_brief: options.guidanceString,
      response_mode: "async",
      client_context: compactObject({
        ui_surface: "day_generation_reliability_experiment",
        action: "generate_day",
        scheduled_date: scheduledDate,
        day_guidance_present: options.guidanceString.trim().length > 0,
        day_guidance_chars: options.guidanceString.trim().length,
      }),
    });
  }

  const scheduledDate = requireLiveValue(
    "MCO_LIVE_REGENERATE_DATE",
    options.liveEnv.regenerateDate,
  );
  return compactObject({
    action: "regenerate_day",
    creator_id: creatorID,
    weekly_plan_id: requireLiveValue(
      "MCO_LIVE_WEEKLY_PLAN_ID",
      options.liveEnv.weeklyPlanID,
    ),
    scheduled_date: scheduledDate,
    preserve_manual_edits: true,
    response_mode: "async",
    day_guidance: options.guidanceString,
    client_context: compactObject({
      ui_surface: "day_generation_reliability_experiment",
      action: "regenerate_day",
      scheduled_date: scheduledDate,
      day_guidance_present: options.guidanceString.trim().length > 0,
      day_guidance_chars: options.guidanceString.trim().length,
    }),
  });
}

async function waitForLiveTerminal(
  experiment: ExperimentKind,
  initial: LiveHTTPResult,
  liveEnv: LiveEnv,
  runIndex: number,
): Promise<LiveTerminalResult> {
  if (initial.timedOut || !initial.ok || !initial.data) {
    logExperimentProgress(
      `run ${runIndex} stopped before polling: http=${
        initial.httpStatus ?? "none"
      } timed_out=${initial.timedOut}`,
    );
    return {
      initialData: initial.data,
      response: initial,
      pollCount: 0,
      finalData: initial.data,
      notes: `initial_http_status=${initial.httpStatus ?? "none"} poll_count=0`,
    };
  }

  const initialKind = liveStatusKind(experiment, initial.data);
  if (isTerminalLiveStatus(initialKind)) {
    logExperimentProgress(
      `run ${runIndex} initial response already terminal: ${initialKind} ${
        summarizeLiveStatus(initial.data)
      }`,
    );
    return {
      initialData: initial.data,
      response: initial,
      pollCount: 0,
      finalData: initial.data,
      notes: `initial_http_status=${initial.httpStatus} final_status=${
        stringValue(initial.data.status) ?? "unknown"
      } poll_count=0`,
    };
  }

  const generationID = stringValue(initial.data.generation_id);
  if (!generationID) {
    logExperimentProgress(
      `run ${runIndex} initial response missing generation_id; cannot poll`,
    );
    return {
      initialData: initial.data,
      response: initial,
      pollCount: 0,
      finalData: initial.data,
      notes: `initial_http_status=${initial.httpStatus} missing_generation_id`,
    };
  }

  const deadline = Date.now() + liveEnv.pollTimeoutMs;
  let pollAfterMs = clampPollAfterMs(
    numberValue(initial.data.poll_after_seconds),
  );
  let pollCount = 0;
  let last = initial;
  logExperimentProgress(
    `run ${runIndex} polling generation_id=${generationID} every ${
      Math.round(pollAfterMs / 1000)
    }s until terminal status`,
  );

  while (Date.now() < deadline) {
    await sleep(pollAfterMs);
    pollCount += 1;
    logExperimentProgress(
      `run ${runIndex} poll ${pollCount} requesting status for generation_id=${generationID}`,
    );
    last = await invokeLiveGenerateWeek(liveEnv, {
      action: "status",
      generation_id: generationID,
      creator_id: requireLiveValue("MCO_LIVE_CREATOR_ID", liveEnv.creatorID),
    });

    if (last.timedOut || !last.ok || !last.data) {
      logExperimentProgress(
        `run ${runIndex} poll ${pollCount} failed: http=${
          last.httpStatus ?? "none"
        } timed_out=${last.timedOut} error=${
          last.networkError ?? "http_or_json"
        }`,
      );
      return {
        initialData: initial.data,
        response: last,
        pollCount,
        finalData: last.data,
        notes: `initial_http_status=${initial.httpStatus} final_http_status=${
          last.httpStatus ?? "none"
        } poll_count=${pollCount}`,
      };
    }

    const statusKind = liveStatusKind(experiment, last.data);
    logExperimentProgress(
      `run ${runIndex} poll ${pollCount}: kind=${statusKind} ${
        summarizeLiveStatus(last.data)
      } next_poll=${
        Math.round(
          clampPollAfterMs(numberValue(last.data.poll_after_seconds)) / 1000,
        )
      }s`,
    );
    if (isTerminalLiveStatus(statusKind)) {
      return {
        initialData: initial.data,
        response: last,
        pollCount,
        finalData: last.data,
        notes:
          `initial_http_status=${initial.httpStatus} final_http_status=${last.httpStatus} final_status=${
            stringValue(last.data.status) ?? "unknown"
          } poll_count=${pollCount}`,
      };
    }

    pollAfterMs = clampPollAfterMs(numberValue(last.data.poll_after_seconds));
  }

  logExperimentProgress(
    `run ${runIndex} polling timed out after ${pollCount} poll(s); ${
      summarizeLiveStatus(last.data)
    }`,
  );
  return {
    response: {
      ...last,
      ok: false,
      timedOut: true,
      data: last.data ?? { error: "poll_timeout" },
      networkError: "poll_timeout",
    },
    pollCount,
    initialData: initial.data,
    finalData: last.data,
    notes: `poll_timeout_ms=${liveEnv.pollTimeoutMs} poll_count=${pollCount}`,
  };
}

async function invokeLiveGenerateWeek(
  liveEnv: LiveEnv,
  body: JsonObject,
): Promise<LiveHTTPResult> {
  const startedMs = Date.now();
  const controller = new AbortController();
  const timeoutID = setTimeout(
    () => controller.abort(),
    liveEnv.requestTimeoutMs,
  );
  try {
    const response = await fetch(liveGenerateWeekURL(liveEnv), {
      method: "POST",
      headers: liveHeaders(liveEnv),
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    const rawText = await response.text();
    return {
      httpStatus: response.status,
      ok: response.ok,
      data: parseJsonObject(rawText),
      rawText,
      durationMs: Date.now() - startedMs,
      timedOut: false,
      networkError: null,
    };
  } catch (error) {
    const timedOut = isAbortError(error);
    return {
      httpStatus: null,
      ok: false,
      data: {
        error: timedOut ? "request_timeout" : "network_error",
        message: shortError(error),
      },
      rawText: "",
      durationMs: Date.now() - startedMs,
      timedOut,
      networkError: timedOut ? "request_timeout" : shortError(error),
    };
  } finally {
    clearTimeout(timeoutID);
  }
}

function validateLiveGeneration(
  data: JsonObject | null,
  response: LiveHTTPResult,
): LiveValidationResult {
  if (response.timedOut) {
    return { passed: false, failureCode: "timeout" };
  }
  if (!response.ok) {
    return {
      passed: false,
      failureCode: stringValue(data?.error) ??
        `http_${response.httpStatus ?? "none"}`,
    };
  }
  if (!data) {
    return { passed: false, failureCode: "invalid_json_response" };
  }

  const status = stringValue(data.status);
  if (
    (status === "draft" || status === "completed") &&
    isRecord(data.daily_card)
  ) {
    return { passed: true, failureCode: "" };
  }
  if (status === "failed") {
    return {
      passed: false,
      failureCode: stringValue(data.error) ?? "generation_failed",
    };
  }
  return { passed: false, failureCode: "invalid_generated_day" };
}

function assessLiveQuality(
  data: JsonObject | null,
  validation: LiveValidationResult,
  durationMs: number,
  timedOut: boolean,
): LiveQualityAssessment {
  if (!validation.passed || !data) {
    const qualityBreakdown = zeroQualityBreakdown(
      "Live generation did not pass validation.",
    );
    return {
      qualityScore: 0,
      qualityBreakdown,
      hardGateBlockingFailures: 1,
      hardGateWarnings: 0,
      autoresearchObjectiveScore: 0,
    };
  }

  const content = JSON.stringify(data);
  const qualityBreakdown: Record<QualityCategory, QualityCategoryScore> = {
    opening_attention: liveQualityCategory(
      content,
      [
        "hook",
        "cover_text",
        "on_screen_text",
        "0:00",
        "0-3",
      ],
      "Checks whether the returned JSON exposes hook and first-frame packaging.",
    ),
    retention_architecture: liveQualityCategory(
      content,
      [
        "shot_timeline",
        "voiceover_timeline",
        "duration_seconds",
        "scene_list",
        "silent_version_timeline",
      ],
      "Checks whether the returned JSON exposes scene progression and timeline structure.",
    ),
    creator_voice_specificity: liveQualityCategory(
      content,
      [
        "source_note",
        "brand_event_notes",
        "assumptions",
        "script",
        "caption",
      ],
      "Checks whether the returned JSON includes creator-specific writing surfaces.",
    ),
    audience_goal_fit: liveQualityCategory(
      content,
      [
        "growth_job",
        "content_pillar",
        "why_today",
        "save_share_reason",
        "creator_fit_score",
      ],
      "Checks whether the returned JSON includes goal, pillar, and fit fields.",
    ),
    save_share_trigger: liveQualityCategory(
      content,
      [
        "save_share_reason",
        "cta",
        "caption",
        "backup_caption_only",
      ],
      "Checks whether the returned JSON includes save/share and CTA surfaces.",
    ),
    accessibility_comprehension: liveQualityCategory(
      content,
      [
        "on_screen_text",
        "silent_version_timeline",
        "caption",
        "no_voiceover_version",
      ],
      "Checks whether the returned JSON includes silent-mode and caption surfaces.",
    ),
    format_production_fit: liveQualityCategory(
      content,
      [
        "format",
        "duration_seconds",
        "shootability",
        "estimated_shoot_minutes",
        "post_instructions",
      ],
      "Checks whether the returned JSON includes shootability and production-fit fields.",
    ),
  };
  const qualityScore = weightedQualityScore(qualityBreakdown);
  const latencyScore = timedOut
    ? 0
    : Math.max(0, Math.round(100 - durationMs / 1_800));
  const hardGateWarnings = qualityScore < 75 ? 1 : 0;
  const autoresearchObjectiveScore = Math.round(
    35 +
      Math.min(35, qualityScore * 0.35) +
      Math.min(20, latencyScore * 0.2) +
      10,
  );

  return {
    qualityScore,
    qualityBreakdown,
    hardGateBlockingFailures: 0,
    hardGateWarnings,
    autoresearchObjectiveScore,
  };
}

function liveQualityCategory(
  content: string,
  markers: string[],
  explanation: string,
): QualityCategoryScore {
  const lower = content.toLowerCase();
  const matched = markers.filter((marker) =>
    lower.includes(marker.toLowerCase())
  );
  const textDepthBonus = content.length > 2_000
    ? 8
    : content.length > 800
    ? 4
    : 0;
  return {
    score: Math.min(98, 52 + matched.length * 8 + textDepthBonus),
    weight: 0,
    explanation:
      `${explanation} Markers found: ${matched.length}/${markers.length}.`,
  };
}

function zeroQualityBreakdown(
  explanation: string,
): Record<QualityCategory, QualityCategoryScore> {
  return {
    opening_attention: {
      score: 0,
      weight: QUALITY_WEIGHTS.opening_attention,
      explanation,
    },
    retention_architecture: {
      score: 0,
      weight: QUALITY_WEIGHTS.retention_architecture,
      explanation,
    },
    creator_voice_specificity: {
      score: 0,
      weight: QUALITY_WEIGHTS.creator_voice_specificity,
      explanation,
    },
    audience_goal_fit: {
      score: 0,
      weight: QUALITY_WEIGHTS.audience_goal_fit,
      explanation,
    },
    save_share_trigger: {
      score: 0,
      weight: QUALITY_WEIGHTS.save_share_trigger,
      explanation,
    },
    accessibility_comprehension: {
      score: 0,
      weight: QUALITY_WEIGHTS.accessibility_comprehension,
      explanation,
    },
    format_production_fit: {
      score: 0,
      weight: QUALITY_WEIGHTS.format_production_fit,
      explanation,
    },
  };
}

function liveStatusKind(
  _experiment: ExperimentKind,
  data: JsonObject | null,
): LiveStatusKind {
  const status = stringValue(data?.status);
  if (status === "running" || status === "pending") {
    return "running";
  }
  if (status === "failed") {
    return "failed";
  }
  if (status === "cancelled" || status === "canceled") {
    return "cancelled";
  }
  if (status === "draft" || status === "completed") {
    return "success";
  }
  return "unknown";
}

function isTerminalLiveStatus(status: LiveStatusKind): boolean {
  return ["success", "partial", "failed", "cancelled"].includes(status);
}

function liveGenerateWeekURL(liveEnv: LiveEnv): string {
  const base = normalizeSupabaseURLValue(
    requireLiveValue("MCO_SUPABASE_URL", liveEnv.supabaseURL),
  )
    .replace(/\/+$/, "");
  return base.endsWith("/functions/v1/generate-week")
    ? base
    : `${base}/functions/v1/generate-week`;
}

function liveHeaders(liveEnv: LiveEnv): HeadersInit {
  const publishableKey = requireLiveValue(
    "MCO_SUPABASE_PUBLISHABLE_KEY",
    liveEnv.publishableKey,
  );
  return {
    Authorization: `Bearer ${publishableKey}`,
    apikey: publishableKey,
    "Content-Type": "application/json",
    "x-client": "day-generation-reliability-experiment",
    "x-mco-device-token": requireLiveValue(
      "MCO_LIVE_DEVICE_TOKEN",
      liveEnv.deviceToken,
    ),
  };
}

function validateLiveEnv(
  experiment: ExperimentKind,
  liveEnv: LiveEnv,
): string[] {
  const errors: string[] = [];
  if (
    liveEnv.supabaseURL &&
    !isURL(normalizeSupabaseURLValue(liveEnv.supabaseURL))
  ) {
    errors.push("MCO_SUPABASE_URL must be a URL");
  }
  if (liveEnv.creatorID && !isUUID(liveEnv.creatorID)) {
    errors.push("MCO_LIVE_CREATOR_ID must be a UUID");
  }
  if (experiment === "regenerate-day") {
    if (liveEnv.weeklyPlanID && !isUUID(liveEnv.weeklyPlanID)) {
      errors.push("MCO_LIVE_WEEKLY_PLAN_ID must be a UUID");
    }
    if (liveEnv.regenerateDate && !isDateString(liveEnv.regenerateDate)) {
      errors.push("MCO_LIVE_REGENERATE_DATE must be YYYY-MM-DD");
    }
  }
  if (experiment === "generate-day") {
    if (liveEnv.regenerateDate && !isDateString(liveEnv.regenerateDate)) {
      errors.push("MCO_LIVE_GENERATE_DATE must be YYYY-MM-DD");
    }
  }
  return errors;
}

function mockRunResult(
  experiment: ExperimentKind,
  index: number,
  rng: () => number,
): MockResult {
  // Deterministic-ish mock: most runs succeed, a small fraction fail/timeout
  // so summary stats and failure-code tallying are exercisable in dry-run.
  const roll = rng();
  const timedOut = index > 0 && roll < 0.05;
  const failedValidation = !timedOut && roll > 0.92;
  const durationMs = timedOut
    ? 180_000
    : Math.round(8_000 + rng() * 22_000) + index * 50;
  const validationPassed = !timedOut && !failedValidation;
  const failureCode = timedOut
    ? "timeout"
    : failedValidation
    ? "validation_failed"
    : "";
  const qualityBreakdown = mockQualityBreakdown(validationPassed, rng);
  const qualityScore = weightedQualityScore(qualityBreakdown);
  const hardGateBlockingFailures = validationPassed ? 0 : 1;
  const hardGateWarnings = validationPassed && qualityScore < 75 ? 1 : 0;
  const latencyScore = timedOut
    ? 0
    : Math.max(0, Math.round(100 - durationMs / 1_800));
  const autoresearchObjectiveScore = Math.round(
    (validationPassed ? 35 : 0) +
      Math.min(35, qualityScore * 0.35) +
      Math.min(20, latencyScore * 0.2) +
      (hardGateBlockingFailures === 0 ? 10 : 0),
  );
  const generatedContent = mockGeneratedContent(
    experiment,
    index,
    validationPassed,
  );
  return {
    httpStatus: null,
    durationMs,
    timedOut,
    validationPassed,
    failureCode,
    qualityScore,
    qualityBreakdown,
    hardGateBlockingFailures,
    hardGateWarnings,
    autoresearchObjectiveScore,
    generatedContent,
    generationID: null,
    weeklyPlanID: null,
    pollCount: null,
    notes:
      "dry-run: no live Supabase/OpenAI call; metrics are mock values for harness verification",
  };
}

function mockQualityBreakdown(
  validationPassed: boolean,
  rng: () => number,
): Record<QualityCategory, QualityCategoryScore> {
  const base = validationPassed ? 62 : 0;
  return {
    opening_attention: qualityCategory(
      base,
      rng,
      "First frame, first 3 seconds, motion, curiosity gap, and viewer identity match.",
    ),
    retention_architecture: qualityCategory(
      base,
      rng,
      "Scene progression, pacing, payoff match, pattern breaks, and loop potential.",
    ),
    creator_voice_specificity: qualityCategory(
      base,
      rng,
      "Creator-native phrasing, lived detail, context anchor, and no generic AI voice.",
    ),
    audience_goal_fit: qualityCategory(
      base,
      rng,
      "Target viewer, content job, pillar alignment, metric goal, and pain/desire match.",
    ),
    save_share_trigger: qualityCategory(
      base,
      rng,
      "Real save/send reason, practical or emotional utility, and non-forced CTA.",
    ),
    accessibility_comprehension: qualityCategory(
      base,
      rng,
      "Captions, silent-mode comprehension, readability, text density, and jargon handling.",
    ),
    format_production_fit: qualityCategory(
      base,
      rng,
      "Duration, aspect ratio, audio strategy, scene variety, and shootability.",
    ),
  };
}

function qualityCategory(
  base: number,
  rng: () => number,
  explanation: string,
): QualityCategoryScore {
  const score = base === 0 ? 0 : Math.min(98, Math.round(base + rng() * 34));
  return {
    score,
    weight: 0,
    explanation,
  };
}

function weightedQualityScore(
  breakdown: Record<QualityCategory, QualityCategoryScore>,
): number {
  let weighted = 0;
  const withWeights = breakdown as Record<
    QualityCategory,
    QualityCategoryScore
  >;
  for (const key of Object.keys(QUALITY_WEIGHTS) as QualityCategory[]) {
    const weight = QUALITY_WEIGHTS[key];
    withWeights[key].weight = weight;
    weighted += withWeights[key].score * weight;
  }
  return Math.round(weighted / 100);
}

function mockGeneratedContent(
  experiment: ExperimentKind,
  index: number,
  passed: boolean,
): string {
  if (!passed) {
    return JSON.stringify({
      run_index: index + 1,
      experiment,
      daily_card: null,
      note: "mock failed generation for harness verification",
    });
  }
  // Mock content embeds a few known terms (Bombay, gym, hook, voiceover_timeline)
  // so the guidance evaluator can be verified end-to-end in dry-run.
  return JSON.stringify({
    run_index: index + 1,
    experiment,
    strategy_note: "Mock dry-run strategy for harness verification.",
    daily_card: {
      scheduled_date: "2026-08-25",
      title: `Bombay gym reset ${index + 1}`,
      hook: "First 2 seconds show motion proof before advice.",
      weekly_brief_anchor: "Back in Bombay, restarting gym routine.",
      caption:
        "Short caption that keeps it grounded and avoids weight-loss framing.",
      shot_timeline: [
        {
          timestamp: "0:00-0:03",
          detail: "Open on gym bag in Bombay hallway.",
        },
      ],
      voiceover_timeline: [
        {
          timestamp: "0:00-0:03",
          video_portion: "opening",
          voiceover: "Steady start.",
        },
      ],
    },
  });
}

function computeSummary(resultsPath: string, rows: ResultRow[]): SummaryStats {
  const executed = rows.filter((row) => row.planned);
  const valid = executed.filter((row) => row.validation_passed);
  const failed = executed.filter((row) => !row.validation_passed);
  const durations = executed.map((row) => row.duration_ms).sort((a, b) =>
    a - b
  );
  const qualities = valid.map((row) => row.quality_score).sort((a, b) => a - b);
  const adherenceScores = valid
    .map((row) => row.guidance_adherence_score)
    .filter((value): value is number => typeof value === "number");
  const failureCodes: Record<string, number> = {};
  for (const row of failed) {
    const code = row.failure_code || "unknown";
    failureCodes[code] = (failureCodes[code] ?? 0) + 1;
  }
  return {
    input_file: resultsPath,
    total_runs: rows.length,
    executed_runs: executed.length,
    valid_runs: valid.length,
    failed_runs: failed.length,
    failure_rate: executed.length === 0 ? 0 : failed.length / executed.length,
    duration_ms_min: durations.length ? durations[0] : 0,
    duration_ms_avg: avg(durations),
    duration_ms_p50: percentile(durations, 0.5),
    duration_ms_p90: percentile(durations, 0.9),
    duration_ms_p95: percentile(durations, 0.95),
    duration_ms_max: durations.length ? durations[durations.length - 1] : 0,
    quality_score_min: qualities.length ? qualities[0] : 0,
    quality_score_avg: avg(qualities),
    quality_score_p50: percentile(qualities, 0.5),
    quality_score_p90: percentile(qualities, 0.9),
    quality_score_max: qualities.length ? qualities[qualities.length - 1] : 0,
    guidance_adherence_avg: adherenceScores.length
      ? avg(adherenceScores)
      : null,
    failure_codes: failureCodes,
  };
}

function renderSummary(stats: SummaryStats): string {
  const failureLines = Object.keys(stats.failure_codes).length === 0
    ? ["- none"]
    : Object.entries(stats.failure_codes).map(
      ([code, count]) => `- ${code}: ${count}`,
    );
  return [
    "# Day Generation Reliability Experiment Summary",
    "",
    `Source: ${stats.input_file}`,
    `Generated: ${new Date().toISOString()}`,
    "",
    "## Counts",
    "",
    `- Total rows: ${stats.total_runs}`,
    `- Executed (planned) runs: ${stats.executed_runs}`,
    `- Valid runs: ${stats.valid_runs}`,
    `- Failed runs: ${stats.failed_runs}`,
    `- Failure rate: ${(stats.failure_rate * 100).toFixed(1)}%`,
    "",
    "## Latency (ms)",
    "",
    `- min: ${stats.duration_ms_min}`,
    `- avg: ${stats.duration_ms_avg}`,
    `- p50: ${stats.duration_ms_p50}`,
    `- p90: ${stats.duration_ms_p90}`,
    `- p95: ${stats.duration_ms_p95}`,
    `- max: ${stats.duration_ms_max}`,
    "",
    "## Quality score",
    "",
    `- min: ${stats.quality_score_min}`,
    `- avg: ${stats.quality_score_avg}`,
    `- p50: ${stats.quality_score_p50}`,
    `- p90: ${stats.quality_score_p90}`,
    `- max: ${stats.quality_score_max}`,
    "",
    "## Guidance adherence",
    "",
    stats.guidance_adherence_avg === null
      ? "- not evaluated (run --mode evaluate-guidance on the outputs file)"
      : `- avg: ${stats.guidance_adherence_avg}`,
    "",
    "## Failure codes",
    "",
    ...failureLines,
    "",
  ].join("\n");
}

function renderGuidanceAggregate(evaluations: GuidanceEvaluation[]): string {
  const total = evaluations.length;
  const passed = evaluations.filter((evaluation) => evaluation.passed).length;
  const avgAdherence = total === 0
    ? 0
    : avg(evaluations.map((evaluation) => evaluation.adherence_score));
  const allMissingRequired = evaluations.flatMap((evaluation) =>
    evaluation.required_terms_missing
  );
  const allForbiddenViolations = evaluations.flatMap((evaluation) =>
    evaluation.forbidden_terms_violations
  );
  return [
    "# Guidance Adherence Aggregate",
    "",
    `Generated: ${new Date().toISOString()}`,
    "",
    `- Rows evaluated: ${total}`,
    `- Passed (all required present, no forbidden): ${passed}`,
    `- Avg adherence score: ${avgAdherence}`,
    "",
    "## Frequently missing required terms",
    "",
    ...tally(allMissingRequired).slice(0, 10).map(
      ([term, count]) => `- ${term}: ${count}`,
    ),
    "",
    "## Frequently violated forbidden terms",
    "",
    ...tally(allForbiddenViolations).slice(0, 10).map(
      ([term, count]) => `- ${term}: ${count}`,
    ),
    "",
  ].join("\n");
}

function compactObject(value: JsonObject): JsonObject {
  const compacted: JsonObject = {};
  for (const [key, entry] of Object.entries(value)) {
    if (entry !== undefined && entry !== null) {
      compacted[key] = entry;
    }
  }
  return compacted;
}

function normalizeSupabaseURLValue(value: string): string {
  // xcconfig escapes URL double slashes as https:/$()/example.supabase.co.
  // Normalize that raw build-setting form before Deno validates or fetches.
  return value.replace(":/\$()/", "://");
}

function parseJsonObject(rawText: string): JsonObject | null {
  if (!rawText.trim()) {
    return null;
  }
  try {
    const parsed = JSON.parse(rawText) as unknown;
    if (isRecord(parsed)) {
      return parsed;
    }
    return { response: parsed };
  } catch {
    return { raw_response: rawText.slice(0, 4_000) };
  }
}

function requireLiveValue(name: string, value: string | null): string {
  if (!value) {
    fail(`Live mode missing required env var ${name}. Values are not printed.`);
  }
  return value;
}

function logExperimentProgress(message: string): void {
  console.log(
    `[day-generation-harness ${new Date().toISOString()}] ${message}`,
  );
}

function summarizeLiveStatus(data: JsonObject | null): string {
  if (!data) {
    return "status=none";
  }

  const status = stringValue(data.status) ?? "unknown";
  const generationID = stringValue(data.generation_id);
  const weeklyPlanID = stringValue(data.weekly_plan_id);
  const savedCount = numberValue(data.saved_day_count);
  const failedCount = numberValue(data.failed_day_count);
  const totalCount = numberValue(data.total_day_count);
  const dayStatuses = arrayValue(data.day_statuses)
    ?.filter(isRecord)
    .map((day) => ({
      date: stringValue(day.scheduled_date) ?? "?",
      status: stringValue(day.status) ?? "?",
      attempts: numberValue(day.attempt_count) ?? numberValue(day.attempts),
      error: stringValue(day.error_code),
    })) ?? [];
  const runningDays = dayStatuses.filter((day) =>
    day.status === "running" || day.status === "generating" ||
    day.status === "retrying"
  );
  const queuedDays = dayStatuses.filter((day) =>
    day.status === "pending" || day.status === "queued"
  );
  const completedCount =
    dayStatuses.filter((day) =>
      day.status === "completed" || day.status === "generated"
    ).length;
  const failedDays = dayStatuses.filter((day) => day.status === "failed")
    .map((day) =>
      `${day.date}${day.error ? `:${day.error}` : ""}${
        day.attempts ? `#${day.attempts}` : ""
      }`
    );
  const parts = [
    `status=${status}`,
    generationID ? `generation_id=${generationID}` : "",
    weeklyPlanID ? `weekly_plan_id=${weeklyPlanID}` : "",
    totalCount !== null ? `total=${totalCount}` : "",
    savedCount !== null ? `saved=${savedCount}` : "",
    failedCount !== null ? `failed=${failedCount}` : "",
    dayStatuses.length > 0 ? `completed=${completedCount}` : "",
    dayStatuses.length > 0 ? `running=${runningDays.length}` : "",
    runningDays.length > 0
      ? `running_days=${summarizeDayStatusList(runningDays)}`
      : "",
    dayStatuses.length > 0 ? `queued=${queuedDays.length}` : "",
    queuedDays.length > 0
      ? `queued_days=${summarizeDayStatusList(queuedDays)}`
      : "",
    failedDays.length > 0 ? `failed_days=${failedDays.join(",")}` : "",
    stringValue(data.error) ? `error=${stringValue(data.error)}` : "",
    numberValue(data.poll_after_seconds) !== null
      ? `poll_after=${numberValue(data.poll_after_seconds)}s`
      : "",
  ];
  return parts.filter(Boolean).join(" ");
}

function summarizeDayStatusList(
  days: Array<{ date: string; attempts: number | null; error: string | null }>,
): string {
  return days.map((day) =>
    `${day.date}${day.attempts ? `#${day.attempts}` : ""}${
      day.error ? `:${day.error}` : ""
    }`
  ).join(",");
}

function clampPollAfterMs(pollAfterSeconds: number | null): number {
  const seconds = Math.max(2, Math.min(pollAfterSeconds ?? 5, 15));
  return seconds * 1_000;
}

async function sleep(durationMs: number): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, durationMs));
}

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === "AbortError";
}

function isRecord(value: unknown): value is JsonObject {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function arrayValue(value: unknown): unknown[] | null {
  return Array.isArray(value) ? value : null;
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function numberValue(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function isUUID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

function isDateString(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }
  const parsed = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(parsed.getTime()) &&
    parsed.toISOString().slice(0, 10) === value;
}

function isURL(value: string): boolean {
  try {
    new URL(value);
    return true;
  } catch {
    return false;
  }
}

function tally(values: string[]): Array<[string, number]> {
  const counts: Record<string, number> = {};
  for (const value of values) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  return Object.entries(counts).sort((a, b) => b[1] - a[1]);
}

function avg(values: number[]): number {
  if (values.length === 0) {
    return 0;
  }
  return Math.round(
    values.reduce((sum, value) => sum + value, 0) / values.length,
  );
}

function percentile(sorted: number[], p: number): number {
  if (sorted.length === 0) {
    return 0;
  }
  const index = Math.min(sorted.length - 1, Math.floor(p * sorted.length));
  return sorted[index];
}

type ParsedArgs = Record<string, string>;

function parseArgs(argv: string[]): ParsedArgs {
  const result: ParsedArgs = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg.startsWith("--")) {
      const rawKey = arg.slice(2);
      const key = dashToCamel(rawKey);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith("--")) {
        result[key] = "1";
      } else {
        result[key] = next;
        i += 1;
      }
    }
  }
  return result;
}

function dashToCamel(key: string): string {
  return key.replace(/-([a-z])/g, (_match, letter) => letter.toUpperCase());
}

function parsePositiveInt(value: string | undefined): number | null {
  if (!value) {
    return null;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return null;
  }
  return Math.trunc(parsed);
}

function parseTermList(value: string | undefined): string[] {
  if (!value) {
    return [];
  }
  return value.split(",").map((term) => term.trim()).filter((term) =>
    term.length > 0
  );
}

function envValue(name: string): string | null {
  return Deno.env.get(name)?.trim() || null;
}

function defaultOutputPath(mode: Mode, isDryRun: boolean): string {
  const slug = isDryRun ? "dry-run" : "live";
  if (mode === "plan-regenerate-day") {
    return `${DEFAULT_OUTPUT_DIR}/regenerate-day-${slug}.jsonl`;
  }
  if (mode === "plan-generate-day") {
    return `${DEFAULT_OUTPUT_DIR}/generate-day-${slug}.jsonl`;
  }
  return "";
}

function extractContent(parsed: unknown): string {
  if (!parsed || typeof parsed !== "object") {
    return "";
  }
  const record = parsed as Record<string, unknown>;
  if (typeof record.generated_content === "string") {
    return record.generated_content;
  }
  return JSON.stringify(record);
}

function extractRunIndex(parsed: unknown): number | null {
  if (!parsed || typeof parsed !== "object") {
    return null;
  }
  const record = parsed as Record<string, unknown>;
  return typeof record.run_index === "number" ? record.run_index : null;
}

async function appendJsonl(path: string, value: unknown): Promise<void> {
  await Deno.writeTextFile(path, `${JSON.stringify(value)}\n`, {
    append: true,
  });
}

async function readJsonl<T>(path: string): Promise<T[]> {
  const raw = await Deno.readTextFile(path);
  const lines = raw.split(/\r?\n/).filter((line) => line.trim().length > 0);
  const rows: T[] = [];
  for (const line of lines) {
    try {
      rows.push(JSON.parse(line) as T);
    } catch (error) {
      fail(`failed to parse JSONL line in ${path}: ${shortError(error)}`);
    }
  }
  return rows;
}

async function ensureDir(path: string): Promise<void> {
  if (path) {
    await Deno.mkdir(path, { recursive: true });
  }
}

function dirname(path: string): string {
  const slash = path.lastIndexOf("/");
  return slash >= 0 ? path.slice(0, slash) : "";
}

function mulberry32(seed: number): () => number {
  let state = seed >>> 0;
  return function (): number {
    state = (state + 0x6D2B79F5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function shortError(error: unknown): string {
  if (error instanceof Error) {
    return error.message.slice(0, 240);
  }
  return String(error).slice(0, 240);
}

function fail(message: string): never {
  console.error(`error: ${message}`);
  Deno.exit(1);
}
