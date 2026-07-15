# Pivot brief: day-at-a-time generation (2026-07-05)

## Decision

Full-week parallel generation is **paused**, not deleted. The app's generation
capability going forward is **one day at a time**: the user can generate a
content card for today, tomorrow, or the day after; the app keeps track of
which dates have generated content and surfaces that day's card on that day.

## Where the old work lives

- Branch **`archive/full-week-parallel-generation`** (tip `f10c820`, on top of
  `codex/quality-validation-loop` @ `7cdb91c`). Contains the final state of the
  reliability effort: 120s day timeout default, worker-lifetime gating
  (`worker_lifetime_exhausted`), Tuesday weekday-name guard, and
  `failDayJob` error-message persistence. The commit message lists the open
  defects with evidence pointers.
- Gate evidence: `build-logs/opencode-generation-reliability/`
  (`live-fallback-gate-timeout120-20260704`, `live-regen-day-tuesday-20260705`,
  `live-tuesday-guard-gate-20260705`).
- Root-cause analysis: `docs/generation-timeout-2026-11-27-root-cause.md`.

## Live project state (zogvvrxhiwozjmufvddu) as of the pause

- `generate-week` deployed from the archive-branch tree (includes all fixes).
- Migrations applied through `20260704112000_enforce_parallel_day_job_lane_cap`.
- Secrets: `MCO_AI_DAY_REQUEST_TIMEOUT_MS=120000`,
  `MCO_GENERATION_DAY_STALE_MS=270000`.
- A harness worker device token exists (`device_installations` row
  `66f01ea1-c6e9-450d-8726-e42f183a5214`, name `reliability-gate-worker`) —
  revoke when live testing is over.

## Product shape going forward

- Generate exactly one daily card per request, for an explicit target date
  (today / tomorrow / day after; no further ahead until decided otherwise).
- The app records which dates have a generated card and shows the card on its
  date. No week-level generation runs, no 7-day fan-out, no parallel lanes.
- Weekly setup / creator profile inputs stay as prompt context; the weekly
  *generation* concept goes away from the UX.

## What to reuse (all already in the codebase)

- The day-scoped provider path: `callAIProvidersForDay`, day prompt builders,
  day validators (`parseGeneratedDayJSON`, `assertNoConflictingWeekdayLanguage`
  etc.), and the repair-retry loop in `generation.ts`. One day per isolate
  fits comfortably: successful day calls run 68–130s against a ~400s worker
  lifetime and 120s request timeout — the whole reliability problem above
  existed only because seven of these were multiplexed across dying isolates.
- The regenerate-day lane (`regenerate_day` action) is the closest existing
  entry point; it currently requires an existing draft `weekly_plans` row —
  the main backend work is letting a single day be generated/stored without a
  full week draft (or auto-creating a thin week container per date).
- Single-attempt telemetry (`generation_ai_attempt` console logs) and the
  day-job leases can stay for the single-day path; they are harmless at n=1.

## Known validation flakiness to keep in mind (from the gate runs)

Even single-day generation retries on content validation (~1 in 3 days needs
attempt 2–3). Known recurring validation failures: "cta is required.",
placeholder `source_note` content. With one day per request this is a matter
of in-request repair retries (fast), not stale-window reclaim — but budget
2–3 provider attempts (~90s each) per generate tap in UX expectations.

## Implementation status (2026-07-05)

Day-at-a-time generation is implemented on `codex/quality-validation-loop`
(uncommitted at time of writing):

- **Backend**: new `generate_day` action in `generate-week`
  (`normalizeGenerateDayRequest` in `generation.ts`; `handleGenerateDayRequest`,
  `ensureDayPlanContainer`, `startPreparedDayGeneration` in `index.ts`). Takes
  `creator_id`, `scheduled_date` (today or any future date), and a required
  free-text `day_brief` (≤2000 chars; brand work and one-off asks go in here).
  Finds or creates a thin draft `weekly_plans` container for the containing
  Monday-anchored week — no migration needed — then reuses the single-day
  pipeline (DeepSeek `reasoning_effort: max`, day validators, repair retries,
  `daily_cards` persistence, sync + async/poll modes). Per product decision,
  the day brief **replaces** the stored weekly setup in the prompt input
  (`weekly_setup = { notes: day_brief }` + `day_guidance`), so it is the only
  brief the model anchors to. `MAX_DAY_GUIDANCE_LENGTH` raised 500 → 2000.
- **iOS**: new Daily tab (`Features/Daily/DayGenerationView.swift`) in the
  manager shell — quick chips for today/tomorrow/day-after plus a date picker
  for any future date, a day-brief composer, elapsed-time progress, and the
  result rendered with the existing storyboard + caption blocks
  (`GeneratedDayPlannedContent`). `AppServices.generateDayCard(scheduledDate:dayBrief:)`
  with `dayBriefGeneratedCards`/`generatingDayBriefDates`/`dayBriefGenerationErrors`
  state; `SupabaseGenerateDayRequest` DTO; repository method reuses the
  regenerate-day response decoding and polling.
- **Tests**: 5 new `generate_day` deno tests (validation, past-date, container
  reuse/create, brief-replaces-setup, async) — 176 backend tests green; 3 new
  Swift tests in `GenerateWeekTests` for the service method. Deploy of the
  updated `generate-week` function is still pending.

## Session note

This brief is the distilled hand-off. Start the day-at-a-time implementation
as a fresh session from `codex/quality-validation-loop` (or a new feature
branch off it); do not resume the full-week reliability thread.
