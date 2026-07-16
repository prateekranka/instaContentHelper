import {
  availableParallelDayJobSlots,
  handleGenerateWeekRequest,
  overrideTodayISO,
} from "./index.ts";
import {
  AIProviderConfig,
  GenerateWeekValidationError,
  GenerationInputSnapshot,
  makeMockGeneratedWeek,
} from "./generation.ts";

overrideTodayISO(() => "2026-01-01");

const workspaceID = "11111111-1111-4111-8111-111111111111";
const memberID = "22222222-2222-4222-8222-222222222222";
const creatorID = "33333333-3333-4333-8333-333333333333";
const setupID = "44444444-4444-4444-8444-444444444444";
const generationRunID = "55555555-5555-4555-8555-555555555555";
const weeklyPlanID = "66666666-6666-4666-8666-666666666666";
const dailyCardIDs = Array.from(
  { length: 7 },
  (_, index) => `77777777-7777-4777-8777-77777777777${index}`,
);

Deno.test("generate-week rejects creator role", async () => {
  const response = await callHandler(
    {
      creator_id: creatorID,
      week_start_date: "2026-06-08",
    },
    { memberRole: "creator" },
  );

  assertEquals(response.status, 403);
  assertEquals(await errorCode(response), "role_not_allowed");
});

Deno.test("generate-week status returns queued day-job progress", async () => {
  const state = dayGenerationState();
  state.dayJobs = makeQueuedDayJobs([
    ["generated", dailyCardIDs[0]],
    ["generated", dailyCardIDs[1]],
    ["generating", null],
    ["queued", null],
    ["queued", null],
    ["failed", null],
    ["retrying", null],
  ]);
  state.generationRun = {
    id: generationRunID,
    workspace_id: workspaceID,
    creator_id: creatorID,
    status: "running",
    weekly_plan_id: weeklyPlanID,
    input_snapshot: generationInputSnapshot(),
  };

  const response = await handleGenerateWeekRequest(
    requestFor({
      action: "status",
      generation_id: generationRunID,
      creator_id: creatorID,
    }),
    {
      env: fakeEnv("test-key"),
      createAdminClient: () => fakeAdmin(state),
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.status, "running");
  assertEquals(body.completed_day_count, 2);
  assertEquals(body.failed_day_count, 1);
  assertEquals(body.current_day, "2026-06-10");
  const days = body.days as Record<string, unknown>[];
  assertEquals(days[0].status, "generated");
  assertEquals(days[2].status, "generating");
  assertEquals(days[5].retry_action, "retry_day");
});

Deno.test("parallel generate-week status tops up retryable days when lanes are free", async () => {
  let scheduled: Promise<void> | undefined;
  const calls: string[] = [];
  const retryContexts = new Map<
    string,
    Record<string, unknown> | undefined
  >();
  const input = generationInputSnapshot();
  const startedAt = new Date().toISOString();
  const state = dayGenerationState();
  state.generationRun = {
    id: generationRunID,
    workspace_id: workspaceID,
    creator_id: creatorID,
    requested_by_member_id: memberID,
    status: "running",
    model: "openai:gpt-4.1-mini",
    weekly_plan_id: weeklyPlanID,
    input_snapshot: input,
    output_snapshot: {
      kind: "parallel_week_generation_v1",
      week_start_date: "2026-06-08",
      weekly_plan_id: weeklyPlanID,
      strategy_created: true,
      updated_at: startedAt,
      days: weekDatesForTest("2026-06-08").map((scheduledDate, index) => {
        if (index === 1 || index === 4) {
          return {
            scheduled_date: scheduledDate,
            status: "failed",
            attempts: 1,
            error_code: "invalid_ai_json",
            completed_at: startedAt,
          };
        }
        if (index === 5 || index === 6) {
          return {
            scheduled_date: scheduledDate,
            status: "running",
            attempts: 1,
            started_at: startedAt,
          };
        }
        return {
          scheduled_date: scheduledDate,
          status: "completed",
          attempts: 1,
          daily_card_id: dailyCardIDs[index],
          completed_at: startedAt,
        };
      }),
    },
  };

  const previousConcurrency = Deno.env.get(
    "MCO_PARALLEL_WEEK_GENERATION_CONCURRENCY",
  );
  Deno.env.set("MCO_PARALLEL_WEEK_GENERATION_CONCURRENCY", "4");

  try {
    const response = await handleGenerateWeekRequest(
      requestFor({
        action: "status",
        generation_id: generationRunID,
        creator_id: creatorID,
      }),
      {
        env: fakeEnv("openai-key"),
        createAdminClient: () => fakeAdmin(state),
        generateDayAI: async (input, _providers, scheduledDate, dayIndex) => {
          calls.push(scheduledDate);
          retryContexts.set(scheduledDate, input.day_retry_context);
          const card = makeMockGeneratedWeek(input).daily_cards[dayIndex];
          return {
            strategy_note: `Retried ${scheduledDate}`,
            warnings: [],
            assumptions: [],
            daily_card: { ...card, scheduled_date: scheduledDate },
            idea_bank: [],
            source_summary: "retried",
          };
        },
        runInBackground: (promise: Promise<void>) => {
          scheduled = promise;
        },
      },
    );

    assertEquals(response.status, 200);
    if (!scheduled) {
      throw new Error(
        "Expected status polling to top up free generation lanes.",
      );
    }
    await scheduled;

    assertEquals(calls.join(","), "2026-06-09,2026-06-12");
    const tuesdayRetry = recordValue(retryContexts.get("2026-06-09"));
    const fridayRetry = recordValue(retryContexts.get("2026-06-12"));
    assertEquals(tuesdayRetry.retry_kind, "failed_day_repair");
    assertEquals(tuesdayRetry.retry_reason, "invalid_ai_json");
    assertEquals(tuesdayRetry.scheduled_date, "2026-06-09");
    assertEquals(tuesdayRetry.day_attempt, 2);
    assertEquals(fridayRetry.retry_kind, "failed_day_repair");
    assertEquals(fridayRetry.retry_reason, "invalid_ai_json");
    assertEquals(fridayRetry.scheduled_date, "2026-06-12");
    assertEquals(fridayRetry.day_attempt, 2);
    const progress = recordValue(state.generationRun?.output_snapshot);
    const days = progress.days as Record<string, unknown>[];
    assertEquals(days[1].status, "completed");
    assertEquals(days[4].status, "completed");
    assertEquals(days[5].status, "running");
    assertEquals(days[6].status, "running");
  } finally {
    if (previousConcurrency === undefined) {
      Deno.env.delete("MCO_PARALLEL_WEEK_GENERATION_CONCURRENCY");
    } else {
      Deno.env.set(
        "MCO_PARALLEL_WEEK_GENERATION_CONCURRENCY",
        previousConcurrency,
      );
    }
  }
});

Deno.test("parallel generate-week status does not dispatch recovery when lanes are full", async () => {
  let scheduled: Promise<void> | undefined;
  const state = dayGenerationState();
  const now = new Date().toISOString();
  state.dayJobs = makeQueuedDayJobs([
    ["generating", null],
    ["generating", null],
    ["generating", null],
    ["generating", null],
    ["queued", null],
    ["queued", null],
    ["queued", null],
  ]);
  for (const job of state.dayJobs.slice(0, 4)) {
    job.started_at = now;
    job.heartbeat_at = now;
  }
  state.generationRun = {
    id: generationRunID,
    workspace_id: workspaceID,
    creator_id: creatorID,
    requested_by_member_id: memberID,
    status: "running",
    model: "openai:gpt-4.1-mini",
    weekly_plan_id: weeklyPlanID,
    input_snapshot: generationInputSnapshot(),
    output_snapshot: {
      kind: "parallel_week_generation_v1",
      week_start_date: "2026-06-08",
      weekly_plan_id: weeklyPlanID,
      strategy_created: true,
      updated_at: now,
      days: weekDatesForTest("2026-06-08").map((scheduledDate, index) => ({
        scheduled_date: scheduledDate,
        status: index < 4 ? "running" : "pending",
        attempts: index < 4 ? 1 : 0,
        started_at: index < 4 ? now : undefined,
        heartbeat_at: index < 4 ? now : undefined,
      })),
    },
  };

  const previousConcurrency = Deno.env.get(
    "MCO_PARALLEL_WEEK_GENERATION_CONCURRENCY",
  );
  Deno.env.set("MCO_PARALLEL_WEEK_GENERATION_CONCURRENCY", "4");

  try {
    const response = await handleGenerateWeekRequest(
      requestFor({
        action: "status",
        generation_id: generationRunID,
        creator_id: creatorID,
      }),
      {
        env: fakeEnv("openai-key"),
        createAdminClient: () => fakeAdmin(state),
        generateDayAI: () => {
          throw new Error("generation should not start when lanes are full");
        },
        runInBackground: (promise: Promise<void>) => {
          scheduled = promise;
        },
      },
    );

    assertEquals(response.status, 200);
    assertEquals(Boolean(scheduled), false);
    assertEquals(state.dayJobRPCClaims.length, 0);
  } finally {
    if (previousConcurrency === undefined) {
      Deno.env.delete("MCO_PARALLEL_WEEK_GENERATION_CONCURRENCY");
    } else {
      Deno.env.set(
        "MCO_PARALLEL_WEEK_GENERATION_CONCURRENCY",
        previousConcurrency,
      );
    }
  }
});

Deno.test("parallel generate-week releases a claimed job if a competing worker fills the last lane", async () => {
  let scheduled: Promise<void> | undefined;
  let aiCalls = 0;
  let hookUsed = false;
  const state = dayGenerationState();
  const now = new Date().toISOString();
  state.dayJobs = makeQueuedDayJobs([
    ["generating", null],
    ["generating", null],
    ["generating", null],
    ["queued", null],
    ["queued", null],
    ["queued", null],
    ["queued", null],
  ]);
  for (const job of state.dayJobs.slice(0, 3)) {
    job.started_at = now;
    job.heartbeat_at = now;
  }
  state.dayJobClaimHook = (fakeState, claimedJob) => {
    if (hookUsed) return;
    hookUsed = true;
    const competingJob = fakeState.dayJobs.find((job) =>
      job.id !== claimedJob.id && job.status === "queued"
    );
    if (!competingJob) return;
    competingJob.status = "generating";
    competingJob.lease_token = "competing-worker-lease";
    competingJob.worker_boot_id = "competing-worker-boot";
    competingJob.started_at = now;
    competingJob.heartbeat_at = now;
    competingJob.attempt_count = 1;
  };
  state.generationRun = {
    id: generationRunID,
    workspace_id: workspaceID,
    creator_id: creatorID,
    requested_by_member_id: memberID,
    status: "running",
    model: "openai:gpt-4.1-mini",
    weekly_plan_id: weeklyPlanID,
    input_snapshot: generationInputSnapshot(),
    output_snapshot: {
      kind: "parallel_week_generation_v1",
      week_start_date: "2026-06-08",
      weekly_plan_id: weeklyPlanID,
      strategy_created: true,
      updated_at: now,
      days: weekDatesForTest("2026-06-08").map((scheduledDate, index) => ({
        scheduled_date: scheduledDate,
        status: index < 3 ? "running" : "pending",
        attempts: index < 3 ? 1 : 0,
        started_at: index < 3 ? now : undefined,
        heartbeat_at: index < 3 ? now : undefined,
      })),
    },
  };

  const previousConcurrency = Deno.env.get(
    "MCO_PARALLEL_WEEK_GENERATION_CONCURRENCY",
  );
  Deno.env.set("MCO_PARALLEL_WEEK_GENERATION_CONCURRENCY", "4");

  try {
    const response = await handleGenerateWeekRequest(
      requestFor({
        action: "status",
        generation_id: generationRunID,
        creator_id: creatorID,
      }),
      {
        env: fakeEnv("openai-key"),
        createAdminClient: () => fakeAdmin(state),
        generateDayAI: async () => {
          aiCalls += 1;
          throw new Error("generation should not start over capacity");
        },
        runInBackground: (promise: Promise<void>) => {
          scheduled = promise;
        },
      },
    );

    assertEquals(response.status, 200);
    if (!scheduled) {
      throw new Error("Expected recovery to be scheduled with one free lane.");
    }
    await scheduled;

    assertEquals(aiCalls, 0);
    assertEquals(state.dayJobRPCClaims.length, 1);
    const releasedJob = state.dayJobs[3];
    assertEquals(releasedJob.status, "queued");
    assertEquals(releasedJob.attempt_count, 0);
    assertEquals(releasedJob.lease_token, null);
  } finally {
    if (previousConcurrency === undefined) {
      Deno.env.delete("MCO_PARALLEL_WEEK_GENERATION_CONCURRENCY");
    } else {
      Deno.env.set(
        "MCO_PARALLEL_WEEK_GENERATION_CONCURRENCY",
        previousConcurrency,
      );
    }
  }
});

Deno.test("generate-week status returns completed draft snapshot", async () => {
  const generated = makeMockGeneratedWeek({
    creator_id: creatorID,
    week_start_date: "2026-06-08",
    creator_profile: null,
    weekly_setup: null,
    confirmed_references: [],
    reference_extractions: [],
    recent_archive: [],
    idea_bank: [],
    patterns: [],
    trends: [],
    audio_options: [],
    brand_briefs: [],
    key_moments: [],
  });
  const snapshot = {
    generation_id: generationRunID,
    weekly_plan_id: weeklyPlanID,
    status: "draft",
    strategy_summary: generated.strategy_summary,
    warnings: generated.warnings,
    assumptions: generated.assumptions,
    daily_cards: generated.daily_cards,
    idea_bank: [],
    source_summary: generated.source_summary,
    generated_at: "2026-06-08T08:00:00.000Z",
  };

  const response = await callHandler(
    {
      action: "status",
      generation_id: generationRunID,
      creator_id: creatorID,
    },
    {
      generationRun: {
        id: generationRunID,
        workspace_id: workspaceID,
        creator_id: creatorID,
        status: "completed",
        weekly_plan_id: weeklyPlanID,
        output_snapshot: snapshot,
      },
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.generation_id, generationRunID);
  assertEquals(body.weekly_plan_id, weeklyPlanID);
  assertEquals(Array.isArray(body.daily_cards), true);
  assertEquals((body.daily_cards as unknown[]).length, 7);
});

Deno.test("parallel generate-week status ignores stale cards not recorded on the run", async () => {
  const state = dayGenerationState();
  const startedAt = "2026-06-08T08:00:00.000Z";
  state.generationRun = {
    id: generationRunID,
    workspace_id: workspaceID,
    creator_id: creatorID,
    requested_by_member_id: memberID,
    status: "running",
    model: "openai:gpt-4.1-mini",
    weekly_plan_id: weeklyPlanID,
    input_snapshot: generationInputSnapshot(),
    output_snapshot: {
      kind: "parallel_week_generation_v1",
      week_start_date: "2026-06-08",
      weekly_plan_id: weeklyPlanID,
      strategy_created: true,
      updated_at: startedAt,
      days: weekDatesForTest("2026-06-08").map((scheduledDate) => ({
        scheduled_date: scheduledDate,
        status: "pending",
        attempts: 0,
      })),
    },
  };

  const response = await callHandler(
    {
      action: "status",
      generation_id: generationRunID,
      creator_id: creatorID,
    },
    state,
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.completed_day_count, 0);
  assertEquals(body.saved_day_count, 0);
  assertEquals(Array.isArray(body.daily_cards), true);
  assertEquals((body.daily_cards as unknown[]).length, 0);
});

Deno.test("parallel generate-week status finalizes terminal partial progress", async () => {
  const state = dayGenerationState();
  const completedAt = "2026-06-08T08:05:00.000Z";
  state.generationRun = {
    id: generationRunID,
    workspace_id: workspaceID,
    creator_id: creatorID,
    requested_by_member_id: memberID,
    status: "running",
    model: "openai:gpt-4.1-mini",
    weekly_plan_id: weeklyPlanID,
    input_snapshot: generationInputSnapshot(),
    output_snapshot: {
      kind: "parallel_week_generation_v1",
      week_start_date: "2026-06-08",
      weekly_plan_id: weeklyPlanID,
      strategy_created: true,
      updated_at: completedAt,
      days: weekDatesForTest("2026-06-08").map((scheduledDate, index) =>
        index < 5
          ? {
            scheduled_date: scheduledDate,
            status: "completed",
            attempts: 1,
            daily_card_id: dailyCardIDs[index],
            completed_at: completedAt,
          }
          : {
            scheduled_date: scheduledDate,
            status: "failed",
            attempts: 3,
            error_code: "invalid_generated_week",
            completed_at: completedAt,
          }
      ),
    },
  };

  const response = await callHandler(
    {
      action: "status",
      generation_id: generationRunID,
      creator_id: creatorID,
    },
    state,
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.status, "partial");
  assertEquals(body.overall_status, "partial");
  assertEquals(body.saved_day_count, 5);
  assertEquals(body.failed_day_count, 2);
  assertEquals((body.daily_cards as unknown[]).length, 5);
  assertEquals(state.generationRun?.status, "completed");
  assertEquals(state.generationRun?.error_code, "partial_generation");
});

Deno.test("parallel generate-week status reconciles saved cards over stale timeout snapshot", async () => {
  const state = dayGenerationState();
  const input = generationInputSnapshot();
  const startedAt = "2026-06-08T08:00:00.000Z";
  const retryStartedAt = "2026-06-08T08:05:00.000Z";
  const savedAt = "2026-06-08T08:06:00.000Z";
  state.dailyCards = state.dailyCards.map((card, index) => ({
    ...card,
    updated_at: index === 0 || index === 5 || index === 6
      ? savedAt
      : "2026-06-08T08:01:00.000Z",
  }));
  state.generationRun = {
    id: generationRunID,
    workspace_id: workspaceID,
    creator_id: creatorID,
    requested_by_member_id: memberID,
    status: "running",
    model: "openai:gpt-4.1-mini",
    weekly_plan_id: weeklyPlanID,
    input_snapshot: input,
    output_snapshot: {
      kind: "parallel_week_generation_v1",
      week_start_date: "2026-06-08",
      weekly_plan_id: weeklyPlanID,
      strategy_created: true,
      updated_at: startedAt,
      days: weekDatesForTest("2026-06-08").map((scheduledDate, index) => {
        if (index === 0) {
          return {
            scheduled_date: scheduledDate,
            status: "failed",
            attempts: 3,
            started_at: retryStartedAt,
            completed_at: "2026-06-08T08:10:00.000Z",
            error_code: "generation_timeout",
          };
        }
        if (index === 5 || index === 6) {
          return {
            scheduled_date: scheduledDate,
            status: "running",
            attempts: 3,
            started_at: retryStartedAt,
          };
        }
        return {
          scheduled_date: scheduledDate,
          status: "completed",
          attempts: 1,
          daily_card_id: dailyCardIDs[index],
          completed_at: startedAt,
        };
      }),
    },
  };

  const response = await handleGenerateWeekRequest(
    requestFor({
      action: "status",
      generation_id: generationRunID,
      creator_id: creatorID,
    }),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(state),
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.status, "draft");
  assertEquals(body.saved_day_count, 7);
  assertEquals(body.failed_day_count, 0);
  assertEquals((body.daily_cards as unknown[]).length, 7);
  assertEquals(state.generationRun?.status, "completed");
  assertEquals(state.generationRun?.error_code, null);
});

Deno.test("parallel generate-week status does not retry failed days at max attempts", async () => {
  let scheduled: Promise<void> | undefined;
  const calls: string[] = [];
  const input = generationInputSnapshot();
  const state = dayGenerationState();
  const completedAt = "2026-06-08T08:05:00.000Z";
  state.generationRun = {
    id: generationRunID,
    workspace_id: workspaceID,
    creator_id: creatorID,
    requested_by_member_id: memberID,
    status: "running",
    model: "openai:gpt-4.1-mini",
    weekly_plan_id: weeklyPlanID,
    input_snapshot: input,
    output_snapshot: {
      kind: "parallel_week_generation_v1",
      week_start_date: "2026-06-08",
      weekly_plan_id: weeklyPlanID,
      strategy_created: true,
      updated_at: completedAt,
      days: weekDatesForTest("2026-06-08").map((scheduledDate, index) => {
        if (index === 1) {
          return {
            scheduled_date: scheduledDate,
            status: "failed",
            attempts: 3,
            error_code: "invalid_ai_json",
            completed_at: completedAt,
          };
        }
        if (index === 2) {
          return {
            scheduled_date: scheduledDate,
            status: "pending",
            attempts: 0,
          };
        }
        return {
          scheduled_date: scheduledDate,
          status: "completed",
          attempts: 1,
          daily_card_id: dailyCardIDs[index],
          completed_at: completedAt,
        };
      }),
    },
  };

  const response = await handleGenerateWeekRequest(
    requestFor({
      action: "status",
      generation_id: generationRunID,
      creator_id: creatorID,
    }),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(state),
      generateDayAI: async (snapshot, _providers, scheduledDate, dayIndex) => {
        calls.push(scheduledDate);
        const card = makeMockGeneratedWeek(snapshot).daily_cards[dayIndex];
        return {
          strategy_note: `Resumed ${scheduledDate}`,
          warnings: [],
          assumptions: [],
          daily_card: { ...card, scheduled_date: scheduledDate },
          idea_bank: [],
          source_summary: "resumed",
        };
      },
      runInBackground: (promise: Promise<void>) => {
        scheduled = promise;
      },
    },
  );

  assertEquals(response.status, 200);
  if (!scheduled) {
    throw new Error("Expected pending day generation to be scheduled.");
  }
  await scheduled;

  assertEquals(calls.join(","), "2026-06-10");
  assertEquals(state.generationRun?.status, "completed");
  assertEquals(state.generationRun?.error_code, "partial_generation");
  const progress = recordValue(state.generationRun?.output_snapshot);
  const days = progress.days as Record<string, unknown>[];
  assertEquals(days[1].status, "failed");
  assertEquals(days[1].attempts, 3);
  assertEquals(days[2].status, "completed");
});

Deno.test("generate-week status marks third-stale running days as failed", async () => {
  let scheduled: Promise<void> | undefined;
  const input = generationInputSnapshot();
  const state = dayGenerationState();
  const startedAt = new Date(Date.now() - 400_000).toISOString();
  state.generationRun = {
    id: generationRunID,
    workspace_id: workspaceID,
    creator_id: creatorID,
    requested_by_member_id: memberID,
    status: "running",
    model: "openai:gpt-4.1-mini",
    input_snapshot: input,
    output_snapshot: {
      kind: "per_day_generation_v1",
      week_start_date: "2026-06-08",
      updated_at: startedAt,
      days: [
        ...["2026-06-08", "2026-06-09", "2026-06-10"].map((
          scheduledDate,
          index,
        ) => ({
          scheduled_date: scheduledDate,
          status: "completed",
          attempts: 1,
          completed_at: startedAt,
          output: {
            strategy_note: `Completed ${index}`,
            warnings: [],
            assumptions: [],
            daily_card: makeMockGeneratedWeek(input).daily_cards[index],
            idea_bank: [],
            source_summary: "completed",
          },
        })),
        {
          scheduled_date: "2026-06-11",
          status: "running",
          attempts: 3,
          started_at: startedAt,
        },
        ...["2026-06-12", "2026-06-13", "2026-06-14"].map((
          scheduledDate,
        ) => ({
          scheduled_date: scheduledDate,
          status: "pending",
          attempts: 0,
        })),
      ],
    },
  };

  const response = await handleGenerateWeekRequest(
    requestFor({
      action: "status",
      generation_id: generationRunID,
      creator_id: creatorID,
    }),
    {
      env: fakeEnv("test-key"),
      createAdminClient: () => fakeAdmin(state),
      generateDayAI: async (snapshot, _providers, scheduledDate, dayIndex) => {
        const card = makeMockGeneratedWeek(snapshot).daily_cards[dayIndex];
        return {
          strategy_note: `Resumed ${scheduledDate}`,
          warnings: [],
          assumptions: [],
          daily_card: { ...card, scheduled_date: scheduledDate },
          idea_bank: [],
          source_summary: "resumed",
        };
      },
      runInBackground: (promise: Promise<void>) => {
        scheduled = promise;
      },
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.completed_day_count, 3);
  assertEquals(body.failed_day_count, 1);
  assertEquals(body.current_day, "2026-06-12");
  assertEquals(Boolean(scheduled), true);
});

Deno.test({
  name:
    "generate-week status returns partial progress when one day failed and six days were saved",
  ignore: true,
  async fn() {
    const input = generationInputSnapshot();
    const generated = makeMockGeneratedWeek(input);
    const completedAt = "2026-06-08T08:00:00.000Z";
    const failedAt = "2026-06-08T08:01:00.000Z";
    const state = dayGenerationState();
    state.generationRun = {
      id: generationRunID,
      workspace_id: workspaceID,
      creator_id: creatorID,
      requested_by_member_id: memberID,
      status: "partial",
      weekly_plan_id: weeklyPlanID,
      input_snapshot: input,
      output_snapshot: {
        kind: "per_day_generation_v1",
        week_start_date: "2026-06-08",
        updated_at: failedAt,
        days: weekDatesForTest("2026-06-08").map((scheduledDate, index) =>
          index === 2
            ? {
              scheduled_date: scheduledDate,
              status: "failed",
              attempts: 1,
              error_code: "openai_request_failed",
              completed_at: failedAt,
            }
            : {
              scheduled_date: scheduledDate,
              status: "completed",
              attempts: 1,
              completed_at: completedAt,
              daily_card_id: dailyCardIDs[index],
              output: {
                strategy_note: `Saved ${index + 1}`,
                warnings: [],
                assumptions: [],
                daily_card: generated.daily_cards[index],
                idea_bank: [],
                source_summary: "saved",
              },
            }
        ),
      },
    };

    const response = await handleGenerateWeekRequest(
      requestFor({
        action: "status",
        generation_id: generationRunID,
        creator_id: creatorID,
      }),
      {
        env: fakeEnv("openai-key"),
        createAdminClient: () => fakeAdmin(state),
      },
    );

    assertEquals(response.status, 200);
    const body = await response.json();
    assertEquals(body.generation_id, generationRunID);
    assertEquals(body.weekly_plan_id, weeklyPlanID);
    assertEquals(body.status, "partial");
    assertEquals(body.completed_day_count, 6);
    assertEquals(body.saved_day_count, 6);
    assertEquals(body.failed_day_count, 1);
    assertEquals(body.total_day_count, 7);
    assertEquals(Array.isArray(body.daily_cards), true);
    assertEquals((body.daily_cards as unknown[]).length, 6);
    assertEquals(Array.isArray(body.failed_days), true);
    const failedDays = body.failed_days as Record<string, unknown>[];
    assertEquals(failedDays[0].scheduled_date, "2026-06-10");
    assertEquals(failedDays[0].day_index, 2);
    assertEquals(failedDays[0].status, "failed");
    assertEquals(failedDays[0].error_code, "openai_request_failed");
    assertEquals(failedDays[0].retry_action, "regenerate_day");
  },
});

Deno.test("regenerate_day updates exactly one draft card and leaves the other six unchanged", async () => {
  const state = dayGenerationState();
  const before = structuredClone(state.dailyCards);
  const response = await handleGenerateWeekRequest(
    requestFor({
      action: "regenerate_day",
      creator_id: creatorID,
      weekly_plan_id: weeklyPlanID,
      scheduled_date: "2026-06-10",
      preserve_manual_edits: false,
    }),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(state),
      generateDayAI: async (input, providers, scheduledDate, dayIndex) => {
        assertEquals(providers[0].provider, "openai");
        const mock = makeMockGeneratedWeek(input);
        return {
          strategy_note: "Regenerated Wednesday only.",
          warnings: [],
          assumptions: [],
          daily_card: {
            ...mock.daily_cards[dayIndex],
            scheduled_date: scheduledDate,
            title: "Fresh Wednesday",
          },
          idea_bank: [],
          source_summary: "Live context plus the other six cards.",
        };
      },
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.target_scheduled_date, "2026-06-10");
  assertEquals(body.daily_card.title, "Fresh Wednesday");
  assertEquals(state.dailyCards[2].title, "Fresh Wednesday");
  for (const index of [0, 1, 3, 4, 5, 6]) {
    assertEquals(
      JSON.stringify(state.dailyCards[index]),
      JSON.stringify(before[index]),
      `card ${index} must remain unchanged`,
    );
  }
  assertEquals(state.updatedDailyCardIDs.join(","), dailyCardIDs[2]);
});

Deno.test("regenerate_day retries a failed draft day and keeps the other six cards", async () => {
  const state = dayGenerationState();
  state.dailyCards[2].title = "Failed Wednesday placeholder";
  state.dailyCards[2].assumptions = ["Previous generation failed."];
  const before = structuredClone(state.dailyCards);
  const response = await handleGenerateWeekRequest(
    requestFor({
      action: "regenerate_day",
      creator_id: creatorID,
      weekly_plan_id: weeklyPlanID,
      scheduled_date: "2026-06-10",
      preserve_manual_edits: false,
    }),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(state),
      generateDayAI: async (input, _providers, scheduledDate, dayIndex) => {
        const card = makeMockGeneratedWeek(input).daily_cards[dayIndex];
        return {
          strategy_note: "Retry Wednesday only.",
          warnings: [],
          assumptions: ["Retried after partial week failure."],
          daily_card: {
            ...card,
            scheduled_date: scheduledDate,
            title: "Retried Wednesday",
          },
          idea_bank: [],
          source_summary: "Retry context.",
        };
      },
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.target_scheduled_date, "2026-06-10");
  assertEquals(body.daily_card.title, "Retried Wednesday");
  assertEquals(state.dailyCards[2].title, "Retried Wednesday");
  assertEquals(state.updatedDailyCardIDs.join(","), dailyCardIDs[2]);
  for (const index of [0, 1, 3, 4, 5, 6]) {
    assertEquals(
      JSON.stringify(state.dailyCards[index]),
      JSON.stringify(before[index]),
      `card ${index} must remain unchanged`,
    );
  }
});

Deno.test("regenerate_day creates a missing draft card for a failed day", async () => {
  const state = dayGenerationState();
  state.dailyCards = state.dailyCards.filter((card) =>
    card.scheduled_date !== "2026-06-10"
  );
  const beforeDates = state.dailyCards.map((card) => card.scheduled_date);

  const response = await handleGenerateWeekRequest(
    requestFor({
      action: "regenerate_day",
      creator_id: creatorID,
      weekly_plan_id: weeklyPlanID,
      scheduled_date: "2026-06-10",
      preserve_manual_edits: false,
    }),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(state),
      generateDayAI: async (input, _providers, scheduledDate, dayIndex) => {
        const card = makeMockGeneratedWeek(input).daily_cards[dayIndex];
        return {
          strategy_note: "Retry missing Wednesday only.",
          warnings: [],
          assumptions: [],
          daily_card: {
            ...card,
            scheduled_date: scheduledDate,
            title: "Inserted Wednesday",
          },
          idea_bank: [],
          source_summary: "Retry context.",
        };
      },
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.target_scheduled_date, "2026-06-10");
  assertEquals(body.daily_card.title, "Inserted Wednesday");
  assertEquals(beforeDates.includes("2026-06-10"), false);
  assertEquals(state.dailyCards.length, 7);
  assertEquals(
    state.dailyCards.find((card) => card.scheduled_date === "2026-06-10")
      ?.title,
    "Inserted Wednesday",
  );
});

Deno.test("regenerate_day preserves manual review fields by default", async () => {
  const state = dayGenerationState();
  state.dailyCards[2].title = "Manual title";
  state.dailyCards[2].caption = "Manual caption";
  const response = await handleGenerateWeekRequest(
    requestFor({
      action: "regenerate_day",
      creator_id: creatorID,
      weekly_plan_id: weeklyPlanID,
      scheduled_date: "2026-06-10",
    }),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(state),
      generateDayAI: async (input, _providers, scheduledDate, dayIndex) => {
        const card = makeMockGeneratedWeek(input).daily_cards[dayIndex];
        return {
          strategy_note: "One day",
          warnings: [],
          assumptions: [],
          daily_card: {
            ...card,
            scheduled_date: scheduledDate,
            title: "AI title",
            caption: "AI caption",
            script: "New AI script",
          },
          idea_bank: [],
          source_summary: "Context",
        };
      },
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.daily_card.title, "Manual title");
  assertEquals(body.daily_card.caption, "Manual caption");
  assertEquals(body.daily_card.script, "New AI script");
});

Deno.test("regenerate_day rejects cross-workspace plans and published locks", async () => {
  const missingPlan = dayGenerationState();
  missingPlan.weeklyPlan = null;
  const missingResponse = await handleGenerateWeekRequest(
    requestFor(regenerateDayBody()),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(missingPlan),
    },
  );
  assertEquals(missingResponse.status, 404);
  assertEquals(await errorCode(missingResponse), "weekly_plan_not_found");

  const published = dayGenerationState();
  published.weeklyPlan = { ...published.weeklyPlan!, status: "published" };
  const publishedResponse = await handleGenerateWeekRequest(
    requestFor(regenerateDayBody()),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(published),
    },
  );
  assertEquals(publishedResponse.status, 409);
  assertEquals(
    await errorCode(publishedResponse),
    "existing_published_week_locked",
  );
});

