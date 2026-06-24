import {
  claimOneJobFromStore,
  type DayJob,
  type DayJobStore,
  processJob,
  recordProcessResult,
} from "./generate-day-worker.ts";

Deno.test("claimOneJobFromStore continues after a lost claim race", async () => {
  const first = makeJob("job-a", "queued", 0, "2026-09-21");
  const second = makeJob("job-b", "queued", 0, "2026-09-22");
  const store = new MemoryDayJobStore([first, second], {
    loseClaimRaceForJobIDs: ["job-a"],
  });
  const lostRaceJobIDs: string[] = [];

  const claimed = await claimOneJobFromStore(store, {
    wait: () => Promise.resolve(),
    now: () => "2026-06-24T00:00:00.000Z",
    onLostRace: (job) => lostRaceJobIDs.push(job.id),
  });

  assertEquals(claimed?.id, "job-b");
  assertEquals(claimed?.status, "generating");
  assertEquals(claimed?.attempt_count, 1);
  assertEquals(lostRaceJobIDs, ["job-a"]);
  assertEquals(store.job("job-a")?.status, "generating");
  assertEquals(store.job("job-b")?.status, "generating");
});

Deno.test("recordProcessResult marks generated jobs with a daily card id", async () => {
  const job = makeJob("job-generated", "generating", 1, "2026-09-21");
  const store = new MemoryDayJobStore([job]);

  await recordProcessResult(
    store,
    job,
    { status: "generated", dailyCardID: "card-1" },
    () => "2026-06-24T00:05:00.000Z",
  );

  assertEquals(store.job("job-generated")?.status, "generated");
  assertEquals(store.job("job-generated")?.daily_card_id, "card-1");
  assertEquals(store.job("job-generated")?.error_code, null);
});

Deno.test("recordProcessResult marks failed jobs with a stable error code", async () => {
  const job = makeJob("job-failed", "generating", 1, "2026-09-22");
  const store = new MemoryDayJobStore([job]);

  await recordProcessResult(
    store,
    job,
    { status: "failed", errorCode: "day_generation_endpoint_http_504" },
    () => "2026-06-24T00:06:00.000Z",
  );

  assertEquals(store.job("job-failed")?.status, "failed");
  assertEquals(
    store.job("job-failed")?.error_code,
    "day_generation_endpoint_http_504",
  );
});

Deno.test("processJob stub path returns a stable failure without network", async () => {
  const job = makeJob("job-stub", "generating", 1, "2026-09-23");

  const result = await processJob(job, {
    stub: true,
    serviceRoleKey: "test-service-role",
    generateWeekFunctionURL: "http://127.0.0.1/functions/v1/generate-week",
    mock: false,
  });

  assertEquals(result, {
    status: "failed",
    errorCode: "day_generation_endpoint_stubbed",
  });
});

class MemoryDayJobStore implements DayJobStore {
  private jobs: DayJob[] = [];
  private lostRaceJobIDs = new Set<string>();

  init(
    jobs: DayJob[],
    options: { loseClaimRaceForJobIDs?: string[] } = {},
  ) {
    this.jobs = jobs.map(copyJob);
    this.lostRaceJobIDs = new Set(options.loseClaimRaceForJobIDs ?? []);
  }

  constructor(
    jobs: DayJob[],
    options: { loseClaimRaceForJobIDs?: string[] } = {},
  ) {
    this.init(jobs, options);
  }

  job(id: string): DayJob | undefined {
    return this.jobs.find((job) => job.id === id);
  }

  async peekJob(): Promise<DayJob | null> {
    const job = this.jobs
      .filter((candidate) =>
        candidate.status === "queued" || candidate.status === "retrying"
      )
      .sort((left, right) =>
        (left.created_at ?? left.id).localeCompare(right.created_at ?? right.id)
      )[0];
    return job ? copyJob(job) : null;
  }

  async claimJob(
    candidate: DayJob,
    fields: { attemptCount: number; now: string },
  ): Promise<DayJob | null> {
    const job = this.job(candidate.id);
    if (!job || (job.status !== "queued" && job.status !== "retrying")) {
      return null;
    }

    if (this.lostRaceJobIDs.delete(candidate.id)) {
      job.status = "generating";
      return null;
    }

    job.status = "generating";
    job.attempt_count = fields.attemptCount;
    job.error_code = null;
    job.updated_at = fields.now;
    return copyJob(job);
  }

  async markGenerated(
    job: DayJob,
    dailyCardID: string | null,
    now: string,
  ): Promise<void> {
    const storedJob = this.job(job.id);
    if (!storedJob || storedJob.status !== "generating") {
      throw new Error("job_not_generating");
    }
    storedJob.status = "generated";
    storedJob.daily_card_id = dailyCardID;
    storedJob.error_code = null;
    storedJob.updated_at = now;
  }

  async markFailed(
    job: DayJob,
    errorCode: string,
    now: string,
  ): Promise<void> {
    const storedJob = this.job(job.id);
    if (!storedJob || storedJob.status !== "generating") {
      throw new Error("job_not_generating");
    }
    storedJob.status = "failed";
    storedJob.error_code = errorCode;
    storedJob.updated_at = now;
  }
}

function makeJob(
  id: string,
  status: DayJob["status"],
  attemptCount: number,
  scheduledDate: string,
): DayJob {
  return {
    id,
    generation_run_id: "generation-1",
    workspace_id: "workspace-1",
    creator_id: "creator-1",
    weekly_plan_id: "plan-1",
    scheduled_date: scheduledDate,
    day_index: Number(scheduledDate.slice(-2)) % 7,
    status,
    attempt_count: attemptCount,
    daily_card_id: null,
    error_code: null,
    created_at: `${scheduledDate}T00:00:00.000Z`,
    updated_at: `${scheduledDate}T00:00:00.000Z`,
  };
}

function copyJob(job: DayJob): DayJob {
  return { ...job };
}

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
