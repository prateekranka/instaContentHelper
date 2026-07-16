import { initialPerDayGenerationSnapshot } from "./generation-status.ts";
import type { PerDayGenerationSnapshot } from "./generation-status.ts";
import {
  dayGenerationPhase,
  dayGenerationRetryContext,
  finalizePerDayGeneration,
  type PerDayRunnerHost,
  type PerDayRunnerPreparedGeneration,
  scheduleNextPendingDayGeneration,
} from "./generation-per-day-runner.ts";
import type { SupabaseAdminClient } from "../_shared/device-auth.ts";
import { makeMockGeneratedWeek } from "./generation.ts";
import type { GeneratedDayOutput } from "./generation.ts";
import type { GenerationRunStatusRecord } from "./generation-run-snapshot.ts";

function assertEquals(actual: unknown, expected: unknown, message?: string) {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  if (left !== right) {
    throw new Error(message ?? `Expected ${right}, got ${left}`);
  }
}

function withEnv(
  name: string,
  value: string | undefined,
  run: () => void | Promise<void>,
): Promise<void> {
  const previous = Deno.env.get(name);
  return Promise.resolve().then(async () => {
    try {
      if (value === undefined) {
        Deno.env.delete(name);
      } else {
        Deno.env.set(name, value);
      }
      await run();
    } finally {
      if (previous === undefined) {
        Deno.env.delete(name);
      } else {
        Deno.env.set(name, previous);
      }
    }
  });
}

function progressWithRunningDay(
  scheduledDate: string,
  startedAt: string,
  attempts: number,
): PerDayGenerationSnapshot {
  const progress = initialPerDayGenerationSnapshot("2026-06-08");
  return {
    ...progress,
    days: progress.days.map((day) =>
      day.scheduled_date === scheduledDate
        ? {
          ...day,
          status: "running",
          attempts,
          started_at: startedAt,
        }
        : day
    ),
  };
}

function minimalPrepared(): PerDayRunnerPreparedGeneration {
  return {
    request: {
      creator_id: "33333333-3333-4333-8333-333333333333",
      week_start_date: "2026-06-08",
      mode: "generate_draft",
      preserve_manual_edits: false,
      mock: true,
      response_mode: "async",
    },
    session: {
      workspaceID: "11111111-1111-4111-8111-111111111111",
      memberID: "22222222-2222-4222-8222-222222222222",
      role: "owner",
    } as PerDayRunnerPreparedGeneration["session"],
    weeklySetup: null,
    inputSnapshot: {
      week_start_date: "2026-06-08",
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
    } as unknown as PerDayRunnerPreparedGeneration["inputSnapshot"],
    providers: [],
    model: "openai:gpt-4.1-mini",
    mockEnabled: true,
  };
}

function fakeProgressAdmin(): SupabaseAdminClient {
  return {
    from: () => ({
      update: () => ({
        eq: () => ({
          eq: () => Promise.resolve({ error: null }),
        }),
      }),
    }),
  } as unknown as SupabaseAdminClient;
}

function completedProgress(
  inputSnapshot: PerDayRunnerPreparedGeneration["inputSnapshot"],
): PerDayGenerationSnapshot {
  const progress = initialPerDayGenerationSnapshot("2026-06-08");
  const generated = makeMockGeneratedWeek(inputSnapshot);
  return {
    ...progress,
    days: progress.days.map((day, index) => ({
      ...day,
      status: "completed" as const,
      attempts: 1,
      output: {
        strategy_note: `note-${day.scheduled_date}`,
        warnings: [],
        assumptions: [],
        daily_card: generated.daily_cards[index],
        idea_bank: [],
        source_summary: `source-${day.scheduled_date}`,
      } satisfies GeneratedDayOutput,
    })),
  };
}

function stubHost(
  overrides: Partial<PerDayRunnerHost> = {},
): PerDayRunnerHost {
  return {
    generateDayOutput: async () => {
      throw new Error("generateDayOutput not expected");
    },
    markGenerationRunFailed: async () => undefined,
    persistGeneratedWeek: async () => {
      throw new Error("persistGeneratedWeek not expected");
    },
    makeGenerateWeekDraftResponse: () => {
      throw new Error("makeGenerateWeekDraftResponse not expected");
    },
    completeGenerationRun: async () => ({ ok: true as const }),
    persistenceFailureStep: async () => null,
    makeInitialWeekStrategyOutput: () => {
      throw new Error("makeInitialWeekStrategyOutput not expected");
    },
    scheduleBackgroundTask: () => undefined,
    ...overrides,
  };
}

