import {
  availableParallelDayJobSlots as availableParallelDayJobSlotsFromWorker,
} from "./generation-parallel-week-worker.ts";
import {
  activeParallelDayGenerationCount,
  allDaysCompleted,
  allDaysTerminal,
  availableParallelDayJobSlots,
  hasActiveParallelDayGeneration,
  isAttemptedDayGenerationState,
  isParallelWeekGenerationTerminal,
  isRunningDayStale,
  isSingleDayGenerationRunActive,
  isTerminalDayGenerationState,
  SINGLE_DAY_STARTED_AT_STALE_MS,
  liveParallelDayJobCount,
  mergeSavedDailyCardsIntoProgress,
  nextParallelDayGenerationIndex,
  normalizeStaleRunningDays,
  progressReconciledWithDayJobs,
  savedDailyCardMatchesProgressDay,
  savedDailyCardsForProgress,
  savedDailyCardUpdatedAfterDayStarted,
  shouldResumeParallelWeekGeneration,
  shouldRunDayGeneration,
  staleDayFailure,
} from "./generation-day-progress.ts";
import type {
  DayGenerationState,
  PerDayGenerationSnapshot,
  QueuedDayJobRecord,
} from "./generation-status.ts";
import { initialPerDayGenerationSnapshot } from "./generation-status.ts";
import type { GeneratedDayOutput } from "./generation.ts";

const CARD_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const CARD_B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const CARD_C = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const WEEK_START = "2026-06-08";
const NOW_ISO = "2026-06-15T12:00:00.000Z";
const NOW_MS = Date.parse(NOW_ISO);
const STALE_MS = 240_000;
const MAX_ATTEMPTS = 3;

function assert(
  condition: unknown,
  message = "Assertion failed",
): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

function assertEquals(actual: unknown, expected: unknown, message?: string) {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  if (left !== right) {
    throw new Error(message ?? `Expected ${right}, got ${left}`);
  }
}

function dayState(
  overrides: Partial<DayGenerationState> & { scheduled_date: string },
): DayGenerationState {
  return {
    status: "pending",
    attempts: 0,
    ...overrides,
  };
}

function progressWithDays(
  days: DayGenerationState[],
): PerDayGenerationSnapshot {
  const base = initialPerDayGenerationSnapshot(WEEK_START);
  return {
    ...base,
    days: base.days.map((day) =>
      days.find((override) => override.scheduled_date === day.scheduled_date) ??
        day
    ),
    updated_at: "2026-06-08T00:00:00.000Z",
  };
}

function queuedJob(
  overrides: Partial<QueuedDayJobRecord> & {
    scheduled_date: string;
    day_index: number;
    status: QueuedDayJobRecord["status"];
  },
): QueuedDayJobRecord {
  return {
    id: `job-${overrides.day_index}`,
    generation_run_id: "run",
    weekly_plan_id: "plan",
    workspace_id: "workspace",
    creator_id: "creator",
    attempt_count: 1,
    daily_card_id: null,
    error_code: null,
    error_message: null,
    started_at: null,
    completed_at: null,
    heartbeat_at: null,
    lease_token: null,
    worker_boot_id: null,
    staged_output: null,
    ...overrides,
  };
}

