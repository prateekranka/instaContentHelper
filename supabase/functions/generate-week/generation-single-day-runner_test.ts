import { initialSingleDayGenerationSnapshot } from "./generation-run-snapshot.ts";
import type { SingleDayGenerationSnapshot } from "./generation-run-snapshot.ts";
import {
  runDayGenerationPipeline,
  scheduleSingleDayGeneration,
  type SingleDayGenerationLifecycleEvent,
  type SingleDayGenerationStageTimings,
  type SingleDayRunnerHost,
  type SingleDayRunnerPreparedGeneration,
} from "./generation-single-day-runner.ts";
import type { SupabaseAdminClient } from "../_shared/device-auth.ts";
import {
  GenerateWeekValidationError,
  makeMockGeneratedWeek,
} from "./generation.ts";
import type { GeneratedDayOutput } from "./generation.ts";

function assertEquals(actual: unknown, expected: unknown, message?: string) {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  if (left !== right) {
    throw new Error(message ?? `Expected ${right}, got ${left}`);
  }
}

const generationID = "55555555-5555-4555-8555-555555555555";
const weeklyPlanID = "66666666-6666-4666-8666-666666666666";
const weekStartDate = "2026-06-08";
const scheduledDate = "2026-06-10";

function minimalPrepared(
  overrides: Partial<SingleDayRunnerPreparedGeneration> = {},
): SingleDayRunnerPreparedGeneration {
  return {
    request: {
      action: "regenerate_day",
      creator_id: "33333333-3333-4333-8333-333333333333",
      weekly_plan_id: weeklyPlanID,
      scheduled_date: scheduledDate,
      preserve_manual_edits: false,
      mock: true,
      response_mode: "sync",
    },
    session: {
      workspaceID: "11111111-1111-4111-8111-111111111111",
      memberID: "22222222-2222-4222-8222-222222222222",
      role: "owner",
    } as SingleDayRunnerPreparedGeneration["session"],
    plan: {
      id: weeklyPlanID,
      week_start_date: weekStartDate,
      status: "draft",
    },
    inputSnapshot: {
      creator_id: "33333333-3333-4333-8333-333333333333",
      week_start_date: weekStartDate,
      weekly_setup: null,
      creator_profile: {},
      confirmed_references: [],
      reference_extractions: [],
      recent_archive: [],
      idea_bank: [],
      existing_week_cards: [],
      patterns: [],
      trends: [],
      audio_options: [],
      brand_briefs: [],
      key_moments: [],
    } as unknown as SingleDayRunnerPreparedGeneration["inputSnapshot"],
    providers: [],
    model: "openai:gpt-4.1-mini",
    mockEnabled: true,
    ...overrides,
  };
}

function fakeAdmin(): SupabaseAdminClient {
  return {} as SupabaseAdminClient;
}

function stubHost(
  overrides: Partial<SingleDayRunnerHost> = {},
): SingleDayRunnerHost {
  return {
    generateOutput: async () => {
      throw new Error("generateOutput not expected");
    },
    mockOutput: (inputSnapshot, dayIndex) => {
      const mock = makeMockGeneratedWeek(inputSnapshot);
      return {
        strategy_note: mock.strategy_summary,
        warnings: dayIndex === 0 ? mock.warnings : [],
        assumptions: dayIndex === 0 ? mock.assumptions : [],
        daily_card: mock.daily_cards[dayIndex],
        idea_bank: dayIndex === 0 ? mock.idea_bank : [],
        source_summary: mock.source_summary,
      };
    },
    persistRegeneratedDay: async () => {
      throw new Error("persistRegeneratedDay not expected");
    },
    completeDayGenerationRun: async () => ({ ok: true as const }),
    markGenerationRunFailed: async () => undefined,
    stableGenerationError: () => "invalid_generated_week",
    updateGenerationProgress: async () => ({ ok: true as const }),
    scheduleBackgroundTask: () => undefined,
    emitLifecycleEvent: () => undefined,
    ...overrides,
  };
}

