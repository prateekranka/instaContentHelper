# Step 5 performance and database review

Worktree: ContentHelper `redesign/creator-loop`, starting at `8daa6b18322a32ae409fd4731c2e341fd25dbb2f`.
Date: 2026-10-21. Scope: local source changes and local command checks.
The approved plan is [creator-loop-redesign.md](creator-loop-redesign.md).

The supplied profile covered 75 seconds and 10,007 main-thread samples at 1 ms.
It reported a 271 ms hang on the first Today presentation and a 295 ms hang on sheet presentation.
Most sampled hang time was in SwiftUI graph updates. These are supplied baseline measurements.
This step did not repeat the profile or run the app. It does not establish a measured speed improvement or continued e2e acceptance.

App findings and changes:

| Finding | Evidence | Resolution and reason |
| --- | --- | --- |
| Repeated DailyCard construction. | Baseline: 262 inclusive samples in `AppServices.todayCard`, 232 in `DayRevision.dailyCard`, and 231 in `GeneratedDailyCardDraft.dailyCard(completionState:)`. | Fixed in source. `DayStore.projection(for:revisionID:)` caches the card by date and revision ID. Successful transitions and restores invalidate that date. Content, completion, progress, thumbnail, replacement, and undo changes all pass through these paths. Cache reads still read observable `days`, so the cache does not suppress view invalidation. |
| Scene counts repeat the same scan. | Baseline: 120 samples in `areAllScenesShot`, 93 in `unshotSceneCount`, and 69 in `shotSceneCount`. The old count closure also fetched `shotSceneIDs` for every scene. | Fixed in source. `DayCardProjection` captures the shot-ID set once and derives the counts and completion flag once. Today, filming, and Post callers use that same projection. Empty and unavailable cards keep zero counts and a false completion flag. |
| DateFormatter and ISO8601DateFormatter allocation repeats. | Baseline: 221 samples in `contextLine`, 110 in `parseDate`, and 77 in today-date helpers. See `SupabaseDTOs.swift`, `SupabaseDateFormatting`. | Fixed in source. Calendar-day formatters are cached by format and time-zone identifier. A mutex protects construction and use. Date-only labels and arithmetic retain UTC semantics. Today resolves the current client time-zone identifier on every call, with UTC fallback, so a zone change cannot reuse a formatter for the old zone. The timestamp formatter is also reused. Existing output formats and fallback strings stay the same. |
| Snapshot encoding, validation, and file writes run on the main thread. | Baseline: 64 samples in `FileTodayCacheStore.saveSnapshot` through `AppServices.persistDaySnapshot`, including outbox replay. | Fixed in source. The file store uses one serial dispatch queue for file access. Its async save suspends the main actor while validation, encoding, and atomic replacement run on that queue. Existing synchronous setup/cache APIs remain available. The schema, atomic write option, and unreadable-file preservation stay the same. |
| Async saves can complete in the wrong order. | Moving each old synchronous save into an independent task would allow an earlier captured snapshot to overwrite later state. | Prevented in source. `queueDaySnapshot` captures the immutable value on the main actor and chains its write task after the previous task. Each write waits for the prior write to finish, including failure. A later full snapshot can recover from an earlier failure. File operations also use the serial file queue. |
| Async persistence introduces suspension points in outbox handling. | `enqueueIntent`, decision preparation, legacy migration, accepted-run persistence, and `finishIntentPersisting` previously depended on synchronous disk completion. | Preserved in source. These paths now await their save. Decision preparation is serialized, revalidates the current revision, and saves the intent before applying the optimistic decision. Replay runs legacy migration inside the single replay task. `drainOutbox` awaits a fresh save before each send and checks that the intent still exists afterward. Accepted run IDs and terminal states are saved before continuation or cleanup. Failed enqueue/finish operations change only their own intent and queue a recovery snapshot. |
| Foreground cache reload can restore an older snapshot while writes wait. | The async queue can have captured state that has not reached disk when `loadTodayFromCache` is called. | Prevented in source. While writes are pending, the current DayStore remains authoritative. The reload returns the current day's availability without restoring older disk state. |
| SwiftUI view bodies account for remaining cost. | Baseline: 97 samples in `TodayShootSessionView.body`, 73 in `ShootFolioView.body`, and 56 in `TodayView.body`. | View files were left unchanged. Their shared card/count reads now use the store cache. Further layout or view-identity changes need a new profile. No visible copy, accessibility identifier, color, or Dynamic Type code changed. |

