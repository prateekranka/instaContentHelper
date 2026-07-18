# Day Generation Runbook

Operational guide for `generate_day`, `regenerate_day`, and async `status`
polling on the `generate-week` Edge Function. Weekly plan storage and publish
still use `weekly_plan_id` as the draft container for per-day cards.

## Function contract

`generate-week` handles day-at-a-time generation and never exposes AI
credentials to the app.

### Generate a new day

```json
{
  "action": "generate_day",
  "creator_id": "uuid",
  "scheduled_date": "YYYY-MM-DD",
  "day_brief": "string",
  "response_mode": "async",
  "client_context": {}
}
```

### Regenerate one day in an existing draft week

`weekly_plan_id` is required because draft daily cards are stored under the
weekly plan container.

```json
{
  "action": "regenerate_day",
  "creator_id": "uuid",
  "weekly_plan_id": "uuid",
  "scheduled_date": "YYYY-MM-DD",
  "preserve_manual_edits": true,
  "day_guidance": "string, optional",
  "response_mode": "async"
}
```

The response contains the replacement draft card for that date only. The
function rejects published weeks, cross-workspace plan IDs, and dates outside
the draft week.

### Single-day success response shape

```json
{
  "generation_id": "uuid",
  "weekly_plan_id": "uuid",
  "status": "draft",
  "daily_card": {},
  "warnings": [],
  "assumptions": []
}
```

### Async status polling

```json
{
  "action": "status",
  "generation_id": "uuid",
  "creator_id": "uuid"
}
```

Running response (day jobs may still report week-level counters when part of a
multi-day run):

```json
{
  "generation_id": "uuid",
  "weekly_plan_id": "uuid or null",
  "status": "running",
  "overall_status": "running",
  "current_day": "YYYY-MM-DD or null",
  "poll_after_seconds": 5
}
```

Terminal day statuses: `draft` or `completed` with a `daily_card` object.
Failures return `status: "failed"` and an `error` code.

Compatibility notes:

- Poll until `status` is terminal (`draft`, `completed`, `failed`, or
  `cancelled`).
- Use `poll_after_seconds` from each response; do not hammer the endpoint.
- `weekly_plan_id` in status responses links the day back to its draft week
  container when persistence has started.

Auth rules:

- Send only the Supabase publishable key from the app.
- Send `x-mco-device-token` with the paired device token.
- In the current app this token is issued after approved-email OTP sign-in by
  `exchange-auth-session`; testers do not manually enter pairing codes.
- Owner and editor roles may generate.
- Creator role is rejected.
- The Edge Function validates workspace ownership for creator and weekly plan
  IDs.
- Existing published weeks are locked against accidental regeneration.

Stable errors include `missing_device_token`, `invalid_device_token`,
`role_not_allowed`, `creator_not_found`, `invalid_generation_payload`,
`missing_openai_api_key`, `openai_request_failed`, `invalid_ai_json`,
`invalid_generated_day`, `generation_persist_failed`, `weekly_setup_not_found`,
and `existing_published_week_locked`. For compatibility,
`missing_openai_api_key` means no real AI provider secret is configured.

## Required secrets

Set these only in Supabase Edge Function secrets or local function env files:

- `DEEPSEEK_API_KEY`: primary real AI provider.
- `OPENAI_API_KEY`: fallback provider if DeepSeek fails or is not configured.
- `MCO_DEEPSEEK_MODEL`: optional DeepSeek model override. Default:
  `deepseek-v4-pro`.
- `MCO_DEEPSEEK_BASE_URL`: optional DeepSeek API base URL override. Default:
  `https://api.deepseek.com`.
- `MCO_OPENAI_MODEL`: optional OpenAI fallback model override. Default:
  `gpt-4.1-mini`.
- `MCO_AI_PROVIDER_ORDER`: optional comma-separated provider order. Default:
  `deepseek,openai`.
- `MCO_AI_REQUEST_TIMEOUT_MS`: optional provider request timeout. Default:
  `240000`; values below `5000` are ignored and values above `240000` are capped.
- `MCO_AI_DAY_REQUEST_TIMEOUT_MS`: optional day-generation request timeout.
  When unset, falls back to `MCO_AI_REQUEST_TIMEOUT_MS` (same default, min-valid,
  and cap).
- `MCO_GENERATION_DAY_STALE_MS`: optional async per-day stale retry window.
  Default: `135000`; values below `30000` are ignored and values above `600000`
  are capped.
- `MCO_AI_MOCK=1`: local deterministic mock mode.
- `MCO_ALLOW_AI_MOCK_REQUEST=1`: allows request-level `mock: true` for local/dev
  tests only.

