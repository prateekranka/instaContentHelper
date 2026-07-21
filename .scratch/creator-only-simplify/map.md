# Wayfinder: Creator-only daily loop

## Destination

A Creator-only Instagram app whose primary UI is Today → Shoot Folio → decision, with a buried Plan path for day-at-a-time prep, Creator Profile, and References; per-day available-on-Today; Sign in with Apple; notification “Get today’s content ready.” No Manager shell, week soft-lock ceremony, Testers UI, or AI Runway.

## Notes

- Domain: ContentHelper / instaContentHelper (SwiftUI + Supabase). Glossary: root `CONTEXT.md`.
- Skills every session should consult: `/grilling`, `/domain-modeling`, `/batch-grill-me` when frontier questions fan out; `/prototype` for UI fidelity tickets.
- Standing preferences: optimize only for the Creator’s daily loop; Plan is buried, never a second primary mode; Instagram shoot/edit/post stays outside the app; keep offline Today cache and local notification plumbing; produce decisions until the way is clear — do not build the destination inside this map unless Notes are updated.
- Tracker: local markdown under `.scratch/creator-only-simplify/`.

## Decisions so far

- [Primary shell without Manager mode](issues/01-primary-shell.md) — Tabs Today · Archive · Profile; Plan via Profile, empty-Today CTA, or Today `⋯` (Plan only); Profile = account + Plan + Supabase/Gemini status
- [Plan hub information architecture](issues/02-plan-hub-ia.md) — Plan stack: calendar+legend → prompt → generate → edit → available on Today → collapsed Profile & References accordions; green=ready, yellow=draft, overwrite drafts; Edit from Today/Shoot Folio opens Plan; success of available → Today
- [Publish and soft-lock data model (research)](issues/03-publish-data-model-research.md) — Soft-lock is week-only; Today = published-lifecycle card statuses; 7-day publish + post-publish edit/regen blocks; `review_state` ≠ Today availability ([full notes](assets/03-publish-data-model-research.md))
- [Per-day available-on-Today semantics](issues/04-available-on-today-semantics.md) — Per-day draft/ready; Available one day; Unpublish (+ after Decision clears live Decision, keeps Archive); overwrite-generate warns; edit keeps ready; Today = local today only; soft-lock language retired
- [Sign in with Apple + current auth (research)](issues/05-sign-in-with-apple-research.md) — OTP → exchange → device token; Apple via native id_token + same exchange; migration hinges on `members.auth_user_id` ([full notes](assets/05-sign-in-with-apple-research.md))

## Not yet specified

- Migration / encoding of draft vs ready in schema (replace week soft-lock + `status=published` gate) once build starts
- Whether Admin/Manager codepaths are deleted, feature-gated, or left unreachable after shell removal
- Generation prompt / quality behavior once there is no Manager framing (only Creator + Plan)
- TestFlight / allowlisting without Testers UI once Sign in with Apple replaces OTP (blocked on ticket 06 grilling)
- Visual system for Plan hub (beyond IA) — calendar chrome, accordion styling, legend placement
- Exact Profile “Gemini status” / Supabase status presentation (enough that both are required light support)
- Exact Unpublish / Overwrite confirmation copy

## Out of scope

- Manager / Admin shell as a product mode
- Week soft-lock publish ceremony as the way cards reach Today
- Testers UI redesign
- AI Runway
- Multi-creator workspace
- In-app Instagram recording, editing, or publishing
- Redesigning Shoot Folio’s Scenes / Script / Caption / Audio structure in this effort