Deno.test("scheduleSingleDayGeneration writes running progress and dispatches once", async () => {
  const progressWrites: SingleDayGenerationSnapshot[] = [];
  let dispatchCount = 0;
  const host = stubHost({
    updateGenerationProgress: async (_admin, _generationID, progress) => {
      progressWrites.push(progress);
      return { ok: true as const };
    },
    scheduleBackgroundTask: (promise) => {
      dispatchCount += 1;
      void promise.catch(() => undefined);
    },
  });
  const progress = initialSingleDayGenerationSnapshot(
    minimalPrepared().request,
    "2026-06-10T00:00:00.000Z",
  );

  const result = await scheduleSingleDayGeneration(
    fakeAdmin(),
    generationID,
    minimalPrepared(),
    progress,
    host,
  );

  assertEquals(result, { ok: true });
  assertEquals(progressWrites.length, 1);
  assertEquals(progressWrites[0].status, "running");
  assertEquals(progressWrites[0].started_at, progressWrites[0].updated_at);
  assertEquals(progressWrites[0].scheduled_date, scheduledDate);
  assertEquals(dispatchCount, 1);
});

Deno.test("scheduleSingleDayGeneration propagates progress-write failure without dispatch", async () => {
  let dispatchCount = 0;
  const host = stubHost({
    updateGenerationProgress: async () => ({
      response: new Response(
        JSON.stringify({ error: "generation_progress_write_failed" }),
        { status: 500 },
      ),
    }),
    scheduleBackgroundTask: (promise) => {
      dispatchCount += 1;
      void promise.catch(() => undefined);
    },
  });

  const result = await scheduleSingleDayGeneration(
    fakeAdmin(),
    generationID,
    minimalPrepared(),
    initialSingleDayGenerationSnapshot(minimalPrepared().request),
    host,
  );

  assertEquals("response" in result, true);
  if ("response" in result) {
    assertEquals(result.response.status, 500);
    assertEquals(
      await result.response.json(),
      { error: "generation_progress_write_failed" },
    );
  }
  assertEquals(dispatchCount, 0);
});

Deno.test("runDayGenerationPipeline marks invalid scheduled date failed and returns 400", async () => {
  const failedCodes: string[] = [];
  const lifecycleEvents: SingleDayGenerationLifecycleEvent[] = [];
  const host = stubHost({
    markGenerationRunFailed: async (_admin, _generationID, errorCode) => {
      failedCodes.push(errorCode);
    },
    emitLifecycleEvent: (event) => {
      lifecycleEvents.push(event);
    },
  });
  const prepared = minimalPrepared({
    request: {
      ...minimalPrepared().request,
      scheduled_date: "2026-06-20",
    },
  });

  const result = await runDayGenerationPipeline(
    fakeAdmin(),
    generationID,
    prepared,
    host,
  );

  assertEquals("response" in result, true);
  if ("response" in result) {
    assertEquals(result.response.status, 400);
    assertEquals(await result.response.json(), { error: "date_not_in_plan" });
  }
  assertEquals(failedCodes, ["date_not_in_plan"]);
  assertEquals(lifecycleEvents.length, 1);
  assertEquals(lifecycleEvents[0].phase, "generation_failed");
  assertEquals(lifecycleEvents[0].status, "failed");
  assertEquals(lifecycleEvents[0].day_index, null);
});

Deno.test("runDayGenerationPipeline mock path validates persists completes and emits lifecycle", async () => {
  const lifecycleEvents: SingleDayGenerationLifecycleEvent[] = [];
  const prepared = minimalPrepared({ mockEnabled: true });
  const mockOutput = stubHost().mockOutput(prepared.inputSnapshot, 2);
  const persistedCard = { ...mockOutput.daily_card, id: "card-123" };
  let completedPayload: unknown;
  const host = stubHost({
    mockOutput: () => mockOutput,
    persistRegeneratedDay: async () => ({ dailyCard: persistedCard }),
    completeDayGenerationRun: async (_admin, _generationID, payload) => {
      completedPayload = payload;
      return { ok: true as const };
    },
    emitLifecycleEvent: (event) => {
      lifecycleEvents.push(event);
    },
  });

  const result = await runDayGenerationPipeline(
    fakeAdmin(),
    generationID,
    prepared,
    host,
  );

  assertEquals("payload" in result, true);
  if ("payload" in result) {
    assertEquals(result.payload.generation_id, generationID);
    assertEquals(result.payload.weekly_plan_id, weeklyPlanID);
    assertEquals(result.payload.status, "draft");
    assertEquals(result.payload.target_scheduled_date, scheduledDate);
    assertEquals(result.payload.daily_card, persistedCard);
    assertEquals(result.payload.warnings, mockOutput.warnings);
    assertEquals(result.payload.assumptions, mockOutput.assumptions);
    assertEquals(result.payload.source_summary, mockOutput.source_summary);
    assertEquals(typeof result.payload.generated_at, "string");
  }
  assertEquals(
    (completedPayload as { daily_card: unknown }).daily_card,
    persistedCard,
  );
  assertEquals(lifecycleEvents.map((event) => event.phase), [
    "generation_started",
    "generation_completed",
  ]);
  assertEquals(lifecycleEvents[0].day_index, 2);
  assertEquals(lifecycleEvents[1].status, "completed");
});

