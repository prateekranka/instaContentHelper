import {
  type GenerationStatusHandlerHost,
  readQueuedGenerationStatus,
} from "./generation-status-handler.ts";
import type { QueuedDayJobRecord } from "./generation-status.ts";
import type { GenerationRunStatusRecord } from "./generation-run-snapshot.ts";
import type { SupabaseAdminClient } from "../_shared/device-auth.ts";
import type { GeneratedDailyCard } from "./generation.ts";

function assertEquals(actual: unknown, expected: unknown, message?: string) {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  if (left !== right) {
    throw new Error(message ?? `Expected ${right}, got ${left}`);
  }
}

function queuedJob(
  status: QueuedDayJobRecord["status"],
  dayIndex: number,
  dailyCardID?: string | null,
): QueuedDayJobRecord {
  return {
    id: `job-${dayIndex}`,
    generation_run_id: "55555555-5555-4555-8555-555555555555",
    weekly_plan_id: "66666666-6666-4666-8666-666666666666",
    workspace_id: "11111111-1111-4111-8111-111111111111",
    creator_id: "33333333-3333-4333-8333-333333333333",
    scheduled_date: `2026-06-${String(8 + dayIndex).padStart(2, "0")}`,
    day_index: dayIndex,
    status,
    daily_card_id: dailyCardID ?? null,
  };
}

function stubHost(
  dailyCards: GeneratedDailyCard[] = [],
): GenerationStatusHandlerHost {
  return {
    prepareGenerationFromRun: () => {
      throw new Error("not used");
    },
    prepareSingleDayGenerationFromRun: async () => {
      throw new Error("not used");
    },
    markGenerationRunFailed: async () => undefined,
    updateGenerationProgress: async () => ({ ok: true as const }),
    scheduleNextPendingDayGeneration: async () => {
      throw new Error("not used");
    },
    finalizePerDayGeneration: async () => {
      throw new Error("not used");
    },
    finalizeTerminalPerDayGeneration: async () => {
      throw new Error("not used");
    },
    readSavedDailyCards: async () => ({ dailyCards }),
    scheduleSingleDayGeneration: async () => ({ ok: true as const }),
    runParallelWeekGenerationInBackground: () => undefined,
    parallelWeekWorkerHost:
      {} as GenerationStatusHandlerHost["parallelWeekWorkerHost"],
    makeInitialWeekStrategyOutput: () => {
      throw new Error("not used");
    },
  };
}

Deno.test("readQueuedGenerationStatus assembles running queued progress response", async () => {
  const generationID = "55555555-5555-4555-8555-555555555555";
  const run = {
    id: generationID,
    workspace_id: "11111111-1111-4111-8111-111111111111",
    creator_id: "33333333-3333-4333-8333-333333333333",
    weekly_plan_id: "66666666-6666-4666-8666-666666666666",
    status: "running",
  } as GenerationRunStatusRecord;
  const jobs = [
    queuedJob("generated", 0, "card-0"),
    queuedJob("generating", 1),
    queuedJob("failed", 2),
  ];

  const response = await readQueuedGenerationStatus(
    {} as SupabaseAdminClient,
    generationID,
    run,
    jobs,
    stubHost([
      { id: "card-0", scheduled_date: "2026-06-08" } as GeneratedDailyCard,
    ]),
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.generation_id, generationID);
  assertEquals(body.weekly_plan_id, run.weekly_plan_id);
  assertEquals(body.status, "running");
  assertEquals(body.poll_after_seconds, 5);
  assertEquals(Array.isArray(body.days), true);
  assertEquals(body.days.length, 3);
  assertEquals(body.days[2].retry_action, "retry_day");
  assertEquals(body.daily_cards.length, 1);
});

Deno.test("readQueuedGenerationStatus maps completed queued jobs to draft status", async () => {
  const generationID = "55555555-5555-4555-8555-555555555555";
  const run = {
    id: generationID,
    workspace_id: "11111111-1111-4111-8111-111111111111",
    creator_id: "33333333-3333-4333-8333-333333333333",
    weekly_plan_id: "66666666-6666-4666-8666-666666666666",
    status: "running",
  } as GenerationRunStatusRecord;
  const jobs = Array.from(
    { length: 7 },
    (_, dayIndex) => queuedJob("generated", dayIndex, `card-${dayIndex}`),
  );

  const response = await readQueuedGenerationStatus(
    {} as SupabaseAdminClient,
    generationID,
    run,
    jobs,
    stubHost(),
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.status, "draft");
  assertEquals(body.poll_after_seconds, null);
  assertEquals(body.completed_day_count, 7);
});
