# Creator loop round 4

Local source changes on `redesign/creator-loop`, based on `07a4d7093ade43f51d75391e774a53c11459e77b`.
All eight reported traces were re-read and confirmed before their fixes. None was skipped.
No commit, push, deployment, database connection, e2e run, or simulator action was performed.
App UI colors, Dynamic Type layout, and accessibility identifiers were preserved. No code comments or Swift unit tests were added.

## Findings and fixes

| Bug | Confirmed root cause | Local fix | Files |
| --- | --- | --- | --- |
| L1 — real | The archive merge rejected every transition away from Posted, including authoritative undo replies. | Allow authoritative decision changes and optimistic Undo posted. Keep the stored title and caption snapshots. | `TodayCacheStore.swift`, `AppServices.swift`, `pocket-loop.e2e.ts` |
| F1 — real | Past-date rejection remained retryable, with the day left generating and no accepted run. | Retarget an unaccepted firstIdea to current today and persist the date before replay. Other generation intents record terminal failure, leave generating, and show that the day has passed. Persist terminal state before profile cleanup. | `AppServices.swift`, `Models.swift` |
| F2 — real | A stale replacement target removed its intent without leaving generating. | Restore the retained revision's lifecycle, or empty if no revision exists, before resolving the rejected intent. Check request ownership before changing the day. | `AppServices.swift`, `Models.swift` |
| F3 — real | Revision insertion and run completion used separate commits. A stale run then made native failure recovery archive its new revision. | Commit the revision and completed draft snapshot together. Allow finalization to enrich completed snapshots without reopening failed runs. Native failure recovery archives only the prior revision. | New round 4 migration, `generation-persistence.ts`, `generation-run-store.ts`, `Models.swift`, `AppServices.swift`, backend regressions |
| C1 — real | Acceptance archived the old revision but left it current until the new revision arrived. FakeServer also treated its retained day pointer as mutation permission. | Clear is_current at acceptance. Repair previously accepted archived rows in the new migration. Reject changed historical decisions with historical_revision_immutable. Exact historical retries remain read-only and idempotent. | New round 4 migration, `FixtureRepositories.swift`, `creator-loop-db.sql` |
| C2 — real | Migration applied backup or skipped decisions before markShots, whose lifecycle guard rejected decided days. | Restore valid shot marks before applying the saved completion. Add a legacy-backup seed with one filmed shot and its pending backup decision. | `TodayCacheStore.swift`, `AppRuntime.swift`, `pocket-support.ts`, `pocket-loop.e2e.ts` |
| C3 — real | A Posted archive row caused SQL and FakeServer to return before restoring the live card after Unpublish and Make ready. | Restore the live posted status and decision time while retaining the same archive entry, snapshots, and timestamp. | New round 4 migration, `FixtureRepositories.swift`, `creator-loop-db.sql`, `pocket-loop.e2e.ts` |
| C4 — real | Server validation accepted arbitrary string IDs; native decoding treated one malformed shot as failure of the entire list. | Require canonical UUID strings at the edge, SQL, and FakeServer boundaries. Decode shots independently in stored and generated cards. Replace valid backend test IDs with UUIDs and add explicit invalid-ID cases. | New round 4 migration, `update-ready-day-package/index.ts`, `index_test.ts`, `SupabaseDTOs.swift`, `GenerationDTOs.swift`, `FixtureRepositories.swift`, backend fixtures, contract |

## Files changed

