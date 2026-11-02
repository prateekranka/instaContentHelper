# Post

After filming, the creator edits the script and caption, copies the
caption, posts by hand on Instagram, and marks the idea posted. The app
never posts for them.

## Sub-features

- `post.manualInstructions` says the app "does not publish".
- `post.edit` opens `post.script.editor` and `post.caption.editor`.
  `post.keyboardDone` closes the keyboard. `post.save` keeps the edits;
  `post.cancel` drops them.
- `post.copy.caption` puts the caption on the clipboard.
- `post.markPosted` shows "Posted"; `post.undoPosted` reverts it.
- A failed sync shows `post.syncError`, and `post.markPosted` still works.

## How to get to it (user POV)

Complete the last shot in filming. After that, `today.startFilming` opens
Post straight away.

## Driving it with e2e

`ready` runs it inside the filming test; `sync-error` sets
`MCO_FAIL_TODAY_DECISION_SYNC_ONCE=1`. Type with `pressSequentially`,
close with `dismissKeyboard(screen, 'post.keyboardDone')`, and tap Save
and Cancel with `tapEditorControl`.

## Proof

Editor values with `inputValue()` before and after; `device.clipboard()`
equals the saved caption; after a relaunch the script and caption keep
the saved text and Today still says "Posted". On You, the idea title
appears exactly once in the history. Side effect: `todayCard.script` and
`todayCard.caption` in the fixture JSON.

## Charters

```
post-edits|ios|fuzzer|In Post, edit script and caption with emoji, very long text, and empty text; cancel, save, and relaunch; report text that is lost, kept after cancel, or cut
post-state|ios|persistence|Mark posted, undo, mark again, relaunch, and open You; report a double history entry or a wrong posted state
```

## Gotchas

- The keyboard can appear late; never tap a stored Done point.
- The caption editor is below the fold; scroll to it first.
