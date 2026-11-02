# UI numbers for the screens that stay

Source: a UI cheatsheet by @Vedantdzn on X (2026-10-20), with two example
screens (a Home list and a Settings list). Use these numbers in steps 3
and 4 for Filming, Creator voice and topics, You, Account and privacy,
and Sign in. They change `PocketSheetTheme`, the theme those screens use.

## Numbers

| Element | Cheatsheet | Pocket theme now | Use |
| --- | --- | --- | --- |
| Type | SF Pro, Medium and Regular only | Semibold and Bold in places | Medium for titles, row titles, and buttons. Regular for everything else. No Bold. |
| Large text | 18 pt on 22 line | Screen title is `.title2` semibold | Screen and section titles |
| Main text | 16 pt on 20 line | Row title is `.subheadline` semibold | Row titles, body, buttons |
| Small text | 14 pt on 18 line | Row subtitle is `.footnote` | Row subtitles, group labels, help text |
| Text color | `#000000` default, `#666666` subtle | `ink #111111`, `inkMuted #737373` | `ink` and `inkMuted` |
| Label to its list | 12 | `Spacing.s` 12 | Keep |
| Between sections | 28 | none (24 is `xl`) | Add `Spacing.section = 28` |
| Nav icons | 24 | mixed | Back, close, more |
| List icons | 28 | mixed | Leading icon in a row |
| List row padding | 12 vertical, 20 horizontal | mixed | Every list row |
| Buttons | 44 high, 16 horizontal padding, text in 4 horizontal padding, no gap between text and icon | mixed | Every button |

## Elements from the examples

- Grouped list rows on a light gray fill, with thin separators and one
  rounded container per group. A chevron at the end of a row that opens
  a screen.
- One plain line icon at the start of each row.
- Round nav buttons (back, search, more) in a small floating capsule with
  a soft shadow. The screen title is centered and small.
- A short gray group label in sentence case above each group ("App
  settings"). It names the group; it is not an eyebrow over a title.
- A row can carry a status icon at its start (done, in progress).

## Rules that still win

- No eyebrow text. No uppercase labels.
- The user's goal and main action come first on each screen.
- Text must still grow with Dynamic Type. Write sizes as
  `Font.system(size: 16, weight: .medium)` scaled with `@ScaledMetric`
  or `relativeTo:`, never as a fixed size. The `large` e2e group must
  still pass.
- App-owned UI stays black, white, and gray.
- Keep every e2e test ID.
