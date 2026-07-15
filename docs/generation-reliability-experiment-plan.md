# Generation Reliability Experiment Plan

This document describes the experiment harness and the exact procedure for
running generation reliability and speed experiments against the hosted
`generate-week` Supabase Edge Function. The harness lives at
`scripts/generation-reliability-experiment.ts` and is dry-run-first: it can be
verified locally with no live Supabase or OpenAI calls.

Live 20+20 experiments require separate user approval after the harness and logs
are in place. This pass does **not** run live hosted experiments.

## Goal

Produce evidence-driven answers to:

1. How reliable is full-week generation over 20 attempts on the same inputs?
   (validation pass rate, failure modes, latency distribution)
2. How reliable is single-day regeneration over 20 attempts with a guidance
   string, and does the generated content actually adhere to the guidance?
3. What is the pre-publish vs post-publish quality delta, and what decision
   rules should gate future prompt/model/timeout optimization work?
4. Which single, measurable hypothesis should be tried next in a Karpathy-style
   autoresearch loop, using a scalar objective that rewards reliability,
   latency, creator-native quality, hard-gate safety, and guidance adherence
   instead of raw views or vibes?

## Harness overview

Single Deno TypeScript script, no external dependencies, matching the repo's
existing script conventions (`Deno.env`, `Deno.writeTextFile`, JSONL output).

```
deno run --allow-env --allow-read --allow-write \
  scripts/generation-reliability-experiment.ts --mode <mode> [flags]
```

Modes:

| Mode                  | Purpose                                                          |
| --------------------- | ---------------------------------------------------------------- |
| `plan-full-week`      | Plan/execute N full-week `generate_week` attempts.               |
| `plan-regenerate-day` | Plan/execute N `regenerate_day` attempts with a guidance string. |
| `plan-generate-day`   | Plan/execute N day-at-a-time `generate_day` attempts with a day brief (`--brief`). With `--optimize-brief`, runs the Karpathy-style loop: after every run, keep the brief if it set a new best objective, otherwise revert to the best-known brief, then append one targeted instruction for the weakest quality rubric category (one hypothesis per run; validation failures never mutate the brief). Live env: `MCO_SUPABASE_URL`, `MCO_SUPABASE_PUBLISHABLE_KEY`, `MCO_LIVE_CREATOR_ID`, `MCO_LIVE_DEVICE_TOKEN`, `MCO_LIVE_GENERATE_DATE`. |
| `summary`             | Compute summary stats from a results JSONL file.                 |
| `evaluate-guidance`   | Evaluate guidance adherence of generated content.                |

Flags:

| Flag                      | Applies to                 | Description                                                                                          |
| ------------------------- | -------------------------- | ---------------------------------------------------------------------------------------------------- |
| `--runs <n>`              | plan-*                     | Number of attempts (default 20).                                                                     |
| `--dry-run` / `--live`    | plan-*                     | Dry-run is default. `--live` requires approval gate.                                                 |
| `--guidance "<text>"`     | plan-regenerate-day        | Guidance string passed into each regenerate-day request. Required.                                   |
| `--output <path>`         | plan-*                     | Results JSONL path. Defaults under `build-logs/opencode-generation-reliability/experiment-harness/`. |
| `--outputs <path>`        | plan-*                     | Companion JSONL with generated content. Defaults to `<output>.outputs.jsonl`.                        |
| `--input <path>`          | summary, evaluate-guidance | Input JSONL path.                                                                                    |
| `--required-terms a,b,c`  | evaluate-guidance          | Terms that must appear in generated content.                                                         |
| `--forbidden-terms x,y`   | evaluate-guidance          | Terms that must not appear.                                                                          |
| `--target-sections s1,s2` | evaluate-guidance          | Section keys that must be present.                                                                   |
| `--seed <n>`              | plan-*                     | RNG seed for deterministic dry-run mocks (default 42).                                               |

### Dry-run mode (default, verifiable locally now)

No Supabase or OpenAI calls. Mock result rows are written with simulated
latency, validation status, failure codes, and mock generated content. This
exercises the JSONL writer, summary stats, and guidance evaluator end-to-end so
the full pipeline is verified before any live run.

