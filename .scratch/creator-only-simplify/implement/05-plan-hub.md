# Plan hub: calendar, generate, Available, Unpublish

Status: ready-for-agent
Blocked by: 03, 04

Parent: [spec.md](../spec.md) · seam **Creator shell** (consumes **Day package lifecycle**)

## What to build

The buried **Plan** hub is the prep surface. Vertical order: title → calendar + legend → daily generation prompt → Generate for the selected date → result / light edit → Available on Today → Unpublish when green → collapsed **Creator Profile** accordion → collapsed **References** accordion (both collapsed by default). Calendar legend: green = ready package, yellow = draft, no dot = empty. Calendar replaces Today/Tomorrow chips + picker as the date control. Wiring uses the lifecycle mutations from earlier tickets. Profile → Plan is a working entry. Exact calendar chrome polish is out of scope; IA and behavior are not.

## Acceptance criteria

- [ ] Plan opens from Profile with the locked vertical IA order; Profile and References accordions are collapsed by default.
- [ ] Calendar shows green/yellow/none dots with a legend explaining ready vs draft vs empty.
- [ ] Creator can select a date, enter a daily prompt, and Generate a draft for that one date.
- [ ] Draft regenerate overwrites; ready / after-Decision generate uses the warn + Overwrite path from ticket 03.
- [ ] Light edit in Plan on a ready package keeps it ready.
- [ ] Available on Today and Unpublish are available on Plan and match lifecycle behavior (including success → Today when date is local today; failure stays on Plan with a clear error).
- [ ] Creator Profile fields and References (import / needs-your-call / growth-library style surfaces) live under the collapsed Plan accordions — relocated, not redesigned.
- [ ] No screenshot-perfect chrome tests required; behavior tests cover generate / Available / Unpublish / calendar state meanings.

## Blocked by

- [Day lifecycle mutations: Unpublish, overwrite, edit-keeps-ready](03-day-lifecycle-mutations.md)
- [Creator-only shell: Today · Archive · Profile](04-creator-only-shell.md)

## Comments
