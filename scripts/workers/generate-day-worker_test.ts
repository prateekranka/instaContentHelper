import {
  claimOneJobFromStore,
  type DayJob,
  type DayJobStore,
  processJob,
  recordProcessResult,
  runWorkerPool,
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
    dayGenerationEndpointURL: "http://127.0.0.1/functions/v1/generate-week",
    mock: false,
  });

  assertEquals(result, {
    status: "failed",
    errorCode: "day_generation_endpoint_stubbed",
  });
});

Deno.test("runWorkerPool drains queued and retrying jobs with a bounded cap", async () => {
  const jobs = [
    makeJob("job-a", "queued", 0, "2026-09-21"),
    makeJob("job-b", "retrying", 1, "2026-09-22"),
    makeJob("job-c", "queued", 0, "2026-09-23"),
    makeJob("job-d", "queued", 0, "2026-09-24"),
    makeJob("job-e", "queued", 0, "2026-09-25"),
  ];
  const store = new MemoryDayJobStore(jobs, { markDelayMs: 25 });

  const result = await runWorkerPool(store, stubProcessContext(), {
    concurrency: 2,
    dryRun: false,
  });

  assertEquals(result, { claimed: 5, generated: 0, failed: 5 });
  assertEquals(store.maxGeneratingJobs, 2);
  assertEquals(
    jobs.map((job) => store.job(job.id)?.status),
    ["failed", "failed", "failed", "failed", "failed"],
  );
  assertEquals(store.job("job-a")?.attempt_count, 1);
  assertEquals(store.job("job-b")?.attempt_count, 2);
});

Deno.test("runWorkerPool honors a run id filter", async () => {
  const store = new MemoryDayJobStore([
    makeJob("job-a", "queued", 0, "2026-09-21", "generation-1"),
    makeJob("job-b", "queued", 0, "2026-09-22", "generation-2"),
    makeJob("job-c", "retrying", 1, "2026-09-23", "generation-2"),
  ]);

  const result = await runWorkerPool(store, stubProcessContext(), {
    concurrency: 4,
    dryRun: false,
    filter: { runID: "generation-2" },
  });

  assertEquals(result, { claimed: 2, generated: 0, failed: 2 });
  assertEquals(store.job("job-a")?.status, "queued");
  assertEquals(store.job("job-b")?.status, "failed");
  assertEquals(store.job("job-c")?.status, "failed");
});

Deno.test("runWorkerPool recovers when four lanes race the same stale candidate", async () => {
  const jobs = Array.from({ length: 7 }, (_, index) =>
    makeJob(
      `job-${index + 1}`,
      "queued",
      0,
      `2026-09-${String(21 + index).padStart(2, "0")}`,
    ));
  const store = new MemoryDayJobStore(jobs, {
    markDelayMs: 25,
    stalePeek: { jobID: "job-1", copies: 4 },
  });
  const lostRaceJobIDs: string[] = [];

  const result = await runWorkerPool(store, stubProcessContext(), {
    concurrency: 4,
    dryRun: false,
    onClaimLostRace: (job) => lostRaceJobIDs.push(job.id),
  });

  assertEquals(result, { claimed: 7, generated: 0, failed: 7 });
  assertEquals(store.maxGeneratingJobs, 4);
  assertEquals(
    jobs.map((job) => store.job(job.id)?.status),
    ["failed", "failed", "failed", "failed", "failed", "failed", "failed"],
  );
  assertEquals(lostRaceJobIDs, ["job-1", "job-1", "job-1"]);
});

Deno.test("runWorkerPool dry run peeks once without claiming", async () => {
  const store = new MemoryDayJobStore([
    makeJob("job-a", "queued", 0, "2026-09-21"),
    makeJob("job-b", "queued", 0, "2026-09-22"),
  ]);

  const result = await runWorkerPool(store, stubProcessContext(), {
    concurrency: 4,
    dryRun: true,
  });

  assertEquals(result, { claimed: 0, generated: 0, failed: 0 });
  assertEquals(store.peekCount, 1);
  assertEquals(store.job("job-a")?.status, "queued");
  assertEquals(store.job("job-b")?.status, "queued");
});

class MemoryDayJobStore implements DayJobStore {
  private jobs: DayJob[] = [];
  private lostRaceJobIDs = new Set<string>();
  private markDelayMs = 0;
  private stalePeek?: { jobID: string; copiesRemaining: number };
  maxGeneratingJobs = 0;
  peekCount = 0;

  init(
    jobs: DayJob[],
    options: {
      loseClaimRaceForJobIDs?: string[];
      markDelayMs?: number;
      stalePeek?: { jobID: string; copies: number };
    } = {},
  ) {
    this.jobs = jobs.map(copyJob);
    this.lostRaceJobIDs = new Set(options.loseClaimRaceForJobIDs ?? []);
    this.markDelayMs = options.markDelayMs ?? 0;
    this.stalePeek = options.stalePeek
      ? {
        jobID: options.stalePeek.jobID,
        copiesRemaining: options.stalePeek.copies,
      }
      : undefined;
    this.maxGeneratingJobs = 0;
    this.peekCount = 0;
  }

  constructor(
    jobs: DayJob[],
    options: {
      loseClaimRaceForJobIDs?: string[];
      markDelayMs?: number;
      stalePeek?: { jobID: string; copies: number };
    } = {},
  ) {
    this.init(jobs, options);
  }

  job(id: string): DayJob | undefined {
    return this.jobs.find((job) => job.id === id);
  }

  async peekJob(filter: { runID?: string } = {}): Promise<DayJob | null> {
    this.peekCount += 1;
    if (this.stalePeek && this.stalePeek.copiesRemaining > 0) {
      const staleJob = this.job(this.stalePeek.jobID);
      if (
        staleJob &&
        (!filter.runID || staleJob.generation_run_id === filter.runID)
      ) {
        this.stalePeek.copiesRemaining -= 1;
        return copyJob({
          ...staleJob,
          status: "queued",
        });
      }
    }

    const job = this.jobs
      .filter((candidate) =>
        candidate.status === "queued" || candidate.status === "retrying"
      )
      .filter((candidate) =>
        filter.runID ? candidate.generation_run_id === filter.runID : true
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
    this.maxGeneratingJobs = Math.max(
      this.maxGeneratingJobs,
      this.jobs.filter((candidate) => candidate.status === "generating").length,
    );
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
    await delay(this.markDelayMs);
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
    await delay(this.markDelayMs);
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
  generationRunID = "generation-1",
): DayJob {
  return {
    id,
    generation_run_id: generationRunID,
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

function stubProcessContext() {
  return {
    stub: true,
    serviceRoleKey: "test-service-role",
    dayGenerationEndpointURL: "http://127.0.0.1/functions/v1/generate-week",
    mock: false,
  };
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
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