### Live mode (implemented, approval-gated, NOT run this pass)

`--live` requires **both**:

- `EXPERIMENT_LIVE_APPROVED=1` env var (separate user approval; this pass never
  sets it).
- All required `MCO_LIVE_*` env vars set (see below). Values are never printed;
  only presence is reported.
- Deno `--allow-net` permission.

The live branch validates the approval flag and env-var presence, then posts to
the hosted `generate-week` Edge Function using the same app-facing device token
header convention (`Authorization`, `apikey`, `x-mco-device-token`). It requests
`response_mode: "async"`, polls `action: "status"` until the run reaches a
terminal state, and writes the final returned JSON into the companion outputs
file. It does **not** change the request structure used by the app, model,
prompt, schema, max tokens, Edge Function timeout, retry behavior, concurrency,
or temperature. The harness runs attempts **sequentially** with no added retries
and no added concurrency, so the Edge Function's own behavior is the only
behavior under measurement.

## Karpathy-style autoresearch adaptation

This plan uses the useful part of Andrej Karpathy's autoresearch pattern:
repeatable experiments, a fixed evaluation budget, a scalar objective, and a
ratchet rule that keeps only evidence-backed improvements. It does **not** allow
an autonomous agent to change production prompts, models, schemas, timeouts,
retries, or concurrency without explicit human review.

The loop for ContentHelper is:

1. **Baseline:** run the unchanged generator 20 full-week times and 20 guided
   regenerate-day times.
2. **Run autoresearch after every generation attempt:** after run 1, write one
   autoresearch observation; after run 2, write the second; continue through
   run 20. A 20-attempt weekly experiment produces 20 `*.autoresearch.jsonl`
   observations. A 20-attempt regenerate-day experiment also produces 20
   observations.
3. **Score each attempt immediately:** compute `autoresearch_objective_score`
   from validation + latency + weighted pre-publish quality + hard-gate status.
4. **Diagnose each attempt immediately:** inspect failure clusters from hosted
   `generation_lifecycle` and `generation_ai_attempt` logs: timeout, validation
   failure, hard-gate failure, weak quality category, weak guidance adherence,
   or post-publish delta.
5. **Propose one narrow candidate:** e.g. reference compaction, prompt ordering,
   guidance handling, output validation repair, or queue/retry behavior. The
   candidate must name the expected metric movement before it is implemented.
6. **Run the same budget again:** 20 full-week + 20 guided regenerate-day, again
   with one autoresearch observation after every generation attempt.
7. **Ratchet:** keep the candidate only if it improves the scalar objective and
   does not regress any blocking gate. Otherwise revert/abandon that candidate
   and log the result.

Autoresearch constraints:

- One candidate change per run.
- Same creator, same week window, same guidance string, same env unless the
  candidate explicitly tests one variable.
- No OpenAI request/prompt/model/schema/retry/concurrency change ships without
  the required before/after review.
- Hard-gate failures override quality scores.
- Post-publish Tier-1 metrics are used as the long-term objective; dry-run and
  pre-publish runs are only the fast inner loop.

## Result row schema (results JSONL)

Each line is one `ResultRow`:

