# Available on Today: draft → ready package

Status: resolved
Blocked by: None

Parent: [spec.md](../spec.md) · seam **Day package lifecycle**

## What to build

A calendar date can be empty, a **draft**, or a **ready package**. The Creator can take one selected date’s draft and run **Available on Today**, which makes that day a ready package without requiring a seven-day week or week soft-lock ceremony. **Today** shows that package only when the date is the device’s local today; a future ready package does not appear on Today. On Available success for local today, navigation lands on Today showing the card. On failure, the Creator stays where they were and sees a clear error. Encoding of draft vs ready is chosen at implement time (week containers may remain as storage underneath) but must break the old coupling where Today only appears after week soft-lock / full-week publish.

This ticket is the expand + first migrate for day availability: new per-day ready behavior works beside (or without depending on) the old week soft-lock product path. Full Plan calendar chrome can wait for the Plan hub ticket; this slice needs enough UI to select a date and invoke Available on Today end-to-end.

## Acceptance criteria

- [x] A date with a draft can be made a ready package via Available on Today for that single day (no full-week requirement).
- [x] Today shows the ready package when that date is local today; otherwise Today does not show that package.
- [x] Future ready packages do not clutter Today.
- [x] Available on Today success for local today navigates to Today with that card visible.
- [x] Available on Today failure stays put and surfaces a clear error.
- [x] Week soft-lock / seven-day publish is not required for a card to reach Today.
- [x] Repository/Edge (or equivalent) tests lock draft → ready and Today visibility for local today.

## Blocked by

None — can start immediately.

## Comments

## Answer

**Encoding**
- Draft = `daily_cards.status = 'draft'`
- Ready package = `daily_cards.status = 'published'` (then any published-lifecycle status for Today: `published`, `in_decision`, `shot`, `posted`, `used_backup`, `saved_for_tomorrow`, `skipped_intentionally`)
- `weekly_plans` remains a storage container; `make_day_available` does **not** set `is_soft_locked` or require 7 days
- `read-content` `today` already filters by `scheduled_date` + published-lifecycle statuses (future ready packages never become `today_card`)

**Server**
- RPC `public.make_day_available(payload jsonb)` — migration `20260721120000_make_day_available.sql`
- Edge Function `make-day-available` → calls RPC; roles `owner` | `editor` | `creator`

**Client**
- `WeeklyPlanRepository.makeDayAvailable(scheduledDate:dailyCardID:context:)` (Supabase + Fixture)
- `AppServices.makeDayAvailable(scheduledDate:)` → returns `true` when date is local today (caller navigates)
- **UI button:** Admin → Daily Content (`DayGenerationView`) bottom bar — “Available on Today” next to Generate when the selected date has a draft result (`accessibilityIdentifier: daily.availableOnToday`). On success for local today: `appState.activeMode = .creator` (Creator shell defaults to Today tab). On failure: `lastMakeDayAvailableError` banner, stay on Daily.

**Tests**
- Deno: `supabase/functions/make-day-available/index_test.ts`
- Swift: `CreatorContentOSTests/DayAvailabilityTests.swift`
