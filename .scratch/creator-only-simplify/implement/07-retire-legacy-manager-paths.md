# Retire legacy Manager, week soft-lock, and Testers paths

Status: resolved
Blocked by: 05, 06

Parent: [spec.md](../spec.md) · contract across all three seams

## What to build

Contract phase after the Creator-only path is live: remove or fully unreachable the old product surfaces so the app no longer behaves like a two-role system. Creators must not see Manager/Admin mode, week soft-lock / publish-week ceremony language, Testers allowlist UI, or AI Runway. Prefer delete or fully unreachable over a second mode left dangling. Week containers may still exist as storage if needed, but Creator-facing behavior must not require seven-day publish or soft-lock. This is the cleanup ticket that makes the destination feel Creator-only end-to-end — not a redesign of Plan or Today.

## Acceptance criteria

- [x] Manager/Admin shell is not reachable as a product mode from the primary Creator experience.
- [x] Week soft-lock / publish-week ceremony is not the Creator-facing way cards reach Today (language and controls retired from Creator UX).
- [x] Testers allowlist UI and approved-email OTP sign-in are not product paths.
- [x] AI Runway is not presented in the Creator product.
- [x] No owner/editor role gate blocks Plan/generate for Creator.
- [x] Spot-check / regression: Auth → Today → Plan → Available on Today → Shoot Folio still works after legacy removal.
- [x] Exact delete-vs-dead-code choice is documented in the PR/commit notes if anything is left unreachable rather than deleted.

## Blocked by

- [Plan hub: calendar, generate, Available, Unpublish](05-plan-hub.md)
- [Today empty journal card and Plan entry points](06-today-empty-and-plan-entries.md)

## Comments

## Answer

### Deleted vs DEBUG-only (contract choice)

**Product path (Release / live auth):** always `CreatorShellView`. `AppMode.admin` is ignored. Sign-in is Sign in with Apple only (`SignInView`). Plan uses per-day Available on Today — no soft-lock / Publish week language.

| Surface | Choice | Notes |
| --- | --- | --- |
| Live `activeMode` → Admin TabView switch | **Removed** from product routing | `CreatorContentOSAppView` live case is always Creator |
| Manager tools / Profile → Admin | **Already deleted** (ticket 04) | No product entry to set `.admin` |
| OTP / approved-email sign-in UI | **Already deleted** | `SignInView` is Apple-only |
| `AdminShellView` (Daily / Weekly / References) | **DEBUG-only** | `MCO_FORCE_FIXTURE_UI=1` + `MCO_FORCE_APP_MODE=admin` (or `MCO_FORCE_SCREEN=admin`) |
| `WeeklyControlView` + Publish week / soft-lock | **DEBUG-only** (via Admin Weekly tab) | Storage/`publishWeek` RPC kept under Admin/services |
| `AIRunwayView` | **DEBUG-only** | `MCO_FORCE_SCREEN=ai-runway` |
| `TesterAccessView` | **DEBUG-only** | `MCO_FORCE_SCREEN=tester-access`; tester invite/OTP service APIs remain for that screen |
| `DayGenerationView` | **DEBUG Admin Daily wrapper** | Creator Plan uses `PlanHubView` directly |
| `AppMode.admin` | **Kept** | Only for DEBUG fixture Admin routing + tests; activate/sign-out always reset to `.creator` |
| Week containers / `is_soft_locked` columns | **Kept as storage** | Not Creator-facing |

### Role gate
- Verified: `AppServices.canGenerateContent` allows `owner` \| `editor` \| `creator`; Plan generate uses it.

### How to verify
1. `xcodegen generate`
2. `xcodebuild test -scheme CreatorContentOS -destination 'platform=iOS Simulator,id=<sim>' -only-testing:CreatorContentOSTests/AuthenticationRuntimeTests/testRestoreForcesCreatorModeEvenWhenStartedAsAdmin -only-testing:CreatorContentOSTests/CreatorShellNavigationTests`
3. Manual: Sign in with Apple → Today → Profile → Plan → Generate → Available on Today → Shoot Folio. Confirm no Admin tabs, no Publish week, no Testers, no AI Runway.
4. Optional DEBUG: `MCO_FORCE_FIXTURE_UI=1 MCO_FORCE_APP_MODE=admin` still opens Admin Weekly for fixture QA.