Deno.test("runDayGenerationPipeline emits ordered deterministic stage timings", async () => {
  const lifecycleEvents: SingleDayGenerationLifecycleEvent[] = [];
  const stageCalls: string[] = [];
  let clockMS = 0;
  const prepared = minimalPrepared({ mockEnabled: true });
  const mockOutput = stubHost().mockOutput(prepared.inputSnapshot, 2);
  const persistedCard = { ...mockOutput.daily_card, id: "card-timing" };
  const host = stubHost({
    nowMS: () => {
      clockMS += 10;
      return clockMS;
    },
    mockOutput: () => {
      stageCalls.push("text_generation");
      return mockOutput;
    },
    persistRegeneratedDay: async () => {
      stageCalls.push("persistence");
      return { dailyCard: persistedCard };
    },
    attachDayStoryboardThumbnails: async (_admin, _prepared, dailyCard) => {
      stageCalls.push("storyboard_visuals");
      return dailyCard;
    },
    completeDayGenerationRun: async () => {
      stageCalls.push("finalization");
      return { ok: true as const };
    },
    emitLifecycleEvent: (event) => {
      lifecycleEvents.push(event);
    },
  });

  const result = await runDayGenerationPipeline(
    fakeAdmin(),
    generationID,
    prepared,
    host,
  );

  assertEquals("payload" in result, true);
  // Mock skips async visuals; storyboard is not on the script-ready path.
  assertEquals(stageCalls, [
    "text_generation",
    "persistence",
    "finalization",
  ]);
  assertEquals(lifecycleEvents.map((event) => event.phase), [
    "generation_started",
    "generation_completed",
  ]);
  assertEquals(lifecycleEvents[0].stage_timings_ms, {
    text_generation: null,
    validation: null,
    persistence: null,
    storyboard_visuals: null,
    finalization: null,
    total: null,
  });
  const completedTimings = lifecycleEvents[1].stage_timings_ms;
  assertEquals(Object.keys(completedTimings), [
    "text_generation",
    "validation",
    "persistence",
    "storyboard_visuals",
    "finalization",
    "total",
  ]);
  assertEquals(completedTimings, {
    text_generation: 10,
    validation: 10,
    persistence: 10,
    storyboard_visuals: null,
    finalization: 10,
    // Script-ready total excludes async visuals; clock advances on each nowMS().
    total: 100,
  });
  assertEquals(lifecycleEvents[1].visuals_status, "skipped");
  assertCoherentStageTotal(completedTimings);
  assertEquals(lifecycleEvents[1].duration_ms, completedTimings.total);
});

