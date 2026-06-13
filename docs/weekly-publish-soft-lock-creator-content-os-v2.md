# Weekly Publish and Soft-Lock Contract: Creator Content OS V2

This slice implements the Manager/Admin publish contract while preserving fixture runtime by default.

## Product Contract

Manager can publish the current weekly plan from Weekly Control.

Publishing:

- marks the weekly plan as soft-locked
- marks all seven weekly day rows as soft-locked
- creates a seven-card week package in app state
- updates Creator Today to the best matching published card
- keeps the no-paired-session app on fixture data

## Swift Boundary

Repository API:

- `WeeklyPlanRepository.publishWeek(_:ideaBank:context:)`
- result type: `WeeklyPublishResult`

Fixture implementation:

- soft-locks the in-memory weekly plan
- generates seven `DailyCard` values from the seven `WeeklyDay` values
- returns the matching Creator Today card

Supabase implementation:

- invokes the `publish-week` Edge Function
- uses the paired device token header supplied by `SupabaseClientFactory`
- locally reflects the published state after the function succeeds

## Edge Function

Server-side publish lives in:

- `supabase/functions/_shared/device-auth.ts`
- `supabase/functions/publish-week/index.ts`

`publish-week`:

1. verifies `x-mco-device-token`
2. requires member role `owner` or `editor`
3. verifies the creator belongs to the paired workspace
4. publishes or creates the weekly plan
5. replaces an existing published plan for the same creator/week if needed
6. upserts seven `daily_cards` by `weekly_plan_id, scheduled_date`
7. returns `weekly_plan_id`, `daily_card_count`, `is_soft_locked`, and `published_at`

## Acceptance Tests

Automated tests live in:

- `CreatorContentOSTests/PublishWeekFixtureAcceptanceTests.swift`

They verify:

- fixture week starts unlocked
- publishing soft-locks the week
- all seven days become soft-locked
- seven daily cards exist after publish
- Creator Today reads the published fixture card
- initial runtime falls back to fixtures when no paired session exists

## Next Slice

Build offline Today cache from the synced daily card:

- persist the latest daily card/week package locally
- load Creator Today from cache before network refresh
- keep fixture fallback behavior intact