| Field                          | Description                                                                                                         |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| `run_index`                    | 1-based attempt index.                                                                                              |
| `experiment`                   | `full-week` or `regenerate-day`.                                                                                    |
| `started_at` / `finished_at`   | ISO-8601 timestamps.                                                                                                |
| `mode`                         | `dry-run` or `live`.                                                                                                |
| `planned`                      | true = call was planned.                                                                                            |
| `executed`                     | true = live call actually made (false in dry-run).                                                                  |
| `provider`                     | `mock` (dry-run) or `supabase-edge-function` (live).                                                                |
| `model`                        | `managed-by-edge-function` (not changed by harness).                                                                |
| `function_name`                | `generate-week`.                                                                                                    |
| `action`                       | `generate_week` or `regenerate_day`.                                                                                |
| `creator_id_present`           | Boolean — whether env var was set. Never the value.                                                                 |
| `week_start_date`              | Date used (not secret).                                                                                             |
| `scheduled_date`               | Date for regenerate-day (null for full-week).                                                                       |
| `weekly_plan_id_present`       | Boolean — whether env var was set. Never the value.                                                                 |
| `guidance`                     | Guidance string (for regenerate-day; null otherwise).                                                               |
| `request_payload_shape`        | Shape of the request contract (not the token).                                                                      |
| `http_status`                  | HTTP status from the live call (null in dry-run).                                                                   |
| `duration_ms`                  | Wall-clock duration of the attempt.                                                                                 |
| `timed_out`                    | Whether the attempt timed out.                                                                                      |
| `validation_passed`            | Whether the response validated against the day/week schema.                                                         |
| `failure_code`                 | `timeout`, `validation_failed`, `http_<n>`, or empty.                                                               |
| `quality_version`              | Version of the pre-publish rubric, currently `creator_pre_publish_quality_v1`.                                      |
| `quality_score`                | 0-100 quality score (see Metrics).                                                                                  |
| `quality_breakdown`            | Weighted category scores and explanations for the seven-category pre-publish rubric.                                |
| `hard_gate_blocking_failures`  | Blocking safety/brand/platform gate failures. Any value >0 means do not recommend.                                  |
| `hard_gate_warnings`           | Non-blocking warnings for issues that should be fixed or monitored.                                                 |
| `guidance_adherence_score`     | 0-100 adherence score (filled by evaluator; null until then).                                                       |
| `autoresearch_objective_score` | Scalar objective for comparing experiment candidates.                                                               |
| `autoresearch_decision`        | `observe_baseline` or `reject_failure`; candidate keep/reject decisions happen in the follow-up optimization brief. |
| `notes`                        | Free-text note.                                                                                                     |

The companion `<output>.outputs.jsonl` holds one `OutputRow` per run with
`run_index`, `experiment`, and `generated_content` (the raw generated JSON for
evaluator input).

The companion `<output>.autoresearch.jsonl` holds one `AutoresearchObservation`
per generation attempt. This is written inside the attempt loop, immediately
after the corresponding generation result row is written, not as a single
post-20-run analysis. Each observation includes:

- `run_index`
- `observed_after_generation: true`
- current objective score
- previous best objective score
- whether the attempt improved over the previous best
- diagnosis
- failure cluster
- weakest quality category
- suggested next probe
- `allowed_to_change_generation_behavior: false`

The observation can suggest what to inspect next, but it cannot change
generation behavior by itself. Prompt/model/request/retry/concurrency changes
still require the separate before/after review path.

## Env vars required for live mode (names only, never values)

These env var **names** are read by the harness. Values are never printed.

| Env var                        | Used by              | Notes                                                       |
| ------------------------------ | -------------------- | ----------------------------------------------------------- |
| `EXPERIMENT_LIVE_APPROVED`     | approval gate        | Must equal `1` for `--live` to proceed.                     |
| `MCO_SUPABASE_URL`             | both                 | Edge Function base URL.                                     |
| `MCO_SUPABASE_PUBLISHABLE_KEY` | both                 | Supabase publishable/anon key.                              |
| `MCO_LIVE_CREATOR_ID`          | both                 | Target creator UUID.                                        |
| `MCO_LIVE_DEVICE_TOKEN`        | both                 | Owner/editor device token. Treated as secret.               |
| `MCO_LIVE_AI_WEEK_START_DATE`  | both                 | Week start `YYYY-MM-DD`.                                    |
| `MCO_LIVE_AI_WEEKLY_SETUP_ID`  | full-week (optional) | Weekly setup UUID.                                          |
| `MCO_LIVE_WEEKLY_PLAN_ID`      | regenerate-day       | Draft weekly plan UUID to regenerate within.                |
| `MCO_LIVE_REGENERATE_DATE`     | regenerate-day       | `YYYY-MM-DD` of the day to regenerate.                      |
| `EXPERIMENT_EXPECTED_MODEL`    | optional             | Recorded for documentation only; does not change the model. |

## Metrics to collect

Per run:

- `duration_ms` (latency)
- `timed_out` (boolean)
- `validation_passed` (boolean — schema + required fields)
- `failure_code` (categorized)
- `http_status` (live only)
- `quality_score` (0-100, rubric below)
- `guidance_adherence_score` (0-100, regenerate-day only)

