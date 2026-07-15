# Root cause: 2026-11-27 `generation_timeout` (gate run f509df7a, week 2026-11-23)

Analysis of the failed three-run gate (run 1), harness artifacts in
`build-logs/opencode-generation-reliability/live-compact-repair-logged-ramp3-20260703-152909/`,
and the `generate-week` Edge Function on branch `codex/quality-validation-loop`.
No provider request behavior was changed by the patch below.

## Timeline of the failed day (2026-11-27, day index 4)

All timestamps UTC, from `full-week-live.jsonl.outputs.jsonl` `day_statuses`.

| Time | Event |
| --- | --- |
| 09:59:09.7 | Harness POST `generate_week` (async, parallel flag). HTTP 202, run isolate A starts the sliding-window loop, concurrency 4. |
| 09:59:13.7–14.2 | Wave 1 launched: days 0 (11-23), 1 (11-24), 2 (11-25), 3 (11-26) running. 4 running / 3 queued. |
| 10:00:31–10:00:39 | Days 3 and 0 complete (attempt 1). Days 4 (11-27) and 5 (11-28) launched. |
| 10:01:19 / 10:01:38 | Days 2 and 5 complete; day 6 (11-29) launched. Now 4 saved / 3 running (days 1, 4, 6). |
| 10:01:38 → 10:08:10 | **Silence.** The Supabase Edge Function runtime has a hard worker lifetime of approximately 400 seconds, after which an isolate is terminated regardless of in-flight state. Isolate A's death is **inferred** (not directly observed — no boot-ID telemetry was captured) from the absence of any `openai_request_failed` write for day 1 and the orphaned state of days 1, 4, and 6. Each orphan consumed 1 of the 2-attempt budget. |
| 10:08:10.3 | After the stale threshold was set to 240 s, a status poll's stale sweep requeued days 1, 4, 6 (`normalizeStaleRunningDays` → `staleDayFailure` → pending) and spawned resume loop B. All three restarted as attempt 2 (final attempt). |
| 10:09:18 / 10:09:55 | Days 6 and 1 complete (attempt 2, 68 s / 105 s — normal latency). |
| 10:12:11.5 | Day 4's attempt 2 hit 241,214 ms ≈ stale threshold. A poll sweep marked it stale; attempts (2) ≥ max (2) → terminal `failed` with `generation_timeout` (`staleDayFailure`, index.ts:3829). The still-live worker's own provider abort (240 s) would have fired ~1 s later and then tried the fallback provider — it never got the chance. |
| 10:12:12.4 | Run finalized `partial`: 6 saved / 1 failed. Harness total 782,704 ms, 124 polls. |

The error code proves the killer: `generation_timeout` is written **only** by the
stale sweep (index.ts:3829-3842). A worker-side provider timeout maps to
`openai_request_failed` (`stableGenerationError`, index.ts:5737).

## Root cause (three interacting defects)

1. **Staleness cannot distinguish a dead worker from a live slow one.**
   `isRunningDayStale` measured age from `started_at` only (index.ts:4328).
   With stale threshold = 240,000 ms exactly equal to the per-request AI
   timeout (`DEFAULT_AI_REQUEST_TIMEOUT_MS = 240_000`, generation.ts:248), any
   provider call that reaches its own timeout is *guaranteed* to be declared
   stale first (poll cadence 5 s; the worker's abort clock also starts ~1 s
   later after a cancellation-check DB read, index.ts:1995). Consequence: the
   provider-fallback chain in `callAIProvidersForDay` (generation.ts:2236)
   can begin after a provider timeout, but the stale sweep can terminally fail
   the day before that fallback completes. The Edge Function's hard worker
   lifetime also means a 240-second first request plus a fallback cannot be
   assumed to finish in the same isolate.

2. **Orphaned attempts burn the retry budget.** The initial invocation's
   isolate dies before a 7-day / concurrency-4 week finishes (needs 2 waves ≈
   4–5 min of wall clock; the runtime reclaimed it ~2.5 min in). The three
   in-flight day attempts died with it, yet each still counted as a full
   attempt. With `DEFAULT_DAY_GENERATION_MAX_ATTEMPTS = 2` (index.ts:306),
   2026-11-27 reached its final day-level attempt without enough recovery
   budget, and that attempt was killed at 240 s by defect 1.

3. **Last-writer-wins snapshot persistence.** `updateGenerationProgress`
   (index.ts:4286) blindly overwrites the whole `output_snapshot` with no
   version check or per-day merge; poll handlers and background loops race.
   Direct evidence it fires in practice: several final `day_statuses` in
   earlier runs carry Postgres-format `completed_at` timestamps
   (`…+00:00`, e.g. live-day-scoped 2026-11-09/13/14) — those completions were
   lost from the snapshot and re-derived from saved daily-card rows by
   `mergeSavedDailyCardsIntoProgress`. Not the proximate killer of 11-27, but
   it inflates attempt counts and can requeue already-completed work.

This is chronic, not a one-off. Same signature in every prior failed run:
`generation_timeout`, `attempt_count: 2`, duration ≈ stale threshold exactly
(241 s / 301 s / 602 s across live-ramp3, live-tuned-ramp3, live-day-scoped).
live-tuned-ramp3 also ended with a day stuck `running` forever after the
harness stopped polling — recovery is entirely poll-driven.

## Answers to the specific questions

- **Provider latency?** Contributing but not primary: successful day calls run
  68–130 s; the failing attempt exceeded 240 s once. A healthy retry/fallback
  path would have absorbed it.
