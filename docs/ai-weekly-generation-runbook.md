# AI Weekly Generation Runbook

## Function contract

`generate-week` creates a draft week from live Supabase context and never
exposes AI credentials to the app.

Request:

```json
{
  "action": "generate_week",
  "creator_id": "uuid",
  "week_start_date": "YYYY-MM-DD",
  "weekly_setup_id": "uuid, optional",
  "mode": "generate_draft",
  "preserve_manual_edits": true,
  "mock": false,
  "input_overrides": {}
}
```

Per-day regeneration uses the same function and device-token boundary:

```json
{
  "action": "regenerate_day",
  "creator_id": "uuid",
  "weekly_plan_id": "uuid",
  "scheduled_date": "YYYY-MM-DD",
  "preserve_manual_edits": true
}
```

The response contains the replacement draft card for that date only. The
function rejects published weeks, cross-workspace plan IDs, and dates outside
the draft week.

Response:

```json
{
  "generation_id": "uuid",
  "weekly_plan_id": "uuid",
  "status": "draft",
  "strategy_summary": "string",
  "warnings": [],
  "assumptions": [],
  "daily_cards": [],
  "idea_bank": [],
  "source_summary": "string",
  "generated_at": "ISO-8601"
}
```

Async status polling:

```json
{
  "action": "status",
  "generation_id": "uuid",
  "creator_id": "uuid"
}
```

Running response:

```json
{
  "generation_id": "uuid",
  "weekly_plan_id": "uuid or null",
  "status": "running",
  "overall_status": "running",
  "strategy_created": true,
  "drafted_day_count": 4,
  "saved_day_count": 3,
  "failed_day_count": 1,
  "completed_day_count": 4,
  "total_day_count": 7,
  "current_day": "YYYY-MM-DD or null",
  "day_statuses": [
    {
      "scheduled_date": "YYYY-MM-DD",
      "day_index": 0,
      "status": "completed",
      "error_code": null,
      "daily_card_id": "uuid or null",
      "drafted": true,
      "saved": true,
      "attempt_count": 1,
      "started_at": "ISO-8601 or null",
      "completed_at": "ISO-8601 or null"
    }
  ],
  "poll_after_seconds": 5
}
```

Compatibility notes:

- Existing clients can continue using `status`, `completed_day_count`,
  `total_day_count`, and `current_day`.
- New clients should prefer `overall_status`, `drafted_day_count`,
  `saved_day_count`, `failed_day_count`, and `day_statuses`.
- `overall_status` is `completed` when all seven days are usable, `partial` when
  at least one day is usable and at least one day failed, and `failed` only when
  zero usable days exist. In-progress runs return `running`.
- `drafted_day_count` counts days with validated generated output or a saved
  card reference. `saved_day_count` counts days with a persisted
  `daily_card_id`.
- `strategy_created` is true once the lightweight week strategy has been saved
  into the generation snapshot. Older sequential snapshots may report false
  until the parallel strategy path is used.
- Completed draft responses still include the original `status: "draft"` and
  draft payload fields, with the generation status fields added alongside them.

Auth rules:

- Send only the Supabase publishable key from the app.
- Send `x-mco-device-token` with the paired device token.
- In the current app this token is issued after approved-email OTP sign-in by
  `exchange-auth-session`; testers do not manually enter pairing codes.
- Owner and editor roles may generate.
- Creator role is rejected.
- The Edge Function validates workspace ownership for creator, setup, and weekly
  plan IDs.
- Existing published weeks are locked against accidental regeneration.

Stable errors include `missing_device_token`, `invalid_device_token`,
`role_not_allowed`, `creator_not_found`, `invalid_generation_payload`,
`missing_openai_api_key`, `openai_request_failed`, `invalid_ai_json`,
`invalid_generated_week`, `generation_persist_failed`, `weekly_setup_not_found`,
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
  `90000`; values below `5000` are ignored and values above `180000` are capped.
- `MCO_GENERATION_DAY_STALE_MS`: optional async per-day stale retry window.
  Default: `120000`; values below `30000` are ignored and values above `600000`
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
4. Call `generate-week` with the local publishable key and `x-mco-device-token`.
5. Confirm one draft `weekly_plans` row and exactly seven draft `daily_cards`.
6. Confirm rich fields such as `script`, `caption`, and `backup_story` are
   present.
7. Confirm `read-content` weekly returns the draft for Manager review.
8. Publish with `publish-week` using `weekly_plan_id`.
9. Confirm `read-content` today returns the published generated card.
10. Confirm a Creator decision still writes through `write-content`.

The local acceptance script covers this end to end, including
regenerate-preserves-manual-edits:

```sh
SUPABASE_URL=http://127.0.0.1:54321 \
FUNCTIONS_URL=http://127.0.0.1:54321/functions/v1 \
MCO_SUPABASE_PUBLISHABLE_KEY=<local-publishable-key> \
SUPABASE_SERVICE_ROLE_KEY=<local-service-role-key> \
deno run --allow-all supabase/functions/generate-week/acceptance.ts
```

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
5. Switch to Manager Control, open Weekly, generate or review the draft, expand
   `Full generated card`, and publish only after review.

The debug paired environment intentionally takes precedence over any stored
keychain pairing so local simulator proof is deterministic.

## Real AI smoke

1. Confirm `DEEPSEEK_API_KEY` exists as the primary Supabase Edge Function
   secret.
2. Optionally confirm `OPENAI_API_KEY` exists as fallback without printing it.
3. Run one `generate-week` request without mock mode.
4. Inspect the seven cards for Creator-specific fit, no-go topic avoidance,
   practical shootability, valid week dates, and useful
   captions/scripts/backups.
5. If quality is weak, adjust the prompt/schema and rerun once.

For live or local hosted function smoke, use the guarded script:

```sh
MCO_SUPABASE_URL=https://<project-ref>.supabase.co \
MCO_SUPABASE_PUBLISHABLE_KEY=<publishable-key> \
MCO_LIVE_CREATOR_ID=<creator-id> \
MCO_LIVE_DEVICE_TOKEN=<owner-or-editor-device-token> \
MCO_LIVE_AI_WEEK_START_DATE=<safe-future-week-start> \
MCO_LIVE_AI_DRAFT_SMOKE=1 \
deno run --allow-env --allow-net scripts/ai-weekly-generation-smoke.ts
```

The script creates a draft only when `MCO_LIVE_AI_DRAFT_SMOKE=1` is set. It
publishes only when `MCO_LIVE_AI_PUBLISH_SMOKE=1` is also set.

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
5. Smoke `generate-week` with an owner/editor token using
   `scripts/ai-weekly-generation-smoke.ts`, or set `RUN_LIVE_AI_SMOKE=1` when
   running the deploy script.
6. Prefer a future week or test workspace. Do not publish Creator's real current
   week without explicit approval.

## Rollback or disable

- Unset `DEEPSEEK_API_KEY` and `OPENAI_API_KEY` to stop real generation.
- Disable the Generate button through app config if needed.
- Leave existing fixture runtime and legacy `publish-week` caller-supplied
  payload behavior available.
- Existing published weeks remain soft locked.
