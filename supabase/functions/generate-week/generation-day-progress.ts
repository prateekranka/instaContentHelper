import { isUUID } from "./generation-validation.ts";
import { isQueuedDayJobStale } from "./generation-day-job-store.ts";
import type {
  DayGenerationState,
  DayGenerationStatus,
  PerDayGenerationSnapshot,
  QueuedDayJobRecord,
} from "./generation-status.ts";

/** Minimal saved-card shape needed for progress matching/merge. */
export type SavedDailyCardForProgress = {
  id?: string;
  scheduled_date: string;
  updated_at?: string | null;
};

export type ParallelDayJobLiveness = {
  status?: unknown;
  heartbeat_at?: unknown;
  started_at?: unknown;
};

export type StaleRunningDayOptions = {
  maxAttempts: number;
  staleThresholdMS: number;
  nowMS: number;
  nowISO: string;
  dayJobHeartbeats?: Map<number, string | undefined>;
};

export function savedDailyCardsForProgress<T extends SavedDailyCardForProgress>(
  savedCards: T[],
  progress: PerDayGenerationSnapshot,
): T[] {
  return savedCards.filter((card) =>
    progress.days.some((day) => savedDailyCardMatchesProgressDay(card, day))
  );
}

export function mergeSavedDailyCardsIntoProgress<
  T extends SavedDailyCardForProgress,
>(
  progress: PerDayGenerationSnapshot,
  savedCards: T[],
  nowISO: string,
): PerDayGenerationSnapshot {
  let changed = false;
  const days = progress.days.map((day) => {
    const saved = savedCards.find((card) =>
      savedDailyCardMatchesProgressDay(card, day)
    );
    if (!saved) {
      return day;
    }
    if (
      day.status === "completed" &&
      day.daily_card_id === saved.id &&
      !day.error_code
    ) {
      return day;
    }
    changed = true;
    return {
      ...day,
      status: "completed" as const,
      daily_card_id: saved.id,
      completed_at: day.completed_at ?? saved.updated_at ?? nowISO,
      error_code: undefined,
    };
  });
  return changed ? { ...progress, days, updated_at: nowISO } : progress;
}

export function savedDailyCardMatchesProgressDay(
  card: SavedDailyCardForProgress,
  day: DayGenerationState,
): boolean {
  if (!isUUID(card.id) || card.scheduled_date !== day.scheduled_date) {
    return false;
  }
  if (isUUID(day.daily_card_id) && card.id === day.daily_card_id) {
    return true;
  }
  if (!isAttemptedDayGenerationState(day)) {
    return false;
  }
  return savedDailyCardUpdatedAfterDayStarted(card, day);
}

export function isAttemptedDayGenerationState(
  day: DayGenerationState,
): boolean {
  return day.attempts > 0 ||
    day.status === "running" ||
    day.status === "completed" ||
    day.status === "failed" ||
    Boolean(day.output);
}

export function savedDailyCardUpdatedAfterDayStarted(
  card: Pick<SavedDailyCardForProgress, "updated_at">,
  day: Pick<DayGenerationState, "started_at">,
): boolean {
  const updatedAt = Date.parse(card.updated_at ?? "");
  const startedAt = Date.parse(day.started_at ?? "");
  return Number.isFinite(updatedAt) &&
    Number.isFinite(startedAt) &&
    updatedAt >= startedAt;
}

export function progressReconciledWithDayJobs(
  progress: PerDayGenerationSnapshot,
  jobs: QueuedDayJobRecord[],
  nowISO: string,
): PerDayGenerationSnapshot {
  const jobsByDate = new Map(jobs.map((job) => [job.scheduled_date, job]));
  return {
    ...progress,
    days: progress.days.map((day) => {
      const job = jobsByDate.get(day.scheduled_date);
      if (!job) return day;
      const status: DayGenerationStatus = job.status === "generated"
        ? "completed"
        : job.status === "failed" || job.status === "cancelled"
        ? "failed"
        : job.status === "generating" || job.status === "ready_to_persist"
        ? "running"
        : "pending";
      return {
        scheduled_date: day.scheduled_date,
        status,
        attempts: job.attempt_count ?? 0,
        daily_card_id: job.daily_card_id ?? undefined,
        started_at: job.started_at ?? undefined,
        completed_at: job.completed_at ?? undefined,
        heartbeat_at: job.heartbeat_at ?? undefined,
        error_code: job.error_code ?? undefined,
      };
    }),
    updated_at: nowISO,
  };
}

export function nextParallelDayGenerationIndex(
  progress: PerDayGenerationSnapshot,
  inFlight: Map<number, unknown>,
  maxAttempts: number,
  staleThresholdMS: number,
  nowMS: number,
): number {
  return progress.days.findIndex((day, index) =>
    !inFlight.has(index) &&
    shouldRunDayGeneration(day, maxAttempts, staleThresholdMS, nowMS)
  );
}

export function activeParallelDayGenerationCount(
  progress: PerDayGenerationSnapshot,
  staleThresholdMS: number,
  nowMS: number,
): number {
  return progress.days.filter((day) =>
    day.status === "running" && !isRunningDayStale(day, staleThresholdMS, nowMS)
  ).length;
}