Database review inputs:

- All six redesign migrations, `20261020160000` through `20261021120000`, were read in order.
- `supabase/functions/replace-day/index.ts`, `generate-week/generation-idempotency.ts`, and `_shared/creator-loop-db.sql` were read in full.
- The older function definitions, relevant RLS helpers and policies, existing indexes, device authentication, and read/generation entry points were traced.
- The supplied `supabase db lint --local` result was clean. The supplied advisor results are baseline evidence, not commands rerun in this step.
- No local schema or data was changed. No live database, live Supabase project, or deployment was accessed.

Database findings:

| Finding | Evidence | Fixed or not, and why |
| --- | --- | --- |
| Five older functions have mutable search paths. | `20260630170000_touch_plan_on_review_state.sql:5`, `20260703160000_parallel_generation_day_job_leases.sql:163`, `20260704112000_enforce_parallel_day_job_lane_cap.sql:10,78`, and `20260707110000_weekly_generation_run_liveness.sql:21` define the five advisor-listed functions without `SET search_path`. These functions are invoker functions, not security-definer functions. Their table references are already qualified with `public`. | Fixed by five `ALTER FUNCTION ... SET search_path = ''` statements in the new migration. The claim signature has five arguments; the reclaim signature has six. Queue behavior and function security mode are unchanged. |
| Two older trigger functions retain default public EXECUTE access. | The touch-plan and run-updated-at functions are created without a later EXECUTE revoke. PostgreSQL grants EXECUTE to PUBLIC by default. Both return `trigger`, so this is unnecessary privilege rather than a demonstrated callable data-access exploit. | Tightened in the new migration. Revoke EXECUTE from PUBLIC, anon, and authenticated; retain service-role EXECUTE. Existing triggers stay attached. The queue functions already revoke client EXECUTE and retain service-role access. |
| Redesign security-definer function search paths. | `20261020160000_creator_loop_revisions.sql` fixes paths on all new definer functions. `20261020161000_creator_loop_mutations.sql` fixes all its functions; `publish_day_atomic` uses fixed `public`, and the other functions use the empty path. Later redefinitions retain the empty path. Table references are schema-qualified. | No missing fixed path found in the six migrations. No old migration was edited. The fixed `public` setting on `publish_day_atomic` was left unchanged because this review did not confirm a caller-controlled object lookup in its body. |
| Redesign RPC grants. | `20261020160000_creator_loop_revisions.sql:269` and `20261020161000_creator_loop_mutations.sql:519,541` revoke client EXECUTE. The old write helper is explicitly revoked from service_role too; only the definer wrapper calls it. Later `CREATE OR REPLACE` definitions preserve function privileges. | No wide anon/authenticated grant found on the reviewed redesign read or mutation RPCs. Existing service-role-only grants remain unchanged. |
| RLS enabled with no policy on creator_days. | `20261020160000_creator_loop_revisions.sql:28` enables RLS, revokes all client table access, and grants service_role access. `read_creator_days`, revision triggers, and generation RPCs use definer paths. The generation recovery query uses the verified edge-function admin client. | Correct by design. No client policy was added. A policy would expand access to a service-only table. |
| RLS enabled with no policies on generation runs and jobs. | `20260606103000_grant_weekly_generation_runs.sql` and `20260624003000_weekly_generation_day_jobs.sql` enable RLS and grant service-role table access. Queue RPCs are service-role-only invoker functions. Generation entry points authenticate the device before admin-client access. | Correct by design. RLS denies ordinary client row access without a policy. No policy was added. This conclusion is from migration and caller source; this step did not query current database grants. |
| Cross-workspace access through the reviewed edge/RPC paths. | `_shared/device-auth.ts:24` resolves a hashed active device token and an active member in the installation's workspace. `read-content/index.ts:87,124` checks the creator in that workspace. Generation replay filters both verified workspace and creator. `replace-day` delegates to that authenticated handler. New mutation RPCs filter workspace plus creator before card/run changes. The creator-day revision FK also includes workspace and creator. | No cross-workspace path found in this scope. Direct authenticated table policies use `auth.uid()` membership and workspace-role checks. Workspace owners/editors can manage creators within their workspace by design; creator-ID-only isolation within one workspace is not the existing permission model. No policy was widened or removed. |
| creator_days generation-run FK lacks a child index. | `20261020160000_creator_loop_revisions.sql:20` adds `generation_run_id`. Its primary key starts with workspace and creator, and no existing child index starts with generation_run_id. Parent deletion or referenced-key updates can scan the child table. | Fixed with `creator_days_generation_run_id_idx(generation_run_id)`. This is a full index, not a partial index. |
| creator_days current-revision composite FK lacks a matching child index. | `20261020160000_creator_loop_revisions.sql:23` references `(workspace_id, creator_id, current_revision_id)`. The existing child primary key ends in scheduled_date instead. | Fixed with `creator_days_current_revision_fk_idx(workspace_id, creator_id, current_revision_id)`. This covers the full FK and reverse revision-pointer lookup. |
| Archive reads lack an index matching the visible-history filter. | `read-content/index.ts:322` filters workspace, creator, and five decision values, orders by archive_date descending, and limits to 50. The older creator/date index includes `replaced` entries. Repeated replacements can force it to skip growing numbers of hidden rows. | Fixed with `archive_entries_visible_workspace_date_idx(workspace_id, creator_id, archive_date DESC)` and the same five-decision predicate. Existing indexes remain. This is a source-confirmed index mismatch; no measured query-plan improvement is claimed. |
| creator_days workspace/creator/date hot lookup. | The primary key is already `(workspace_id, creator_id, scheduled_date)`. `start_day_generation` and the recovery handler use these predicates. `read_creator_days` uses the workspace/creator prefix. | Already covered. No duplicate day-key index was added. |
| Current daily_cards and revision-ID reads. | `daily_cards_current_day_key(workspace_id, creator_id, scheduled_date) WHERE is_current` covers Today and replacement lookup. `daily_cards.id` is the primary key for the `read_creator_days` current-revision join. `daily_cards_run_date_revision_key(generation_run_id, scheduled_date)` covers persisted-run replay. | Already covered. No duplicate current-day or revision-ID index was added. |
| Full-table scans and unbounded RPC results. | The reviewed mutation RPCs use primary keys, the day key, the generation idempotency unique key, or the run/date index. Queue claims use generation-run/status/day-index indexes. Scene validation iterates request JSON, not a database table. `read_creator_days` aggregates every day for one workspace/creator. | No unscoped all-workspace runtime table scan found by source review. FK scans are addressed above. The creator-day read remains unbounded within one creator. Adding pagination would change the recovery contract and is outside this migration. No EXPLAIN was run; PostgreSQL can choose sequential scans on small local tables. One-time migration backfills are not hot RPCs. |
| Existing SQL regression coverage. | `_shared/creator-loop-db.sql` uses `BEGIN` and `ROLLBACK`, checks revision/decision immutability and atomic replacement, and checks two service-only EXECUTE privileges. It inserts only local test rows. It does not cover every grant, RLS role, index, or query plan. | Reviewed only. It was left unchanged. The user will run it after applying the new migration locally. |
| Other unindexed foreign keys and unused indexes. | The supplied advisor output reports 21 unindexed FKs in total; only the two creator_days findings belong to the redesign table. Local unused-index statistics do not represent production load. | Older-table FK changes remain outside this step. Unused-index findings were ignored as requested. |

