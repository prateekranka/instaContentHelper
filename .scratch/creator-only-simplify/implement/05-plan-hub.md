# Plan hub: calendar, generate, Available, Unpublish

Status: resolved
Blocked by: 03, 04

Parent: [spec.md](../spec.md) · seam **Creator shell** (consumes **Day package lifecycle**)

## What to build

The buried **Plan** hub is the prep surface. Vertical order: title → calendar + legend → daily generation prompt → Generate for the selected date → result / light edit → Available on Today → Unpublish when green → collapsed **Creator Profile** accordion → collapsed **References** accordion (both collapsed by default). Calendar legend: green = ready package, yellow = draft, no dot = empty. Calendar replaces Today/Tomorrow chips + picker as the date control. Wiring uses the lifecycle mutations from earlier tickets. Profile → Plan is a working entry. Exact calendar chrome polish is out of scope; IA and behavior are not.

## Acceptance criteria

- [x] Plan opens from Profile with the locked vertical IA order; Profile and References accordions are collapsed by default.
- [x] Calendar shows green/yellow/none dots with a legend explaining ready vs draft vs empty.
- [x] Creator can select a date, enter a daily prompt, and Generate a draft for that one date.
- [x] Draft regenerate overwrites; ready / after-Decision generate uses the warn + Overwrite path from ticket 03.
- [x] Light edit in Plan on a ready package keeps it ready.
- [x] Available on Today and Unpublish are available on Plan and match lifecycle behavior (including success → Today when date is local today; failure stays on Plan with a clear error).
- [x] Creator Profile fields and References (import / needs-your-call / growth-library style surfaces) live under the collapsed Plan accordions — relocated, not redesigned.
- [x] No screenshot-perfect chrome tests required; behavior tests cover generate / Available / Unpublish / calendar state meanings.

## Blocked by

- [Day lifecycle mutations: Unpublish, overwrite, edit-keeps-ready](03-day-lifecycle-mutations.md)
- [Creator-only shell: Today · Archive · Profile](04-creator-only-shell.md)

## Comments

## Answer

### Done
- **`PlanHubView`** — real Plan hub replacing `PlanHubPlaceholderView` / DayGenerationView-as-Plan.
  - Vertical IA: title → calendar + legend → daily prompt → Generate (command bar) → result / light edit → Available on Today → Unpublish → collapsed Creator Profile → collapsed References.
  - Calendar: selectable dates (today+), green/yellow/none dots, legend (ready / draft / empty).
  - Overwrite confirmation on ready/decision Generate; light edit via `updateReadyDayPackage`; Available / Unpublish wired to lifecycle APIs.
  - Available success for local today: dismiss Plan + `AppState.requestCreatorTab(.today)`.
- **`CreatorProfileAdminView` / `IntelligenceHomeView`** — `.embedded` presentation for Plan accordions (relocated fields/shelves, standalone chrome kept for Admin).
- **`AppServices.dayPackage(for:)`** + **`PlanCalendarDayState`** for calendar / package lookup.
- **`DayGenerationView`** — thin Admin Daily wrapper around `PlanHubView` until ticket 07.
- **Tests** — `PlanHubTests` (calendar meanings, generate overwrite → draft, Available → Today signal, Unpublish → draft); shell nav covers pending Today tab.

### How to verify
1. `xcodegen generate`
2. `xcodebuild test -scheme CreatorContentOS -destination 'platform=iOS Simulator,id=<sim>' -only-testing:CreatorContentOSTests/PlanHubTests -only-testing:CreatorContentOSTests/CreatorShellNavigationTests`
3. Manual: Profile → Plan → calendar legend/dots → prompt → Generate → Available (local today lands on Today) / Unpublish with confirm → expand Creator Profile / References accordions (collapsed by default).