Deno.test("runDayGenerationPipeline retains completed stage timings on persistence failure", async () => {
  const lifecycleEvents: SingleDayGenerationLifecycleEvent[] = [];
  let clockMS = 0;
  const prepared = minimalPrepared({ mockEnabled: true });
  const host = stubHost({
    nowMS: () => {
      clockMS += 10;
      return clockMS;
    },
    persistRegeneratedDay: async () => ({
      response: new Response(
        JSON.stringify({ error: "generation_persist_failed" }),
        { status: 500 },
      ),
    }),
    emitLifecycleEvent: (event) => {
      lifecycleEvents.push(event);
    },
  });

  const result = await runDayGenerationPipeline(
    fakeAdmin(),
    generationID,
    prepared,
    host,
  );

  assertEquals("response" in result, true);
  if ("response" in result) {
    assertEquals(result.response.status, 500);
    assertEquals(await result.response.json(), {
      error: "generation_persist_failed",
    });
  }
  assertEquals(lifecycleEvents.map((event) => event.phase), [
    "generation_started",
    "generation_failed",
  ]);
  const failedTimings = lifecycleEvents[1].stage_timings_ms;
  assertEquals(failedTimings, {
    text_generation: 10,
    validation: 10,
    persistence: 10,
    storyboard_visuals: null,
    finalization: null,
    total: 70,
  });
  assertCoherentStageTotal(failedTimings);
  assertEquals(lifecycleEvents[1].duration_ms, failedTimings.total);
});

Deno.test("runDayGenerationPipeline completes script-ready before async storyboard soft failure", async () => {
  const lifecycleEvents: SingleDayGenerationLifecycleEvent[] = [];
  let clockMS = 0;
  let softFailureHandled = false;
  let backgroundPromise: Promise<unknown> | undefined;
  const prepared = minimalPrepared({ mockEnabled: false });
  const mockOutput = stubHost().mockOutput(prepared.inputSnapshot, 2);
  const persistedCard = { ...mockOutput.daily_card, id: "card-soft-visuals" };
  const host = stubHost({
    nowMS: () => {
      clockMS += 10;
      return clockMS;
    },
    generateOutput: async () => mockOutput,
    persistRegeneratedDay: async () => ({ dailyCard: persistedCard }),
    attachDayStoryboardThumbnails: async (_admin, _prepared, dailyCard) => {
      try {
        throw new Error("synthetic_storyboard_thumbnail_gemini_failed");
      } catch {
        softFailureHandled = true;
        return dailyCard;
      }
    },
    completeDayGenerationRun: async () => ({ ok: true as const }),
    scheduleBackgroundTask: (promise) => {
      backgroundPromise = promise;
    },
    emitLifecycleEvent: (event) => {
      lifecycleEvents.push(event);
    },
  });

  const result = await runDayGenerationPipeline(
    fakeAdmin(),
    generationID,
    prepared,
    host,
  );

  assert("payload" in result, "soft storyboard failure changed HTTP outcome");
  if ("payload" in result) {
    assertEquals(result.payload.visuals_status, "pending");
    assertEquals(
      result.payload.stage_timings_ms?.storyboard_visuals,
      null,
    );
  }
  const completed = lifecycleEvents.find((event) =>
    event.phase === "generation_completed"
  );
  assert(completed !== undefined, "expected completed lifecycle event");
  assertEquals(completed.visuals_status, "pending");
  assertEquals(completed.stage_timings_ms.storyboard_visuals, null);
  assertCoherentStageTotal(completed.stage_timings_ms);
  assertEquals(completed.duration_ms, completed.stage_timings_ms.total);

  assert(backgroundPromise !== undefined, "expected async visuals task");
  await backgroundPromise;
  assert(softFailureHandled, "expected storyboard failure to soft-fail");
  const visualsDone = lifecycleEvents.find((event) =>
    event.phase === "storyboard_visuals_completed" ||
    event.phase === "storyboard_visuals_failed"
  );
  assert(visualsDone !== undefined, "expected visuals lifecycle completion");
  assert(
    typeof visualsDone.stage_timings_ms.storyboard_visuals === "number",
    "async storyboard soft failure was not timed",
  );
});