| File | Change |
| --- | --- |
| `CreatorContentOS/App/AppRuntime.swift` | Adds the session-isolated legacy-backup cache seed with partial filming and a backup decision. |
| `CreatorContentOS/App/AppServices.swift` | Applies archive undo, terminal rejection recovery, first-idea retargeting, and revision-aware generation failure recovery. |
| `CreatorContentOS/Data/GenerationDTOs.swift` | Uses independent shot decoding for generation replies. |
| `CreatorContentOS/Data/SupabaseDTOs.swift` | Adds the shared shot-list decoder and uses it for stored card reads. |
| `CreatorContentOS/Data/TodayCacheStore.swift` | Allows archive undo merges and restores legacy filming marks before decisions. |
| `CreatorContentOS/Fixtures/FixtureRepositories.swift` | Aligns FakeServer UUID validation, historical mutation guards, and repost persistence with SQL. |
| `CreatorContentOS/Models/Models.swift` | Adds pre-acceptance generation rejection recovery and limits failure archiving to the prior revision. |
| `supabase/migrations/20261021100000_round4_creator_loop_recovery.sql` | Replaces four functions to freeze accepted history, save repost state, atomically complete saved generations, and require UUID shot IDs. |
| `supabase/functions/generate-week/generation-persistence.ts` | Supplies the generated card representation for the atomic completed snapshot. |
| `supabase/functions/generate-week/generation-persistence_test.ts` | Checks that persistence supplies the complete generated card snapshot. |
| `supabase/functions/generate-week/generation-run-store.ts` | Enriches already completed day snapshots while keeping failed runs closed. |
| `supabase/functions/generate-week/generation-run-store_test.ts` | Covers both running completion and completed-snapshot enrichment in the existing test. |
| `supabase/functions/replace-day/index_test.ts` | Uses a UUID for the preserved filming mark fixture. |
| `supabase/functions/update-ready-day-package/index.ts` | Validates every supplied shot ID as a canonical UUID string. |
| `supabase/functions/update-ready-day-package/index_test.ts` | Uses valid UUID fixtures and rejects malformed UUID strings. |
| `supabase/functions/_shared/creator-loop-db.sql` | Adds local transaction assertions for early history freeze, repost persistence, atomic completion, and invalid UUIDs. |
| `tests/pocket-loop.e2e.ts` | Adds R4-L1, R4-C3, and R4-C2 UI scenarios, including relaunch checks. |
| `tests/pocket-support.ts` | Adds legacy-backup to the typed scenario list. |
| `docs/design/creator-loop-server-contract.md` | Records the final UUID, replacement, repost, past-date, and atomic completion contracts. |
| `docs/design/creator-loop-lifecycle.md` | Records cache ordering, rejection recovery, and the three pending runtime scenarios. |
| `docs/design/creator-loop-redesign.md` | Updates the implemented design to match the round 4 contracts. |
| `docs/design/creator-loop-round4.md` | Records these findings, file changes, commands, results, and remaining verification. |

Earlier migration files were not changed.

## Commands and results

Read-only inspection used `cat`, `sed`, `rg`, `git status --short`, `git branch --show-current`, `git rev-parse HEAD`, and `git diff`.
The workspace guard passed for the exact checkout and branch. Initial checkout: clean. Final HEAD: unchanged.
The shared evidence helper could not create its directory under the sandbox, so logs use `work/evidence/creator-loop-round4/`.
The command wrapper initially rejected relative log paths; the checks ran after those paths were made absolute.

| Check | Command or operation | Result |
| --- | --- | --- |
| Workspace | `workspace-guard.sh --root <this checkout> --branch redesign/creator-loop` | Passed. |
| Storage | `disk-preflight.sh` | Passed; 38.53 GiB free at the check. |
| Xcode prerequisites | `xcode-proof-preflight.sh` with this source root, branch, evidence directory, and DerivedData/Round4 | Passed. |
| Backend formatting | `deno fmt` on the seven changed TypeScript backend files | Passed. |
| Backend CI | `env -u MCO_LOCAL_DATABASE_URL deno task ci:backend` | Exit 0; type checks passed; 403 tests passed, 0 failed, 2 ignored. |
| Native build | Command below | Exit 74 before compilation; package resolution could not resolve github.com in the sandbox. Xcode also logged restricted cache/service access. |
| Swift syntax | `DEVELOPER_DIR=/Applications/Xcode-27.1-beta.app/Contents/Developer xcrun swiftc -frontend -parse` with all 85 app Swift paths | Passed; syntax only, not a full build. |
| Loop source syntax | `node` calling existing `esbuild.transform` with the TypeScript loader for pocket-loop.e2e.ts and pocket-support.ts | Both passed; no test module or app executed. |
| Diff | `git diff --check` | Passed. |
| Source invariants | Read-only diff checks saved to source-checks.json | Earlier migrations unchanged; no removed accessibility identifiers, added code comments, or Swift test files. |

```sh
DEVELOPER_DIR=/Applications/Xcode-27.1-beta.app/Contents/Developer \
xcodebuild -project CreatorContentOS.xcodeproj -scheme CreatorContentOS \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath DerivedData/Round4 CODE_SIGNING_ALLOWED=NO build
```

Checks ran through `command-watchdog.sh` with absolute stdout and stderr paths under the evidence directory.
Backend output: `backend.stdout.log` and `backend.stderr.log`.
Build output: `build.stdout.log` and `build.stderr.log`.
Syntax output: `swift-reviewed.stdout.log`, `swift-reviewed.stderr.log`, `typescript-syntax.stdout.log`, and `typescript-syntax.stderr.log`.

## Unfinished verification

- The full Xcode build needs a runner with Swift package access. Syntax parsing does not establish type checking or linking.
- The three new loop scenarios and the existing 12 e2e groups and 32 loop tests were not run, as instructed. Their current runtime result is not claimed here.
- MCO_LOCAL_DATABASE_URL was unset for backend CI. No database was contacted. The local database transaction regression was ignored, and the new migration was not applied or executed.
- The other ignored backend test is the existing partial-progress generation-status case.
- SQL and FakeServer changes have source evidence; database and app runtime acceptance remain separate checks.
