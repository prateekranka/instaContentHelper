import {
  makeMockGeneratedWeek,
  validateGeneratedDayOutput,
  weekDates,
} from "../supabase/functions/generate-week/generation.ts";
import type {
  GeneratedDailyCard,
  GeneratedDayOutput,
  GenerationInputSnapshot,
} from "../supabase/functions/generate-week/generation.ts";
import {
  STORYBOARD_THUMBNAIL_PROMPT_VERSION,
} from "../supabase/functions/_shared/storyboard-thumbnail.ts";
import type {
  StoryboardThumbnailAsset,
} from "../supabase/functions/_shared/storyboard-thumbnail.ts";
import { scoreGeneratedDayOutputQuality } from "../supabase/functions/generate-week/generation-quality.ts";
import { runOrderedBounded } from "../supabase/functions/_shared/storyboard-thumbnail-generation.ts";

export const DEFAULT_SAMPLE_COUNT = 20;
export const EXPECTED_THUMBNAIL_COUNT = 5;
export const QUALITY_SCORE_PASS_THRESHOLD = 75;
export const TARGET_P50_TOTAL_MS = 45_000;
export const TARGET_P95_TOTAL_MS = 60_000;
export const PERCENTILE_METHOD = "linear_interpolation_n_minus_1_v1";

export const OFFLINE_FAKE_PROFILE = {
  id: "day_generation_under_60_deterministic_fake_v1",
  fake_only: true,
  context_delay_formula_ms: "800 + ((sample_index * 73) % 201)",
  text_delay_formula_ms: "18000 + ((sample_index * 211) % 2001)",
  persistence_delay_formula_ms: "1600 + ((sample_index * 131) % 401)",
  visual_delay_formula_ms:
    "5200 + ((((sample_index + 1) * 113) + ((visual_index + 1) * 197)) % 401)",
  thumbnail_count: EXPECTED_THUMBNAIL_COUNT,
} as const;

export const OFFLINE_BUDGET_MS = {
  context: 1_000,
  textAndValidation: 20_000,
  persistenceAndFinalization: 2_000,
  fiveVisualsSerial: 28_000,
  margin: 9_000,
  total: 60_000,
} as const;

export type ArchitectureName =
  | "serial_storyboard"
  | "bounded_concurrency_2"
  | "bounded_concurrency_3";

export type DeterministicDelayedFake = {
  contextDelayMs(sampleIndex: number): number;
  textAndValidationDelayMs(sampleIndex: number): number;
  persistenceAndFinalizationDelayMs(sampleIndex: number): number;
  visualDelayMs(sampleIndex: number, visualIndex: number): number;
};

export type SampleTiming = {
  context_ms: number;
  text_stage_ms: number;
  visuals_stage_ms: number;
  persistence_ms: number;
  total_ms: number;
  visual_durations_ms: number[];
};

export type BenchmarkSample = {
  sample_index: number;
  scheduled_date: string;
  day_index: number;
  expected_thumbnail_count: number;
  complete_thumbnail_success: boolean;
  completed_thumbnail_count: number;
  day_output_validation_passed: boolean;
  complete_daily_card_contract: boolean;
  quality_score: number | null;
  quality_score_passed: boolean;
  timings: Record<ArchitectureName, SampleTiming>;
};

export type PercentileSummary = {
  min: number;
  p50: number;
  p95: number;
  max: number;
};

export type ArchitectureMetrics = {
  architecture: ArchitectureName;
  visual_concurrency: number;
  sample_count: number;
  total_ms: PercentileSummary;
  context_stage_ms: PercentileSummary;
  text_stage_ms: PercentileSummary;
  visuals_stage_ms: PercentileSummary;
  persistence_ms: PercentileSummary;
  expected_thumbnail_count: number;
  expected_thumbnail_count_total: number;
  completed_thumbnail_asset_count: number;
  complete_thumbnail_success_count: number;
  day_output_validation_pass_count: number;
  complete_daily_card_contract_pass_count: number;
  quality_score_pass_count: number;
  quality_score_pass_threshold: number;
  p50_total_under_45_seconds: boolean;
  p95_total_under_60_seconds: boolean;
  offline_acceptance_passed: boolean;
};

