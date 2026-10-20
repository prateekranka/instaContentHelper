# Plan

The creator plans the next seven days: pick a day, pick an idea for it,
read its script, caption, and storyboard, and replace it if needed.

## Sub-features

- Seven day chips, `plan.sevenDaySelector.day.<n>`, one selected.
- Without a creator voice, `plan.voiceGate.setup` opens voice setup
  first (see [creator-voice.md](creator-voice.md)); "Back to Plan"
  returns.
- Idea choices `plan.daygen.idea.<n>`. Picking one shows the package
  (`plan.package.title`) and `daily.availableOnToday` ("Save for ...").
- Package tabs `plan.package.tab.script`, `.caption`, `.storyboard`.
- `plan.package.replaceIdea`, then an idea, asks to Overwrite or Cancel.

## How to get to it (user POV)

Plan tab, or "Plan tomorrow" from the backup sheet (opens day 2).

## Driving it with e2e

`POCKET_E2E_SCENARIO=plan` runs `tests/pocket-plan.e2e.ts`. Get the days
with `screen.getByTestId(/^plan\.sevenDaySelector\.day\./)`. Use
`scrollToControl(screen, screen.getByTestId('plan.daygen.idea.0'), 'up')`
before tapping an idea.

## Proof

The selected day stays selected after switching away and back. Cancel
keeps the old title; Overwrite gives a new `plan.package.title` that
stays after switching days. Side effect: `weekCards` in the fixture JSON.

## Charters

```
plan-days|ios|fuzzer|In Plan, switch days fast, pick ideas, save, replace, and cancel on several days; report a draft that shows on the wrong day or an overwrite that happens after Cancel
plan-to-today|ios|integration|Save tomorrow's idea, then check that Today keeps today's idea and that Plan still shows tomorrow's
```

## Gotchas

- `screen.scrollUntilVisible` stops when an idea is only partly visible;
  a tap then hits the status bar and scrolls to the top. Use
  `scrollToControl`.
- A new idea can take up to 45 seconds to appear.