Deno.test("saved-card filtering and merge: exact UUID, attempted fallback, rejections, identity", () => {
  const startedAt = "2026-06-10T10:00:00.000Z";
  const cases: Array<{
    name: string;
    day: DayGenerationState;
    card: { id: string; scheduled_date: string; updated_at?: string };
    matches: boolean;
  }> = [
    {
      name: "exact UUID match",
      day: dayState({
        scheduled_date: WEEK_START,
        daily_card_id: CARD_A,
        status: "pending",
        attempts: 0,
      }),
      card: { id: CARD_A, scheduled_date: WEEK_START, updated_at: startedAt },
      matches: true,
    },
    {
      name: "attempted-day updated-after-start fallback",
      day: dayState({
        scheduled_date: WEEK_START,
        status: "running",
        attempts: 1,
        started_at: startedAt,
      }),
      card: {
        id: CARD_B,
        scheduled_date: WEEK_START,
        updated_at: "2026-06-10T10:00:00.000Z",
      },
      matches: true,
    },
    {
      name: "unattempted day rejects fallback match",
      day: dayState({
        scheduled_date: WEEK_START,
        status: "pending",
        attempts: 0,
      }),
      card: {
        id: CARD_B,
        scheduled_date: WEEK_START,
        updated_at: "2026-06-10T11:00:00.000Z",
      },
      matches: false,
    },
    {
      name: "stale card before started_at rejected",
      day: dayState({
        scheduled_date: WEEK_START,
        status: "failed",
        attempts: 1,
        started_at: startedAt,
      }),
      card: {
        id: CARD_B,
        scheduled_date: WEEK_START,
        updated_at: "2026-06-10T09:59:59.000Z",
      },
      matches: false,
    },
    {
      name: "invalid UUID rejected",
      day: dayState({
        scheduled_date: WEEK_START,
        status: "running",
        attempts: 1,
        started_at: startedAt,
      }),
      card: {
        id: "not-a-uuid",
        scheduled_date: WEEK_START,
        updated_at: "2026-06-10T11:00:00.000Z",
      },
      matches: false,
    },
    {
      name: "date mismatch rejected",
      day: dayState({
        scheduled_date: WEEK_START,
        status: "running",
        attempts: 1,
        started_at: startedAt,
        daily_card_id: CARD_A,
      }),
      card: {
        id: CARD_A,
        scheduled_date: "2026-06-09",
        updated_at: "2026-06-10T11:00:00.000Z",
      },
      matches: false,
    },
  ];

  for (const testCase of cases) {
    assertEquals(
      savedDailyCardMatchesProgressDay(testCase.card, testCase.day),
      testCase.matches,
      testCase.name,
    );
  }

  assertEquals(
    savedDailyCardUpdatedAfterDayStarted(
      { updated_at: startedAt },
      { started_at: startedAt },
    ),
    true,
    "updated_at >= started_at boundary inclusive",
  );
  assert(
    isAttemptedDayGenerationState(
      dayState({ scheduled_date: WEEK_START, status: "running", attempts: 0 }),
    ),
  );

  const progress = progressWithDays([
    dayState({
      scheduled_date: WEEK_START,
      status: "running",
      attempts: 1,
      started_at: startedAt,
      error_code: "provider_failed",
    }),
  ]);
  const matchingCard = {
    id: CARD_C,
    scheduled_date: WEEK_START,
    updated_at: "2026-06-10T11:00:00.000Z",
    title: "Saved",
  };
  const filtered = savedDailyCardsForProgress([matchingCard], progress);
  assertEquals(filtered.map((card) => card.id), [CARD_C]);

  const merged = mergeSavedDailyCardsIntoProgress(
    progress,
    filtered,
    NOW_ISO,
  );
  assertEquals(merged.days[0].status, "completed");
  assertEquals(merged.days[0].daily_card_id, CARD_C);
  assertEquals(merged.days[0].error_code, undefined);
  assertEquals(merged.updated_at, NOW_ISO);

  const alreadyComplete = progressWithDays([
    dayState({
      scheduled_date: WEEK_START,
      status: "completed",
      attempts: 1,
      daily_card_id: CARD_C,
      completed_at: "2026-06-10T11:00:00.000Z",
    }),
  ]);
  const unchanged = mergeSavedDailyCardsIntoProgress(
    alreadyComplete,
    [{ id: CARD_C, scheduled_date: WEEK_START, updated_at: NOW_ISO }],
    NOW_ISO,
  );
  assert(unchanged === alreadyComplete, "unchanged identity when no merge");
});

