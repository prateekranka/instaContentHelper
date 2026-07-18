# Live Supabase and TestFlight Runbook

Use this when the live Supabase project and credentials are available.

## 1. Deploy live Supabase

Required:

```sh
export SUPABASE_PROJECT_REF=your-project-ref
export SUPABASE_ACCESS_TOKEN=your-cli-access-token
export SUPABASE_DB_PASSWORD=your-remote-db-password
```

Verify the token can see the live project before deploying:

```sh
supabase projects list
supabase orgs list
```

If both commands return empty lists, the token was created from an account that has no visible Supabase organizations/projects. Create the token from the Supabase account that owns the live project, or invite this account into the project organization before retrying.

Use `SUPABASE_DB_URL=postgresql://...` instead of `SUPABASE_DB_PASSWORD` if you prefer pushing migrations by direct database URL.

Optional, if function secrets are stored in a local env file:

```sh
export SUPABASE_SECRETS_ENV_FILE=/path/to/live-function-secrets.env
```

Deploy migrations and all ContentHelper Edge Functions:

```sh
scripts/deploy-live-supabase.sh | tee build-logs/live_supabase_deploy_$(date +%Y%m%d_%H%M%S).log
```

The script deploys:

- `exchange-auth-session`
- `pair-device`
- `revoke-device-session`
- `send-auth-email`
- `manage-testers`
- `publish-day`
- `read-content`
- `write-content`
- `import-references`
- `review-reference`
- `generate-week`

All functions deploy with JWT verification disabled because the app uses the publishable key plus `x-mco-device-token`; the service role key stays inside Edge Functions.

## 2. Smoke live read/write boundary

Required for read-only smoke:

```sh
export MCO_SUPABASE_URL=https://your-project-ref.supabase.co
export MCO_SUPABASE_PUBLISHABLE_KEY=your-publishable-or-anon-key
export MCO_LIVE_CREATOR_ID=live-creator-creator-id
export MCO_LIVE_DEVICE_TOKEN=owner-or-editor-device-token
```

Run:

```sh
deno run --allow-env --allow-net scripts/live-write-boundary-smoke.ts
```

To also mutate live data through `write-content`, set:

```sh
export MCO_LIVE_WRITE_SMOKE=1
export MCO_LIVE_DAILY_CARD_ID=live-daily-card-id
export MCO_LIVE_DECISION_STATUS=saved_for_tomorrow
export MCO_LIVE_OUTPUT_LINE="Live smoke: write boundary decision"
```

To prove idea selection and creator-role rejection:

```sh
export MCO_LIVE_IDEA_ID=live-open-idea-id
export MCO_LIVE_WEEKLY_PLAN_ID=live-current-weekly-plan-id
export MCO_LIVE_CREATOR_ROLE_DEVICE_TOKEN=creator-role-device-token
```

## 3. Rebuild live-configured TestFlight

Release builds now fail unless live Supabase bootstrap config is supplied.

```sh
MCO_SUPABASE_URL=https://your-project-ref.supabase.co \
MCO_SUPABASE_PUBLISHABLE_KEY=your-publishable-or-anon-key \
xcodebuild archive \
  -project CreatorContentOS.xcodeproj \
  -scheme CreatorContentOS \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath build-logs/ContentHelper_Live.xcarchive \
  -jobs 1 \
  COMPILER_INDEX_STORE_ENABLE=NO \
  SWIFT_COMPILATION_MODE=wholemodule
```

Upload:

```sh
xcodebuild -exportArchive \
  -archivePath build-logs/ContentHelper_Live.xcarchive \
  -exportPath build-logs/testflight-live-upload \
  -exportOptionsPlist build-logs/ExportOptionsUpload.plist \
  -allowProvisioningUpdates \
  | tee build-logs/upload_testflight_live.log
```

After upload succeeds, pair Manager and Creator with fresh live invite codes and follow `docs/testflight-start-using-contenthelper.md`.
