# Creator loop round 5 fixes

Base: `f0d5b36ca7c3c3f5ffe08d41b3a3bb80c9a22c5c`, branch `redesign/creator-loop`.
All changes are local and uncommitted. No live database access, deployment, push, or history change occurred.
The approved plan was read first. Each supplied trace was checked against the base source before its fix.

## Per-bug result

All twelve supplied source bugs are real. Native runtime verification remains with the separate runner.
Paths below use `CreatorContentOS` and `supabase/functions` as their respective roots.

| Bug | Verdict | Confirmed root cause | Fix | Files |
| --- | --- | --- | --- | --- |
| L1 | Real | Native Today used the phone date; the server and fake compared it with UTC. | Generation and replacement DTOs send time_zone. Generate and regenerate validate that IANA zone, fall back to UTC, and reject only dates before its today. Same-key replay precedes date validation. | GenerationDTOs.swift; FixtureRepositories.swift; generate-week/index.ts |
| L2 | Real | Authoritative archive reads overwrote an optimistic Undo even while its decision intent was pending. | Archive merge overlays the latest pending decision for the same revision before merging or caching the read. The server archive ID and frozen text remain intact. | TodayCacheStore.swift |
| L3 | Real | The Save button and handler both required a script, and the payload always sent one. | One shared format-aware rule permits a caption-only post with an empty script. The handler omits blank script and inapplicable scenes. | TodayPocketPresentation.swift |
| F1 | Real | Replacement acceptance left an archived, non-current pointer; edge lookup, SQL guards, and native package/launcher guards each blocked recovery. | Both replacement and ordinary generation can use the retained pointer for recovery. They reuse its plan, including a locked plan, without touching the frozen revision. Native generation ignores archived content as a current package, and Plan offers ideas. FakeServer permits the same recovery. | AppServices.swift; PlanHubView.swift; FixtureRepositories.swift; generate-week/index.ts; new round5 migration |
| F2 | Real | Mark posted could queue during Unpublish; decision replies then changed only Archive. | Posting checks both active Unpublish and pending return-to-draft for the revision. A decision acknowledgement reconciles current day status and decision, while a newer pending decision still takes precedence. | AppServices.swift |
| F3 | Real | Stale handlers assumed a conditional failure write changed the run, even when completion had won. | Both keyed replay and status reread persisted run state after the write. Completion returns its snapshot; read failure stays retryable instead of manufacturing terminal generation_stale. | generation-idempotency.ts; generation-status-handler.ts; existing stale mock |
| F4 | Real | First-idea and daily_card_not_found cleanup captured the whole queue before an awaited profile save and restored the stale copy. | Cleanup waits first, then removes one current intent. A cache-save failure reinserts only that intent at its prior index. Successful cleanup uses the same helper. | AppServices.swift; TodayCacheStore.swift |
| C1 | Real | All package boundaries accepted duplicate UUIDs, but filming completion used a set. | Edge, SQL, and FakeServer reject repeated shot IDs, comparing canonical UUID identity without case sensitivity. | update-ready-day-package/index.ts; FixtureRepositories.swift; new round5 migration |
| C2 | Real | Optional number and symbol bypassed validation although native decoding requires Int and String. | All boundaries validate id, title, duration, optional integer number within native Int bounds, optional string symbol, and optional string dialogue. Null or other types fail before any patch write. | update-ready-day-package/index.ts; FixtureRepositories.swift; new round5 migration |
| C3 | Real | Preservation rebuilt shots without id/dialogue and kept the new generated script. | Preservation retains saved IDs and dialogue, including empty dialogue and empty lists. Owned scenes retain the saved script and ownership; legacy scenes without owned dialogue retain prior generated-script behavior. Ownership is read and persisted with the revision. | generation-validation.ts; generation.ts; generation-context-store.ts; generation-persistence.ts; new round5 migration |
| C4 | Real | FakeServer stored preserve_manual_edits in identity but did not apply it. | finishRun copies the same manual fields and saved shots before archiving the prior draft. It carries ownership and shot lines into the saved reply. | FixtureRepositories.swift |
| C5 | Real | An empty scene list triggered legacy migration from old timelines on replies and reload. | Explicit scene-list writes set shot_content_owned, including []. Native cache and card projections carry the marker. Only unowned content can migrate; normalization then sets the native marker. Owned empty lists stay empty. | Models.swift; TodayCacheStore.swift; SupabaseDTOs.swift; GenerationDTOs.swift; FixtureRepositories.swift; read-content/index.ts; generation persistence/context; new round5 migration |

## Saved loop failure evidence

Both saved failures are test defects. They do not establish a duplicate current archive entry or a failed repost.
The separate source-confirmed L2 and F2 defects are fixed in the app as described above.

