# Creator-only shell: Today · Archive · Profile

Status: resolved
Blocked by: 01

Parent: [spec.md](../spec.md) · seam **Creator shell**

## What to build

Once signed in, the Creator always lands in a Creator-only shell. Root tabs are **Today · Archive · Profile** (that order). There is no Manager/Admin mode switch in the primary experience. **Archive** is a peer tab of past Decisions. **Profile** shows Apple account identity, sign out, one entry into **Plan**, and light Supabase / Gemini status — not Creator Profile editing, not References, not nested Archive, not Manager tools. Generation and prep entry are available to Creator without an owner/editor role gate. Shoot Folio structure is left alone; this ticket owns shell composition and Profile/Archive placement.

## Acceptance criteria

- [x] Live app uses tabs Today · Archive · Profile in that order; no Manager/Admin mode as a primary product path.
- [x] Opening the app after sign-in lands on Today as the daily job surface.
- [x] Archive tab lists past Decisions (filters remain useful for “today” / history).
- [x] Profile shows Apple identity, sign out, one Plan entry, and light Supabase + Gemini status.
- [x] Profile does not host Creator Profile editor, References, nested Archive, or Manager tools.
- [x] Creator can reach Plan/generate capabilities without an owner/editor role gate.
- [x] UI-level coverage (or equivalent shell/navigation tests) locks tab order and Profile destinations; auth identity on Profile reflects the Apple session from ticket 01.

## Blocked by

- [Sign in with Apple activation](01-sign-in-with-apple-activation.md)

## Comments

## Answer

### Done
- **CreatorShellView** — Tabs **Today · Archive · Profile**; Archive uses existing `ArchiveView`/`ArchiveSection`; default tab remains Today.
- **Profile** — Apple identity (`authenticatedEmail` → `creatorDisplayName` → “Apple ID”), sign out, one **Plan** entry (`profile.plan` → `PlanHubPlaceholderView` → `DayGenerationView` titled Plan), light Supabase + Gemini status. Removed Creator Profile editor, Manager tools, nested Archive.
- **Empty Today** — CTA “Plan today’s content” pushes `CreatorRoute.plan` (no Manager Weekly / `activeMode = .admin`).
- **Role gate** — `AppServices.canGenerateContent` allows `owner` | `editor` | `creator`; `DayGenerationView` and generate/regenerate/storyboard client guards use it. Edge `generate-week` + storyboard thumbnail functions also allow `creator`.
- **Tests** — `CreatorShellNavigationTests` (tab order, Plan-only Profile destinations, creator generate); Installed UITests Archive tab path; Manager-from-Profile proofs XCTSkipped until ticket 07.

### How Plan is entered today
1. **Profile → Plan** (primary buried entry)
2. **Empty Today → “Plan today’s content”** (navigation push to the same Plan placeholder)

Both open `PlanHubPlaceholderView` wrapping `DayGenerationView` (full Plan calendar IA is ticket 05).

### How to verify
1. `deno test --allow-env supabase/functions/generate-week/index_test.ts --filter "allows creator role"`
2. `xcodegen generate`
3. `xcodebuild test -scheme CreatorContentOS -destination 'platform=iOS Simulator,id=<sim>' -only-testing:CreatorContentOSTests/CreatorShellNavigationTests`
4. Manual: sign in → land on Today; tabs Today · Archive · Profile; Profile shows Apple identity + Plan + status (no Manager tools); Plan opens day generation; Archive is its own tab.