Aggregated (from `--mode summary`):

- total / executed / valid / failed counts
- failure rate
- latency: min, avg, p50, p90, p95, max
- quality: min, avg, p50, p90, max
- guidance adherence avg
- failure-code tally

### Pre-publish quality score rubric (0-100)

Use the existing creator learning-loop rubric and version:
`creator_pre_publish_quality_v1`. The weighted score is:

| Category                      | Weight | Checks                                                                                                |
| ----------------------------- | -----: | ----------------------------------------------------------------------------------------------------- |
| `opening_attention`           |     20 | first-frame clarity, first-3-sec hook, visual motion, curiosity gap, viewer identity match            |
| `retention_architecture`      |     15 | scene progression, pacing, payoff match, pattern breaks, rewatch/loop potential                       |
| `creator_voice_specificity`   |     15 | sounds like creator, lived detail, avoids generic AI phrasing, avoids off-brand slang, context anchor |
| `audience_goal_fit`           |     15 | clear target viewer, content job, pillar alignment, metric goal alignment, viewer pain/desire match   |
| `save_share_trigger`          |     15 | send reason, save reason, utility, non-forced CTA, social identity trigger                            |
| `accessibility_comprehension` |     10 | captions, silent-mode comprehension, readability, text density, jargon explained                      |
| `format_production_fit`       |     10 | duration, aspect ratio, audio strategy, scene variety, shootability                                   |

Recommendation thresholds:

- 85-100: strong, recommend shooting/posting if hard gates pass.
- 75-84: good, improve weakest category.
- 60-74: rewrite before shooting.
- below 60: weak fit or weak idea.
- any blocking hard gate: do not recommend, regardless of score.

Hard gates are separate from the weighted score:

- platform policy safe
- recommendation eligible
- original or transformative
- no third-party watermark
- no manipulative engagement bait
- brand safe
- creator voice not violated
- factual claims supported
- rights clear

The harness dry-run emits `quality_breakdown`, `quality_version`,
`hard_gate_blocking_failures`, and `hard_gate_warnings` so the JSONL schema
matches this rubric. Live scoring should prefer the hosted
`generation_ai_attempt.quality_metrics` plus the Swift
`ContentQualityLearningLoop` foundation rather than inventing a second quality
system.

### Guidance adherence score (0-100)

Computed by `--mode evaluate-guidance`:

- 50% weight: required terms present (all must appear).
- 30% weight: forbidden terms absent (none may appear).
- 20% weight: target sections present (e.g. `daily_card`, `shot_timeline`,
  `voiceover_timeline`).

`passed` is true only when all required terms are present AND no forbidden terms
appear.

## Pre-publish and post-publish quality metrics

The harness measures **pre-publish** quality: it generates draft weeks/days and
scores them before any publish mutation. Pre-publish metrics answer "can the
generator reliably produce valid, high-quality draft content on demand?"

**Post-publish** quality is measured separately by the existing
`scripts/ai-weekly-generation-smoke.ts` flow and the in-app quality loop, which
read back published weeks from Supabase and run the same schema validation +
quality rubric against the persisted (published) state.

How they are used together:

1. **Pre-publish regression gate.** A 20+20 live run must meet the reliability
   thresholds (see Decision rules) before any publish smoke is attempted. If
   pre-publish fails, do not publish.
2. **Post-publish delta.** After a publish smoke, re-score the published state.
   If post-publish quality drops more than 5 points below pre-publish avg, treat
   persistence as a suspect and inspect the publish path.
3. **Guidance adherence is pre-publish only.** Guidance is a generation-time
   input; it is not re-checked post-publish (the published card is whatever was
   drafted, possibly edited). Guidance adherence scores are compared across the
   20 regenerate-day attempts to decide whether guidance is reliably honored.

### Post-publish learning-loop rubric

Post-publish evaluation must not optimize only for views. It should use the
existing learning-loop model in
`CreatorContentOS/Models/ContentQualityLearningLoop.swift` and the passive
Supabase migration for:

