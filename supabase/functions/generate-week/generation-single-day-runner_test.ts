import { initialSingleDayGenerationSnapshot } from "./generation-run-snapshot.ts";
import type { SingleDayGenerationSnapshot } from "./generation-run-snapshot.ts";
import {
  runDayGenerationPipeline,
  scheduleSingleDayGeneration,
  type SingleDayGenerationLifecycleEvent,
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
      assertEquals(
        await result.response.json(),
        { error: testCase.stableCode },
        testCase.name,
      );
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