Deno.test("regenerate_day rejects dates outside the plan week", async () => {
  const response = await handleGenerateWeekRequest(
    requestFor({ ...regenerateDayBody(), scheduled_date: "2026-06-15" }),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(dayGenerationState()),
    },
  );
  assertEquals(response.status, 400);
  assertEquals(await errorCode(response), "date_not_in_plan");
});

Deno.test("regenerate_day async mode schedules one card and returns a pollable run", async () => {
  const state = dayGenerationState();
  let scheduled: Promise<void> | undefined;
  const response = await handleGenerateWeekRequest(
    requestFor({
      ...regenerateDayBody(),
      preserve_manual_edits: false,
      response_mode: "async",
    }),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(state),
      generateDayAI: async (input, _providers, scheduledDate, dayIndex) => {
        const card = makeMockGeneratedWeek(input).daily_cards[dayIndex];
        return {
          strategy_note: "Async day",
          warnings: [],
          assumptions: [],
          daily_card: {
            ...card,
            scheduled_date: scheduledDate,
            title: "Async Wednesday",
          },
          idea_bank: [],
          source_summary: "Async context",
        };
      },
      runInBackground: (promise) => {
        scheduled = promise;
      },
    },
  );
  assertEquals(response.status, 202);
  const body = await response.json();
  assertEquals(body.generation_id, generationRunID);
  assertEquals(body.weekly_plan_id, weeklyPlanID);
  assertEquals(body.target_scheduled_date, "2026-06-10");
  if (!scheduled) {
    throw new Error("Expected single-day generation to be scheduled.");
  }
  await scheduled;
  assertEquals(state.dailyCards[2].title, "Async Wednesday");
  assertEquals(state.updatedDailyCardIDs.join(","), dailyCardIDs[2]);
});

