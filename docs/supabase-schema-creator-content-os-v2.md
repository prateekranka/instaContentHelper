# Supabase Schema: Creator Content OS V2

This is the first backend slice for Creator Content OS V2. It creates the Supabase-ready data foundation and the initial no-auth device pairing path.

Migration:

- `supabase/migrations/20260605000000_initial_content_os_schema.sql`

Edge Function:

- `supabase/functions/pair-device/index.ts`

## Design Decisions

- Every product table is scoped by `workspace_id`; creator-owned tables also include `creator_id`.
- The V1 UI can stay bespoke to Creator while the data model supports multiple creators/workspaces later.
- IDs are `uuid` to match the Swift app's `UUID` models and avoid exposing sequential public IDs to paired devices.
- Product `Reference` is stored as `source_references` because `references` is a SQL keyword and would force quoted identifiers.
- Structured generated packages stay as `jsonb` where the app renders strict JSON: scene lists, backups, warnings, assumptions, profile rules, weekly setup context, extraction payloads, and performance snapshots.
- RLS is enabled and forced on public tables. Direct client access is intentionally conservative; Edge Functions/service role should handle device-paired writes in early production.
- Public schema usage and full table/function privileges are explicitly granted to `service_role` so local and deployed Edge Functions can perform privileged device-token operations even with `auto_expose_new_tables = false`.

## Core Tables

- Workspace/device layer: `workspaces`, `creators`, `members`, `device_invites`, `device_installations`.
- Profile and setup: `creator_profiles`, `weekly_setups`, `weekly_setup_sources`.
- Published planning loop: `weekly_plans`, `daily_cards`, `card_alternatives`, `archive_entries`.
- Source intelligence: `source_references`, `reference_extractions`, `watchlists`, `benchmark_creators`, `watchlist_benchmark_creators`, `patterns`, `pattern_references`, `trends`, `trend_references`, `audio_options`, `trend_audio_options`, `ideas`.
- Business/context: `brand_briefs`, `collab_leads`, `key_moments`.
- Learning/history: `feedback`, `learning_summaries`, `post_results`, `sync_events`.

## Access Model

V1 should not show login UI. The intended path is:

1. Manager creates a `device_invite`.
2. A phone pairs into a `member` role and stores a device token in Keychain.
3. Edge Functions verify the device token and role before privileged writes.
4. Supabase table RLS remains enabled; service role keys never ship in the iOS app.

Current RLS helpers:

- `public.is_workspace_member(workspace_id)`
- `public.member_has_workspace_role(workspace_id, allowed_roles)`

Role intent:

- `owner` / `editor`: prepare profile, references, intelligence, weekly setup, plans, cards, archive.
- `creator`: daily decisions and lightweight feedback.
- `scout`: add or update source references.

## Main Query Paths

- Creator Today: `daily_cards` by `creator_id + scheduled_date` where the card is published or completed.
- Manager Weekly Control: `weekly_plans` by `creator_id + week_start_date + status`, then `daily_cards` by `weekly_plan_id`.
- Trend Inbox: `source_references` by `creator_id + status + created_at`.
- Intelligence shelves: `patterns`, `trends`, `audio_options`, and `ideas` by `creator_id + status`.
- Archive: `archive_entries` by `creator_id + archive_date desc`.

## Validation

Local validation was run against a temporary Postgres database with a minimal mock `auth` schema:

- Tables created: 34
- RLS policies created: 126
- Indexes created: 143
- Missing foreign-key index columns: 0

The Supabase CLI and local Docker runtime are installed. Local validation now runs through `supabase start -x vector` and `supabase db reset` using Colima.

Latest local validation:

- Tables created: 34
- RLS policies created: 126
- Indexes created: 143
- `pair-device` Edge Function succeeded against the local stack.
- `publish-day` contract tests verify one selected daily card is published without rewriting its content fields.

## Next Slice

Build the Swift runtime/device boundary:

- Store paired runtime config in Keychain.
- Add a client pairing service.
- Add the initial `pair-device` Edge Function.
- Keep visible app views unchanged.