The only new migration is [20261021130000_step5_performance_and_database.sql](../../supabase/migrations/20261021130000_step5_performance_and_database.sql).
It contains five search-path changes, two trigger-function privilege changes, and three indexes.
It does not change function bodies, policies, rows, or old migrations. It has not been applied.

Files changed:

| File | One-line purpose |
| --- | --- |
| `CreatorContentOS/App/AppServices.swift` | Read cached card/count projections and coordinate ordered async snapshot saves, durable outbox replay, and serialized decision preparation. |
| `CreatorContentOS/Data/TodayCacheStore.swift` | Cache revision projections and perform snapshot validation, encoding, and atomic file replacement on a serial background queue. |
| `CreatorContentOS/Data/SupabaseDTOs.swift` | Reuse synchronized date/timestamp formatters keyed by format and time zone. |
| `supabase/migrations/20261021130000_step5_performance_and_database.sql` | Fix confirmed older search paths, reduce trigger-function privileges, and add the two FK indexes plus the visible Archive index. |
| `docs/design/step5-performance-and-database.md` | Record performance changes, database evidence, commands, and verification limits. |

Commands and results:

| Command | Result |
| --- | --- |
| `workspace-guard.sh --root "$PWD" --branch redesign/creator-loop`, `git status --short`, `git rev-parse HEAD`, and `git remote -v` | Correct worktree, branch, origin, clean starting tree, and expected HEAD. |
| `cat`, `sed`, `rg`, `rg --files`, and `wc -l` on the approved plan, rules, Swift source, migrations, SQL regression file, and backend handlers | Read all three changed Swift files end to end and completed the source traces above. |
| `evidence-path.sh --root /Users/prateekranka/.codex/evidence --label contenthelper-step5` | Shared evidence location was not writable in this sandbox. |
| `evidence-path.sh --root "$PWD/work/evidence" --label step5-performance-database` | Created the task-local evidence directory linked below. |
| `disk-preflight.sh` and `xcode-proof-preflight.sh` with this worktree/branch and task-local evidence | Passed. Free disk space remained above the 10 GiB gate. |
| `deno task ci:backend`, working directory `supabase/functions`, through `command-watchdog.sh --timeout-seconds 240` | Exit 0. Type checking passed; 403 tests passed, 0 failed, 2 ignored. Deno resolved the root `deno.json` task. The local database test was among the ignored checks; this result does not validate the migration against PostgreSQL. |
| Two generic-iOS Debug builds with `-resultBundlePath`, through the watchdog | Both compiled, linked, produced the app, and printed `BUILD SUCCEEDED`; both exited 133 while serializing the result bundle. The crash summaries identify `IDESchemeActionDeviceRecord.v3_snapshot(to:)` and `ResultBundleWriter.takeSnapshot`. The result bundles are not reliable proof artifacts. |
| Final generic-iOS Debug build without explicit `-resultBundlePath` | Exit 0 and `BUILD SUCCEEDED`. The final source builds with Xcode 27.1 beta. No simulator or app runtime was used. |
| `git diff --check` | Passed after the final source edits. |
| Final `git status --short`, `git rev-parse --short HEAD`, and a Python diff/scope check | Exactly three Swift files, one new migration, and this report changed. HEAD remains `8daa6b1`. No added Swift comments or accessibility identifier edits. |

