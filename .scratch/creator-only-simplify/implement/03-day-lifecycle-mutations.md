# Day lifecycle mutations: Unpublish, overwrite, edit-keeps-ready

Status: ready-for-agent
Blocked by: 02

Parent: [spec.md](../spec.md) · seam **Day package lifecycle**

## What to build

Complete the day package mutation matrix on top of ready packages. **Unpublish** (with confirmation) demotes a ready package to draft; if that day had a live **Decision**, Unpublish clears the live Decision but keeps **Archive** history. Regenerating a draft overwrites the previous draft without a ready-overwrite warning. Generating over a ready package — or after a Decision — requires warn + explicit **Overwrite**, yields a new draft (not a silent ready replace), clears any live Decision, and keeps Archive history. Light edit of a ready package keeps it ready; when that date is local today, Today refreshes with the edited content. Failed Unpublish / Generate / overwrite paths surface clear errors.

## Acceptance criteria

- [ ] Unpublish on a ready day (with confirmation) returns that day to draft; if it was local today, Today becomes empty of that package.
- [ ] Unpublish after a Decision clears the live Decision and retains Archive history.
- [ ] Draft regenerate overwrites the previous draft without the ready-overwrite warning.
- [ ] Generate on ready or after a Decision shows warn + explicit Overwrite; result is a new draft; live Decision clears if present; Archive history remains.
- [ ] Light edit of a ready package keeps it ready; Today reflects edits when the date is local today.
- [ ] Failed Unpublish / Generate / overwrite surfaces a clear error and does not leave an ambiguous state.
- [ ] Tests cover the lifecycle matrix: Unpublish; overwrite-generate with confirmation; edit-keeps-ready; Decision + Unpublish (live cleared, Archive retained); Decision + overwrite-generate (same Decision rules).

## Blocked by

- [Available on Today: draft → ready package](02-available-on-today-ready-package.md)

## Comments
