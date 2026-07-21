# Available on Today: draft → ready package

Status: ready-for-agent
Blocked by: None

Parent: [spec.md](../spec.md) · seam **Day package lifecycle**

## What to build

A calendar date can be empty, a **draft**, or a **ready package**. The Creator can take one selected date’s draft and run **Available on Today**, which makes that day a ready package without requiring a seven-day week or week soft-lock ceremony. **Today** shows that package only when the date is the device’s local today; a future ready package does not appear on Today. On Available success for local today, navigation lands on Today showing the card. On failure, the Creator stays where they were and sees a clear error. Encoding of draft vs ready is chosen at implement time (week containers may remain as storage underneath) but must break the old coupling where Today only appears after week soft-lock / full-week publish.

This ticket is the expand + first migrate for day availability: new per-day ready behavior works beside (or without depending on) the old week soft-lock product path. Full Plan calendar chrome can wait for the Plan hub ticket; this slice needs enough UI to select a date and invoke Available on Today end-to-end.

## Acceptance criteria

- [ ] A date with a draft can be made a ready package via Available on Today for that single day (no full-week requirement).
- [ ] Today shows the ready package when that date is local today; otherwise Today does not show that package.
- [ ] Future ready packages do not clutter Today.
- [ ] Available on Today success for local today navigates to Today with that card visible.
- [ ] Available on Today failure stays put and surfaces a clear error.
- [ ] Week soft-lock / seven-day publish is not required for a card to reach Today.
- [ ] Repository/Edge (or equivalent) tests lock draft → ready and Today visibility for local today.

## Blocked by

None — can start immediately.

## Comments
