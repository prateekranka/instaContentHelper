# Today and filming

Today shows one ready idea. The creator films it shot by shot, can stop
and come back, or pick an easier backup.

## Sub-features

- Today card: `today.package.title` and the main action
  `today.startFilming`. It reads "Continue filming" after a partial shoot.
  An empty day shows `today.emptyCard`.
- Filming: `shoot.progress` ("Shot N of M", 2 to 12 shots),
  `shoot.complete`, `shoot.next`, `shoot.previous`. A done shot disables
  `shoot.complete`. The first shot disables `shoot.previous`; the last
  disables `shoot.next`. Completing the last shot opens Post.
- Easier backup: `today.notEasier` opens a sheet with
  "10-second story" and "Caption-only post". The preview has Cancel and
  `backup.confirmPosted`. Confirming shows "Used backup: caption-only
  post" and keeps the main idea. "Plan tomorrow" opens Plan on day 2.

## How to get to it (user POV)

Today tab, after onboarding.

## Driving it with e2e

`ready` runs `tests/pocket-today.e2e.ts` (open, then the full shoot);
`alternatives` runs `tests/pocket-alternatives.e2e.ts` (partial shoot,
relaunch, backups). Relaunch with `device.openApp(bundleId, { relaunch:
true, launchArguments: [..., '-MCO_QA_SESSION', session,
'-MCO_FORCE_ONBOARDING', '0'] })` to prove progress survives.

## Proof

Progress text after each tap, and after a relaunch "Continue filming"
plus the next unfilmed shot. `today.startFilming` is at least 44 by 44
points and inside the 402 by 874 screen. After a backup, the Today title
is the same as before.

## Charters

```
filming-order|ios|fuzzer|From Today, film shots out of order: complete, go back, double tap complete, go next and previous fast; report a wrong count, a shot that un-completes, or a Post that opens early
filming-resume|ios|persistence|Film some shots, relaunch the app at each step, and continue; report lost progress or a wrong "Continue filming" state
backup-sheet|ios|recovery|Open "Need something easier?", preview each backup, cancel, confirm, and switch tabs between; report a backup that replaces the main idea or a sheet that will not close
```

## Gotchas

- In accessibility text sizes the bottom bar is hidden; `today.notEasier`
  is then inside the scroll content. Use `scrollToControl` before tapping.
- The backup sheet's Cancel trips the runner's overlap guard; the test
  taps its measured point instead.