Deno.test("job reconciliation maps queued statuses and preserves job fields", () => {
  const progress = progressWithDays([]);
  const started = "2026-06-10T09:00:00.000Z";
  const completed = "2026-06-10T09:05:00.000Z";
  const heartbeat = "2026-06-10T09:04:00.000Z";
  const cases: Array<{
    status: QueuedDayJobRecord["status"];
    expected: DayGenerationState["status"];
  }> = [
    { status: "generated", expected: "completed" },
    { status: "failed", expected: "failed" },
    { status: "cancelled", expected: "failed" },
    { status: "generating", expected: "running" },
    { status: "ready_to_persist", expected: "running" },
    { status: "queued", expected: "pending" },
    { status: "retrying", expected: "pending" },
  ];

  for (const [index, testCase] of cases.entries()) {
    const scheduledDate = progress.days[index].scheduled_date;
    const job = queuedJob({
      scheduled_date: scheduledDate,
      day_index: index,
      status: testCase.status,
      attempt_count: 2,
      daily_card_id: CARD_A,
      started_at: started,
      completed_at: completed,
      heartbeat_at: heartbeat,
      error_code: "boom",
    });
    const reconciled = progressReconciledWithDayJobs(
      progress,
      [job],
      NOW_ISO,
    );
    const day = reconciled.days[index];
    assertEquals(day.status, testCase.expected, testCase.status);
    assertEquals(day.attempts, 2, `${testCase.status} attempts`);
    assertEquals(day.daily_card_id, CARD_A, `${testCase.status} daily_card_id`);
    assertEquals(day.started_at, started, `${testCase.status} started_at`);
    assertEquals(
      day.completed_at,
      completed,
      `${testCase.status} completed_at`,
    );
    assertEquals(
      day.heartbeat_at,
      heartbeat,
      `${testCase.status} heartbeat_at`,
    );
    assertEquals(day.error_code, "boom", `${testCase.status} error_code`);
    assertEquals(reconciled.updated_at, NOW_ISO);
  }
});

Deno.test("stale running normalization: heartbeat override and exact boundary", () => {
  const startedAt = new Date(NOW_MS - STALE_MS - 1).toISOString();
  const freshHeartbeat = new Date(NOW_MS - STALE_MS).toISOString();
  const staleHeartbeat = new Date(NOW_MS - STALE_MS - 1).toISOString();

  const progress = progressWithDays([
    dayState({
      scheduled_date: WEEK_START,
      status: "running",
      attempts: 1,
      started_at: startedAt,
      heartbeat_at: staleHeartbeat,
    }),
    dayState({
      scheduled_date: "2026-06-09",
      status: "running",
      attempts: 1,
      started_at: startedAt,
      heartbeat_at: staleHeartbeat,
    }),
    dayState({
      scheduled_date: "2026-06-10",
      status: "running",
      attempts: MAX_ATTEMPTS,
      started_at: startedAt,
      heartbeat_at: staleHeartbeat,
    }),
  ]);

  const normalized = normalizeStaleRunningDays(progress, {
    maxAttempts: MAX_ATTEMPTS,
    staleThresholdMS: STALE_MS,
    nowMS: NOW_MS,
    nowISO: NOW_ISO,
    dayJobHeartbeats: new Map([
      [0, freshHeartbeat],
    ]),
  });

  assertEquals(
    normalized.days[0].status,
    "running",
    "fresh heartbeat override keeps running",
  );
  assertEquals(normalized.days[0].heartbeat_at, freshHeartbeat);
  assertEquals(
    normalized.days[1].status,
    "pending",
    "stale below max attempts retries",
  );
  assertEquals(normalized.days[1].started_at, undefined);
  assertEquals(normalized.days[1].heartbeat_at, undefined);
  assertEquals(normalized.days[2].status, "failed");
  assertEquals(normalized.days[2].error_code, "generation_timeout");
  assertEquals(normalized.days[2].completed_at, NOW_ISO);
  assertEquals(normalized.updated_at, NOW_ISO);

  assertEquals(
    isRunningDayStale(
      dayState({
        scheduled_date: WEEK_START,
        status: "running",
        attempts: 1,
        heartbeat_at: freshHeartbeat,
      }),
      STALE_MS,
      NOW_MS,
    ),
    false,
    "exact boundary is not stale (strict greater-than)",
  );
  assertEquals(
    isRunningDayStale(
      dayState({
        scheduled_date: WEEK_START,
        status: "running",
        attempts: 1,
        heartbeat_at: staleHeartbeat,
      }),
      STALE_MS,
      NOW_MS,
    ),
    true,
  );
  assertEquals(
    isRunningDayStale(
      dayState({
        scheduled_date: WEEK_START,
        status: "running",
        attempts: 1,
        started_at: staleHeartbeat,
      }),
      STALE_MS,
      NOW_MS,
    ),
    true,
    "started_at fallback when heartbeat missing",
  );
});

