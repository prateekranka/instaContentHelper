# Day generation under 60 seconds

## Decision summary

This benchmark supports bounded storyboard concurrency as the preferred
architecture for the day-only `generate_day` path. With the same deterministic
text, validation, persistence, and five-visual workload, virtual p50/p95 total
time improved from 48.616/49.726 seconds for serial storyboard work to
37.755/38.699 seconds with two visual lanes. Three lanes measured 32.557/33.569
seconds in the same offline model.

These are offline architectural results, not live SLA proof. They do not measure
provider latency, network latency, rate limits, retries, Supabase, or device
behavior.

## Offline benchmark

Run the deterministic benchmark with:

```sh
deno task benchmark:day-generation-under-60
```

The run uses 20 deterministic samples and writes:

`build-logs/day-generation-under-60/day-generation-under-60-benchmark.json`

The fixture uses the production `makeMockGeneratedWeek`,
`validateGeneratedDayOutput`, `scoreGeneratedDayOutputQuality`, and the same
ordered bounded scheduler seam used by storyboard generation. The validator
normalizes the text card and does not retain the optional thumbnail asset field,
so the adapter reattaches five deterministic production-shaped assets with
`row_index` values `0...4`, `status=generated`, nonempty `prompt_hash`,
`storage_path`, `public_url`, `model`, `prompt_version`, and `generated_at`
fields before checking the complete daily-card contract. This keeps the
benchmark honest: a text-only, partial, duplicate-row, or incomplete-asset card
is not a successful sample. No provider, network, environment secret, prompt,
schema, or day-only product behavior is used or changed by the benchmark. The
artifact records the exact deterministic fake profile and the percentile
convention `linear_interpolation_n_minus_1_v1`.

### Explicit budget

| Stage                              | Budget |
| ---------------------------------- | -----: |
| Context                            |    1 s |
| Text + validation                  |   20 s |
| Persistence + finalization         |    2 s |
| Five visuals, serial critical path |   28 s |
| Margin                             |    9 s |
| Total                              |   60 s |

The fake delays stay within the stage budgets. Serial execution therefore has 51
seconds of modeled work before margin; bounded lanes shorten only the storyboard
critical path while still requiring all five visuals to complete.

### Measured artifact results

The JSON artifact contains per-sample rows and the following aggregate metrics.
`p50` and `p95` are virtual milliseconds converted to seconds here.

| Architecture          |      Text p50/p95 |   Visuals p50/p95 |     Total p50/p95 |            Expected thumbnails | Complete thumbnail sets | Day validation passes | Quality-score passes |
| --------------------- | ----------------: | ----------------: | ----------------: | -----------------------------: | ----------------------: | --------------------: | -------------------: |
| Serial storyboard     | 18.899 / 19.802 s | 26.995 / 27.317 s | 48.616 / 49.726 s | 5 generated/sample (100 total) |                   20/20 |                 20/20 |                20/20 |
| Bounded concurrency 2 | 18.899 / 19.802 s | 16.095 / 16.427 s | 37.755 / 38.699 s | 5 generated/sample (100 total) |                   20/20 |                 20/20 |                20/20 |
| Bounded concurrency 3 | 18.899 / 19.802 s | 10.864 / 11.080 s | 32.557 / 33.569 s | 5 generated/sample (100 total) |                   20/20 |                 20/20 |                20/20 |

The production quality score varied between 78 and 85; all samples passed the
benchmark threshold of 75. Bounded concurrency 2 is the only gated candidate; it
passes only when every sample has all five production-shaped thumbnails, the
full daily-card contract, validation and quality passes, p50 <= 45 seconds, and
p95 < 60 seconds. Concurrency 3 is optional comparison evidence. Serial
storyboard work is comparison-only and misses the modeled p50 target. The CLI
exits nonzero if the bounded-concurrency-2 candidate fails any gate.

## Later live 20-pair experiment

This checkout intentionally does not implement a live mode. The benchmark CLI
accepts only sample-count and output-path arguments and has no provider call
path. A later experiment must be separately approved and explicitly gated; it
must not be enabled by an unset or silently inferred environment variable.

### Pre-registered inputs

Prepare 20 fixed pairs, each with the same values on both sides:

- pair ID `01` through `20`;
- one fixed `creator_id` and one scheduled date per pair;
- one fixed day brief per pair, including its length and exact bytes;
- a hash of the complete generation-input snapshot used by both runs;
- the exact provider/model route, prompt version, response format, timeout, and
  retry policy;
- expected thumbnail count of five and quality threshold of 75.

Keep live configuration in the approved runner's secret store. If the existing
day-generation harness is used, its documented input names are
`MCO_SUPABASE_URL`, `MCO_SUPABASE_PUBLISHABLE_KEY`, `MCO_LIVE_CREATOR_ID`,
`MCO_LIVE_DEVICE_TOKEN`, and `MCO_LIVE_GENERATE_DATE`; report only presence or
non-sensitive run metadata, never values.

### Procedure

1. Obtain explicit approval for the live provider calls and use an isolated
   experiment run. Add an explicit `--live` plus an approval sentinel to that
   future runner; this offline script must remain offline.
2. For every pair, run the same day-only request once with serial storyboard
   scheduling and once with bounded concurrency 2. Keep the provider, prompt,
   input snapshot, timeout, and retry policy identical. Randomize which member
   runs first and record the order; do not publish either draft.
3. Capture request start/end and stage timestamps for context, text, validation,
   each of the five visual jobs, and persistence/finalization. Store one JSONL
   row per pair member without secrets or full auth headers.
4. For both outputs, run production `validateGeneratedDayOutput` and require the
   complete daily-card contract. Count all five thumbnail records, require
   unique row indexes `0...4`, `status=generated`, and nonempty storage/public
   fields; text-only and incomplete-thumbnail results are failures, not
   successful fast paths. Score with production `scoreGeneratedDayOutputQuality`
   and count scores >= 75.
5. Summarize each arm and the paired deltas with total/text/visual p50 and p95,
   expected and complete thumbnail counts, validation passes, and quality
   passes. Use a durable artifact such as
   `build-logs/day-generation-under-60/live-20-pair.jsonl` plus a summary JSON.
6. Treat the candidate as live-SLA evidence only if all 20 pairs preserve the
   complete contract and quality gate, p50 is <= 45 seconds, p95 is < 60 seconds
   including all five thumbnails, and no provider-error or retry-rate regression
   is hidden by excluding failed samples.

The live result must be reported separately from this artifact. Passing this
offline benchmark is useful for choosing the architecture, but it cannot
substitute for that controlled experiment.
