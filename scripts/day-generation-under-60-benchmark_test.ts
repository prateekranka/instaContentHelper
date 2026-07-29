import {
  buildOfflineValidatedDayOutput,
  createDeterministicThumbnailAssets,
  DEFAULT_SAMPLE_COUNT,
  EXPECTED_THUMBNAIL_COUNT,
  hasCompleteDailyCardContract,
  meetsOfflineLatencyTargets,
  offlineArchitectureAccepted,
  PERCENTILE_METHOD,
  percentileLinearNMinus1,
  runBenchmark,
  simulateSampleTiming,
  simulateVisualStage,
} from "./day-generation-under-60-benchmark.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  if (!Object.is(actual, expected)) {
    throw new Error(message ?? `Expected ${expected}, got ${actual}`);
  }
}

Deno.test("offline benchmark gates bounded concurrency 2 across 20 complete day outputs", async () => {
  const report = await runBenchmark();

  assertEquals(report.sample_count, DEFAULT_SAMPLE_COUNT);
  assertEquals(report.architectures.length, 3);
  assertEquals(report.samples.length, DEFAULT_SAMPLE_COUNT);
  assertEquals(report.network_calls, false);
  assertEquals(report.provider_calls, false);
  assertEquals(report.secrets_used, false);
  assertEquals(report.fake_profile.fake_only, true);
  assertEquals(report.percentile_method, PERCENTILE_METHOD);
  assertEquals(report.bounded_concurrency_2_acceptance_passed, true);

  for (const metrics of report.architectures) {
    assertEquals(metrics.expected_thumbnail_count, EXPECTED_THUMBNAIL_COUNT);
    assertEquals(metrics.complete_thumbnail_success_count, 20);
    assertEquals(metrics.day_output_validation_pass_count, 20);
    assertEquals(metrics.complete_daily_card_contract_pass_count, 20);
    assertEquals(metrics.quality_score_pass_count, 20);
  }
  const candidate = report.architectures.find((metrics) =>
    metrics.architecture === "bounded_concurrency_2"
  );
  assert(candidate !== undefined, "bounded concurrency 2 metrics missing");
  assertEquals(candidate.offline_acceptance_passed, true);
  assertEquals(candidate.p50_total_under_45_seconds, true);
  assertEquals(candidate.p95_total_under_60_seconds, true);
});

Deno.test("production bounded scheduler lowers virtual visual and total stages", async () => {
  const serial = await simulateSampleTiming(7, 1);
  const bounded2 = await simulateSampleTiming(7, 2);
  const bounded3 = await simulateSampleTiming(7, 3);

  assert(
    bounded2.visuals_stage_ms < serial.visuals_stage_ms,
    "two visual lanes should beat serial storyboard timing",
  );
  assert(
    bounded3.visuals_stage_ms < bounded2.visuals_stage_ms,
    "three visual lanes should beat two visual lanes",
  );
  assert(
    bounded3.total_ms < bounded2.total_ms &&
      bounded2.total_ms < serial.total_ms,
    "bounded visual concurrency should reduce total virtual time",
  );
  assertEquals(
    await simulateVisualStage([100, 200, 300, 400, 500], 1),
    1_500,
  );
  assertEquals(
    await simulateVisualStage([100, 200, 300, 400, 500], 2),
    900,
  );
});

Deno.test("benchmark is deterministic and enforces the production thumbnail contract", async () => {
  const first = await runBenchmark();
  const second = await runBenchmark();
  assertEquals(JSON.stringify(first), JSON.stringify(second));

  const output = buildOfflineValidatedDayOutput(0);
  const assets = createDeterministicThumbnailAssets(0);
  assert(
    hasCompleteDailyCardContract(output),
    "production-shaped five-thumbnail card should pass the contract gate",
  );
  assertEquals(
    JSON.stringify(assets.map((asset) => asset.row_index)),
    JSON.stringify([0, 1, 2, 3, 4]),
  );
  assert(
    assets.every((asset) =>
      asset.status === "generated" &&
      Boolean(asset.storage_path) &&
      Boolean(asset.public_url)
    ),
    "fixture assets should use generated status and nonempty storage/public fields",
  );

  const duplicateRowOutput = {
    ...output,
    daily_card: {
      ...output.daily_card,
      storyboard_thumbnail_assets: assets.map((asset, index) =>
        index === 4 ? { ...asset, row_index: 3 } : asset
      ),
    },
  };
  assert(
    !hasCompleteDailyCardContract(duplicateRowOutput),
    "duplicate row indexes must fail the thumbnail contract",
  );
  const missingPublicURLOutput = {
    ...output,
    daily_card: {
      ...output.daily_card,
      storyboard_thumbnail_assets: assets.map((asset, index) =>
        index === 2 ? { ...asset, public_url: "" } : asset
      ),
    },
  };
  assert(
    !hasCompleteDailyCardContract(missingPublicURLOutput),
    "missing public URLs must fail the thumbnail contract",
  );

  const partialOutput = {
    daily_card: {
      storyboard_thumbnail_assets: Array.from(
        { length: EXPECTED_THUMBNAIL_COUNT },
        () => ({ status: "generated" }),
      ),
    },
  } as never;
  assert(
    !hasCompleteDailyCardContract(partialOutput),
    "a partial card must fail even when all thumbnail records exist",
  );
  const textOnlyOutput = {
    daily_card: {
      storyboard_thumbnail_assets: [],
    },
  } as never;
  assert(
    !hasCompleteDailyCardContract(textOnlyOutput),
    "text-only output must fail the complete daily-card contract",
  );
});

Deno.test("offline gate uses locked percentiles, strict p95, and complete contracts", async () => {
  const exactVector = Array.from({ length: 20 }, (_, index) => index * 1_000);
  assertEquals(percentileLinearNMinus1(exactVector, 0.5), 9_500);
  assertEquals(percentileLinearNMinus1(exactVector, 0.95), 18_050);
  assertEquals(meetsOfflineLatencyTargets(45_000, 59_999), true);
  assertEquals(meetsOfflineLatencyTargets(45_000, 60_000), false);
  assertEquals(meetsOfflineLatencyTargets(45_001, 59_999), false);

  const report = await runBenchmark({ includeConcurrency3: false });
  const candidate = report.architectures.find((metrics) =>
    metrics.architecture === "bounded_concurrency_2"
  );
  assert(candidate !== undefined, "bounded concurrency 2 metrics missing");
  assertEquals(offlineArchitectureAccepted(candidate), true);
  assertEquals(
    offlineArchitectureAccepted({
      ...candidate,
      total_ms: { ...candidate.total_ms, p95: 60_000 },
    }),
    false,
    "exactly 60 seconds must fail the strict p95 gate",
  );
  assertEquals(
    offlineArchitectureAccepted({
      ...candidate,
      complete_daily_card_contract_pass_count: DEFAULT_SAMPLE_COUNT - 1,
    }),
    false,
    "one incomplete card must fail the candidate gate",
  );
});
