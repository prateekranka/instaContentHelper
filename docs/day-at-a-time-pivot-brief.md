# Pivot brief: day-at-a-time generation (2026-07-05, updated 2026-07-16)

## Decision (settled)

**Day-wise generation is the product.** Users generate one daily card at a time from
an explicit daily brief and target date (today, tomorrow, day after, or another
chosen future date). The app records which dates have a generated card and shows
the card on its date.

Full-week parallel generation (seven-day fan-out, parallel lanes, week-level
generation runs) is **archived and removed** from the supported product surface.
Current clients do not expose or invoke it. Legacy compatibility handlers and
feature-flag code remain until the protected provider/API removal is reviewed;
they are not a path to resume. See `PRODUCT.md` for the current product register.

## Current shipped surface

- **Backend**: supported clients call the deployed `generate-week` Edge
  Function with the day actions `generate_day` and `regenerate_day`. Each
  request produces one daily card. Legacy batch handlers remain behind this
  endpoint until their provider/API removal receives explicit review. In the
  supported day-wise flow, `weekly_plans` is a thin Monday-anchored storage and
  publishing container, not the unit submitted for generation.
- **iOS**: the Daily tab (`Features/Daily/DayGenerationView.swift`) is the
  manager generation surface — date chips, day-brief composer, progress, and
  `GeneratedDayPlannedContent` rendering. `AppServices.generateDayCard` and
  `regenerateDayCard` call the day actions with sync/async polling.
- **Workers and harnesses**: `scripts/workers/generate-day-worker.ts` drains
  `weekly_generation_day_jobs` by calling `regenerate_day` on the hosted endpoint.
  `scripts/day-generation-reliability-experiment.ts` plans and measures
  `generate_day` / `regenerate_day` reliability in dry-run or gated live mode.
- **Compatibility contracts** (unchanged by naming cleanup): the deployed path
  `/functions/v1/generate-week` and env var `MCO_GENERATE_WEEK_FUNCTION_URL`
  remain the operational endpoint identifiers even though generation is
  day-scoped.

## Product shape

- Generate exactly one daily card per request for an explicit target date.
- Weekly setup / creator profile inputs stay as prompt context where relevant;
  the day brief is the primary anchor for `generate_day`.
- Each supported client request starts one day only: no week-level generation
  run or 7-day fan-out. The worker pool may process independent queued day jobs
  concurrently; that concurrency is not a batch request.

## What to reuse (already in the codebase)

- The day-scoped provider path: `callAIProvidersForDay`, day prompt builders,
  day validators (`parseGeneratedDayJSON`, `assertNoConflictingWeekdayLanguage`
  etc.), and the repair-retry loop in `generation.ts`. One day per isolate
  fits comfortably against worker lifetime and request timeout budgets.
- Single-attempt telemetry (`generation_ai_attempt` console logs) and day-job
  leases remain useful at n=1.

## Known validation flakiness (from gate runs)

Even single-day generation retries on content validation (~1 in 3 days needs
attempt 2–3). Known recurring validation failures: "cta is required.",
placeholder `source_note` content. With one day per request this is a matter
of in-request repair retries (fast), not stale-window reclaim — but budget
2–3 provider attempts (~90s each) per generate tap in UX expectations.

## Where the old full-week work lives (historical only)

Do **not** resume the full-week reliability thread. These pointers are for
forensics and regression archaeology only.

- Branch **`archive/full-week-parallel-generation`** (tip `f10c820`, on top of
  `codex/quality-validation-loop` @ `7cdb91c`). Contains the final state of the
  reliability effort: 120s day timeout default, worker-lifetime gating
  (`worker_lifetime_exhausted`), Tuesday weekday-name guard, and
  `failDayJob` error-message persistence.
- Gate evidence: `build-logs/opencode-generation-reliability/`
  (`live-fallback-gate-timeout120-20260704`, `live-regen-day-tuesday-20260705`,
  `live-tuesday-guard-gate-20260705`).
- Root-cause analysis: `docs/generation-timeout-2026-11-27-root-cause.md`.

The whole reliability problem above existed because seven day calls were
multiplexed across dying isolates. That architecture is not coming back.

## Live project notes (from the pause, 2026-07-05)

Historical snapshot from when full-week parallel was retired:

- `generate-week` deployed with day-path fixes from the archive-branch tree.
- Migrations applied through `20260704112000_enforce_parallel_day_job_lane_cap`.
- Secrets: `MCO_AI_DAY_REQUEST_TIMEOUT_MS=120000`,
  `MCO_GENERATION_DAY_STALE_MS=270000`.
- A harness worker device token existed (`device_installations` row
  `66f01ea1-c6e9-450d-8726-e42f183a5214`, name `reliability-gate-worker`) —
  revoke when live testing is over.