Deno.test("runDayGenerationPipeline schedules Gemini storyboard attach after script-ready completion", async () => {
  const prepared = minimalPrepared({ mockEnabled: false });
  const mockOutput = stubHost().mockOutput(prepared.inputSnapshot, 2);
  const persistedCard = { ...mockOutput.daily_card, id: "card-storyboard" };
  const storyboardAssets = [{
    row_index: 0,
    prompt_hash: "hash-1",
    public_url: "https://example.com/row-0.jpg",
    status: "generated",
  }];
  let attachCalled = false;
  let completedCard: unknown;
  let completedVisualsStatus: unknown;
  let patchedPayload: unknown;
  let backgroundPromise: Promise<unknown> | undefined;
  let releaseAttach: (() => void) | undefined;
  const attachGate = new Promise<void>((resolve) => {
    releaseAttach = resolve;
  });

  const host = stubHost({
    generateOutput: async () => mockOutput,
    persistRegeneratedDay: async () => ({ dailyCard: persistedCard }),
    attachDayStoryboardThumbnails: async (_admin, _prepared, dailyCard) => {
      await attachGate;
      attachCalled = true;
      return {
        ...dailyCard,
        storyboard_thumbnail_assets: storyboardAssets,
      };
    },
    completeDayGenerationRun: async (_admin, _generationID, payload) => {
      completedCard = payload.daily_card;
      completedVisualsStatus = payload.visuals_status;
      return { ok: true as const };
    },
    patchCompletedDayGenerationSnapshot: async (_admin, _id, payload) => {
      patchedPayload = payload;
      return { ok: true as const };
    },
    scheduleBackgroundTask: (promise) => {
      backgroundPromise = promise;
    },
  });

  const result = await runDayGenerationPipeline(
    fakeAdmin(),
    generationID,
    prepared,
    host,
  );

  assertEquals(attachCalled, false);
  assertEquals("payload" in result, true);
  if ("payload" in result) {
    assertEquals(result.payload.visuals_status, "pending");
    assertEquals(
      result.payload.daily_card.storyboard_thumbnail_assets ?? [],
      persistedCard.storyboard_thumbnail_assets ?? [],
    );
  }
  // Script-ready completion must not wait for thumbs on the critical path.
  assertEquals(
    (completedCard as { storyboard_thumbnail_assets?: unknown })
      .storyboard_thumbnail_assets ?? [],
    persistedCard.storyboard_thumbnail_assets ?? [],
  );
  assertEquals(completedVisualsStatus, "pending");

  assert(backgroundPromise !== undefined, "expected async visuals task");
  releaseAttach?.();
  await backgroundPromise;
  assertEquals(attachCalled, true);
  assertEquals(
    (patchedPayload as {
      daily_card: { storyboard_thumbnail_assets: unknown };
      visuals_status: string;
    }).daily_card.storyboard_thumbnail_assets,
    storyboardAssets,
  );
  assertEquals(
    (patchedPayload as { visuals_status: string }).visuals_status,
    "ready",
  );
});

Deno.test("runDayGenerationPipeline maps provider and validation failures to 400 vs 502", async () => {
  const cases: Array<{
    name: string;
    error: unknown;
    stableCode: string;
    expectedStatus: number;
  }> = [
    {
      name: "validation",
      error: new GenerateWeekValidationError("invalid_ai_json", "bad json"),
      stableCode: "invalid_ai_json",
      expectedStatus: 400,
    },
    {
      name: "provider",
      error: new Error("openai_request_failed: timeout"),
      stableCode: "openai_request_failed",
      expectedStatus: 502,
    },
  ];

  for (const testCase of cases) {
    const failedCodes: string[] = [];
    const prepared = minimalPrepared({ mockEnabled: false });

    const result = await runDayGenerationPipeline(
      fakeAdmin(),
      generationID,
      prepared,
      stubHost({
        generateOutput: async () => {
          throw testCase.error;
        },
        stableGenerationError: () => testCase.stableCode,
        markGenerationRunFailed: async (_admin, _generationID, errorCode) => {
          failedCodes.push(errorCode);
        },
      }),
    );

    assertEquals("response" in result, true, testCase.name);
    if ("response" in result) {
      assertEquals(
        result.response.status,
        testCase.expectedStatus,
        testCase.name,
      );
      const body = await result.response.json() as Record<string, unknown>;
      assertEquals(body.error, testCase.stableCode, testCase.name);
      assertEquals("error_message" in body, true, testCase.name);
    }
    assertEquals(failedCodes, [testCase.stableCode], testCase.name);
  }
});