- **Edge Function execution limits?** Yes — isolate A's death orphaned three
  attempts. This is expected platform behavior the design must tolerate, and
  the poll-driven resume mostly does; the attempt-budget accounting does not.
- **Stale-job handling?** Primary defect (see 1).
- **Duplicate workers / lease ownership?** No lease/claim exists anywhere in
  the parallel path; duplicate resume loops are possible between a qualifying
  poll and the resumed loop's first write. Not observed as the killer here.
- **Oversized input/output?** No. Compact prompts (~29.9 KB) were in effect;
  days that completed did so quickly.
- **Parsing / contract validation?** No — the day never returned output.
- **Persistence latency / races?** Real (defect 3) but secondary.
- **Retry budget / backoff?** Yes — budget of 2 consumed by an orphan +
  one stale-killed real attempt (defect 2).
- **Late provider response after stale/fail marking?** For attempt 1: no
  response could arrive (isolate dead). For attempt 2: the sweep failed the day
  at t≈241 s while the worker's request was still in flight; its response (or
  abort) landed after the terminal write and was discarded. Hosted
  `generation_ai_attempt` rows are needed to confirm whether the provider
  ultimately answered — see missing telemetry.

## Missing telemetry to fully prove the diagnosis

- Hosted `generation_ai_attempt` logs for f509df7a (no DB credentials/CLI in
  this environment): would show whether day 4's attempt-1 provider call was
  ever issued, and attempt 2's finish reason/latency.
- Isolate/boot ID in day worker logs — would directly prove isolate A's death
  window (currently inferred).
- Durable per-day heartbeat, lease, and boot identifiers (added by this patch)
  make worker ownership and liveness observable independently of snapshots.

## Ranked repair options

1. **Durable per-day leases, heartbeats, and staged output** *(implemented)*.
   Claims and stale reclaims use row locks; heartbeats and staging require the
   current lease and attempt. Generated output is staged durably before any
   daily-card write, so an expired worker cannot overwrite a newer owner.
2. **Fresh job-row reconciliation before finalization** *(implemented)*.
   Completion and failure summaries come from durable day jobs rather than an
   isolate's stale in-memory snapshot.
3. **Bounded stale reclaim** *(implemented)*. A stale job at the maximum
   attempt count becomes terminal `generation_timeout` instead of being
   reclaimed indefinitely.
4. **Lower the per-provider AI request timeout (e.g. 120 s) so two provider
   attempts fit inside one stale window.** Cheap, but this **changes provider
   request behavior** — requires explicit approval per project rules, and is
   unnecessary if option 1 works. Documented before/after would be:
   before: single fetch abort at 240,000 ms; after: abort at 120,000 ms,
   earlier fallback to second provider. **Not implemented.**
5. **Raise stale threshold above the total worker budget (~960 s).** Rejected:
   masks the defect, slows orphan recovery to 16+ min — exactly the "increase
   every timeout" non-fix.

## Implemented patch (narrow)

The patch replaces the unsafe whole-snapshot heartbeat mechanism with durable,
ownership-guarded per-day jobs using the existing `weekly_generation_day_jobs`
table.

### Changes

- **Migration** (`20260703160000_parallel_generation_day_job_leases.sql`):
  Added lease/boot identifiers and durable staged output to
  `weekly_generation_day_jobs`. Atomic claim, stale reclaim, and output-stage
  functions use `FOR UPDATE SKIP LOCKED` and lease/attempt guards. Queue RPCs
  are executable only by `service_role`.

- **Orchestration** (`index.ts`): The parallel week-generation lane now:
  - Creates durable day-job rows at start (previously only the queued lane did this).
  - Claims queued/retrying jobs atomically via the `claim_queued_day_job` RPC,
    receiving a unique `lease_token` per claim.
  - Heartbeats via a direct `UPDATE` on the day-job row guarded by both
    `lease_token` and `status = 'generating'` — a stale worker's heartbeat is
    silently rejected.
  - Stages validated output atomically using job ID, lease, attempt, and status
    before persisting a daily card. Polling can resume staged persistence after
    isolate termination.
  - Completes or fails a job via a row-returning guarded update. No-error with
    zero affected rows is not treated as ownership.
  - Stale reclaim uses the `reclaim_stale_day_job` RPC, which atomically
    increments `attempt_count` and assigns a new `lease_token`.

- **Snapshot separation**: Heartbeats never overwrite `output_snapshot`.
  Snapshot writes are compatibility summaries reconciled from fresh durable
  day-job rows before finalization.

- **Shutdown telemetry**: Structured `generation_shutdown` logs include
  generation, boot and hosted execution identifiers, runtime shutdown reason,
  active job IDs, and normal completion counters. No secrets, prompts,
  generated content, or tokens are logged.

- **Status polling staleness**: `readParallelGenerationStatus` now reads
  day-job row `heartbeat_at` values to determine which "running" days are
  truly stale, replacing the snapshot-only staleness check.

### Provider request behavior: unchanged.
No prompt, model, schema, timeout, retry, or concurrency change to any
OpenAI/DeepSeek request.

### Known residual risks

- **Supabase Edge Function hard limit of ~400s**: The hosted runtime may
  terminate an isolate mid-loop. The day-job lease model tolerates this
  (stale reclaim recovers), but a mid-request termination still burns an
  attempt. The 240s stale threshold is safe only if heartbeat interval ≤ 60s
  (which it is).
- **RPC dependency**: The atomic claim/reclaim/stage functions require the
  migration to be deployed before the new Edge Function code activates.
  Deploy the migration before the Edge Function; there is no unsafe fallback.