export type BenchmarkReport = {
  schema_version: "day_generation_under_60_offline_v1";
  evidence_class: "offline_architectural_evidence_not_live_sla_proof";
  network_calls: false;
  provider_calls: false;
  secrets_used: false;
  fake_profile: typeof OFFLINE_FAKE_PROFILE;
  percentile_method: typeof PERCENTILE_METHOD;
  sample_count: number;
  budget_ms: typeof OFFLINE_BUDGET_MS;
  quality_score_pass_threshold: number;
  bounded_concurrency_2_acceptance_passed: boolean;
  architectures: ArchitectureMetrics[];
  samples: BenchmarkSample[];
};

const REQUIRED_DAILY_CARD_FIELDS: ReadonlyArray<keyof GeneratedDailyCard> = [
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

const ARCHITECTURES: Array<{
  name: ArchitectureName;
  visualConcurrency: number;
}> = [
  { name: "serial_storyboard", visualConcurrency: 1 },
  { name: "bounded_concurrency_2", visualConcurrency: 2 },
  { name: "bounded_concurrency_3", visualConcurrency: 3 },
];

/**
 * Fixed stage delays model the explicit 1s + 20s + 28s + 2s budget. The
 * values vary by sample but never use wall-clock time, randomness, network,
 * providers, environment variables, or secrets.
 */
export function createDeterministicDelayedFake(): DeterministicDelayedFake {
  return {
    contextDelayMs: (sampleIndex) => 800 + ((sampleIndex * 73) % 201),
    textAndValidationDelayMs: (sampleIndex) =>
      18_000 + ((sampleIndex * 211) % 2_001),
    persistenceAndFinalizationDelayMs: (sampleIndex) =>
      1_600 + ((sampleIndex * 131) % 401),
    visualDelayMs: (sampleIndex, visualIndex) =>
      5_200 + (((sampleIndex + 1) * 113 + (visualIndex + 1) * 197) % 401),
  };
}

type PendingVirtualDelay = {
  finishMS: number;
  sequence: number;
  resolve: () => void;
};

class DeterministicVirtualClock {
  private currentMS = 0;
  private nextSequence = 0;
  private pending: PendingVirtualDelay[] = [];
  private pumpScheduled = false;

  get elapsedMS(): number {
    return this.currentMS;
  }

  wait(durationMS: number): Promise<void> {
    if (!Number.isFinite(durationMS) || durationMS < 0) {
      throw new Error("virtual duration must be a nonnegative finite number");
    }
    return new Promise((resolve) => {
      this.pending.push({
        finishMS: this.currentMS + durationMS,
        sequence: this.nextSequence++,
        resolve,
      });
      this.schedulePump();
    });
  }

  private schedulePump(): void {
    if (this.pumpScheduled) return;
    this.pumpScheduled = true;
    // Two microtask turns let the production worker observe a completed fake
    // delay and claim its next item before the next virtual completion fires.
    queueMicrotask(() => queueMicrotask(() => this.advance()));
  }

  private advance(): void {
    this.pumpScheduled = false;
    if (this.pending.length === 0) return;
    this.pending.sort((left, right) =>
      left.finishMS - right.finishMS || left.sequence - right.sequence
    );
    const next = this.pending.shift();
    if (!next) return;
    this.currentMS = next.finishMS;
    next.resolve();
    if (this.pending.length > 0) this.schedulePump();
  }
}

/**
 * Return virtual completion time while executing the same ordered bounded
 * scheduler used by production storyboard generation.
 */
export async function simulateVisualStage(
  visualDurationsMs: readonly number[],
  concurrency: number,
): Promise<number> {
  if (visualDurationsMs.length === 0) {
    return 0;
  }
  const clock = new DeterministicVirtualClock();
  const settlements = await runOrderedBounded(
    visualDurationsMs,
    concurrency,
    async (durationMS) => {
      await clock.wait(durationMS);
      return durationMS;
    },
  );
  const failure = settlements.find((settlement) => !settlement.ok);
  if (failure && !failure.ok) {
    throw failure.error;
  }
  return clock.elapsedMS;
}

export async function simulateSampleTiming(
  sampleIndex: number,
  visualConcurrency: number,
  delayedFake: DeterministicDelayedFake = createDeterministicDelayedFake(),
): Promise<SampleTiming> {
  const contextMs = delayedFake.contextDelayMs(sampleIndex);
  const textStageMs = delayedFake.textAndValidationDelayMs(sampleIndex);
  const visualDurationsMs = Array.from(
    { length: EXPECTED_THUMBNAIL_COUNT },
    (_, visualIndex) => delayedFake.visualDelayMs(sampleIndex, visualIndex),
  );
  const visualsStageMs = await simulateVisualStage(
    visualDurationsMs,
    visualConcurrency,
  );
  const persistenceMs = delayedFake.persistenceAndFinalizationDelayMs(
    sampleIndex,
  );

  return {
    context_ms: contextMs,
    text_stage_ms: textStageMs,
    visuals_stage_ms: visualsStageMs,
    persistence_ms: persistenceMs,
    total_ms: contextMs + textStageMs + visualsStageMs + persistenceMs,
    visual_durations_ms: visualDurationsMs,
  };
}

export function hasCompleteDailyCardContract(
  output: GeneratedDayOutput,
): boolean {
  const card = output.daily_card;
  if (!REQUIRED_DAILY_CARD_FIELDS.every((field) => field in card)) {
    return false;
  }
  return hasCompleteThumbnailAssetSet(card.storyboard_thumbnail_assets);
}

export function hasCompleteThumbnailAssetSet(
  assets:
    | Array<StoryboardThumbnailAsset | Record<string, unknown>>
    | undefined,
): boolean {
  if (!Array.isArray(assets) || assets.length !== EXPECTED_THUMBNAIL_COUNT) {
    return false;
  }
  const rowIndexes = assets.map((asset) =>
    typeof asset.row_index === "number" ? asset.row_index : Number.NaN
  );
  const expectedRowIndexes = Array.from(
    { length: EXPECTED_THUMBNAIL_COUNT },
    (_, index) => index,
  );
  const sortedRowIndexes = [...rowIndexes].sort((left, right) => left - right);
  const assetFields: Array<
    | "prompt_hash"
    | "storage_path"
    | "public_url"
    | "model"
    | "prompt_version"
    | "generated_at"
  > = [
    "prompt_hash",
    "storage_path",
    "public_url",
    "model",
    "prompt_version",
    "generated_at",
  ];
  return JSON.stringify(sortedRowIndexes) ===
      JSON.stringify(expectedRowIndexes) &&
    new Set(rowIndexes).size === EXPECTED_THUMBNAIL_COUNT &&
    assets.every((asset) =>
      Number.isInteger(asset.row_index) &&
      asset.status === "generated" &&
      assetFields.every((field) =>
        typeof asset[field] === "string" && asset[field].trim().length > 0
      )
    );
}

function fixtureInput(): GenerationInputSnapshot {
  return {
    creator_id: "33333333-3333-4333-8333-333333333333",
    week_start_date: "2026-08-03",
    creator_profile: {
      display_name: "Offline benchmark creator",
      positioning: "Lifestyle creator after 60",
      never_say: ["weight talk", "politics"],
    },
    weekly_setup: {
      id: "77777777-7777-4777-8777-777777777771",
      location: "Bombay",
      notes:
        "Weekly brief: in Bombay this week, back to gym after travel, and recording a podcast.",
    },
    confirmed_references: [
      {
        id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
        source_type: "reel_link",
        manual_notes: "Confirmed towel transition",
      },
    ],
    reference_extractions: [],
    recent_archive: [],
    idea_bank: [],
    patterns: [],
    trends: [],
    audio_options: [],
    brand_briefs: [],
    key_moments: [],
  };
}

type SampleContract = {
  scheduledDate: string;
  dayIndex: number;
  completeThumbnailSuccess: boolean;
  completedThumbnailCount: number;
  validationPassed: boolean;
  completeDailyCardContract: boolean;
  qualityScore: number | null;
};

export function createDeterministicThumbnailAssets(
  sampleIndex: number,
): StoryboardThumbnailAsset[] {
  return Array.from(
    { length: EXPECTED_THUMBNAIL_COUNT },
    (_, rowIndex) => ({
      row_index: rowIndex,
      prompt_hash: `offline-prompt-hash-${sampleIndex}-${rowIndex}`,
      storage_path:
        `offline-workspace/offline-creator/day-${sampleIndex}/row-${rowIndex}.jpg`,
      public_url:
        `https://offline.invalid/day-generation-under-60/${sampleIndex}/${rowIndex}.jpg`,
      model: "offline-image-fake-v1",
      prompt_version: STORYBOARD_THUMBNAIL_PROMPT_VERSION,
      status: "generated",
      generated_at: "2026-08-03T08:00:00.000Z",
    }),
  );
}

export function buildOfflineValidatedDayOutput(
  sampleIndex: number,
): GeneratedDayOutput {
  const input = fixtureInput();
  const dayIndex = sampleIndex % 7;
  const scheduledDate = weekDates(input.week_start_date)[dayIndex];
  const generated = makeMockGeneratedWeek(input);
  const thumbnailAssets = createDeterministicThumbnailAssets(sampleIndex);

  const validated = validateGeneratedDayOutput(
    {
      strategy_note: generated.strategy_summary,
      warnings: generated.warnings,
      assumptions: generated.assumptions,
      daily_card: {
        ...generated.daily_cards[dayIndex],
        storyboard_thumbnail_assets: thumbnailAssets,
      },
      idea_bank: generated.idea_bank,
      source_summary: generated.source_summary,
    },
    scheduledDate,
    dayIndex,
  );
  // The production validator intentionally normalizes the text contract;
  // reattach the separately generated optional visual assets for the full
  // day-output fixture evaluated by this architecture benchmark.
  return {
    ...validated,
    daily_card: {
      ...validated.daily_card,
      storyboard_thumbnail_assets: thumbnailAssets,
    },
  };
}

function buildSampleContract(sampleIndex: number): SampleContract {
  const input = fixtureInput();
  const dayIndex = sampleIndex % 7;
  const scheduledDate = weekDates(input.week_start_date)[dayIndex];

  try {
    const output = buildOfflineValidatedDayOutput(sampleIndex);
    const thumbnailAssets = output.daily_card.storyboard_thumbnail_assets ?? [];
    const completeThumbnailSuccess = hasCompleteThumbnailAssetSet(
      thumbnailAssets,
    );
    const completeDailyCardContract = hasCompleteDailyCardContract(output);
    const qualityScore = completeDailyCardContract
      ? scoreGeneratedDayOutputQuality(input, output, scheduledDate).score
      : null;
    return {
      scheduledDate,
      dayIndex,
      completeThumbnailSuccess,
      completedThumbnailCount: thumbnailAssets.length,
      validationPassed: true,
      completeDailyCardContract,
      qualityScore,
    };
  } catch {
    return {
      scheduledDate,
      dayIndex,
      completeThumbnailSuccess: false,
      completedThumbnailCount: 0,
      validationPassed: false,
      completeDailyCardContract: false,
      qualityScore: null,
    };
  }
}

export function percentileLinearNMinus1(
  values: readonly number[],
  fraction: number,
): number {
  if (!Number.isFinite(fraction) || fraction < 0 || fraction > 1) {
    throw new Error("percentile fraction must be between zero and one");
  }
  const sorted = [...values].sort((left, right) => left - right);
  if (sorted.length === 0) {
    return 0;
  }
  const position = (sorted.length - 1) * fraction;
  const lower = Math.floor(position);
  const upper = Math.ceil(position);
  if (lower === upper) {
    return sorted[lower];
  }
  return Math.round(
    sorted[lower] + (sorted[upper] - sorted[lower]) *
        (position - lower),
  );
}

function summarize(values: number[]): PercentileSummary {
  const sorted = [...values].sort((left, right) => left - right);
  return {
    min: sorted[0] ?? 0,
    p50: percentileLinearNMinus1(sorted, 0.5),
    p95: percentileLinearNMinus1(sorted, 0.95),
    max: sorted.at(-1) ?? 0,
  };
}

export function meetsOfflineLatencyTargets(
  p50MS: number,
  p95MS: number,
): boolean {
  return p50MS <= TARGET_P50_TOTAL_MS && p95MS < TARGET_P95_TOTAL_MS;
}

export function offlineArchitectureAccepted(
  metrics: Pick<
    ArchitectureMetrics,
    | "sample_count"
    | "total_ms"
    | "expected_thumbnail_count_total"
    | "completed_thumbnail_asset_count"
    | "complete_thumbnail_success_count"
    | "day_output_validation_pass_count"
    | "complete_daily_card_contract_pass_count"
    | "quality_score_pass_count"
  >,
): boolean {
  const sampleCount = metrics.sample_count;
  return sampleCount >= DEFAULT_SAMPLE_COUNT &&
    meetsOfflineLatencyTargets(metrics.total_ms.p50, metrics.total_ms.p95) &&
    metrics.completed_thumbnail_asset_count ===
      metrics.expected_thumbnail_count_total &&
    metrics.complete_thumbnail_success_count === sampleCount &&
    metrics.day_output_validation_pass_count === sampleCount &&
    metrics.complete_daily_card_contract_pass_count === sampleCount &&
    metrics.quality_score_pass_count === sampleCount;
}

function architectureMetrics(
  architecture: ArchitectureName,
  visualConcurrency: number,
  samples: BenchmarkSample[],
): ArchitectureMetrics {
  const timings = samples.map((sample) => sample.timings[architecture]);
  const totalMS = summarize(timings.map((timing) => timing.total_ms));
  const qualityScorePassCount =
    samples.filter((sample) => sample.quality_score_passed).length;
  const metrics: ArchitectureMetrics = {
    architecture,
    visual_concurrency: visualConcurrency,
    sample_count: samples.length,
    total_ms: totalMS,
    context_stage_ms: summarize(timings.map((timing) => timing.context_ms)),
    text_stage_ms: summarize(timings.map((timing) => timing.text_stage_ms)),
    visuals_stage_ms: summarize(
      timings.map((timing) => timing.visuals_stage_ms),
    ),
    persistence_ms: summarize(timings.map((timing) => timing.persistence_ms)),
    expected_thumbnail_count: EXPECTED_THUMBNAIL_COUNT,
    expected_thumbnail_count_total: samples.length * EXPECTED_THUMBNAIL_COUNT,
    completed_thumbnail_asset_count: samples.reduce(
      (total, sample) => total + sample.completed_thumbnail_count,
      0,
    ),
    complete_thumbnail_success_count:
      samples.filter((sample) => sample.complete_thumbnail_success).length,
    day_output_validation_pass_count:
      samples.filter((sample) => sample.day_output_validation_passed).length,
    complete_daily_card_contract_pass_count:
      samples.filter((sample) => sample.complete_daily_card_contract).length,
    quality_score_pass_count: qualityScorePassCount,
    quality_score_pass_threshold: QUALITY_SCORE_PASS_THRESHOLD,
    p50_total_under_45_seconds: totalMS.p50 <= TARGET_P50_TOTAL_MS,
    p95_total_under_60_seconds: totalMS.p95 < TARGET_P95_TOTAL_MS,
    offline_acceptance_passed: false,
  };
  metrics.offline_acceptance_passed = offlineArchitectureAccepted(metrics);
  return metrics;
}

export async function runBenchmark(options: {
  sampleCount?: number;
  includeConcurrency3?: boolean;
} = {}): Promise<BenchmarkReport> {
  const sampleCount = options.sampleCount ?? DEFAULT_SAMPLE_COUNT;
  if (!Number.isInteger(sampleCount) || sampleCount < DEFAULT_SAMPLE_COUNT) {
    throw new Error(`sampleCount must be at least ${DEFAULT_SAMPLE_COUNT}`);
  }

  const architectureDefinitions = options.includeConcurrency3 === false
    ? ARCHITECTURES.slice(0, 2)
    : ARCHITECTURES;
  const delayedFake = createDeterministicDelayedFake();
  const samples = await Promise.all(
    Array.from({ length: sampleCount }, async (_, sampleIndex) => {
      const contract = buildSampleContract(sampleIndex);
      const timingEntries = await Promise.all(
        architectureDefinitions.map(async ({ name, visualConcurrency }) =>
          [
            name,
            await simulateSampleTiming(
              sampleIndex,
              visualConcurrency,
              delayedFake,
            ),
          ] as const
        ),
      );
      const timings = Object.fromEntries(timingEntries) as Record<
        ArchitectureName,
        SampleTiming
      >;
      return {
        sample_index: sampleIndex,
        scheduled_date: contract.scheduledDate,
        day_index: contract.dayIndex,
        expected_thumbnail_count: EXPECTED_THUMBNAIL_COUNT,
        complete_thumbnail_success: contract.completeThumbnailSuccess,
        completed_thumbnail_count: contract.completedThumbnailCount,
        day_output_validation_passed: contract.validationPassed,
        complete_daily_card_contract: contract.completeDailyCardContract,
        quality_score: contract.qualityScore,
        quality_score_passed: contract.qualityScore !== null &&
          contract.qualityScore >= QUALITY_SCORE_PASS_THRESHOLD &&
          contract.completeDailyCardContract,
        timings,
      } satisfies BenchmarkSample;
    }),
  );

  const architectures = architectureDefinitions.map(
    ({ name, visualConcurrency }) =>
      architectureMetrics(name, visualConcurrency, samples),
  );
  const boundedConcurrency2 = architectures.find((metrics) =>
    metrics.architecture === "bounded_concurrency_2"
  );

  return {
    schema_version: "day_generation_under_60_offline_v1",
    evidence_class: "offline_architectural_evidence_not_live_sla_proof",
    network_calls: false,
    provider_calls: false,
    secrets_used: false,
    fake_profile: OFFLINE_FAKE_PROFILE,
    percentile_method: PERCENTILE_METHOD,
    sample_count: sampleCount,
    budget_ms: OFFLINE_BUDGET_MS,
    quality_score_pass_threshold: QUALITY_SCORE_PASS_THRESHOLD,
    bounded_concurrency_2_acceptance_passed:
      boundedConcurrency2?.offline_acceptance_passed === true,
    architectures,
    samples,
  };
}

export function assertOfflineCandidateAccepted(report: BenchmarkReport): void {
  if (!report.bounded_concurrency_2_acceptance_passed) {
    throw new Error(
      "bounded_concurrency_2 failed the offline under-60 acceptance gate",
    );
  }
}

function parseArgs(
  args: string[],
): { sampleCount: number; outputPath: string } {
  let sampleCount = DEFAULT_SAMPLE_COUNT;
  let outputPath =
    "build-logs/day-generation-under-60/day-generation-under-60-benchmark.json";
  for (const arg of args) {
    if (arg.startsWith("--samples=")) {
      sampleCount = Number.parseInt(arg.slice("--samples=".length), 10);
    } else if (arg.startsWith("--output=")) {
      outputPath = arg.slice("--output=".length);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }
  if (!outputPath) {
    throw new Error("--output must not be empty");
  }
  return { sampleCount, outputPath };
}

async function main(): Promise<void> {
  const { sampleCount, outputPath } = parseArgs(Deno.args);
  const report = await runBenchmark({ sampleCount });
  const separator = outputPath.lastIndexOf("/");
  if (separator > 0) {
    await Deno.mkdir(outputPath.slice(0, separator), { recursive: true });
  }
  await Deno.writeTextFile(
    outputPath,
    JSON.stringify(report, null, 2) + "\n",
  );
  console.log(JSON.stringify(
    {
      output_path: outputPath,
      sample_count: report.sample_count,
      bounded_concurrency_2_acceptance_passed:
        report.bounded_concurrency_2_acceptance_passed,
      architectures: report.architectures.map((metrics) => ({
        architecture: metrics.architecture,
        p50_total_ms: metrics.total_ms.p50,
        p95_total_ms: metrics.total_ms.p95,
        complete_thumbnail_success_count:
          metrics.complete_thumbnail_success_count,
        day_output_validation_pass_count:
          metrics.day_output_validation_pass_count,
        quality_score_pass_count: metrics.quality_score_pass_count,
      })),
    },
    null,
    2,
  ));
  assertOfflineCandidateAccepted(report);
}

if (import.meta.main) {
  await main();
}
