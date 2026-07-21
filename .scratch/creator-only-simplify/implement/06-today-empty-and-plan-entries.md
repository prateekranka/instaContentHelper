# Today empty journal card and Plan entry points

Status: ready-for-agent
Blocked by: 02, 04, 05

Parent: [spec.md](../spec.md) · seam **Creator shell** (consumes **Day package lifecycle**)

## What to build

Finish the Creator daily loop on Today. When there is no ready package for local today, Today shows the journal-card empty state (prototype variant B): headline “Nothing ready for today,” short body that nothing is ready yet, single CTA **Plan today’s content** → Plan; no overflow menu on empty Today. When a ready package exists, Today shows it; Shoot Folio (Scenes / Script / Caption / Audio), copy, mark shot/posted, and **Give me other ideas** → Decision stay available. With a card showing: Edit opens Plan on that date; `⋯` overflow contains **Plan only**. Morning local notification copy is **Get today’s content ready.** Offline cached Today still serves a ready package when the network fails. Instagram shoot/edit/post remains outside the app.

Empty-state visual source: `.scratch/creator-only-simplify/assets/07-empty-today-prototype.html` (variant B).

## Acceptance criteria

- [ ] Empty Today (no ready package for local today) shows the journal card: “Nothing ready for today,” supporting body, CTA “Plan today’s content” → Plan; no `⋯` on empty Today.
- [ ] Ready Today shows the package; Creator can open Shoot Folio, copy text, mark scenes shot / posted, and use Other ideas → Decision.
- [ ] Edit on Today hero and Edit on Shoot Folio open Plan with that card’s date preselected.
- [ ] When a card is showing, `⋯` contains Plan only (no other overflow items).
- [ ] Local notification title/copy is “Get today’s content ready.”
- [ ] Offline cached Today still presents a ready package when network fails.
- [ ] UI tests (or highest existing UI seam) lock: empty CTA → Plan; Edit/`⋯` → Plan with date; ready card still reachable after Available on Today.

## Blocked by

- [Available on Today: draft → ready package](02-available-on-today-ready-package.md)
- [Creator-only shell: Today · Archive · Profile](04-creator-only-shell.md)
- [Plan hub: calendar, generate, Available, Unpublish](05-plan-hub.md)

## Comments