Deno.test("should-run and terminal behavior below/at max attempts", () => {
  const staleStarted = new Date(NOW_MS - STALE_MS - 1).toISOString();
  const cases: Array<{
    name: string;
    day: DayGenerationState;
    shouldRun: boolean;
    terminal: boolean;
  }> = [
    {
      name: "pending always runs",
      day: dayState({
        scheduled_date: WEEK_START,
        status: "pending",
        attempts: 0,
      }),
      shouldRun: true,
      terminal: false,
    },
    {
      name: "failed below max retries",
      day: dayState({
        scheduled_date: WEEK_START,
        status: "failed",
        attempts: MAX_ATTEMPTS - 1,
      }),
      shouldRun: true,
      terminal: false,
    },
    {
      name: "failed at max is terminal",
      day: dayState({
        scheduled_date: WEEK_START,
        status: "failed",
        attempts: MAX_ATTEMPTS,
      }),
      shouldRun: false,
      terminal: true,
    },
    {
      name: "fresh running does not run again",
      day: dayState({
        scheduled_date: WEEK_START,
        status: "running",
        attempts: 1,
        heartbeat_at: NOW_ISO,
      }),
      shouldRun: false,
      terminal: false,
    },
    {
      name: "stale running below max reruns",
      day: dayState({
        scheduled_date: WEEK_START,
        status: "running",
        attempts: MAX_ATTEMPTS - 1,
        started_at: staleStarted,
      }),
      shouldRun: true,
      terminal: false,
    },
    {
      name: "stale running at max does not rerun",
      day: dayState({
        scheduled_date: WEEK_START,
        status: "running",
        attempts: MAX_ATTEMPTS,
        started_at: staleStarted,
      }),
      shouldRun: false,
      terminal: false,
    },
    {
      name: "completed is terminal",
      day: dayState({
        scheduled_date: WEEK_START,
        status: "completed",
        attempts: 1,
      }),
      shouldRun: false,
      terminal: true,
    },
  ];

  for (const testCase of cases) {
    assertEquals(
      shouldRunDayGeneration(testCase.day, MAX_ATTEMPTS, STALE_MS, NOW_MS),
      testCase.shouldRun,
      `${testCase.name} shouldRun`,
    );
    assertEquals(
      isTerminalDayGenerationState(testCase.day, MAX_ATTEMPTS),
      testCase.terminal,
      `${testCase.name} terminal`,
    );
  }
});

Deno.test("staleDayFailure retryable vs terminal timeout with explicit nowISO", () => {
  const day = dayState({
    scheduled_date: WEEK_START,
    status: "running",
    attempts: MAX_ATTEMPTS - 1,
    started_at: "2026-06-10T10:00:00.000Z",
    heartbeat_at: "2026-06-10T10:01:00.000Z",
  });
  const retryable = staleDayFailure(day, MAX_ATTEMPTS, NOW_ISO);
  assertEquals(retryable.status, "pending");
  assertEquals(retryable.started_at, undefined);
  assertEquals(retryable.heartbeat_at, undefined);

  const terminal = staleDayFailure(
    { ...day, attempts: MAX_ATTEMPTS },
    MAX_ATTEMPTS,
    NOW_ISO,
  );
  assertEquals(terminal.status, "failed");
  assertEquals(terminal.error_code, "generation_timeout");
  assertEquals(terminal.completed_at, NOW_ISO);
  assertEquals(terminal.output, undefined);
});