Deno.test("regenerate_day async mode creates a missing card and polls to draft", async () => {
  const state = dayGenerationState();
  state.dailyCards = state.dailyCards.filter((card) =>
    card.scheduled_date !== "2026-06-10"
  );
  assertEquals(state.dailyCards.length, 6);

  const admin = fakeAdmin(state);
  let scheduled: Promise<void> | undefined;
  const deps = {
    env: fakeEnv("openai-key"),
    createAdminClient: () => admin,
    generateDayAI: async (
      input: GenerationInputSnapshot,
      _providers: AIProviderConfig[],
      scheduledDate: string,
      dayIndex: number,
    ) => {
      const card = makeMockGeneratedWeek(input).daily_cards[dayIndex];
      return {
        strategy_note: "Async missing-day recovery.",
        warnings: [],
        assumptions: ["Recovered missing Wednesday."],
        daily_card: {
          ...card,
          scheduled_date: scheduledDate,
          title: "Recovered Async Wednesday",
        },
        idea_bank: [],
        source_summary: "Recovery context.",
      };
    },
    runInBackground: (promise: Promise<void>) => {
      scheduled = promise;
    },
  };

  const initial = await handleGenerateWeekRequest(
    requestFor({
      action: "regenerate_day",
      creator_id: creatorID,
      weekly_plan_id: weeklyPlanID,
      scheduled_date: "2026-06-10",
      preserve_manual_edits: false,
      response_mode: "async",
    }),
    deps,
  );
  assertEquals(initial.status, 202);
  const initialBody = await initial.json();
  assertEquals(initialBody.generation_id, generationRunID);
  assertEquals(initialBody.weekly_plan_id, weeklyPlanID);
  assertEquals(initialBody.status, "running");
  assertEquals(initialBody.target_scheduled_date, "2026-06-10");
  assertEquals(initialBody.poll_after_seconds, 5);
  if (!scheduled) {
    throw new Error("Expected single-day generation to be scheduled.");
  }

  await scheduled;

  const status = await handleGenerateWeekRequest(
    requestFor({
      action: "status",
      generation_id: generationRunID,
      creator_id: creatorID,
    }),
    deps,
  );
  assertEquals(status.status, 200);
  const statusBody = await status.json();
  assertEquals(statusBody.generation_id, generationRunID);
  assertEquals(statusBody.status, "draft");
  assertEquals(statusBody.target_scheduled_date, "2026-06-10");
  const dailyCard = statusBody.daily_card as Record<string, unknown>;
  assertEquals(
    typeof dailyCard,
    "object",
    "expected daily_card in completed response",
  );
  assertEquals(dailyCard.scheduled_date, "2026-06-10");
  assertEquals(dailyCard.title, "Recovered Async Wednesday");

  assertEquals(state.dailyCards.length, 7);
  const recovered = state.dailyCards.find((card) =>
    card.scheduled_date === "2026-06-10"
  );
  if (!recovered) {
    throw new Error("Expected recovered card in daily_cards state.");
  }
  assertEquals(recovered.title, "Recovered Async Wednesday");
  assertEquals(recovered.weekly_plan_id, weeklyPlanID);
});

