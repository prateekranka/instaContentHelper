# Retire legacy Manager, week soft-lock, and Testers paths

Status: ready-for-agent
Blocked by: 05, 06

Parent: [spec.md](../spec.md) · contract across all three seams

## What to build

Contract phase after the Creator-only path is live: remove or fully unreachable the old product surfaces so the app no longer behaves like a two-role system. Creators must not see Manager/Admin mode, week soft-lock / publish-week ceremony language, Testers allowlist UI, or AI Runway. Prefer delete or fully unreachable over a second mode left dangling. Week containers may still exist as storage if needed, but Creator-facing behavior must not require seven-day publish or soft-lock. This is the cleanup ticket that makes the destination feel Creator-only end-to-end — not a redesign of Plan or Today.

## Acceptance criteria

- [ ] Manager/Admin shell is not reachable as a product mode from the primary Creator experience.
- [ ] Week soft-lock / publish-week ceremony is not the Creator-facing way cards reach Today (language and controls retired from Creator UX).
- [ ] Testers allowlist UI and approved-email OTP sign-in are not product paths.
- [ ] AI Runway is not presented in the Creator product.
- [ ] No owner/editor role gate blocks Plan/generate for Creator.
- [ ] Spot-check / regression: Auth → Today → Plan → Available on Today → Shoot Folio still works after legacy removal.
- [ ] Exact delete-vs-dead-code choice is documented in the PR/commit notes if anything is left unreachable rather than deleted.

## Blocked by

- [Plan hub: calendar, generate, Available, Unpublish](05-plan-hub.md)
- [Today empty journal card and Plan entry points](06-today-empty-and-plan-entries.md)

## Comments