Deno.test("active count, next index, and resume decisions with injected config", () => {
  const staleStarted = new Date(NOW_MS - STALE_MS - 1).toISOString();
  const progress = progressWithDays([
    dayState({
      scheduled_date: WEEK_START,
      status: "running",
      attempts: 1,
      heartbeat_at: NOW_ISO,
    }),
    dayState({
      scheduled_date: "2026-06-09",
      status: "pending",
      attempts: 0,
    }),
    dayState({
      scheduled_date: "2026-06-10",
      status: "running",
      attempts: 1,
      started_at: staleStarted,
    }),
  ]);

  assertEquals(
    activeParallelDayGenerationCount(progress, STALE_MS, NOW_MS),
    1,
  );
  assertEquals(
    hasActiveParallelDayGeneration(progress, STALE_MS, NOW_MS),
    true,
  );
  assertEquals(
    nextParallelDayGenerationIndex(
      progress,
      new Map([[0, true]]),
      MAX_ATTEMPTS,
      STALE_MS,
      NOW_MS,
    ),
    1,
  );
  assertEquals(
    shouldResumeParallelWeekGeneration(
      progress,
      2,
      MAX_ATTEMPTS,
      STALE_MS,
      NOW_MS,
    ),
    true,
  );
  assertEquals(
    shouldResumeParallelWeekGeneration(
      progress,
      1,
      MAX_ATTEMPTS,
      STALE_MS,
      NOW_MS,
    ),
    false,
    "at concurrency capacity does not resume",
  );
  assertEquals(
    isParallelWeekGenerationTerminal(progress, MAX_ATTEMPTS),
    false,
  );
});

Deno.test("allDaysCompleted and allDaysTerminal require seven days", () => {
  const output = {
    daily_card: { scheduled_date: WEEK_START },
  } as unknown as GeneratedDayOutput;
  const sixCompleted = {
    ...initialPerDayGenerationSnapshot(WEEK_START),
    days: initialPerDayGenerationSnapshot(WEEK_START).days.slice(0, 6).map(
      (day) => ({
        ...day,
        status: "completed" as const,
        attempts: 1,
        output,
      }),
    ),
  };
  assertEquals(allDaysCompleted(sixCompleted), false);
  assertEquals(allDaysTerminal(sixCompleted, MAX_ATTEMPTS), false);

  const sevenCompleted = progressWithDays(
    initialPerDayGenerationSnapshot(WEEK_START).days.map((day) => ({
      ...day,
      status: "completed" as const,
      attempts: 1,
      output,
    })),
  );
  assertEquals(allDaysCompleted(sevenCompleted), true);
  assertEquals(allDaysTerminal(sevenCompleted, MAX_ATTEMPTS), true);

  const mixedTerminal = progressWithDays(
    initialPerDayGenerationSnapshot(WEEK_START).days.map((day, index) =>
      index === 0
        ? {
          ...day,
          status: "failed" as const,
          attempts: MAX_ATTEMPTS,
        }
        : {
          ...day,
          status: "completed" as const,
          attempts: 1,
          output,
        }
    ),
  );
  assertEquals(allDaysCompleted(mixedTerminal), false);
  assertEquals(allDaysTerminal(mixedTerminal, MAX_ATTEMPTS), true);
});

