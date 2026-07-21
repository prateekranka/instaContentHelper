# Today empty journal card and Plan entry points

Status: resolved
Blocked by: 02, 04, 05

Parent: [spec.md](../spec.md) · seam **Creator shell** (consumes **Day package lifecycle**)

## What to build

Finish the Creator daily loop on Today. When there is no ready package for local today, Today shows the journal-card empty state (prototype variant B): headline “Nothing ready for today,” short body that nothing is ready yet, single CTA **Plan today’s content** → Plan; no overflow menu on empty Today. When a ready package exists, Today shows it; Shoot Folio (Scenes / Script / Caption / Audio), copy, mark shot/posted, and **Give me other ideas** → Decision stay available. With a card showing: Edit opens Plan on that date; `⋯` overflow contains **Plan only**. Morning local notification copy is **Get today’s content ready.** Offline cached Today still serves a ready package when the network fails. Instagram shoot/edit/post remains outside the app.

Empty-state visual source: `.scratch/creator-only-simplify/assets/07-empty-today-prototype.html` (variant B).

## Acceptance criteria

- [x] Empty Today (no ready package for local today) shows the journal card: “Nothing ready for today,” supporting body, CTA “Plan today’s content” → Plan; no `⋯` on empty Today.
- [x] Ready Today shows the package; Creator can open Shoot Folio, copy text, mark scenes shot / posted, and use Other ideas → Decision.
- [x] Edit on Today hero and Edit on Shoot Folio open Plan with that card’s date preselected.
- [x] When a card is showing, `⋯` contains Plan only (no other overflow items).
- [x] Local notification title/copy is “Get today’s content ready.”
- [x] Offline cached Today still presents a ready package when network fails.
- [x] UI tests (or highest existing UI seam) lock: empty CTA → Plan; Edit/`⋯` → Plan with date; ready card still reachable after Available on Today.

## Blocked by

- [Available on Today: draft → ready package](02-available-on-today-ready-package.md)
- [Creator-only shell: Today · Archive · Profile](04-creator-only-shell.md)
- [Plan hub: calendar, generate, Available, Unpublish](05-plan-hub.md)

## Comments

## Answer

### Empty Today (prototype B)
- Journal card headline **Nothing ready for today**
- Body: **There’s no ready package for this date yet. Open Plan to generate one and make it available on Today.**
- CTA **Plan today’s content** → `CreatorRoute.plan(selectedDate:)` for the missing date
- No `⋯` when `todayContentState` is not `.ready`

### Ready Today + Shoot Folio
- Hero → Shoot Folio; Other ideas → Decision; mark shot/posted; copy unchanged
- **Edit** (`today.edit` / `shootFolio.edit`) → Plan with that card’s `scheduledDate`
- **`⋯`** (`today.overflow` / `shootFolio.overflow`) → **Plan only** (Report issue removed)

### Date preselection
- `AppState.planSelectedDate` + `preparePlan(selecting:)` / `consumePlanSelectedDate()`
- `CreatorRoute.plan(selectedDate:)` carries the date into `PlanHubView(initialSelectedDate:)`
- Profile → Plan clears leftover Edit date and opens on local today

### Notification
- `TodayNotificationCopy.reminderTitle` = **Get today’s content ready.**

### Offline cache
- Unchanged fallback path; covered by `TodayPlanEntryTests` + existing persistence test

### Tests
- `CreatorContentOSTests/TodayPlanEntryTests.swift`
- Shell nav: `testPreparePlanSelectedDateForEditAndOverflowEntries`
- Notification title assertion updated in `PublishWeekFixtureAcceptanceTests`
