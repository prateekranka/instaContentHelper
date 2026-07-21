# Day lifecycle mutations: Unpublish, overwrite, edit-keeps-ready

Status: resolved
Blocked by: 02

Parent: [spec.md](../spec.md) · seam **Day package lifecycle**

## What to build

Complete the day package mutation matrix on top of ready packages. **Unpublish** (with confirmation) demotes a ready package to draft; if that day had a live **Decision**, Unpublish clears the live Decision but keeps **Archive** history. Regenerating a draft overwrites the previous draft without a ready-overwrite warning. Generating over a ready package — or after a Decision — requires warn + explicit **Overwrite**, yields a new draft (not a silent ready replace), clears any live Decision, and keeps Archive history. Light edit of a ready package keeps it ready; when that date is local today, Today refreshes with the edited content. Failed Unpublish / Generate / overwrite paths surface clear errors.

## Acceptance criteria

- [x] Unpublish on a ready day (with confirmation) returns that day to draft; if it was local today, Today becomes empty of that package.
- [x] Unpublish after a Decision clears the live Decision and retains Archive history.
- [x] Draft regenerate overwrites the previous draft without the ready-overwrite warning.
- [x] Generate on ready or after a Decision shows warn + explicit Overwrite; result is a new draft; live Decision clears if present; Archive history remains.
- [x] Light edit of a ready package keeps it ready; Today reflects edits when the date is local today.
- [x] Failed Unpublish / Generate / overwrite surfaces a clear error and does not leave an ambiguous state.
- [x] Tests cover the lifecycle matrix: Unpublish; overwrite-generate with confirmation; edit-keeps-ready; Decision + Unpublish (live cleared, Archive retained); Decision + overwrite-generate (same Decision rules).

## Blocked by

- [Available on Today: draft → ready package](02-available-on-today-ready-package.md)

## Comments

## Answer

**Server**
- RPC `public.unpublish_day(payload jsonb)` — migration `20260721130000_day_lifecycle_mutations.sql`
  - Demotes ready/decision statuses → `draft`; clears `decision_at` + `completed_by_member_id`
  - Does **not** delete `archive_entries` (history retained by `daily_card_id`)
- RPC `public.update_ready_day_package(payload jsonb)` — same migration
  - Light-edits package fields in place; **keeps** published-lifecycle status; ignores week soft-lock
- Edge `unpublish-day` → RPC; roles `owner` | `editor` | `creator`
- Edge `update-ready-day-package` → RPC; roles `owner` | `editor` | `creator`

**Client**
- `WeeklyPlanRepository.unpublishDay` / `updateReadyDayPackage` (Supabase + Fixture)
- `AppServices.unpublishDay(scheduledDate:)` — empties Today when date is local today
- `AppServices.updateReadyDayPackage(scheduledDate:package:)` — keeps ready; refreshes Today when local today
- `AppServices.generateDayCard(..., confirmOverwrite:)` — ready/decision requires `confirmOverwrite`; unpublishes first (clears live Decision, keeps Archive), then regenerates as draft
- **UI (Admin Daily / Plan):** `DayGenerationView`
  - Unpublish button + confirmation (`daily.unpublish`)
  - Overwrite confirmation before Generate on ready/decision days
  - Light edit caption save on ready packages (`daily.ready.edit.caption` / `daily.ready.edit.save`)

**Tests**
- Deno: `supabase/functions/unpublish-day/index_test.ts`, `supabase/functions/update-ready-day-package/index_test.ts`
- Swift: `CreatorContentOSTests/DayLifecycleTests.swift` (full matrix)