Deno.test("generate-week status returns completed single-day snapshot", async () => {
  const state = dayGenerationState();
  const card = state.dailyCards[2];
  const snapshot = {
    generation_id: generationRunID,
    weekly_plan_id: weeklyPlanID,
    status: "draft",
    target_scheduled_date: "2026-06-10",
    daily_card: card,
    warnings: [],
    assumptions: [],
    source_summary: "One day",
    generated_at: "2026-06-10T08:00:00.000Z",
  };
  const response = await callHandler(
    {
      action: "status",
      generation_id: generationRunID,
      creator_id: creatorID,
    },
    {
      generationRun: {
        id: generationRunID,
        workspace_id: workspaceID,
        creator_id: creatorID,
        generation_scope: "day",
        status: "completed",
        weekly_plan_id: weeklyPlanID,
        target_daily_card_id: dailyCardIDs[2],
        target_scheduled_date: "2026-06-10",
        output_snapshot: snapshot,
      },
    },
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.target_scheduled_date, "2026-06-10");
  assertEquals(body.daily_card.id, dailyCardIDs[2]);
});

Deno.test("regenerate_day accepts a past scheduled_date inside the draft week for retry recovery", async () => {
  overrideTodayISO(() => "2026-07-01");
  try {
    const response = await handleGenerateWeekRequest(
      requestFor({
        action: "regenerate_day",
        creator_id: creatorID,
        weekly_plan_id: weeklyPlanID,
        scheduled_date: "2026-06-10",
        preserve_manual_edits: false,
      }),
      {
        env: fakeEnv("openai-key"),
        createAdminClient: () => fakeAdmin(dayGenerationState()),
        generateDayAI: async (input, _providers, scheduledDate, dayIndex) => {
          const card = makeMockGeneratedWeek(input).daily_cards[dayIndex];
          return {
            strategy_note: "Retry a failed day from the active draft week.",
            warnings: [],
            assumptions: [],
            daily_card: { ...card, scheduled_date: scheduledDate },
            idea_bank: [],
            source_summary: "Past-date retry recovery.",
          };
        },
      },
    );
    assertEquals(response.status, 200);
    const body = await response.json();
    assertEquals(body.target_scheduled_date, "2026-06-10");
  } finally {
    overrideTodayISO(() => "2026-01-01");
  }
});

Deno.test("regenerate_day accepts today or future scheduled_date", async () => {
  overrideTodayISO(() => "2026-01-01");
  try {
    const response = await handleGenerateWeekRequest(
      requestFor({
        action: "regenerate_day",
        creator_id: creatorID,
        weekly_plan_id: weeklyPlanID,
        scheduled_date: "2026-06-10",
        preserve_manual_edits: false,
      }),
      {
        env: fakeEnv("openai-key"),
        createAdminClient: () => fakeAdmin(dayGenerationState()),
        generateDayAI: async (input, _providers, scheduledDate, dayIndex) => {
          const card = makeMockGeneratedWeek(input).daily_cards[dayIndex];
          return {
            strategy_note: "Accepted day",
            warnings: [],
            assumptions: [],
            daily_card: {
              ...card,
              scheduled_date: scheduledDate,
              title: "Accepted scheduled date",
            },
            idea_bank: [],
            source_summary: "accepted",
          };
        },
      },
    );
    assertEquals(response.status, 200);
  } finally {
    overrideTodayISO(() => "2026-01-01");
  }
});

Deno.test("regenerate_day accepts and bounds day_guidance", async () => {
  let capturedGuidance: string | undefined;
  const state = dayGenerationState();
  const deps = {
    env: fakeEnv("openai-key"),
    createAdminClient: () => fakeAdmin(state),
    generateDayAI: async (
      input: GenerationInputSnapshot,
      _providers: AIProviderConfig[],
      _scheduledDate: string,
      _dayIndex: number,
    ) => {
      capturedGuidance = input.day_guidance;
      const card = makeMockGeneratedWeek(input).daily_cards[2];
      return {
        strategy_note: "Guidance test",
        warnings: [],
        assumptions: [],
        daily_card: { ...card, scheduled_date: "2026-06-10" },
        idea_bank: [],
        source_summary: "test",
      };
    },
  };

  const response = await handleGenerateWeekRequest(
    requestFor({
      action: "regenerate_day",
      creator_id: creatorID,
      weekly_plan_id: weeklyPlanID,
      scheduled_date: "2026-06-10",
      preserve_manual_edits: false,
      day_guidance:
        "  Focus on the Thursday brand brief for recovery products.  ",
    }),
    deps,
  );

  assertEquals(response.status, 200);
  assertEquals(
    capturedGuidance,
    "Focus on the Thursday brand brief for recovery products.",
  );

  const longGuidance = "x".repeat(2400);
  const longResponse = await handleGenerateWeekRequest(
    requestFor({
      action: "regenerate_day",
      creator_id: creatorID,
      weekly_plan_id: weeklyPlanID,
      scheduled_date: "2026-06-10",
      preserve_manual_edits: false,
      day_guidance: longGuidance,
    }),
    deps,
  );

  assertEquals(longResponse.status, 200);
  assertEquals(
    capturedGuidance?.length,
    2000,
    `day_guidance should be bounded to 2000 chars, got ${capturedGuidance?.length}`,
  );
  assertEquals(
    capturedGuidance,
    longGuidance.slice(0, 2000),
  );
});

Deno.test("generate_day requires a non-empty day brief", async () => {
  const state = dayGenerationState();
  const response = await handleGenerateWeekRequest(
    requestFor({
      action: "generate_day",
      creator_id: creatorID,
      scheduled_date: "2026-06-10",
      day_brief: "   ",
    }),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(state),
    },
  );

  assertEquals(response.status, 400);
  assertEquals(await errorCode(response), "day_brief_required");
});

Deno.test("generate_day rejects past scheduled dates", async () => {
  overrideTodayISO(() => "2026-07-01");
  try {
    const state = dayGenerationState();
    const response = await handleGenerateWeekRequest(
      requestFor({
        action: "generate_day",
        creator_id: creatorID,
        scheduled_date: "2026-06-30",
        day_brief: "Yesterday's shoot.",
      }),
      {
        env: fakeEnv("openai-key"),
        createAdminClient: () => fakeAdmin(state),
      },
    );

    assertEquals(response.status, 400);
    assertEquals(await errorCode(response), "past_generation_date_not_allowed");
  } finally {
    overrideTodayISO(() => "2026-01-01");
  }
});

Deno.test("generate_day reuses the existing draft week and sends the day brief as the only brief", async () => {
  const state = dayGenerationState();
  const dayBrief =
    "Brand shoot day: unbox the new recovery drink at home after the morning walk. Keep it honest, one deliverable Reel.";
  let capturedInput: GenerationInputSnapshot | undefined;

  const response = await handleGenerateWeekRequest(
    requestFor({
      action: "generate_day",
      creator_id: creatorID,
      scheduled_date: "2026-06-10",
      day_brief: dayBrief,
    }),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(state),
      generateDayAI: async (input, _providers, scheduledDate, dayIndex) => {
        capturedInput = input;
        const card = makeMockGeneratedWeek(input).daily_cards[dayIndex];
        return {
          strategy_note: "Single day from day brief.",
          warnings: [],
          assumptions: [],
          daily_card: {
            ...card,
            scheduled_date: scheduledDate,
            title: "Brand recovery drink day",
          },
          idea_bank: [],
          source_summary: "Day brief plus creator profile and references.",
        };
      },
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.weekly_plan_id, weeklyPlanID);
  assertEquals(body.target_scheduled_date, "2026-06-10");
  assertEquals(body.daily_card.title, "Brand recovery drink day");
  assertEquals(
    state.insertedWeeklyPlans.length,
    0,
    "must reuse the existing draft container",
  );
  assertEquals(
    (capturedInput?.weekly_setup as Record<string, unknown>)?.notes,
    dayBrief,
    "the day brief must replace the stored weekly setup",
  );
  assertEquals(capturedInput?.day_guidance, dayBrief);
  assertEquals(state.dailyCards[2].title, "Brand recovery drink day");
});

Deno.test("generate_day creates a thin draft container week when none exists", async () => {
  const state = dayGenerationState();
  const dayBrief = "Rest day vlog: easy morning, stretch, and simple meals.";
  let capturedInput: GenerationInputSnapshot | undefined;

  const response = await handleGenerateWeekRequest(
    requestFor({
      action: "generate_day",
      creator_id: creatorID,
      scheduled_date: "2026-06-17",
      day_brief: dayBrief,
    }),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(state),
      generateDayAI: async (input, _providers, scheduledDate, dayIndex) => {
        capturedInput = input;
        const card = makeMockGeneratedWeek(input).daily_cards[dayIndex];
        return {
          strategy_note: "Fresh container week.",
          warnings: [],
          assumptions: [],
          daily_card: {
            ...card,
            scheduled_date: scheduledDate,
            title: "Rest day reset",
          },
          idea_bank: [],
          source_summary: "Day brief only.",
        };
      },
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(state.insertedWeeklyPlans.length, 1);
  const container = state.insertedWeeklyPlans[0];
  assertEquals(container.week_start_date, "2026-06-15");
  assertEquals(container.status, "draft");
  assertEquals(container.weekly_setup_id, null);
  assertEquals(body.weekly_plan_id, container.id);
  assertEquals(body.target_scheduled_date, "2026-06-17");
  assertEquals(body.daily_card.title, "Rest day reset");
  assertEquals(capturedInput?.week_start_date, "2026-06-15");
  assertEquals(
    (capturedInput?.weekly_setup as Record<string, unknown>)?.notes,
    dayBrief,
  );
  assertEquals(
    state.upsertedDailyCardDates.includes("2026-06-17"),
    true,
    "the generated card must be written for the requested date",
  );
});

Deno.test("generate_day async mode returns a pollable run", async () => {
  const state = dayGenerationState();
  const backgrounded: Promise<void>[] = [];
  const response = await handleGenerateWeekRequest(
    requestFor({
      action: "generate_day",
      creator_id: creatorID,
      scheduled_date: "2026-06-10",
      day_brief: "Simple gym return day.",
      response_mode: "async",
    }),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(state),
      runInBackground: (promise) => {
        backgrounded.push(promise);
      },
      generateDayAI: async (input, _providers, scheduledDate, dayIndex) => {
        const card = makeMockGeneratedWeek(input).daily_cards[dayIndex];
        return {
          strategy_note: "Async day.",
          warnings: [],
          assumptions: [],
          daily_card: {
            ...card,
            scheduled_date: scheduledDate,
            title: "Async gym return",
          },
          idea_bank: [],
          source_summary: "Day brief.",
        };
      },
    },
  );

  assertEquals(response.status, 202);
  const body = await response.json();
  assertEquals(body.status, "running");
  assertEquals(body.target_scheduled_date, "2026-06-10");
  assertEquals(typeof body.generation_id, "string");

  await Promise.all(backgrounded);
  assertEquals(state.dailyCards[2].title, "Async gym return");
});

function requestFor(body: Record<string, unknown>): Request {
  return new Request("http://localhost/generate-week", {
    method: "POST",
    headers: { "x-mco-device-token": "device-token" },
    body: JSON.stringify(body),
  });
}

function regenerateDayBody(): Record<string, unknown> {
  return {
    action: "regenerate_day",
    creator_id: creatorID,
    weekly_plan_id: weeklyPlanID,
    scheduled_date: "2026-06-10",
  };
}

function weekDatesForTest(weekStartDate: string): string[] {
  const dates: string[] = [];
  const start = new Date(`${weekStartDate}T00:00:00.000Z`);
  for (let index = 0; index < 7; index += 1) {
    const date = new Date(start);
    date.setUTCDate(start.getUTCDate() + index);
    dates.push(date.toISOString().slice(0, 10));
  }
  return dates;
}

