# You and creator voice

The You tab holds the creator's history and preferences. Creator voice
tells the idea maker how the creator talks and what they make.

## Sub-features

- `you.preferences.toggle` shows the rows `you.row.account`,
  `.interests`, `.production`, `.context`, `.voice`, `.references`. Each
  opens `you.screen.<name>`; "Back to You" returns.
- History: past ideas; `you.archive.seeMore` appears after five entries.
  The archive has All and Backups filters and a detail view.
- Voice: `you.voice.positioning` and `you.voice.rules` text fields,
  `you.voice.keyboardDone`, and `you.voice.save` (disabled once saved).

## How to get to it (user POV)

You tab, then the preferences toggle, then a row. Or Plan's
`plan.voiceGate.setup` when no voice is saved.

## Driving it with e2e

`plan` drives voice setup from Plan. The catalog
(`npx e2e run --config e2e.screens.config.ts --grep 'catalog You'`) opens
every preference screen. A full archive needs `MCO_BREAK_UI_DATA=worst`.

## Proof

`you.voice.save` is disabled after save, and Plan's ideas become enabled.
Reopen voice after a relaunch to prove the text stayed. History shows
each posted idea once.

## Charters

```
voice-input|ios|fuzzer|Enter voice text that is empty, very long, emoji, and many lines; save, leave, and relaunch; report text that is lost or a Save that stays enabled
you-rows|ios|navigation|Open every You row and come back, at normal and large text; report a row that does not open, a dead back button, or a lost scroll place
```

## Gotchas

- The voice fields are below the fold in large text; scroll and dismiss
  the keyboard between them.
- Account, privacy, and AI consent screens touch real services outside
  fixture mode. Never test them signed in to a real account.