- `PostPublishRawMetrics` with nullable API/manual/screenshot/mixed values.
- `DerivedMetricsCalculator` with null/zero-safe formulas.
- `PostPublishPerformanceScorer` with goal-specific weights.
- `CreatorBaselineService` with partial/insufficient confidence states.
- `LearningLoopAnalyzer` with the four outcome quadrants.

Tier-1 learning metrics:

1. `send_rate_by_reach`
2. `avg_watch_pct` / `completion_proxy`
3. `save_rate_by_reach`
4. `follow_rate_by_reach`
5. `non_follower_reach_rate`
6. `profile_to_follow_rate`
7. `story_completion_rate` / `story_exit_rate`
8. `comment_quality_score`

Derived metric rules:

- If denominator is null or zero, return null, not zero.
- Keep zero distinct from unknown.
- Do not fabricate sends when only shares are available.
- Use `view_frequency` for views/reach.
- Use `inferred_replay_rate` only when it is inferred from views and reach.
- Exclude paid/boosted posts from organic baselines unless explicitly requested.
- Preserve `metric_source` and `data_quality`.

Goal-specific scoring:

- Reach/discovery: prioritize send/share rate, watch, non-follower reach, follow
  conversion, and view frequency.
- Authority/education: prioritize save rate, watch, sends/shares, follows, and
  meaningful comments.
- Trust/story: prioritize completion/watch, meaningful comments/replies, profile
  visits, follows, and saves/shares.
- Brand/collab: prioritize retention, saves/shares, link/profile actions, brand
  fit, and sentiment.
- Community: prioritize meaningful comments/replies, social spread,
  completion/watch, profile visits, and follows.
- Link/sales: prioritize link taps, profile visits, retention, saves/shares, and
  follow/comment quality.

Outcome classification:

- `high_reach_high_quality`: winning format; repeat the structure.
- `high_reach_low_quality`: empty virality; do not copy blindly.
- `low_reach_high_quality`: good idea; weak packaging/distribution.
- `low_reach_low_quality`: weak idea or weak execution; drop or rethink.

The autoresearch outer loop should use post-publish signals only after the
content is actually published and measured. Until then, pre-publish quality/hard
gates are the fast proxy, not the final truth.

## Exact live experiment procedure

> **Approval required.** Live 20+20 experiments need explicit user approval
> after the harness and logs are in place. Do not proceed without it.

1. **Pick a safe target week.** Choose a future/test `week_start_date` and a
   draft `weekly_plan_id` that will not collide with real production content.
   Set `MCO_LIVE_AI_WEEK_START_DATE` accordingly.
2. **Set env vars (names only; do not echo values):**
   - `EXPERIMENT_LIVE_APPROVED=1`
   - `MCO_SUPABASE_URL`, `MCO_SUPABASE_PUBLISHABLE_KEY`
   - `MCO_LIVE_CREATOR_ID`, `MCO_LIVE_DEVICE_TOKEN`
   - `MCO_LIVE_AI_WEEK_START_DATE`
   - Optional: `MCO_LIVE_AI_WEEKLY_SETUP_ID`
   - For regenerate-day: `MCO_LIVE_WEEKLY_PLAN_ID`, `MCO_LIVE_REGENERATE_DATE`
   - Optional harness-only timeouts: `MCO_LIVE_REQUEST_TIMEOUT_MS` (default
     240000), `MCO_LIVE_POLL_TIMEOUT_MS` (default 1800000 for full weeks, 600000
     for regenerate-day)
3. **Confirm dry-run still passes** on the same `--runs 20` to ensure the
   harness itself is healthy before spending live calls:
   ```
   deno run --allow-env --allow-read --allow-write \
     scripts/generation-reliability-experiment.ts \
     --mode plan-full-week --runs 20 --dry-run \
     --output build-logs/opencode-generation-reliability/experiment-harness/full-week-dry-run.jsonl
   ```
4. **Run full-week 20** (live):
   ```
   deno run --allow-env --allow-read --allow-write --allow-net \
     scripts/generation-reliability-experiment.ts \
     --mode plan-full-week --runs 20 --live \
     --output build-logs/opencode-generation-reliability/experiment-harness/full-week-live.jsonl
   ```