Do not add DeepSeek or OpenAI keys to the iOS app, `Runtime.xcconfig`, Git, or
TestFlight build settings.

To add real provider keys after deploy, keep them in a local ignored env file
and pass that file to Supabase:

```sh
supabase secrets set --project-ref <project-ref> --env-file <provider-secrets.env>
```

`DEEPSEEK_API_KEY` is enough for real generation. Add `OPENAI_API_KEY` when you
want OpenAI to be available as the fallback provider.

## Local mock smoke

1. Start local Supabase:

   ```sh
   supabase status || supabase start
   supabase db push --local --include-all --yes
   ```

2. Serve functions with mock AI:

   ```sh
   printf 'MCO_AI_MOCK=1\n' > /tmp/mco-functions-local.env
   supabase functions serve --no-verify-jwt --env-file /tmp/mco-functions-local.env
   ```

   Supabase local serve provides its own `SUPABASE_URL` and
   `SUPABASE_SERVICE_ROLE_KEY`. Put `MCO_AI_MOCK=1` in the env file; do not rely
   on shell-prefixed env vars for local mock mode.

3. Pair an owner/editor device token through `pair-device`.
4. Call `generate-week` with `action: "generate_day"` or `regenerate_day` using
   the local publishable key and `x-mco-device-token`.
5. Poll `action: "status"` until the day reaches a terminal state.
6. Confirm the draft `daily_card` includes rich fields such as `script`,
   `caption`, and `backup_story`.
7. Confirm `read-content` returns the draft card for Manager review.
8. Publish the reviewed date with `publish-day` using its `daily_card_id`.
9. Confirm `read-content` today returns the published generated card.
10. Confirm a Creator decision still writes through `write-content`.

The local acceptance script covers regenerate-preserves-manual-edits and related
day paths:

```sh
SUPABASE_URL=http://127.0.0.1:54321 \
FUNCTIONS_URL=http://127.0.0.1:54321/functions/v1 \
MCO_SUPABASE_PUBLISHABLE_KEY=<local-publishable-key> \
SUPABASE_SERVICE_ROLE_KEY=<local-service-role-key> \
deno run --allow-all supabase/functions/generate-week/acceptance.ts
```

## Queued day worker

Day generation can be processed by durable per-day jobs instead of one long
Edge Function lifecycle. `scripts/workers/generate-day-worker.ts` runs a bounded
worker pool, defaults to four concurrent lanes, claims `queued` or `retrying`
`weekly_generation_day_jobs` rows, moves each owned row to `generating`, calls
day generation, then marks the row `generated` or `failed`.

The worker expects day jobs with these columns:

- `id`
- `generation_run_id`
- `workspace_id`
- `creator_id`
- `weekly_plan_id`
- `scheduled_date`
- `day_index`
- `status`
- `attempt_count`
- `daily_card_id`
- `error_code`
- `started_at`
- `completed_at`
- `created_at`
- `updated_at`

Claimable statuses are `queued` and `retrying`. Terminal statuses are
`generated`, `failed`, and `cancelled`.

Local dry-run, which selects one queued/retrying job without mutation:

```sh
SUPABASE_URL=http://127.0.0.1:54321 \
SUPABASE_SERVICE_ROLE_KEY=<local-service-role-key> \
deno run --allow-env --allow-net scripts/workers/generate-day-worker.ts --dry-run
```

Local bounded-pool execution against served functions:

```sh
SUPABASE_URL=http://127.0.0.1:54321 \
SUPABASE_SERVICE_ROLE_KEY=<local-service-role-key> \
MCO_GENERATE_WEEK_FUNCTION_URL=http://127.0.0.1:54321/functions/v1/generate-week \
MCO_WORKER_DEVICE_TOKEN=<owner-or-editor-device-token> \
MCO_DAY_WORKER_MOCK=1 \
deno run --allow-env --allow-net scripts/workers/generate-day-worker.ts --once --concurrency=4
```

Production bounded-pool execution:

```sh
SUPABASE_URL=https://<project-ref>.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=<service-role-key> \
MCO_GENERATE_WEEK_FUNCTION_URL=https://<project-ref>.supabase.co/functions/v1/generate-week \
MCO_WORKER_DEVICE_TOKEN=<owner-or-editor-device-token> \
deno run --allow-env --allow-net scripts/workers/generate-day-worker.ts --once --concurrency=4
```

