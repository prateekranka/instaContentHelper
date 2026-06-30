import {
  addDaysToDateString,
  daysBetweenDateStrings,
  pickWorkingPlan,
  workingPlanScore,
} from "./working-plan-selection.ts";

Deno.test("pickWorkingPlan prefers draft whose week contains today", () => {
  const olderEditedPlan = {
    id: "edited-plan-id",
    week_start_date: "2026-06-28",
    status: "draft",
    updated_at: "2026-06-30T12:00:00Z",
  };
  const newerGeneratedPlan = {
    id: "generated-plan-id",
    week_start_date: "2026-07-07",
    status: "draft",
    updated_at: "2026-06-30T18:00:00Z",
  };

  const selected = pickWorkingPlan(
    [newerGeneratedPlan, olderEditedPlan],
    "2026-06-30",
  );

  assertEquals(selected?.id, "edited-plan-id");
});

Deno.test("pickWorkingPlan breaks ties by updated_at when multiple drafts contain today", () => {
  const olderPlan = {
    id: "older-plan-id",
    week_start_date: "2026-06-28",
    status: "draft",
    updated_at: "2026-06-30T10:00:00Z",
  };
  const newerPlan = {
    id: "newer-plan-id",
    week_start_date: "2026-06-30",
    status: "draft",
    updated_at: "2026-06-30T15:00:00Z",
  };

  const selected = pickWorkingPlan([olderPlan, newerPlan], "2026-06-30");

  assertEquals(selected?.id, "newer-plan-id");
});

Deno.test("workingPlanScore marks current week as containing today", () => {
  const score = workingPlanScore(
    { id: "plan", week_start_date: "2026-06-30", status: "draft" },
    "2026-07-02",
  );

  assertEquals(score.containsToday, true);
  assertEquals(addDaysToDateString("2026-06-30", 6), "2026-07-06");
  assertEquals(daysBetweenDateStrings("2026-06-30", "2026-07-02"), 2);
});

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  if (
    actual !== expected && JSON.stringify(actual) !== JSON.stringify(expected)
  ) {
    throw new Error(
      message ??
        `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
