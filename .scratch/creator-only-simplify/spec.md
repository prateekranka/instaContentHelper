# Spec: Creator-only daily loop

Status: ready-for-agent

Source: wayfinder map `.scratch/creator-only-simplify/` (tickets 01–07 resolved) · glossary `CONTEXT.md`

## Problem Statement

The Creator opens ContentHelper to get Instagram content ready for today, but the product still behaves like a two-role system: Manager prep (Admin shell, week soft-lock publish, seven-day gates) sits in front of the daily shoot loop. Sign-in is approved-email OTP and allowlisted testers. Empty Today pushes toward Weekly/Manager instead of Plan. The Creator cannot treat prep as a buried path on the same phone they shoot from, and “published” means locking a whole week rather than making one day’s ready package available.

## Solution

Make ContentHelper a **Creator-only** Instagram app. Primary UI is **Today → Shoot Folio → Decision**, with **Archive** and **Profile** as peer tabs. Prep lives in a buried **Plan** hub (calendar, generate, light edit, Available on Today, Creator Profile, References). A calendar date is either empty, a **draft** (yellow), or a **ready package** (green). **Today** shows only today’s local ready package, or a journal-card empty state with one CTA into Plan. Auth is **Sign in with Apple** only, keeping Auth → exchange → device token, with auto-provisioned Creator and no allowlist. Instagram shoot/edit/post stays outside the app. Local notification copy becomes “Get today’s content ready.” Offline Today cache remains.

## User Stories