Deno.test("live job count and available slots exclude stale generating jobs", () => {
  const staleHeartbeat = new Date(NOW_MS - STALE_MS - 1).toISOString();
  const freshHeartbeat = new Date(NOW_MS - 1_000).toISOString();
  const jobs = [
    { status: "generating", heartbeat_at: freshHeartbeat },
    {
      status: "generating",
      heartbeat_at: staleHeartbeat,
      started_at: staleHeartbeat,
    },
    { status: "queued" },
    { status: "ready_to_persist", heartbeat_at: freshHeartbeat },
  ];

  assertEquals(liveParallelDayJobCount(jobs, STALE_MS, NOW_MS), 1);
  assertEquals(availableParallelDayJobSlots(jobs, 4, STALE_MS, NOW_MS), 3);
  assertEquals(availableParallelDayJobSlots(jobs, 1, STALE_MS, NOW_MS), 0);
});

Deno.test("public availableParallelDayJobSlots compatibility shape", () => {
  const jobs = [
    {
      status: "generating",
      heartbeat_at: new Date(NOW_MS - STALE_MS - 1).toISOString(),
    },
  ];
  assertEquals(
    availableParallelDayJobSlotsFromWorker(jobs, 2, STALE_MS, NOW_MS),
    2,
  );
  assertEquals(
    availableParallelDayJobSlots(jobs, 2, STALE_MS, NOW_MS),
    availableParallelDayJobSlotsFromWorker(jobs, 2, STALE_MS, NOW_MS),
  );
  assertEquals(
    typeof availableParallelDayJobSlotsFromWorker(jobs, 2, STALE_MS),
    "number",
    "worker export keeps optional now default",
  );
});

Deno.test("isSingleDayGenerationRunActive uses heartbeat threshold when heartbeat exists", () => {
  const staleHeartbeat = "2026-06-10T09:00:00.000Z";
  const freshStartedAt = "2026-06-10T11:00:00.000Z";
  assertEquals(
    isSingleDayGenerationRunActive(
      {
        status: "running",
        started_at: freshStartedAt,
        heartbeat_at: staleHeartbeat,
      },
      STALE_MS,
      NOW_MS,
    ),
    false,
    "stale heartbeat should mark the run inactive even when started_at is fresh",
  );
  assertEquals(
    isSingleDayGenerationRunActive(
      {
        status: "running",
        started_at: staleHeartbeat,
        heartbeat_at: NOW_ISO,
      },
      STALE_MS,
      NOW_MS,
    ),
    true,
    "fresh heartbeat should keep the run active even when started_at is stale",
  );
});

Deno.test("isSingleDayGenerationRunActive falls back to 10-minute started_at without heartbeat", () => {
  const fourMinutesAgo = new Date(NOW_MS - 4 * 60 * 1000).toISOString();
  const elevenMinutesAgo = new Date(
    NOW_MS - SINGLE_DAY_STARTED_AT_STALE_MS - 60_000,
  ).toISOString();

  assertEquals(
    isSingleDayGenerationRunActive(
      {
        status: "running",
        started_at: fourMinutesAgo,
      },
      STALE_MS,
      NOW_MS,
    ),
    true,
    "no heartbeat and a 4-minute started_at should remain active",
  );
  assertEquals(
    isSingleDayGenerationRunActive(
      {
        status: "running",
        started_at: elevenMinutesAgo,
      },
      STALE_MS,
      NOW_MS,
    ),
    false,
    "no heartbeat and a greater-than-10-minute started_at should become recoverable",
  );
});

Deno.test("isSingleDayGenerationRunActive treats running without valid timestamps as active", () => {
  assertEquals(
    isSingleDayGenerationRunActive(
      { status: "running" },
      STALE_MS,
      NOW_MS,
    ),
    true,
    "running without valid timestamps should stay active",
  );
  assertEquals(
    isSingleDayGenerationRunActive(
      { status: "pending", started_at: NOW_ISO },
      STALE_MS,
      NOW_MS,
    ),
    false,
    "pending runs are never active",
  );
});