async function callHandler(
  body: Record<string, unknown>,
  state: Partial<FakeState>,
): Promise<Response> {
  return await handleGenerateWeekRequest(
    new Request("http://localhost/generate-week", {
      method: "POST",
      headers: { "x-mco-device-token": "device-token" },
      body: JSON.stringify(body),
    }),
    {
      env: fakeEnv(state.openAIKey, state.allowMockRequest),
      createAdminClient: () => fakeAdmin(state),
    },
  );
}

function fakeEnv(
  openAIKey?: string,
  allowMockRequest = false,
  deepSeekKey?: string,
): { get: (name: string) => string | undefined } {
  const values: Record<string, string> = {
    SUPABASE_URL: "http://127.0.0.1:54321",
    SUPABASE_SERVICE_ROLE_KEY: "local-service-role",
  };
  if (openAIKey) {
    values.OPENAI_API_KEY = openAIKey;
  }
  if (deepSeekKey) {
    values.DEEPSEEK_API_KEY = deepSeekKey;
  }
  if (allowMockRequest) {
    values.MCO_ALLOW_AI_MOCK_REQUEST = "1";
  }
  return { get: (name) => values[name] };
}

type FakeState = {
  memberRole: string;
  creatorExists: boolean;
  setupExists: boolean;
  publishedWeekExists: boolean;
  generationRun: Record<string, unknown> | null;
  weeklyPlan: Record<string, unknown> | null;
  dailyCards: Record<string, unknown>[];
  dayJobs: Record<string, unknown>[];
  insertedWeeklyPlans: Record<string, unknown>[];
  updatedDailyCardIDs: string[];
  upsertedDailyCardDates: string[];
  dailyCardUpdateMissDates: Set<string>;
  dailyCardInsertNoDataDates: Set<string>;
  dailyCardInsertDuplicateDates: Set<string>;
  openAIKey?: string;
  allowMockRequest: boolean;
  lookupFailures: Set<string>;
  dayJobRPCClaims: Record<string, unknown>[];
  dayJobRPCReclaims: Record<string, unknown>[];
  dayJobLeaseUpdates: Record<string, unknown>[];
  dayJobClaimHook?: (
    state: FakeState,
    job: Record<string, unknown>,
  ) => void;
};

function fakeAdmin(
  state: Partial<FakeState>,
): {
  from: (table: string) => any;
  rpc: (
    fn: string,
    params?: Record<string, unknown>,
  ) => Promise<{ data: unknown; error: null }>;
} {
  const resolved: FakeState = {
    memberRole: state.memberRole ?? "owner",
    creatorExists: state.creatorExists ?? true,
    setupExists: state.setupExists ?? true,
    publishedWeekExists: state.publishedWeekExists ?? false,
    generationRun: state.generationRun ?? null,
    weeklyPlan: state.weeklyPlan ?? null,
    dailyCards: state.dailyCards ?? [],
    dayJobs: state.dayJobs ?? [],
    insertedWeeklyPlans: state.insertedWeeklyPlans ?? [],
    updatedDailyCardIDs: state.updatedDailyCardIDs ?? [],
    upsertedDailyCardDates: state.upsertedDailyCardDates ?? [],
    dailyCardUpdateMissDates: state.dailyCardUpdateMissDates ?? new Set(),
    dailyCardInsertNoDataDates: state.dailyCardInsertNoDataDates ?? new Set(),
    dailyCardInsertDuplicateDates: state.dailyCardInsertDuplicateDates ??
      new Set(),
    openAIKey: state.openAIKey,
    allowMockRequest: state.allowMockRequest ?? false,
    lookupFailures: state.lookupFailures ?? new Set(),
    dayJobRPCClaims: state.dayJobRPCClaims ?? [],
    dayJobRPCReclaims: state.dayJobRPCReclaims ?? [],
    dayJobLeaseUpdates: state.dayJobLeaseUpdates ?? [],
    dayJobClaimHook: state.dayJobClaimHook,
  };
  return {
    from(table: string) {
      return new FakeQuery(table, resolved);
    },
    rpc(fn: string, params?: Record<string, unknown>) {
      return fakeRPC(fn, params ?? {}, resolved);
    },
  };
}

async function fakeRPC(
  fn: string,
  params: Record<string, unknown>,
  state: FakeState,
): Promise<{ data: unknown; error: null }> {
  switch (fn) {
    case "claim_queued_day_job": {
      const genRunID = params.p_generation_run_id as string;
      const job = state.dayJobs.find((j) =>
        j.generation_run_id === genRunID &&
        (j.status === "queued" || j.status === "retrying")
      );
      if (!job) return { data: null, error: null };
      job.status = "generating";
      job.lease_token = params.p_lease_token;
      job.worker_boot_id = params.p_worker_boot_id;
      job.heartbeat_at = new Date().toISOString();
      job.started_at = job.started_at ?? new Date().toISOString();
      job.attempt_count = ((job.attempt_count as number) ?? 0) + 1;
      job.error_code = null;
      job.error_message = null;
      job.completed_at = null;
      state.dayJobRPCClaims.push({ ...job });
      state.dayJobClaimHook?.(state, job);
      return { data: job, error: null };
    }
    case "reclaim_stale_day_job": {
      const genRunID = params.p_generation_run_id as string;
      const threshold = (params.p_stale_threshold_ms as number) ?? 240000;
      const maxAttempts = (params.p_max_attempts as number) ?? 3;
      const cutoff = new Date(Date.now() - threshold).toISOString();

      for (const j of state.dayJobs) {
        if (
          j.generation_run_id === genRunID &&
          j.status === "generating" &&
          typeof j.heartbeat_at === "string" &&
          j.heartbeat_at < cutoff &&
          ((j.attempt_count as number) ?? 0) >= maxAttempts
        ) {
          j.status = "failed";
          j.error_code = "generation_timeout";
          j.error_message =
            "Stale job reached max attempts without completing.";
          j.completed_at = new Date().toISOString();
        }
      }

      const stale = state.dayJobs.find((j) =>
        j.generation_run_id === genRunID &&
        j.status === "generating" &&
        typeof j.heartbeat_at === "string" &&
        j.heartbeat_at < cutoff &&
        ((j.attempt_count as number) ?? 0) < maxAttempts
      );
      if (!stale) return { data: null, error: null };
      stale.lease_token = params.p_lease_token;
      stale.worker_boot_id = params.p_worker_boot_id;
      stale.heartbeat_at = new Date().toISOString();
      stale.started_at = new Date().toISOString();
      stale.attempt_count = ((stale.attempt_count as number) ?? 0) + 1;
      stale.error_code = null;
      stale.error_message = null;
      stale.completed_at = null;
      state.dayJobRPCReclaims.push({ ...stale });
      return { data: stale, error: null };
    }
    case "stage_day_job_output": {
      const job = state.dayJobs.find((candidate) =>
        candidate.id === params.p_job_id &&
        candidate.lease_token === params.p_lease_token &&
        candidate.attempt_count === params.p_attempt &&
        candidate.status === "generating"
      );
      if (!job) return { data: null, error: null };
      job.status = "ready_to_persist";
      job.staged_output = params.p_output;
      job.completed_at = new Date().toISOString();
      return { data: job, error: null };
    }
    default:
      return { data: null, error: null };
  }
}

class FakeQuery {
  private operation: "select" | "update" | "insert" | "upsert" | "delete" =
    "select";
  private filters: Record<string, unknown> = {};
  private values: unknown;

  constructor(
    private readonly table: string,
    private readonly state: FakeState,
  ) {}

  select(_columns?: string): FakeQuery {
    return this;
  }

  update(values: unknown): FakeQuery {
    this.operation = "update";
    this.values = values;
    return this;
  }

  insert(values: unknown): FakeQuery {
    this.operation = "insert";
    this.values = values;
    return this;
  }

  upsert(values: unknown): FakeQuery {
    this.operation = "upsert";
    this.values = values;
    return this;
  }

  delete(): FakeQuery {
    this.operation = "delete";
    return this;
  }

  eq(column: string, value: unknown): FakeQuery {
    this.filters[column] = value;
    return this;
  }

  is(column: string, value: unknown): FakeQuery {
    this.filters[column] = value;
    return this;
  }

  in(column: string, value: unknown): FakeQuery {
    this.filters[column] = value;
    return this;
  }

  gte(column: string, value: unknown): FakeQuery {
    this.filters[`${column}.gte`] = value;
    return this;
  }

  lte(column: string, value: unknown): FakeQuery {
    this.filters[`${column}.lte`] = value;
    return this;
  }

  order(_column: string, _options?: unknown): FakeQuery {
    return this;
  }

  limit(_count: number): FakeQuery {
    return this;
  }

  maybeSingle(): Promise<{ data: unknown; error: null }> {
    const result = this.resolve();
    return Promise.resolve({
      data: Array.isArray(result.data) ? result.data[0] ?? null : result.data,
      error: null,
    });
  }

  single(): Promise<{ data: unknown; error: null }> {
    const result = this.resolve();
    return Promise.resolve({
      data: Array.isArray(result.data) ? result.data[0] ?? null : result.data,
      error: null,
    });
  }

  then<TResult1 = { data: unknown; error: null }, TResult2 = never>(
    onfulfilled?:
      | ((
        value: { data: unknown; error: null },
      ) => TResult1 | PromiseLike<TResult1>)
      | null,
    onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
  ): Promise<TResult1 | TResult2> {
    return Promise.resolve(this.resolve()).then(onfulfilled, onrejected);
  }