Use `MCO_DAY_WORKER_CONCURRENCY=4` instead of `--concurrency=4` when the process
supervisor owns command arguments. Keep the cap at four until two live four-wide
runs are stable; after that the cap can be tuned without code changes. Use
`--run-id=<generation_run_id>` when a scheduler should drain only one generation
run.

Do not print or commit the service role key or worker device token. Run the
worker from a scheduler, queue runner, or process supervisor. Each invocation is
bounded by the concurrency cap and exits after no matching queued/retrying jobs
remain.

Current integration hook: the worker uses the existing `generate-week`
`regenerate_day` action with `response_mode: "sync"`. That endpoint still
requires `x-mco-device-token`, so production should either provide an
owner/editor worker device token or add a service-role-only internal
day-generation endpoint/helper in `generate-week/index.ts`. Until that hook is
added, `MCO_DAY_WORKER_STUB=1` can exercise the claim/terminal-failure path; it
marks the claimed row `failed` with `day_generation_endpoint_stubbed` and does
not create a daily card.

## Local simulator live-runtime smoke

Use this when validating the iOS app against local Supabase rather than
fixtures.

1. Build and install with XcodeBuildMCP `build_run_sim`.
2. Stop the app if it launched without the debug paired environment.
3. Relaunch with explicit simulator environment using XcodeBuildMCP
   `launch_app_sim(env:)`:

   - `MCO_SUPABASE_URL=http://127.0.0.1:54321`
   - `MCO_SUPABASE_PUBLISHABLE_KEY=<local-publishable-key>`
   - `MCO_DEBUG_PAIRED_WORKSPACE_ID=<workspace-id>`
   - `MCO_DEBUG_PAIRED_CREATOR_ID=<creator-id>`
   - `MCO_DEBUG_PAIRED_MEMBER_ID=<member-id>`
   - `MCO_DEBUG_PAIRED_DEVICE_INSTALLATION_ID=<installation-id>`
   - `MCO_DEBUG_PAIRED_DEVICE_TOKEN=<owner-or-editor-device-token>`
   - `MCO_DEBUG_PAIRED_MEMBER_ROLE=owner`

4. Open Profile and confirm it says `Live Supabase - Creator` with owner/editor
   access.
5. Switch to Manager Control, open Weekly, generate or review draft days, expand
   `Full generated card`, and publish only after review.

The debug paired environment intentionally takes precedence over any stored
keychain pairing so local simulator proof is deterministic.

## Reliability experiments

For structured 20-run dry-run or approval-gated live experiments, use
`scripts/day-generation-reliability-experiment.ts` and
`docs/day-generation-reliability-experiment-plan.md`. Dry-run is the default;
live runs require `EXPERIMENT_LIVE_APPROVED=1` and all `MCO_LIVE_*` env vars.

## Live deploy

1. Confirm the Supabase project is linked and you have deploy credentials.
2. Apply migrations.
3. Deploy:

   ```sh
   SUPABASE_PROJECT_REF=<project-ref> \
   SUPABASE_ACCESS_TOKEN=<access-token> \
   SUPABASE_SECRETS_ENV_FILE=<secrets-env-file> \
   scripts/deploy-live-supabase.sh
   ```

4. Set `DEEPSEEK_API_KEY` as the primary Supabase secret and `OPENAI_API_KEY` as
   fallback if available.
5. Smoke day generation with an owner/editor token using the reliability harness
   in dry-run first, then a single live `generate_day` or `regenerate_day` call
   when approved.
6. Prefer a future date or test workspace. Do not publish Creator's real current
   week without explicit approval.

## Rollback or disable

- Unset `DEEPSEEK_API_KEY` and `OPENAI_API_KEY` to stop real generation.
- Disable the Generate button through app config if needed.
- Keep existing fixture runtime available for offline UI development.
- Existing published daily cards remain readable in Today.

## Troubleshooting

| Symptom | Likely cause | Check |
| ------- | ------------ | ----- |
| `missing_device_token` | No `x-mco-device-token` header | Pair device; confirm header on request |
| `role_not_allowed` | Creator role token | Use owner/editor token |
| `existing_published_week_locked` | Regenerate on published week | Target a draft `weekly_plan_id` |
| `invalid_generated_day` | Schema validation failed | Inspect `generation_ai_attempt` logs |
| Status stuck on `running` | Provider timeout or queue backlog | Poll with `poll_after_seconds`; check `MCO_GENERATION_DAY_STALE_MS` |
| `poll_timeout` from harness | `MCO_LIVE_POLL_TIMEOUT_MS` exceeded | Increase timeout or inspect edge function lifecycle logs |
