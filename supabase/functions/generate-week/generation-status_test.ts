import {
  completedDraftStatusSummary,
  dayGenerationStatusResponse,
  initialPerDayGenerationSnapshot,
  normalizePerDayGenerationSnapshot,
  queuedDayJobStatusResponse,
  queuedDayJobStatusSummary,
  weekGenerationStatusSummary,
} from "./generation-status.ts";
import type {
  DayGenerationState,
  QueuedDayJobRecord,
} from "./generation-status.ts";
import type { GeneratedDailyCard } from "./generation.ts";

Deno.test("status snapshots initialize and normalize to the requested week", () => {
  const initial = initialPerDayGenerationSnapshot("2026-06-08");
  assertEquals(initial.kind, "per_day_generation_v1");
  assertEquals(initial.days.length, 7);
  assertEquals(initial.days[0].scheduled_date, "2026-06-08");
  assertEquals(initial.days[6].scheduled_date, "2026-06-14");

  const normalized = normalizePerDayGenerationSnapshot({
    kind: "per_day_generation_v1",
    week_start_date: "wrong-week",
    days: [{
      scheduled_date: "2026-06-08",
      status: "completed",
      attempts: 2,
    }],
  }, "2026-06-08");
  assertEquals(normalized.week_start_date, "2026-06-08");
  assertEquals(normalized.days[0].status, "pending");
  assertEquals(normalized.days[0].attempts, 2);

  const fallback = normalizePerDayGenerationSnapshot(
    { kind: "unknown", days: [] },
    "2026-06-08",
  );
  assertEquals(fallback.kind, "per_day_generation_v1");
  assertEquals(fallback.days.every((day) => day.status === "pending"), true);
});

Deno.test("status summaries preserve day counts and retry mappings", () => {
  const progress = initialPerDayGenerationSnapshot("2026-06-08");
  const days: DayGenerationState[] = progress.days.map((day, index) =>
    index === 0
      ? {
        ...day,
        status: "failed",
        attempts: 3,
        error_code: "provider_failed",
      }
      : {
        ...day,
        status: "completed",
        attempts: 1,
        daily_card_id: `card-${index}`,
      }
  );
  const summary = weekGenerationStatusSummary(
    { ...progress, days },
    "completed",
    (day) =>
      day.status === "completed" ||
      (day.status === "failed" && day.attempts >= 3),
  );
  assertEquals(summary.overall_status, "partial");
  assertEquals(summary.drafted_day_count, 6);
  assertEquals(summary.saved_day_count, 6);
  assertEquals(summary.failed_day_count, 1);
  assertEquals(summary.day_statuses[0].retry_action, "regenerate_day");

  const queued = queuedDayJobStatusSummary([
    queuedJob("ready_to_persist", 0),
    queuedJob("generated", 1, "card-1"),
    queuedJob("failed", 2),
  ]);
  assertEquals(queued.overall_status, "running");
  assertEquals(queued.completed_day_count, 1);
  assertEquals(queued.failed_day_count, 1);
  assertEquals(queued.current_day, "2026-06-08");
  assertEquals(queued.day_statuses[0].status, "generating");
  assertEquals(queued.day_statuses[2].retry_action, "retry_day");

  const dayResponse = dayGenerationStatusResponse(days[0], 0);
  assertEquals(dayResponse.drafted, false);
  assertEquals(dayResponse.error_code, "provider_failed");
  assertEquals(dayResponse.attempt_count, 3);
});

Deno.test("completed draft summaries map cards by requested dates", () => {
  const card = {
    id: "card-1",
    scheduled_date: "2026-06-08",
  } as GeneratedDailyCard;
  const summary = completedDraftStatusSummary({
    daily_cards: [card],
    strategy_summary: "Strategy",
    generated_at: "2026-06-08T08:00:00.000Z",
  }, undefined);
  assertEquals(summary.overall_status, "completed");
  assertEquals(summary.total_day_count, 1);
  assertEquals(summary.saved_day_count, 1);
  assertEquals(summary.day_statuses[0].scheduled_date, "2026-06-08");
  assertEquals(summary.day_statuses[0].daily_card_id, "card-1");
});

function queuedJob(
  status: QueuedDayJobRecord["status"],
  dayIndex: number,
  dailyCardID?: string,
): QueuedDayJobRecord {
  return {
    id: `job-${dayIndex}`,
    generation_run_id: "run-1",
    weekly_plan_id: "plan-1",
    workspace_id: "workspace-1",
    creator_id: "creator-1",
    scheduled_date: `2026-06-${String(8 + dayIndex).padStart(2, "0")}`,
    day_index: dayIndex,
    status,
    daily_card_id: dailyCardID,
  };
}

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  if (!Object.is(actual, expected)) {
    throw new Error(
      message ??
        `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