Every xcodebuild invocation used `DEVELOPER_DIR=/Applications/Xcode-27.1-beta.app/Contents/Developer`.
The build arguments were:

```sh
xcodebuild -project CreatorContentOS.xcodeproj -scheme CreatorContentOS \
  -configuration Debug -destination generic/platform=iOS \
  -derivedDataPath "$PWD/DerivedData/Step5Performance" \
  -clonedSourcePackagesDirPath "$PWD/DerivedData/Phase5/SourcePackages" \
  -packageCachePath "$PWD/DerivedData/Step5Performance/PackageCache" \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -IDEPackageSupportDisableManifestSandbox=YES \
  'OTHER_SWIFT_FLAGS=$(inherited) -Xfrontend -disable-sandbox' \
  CODE_SIGNING_ALLOWED=NO build
```

The environment also set `CFFIXED_USER_HOME`, `CLANG_MODULE_CACHE_PATH`, and `SWIFTPM_MODULECACHE_OVERRIDE`
inside `DerivedData/Step5Performance`. The first two builds additionally supplied separate `.xcresult` paths.
No source, cache, or simulator cleanup command was run.

Evidence: [step5 command logs and crash summary](../../work/evidence/step5-performance-database/20261021T071509Z.WmJGOE).
Build product: `DerivedData/Step5Performance/Build/Products/Debug-iphoneos/ContentHelper.app`.

Repeatable build friction:

- Symptom: xcodebuild exits 133 after a successful build when writing an explicit result bundle.
- Tried fixes: the final source was rebuilt with a new result-bundle path; the same serialization crash repeated.
  Crash stacks localized it to result-bundle device-record serialization.
  Recovery options considered were omitting explicit bundle output, pinning bundle version 3, changing the destination,
  or using a different Xcode. The stack already uses v3. Device changes and a different Xcode would expand this task.
  [Apple documents result bundles as an optional xcodebuild output](https://developer.apple.com/videos/play/wwdc2019/413/).
- Latest working fix: Omit explicit `-resultBundlePath` for this compile-only build. The final build exited 0 and printed `BUILD SUCCEEDED`; stdout/stderr remain durable evidence.
- The global papercut log is outside the writable sandbox. This report keeps the local record.

Remaining verification:

- The new migration awaits the user's local reset, database regression run, and advisor check.
- The two supplied profiler hangs need a new runtime profile to confirm their duration after these changes.
- e2e was not run, as requested. No Swift unit tests or new test files were written.
- No UI source, accessibility identifier, visible copy, or app-owned color was changed.
- No commit, push, history change, live database access, or deployment occurred.