Deno.test("dayGenerationRetryContext is undefined on first attempt", () => {
  assertEquals(
    dayGenerationRetryContext(
      {
        scheduled_date: "2026-06-08",
        status: "pending",
        attempts: 0,
      },
      0,
      1,
    ),
    undefined,
  );
});

Deno.test("dayGenerationRetryContext builds stale_day_repair for stale running days", () => {
  const context = dayGenerationRetryContext(
    {
      scheduled_date: "2026-06-09",
      status: "running",
      attempts: 2,
      started_at: "2026-06-09T00:00:00.000Z",
    },
    1,
    3,
  );
  assertEquals(context?.retry_kind, "stale_day_repair");
  assertEquals(context?.retry_reason, "generation_stale");
  assertEquals(context?.day_index, 2);
  assertEquals(context?.day_attempt, 3);
});

Deno.test("dayGenerationRetryContext builds failed_day_repair with prior error code", () => {
  const context = dayGenerationRetryContext(
    {
      scheduled_date: "2026-06-10",
      status: "failed",
      attempts: 1,
      error_code: "openai_request_failed",
    },
    2,
    2,
  );
  assertEquals(context?.retry_kind, "failed_day_repair");
  assertEquals(context?.retry_reason, "openai_request_failed");
});

Deno.test("dayGenerationPhase distinguishes async and parallel snapshots", () => {
  const asyncProgress = initialPerDayGenerationSnapshot("2026-06-08");
  assertEquals(dayGenerationPhase(asyncProgress), "async_day_generation");

  const parallelProgress = {
    ...asyncProgress,
    kind: "parallel_week_generation_v1" as const,
    weekly_plan_id: "66666666-6666-4666-8666-666666666666",
    strategy_summary: "Parallel week",
  };
  assertEquals(dayGenerationPhase(parallelProgress), "parallel_day_generation");
});

Deno.test("scheduleNextPendingDayGeneration returns unchanged progress when a day is actively running", async () => {
  const progress = progressWithRunningDay(
    "2026-06-08",
    new Date().toISOString(),
    1,
  );
  const result = await scheduleNextPendingDayGeneration(
    {} as SupabaseAdminClient,
    "55555555-5555-4555-8555-555555555555",
    minimalPrepared(),
    progress,
    stubHost(),
  );
  assertEquals("progress" in result, true);
  if ("progress" in result) {
    assertEquals(result.progress.days[0].status, "running");
  }
});

Deno.test("scheduleNextPendingDayGeneration normalizes stale running days before scheduling", async () => {
  await withEnv("MCO_GENERATION_DAY_STALE_MS", "60000", async () => {
    const staleStartedAt = new Date(Date.now() - 120_000).toISOString();
    const progress = progressWithRunningDay(
      "2026-06-08",
      staleStartedAt,
      2,
    );
    progress.days[1] = {
      ...progress.days[1],
      status: "pending",
      attempts: 0,
    };

    let scheduled = false;
    const result = await scheduleNextPendingDayGeneration(
      fakeProgressAdmin(),
      "55555555-5555-4555-8555-555555555555",
      minimalPrepared(),
      progress,
      stubHost({
        scheduleBackgroundTask: () => {
          scheduled = true;
        },
      }),
    );

    assertEquals("progress" in result, true);
    if ("progress" in result) {
      assertEquals(result.progress.days[0].status, "running");
      assertEquals(result.progress.days[0].attempts, 3);
      assertEquals(scheduled, true);
    }
  });
});

Deno.test("finalizePerDayGeneration falls back to the session member for blank stored member IDs", async () => {
  const prepared = minimalPrepared();
  let persistedMemberID: string | undefined;
  const result = await finalizePerDayGeneration(
    {} as SupabaseAdminClient,
    "55555555-5555-4555-8555-555555555555",
    {
      id: "55555555-5555-4555-8555-555555555555",
      workspace_id: prepared.session.workspaceID,
      creator_id: prepared.request.creator_id,
      requested_by_member_id: "   ",
    } as GenerationRunStatusRecord,
    prepared.session,
    prepared.inputSnapshot,
    completedProgress(prepared.inputSnapshot),
    stubHost({
      persistGeneratedWeek: async (
        _admin,
        _workspaceID,
        _request,
        memberID,
      ) => {
        persistedMemberID = memberID;
        return {
          weeklyPlanID: "66666666-6666-4666-8666-666666666666",
          dailyCards: [],
          ideaBank: [],
        };
      },
      makeGenerateWeekDraftResponse: () => ({
        generation_id: "55555555-5555-4555-8555-555555555555",
      } as never),
    }),
  );

  assertEquals("payload" in result, true);
  assertEquals(persistedMemberID, prepared.session.memberID);
});