5. **Run regenerate-day 20** (live) with a guidance string that names a concrete
   hook constraint, a required anchor, and a forbidden framing:
   ```
   deno run --allow-env --allow-read --allow-write --allow-net \
     scripts/generation-reliability-experiment.ts \
     --mode plan-regenerate-day --runs 20 --live \
     --guidance "Keep the hook under 2 seconds. Mention Bombay. Avoid weight-loss framing." \
     --output build-logs/opencode-generation-reliability/experiment-harness/regenerate-day-live.jsonl
   ```
6. **Summarize both:**
   ```
   deno run --allow-read --allow-write \
     scripts/generation-reliability-experiment.ts \
     --mode summary --input .../full-week-live.jsonl
   deno run --allow-read --allow-write \
     scripts/generation-reliability-experiment.ts \
     --mode summary --input .../regenerate-day-live.jsonl
   ```
7. **Evaluate guidance adherence** on the regenerate-day outputs:
   ```
   deno run --allow-read --allow-write \
     scripts/generation-reliability-experiment.ts \
     --mode evaluate-guidance \
     --input .../regenerate-day-live.jsonl.outputs.jsonl \
     --required-terms "Bombay,hook,voiceover_timeline" \
     --forbidden-terms "weight loss,guaranteed,lorem" \
     --target-sections "daily_card,shot_timeline,voiceover_timeline"
   ```
8. **Capture post-publish quality** separately using the existing weekly smoke +
   quality loop on the resulting draft/published state.
9. **Review per-attempt autoresearch observations** in:
   - `full-week-live.jsonl.autoresearch.jsonl`
   - `regenerate-day-live.jsonl.autoresearch.jsonl` Confirm there are exactly 20
     observations for each 20-run experiment and that each observation maps to
     the same `run_index` as a generation row.
10. **Archive** all JSONL + summary + guidance + autoresearch reports under
    `build-logs/opencode-generation-reliability/experiment-harness/` and
    reference them in the optimization decision (see below).

## Decision rules for future optimization work

Apply these after a live 20+20 run. All thresholds are over the 20-attempt
sample.

| Metric                                               | Gate                                            | Action if violated                                                                                                    |
| ---------------------------------------------------- | ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Full-week validation pass rate                       | >= 18/20 (90%)                                  | Investigate failure codes; do not optimize anything else until reliability is restored.                               |
| Full-week p90 latency                                | <= 60s                                          | If exceeded, profile the edge function (timeout/request structure are NOT to be changed by this harness).             |
| Full-week avg quality score                          | >= 75                                           | If below, run `scripts/ai-day-generation-prompt-benchmark.ts` to find a better prompt variant.                        |
| Blocking hard-gate failures                          | 0                                               | If any occur, fix gate cause before scoring quality or latency wins.                                                  |
| Autoresearch objective score                         | improves over baseline without gate regressions | Keep one candidate only if it improves the scalar objective and does not regress validation, hard gates, or guidance. |
| Regenerate-day validation pass rate                  | >= 18/20 (90%)                                  | Same as full-week.                                                                                                    |
| Regenerate-day guidance adherence avg                | >= 80                                           | If below, revise the guidance field UX and/or the prompt's guidance-handling section.                                 |
| Regenerate-day `passed` (all required, no forbidden) | >= 16/20 (80%)                                  | If below, the guidance contract is not reliable; do not ship guidance-dependent features.                             |
| Pre-publish vs post-publish quality delta            | <= 5 points                                     | If larger, inspect the publish/persistence path before further generation work.                                       |

If any gate is violated, the next step is **diagnosis, not tuning**. Do not
change the model, prompt, schema, max tokens, timeout, retry, concurrency, or
temperature until the failure mode is identified and a targeted fix is proposed
in a separate brief.

## Files

- `scripts/generation-reliability-experiment.ts` — the harness.
- `docs/generation-reliability-experiment-plan.md` — this doc.
- `build-logs/opencode-generation-reliability/experiment-harness/opencode-status.md`
  — status backchannel.
- `build-logs/opencode-generation-reliability/experiment-harness/brief.md` — the
  originating brief.