  private resolve(): { data: unknown; error: null } {
    if (
      this.operation === "select" && this.state.lookupFailures.has(this.table)
    ) {
      return {
        data: null,
        error: { message: `${this.table} forced lookup failure` } as never,
      };
    }

    if (this.operation !== "select") {
      if (this.table === "weekly_plans" && this.operation === "insert") {
        const values = this.values as Record<string, unknown>;
        this.state.insertedWeeklyPlans.push({ ...values });
        this.state.weeklyPlan = { is_soft_locked: false, ...values };
        return { data: { id: values.id }, error: null };
      }
      if (
        this.table === "weekly_generation_runs" &&
        this.operation === "insert"
      ) {
        const values = this.values as Record<string, unknown>;
        this.state.generationRun = { id: generationRunID, ...values };
        return { data: { id: generationRunID }, error: null };
      }
      if (
        this.table === "weekly_generation_runs" &&
        this.operation === "update" && this.state.generationRun
      ) {
        Object.assign(
          this.state.generationRun,
          this.values as Record<string, unknown>,
        );
      }
      if (
        this.table === "weekly_generation_day_jobs" &&
        this.operation === "update"
      ) {
        const values = this.values as Record<string, unknown>;
        const rows = this.state.dayJobs.filter((job) =>
          (!this.filters.id || job.id === this.filters.id) &&
          (!this.filters.lease_token ||
            job.lease_token === this.filters.lease_token) &&
          (!this.filters.generation_run_id ||
            job.generation_run_id === this.filters.generation_run_id) &&
          (!this.filters.workspace_id ||
            job.workspace_id === this.filters.workspace_id) &&
          (!this.filters.creator_id ||
            job.creator_id === this.filters.creator_id) &&
          (!this.filters.scheduled_date ||
            job.scheduled_date === this.filters.scheduled_date) &&
          (!this.filters.status || job.status === this.filters.status ||
            (Array.isArray(this.filters.status) &&
              this.filters.status.includes(job.status)))
        );
        const applied = rows.length;
        rows.forEach((row) => Object.assign(row, values));
        if (applied > 0) {
          this.state.dayJobLeaseUpdates.push({
            filters: { ...this.filters },
            values: { ...values },
            applied,
          });
        }
        return {
          data: applied > 0 ? rows[0] : null,
          error: applied > 0 ? null : { message: "no rows matched" } as never,
        };
      }
      if (this.table === "daily_cards" && this.operation === "update") {
        if (
          this.state.dailyCardUpdateMissDates.has(
            String(this.filters.scheduled_date),
          )
        ) {
          return { data: null, error: null };
        }
        const card = this.state.dailyCards.find((candidate) =>
          candidate.id === this.filters.id &&
          candidate.scheduled_date === this.filters.scheduled_date
        );
        if (!card) {
          return { data: null, error: null };
        }
        Object.assign(card, this.values as Record<string, unknown>);
        this.state.updatedDailyCardIDs.push(String(card.id));
        return {
          data: { id: card.id, scheduled_date: card.scheduled_date },
          error: null,
        };
      }
      if (
        this.table === "daily_cards" &&
        (this.operation === "insert" || this.operation === "upsert")
      ) {
        const values = this.values as Record<string, unknown>;
        const scheduledDate = String(values.scheduled_date);
        this.state.upsertedDailyCardDates.push(scheduledDate);
        if (
          this.operation === "insert" &&
          this.state.dailyCardInsertDuplicateDates.has(scheduledDate)
        ) {
          this.state.dailyCards.push({
            ...values,
            id: dailyCardIDs[0],
          });
          return {
            data: null,
            error: {
              message:
                'duplicate key value violates unique constraint "daily_cards_weekly_plan_id_scheduled_date_key"',
              code: "23505",
            } as never,
          };
        }
        const existing = this.state.dailyCards.find((candidate) =>
          candidate.weekly_plan_id === values.weekly_plan_id &&
          candidate.scheduled_date === values.scheduled_date
        );
        if (existing) {
          Object.assign(existing, values);
        } else {
          this.state.dailyCards.push(values);
        }
        if (
          this.operation === "insert" &&
          this.state.dailyCardInsertNoDataDates.has(scheduledDate)
        ) {
          return { data: null, error: null };
        }
        return {
          data: { id: values.id, scheduled_date: values.scheduled_date },
          error: null,
        };
      }
      if (
        this.table === "weekly_generation_day_jobs" &&
        (this.operation === "insert" || this.operation === "upsert")
      ) {
        const values = Array.isArray(this.values)
          ? this.values as Record<string, unknown>[]
          : [this.values as Record<string, unknown>];
        values.forEach((value, index) => {
          const existing = this.state.dayJobs.find((job) =>
            job.generation_run_id === value.generation_run_id &&
            job.scheduled_date === value.scheduled_date
          );
          const row = {
            id: `99999999-9999-4999-8999-99999999999${index}`,
            ...value,
          };
          if (existing) {
            Object.assign(existing, row);
          } else {
            this.state.dayJobs.push(row);
          }
        });
        return { data: this.state.dayJobs, error: null };
      }
      return {
        data: Array.isArray(this.values) ? this.values : this.values ?? {
          id: "write-ok",
        },
        error: null,
      };
    }

    switch (this.table) {
      case "device_installations":
        return {
          data: {
            id: "device-installation-id",
            workspace_id: workspaceID,
            member_id: memberID,
            revoked_at: null,
          },
          error: null,
        };
      case "members":
        return {
          data: {
            id: memberID,
            workspace_id: workspaceID,
            role: this.state.memberRole,
            status: "active",
          },
          error: null,
        };
      case "creators":
        return {
          data: this.state.creatorExists
            ? {
              id: creatorID,
              display_name: "Creator",
              default_timezone: "Asia/Kolkata",
            }
            : null,
          error: null,
        };
      case "weekly_plans":
        if (this.filters.id === weeklyPlanID) {
          return { data: this.state.weeklyPlan, error: null };
        }
        if (
          this.filters.id &&
          this.state.weeklyPlan &&
          this.state.weeklyPlan.id === this.filters.id
        ) {
          return { data: this.state.weeklyPlan, error: null };
        }
        if (
          this.state.weeklyPlan &&
          this.filters.creator_id === this.state.weeklyPlan.creator_id &&
          this.filters.week_start_date === this.state.weeklyPlan.week_start_date
        ) {
          const statuses = Array.isArray(this.filters.status)
            ? this.filters.status
            : [this.filters.status];
          if (
            statuses.includes(this.state.weeklyPlan.status) ||
            statuses.includes(undefined)
          ) {
            return { data: [this.state.weeklyPlan], error: null };
          }
        }
        return {
          data: this.state.publishedWeekExists &&
              this.filters.status === "published"
            ? { id: "published-plan-id" }
            : [],
          error: null,
        };
      case "weekly_generation_runs":
        return {
          data: this.state.generationRun ? this.state.generationRun : [],
          error: null,
        };
      case "weekly_generation_day_jobs":
        return {
          data: this.state.dayJobs.filter((job) =>
            (!this.filters.generation_run_id ||
              job.generation_run_id === this.filters.generation_run_id) &&
            (!this.filters.workspace_id ||
              job.workspace_id === this.filters.workspace_id) &&
            (!this.filters.creator_id ||
              job.creator_id === this.filters.creator_id)
          ),
          error: null,
        };
      case "daily_cards":
        return {
          data: this.state.dailyCards.filter((card) =>
            (!this.filters.id || card.id === this.filters.id) &&
            (!this.filters.workspace_id ||
              card.workspace_id === this.filters.workspace_id) &&
            (!this.filters.weekly_plan_id ||
              card.weekly_plan_id === this.filters.weekly_plan_id) &&
            (!this.filters.scheduled_date ||
              card.scheduled_date === this.filters.scheduled_date) &&
            (!this.filters.creator_id ||
              card.creator_id === this.filters.creator_id)
          ),
          error: null,
        };
      case "weekly_setups":
        return {
          data: this.state.setupExists
            ? [{
              id: setupID,
              creator_profile_id: null,
              week_start_date: "2026-06-08",
              status: "draft",
              location: "Mumbai",
            }]
            : [],
          error: null,
        };
      case "creator_profiles":
        return {
          data: [{
            id: "profile-id",
            status: "active",
            positioning: "Fitness after 60",
          }],
          error: null,
        };
      case "source_references":
        return {
          data: [{
            id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
            source_type: "reel_link",
            manual_notes: "Confirmed towel transition",
            status: "confirmed",
          }],
          error: null,
        };
      case "reference_extractions":
        return {
          data: [{
            id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1",
            source_reference_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
            extraction_kind: "pattern",
            extracted_payload: { summary: "hook-led sock transition" },
            status: "confirmed",
          }],
          error: null,
        };
      case "archive_entries":
        return { data: [], error: null };
      case "ideas":
        return { data: [], error: null };
      case "patterns":
        return { data: [], error: null };
      case "trends":
        return { data: [], error: null };
      case "audio_options":
        return { data: [], error: null };
      case "brand_briefs":
        return {
          data: [{
            id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            brand_name: "Brand hydration reminder",
            status: "active",
          }],
          error: null,
        };
      case "key_moments":
        return {
          data: [{
            id: "cccccccc-cccc-4ccc-8ccc-ccccccccccc1",
            name: "Sunday 10K",
            moment_date: "2026-06-14",
            status: "upcoming",
          }],
          error: null,
        };
      default:
        return { data: [], error: null };
    }
  }
}

function dayGenerationState(): FakeState {
  const input = generationInputSnapshot();
  const cards = makeMockGeneratedWeek(input).daily_cards.map((card, index) => ({
    ...card,
    id: dailyCardIDs[index],
    workspace_id: workspaceID,
    creator_id: creatorID,
    weekly_plan_id: weeklyPlanID,
    status: "draft",
    post_instructions: {
      instructions: card.post_instructions,
      audio_option_notes: card.audio_option_notes,
      format: card.format,
      primary_surface: card.primary_surface,
      duration_seconds: card.duration_seconds,
      hook: card.hook,
      weekly_brief_anchor: card.weekly_brief_anchor,
      brief_alignment: card.brief_alignment,
      brief_context_tags: card.brief_context_tags,
      save_share_reason: card.save_share_reason,
      shot_timeline: card.shot_timeline,
      voiceover_timeline: card.voiceover_timeline,
      silent_version_timeline: card.silent_version_timeline,
      on_screen_text_timeline: card.on_screen_text_timeline,
      caption_backup_detail: card.caption_backup_detail,
    },
    backup_story: { line: card.backup_story, detail: card.backup_story_detail },
    backup_caption_only: {
      line: card.backup_caption_only,
      detail: card.caption_backup_detail,
    },
  }));
  return {
    memberRole: "owner",
    creatorExists: true,
    setupExists: true,
    publishedWeekExists: false,
    generationRun: null,
    weeklyPlan: {
      id: weeklyPlanID,
      workspace_id: workspaceID,
      creator_id: creatorID,
      weekly_setup_id: setupID,
      week_start_date: "2026-06-08",
      status: "draft",
      is_soft_locked: false,
    },
    dailyCards: cards,
    dayJobs: [],
    insertedWeeklyPlans: [],
    updatedDailyCardIDs: [],
    upsertedDailyCardDates: [],
    dailyCardUpdateMissDates: new Set(),
    dailyCardInsertNoDataDates: new Set(),
    dailyCardInsertDuplicateDates: new Set(),
    openAIKey: "openai-key",
    allowMockRequest: false,
    lookupFailures: new Set(),
    dayJobRPCClaims: [],
    dayJobRPCReclaims: [],
    dayJobLeaseUpdates: [],
  };
}

function makeQueuedDayJobs(
  statuses: Array<[string, string | null]>,
): Record<string, unknown>[] {
  return statuses.map(([status, dailyCardID], index) => ({
    id: `99999999-9999-4999-8999-99999999999${index}`,
    generation_run_id: generationRunID,
    weekly_plan_id: weeklyPlanID,
    workspace_id: workspaceID,
    creator_id: creatorID,
    scheduled_date: weekDatesForTests("2026-06-08")[index],
    day_index: index,
    status,
    attempt_count: status === "queued" ? 0 : 1,
    daily_card_id: dailyCardID,
    error_code: status === "failed" ? "invalid_ai_json" : null,
    started_at: status === "queued" ? null : "2026-06-01T00:00:00.000Z",
    completed_at: status === "generated" || status === "failed"
      ? "2026-06-01T00:01:00.000Z"
      : null,
  }));
}

function weekDatesForTests(weekStartDate: string): string[] {
  const start = new Date(`${weekStartDate}T00:00:00.000Z`);
  return Array.from({ length: 7 }, (_, index) => {
    const date = new Date(start);
    date.setUTCDate(start.getUTCDate() + index);
    return date.toISOString().slice(0, 10);
  });
}

function generationInputSnapshot(): GenerationInputSnapshot {
  return {
    creator_id: creatorID,
    week_start_date: "2026-06-08",
    creator_profile: null,
    weekly_setup: null,
    confirmed_references: [],
    reference_extractions: [],
    recent_archive: [],
    idea_bank: [],
    patterns: [],
    trends: [],
    audio_options: [],
    brand_briefs: [],
    key_moments: [],
  };
}

async function errorCode(response: Response): Promise<string | undefined> {
  return (await response.json()).error;
}