1. As a Creator, I want to open the app and land on Today, so that my daily job is immediately clear.
2. As a Creator, I want Today to show today’s ready package when one exists, so that I know what to shoot.
3. As a Creator, I want Today to show a single empty journal card when nothing is ready, so that I am not dumped into Manager/Weekly.
4. As a Creator, I want the empty-state CTA “Plan today’s content,” so that I can create today’s package in one tap.
5. As a Creator, I want empty Today to omit the overflow menu, so that there is only one job on that screen.
6. As a Creator, I want to open Shoot Folio from the Today hero, so that I can work the package in detail.
7. As a Creator, I want Shoot Folio tabs for Scenes, Script, Caption, and Audio unchanged, so that my muscle memory stays intact.
8. As a Creator, I want to copy package text from Shoot Folio, so that I can paste into Instagram.
9. As a Creator, I want to mark scenes shot and mark posted, so that I can record progress without leaving the app.
10. As a Creator, I want “Give me other ideas” on Today when a card is ready, so that I can pick a backup when I cannot shoot the primary.
11. As a Creator, I want backup choices (short story, caption-only, save, skip) to record a Decision, so that the day has a clear outcome.
12. As a Creator, I want an Archive tab of past Decisions, so that I can review what I did without opening Profile.
13. As a Creator, I want Profile for account, Plan entry, and light Supabase/Gemini status, so that support and prep entry stay out of the daily hero.
14. As a Creator, I want to sign out from Profile, so that I can clear the device session and return to Sign in with Apple.
15. As a Creator, I want tabs ordered Today · Archive · Profile, so that the daily job comes first.
16. As a Creator, I want to enter Plan from Profile, so that prep is always reachable.
17. As a Creator, I want to enter Plan from the empty Today CTA, so that prep starts where the gap is felt.
18. As a Creator, I want Today overflow `⋯` → Plan when a card is showing, so that I can plan further without a Plan tab.
19. As a Creator, I want that overflow menu to contain Plan only, so that it stays simple.
20. As a Creator, I want an Edit control on the Today hero that opens Plan on that date, so that I can change the package without hunting.
21. As a Creator, I want an Edit control on Shoot Folio that opens Plan on that date, so that edits start from the package I’m reading.
22. As a Creator, I want Plan to open with a calendar date control and legend, so that I can see draft vs ready at a glance.
23. As a Creator, I want green dots for ready packages, yellow for drafts, and no dot when empty, so that calendar state is obvious.
24. As a Creator, I want a legend explaining those colors, so that I do not guess.
25. As a Creator, I want a daily generation prompt under the calendar, so that I can brief the day I’m planning.
26. As a Creator, I want a Generate action for one selected date, so that I get a draft without planning a whole week.
27. As a Creator, I want regenerating a draft to overwrite the previous draft, so that I do not accumulate stale drafts.
28. As a Creator, I want a warning and explicit Overwrite when generating over a ready package, so that I do not destroy a ready day by accident.
29. As a Creator, I want overwrite-generate to leave a new draft (yellow), so that ready is never silently replaced.
30. As a Creator, I want the same warn + Overwrite when generating after a Decision, so that history-changing regenerates are deliberate.
31. As a Creator, I want light edit of a ready package in Plan to keep it ready, so that copy fixes do not force re-availability.
32. As a Creator, I want Available on Today for a single day, so that one card can reach the Creator loop without seven days ready.
33. As a Creator, I want Available on Today success to navigate to Today when that date is local today, so that success feels like the daily loop.
34. As a Creator, I want Available on Today to stay on Plan when it fails, so that I can fix and retry.
35. As a Creator, I want Unpublish on a ready day (with confirmation), so that I can pull a package back to draft.
36. As a Creator, I want Unpublish after a Decision to clear the live Decision but keep Archive history, so that I can restart the day without losing the record.
37. As a Creator, I want overwrite-generate after a Decision to clear the live Decision and keep Archive history, so that behavior matches Unpublish.
38. As a Creator, I want Today to show only the ready package for the device’s local today, so that future ready days do not clutter Today.
39. As a Creator, I want future ready packages to stay green on the Plan calendar, so that I can plan ahead.
40. As a Creator, I want Creator Profile fields under a collapsed Plan accordion, so that voice/pillars stay available without a primary tab.
41. As a Creator, I want References (import, needs-your-call, growth/library) under a collapsed Plan accordion, so that intelligence stays prep, not a second mode.
42. As a Creator, I want Plan accordions collapsed by default, so that generate stays the focus.
43. As a Creator, I want Sign in with Apple as the only sign-in, so that I never enter email OTP.
44. As a Creator, I want first Apple sign-in to auto-provision my Creator workspace, so that I am not blocked by an allowlist.
45. As a Creator, I want no “tester not approved” dead end, so that Apple sign-in is sufficient to enter.
46. As a Creator, I want Auth session → exchange → device token to remain after Apple, so that live Edge Functions keep working.
47. As a Creator, I want restore of a prior device session on launch when valid, so that I am not asked to sign in every cold start.
48. As a Creator, I want sign-out to revoke the device session and clear local Auth, so that the next person sees Sign in with Apple.
49. As a Creator, I want existing OTP accounts to use Apple without a special link-email product flow, so that the destination stays simple.
50. As a Creator, I want a morning local notification “Get today’s content ready,” so that I am nudged into the daily loop.
51. As a Creator, I want offline cached Today when network fails, so that a ready package still helps me shoot.
52. As a Creator, I want Instagram recording, editing, and publishing to stay outside the app, so that ContentHelper remains the prep and decision layer.
53. As a Creator, I want never to see Manager/Admin mode, week soft-lock language, Testers UI, or AI Runway, so that the product feels Creator-only.
54. As a Creator, I want generation and Plan actions available without an owner/editor role gate, so that Creator is enough.
55. As a returning Creator, I want decisions recorded in Archive filters as today, so that history remains useful.
56. As a Creator planning tomorrow, I want to select tomorrow on the Plan calendar, generate a draft, and make it a ready package, so that tomorrow morning Today already has content.
57. As a Creator, I want Edit from Today to preselect that card’s date in Plan, so that I do not re-find the day.
58. As a Creator, I want Supabase and Gemini status on Profile, so that I can tell if prep backends are reachable without opening debug screens.
59. As a Creator, I want Profile account to reflect my Apple identity, so that I know which account is signed in.
60. As a Creator, I want failed Available on Today / Unpublish / Generate to surface a clear error, so that I know what to do next.

## Implementation Decisions

### Seams (confirmed)

1. **Auth activation** — Sign in with Apple front door; Supabase Auth via native identity token; reuse exchange → device token; auto-provision Creator membership/workspace on first sign-in; remove allowlist gate and OTP UI; keep restore and sign-out/revoke behavior.
2. **Day package lifecycle** — Single lifecycle for a calendar date: draft ↔ ready package (Available on Today, Unpublish, overwrite-generate rules, light edit while ready); Today read + offline cache + notification trigger off ready package for local today; replace week soft-lock / seven-day publish ceremony as the product path to Today.
3. **Creator shell** — UI composition only: tabs Today · Archive · Profile; Plan hub; empty Today journal card; Edit and `⋯` → Plan; no Manager mode. Consumes seams 1–2.

### Auth

