export type WeeklyPlanRecord = Record<string, unknown> & {
  id: string;
  week_start_date?: string;
  weekly_setup_id?: string | null;
  status?: string;
  updated_at?: string;
};

export function utcTodayDateString(): string {
  return new Date().toISOString().slice(0, 10);
}

export function addDaysToDateString(date: string, days: number): string {
  const parsed = new Date(`${date}T00:00:00Z`);
  parsed.setUTCDate(parsed.getUTCDate() + days);
  return parsed.toISOString().slice(0, 10);
}

export function daysBetweenDateStrings(start: string, end: string): number {
  const startMs = Date.parse(`${start}T00:00:00Z`);
  const endMs = Date.parse(`${end}T00:00:00Z`);
  return Math.round((endMs - startMs) / 86_400_000);
}

export function workingPlanScore(
  plan: WeeklyPlanRecord,
  today: string,
): { containsToday: boolean; weekDistance: number } {
  const weekStart = String(plan.week_start_date ?? "");
  if (!weekStart) {
    return { containsToday: false, weekDistance: Number.MAX_SAFE_INTEGER };
  }

  const weekEnd = addDaysToDateString(weekStart, 6);
  const containsToday = weekStart <= today && today <= weekEnd;
  const weekDistance = weekStart >= today
    ? daysBetweenDateStrings(today, weekStart)
    : 1_000 + daysBetweenDateStrings(weekStart, today);

  return { containsToday, weekDistance };
}

export function pickWorkingPlan(
  planRows: WeeklyPlanRecord[],
  today: string,
): WeeklyPlanRecord | null {
  const drafts = planRows.filter((row) =>
    row.status === "draft" || row.status === "reviewed"
  );
  if (drafts.length === 0) return null;
  if (drafts.length === 1) return drafts[0];

  return [...drafts].sort((left, right) => {
    const leftScore = workingPlanScore(left, today);
    const rightScore = workingPlanScore(right, today);

    if (leftScore.containsToday !== rightScore.containsToday) {
      return leftScore.containsToday ? -1 : 1;
    }

    if (leftScore.weekDistance !== rightScore.weekDistance) {
      return leftScore.weekDistance - rightScore.weekDistance;
    }

    const leftUpdated = String(left.updated_at ?? "");
    const rightUpdated = String(right.updated_at ?? "");
    return rightUpdated.localeCompare(leftUpdated);
  })[0] ?? null;
}