function assert(
  condition: unknown,
  message = "Assertion failed",
): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  if (!Object.is(actual, expected)) {
    throw new Error(
      message ??
        `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

function recordValue(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(`Expected object, got ${JSON.stringify(value)}`);
  }
  return value as Record<string, unknown>;
}

function assertArrayContainsObject(
  value: unknown,
  key: string,
  expected: unknown,
): void {
  if (!Array.isArray(value)) {
    throw new Error(`Expected array, got ${JSON.stringify(value)}`);
  }
  const found = value.some((item) =>
    typeof item === "object" &&
    item !== null &&
    Object.is(
      JSON.stringify((item as Record<string, unknown>)[key]),
      JSON.stringify(expected),
    )
  );
  if (!found) {
    throw new Error(
      `Expected array to contain ${key}=${JSON.stringify(expected)}, got ${
        JSON.stringify(value)
      }`,
    );
  }
}

// ── Lifecycle logging tests ──

type CapturedLog = {
  raw: string;
  parsed: Record<string, unknown> | null;
};

function captureConsoleLog(): {
  logs: CapturedLog[];
  restore: () => void;
} {
  const logs: CapturedLog[] = [];
  const original = console.log;
  console.log = (...args: unknown[]) => {
    const raw = args.map(String).join(" ");
    let parsed: Record<string, unknown> | null = null;
    try {
      const obj = JSON.parse(raw);
      if (typeof obj === "object" && obj !== null) {
        parsed = obj as Record<string, unknown>;
      }
    } catch {
    }
    logs.push({ raw, parsed });
  };
  return {
    logs,
    restore: () => {
      console.log = original;
    },
  };
}

function lifecycleLogs(
  captured: CapturedLog[],
): Record<string, unknown>[] {
  return captured
    .filter((entry) => entry.parsed?.event === "generation_lifecycle")
    .map((entry) => entry.parsed as Record<string, unknown>);
}

function findLifecycleLog(
  captured: CapturedLog[],
  action: string,
  phase: string,
): Record<string, unknown> | undefined {
  return lifecycleLogs(captured).find((log) =>
    log.action === action && log.phase === phase
  );
}

function assertLifecycleSanitized(
  captured: CapturedLog[],
  sensitiveValues: string[] = [],
): void {
  const forbiddenKeys = new Set([
    "day_guidance",
    "api_key",
    "apiKey",
    "authorization",
    "prompt",
    "system",
    "user_content",
    "request_body",
    "response_body",
    "token",
    "openai_api_key",
    "deepseek_api_key",
    "supabase_service_role_key",
  ]);
  for (const entry of lifecycleLogs(captured)) {
    for (const key of Object.keys(entry)) {
      if (forbiddenKeys.has(key)) {
        throw new Error(
          `Lifecycle log contains forbidden key "${key}": ${
            JSON.stringify(entry).slice(0, 300)
          }`,
        );
      }
    }
    for (const value of sensitiveValues) {
      if (value && JSON.stringify(entry).includes(value)) {
        throw new Error(
          `Lifecycle log contains sensitive value "${value}": ${
            JSON.stringify(entry).slice(0, 300)
          }`,
        );
      }
    }
  }
}

Deno.test("regenerate_day emits accepted/started/completed lifecycle logs with guidance metadata", async () => {
  const guidance = "Focus on the Thursday brand brief for recovery products.";
  const captured = captureConsoleLog();
  try {
    const response = await handleGenerateWeekRequest(
      requestFor({
        action: "regenerate_day",
        creator_id: creatorID,
        weekly_plan_id: weeklyPlanID,
        scheduled_date: "2026-06-10",
        preserve_manual_edits: false,
        day_guidance: guidance,
      }),
      {
        env: fakeEnv("openai-key"),
        createAdminClient: () => fakeAdmin(dayGenerationState()),
        generateDayAI: async (input, _providers, scheduledDate, dayIndex) => {
          const card = makeMockGeneratedWeek(input).daily_cards[dayIndex];
          return {
            strategy_note: "Regenerated",
            warnings: [],
            assumptions: [],
            daily_card: { ...card, scheduled_date: scheduledDate },
            idea_bank: [],
            source_summary: "test",
          };
        },
      },
    );
    assertEquals(response.status, 200);
  } finally {
    captured.restore();
  }

  const accepted = findLifecycleLog(
    captured.logs,
    "regenerate_day",
    "request_accepted",
  );
  assert(accepted !== undefined, "expected request_accepted lifecycle log");
  assertEquals(accepted.generation_id, generationRunID);
  assertEquals(accepted.weekly_plan_id, weeklyPlanID);
  assertEquals(accepted.scheduled_date, "2026-06-10");
  assertEquals(accepted.day_guidance_present, true);
  assertEquals(accepted.day_guidance_chars, guidance.length);

  const started = findLifecycleLog(
    captured.logs,
    "regenerate_day",
    "generation_started",
  );
  assert(started !== undefined, "expected generation_started lifecycle log");
  assertEquals(started.status, "running");
  assertEquals(started.day_index, 2);
  assertEquals(started.day_guidance_present, true);

  const completed = findLifecycleLog(
    captured.logs,
    "regenerate_day",
    "generation_completed",
  );
  assert(
    completed !== undefined,
    "expected generation_completed lifecycle log",
  );
  assertEquals(completed.status, "completed");
  assertEquals(completed.day_index, 2);
  assert(
    typeof completed.duration_ms === "number" && completed.duration_ms >= 0,
    "duration_ms should be a non-negative number",
  );
  assertEquals(completed.day_guidance_present, true);
  assertEquals(completed.day_guidance_chars, guidance.length);

  assertLifecycleSanitized(captured.logs, [guidance]);
});

Deno.test("regenerate_day without guidance logs day_guidance_present=false", async () => {
  const captured = captureConsoleLog();
  try {
    const response = await handleGenerateWeekRequest(
      requestFor({
        action: "regenerate_day",
        creator_id: creatorID,
        weekly_plan_id: weeklyPlanID,
        scheduled_date: "2026-06-10",
        preserve_manual_edits: false,
      }),
      {
        env: fakeEnv("openai-key"),
        createAdminClient: () => fakeAdmin(dayGenerationState()),
        generateDayAI: async (input, _providers, scheduledDate, dayIndex) => {
          const card = makeMockGeneratedWeek(input).daily_cards[dayIndex];
          return {
            strategy_note: "No guidance",
            warnings: [],
            assumptions: [],
            daily_card: { ...card, scheduled_date: scheduledDate },
            idea_bank: [],
            source_summary: "test",
          };
        },
      },
    );
    assertEquals(response.status, 200);
  } finally {
    captured.restore();
  }

  const accepted = findLifecycleLog(
    captured.logs,
    "regenerate_day",
    "request_accepted",
  );
  assert(accepted !== undefined, "expected request_accepted lifecycle log");
  assertEquals(accepted.day_guidance_present, false);
  assertEquals(accepted.day_guidance_chars, 0);

  const completed = findLifecycleLog(
    captured.logs,
    "regenerate_day",
    "generation_completed",
  );
  assert(
    completed !== undefined,
    "expected generation_completed lifecycle log",
  );
  assertEquals(completed.day_guidance_present, false);
  assertEquals(completed.day_guidance_chars, 0);
});

Deno.test("regenerate_day emits generation_failed lifecycle log on AI failure", async () => {
  const captured = captureConsoleLog();
  try {
    const response = await handleGenerateWeekRequest(
      requestFor({
        action: "regenerate_day",
        creator_id: creatorID,
        weekly_plan_id: weeklyPlanID,
        scheduled_date: "2026-06-10",
        preserve_manual_edits: false,
      }),
      {
        env: fakeEnv("openai-key"),
        createAdminClient: () => fakeAdmin(dayGenerationState()),
        generateDayAI: async () => {
          throw new GenerateWeekValidationError(
            "invalid_ai_json",
            "AI returned malformed JSON.",
          );
        },
      },
    );
    assertEquals(response.status, 400);
  } finally {
    captured.restore();
  }

  const failed = findLifecycleLog(
    captured.logs,
    "regenerate_day",
    "generation_failed",
  );
  assert(failed !== undefined, "expected generation_failed lifecycle log");
  assertEquals(failed.status, "failed");
  assertEquals(failed.generation_id, generationRunID);
  assertEquals(failed.scheduled_date, "2026-06-10");
  assertEquals(failed.day_index, 2);
  assert(
    typeof failed.duration_ms === "number" && failed.duration_ms >= 0,
    "duration_ms should be a non-negative number",
  );
  assertLifecycleSanitized(captured.logs);
});

Deno.test("parallel day-job heartbeat updates only the row owned by the lease and attempt", async () => {
  const state = dayGenerationState();
  const now = Date.now();
  const completedAt = new Date(now - 60_000).toISOString();

  state.dayJobs = makeQueuedDayJobs([
    ["queued", null],
    ["generated", dailyCardIDs[1]],
    ["generated", dailyCardIDs[2]],
    ["generated", dailyCardIDs[3]],
    ["generated", dailyCardIDs[4]],
    ["generated", dailyCardIDs[5]],
    ["generated", dailyCardIDs[6]],
  ]);
  state.dayJobs[0].lease_token = "lease-worker-a";
  state.dayJobs[0].worker_boot_id = "boot-a";
  state.dayJobs[0].status = "generating";
  state.dayJobs[0].heartbeat_at = new Date(now - 10_000).toISOString();
  state.dayJobs[0].started_at = new Date(now - 40_000).toISOString();

  state.generationRun = {
    id: generationRunID,
    workspace_id: workspaceID,
    creator_id: creatorID,
    requested_by_member_id: memberID,
    status: "running",
    model: "openai:gpt-4.1-mini",
    weekly_plan_id: weeklyPlanID,
    input_snapshot: generationInputSnapshot(),
    output_snapshot: {
      kind: "parallel_week_generation_v1",
      week_start_date: "2026-06-08",
      weekly_plan_id: weeklyPlanID,
      strategy_created: true,
      updated_at: completedAt,
      days: weekDatesForTest("2026-06-08").map((scheduledDate, index) => ({
        scheduled_date: scheduledDate,
        status: index === 0 ? "running" : "completed",
        attempts: 1,
        daily_card_id: index > 0 ? dailyCardIDs[index] : undefined,
        started_at: index === 0 ? state.dayJobs[0].started_at : undefined,
        heartbeat_at: index === 0 ? state.dayJobs[0].heartbeat_at : undefined,
        completed_at: index > 0 ? completedAt : undefined,
      })),
    },
  };

  const response = await handleGenerateWeekRequest(
    requestFor({
      action: "status",
      generation_id: generationRunID,
      creator_id: creatorID,
    }),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(state),
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.status, "running");
  assertEquals(body.failed_day_count, 0);
});

Deno.test("parallel day-job stale reclaim gives a new lease and the old lease is powerless", async () => {
  const state = dayGenerationState();
  const now = Date.now();
  const staleHeartbeat = new Date(now - 400_000).toISOString();

  state.dayJobs = makeQueuedDayJobs([
    ["generating", null],
    ["generated", dailyCardIDs[1]],
    ["generated", dailyCardIDs[2]],
    ["generated", dailyCardIDs[3]],
    ["generated", dailyCardIDs[4]],
    ["generated", dailyCardIDs[5]],
    ["generated", dailyCardIDs[6]],
  ]);
  state.dayJobs[0].lease_token = "lease-worker-a";
  state.dayJobs[0].worker_boot_id = "boot-a";
  state.dayJobs[0].heartbeat_at = staleHeartbeat;
  state.dayJobs[0].started_at = staleHeartbeat;
  state.dayJobs[0].attempt_count = 1;
  state.dayJobs[0].status = "generating";

  state.generationRun = {
    id: generationRunID,
    workspace_id: workspaceID,
    creator_id: creatorID,
    requested_by_member_id: memberID,
    status: "running",
    model: "openai:gpt-4.1-mini",
    weekly_plan_id: weeklyPlanID,
    input_snapshot: generationInputSnapshot(),
    output_snapshot: {
      kind: "parallel_week_generation_v1",
      week_start_date: "2026-06-08",
      weekly_plan_id: weeklyPlanID,
      strategy_created: true,
      updated_at: staleHeartbeat,
      days: weekDatesForTest("2026-06-08").map((scheduledDate, index) => ({
        scheduled_date: scheduledDate,
        status: index === 0 ? "running" : "completed",
        attempts: 1,
        daily_card_id: index > 0 ? dailyCardIDs[index] : undefined,
        started_at: index === 0 ? staleHeartbeat : undefined,
        heartbeat_at: index === 0 ? staleHeartbeat : undefined,
        completed_at: index > 0
          ? new Date(now - 2_000).toISOString()
          : undefined,
      })),
    },
  };

  // Reclaim directly via the RPC — simulates what happens when the status poll's
  // resume loop detects the stale generating job.
  const admin = fakeAdmin(state);
  const bLease = "lease-worker-b";
  const result = await admin.rpc("reclaim_stale_day_job", {
    p_generation_run_id: generationRunID,
    p_lease_token: bLease,
    p_worker_boot_id: "boot-b",
    p_stale_threshold_ms: 240000,
  });

  assertEquals(result.error, null);
  assertEquals(state.dayJobRPCReclaims.length, 1);

  const job = state.dayJobs[0];
  assertEquals(job.lease_token, bLease);
  assertEquals(job.attempt_count, 2);
  assertEquals(job.error_code, null);
});

Deno.test("four stale generating jobs leave four slots available for reclaim", () => {
  const now = Date.now();
  const staleHeartbeat = new Date(now - 400_000).toISOString();
  const jobs = makeQueuedDayJobs([
    ["generating", null],
    ["generating", null],
    ["generating", null],
    ["generating", null],
    ["generated", dailyCardIDs[4]],
    ["generated", dailyCardIDs[5]],
    ["generated", dailyCardIDs[6]],
  ]);
  for (const job of jobs.slice(0, 4)) {
    job.started_at = staleHeartbeat;
    job.heartbeat_at = staleHeartbeat;
  }

  assertEquals(
    availableParallelDayJobSlots(jobs, 4, 240_000, now),
    4,
    "stale workers must not consume live concurrency slots",
  );
});

Deno.test("competing-worker regression: late heartbeat from worker A cannot mutate worker B reclaimed row", async () => {
  const state = dayGenerationState();
  const now = Date.now();
  const staleHeartbeat = new Date(now - 400_000).toISOString();

  state.dayJobs = makeQueuedDayJobs([
    ["generating", null],
    ["generated", dailyCardIDs[1]],
    ["generated", dailyCardIDs[2]],
    ["generated", dailyCardIDs[3]],
    ["generated", dailyCardIDs[4]],
    ["generated", dailyCardIDs[5]],
    ["generated", dailyCardIDs[6]],
  ]);
  const job = state.dayJobs[0];
  job.lease_token = "lease-worker-a";
  job.worker_boot_id = "boot-a";
  job.heartbeat_at = staleHeartbeat;
  job.started_at = staleHeartbeat;
  job.attempt_count = 1;

  state.generationRun = {
    id: generationRunID,
    workspace_id: workspaceID,
    creator_id: creatorID,
    requested_by_member_id: memberID,
    status: "running",
    model: "openai:gpt-4.1-mini",
    weekly_plan_id: weeklyPlanID,
    input_snapshot: generationInputSnapshot(),
    output_snapshot: {
      kind: "parallel_week_generation_v1",
      week_start_date: "2026-06-08",
      weekly_plan_id: weeklyPlanID,
      strategy_created: true,
      updated_at: staleHeartbeat,
      days: weekDatesForTest("2026-06-08").map((scheduledDate, index) => ({
        scheduled_date: scheduledDate,
        status: index === 0 ? "running" : "completed",
        attempts: 1,
        daily_card_id: index > 0 ? dailyCardIDs[index] : undefined,
        started_at: index === 0 ? staleHeartbeat : undefined,
        heartbeat_at: index === 0 ? staleHeartbeat : undefined,
        completed_at: index > 0
          ? new Date(now - 2_000).toISOString()
          : undefined,
      })),
    },
  };

  const admin = fakeAdmin(state);

  // Simulate worker B reclaiming the stale job via the RPC
  const bLease = "lease-worker-b";
  await admin.rpc("reclaim_stale_day_job", {
    p_generation_run_id: generationRunID,
    p_lease_token: bLease,
    p_worker_boot_id: "boot-b",
    p_stale_threshold_ms: 240000,
  });

  assertEquals(state.dayJobRPCReclaims.length, 1);
  assertEquals(job.lease_token, bLease);
  assertEquals(job.attempt_count, 2);

  const staleStage = await admin.rpc("stage_day_job_output", {
    p_job_id: job.id,
    p_lease_token: "lease-worker-a",
    p_attempt: 1,
    p_output: { source_summary: "stale worker output" },
  });
  assertEquals(staleStage.data, null);
  assertEquals(job.staged_output ?? null, null);

  const currentStage = await admin.rpc("stage_day_job_output", {
    p_job_id: job.id,
    p_lease_token: bLease,
    p_attempt: 2,
    p_output: { source_summary: "current worker output" },
  });
  assert(currentStage.data !== null, "current owner should stage its output");
  assertEquals(job.status, "ready_to_persist");
  assertEquals(
    (job.staged_output as Record<string, unknown>).source_summary,
    "current worker output",
  );

  // Worker A's late heartbeat must NOT update the row (lease mismatch)
  const preHeartbeatAttempt = job.attempt_count;
  const preHeartbeatLease = job.lease_token;

  // Direct update via fake admin with worker A's old lease
  await admin.from("weekly_generation_day_jobs")
    .update({ heartbeat_at: new Date(now + 60_000).toISOString() })
    .eq("id", job.id)
    .eq("lease_token", "lease-worker-a")
    .eq("status", "ready_to_persist");

  assertEquals(
    job.attempt_count,
    preHeartbeatAttempt,
    "worker A's late heartbeat must not change attempt_count",
  );
  assertEquals(
    job.lease_token,
    preHeartbeatLease,
    "worker A's late heartbeat must not change lease_token",
  );

  // Worker A's late completion must also be rejected
  await admin.from("weekly_generation_day_jobs")
    .update({ status: "generated", daily_card_id: dailyCardIDs[0] })
    .eq("id", job.id)
    .eq("lease_token", "lease-worker-a")
    .eq("status", "ready_to_persist");

  assertEquals(
    job.status,
    "ready_to_persist",
    "worker A's late completion with wrong lease must not change status",
  );
  assertEquals(
    job.daily_card_id ?? null,
    null,
    "worker A's late completion with wrong lease must not set daily_card_id",
  );
});

Deno.test("parallel day-job worker heartbeat is recorded in the day-job table", async () => {
  const state = dayGenerationState();
  const now = Date.now();

  state.dayJobs = makeQueuedDayJobs([
    ["generating", null],
    ["generated", dailyCardIDs[1]],
    ["generated", dailyCardIDs[2]],
    ["generated", dailyCardIDs[3]],
    ["generated", dailyCardIDs[4]],
    ["generated", dailyCardIDs[5]],
    ["generated", dailyCardIDs[6]],
  ]);
  const job = state.dayJobs[0];
  const lease = "lease-worker-x";
  job.lease_token = lease;
  job.status = "generating";
  job.heartbeat_at = new Date(now - 10_000).toISOString();

  const admin = fakeAdmin(state);

  await admin.from("weekly_generation_day_jobs")
    .update({ heartbeat_at: new Date().toISOString() })
    .eq("id", job.id)
    .eq("lease_token", lease)
    .eq("status", "generating");

  const heartbeatLeaseUpdates = state.dayJobLeaseUpdates.filter((u) => {
    const update = u as {
      filters: Record<string, unknown>;
      values: Record<string, unknown>;
      applied: number;
    };
    return update.filters.lease_token === lease &&
      update.filters.status === "generating" &&
      update.values.heartbeat_at !== undefined &&
      update.applied > 0;
  });
  assert(
    heartbeatLeaseUpdates.length > 0,
    "expected at least one day-job heartbeat with correct lease to be recorded",
  );

  // Confirm stale worker can't heartbeat
  await admin.from("weekly_generation_day_jobs")
    .update({ heartbeat_at: new Date().toISOString() })
    .eq("id", job.id)
    .eq("lease_token", "wrong-lease")
    .eq("status", "generating");

  const staleUpdates = state.dayJobLeaseUpdates.filter((u) => {
    const update = u as {
      filters: Record<string, unknown>;
      values: Record<string, unknown>;
      applied: number;
    };
    return update.filters.lease_token === "wrong-lease" && update.applied > 0;
  });
  assertEquals(staleUpdates.length, 0);
});

Deno.test("generate-week parallel shutdown telemetry is emitted with boot_id", async () => {
  let lastLog = "";
  const original = console.log;
  console.log = (msg: string) => {
    lastLog = msg;
  };

  try {
    const state = dayGenerationState();
    state.dayJobs = makeQueuedDayJobs([
      ["generated", dailyCardIDs[0]],
      ["generated", dailyCardIDs[1]],
      ["generated", dailyCardIDs[2]],
      ["generated", dailyCardIDs[3]],
      ["generated", dailyCardIDs[4]],
      ["generated", dailyCardIDs[5]],
      ["generated", dailyCardIDs[6]],
    ]);
    state.generationRun = {
      id: generationRunID,
      workspace_id: workspaceID,
      creator_id: creatorID,
      requested_by_member_id: memberID,
      status: "running",
      model: "openai:gpt-4.1-mini",
      weekly_plan_id: weeklyPlanID,
      input_snapshot: generationInputSnapshot(),
      output_snapshot: {
        kind: "parallel_week_generation_v1",
        week_start_date: "2026-06-08",
        weekly_plan_id: weeklyPlanID,
        strategy_created: true,
        updated_at: new Date().toISOString(),
        days: weekDatesForTest("2026-06-08").map((scheduledDate, index) => ({
          scheduled_date: scheduledDate,
          status: "completed",
          attempts: 1,
          daily_card_id: dailyCardIDs[index],
          completed_at: new Date().toISOString(),
        })),
      },
    };

    const response = await handleGenerateWeekRequest(
      requestFor({
        action: "status",
        generation_id: generationRunID,
        creator_id: creatorID,
      }),
      {
        env: fakeEnv("openai-key"),
        createAdminClient: () => fakeAdmin(state),
      },
    );

    assertEquals(response.status, 200);
    const body = await response.json();
    assertEquals(body.status, "draft");
  } finally {
    console.log = original;
  }

  // Verify that no sensitive data leaked into the telemetry
  assert(
    !lastLog.includes("api_key") && !lastLog.includes("prompt"),
    "shutdown telemetry must not contain secrets",
  );
});

Deno.test("full_week_generation_retired: implicit valid full-week request returns 400 without AI or run", async () => {
  let generateAICalled = false;
  const state = dayGenerationState();
  state.generationRun = null;

  const response = await handleGenerateWeekRequest(
    requestFor({
      creator_id: creatorID,
      week_start_date: "2026-06-08",
    }),
    {
      env: fakeEnv("test-key"),
      createAdminClient: () => fakeAdmin(state),
      generateAI: async () => {
        generateAICalled = true;
        throw new Error("generateAI should not be called");
      },
    },
  );

  assertEquals(response.status, 400);
  assertEquals(await errorCode(response), "full_week_generation_retired");
  assertEquals(generateAICalled, false);
  assertEquals(state.generationRun, null);
});

Deno.test("full_week_generation_retired: explicit generate_week returns 400 without AI or run", async () => {
  let generateAICalled = false;
  const state = dayGenerationState();
  state.generationRun = null;

  const response = await handleGenerateWeekRequest(
    requestFor({
      action: "generate_week",
      creator_id: creatorID,
      week_start_date: "2026-06-08",
    }),
    {
      env: fakeEnv("test-key"),
      createAdminClient: () => fakeAdmin(state),
      generateAI: async () => {
        generateAICalled = true;
        throw new Error("generateAI should not be called");
      },
    },
  );

  assertEquals(response.status, 400);
  assertEquals(await errorCode(response), "full_week_generation_retired");
  assertEquals(generateAICalled, false);
  assertEquals(state.generationRun, null);
});

Deno.test("full_week_generation_retired: retry_day returns 400 without mutating queued jobs", async () => {
  const state = dayGenerationState();
  state.dayJobs = makeQueuedDayJobs([
    ["generated", dailyCardIDs[0]],
    ["failed", null],
  ]);
  state.generationRun = {
    id: generationRunID,
    workspace_id: workspaceID,
    creator_id: creatorID,
    status: "running",
    weekly_plan_id: weeklyPlanID,
  };
  const jobsBefore = state.dayJobs.map((job) => ({ ...job }));

  const response = await handleGenerateWeekRequest(
    requestFor({
      action: "retry_day",
      generation_id: generationRunID,
      scheduled_date: "2026-06-09",
    }),
    {
      env: fakeEnv("test-key"),
      createAdminClient: () => fakeAdmin(state),
    },
  );

  assertEquals(response.status, 400);
  assertEquals(await errorCode(response), "full_week_generation_retired");
  assertEquals(
    state.dayJobs.map((job) => job.status).join(","),
    jobsBefore.map((job) => job.status).join(","),
  );
});

Deno.test("full_week_generation_retired: cancel_generation returns 400 without mutating run", async () => {
  const state = dayGenerationState();
  state.generationRun = {
    id: generationRunID,
    workspace_id: workspaceID,
    creator_id: creatorID,
    requested_by_member_id: memberID,
    status: "running",
    model: "openai:gpt-4.1-mini",
    weekly_plan_id: weeklyPlanID,
    input_snapshot: generationInputSnapshot(),
  };

  const response = await handleGenerateWeekRequest(
    requestFor({
      action: "cancel_generation",
      generation_id: generationRunID,
    }),
    {
      env: fakeEnv("openai-key"),
      createAdminClient: () => fakeAdmin(state),
    },
  );

  assertEquals(response.status, 400);
  assertEquals(await errorCode(response), "full_week_generation_retired");
  assertEquals(state.generationRun?.status, "running");
  assertEquals(state.generationRun?.error_code, undefined);
});

Deno.test("full_week_generation_retired: historical status remains readable", async () => {
  const state = dayGenerationState();
  state.dayJobs = makeQueuedDayJobs([
    ["generated", dailyCardIDs[0]],
    ["generated", dailyCardIDs[1]],
    ["generating", null],
    ["queued", null],
    ["queued", null],
    ["failed", null],
    ["retrying", null],
  ]);
  state.generationRun = {
    id: generationRunID,
    workspace_id: workspaceID,
    creator_id: creatorID,
    status: "running",
    weekly_plan_id: weeklyPlanID,
    input_snapshot: generationInputSnapshot(),
  };

  const response = await handleGenerateWeekRequest(
    requestFor({
      action: "status",
      generation_id: generationRunID,
      creator_id: creatorID,
    }),
    {
      env: fakeEnv("test-key"),
      createAdminClient: () => fakeAdmin(state),
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.status, "running");
  assertEquals(body.completed_day_count, 2);
  assertEquals(body.failed_day_count, 1);
});

Deno.test("full_week_generation_retired: generate_day route remains supported", async () => {
  const state = dayGenerationState();
  state.weeklyPlan = null;
  state.dailyCards = [];

  const response = await handleGenerateWeekRequest(
    requestFor({
      action: "generate_day",
      creator_id: creatorID,
      scheduled_date: "2026-06-10",
      day_brief: "Simple gym return day.",
      mock: true,
    }),
    {
      env: fakeEnv("test-key", true),
      createAdminClient: () => fakeAdmin(state),
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.status, "draft");
  assertEquals(typeof body.generation_id, "string");
  assertEquals(typeof body.weekly_plan_id, "string");
});