- **R4-L1:** The log fails at line 503, before Undo is selected. In its `failure/screen.txt`, nodes n194829/n194831 show `Loop ready package` and `Posted`. Nodes n194835/n194837 show `Race week has entered the house` and another `Posted`. These are two different titles, not two rows for the loop revision. Keep the existing assertion that the loop title appears once. The new `archive.output.Loop ready package` target checks that entry's status before Undo, after Undo, and after relaunch. Existing accessibility identifiers were retained.
- **R4-C3:** The log fails at line 529, before the second Mark posted action at line 531. Its `failure/screen.txt` is `/ Post`, with BackButton at n204267, `Ready for Today.` at n204272, `post.manualInstructions` at n204275, and `post.markPosted` at n204285. The Today tab is already selected. `selectTab` therefore returns without popping its saved Post route. The new helper selects Today and pops a bounded number of Back routes to its root, then checks `today.startFilming`. Both round 4 scenarios use it. The repost assertions still require the posted state after two relaunches and one loop title in Archive.

Evidence roots:

- `.e2e/proof/r4-loop-030243.log`
- `.e2e/proof/r4-loop-030243/artifacts/contenthelper-ios/tests_pocket-loop.e2e.ts__loop_20R4-L1_3A_20Undo_20posted_20updates_20the_20single_20Archive_20entry_20after_20-7e24b38d/default/attempt-0/failure/screen.txt`
- `.e2e/proof/r4-loop-030243/artifacts/contenthelper-ios/tests_pocket-loop.e2e.ts__loop_20R4-C3_3A_20repost_20after_20Unpublish_20and_20Make_20ready_20persists_20one_20-53cef202/default/attempt-0/failure/screen.txt`

## Files changed

| File | Change |
| --- | --- |
| `CreatorContentOS/App/AppServices.swift` | Treats archived recovery data as no package, serializes posting with Unpublish, reconciles decision replies, and removes only the resolved intent. |
| `CreatorContentOS/Data/GenerationDTOs.swift` | Sends the phone time zone for generation and replacement and decodes shot ownership in generation replies. |
| `CreatorContentOS/Data/SupabaseDTOs.swift` | Decodes the server shot ownership marker and carries it into both native card models. |
| `CreatorContentOS/Data/TodayCacheStore.swift` | Keeps pending decisions ahead of archive refreshes, marks scene edits as owned, and restores only one failed intent removal. |
| `CreatorContentOS/Features/Archive/ArchiveView.swift` | Adds an output identifier per archive title so loop assertions can target the intended entry. |
| `CreatorContentOS/Features/Daily/PlanHubView.swift` | Shows the idea launcher for archived replacement recovery data while hiding the old package. |
| `CreatorContentOS/Features/Today/TodayPocketPresentation.swift` | Uses one format-aware save rule and omits inapplicable empty script and scene fields for caption-only posts. |
| `CreatorContentOS/Fixtures/FixtureRepositories.swift` | Matches time-zone validation, recovery generation, shot validation, edit preservation, and ownership persistence in FakeServer. |
| `CreatorContentOS/Models/Models.swift` | Persists shot ownership through cache and projections and restricts legacy timeline migration to unowned content. |
| `supabase/functions/generate-week/generation-context-store.ts` | Reads shot ownership with saved generation context. |
| `supabase/functions/generate-week/generation-context-store_test.ts` | Updates the existing select-contract expectation for the ownership field. |
| `supabase/functions/generate-week/generation-idempotency.ts` | Reads persisted run state after a stale failure write before choosing a replay response. |
| `supabase/functions/generate-week/generation-idempotency_test.ts` | Updates the existing stale-run mock to supply the required authoritative read. |
| `supabase/functions/generate-week/generation-persistence.ts` | Persists shot ownership and reads ownership and script when preserving saved edits. |
| `supabase/functions/generate-week/generation-status-handler.ts` | Returns the persisted result when completion wins a stale-status race. |
| `supabase/functions/generate-week/generation-validation.ts` | Retains saved shot identity and dialogue and validates optional native metadata during preservation. |
| `supabase/functions/generate-week/generation.ts` | Preserves saved shot identity, dialogue, ownership, and owned script during regeneration. |
| `supabase/functions/generate-week/index.ts` | Validates dates in the client zone and reuses the retained plan for ordinary or replacement recovery generation. |
| `supabase/functions/generate-week/index_test.ts` | Updates the existing past-date regeneration expectation to the approved date rule. |
| `supabase/functions/read-content/index.ts` | Includes shot ownership in stored-card reads. |
| `supabase/functions/update-ready-day-package/index.ts` | Rejects duplicate UUIDs and invalid optional number, symbol, and dialogue fields before the RPC. |
| `supabase/migrations/20261021120000_round5_creator_loop_recovery.sql` | Adds ownership and replaces only the generation-start, revision-persistence, and package-update functions for recovery and validation. |
| `tests/pocket-loop.e2e.ts` | Targets the loop archive entry and returns to Today root in the two failing round 4 scenarios. |
| `tests/pocket-support.ts` | Adds the bounded Today-root navigation helper used by those loop scenarios. |
| `docs/design/creator-loop-redesign.md` | Records round 5 behavior and the remaining runtime gates in the approved design document. |
| `docs/design/creator-loop-server-contract.md` | Documents local-date validation, archived recovery, stale-run responses, native shot types, and ownership. |
| `docs/design/creator-loop-round5-fixes.md` | Records each confirmed trace, fix, changed file, command result, and validation limit. |

