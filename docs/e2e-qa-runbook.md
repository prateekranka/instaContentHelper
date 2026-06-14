# Live E2E QA Runbook

This suite validates the Creator Content OS live Supabase boundaries with an
isolated QA workspace. It does not use the production creator workspace.

## Script

Run:

```sh
MCO_SUPABASE_URL=https://zogvvrxhiwozjmufvddu.supabase.co \
MCO_SUPABASE_PUBLISHABLE_KEY=<publishable-key> \
MCO_SUPABASE_SERVICE_ROLE_KEY=<service-role-key> \
MCO_QA_WEEK_START_DATE=2026-07-06 \
deno run --allow-all scripts/qa/live-e2e-qa.ts
```

Optional:

```sh
MCO_QA_GENERATE_MOCK=1
```

Use mock mode only when the live `generate-week` function explicitly allows
request mock mode for QA.

Cleanup only:

```sh
MCO_QA_CLEANUP_ONLY=1 deno run --allow-all scripts/qa/live-e2e-qa.ts
```

## Admin Coverage

The script simulates the admin path through live Edge Functions:

1. Resets and seeds a dedicated QA workspace, creator, owner/editor/creator
   device sessions, creator profile, weekly setup, confirmed reference, and
   idea.
2. Reads creator profile and intelligence through `read-content`.
3. Calls `generate-week` for a future QA week.
4. Polls generation status until a draft week is available.
5. Verifies seven generated daily cards with rich fields.
6. Edits Weekly Brief through `write-content.update_weekly_setup`.
7. Imports and approves a QA reference through `import-references` and
   `review-reference`.
8. Regenerates one draft day through `generate-week` with
   `action: regenerate_day`.
9. Publishes the draft through `publish-week`, including an edited card payload.
10. Verifies published plan, cards, Weekly Brief edits, and reference
    persistence through `read-content`.

## Creator Coverage

The script validates the creator-side live data path:

1. Reads the published generated Today card through `read-content.today` using a
   creator-role device token.
2. Verifies script, caption, and scene list are present for Shoot Folio.
3. Writes a creator decision through `write-content.complete_today`.
4. Reads `read-content.archive` and verifies the decision appears in the
   embedded archive data.

Native UI navigation and scene-detail tap automation should be added as an Xcode
UI test target. The current script covers the live backend/data contracts those
screens depend on.

## Security And Boundary Coverage

The script asserts:

- Invalid device tokens are rejected.
- Creator role cannot call `generate-week`.
- Cross-workspace creator IDs are rejected.
- Published week lock blocks accidental regeneration.
- App-style calls use publishable key plus `x-mco-device-token`.

Service role is used only for QA setup, direct assertions, and cleanup.

## Evidence

Save each run under `build-logs`, for example:

```sh
LOG="build-logs/live-e2e-qa-$(date +%Y%m%d-%H%M%S).log"
deno run --allow-all scripts/qa/live-e2e-qa.ts 2>&1 | tee "$LOG"
```