Deno.test("runDayGenerationPipeline marks failed on persistence and completion errors", async () => {
  const prepared = minimalPrepared({ mockEnabled: true });
  const mockOutput = stubHost().mockOutput(prepared.inputSnapshot, 2);
  const persistedCard = { ...mockOutput.daily_card, id: "card-123" };

  const persistFailedCodes: string[] = [];
  const persistLifecycle: SingleDayGenerationLifecycleEvent[] = [];
  const persistResult = await runDayGenerationPipeline(
    fakeAdmin(),
    generationID,
    prepared,
    stubHost({
      persistRegeneratedDay: async () => ({
        response: new Response(
          JSON.stringify({ error: "generation_persist_failed", step: "x" }),
          { status: 500 },
        ),
      }),
      markGenerationRunFailed: async (_admin, _generationID, errorCode) => {
        persistFailedCodes.push(errorCode);
      },
      emitLifecycleEvent: (event) => {
        persistLifecycle.push(event);
      },
    }),
  );
  assertEquals("response" in persistResult, true);
  if ("response" in persistResult) {
    assertEquals(persistResult.response.status, 500);
  }
  assertEquals(persistFailedCodes, ["generation_persist_failed"]);
  assertEquals(
    persistLifecycle.filter((event) => event.phase === "generation_failed")
      .length,
    1,
  );

  const completionFailedCodes: string[] = [];
  const completionLifecycle: SingleDayGenerationLifecycleEvent[] = [];
  const completionResult = await runDayGenerationPipeline(
    fakeAdmin(),
    generationID,
    prepared,
    stubHost({
      persistRegeneratedDay: async () => ({ dailyCard: persistedCard }),
      completeDayGenerationRun: async () => ({
        response: new Response(
          JSON.stringify({ error: "generation_persist_failed", step: "y" }),
          { status: 500 },
        ),
      }),
      markGenerationRunFailed: async (_admin, _generationID, errorCode) => {
        completionFailedCodes.push(errorCode);
      },
      emitLifecycleEvent: (event) => {
        completionLifecycle.push(event);
      },
    }),
  );
  assertEquals("response" in completionResult, true);
  if ("response" in completionResult) {
    assertEquals(completionResult.response.status, 500);
  }
  assertEquals(completionFailedCodes, ["generation_persist_failed"]);
  assertEquals(completionLifecycle.map((event) => event.phase), [
    "generation_started",
    "generation_failed",
  ]);
});

Deno.test("runDayGenerationPipeline records heartbeat progress while generating", async () => {
  const progressWrites: SingleDayGenerationSnapshot[] = [];
  let releaseGenerate: (() => void) | undefined;
  const generateGate = new Promise<void>((resolve) => {
    releaseGenerate = resolve;
  });
  const prepared = minimalPrepared({ mockEnabled: false });
  const host = stubHost({
    dayHeartbeatIntervalMS: 15,
    generateOutput: async () => {
      await generateGate;
      return stubHost().mockOutput(prepared.inputSnapshot, 2);
    },
    updateGenerationProgress: async (_admin, _generationID, progress) => {
      progressWrites.push(progress);
      return { ok: true as const };
    },
    persistRegeneratedDay: async () => ({
      dailyCard: {
        ...stubHost().mockOutput(prepared.inputSnapshot, 2).daily_card,
        id: "card-123",
      },
    }),
    // Keep heartbeat coverage off the live Gemini path.
    attachDayStoryboardThumbnails: async (_admin, _prepared, dailyCard) =>
      dailyCard,
  });

  const pipelinePromise = runDayGenerationPipeline(
    fakeAdmin(),
    generationID,
    prepared,
    host,
  );
  await new Promise((resolve) => setTimeout(resolve, 30));
  releaseGenerate?.();
  await pipelinePromise;

  assert(
    progressWrites.some((progress) =>
      typeof progress.heartbeat_at === "string" &&
      progress.started_at === progressWrites[0]?.started_at
    ),
    "expected at least one heartbeat write that preserves started_at",
  );
});

function assert(
  condition: unknown,
  message = "Assertion failed",
): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

function assertCoherentStageTotal(
  timings: SingleDayGenerationStageTimings,
): void {
  const completedStageTotal = [
    timings.text_generation,
    timings.validation,
    timings.persistence,
    // Async visuals are excluded from script-ready total coherence.
    timings.finalization,
  ].reduce<number>((total, duration) => total + (duration ?? 0), 0);
  const total = timings.total;
  assert(
    typeof total === "number" && total >= completedStageTotal,
    "total timing must cover every completed script-ready stage",
  );
}
