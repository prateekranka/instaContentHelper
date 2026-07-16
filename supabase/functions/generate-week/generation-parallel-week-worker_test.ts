import { availableParallelDayJobSlots as availableParallelDayJobSlotsFromProgress } from "./generation-day-progress.ts";
import {
  availableParallelDayJobSlots,
  isGenerationRunRecordCancelled,
  maxDayGenerationAttempts,
  parallelWeekGenerationConcurrency,
  runningDayStaleMS,
  shouldDispatchQueuedDayJobRecovery,
} from "./generation-parallel-week-worker.ts";
import { availableParallelDayJobSlots as availableParallelDayJobSlotsFromIndex } from "./index.ts";
import type { QueuedDayJobRecord } from "./generation-status.ts";

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
  run: () => void,
): void {
  const previous = Deno.env.get(name);
  try {
    if (value === undefined) {
      Deno.env.delete(name);
    } else {
      Deno.env.set(name, value);
    }
    run();
  } finally {
    if (previous === undefined) {
      Deno.env.delete(name);
    } else {
      Deno.env.set(name, previous);
    }
  }
}

Deno.test("parallelWeekGenerationConcurrency defaults and clamps env", () => {
  withEnv("MCO_PARALLEL_WEEK_GENERATION_CONCURRENCY", undefined, () => {
    assertEquals(parallelWeekGenerationConcurrency(), 2);
  });
  withEnv("MCO_PARALLEL_WEEK_GENERATION_CONCURRENCY", "0", () => {
    assertEquals(parallelWeekGenerationConcurrency(), 1);
  });
  withEnv("MCO_PARALLEL_WEEK_GENERATION_CONCURRENCY", "99", () => {
    assertEquals(parallelWeekGenerationConcurrency(), 7);
  });
  withEnv("MCO_PARALLEL_WEEK_GENERATION_CONCURRENCY", "not-a-number", () => {
    assertEquals(parallelWeekGenerationConcurrency(), 2);
  });
});

Deno.test("runningDayStaleMS and maxDayGenerationAttempts honor env bounds", () => {
  withEnv("MCO_GENERATION_DAY_STALE_MS", undefined, () => {
    assertEquals(runningDayStaleMS(), 135_000);
  });
  withEnv("MCO_GENERATION_DAY_STALE_MS", "45000", () => {
    assertEquals(runningDayStaleMS(), 45_000);
  });
  withEnv("MCO_GENERATION_DAY_MAX_ATTEMPTS", "9", () => {
    assertEquals(maxDayGenerationAttempts(), 5);
  });
  withEnv("MCO_GENERATION_DAY_MAX_ATTEMPTS", undefined, () => {
    assertEquals(maxDayGenerationAttempts(), 3);
  });
});

Deno.test("shouldDispatchQueuedDayJobRecovery respects ready-to-persist and capacity", () => {
  const now = Date.now();
  const staleHeartbeat = new Date(now - 400_000).toISOString();
  const readyJob = {
    status: "ready_to_persist",
    staged_output: { daily_card: { scheduled_date: "2026-06-08" } },
  } as unknown as QueuedDayJobRecord;
  assertEquals(shouldDispatchQueuedDayJobRecovery([readyJob]), true);

  const fullGenerating = Array.from({ length: 4 }, () => ({
    status: "generating",
    heartbeat_at: new Date(now - 1_000).toISOString(),
    started_at: new Date(now - 1_000).toISOString(),
  })) as QueuedDayJobRecord[];
  withEnv("MCO_PARALLEL_WEEK_GENERATION_CONCURRENCY", "4", () => {
    assertEquals(shouldDispatchQueuedDayJobRecovery(fullGenerating), false);
  });

  const staleGenerating = [{
    status: "generating",
    heartbeat_at: staleHeartbeat,
    started_at: staleHeartbeat,
  }] as QueuedDayJobRecord[];
  withEnv("MCO_PARALLEL_WEEK_GENERATION_CONCURRENCY", "4", () => {
    assertEquals(shouldDispatchQueuedDayJobRecovery(staleGenerating), true);
  });
});

Deno.test("isGenerationRunRecordCancelled matches cancelled and generation_cancelled failed", () => {
  assertEquals(isGenerationRunRecordCancelled({ status: "cancelled" }), true);
  assertEquals(
    isGenerationRunRecordCancelled({
      status: "failed",
      error_code: "generation_cancelled",
    }),
    true,
  );
  assertEquals(isGenerationRunRecordCancelled({ status: "running" }), false);
});

Deno.test("availableParallelDayJobSlots matches progress helper and index re-export", () => {
  const now = Date.now();
  const staleHeartbeat = new Date(now - 400_000).toISOString();
  const jobs = [
    {
      status: "generating",
      heartbeat_at: staleHeartbeat,
      started_at: staleHeartbeat,
    },
    {
      status: "generating",
      heartbeat_at: staleHeartbeat,
      started_at: staleHeartbeat,
    },
    {
      status: "generating",
      heartbeat_at: staleHeartbeat,
      started_at: staleHeartbeat,
    },
    {
      status: "generating",
      heartbeat_at: staleHeartbeat,
      started_at: staleHeartbeat,
    },
    { status: "generated" },
    { status: "generated" },
    { status: "generated" },
  ];

  assertEquals(availableParallelDayJobSlots(jobs, 4, 240_000, now), 4);
  assertEquals(
    availableParallelDayJobSlots(jobs, 4, 240_000, now),
    availableParallelDayJobSlotsFromProgress(jobs, 4, 240_000, now),
  );
  assertEquals(
    availableParallelDayJobSlotsFromIndex(jobs, 4, 240_000, now),
    availableParallelDayJobSlots(jobs, 4, 240_000, now),
  );
});