## Commands and results

- `workspace-guard.sh --root <checkout> --branch redesign/creator-loop`: passed; the initial checkout had zero dirty paths.
- `git status --short`, `git rev-parse HEAD`, and `git branch --show-current`: confirmed the base and branch. Only task changes remain.
- Read-only `rg`, `cat`, `sed`, and `wc` commands: traced each issue and read the changed Swift and SQL files end to end. No build or runtime claim is based on these reads.
- `evidence-path.sh --root <checkout>/work/evidence --label round5-fixes`: created `work/evidence/round5-fixes/20261021T020858Z.gCJ2Pz`. The workspace path is durable and writable in this sandbox.
- `command-watchdog.sh --timeout-seconds 240 ... -- deno task ci:backend`: final result passed, **403 passed, 0 failed, 2 ignored**. Type checking passed. The ignored checks are the local-database transaction test and the existing partial-week status test. Earlier attempts exposed one TypeScript narrowing error and three contract expectations; these were corrected. The wrapper's first invocation rejected relative log paths; subsequent invocations used absolute paths.
- `deno fmt <seven changed backend TypeScript files>`: passed, seven files checked.
- Xcode 27.1 beta toolchain `swiftc -frontend -parse <nine changed Swift files>`: passed, exit 0. This is syntax-only parsing, not an iOS build or full type check. Final result is in `swift-parse-final.log`.
- `node` TypeScript parser attempt: unavailable because the workspace has no `typescript` module. No package was installed. Deno's parser was used instead.
- `deno fmt --ext ts -` with each loop test file supplied on stdin and output discarded: both files parsed successfully, exit 0. This did not run e2e or change either file.
- `git diff --check`: passed.

Final backend logs are `backend-final.stdout.log` and `backend-final.stderr.log` in the evidence directory above.

## Remaining validation

No implementation item is left open in this round. The following evidence is intentionally outside this sandbox task:

- Full iOS build and Swift type checking.
- Local application of the new migration and rollback-only database transaction checks.
- TesterArmy e2e rerun, including both corrected loop scenarios and the round 5 behavior cases.

No simulator was accessed. No e2e command was run. No Swift unit test, new backend unit test, or code comment was added.
Earlier migration files were not changed. Backend CI does not prove that the new migration applies or that native flows pass.

## Regression repair after the round 5 review

Reviewed `.e2e/proof/r5-loop-075237/report.json`, its failure screens, and the ready report and failure screen under `.e2e/proof/r5-ready-075237/`.
The existing assertions remain unchanged in this repair.

- The loop failures share a fixture construction defect. `storyboardBreakdownFixture` already normalizes its ten shots and marks their dialogue as owned. `fixtureDailyCardDraft` then assigned stable IDs by rebuilding those shots without their dialogue. The ownership marker correctly prevented another legacy import, leaving nine newline separators and no spoken text. This explains the disabled Shoot and Plan saves, empty Post editor in R3-C7, missing timeline lines, and R1-3 copy mismatch. `AppRuntime.swift` now carries dialogue through the ID mapping. The line-script and blank-copy overrides also edit shot dialogue directly, so their intended content survives normalization.
- The ready failure expects three trailing blank lines after relaunch; screen node n9583 contains the edited text without those lines. The Post payload used the trimmed value returned by `nilIfBlank`, and FakeServer also trimmed newlines from script writes. `TodayPocketPresentation.swift` now checks blankness separately and sends the original nonblank script. `FixtureRepositories.swift` preserves script newlines and matches SQL's space-only `trim` behavior.

All twelve round 5 fixes remain. Legacy normalization still runs only for unowned content, explicit empty scene lists stay empty, caption-only posts can save without a script, and posting remains blocked during Unpublish. No save validation or test expectation was weakened.

Only three Swift files changed in this repair: `AppRuntime.swift`, `TodayPocketPresentation.swift`, and `FixtureRepositories.swift`. Each was read end to end. This report is the only documentation change in the repair.

Validation:

- Xcode 27.1 beta toolchain `swiftc -frontend -parse` on those three Swift files: passed, exit 0. Syntax parsing does not replace a full iOS build or type check.
- `deno task ci:backend`: passed, 403 passed, 0 failed, 2 ignored.
- `git diff --check`: passed.
- HEAD remains `f0d5b36ca7c3c3f5ffe08d41b3a3bb80c9a22c5c` on `redesign/creator-loop`. Existing round 5 changes remain uncommitted.

Logs are under `work/evidence/round5-regressions/20261021T025347Z.TQlvLW/`.
The ready and loop reruns remain with the separate runner. No e2e, simulator, iOS build, or database command ran in this repair.