export function hasActiveParallelDayGeneration(
  progress: PerDayGenerationSnapshot,
  staleThresholdMS: number,
  nowMS: number,
): boolean {
  return activeParallelDayGenerationCount(progress, staleThresholdMS, nowMS) >
    0;
}

export function liveParallelDayJobCount(
  jobs: ParallelDayJobLiveness[],
  staleThresholdMS: number,
  nowMS: number,
): number {
  return jobs.filter((job) =>
    job.status === "generating" &&
    !isQueuedDayJobStale(job, staleThresholdMS, nowMS)
  ).length;
}

export function availableParallelDayJobSlots(
  jobs: ParallelDayJobLiveness[],
  concurrency: number,
  staleThresholdMS: number,
  nowMS: number,
): number {
  const liveRunningCount = liveParallelDayJobCount(
    jobs,
    staleThresholdMS,
    nowMS,
  );
  return Math.max(0, concurrency - liveRunningCount);
}

export function shouldResumeParallelWeekGeneration(
  progress: PerDayGenerationSnapshot,
  concurrency: number,
  maxAttempts: number,
  staleThresholdMS: number,
  nowMS: number,
): boolean {
  if (
    !progress.days.some((day) =>
      shouldRunDayGeneration(day, maxAttempts, staleThresholdMS, nowMS)
    )
  ) {
    return false;
  }
  return activeParallelDayGenerationCount(progress, staleThresholdMS, nowMS) <
    concurrency;
}

export function isParallelWeekGenerationTerminal(
  progress: PerDayGenerationSnapshot,
  maxAttempts: number,
): boolean {
  return progress.days.length > 0 &&
    progress.days.every((day) =>
      isTerminalDayGenerationState(day, maxAttempts)
    );
}

export function normalizeStaleRunningDays(
  progress: PerDayGenerationSnapshot,
  options: StaleRunningDayOptions,
): PerDayGenerationSnapshot {
  const {
    maxAttempts,
    staleThresholdMS,
    nowMS,
    nowISO,
    dayJobHeartbeats,
  } = options;
  let changed = false;
  const days = progress.days.map((day, index) => {
    if (day.status !== "running") return day;

    const effectiveHeartbeat = dayJobHeartbeats?.get(index) ?? day.heartbeat_at;
    const effectiveDay: DayGenerationState = effectiveHeartbeat !==
        day.heartbeat_at
      ? { ...day, heartbeat_at: effectiveHeartbeat }
      : day;

    if (isRunningDayStale(effectiveDay, staleThresholdMS, nowMS)) {
      changed = true;
      return staleDayFailure(effectiveDay, maxAttempts, nowISO);
    }
    return effectiveDay !== day ? effectiveDay : day;
  });
  return changed ? { ...progress, days, updated_at: nowISO } : progress;
}

export function shouldRunDayGeneration(
  day: DayGenerationState,
  maxAttempts: number,
  staleThresholdMS: number,
  nowMS: number,
): boolean {
  if (day.status === "pending") {
    return true;
  }
  if (day.status === "failed") {
    return day.attempts < maxAttempts;
  }
  return day.status === "running" &&
    isRunningDayStale(day, staleThresholdMS, nowMS) &&
    day.attempts < maxAttempts;
}

export function isTerminalDayGenerationState(
  day: DayGenerationState,
  maxAttempts: number,
): boolean {
  return day.status === "completed" ||
    (day.status === "failed" && day.attempts >= maxAttempts);
}

export function staleDayFailure(
  day: DayGenerationState,
  maxAttempts: number,
  nowISO: string,
): DayGenerationState {
  if (day.attempts < maxAttempts) {
    return {
      ...day,
      status: "pending",
      started_at: undefined,
      heartbeat_at: undefined,
    };
  }

  return {
    ...day,
    status: "failed",
    completed_at: nowISO,
    error_code: "generation_timeout",
    output: undefined,
  };
}

export function allDaysCompleted(progress: PerDayGenerationSnapshot): boolean {
  return progress.days.length === 7 &&
    progress.days.every((day) => day.status === "completed" && day.output);
}

export function allDaysTerminal(
  progress: PerDayGenerationSnapshot,
  maxAttempts: number,
): boolean {
  return progress.days.length === 7 &&
    progress.days.every((day) =>
      isTerminalDayGenerationState(day, maxAttempts)
    );
}

export function isRunningDayStale(
  day: DayGenerationState,
  staleThresholdMS: number,
  nowMS: number,
): boolean {
  const lastLiveness = day.heartbeat_at ?? day.started_at;
  if (!lastLiveness) {
    return false;
  }
  return nowMS - Date.parse(lastLiveness) > staleThresholdMS;
}

export function isSingleDayGenerationRunActive(
  progress: {
    status: string;
    started_at?: string;
    heartbeat_at?: string;
  },
  staleThresholdMS: number,
  nowMS: number = Date.now(),
): boolean {
  if (progress.status !== "running") {
    return false;
  }
  return !isRunningDayStale(
    {
      scheduled_date: "",
      status: "running",
      attempts: 0,
      started_at: progress.started_at,
      heartbeat_at: progress.heartbeat_at,
    },
    staleThresholdMS,
    nowMS,
  );
}