- Sign-in screen: ContentHelper brand + Sign in with Apple only.
- Pipeline: Apple → Auth session → exchange → Keychain device session (same dual-session model).
- Auto-provision Creator on first successful Apple Auth when no member exists; role is Creator only for destination UX.
- No in-app Testers allowlist UI; no pairing-code sign-in product path.
- No special OTP→Apple account-linking product; ops may rebind data later outside this spec.

### Day package lifecycle

- Per-date states: none / draft (yellow) / ready package (green).
- Available on Today: one selected date’s draft → ready; no full-week requirement; soft-lock language retired for Creators.
- Unpublish: ready → draft with confirmation; allowed after Decision; clears live Decision; keeps Archive history.
- Light edit on ready: stays ready; Today refreshes when that date is current.
- Generate on ready or after Decision: warn + explicit Overwrite → new draft; clears live Decision if any; keep Archive history.
- Draft regenerate: overwrite without ready-overwrite warning.
- Today: only ready package for device-local today; else empty journal card.
- Week containers may remain as storage underneath until encoding/migration is chosen at implement time; product behavior must not require seven-day publish or week soft-lock.
- Encoding of draft vs ready (schema/status mapping) is an implement-time decision constrained by research: Today today keys off published-lifecycle statuses; week soft-lock blocks regenerate/edit — those couplings must be broken to match this spec.

### Creator shell / Plan

- Remove Manager/Admin as a product mode from the primary experience.
- Plan vertical order: title → calendar+legend → prompt → Generate → result/light edit → Available on Today → collapsed Creator Profile accordion → collapsed References accordion.
- Calendar replaces Today/Tomorrow chips + picker as the date control.
- References content: existing intelligence surfaces relocated under Plan (import/detail as pushes).
- Creator Profile: existing fields relocated, not redesigned.
- Empty Today (prototype B): journal card; headline “Nothing ready for today”; body explaining no ready package yet; CTA “Plan today’s content.”
- Notification title/copy: “Get today’s content ready.”
- Keep offline Today cache and local notification plumbing as infrastructure.
- Shoot Folio structure out of redesign scope.
- Prefer deleting or fully unreachable Manager shell / Testers / AI Runway / week-publish UX over leaving a second mode; exact delete-vs-dead-code choice is implement-time under seam 3.

### Testing Decisions

- Good tests assert **external behavior** at the three seams (auth activation outcomes, day lifecycle transitions and Today visibility, shell navigation destinations) — not internal SwiftUI layout trees or private helpers.
- Prefer highest existing test seams: authentication runtime/session tests, repository/Edge contract tests for Today read and generate/publish-like writes, and UI tests only where they lock Creator-visible flows (sign-in, empty Today CTA → Plan, Available on Today → Today).
- Prior art: existing authentication runtime tests, Supabase/repository tests, and device/UI test targets already in the project; extend those styles rather than inventing a parallel harness.
- Cover critical lifecycle matrix: draft→ready→Today; Unpublish; overwrite-generate with confirmation; edit-keeps-ready; Decision + Unpublish clears live Decision but Archive retains history; empty Today when no ready for local today.
- Cover auth: Apple front-door success path (may stub Apple credential), auto-provision first launch, restore device session, sign-out clears live phase.
- Do not require screenshot-perfect Plan chrome tests for calendar styling fog items.

## Out of Scope

- Manager / Admin shell as a product mode
- Week soft-lock / publish-week ceremony as the Creator-facing way cards reach Today
- Testers UI redesign and approved-email OTP sign-in
- AI Runway
- Multi-creator workspace switching
- In-app Instagram recording, editing, or publishing
- Redesigning Shoot Folio’s Scenes / Script / Caption / Audio structure
- Exact Plan visual polish beyond the IA (calendar chrome details, accordion styling)
- Exact Unpublish / Overwrite confirmation microcopy (behavior locked; wording can be finalized at implement)
- Special OTP-user migration UX

## Further Notes

- Wayfinder decisions: `.scratch/creator-only-simplify/map.md` and linked issue answers 01–07.
- Research assets: publish/soft-lock data model; Sign in with Apple vs current auth.
- Empty Today prototype source: `.scratch/creator-only-simplify/assets/07-empty-today-prototype.html` (variant B won).
- Use `CONTEXT.md` terms throughout implementation and tickets: Creator, Today, Shoot Folio, Other ideas, Plan, Draft, Ready package, Available on Today, Unpublish, Decision, Archive, Profile, References, Creator Profile, Sign in with Apple.
- Implementation tickets: `.scratch/creator-only-simplify/implement/` (01–07). Work the frontier with `/implement`.
