# Creator loop redesign

Status: draft for approval (2026-10-20). Base: `92406c5` on `fix/e2e-keyboard-done`.

## Why patches stopped working

Three bug hunts found 14, 10, and 16 bugs in the same loop. Almost every bug
comes from one of five root causes:

| # | Root cause | Bugs it made (examples) |
| --- | --- | --- |
| A | One day lives in many copies: `todayCard`, `weekCards`, `dayBriefGeneratedCards`, `latestGenerationSummary`, `planDayIdeasByDate`, `archiveEntries`, the cache file. Each copy is updated by hand. | Plan shows an old caption after a save. Offline relaunch shows a placeholder as ready. Shot ids lost on replace. |
| B | Work that is not finished yet sits in four separate stores, each with its own rules: `unsyncedTodayDecision` (one slot), `PendingFirstIdea` (UserDefaults, expires at midnight), `acceptedGenerationStore`, and local variables during an overwrite. | A new decision erases an older unsynced one. First idea lost after midnight. Retry resumes a dead run. Overwrite loses filming progress on a crash. |
| C | "Replace this day" is two client calls (unpublish, then generate). A crash or error between them leaves a half state. | Overwrite recovery bugs in rounds 1, 2, and 3. |
| D | The server reuses one `daily_cards` row for every idea on a date. The archive points at that row. | A posted idea shows the new idea's title. A new decision replaces the old one. |
| E | Fixtures copy server rules by hand and drift (blank edits, posted state, today pointer, profile not saved). | Tests pass on behavior the real server does not have. |

A smaller sixth cause: dialogue and timecodes come from two sources
(script text and the shot timeline), and the code guesses which one wins.

## The new shape

### 1. One day, one record (fixes A)

- A `Day` value per creator and date. It holds the current content
  **revision** (an immutable id plus its content), the lifecycle, and the
  filming progress for that revision.
- Lifecycle is one enum: `empty`, `generating(run)`, `draft`, `ready`,
  `filming(progress)`, `decided(posted | backup | skipped)`, `unavailable`.
  Moves between states go through one function that rejects illegal moves.
- A `DayStore` owns all `Day` values. Today, Plan, Filming, Post, and
  Archive read views of it. No screen keeps its own copy.
- The cache file is a snapshot of `DayStore` plus the outbox, with a
  schema version. Old files decode with missing fields set to empty;
  a file that cannot decode is kept aside, not overwritten.

### 2. One outbox for unfinished work (fixes B)

- One saved queue of intents: `decide`, `editPackage`, `generate`,
  `replaceDay`, `firstIdea`. Each intent has an idempotency key and the
  revision id it targets.
- Intents never expire by date. They leave the queue only when the server
  answers "done" or "this revision no longer exists".
- One replay loop runs on launch, foreground, day change, and after
  network returns. It is the only retry path.
- The accepted-generation store, `PendingFirstIdea`, and the single
  unsynced slot are deleted.

### 3. Server owns the hard steps (fixes C and D)

New migration and functions (client and server code in this repo):

- Every generation makes a **new** `daily_cards` row (a new revision).
  The date points at its current revision. Old revisions stay.
- `archive_entries` points at the exact revision that was posted, and
  stores the title and caption at decision time. Posted history never
  changes after that.
- `replace-day` does unpublish, archive of the old revision, and the start
  of a new generation in one transaction. Filming progress stays with the
  old revision.
- Generation runs are keyed by the idempotency key. A retry with a new
  brief starts a new run. The server closes failed runs, so the client
  never resumes a dead run.
- Package edits follow one written rule: blank text is rejected with an
  error, and the client editors block an empty save.
- Decisions are upserts keyed by revision id, so a replay is safe.

### 4. Fixtures become a fake server (fixes E)

- One `FakeServer` implements the same function contract as the real
  functions (same inputs, same errors, same rules), saved per
  `MCO_QA_SESSION`, including the creator profile.
- Fixture repositories call it the same way the real repositories call
  Supabase. No per-feature fixture logic.

### 5. Shots own their lines (the sixth cause)

- Each shot stores its dialogue and duration. Script text is built from the
  shots, not parsed back into them. Timecodes come from durations only.
- The script editor edits shot lines, so a one-word change stays on its shot.

## Phases

Every phase ends with a build and all 12 e2e groups passing. Codex
(gpt-6.1-sol, extra high) writes each phase. Claude reviews each diff
before the next phase. Haiku runs the e2e groups.

| Phase | Work | Done when |
| --- | --- | --- |
| 0 | Write the lifecycle table and turn the 40 found bugs into e2e scenarios where the e2e tool can reach them. | Scenarios exist; the ones for open bugs fail for the right reason. |
| 1 | Server: revision rows, archive snapshot, `replace-day`, keyed runs, edit rule. Local Supabase only. | Server tests in `supabase/functions` pass. No live change. |
| 2 | `DayStore` and views; screens read from it. Old copies removed. | Today, Plan, Filming, Post read one source. |
| 3 | Outbox replaces the four pending stores. | Crash and offline scenarios pass. |
| 4 | `FakeServer` replaces fixture logic. | Fixture and real paths share one contract. |
| 5 | Shots own dialogue and duration. | Script edit scenarios pass. |
| 6 | Delete dead code, then one bug hunt round on Codex. | Zero confirmed bugs, or a short list with no repeat root cause. |

Step 4 (the 17 UI items) runs after phase 6, because phases 2 and 5 change
the same screens.

## Not in scope

- Live database migration or deploy. This needs a separate yes, and a plan
  to move existing rows to revisions.
- Onboarding questions, AI prompts, and screen design.

## Kept from the stopped patch job

The partial round 3 fixes are saved in `.e2e/patches/round3-partial-fixes.patch`
and in git stash "round3 partial patch fixes". Phases reuse ideas from it
only where they still fit.
