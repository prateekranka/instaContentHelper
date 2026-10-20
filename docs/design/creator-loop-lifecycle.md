# Creator loop lifecycle

Implemented through phase 6 of the approved [creator loop redesign](creator-loop-redesign.md).
This document describes the current source and its verification limits. All work remains local.
The separate simulator owner provides runtime evidence. Phase 6 does not run e2e or change simulator state.

## Identity and saved work

A `DayIdentity` contains workspace, creator, and calendar date (`yyyy-MM-dd`).
`DayStore` keeps one `Day` per date for its active workspace and creator.
A `Day` holds its current revision, previous revisions, lifecycle, last known lifecycle, and server timestamp.
Each `DayRevision` owns its content, stable shot IDs, filming progress, and decision.
Today selects the current date. Plan selects the tapped date.
Date-only display uses UTC formatting; selecting Today uses the existing creator-day policy.
A day change does not rewrite a saved revision or an intent's target date.

`DayStoreSnapshot` saves days, archive entries, and the outbox together.
`CachedTodaySnapshot` uses schema version 3 and supplies defaults for missing old fields.
Unreadable or unsupported cache files move to a separate recovery file.
Legacy Today, week, shot marks, and pending decisions migrate into the new snapshot.
Legacy first-idea and accepted-generation UserDefaults values migrate through decode-only models.
Their keys are removed only after the migrated snapshot saves.
A date or the former two-hour cutoff never expires saved work.

## Lifecycle states and transitions

`Day.transition` validates a candidate value before applying it.
`DayStore` also rejects reads that predate local changes. Server timestamps reject older answers.
Identity checks prevent a response for one creator, date, or revision from changing another.

| State | Stored meaning |
| --- | --- |
| `empty` | No current revision exists. Previous revisions can remain. |
| `generating(run)` | A saved request owns this date. An accepted server run ID can arrive later. |
| `draft` | A revision exists but is not available on Today. |
| `ready` | A published revision has no shot marks or final decision. |
| `filming(progress)` | A ready revision owns partial or complete shot marks. |
| `decided(posted \| backup \| skipped)` | The revision has a confirmed local outcome, with a pending outbox marker until server acknowledgement. |
| `unavailable` | No usable ready state is established. Prior content and progress can remain for recovery. |

`loading` is presentation state, not a persisted lifecycle value.
Legacy `shot` maps to complete filming. `savedForTomorrow` maps to the skipped outcome and retains its original date.

| Move | Guard and result |
| --- | --- |
| Start generation | Save the intent first. Only one local generation or replacement can own a date. Existing content requires replacement permission. |
| Finish generation | Require the same target date. Install the new revision and keep the prior revision with its progress. A regular result becomes draft. |
| Fail generation | A terminal failed run resolves its intent. Without a revision, the day becomes empty. A retained archived revision becomes unavailable. |
| Reconcile generation | Read the server's exact date and run. A pre-acceptance failure can retain the old ready package. An accepted failed replacement keeps the old revision archived. |
| Make ready | Require draft state and a revision. Set published status, clear the active decision, and recover that revision's saved filming progress. |
| Mark shots | Require ready or filming state. New marks must be valid shot IDs and must include all existing marks. |
| Mark shot or posted | Require complete filming or a non-filming package. Finishing filming alone does not claim a post. |
| Choose backup or skip | Reject a posted revision or complete filming. Recheck the guard when applying the decision. |
| Undo posted | Target the same posted revision and return to complete filming or text-only ready state. Keep archive text snapshots. |
| Return to draft | Require a ready, filming, or decided revision. Clear its active decision; retain history and shot marks. |
| Edit | Target the current draft or ready revision. Preserve its lifecycle outcome and stable shot IDs. |
| Missing ready package | Keep an active generation. Otherwise demote retained content to draft, or use empty when no revision exists. |
| Removed revision | Move current content to previous revisions and clear the current revision. |
| Unavailable | Save the last known lifecycle and retain recovery data. |
| Authoritative read | Reconcile current revision, lifecycle, and run by identity and version. Preserve pending decisions and locally newer work. |

The server accepts replacement before provider work starts. It does not automatically republish an archived revision after provider failure.
The app does not turn retained recovery content into a ready package without an authoritative answer.

## Outbox and replay

`ContentOutbox.swift` contains the intent models. `DayStore` owns the saved queue.
`AppServices.replayOutboxImmediately` is the single replay entry point.
Launch, foreground, day change, and restored network access wake that loop.
Repeated wake events share the existing task.

| Intent | Saved target and continuation |
| --- | --- |
| `generate` | Creator, date, brief or regeneration input, requested revision, idempotency key, accepted run ID, and completed revision ID. |
| `replaceDay` | The same generation data plus the prior revision ID. The repository calls `replace-day` instead of independent unpublish and generate requests. |
| `firstIdea` | Original date, onboarding data, brief, profile-save state, run ID, and completed revision ID. Continue profile save, generation, and make ready in one intent. |
| `editPackage` | Exact revision, patch, and action: `update`, `makeReady`, or `returnToDraft`. |
| `decide` | Exact revision, decision or undo action, card snapshot, and archive snapshot. |

The client persists an intent before sending it or showing an optimistic decision.
A generation result binds dependent local requested IDs to the server's revision ID.
Dependent work waits while its generation has no completed revision.
Replay retains the same key after a timeout, connection loss, relaunch, or missing answer.
Expected versions are saved and sent; current server behavior remains defined by the server contract.

Success removes the intent after the resulting snapshot saves.
`daily_card_not_found` resolves an explicitly removed target. Terminal generation failures resolve failed runs.
Other errors, including rejected package edits, remain queued and expose an error for later replay.
A failure blocks later requests for that revision during the current pass; other revisions can continue.
No pending request is filtered out because its date is past.

Current posted undo can update the archive decision and decision time while retaining the stored title and caption.
A repeated posted decision returns its original snapshot. Replaced revision history is frozen.
Archive reads use those snapshots instead of joining mutable package text.

## Shots and package validation

`ShotScene` owns dialogue and duration. `ShotScript` builds script text and cumulative timecodes.
Legacy timelines and script text are normalized once shot dialogue exists.
The editor displays one line per numbered shot. Blank lines clear their own shot.
Short input retains later shot lines; extra lines join the final shot.
A scene rename does not change its ID or filmed mark. Duration edits change subsequent timecodes.
Copy actions use real saved script, caption, or audio text and reject empty-state instructions.

Editors block blank script or caption saves. SQL, the edge function, and the fake server reject blank package text.
The same boundaries require an array of shot objects with string `id`, `title`, and `duration`.
Optional `dialogue` must be a string; explicit null is invalid. Existing metadata remains accepted.
Malformed shots return `invalid_package_scene_list` before any part of the edit is saved.
See [the server contract](creator-loop-server-contract.md) for field and shot-index error details.

App-owned UI stays monochrome. Existing Dynamic Type behavior and accessibility identifiers remain in place.

## E2e scenarios and handoff

The scenarios are in `tests/pocket-loop.e2e.ts`; helpers are in `tests/pocket-support.ts`.
The existing `e2e.loop.config.ts` selects that suite. `e2e.config.ts` selects the legacy scenario groups.
The loop suite registers 32 cases, including parameterized states and missing-copy cases.
Each case creates a unique `MCO_QA_SESSION`; relaunch retains that session and replaces its launch arguments.
Tests use TesterArmy mobile UI actions, clipboard reads, and relaunch. They do not call live Supabase.

`FakeServer` saves revisions, current pointers, generation runs, archive entries, and profile preferences per session.
`MCO_LOOP_SCENARIO` seeds the session once. Relaunch reads edited saved state instead of reseeding.

| Seed | Starting data |
| --- | --- |
| `initial` | Existing initial Today fixture and onboarding paths. |
| `ready` | Ten-shot package for today and a separate ready revision for tomorrow. |
| `line-script` | Distinct creator lines migrated into their shots from the legacy script and timeline inputs. |
| `blank-copy` | No script, caption, audio notes, or dialogue timelines. |
| `stale-pointer` | Today's ready package plus yesterday's legacy Today pointer. |
| `legacy-cache` | Fully filmed legacy cache with a pending shot decision and no embedded pending card. |
| `old-decision` | Today's ready revision plus yesterday's revision and its pending posted decision. |

Phase 5 evidence recorded an ambiguous R3-C5 text match and an XCTest session failure during R3-C7 Post clear.
Phase 6 scopes R3-C5 to `shoot.scene.1` containing the saved title.
For Post's script editor, `clearThenType` uses Select All and one keyboard delete, verifies empty text,
then types and verifies the replacement. It does not call the crashing bulk-clear action for that editor.
The blank-save, enabled-save, cancel, and relaunch assertions remain.
These repairs are authored but not runtime-verified in phase 6.

### Finding coverage

IDs preserve the order of the supplied hunt bullets. `L`, `F`, and `C` mean logic, failure path, and contract.
The supplied report has 35 bullets, several with multiple checks. The approved plan calls the combined hunts “40 found bugs.”
The table tracks every supplied bullet, including each compound behavior, without treating that count as runtime proof.
“Partial” means the named UI scenario covers only the stated behavior. The remaining part has a gap ID below.

| Finding | Scenario title fragment or gap | Scope |
| --- | --- | --- |
| R1-1 Scene rename preserves marks | `R1-1: renaming a filmed scene` | UI save and same-session relaunch. |
| R1-2 No easier backup after shot or posted | `R1-2: easier backups stay hidden after shot/posted` | Both states and large-text overflow. Service-level refusal is gap N1. |
| R1-3 Copy only real script, caption, audio | `R1-3: script and caption copy`, `audio copy`, `missing ... never copies` | Exact clipboard values and three missing-field cases. |
| R1-4 UTC calendar formatting | N2 | Requires a controlled device time zone. |
| R1-5 Dead accepted runs and creator ownership | N3 | The fake server models runs; UI coverage still lacks controlled terminal and foreign-run responses. |
| R1-6 Profile first; no premature onboarding | `R1-6: an established creator` plus N4 | Partial: established relaunch. Delayed profile ordering is not injected. |
| R1-7 Plan keeps tapped day, rejects past saved day, isolates async results | `R1-7: Plan keeps the tapped day`, `an async generation stays` plus N2 | Partial: selection, relaunch, and async generation. Past saved selection needs a day-change seam. |
| R1b-1 Failed decision retained and retried | `R1b-1: a failed posted decision` plus N5 | Partial: one failure and successful replay after relaunch. Repeated refresh failures need a controllable failure queue. |
| R1b-2 No past cached Today; retry and day/foreground refresh | N5, N6 | Stale-pointer coverage is tracked separately under R3-C4. |
| R1b-3 Creator script lines win | `R1b-3: the Script tab uses the creator lines` | First and last shot assertions. |
| R1b-4 Failed replace restores old idea | `R1b-4 R2-4: failed replacement restores the title` | Normal recoverable fixture failure. |
| R1b-5 First idea retries after close or failure | `R1b-5 R3-C6: a failed first idea` plus N7 | Partial: relaunch after an observable failure. Mid-request termination needs a barrier. |
| R2-1 Old unsynced decision keeps its card after midnight | `R2-1: an older pending decision` plus N6 | Seeded post-boundary state: replay yesterday's decision while today's package stays ready. Exact day-change delivery remains uncovered. |
| R2-2 Retry preparing first idea; promote complete draft | N7 | Profile and handoff are durable; deterministic mid-handoff UI barriers remain absent. |
| R2-3 Retain accepted run on timeout/network; remove ended or old runs | N3 | Outbox migration and replay no longer expire runs by age. |
| R2-4 Restore decision and scene marks after failed overwrite | `R2-4: a failed replacement restores a posted decision`, `R1b-4 R2-4` plus N8 | Partial: normal failure. Persisted interruption and recovery-network failure need a barrier. |
| R2-5 Refresh empty/unavailable Today on new day | N6 | No virtual date or network-failure seam. |
| R2-6 Edited script takes precedence; unedited timing stays | `R1b-3: the Script tab`, `R2-6: an unedited script` | Distinct lines plus all ten original timed rows. |
| R2-7 Fixture archive keyed by card; Plan edits update saved draft | `R3-L1 R2-7: posting a replacement`, `R2-7: a future caption edit` | Two archive revisions, saved/copyable caption, and relaunch. |
| R3-L1 Posted history changes on replacement | `R3-L1 R2-7: posting a replacement` plus N9 | Fixture archive behavior; real revision and snapshot rules have separate local SQL checks. |
| R3-L2 Interrupted first idea lost after midnight | N7 | The handoff is durable; there is no controlled day change during acceptance. |
| R3-L3 Word/paragraph edit shifts shot dialogue | `R3-L3: one word`, `R3-L3: a paragraph edit` | Supplied ten-shot, nine-line fixture; assert shot two and final dialogue. |
| R3-L4 Saved durations leave old timecodes | `R3-L4: a saved scene duration` | Assert first range and cumulative next range after relaunch. |
| R3-F1 New decision overwrites old unsynced decision | `R3-F1: a new decision cannot erase` | Seed yesterday's pending A, observe its failed retry, decide B, then require both archive records after relaunch. |
| R3-F2 Interrupted overwrite loses progress | N8 | No deterministic server-acceptance or failed-recovery barrier. |
| R3-F3 First-idea and accepted-run recovery collide | N7 | No shared accepted-run/profile synchronization barrier. |
| R3-F4 First retry resumes terminal dead run | N3 | The fake server supports failed runs; no UI seed forces terminal failure and then observes a fresh run key. |
| R3-C1 Old cache cannot decode pending card | `R3-C1: an old pending-decision cache` | Legacy file is seeded in-app before normal cache loading. Assert filmed state and archive replay. |
| R3-C2 Restored published future package displays old edit | N10 | The fake server restores current packages; there is no isolated restored-summary response scenario. |
| R3-C3 Fixture draft resurrects Posted | `R3-C3: edit, unpublish, and make ready` | Edit a posted revision, unpublish, approve, and relaunch. |
| R3-C4 Fixture Today keeps yesterday | `R3-C4: a stale fixture pointer` plus N6 | Seeded post-boundary state and relaunch; exact midnight notification remains uncovered. |
| R3-C5 Initial ready fixture absent from writable store | `R3-C5: the initial ready fixture` | Uses `initial`, without the writable `ready` seed. |
| R3-C6 Fixture preferences/handoff lost on relaunch | `R3-C6: onboarding interests`, `R1b-5 R3-C6: a failed first idea` plus N7 | Selected interest and failed first-idea recovery. Preparing handoff interruption remains uncovered. |
| R3-C7 Blank edit contracts differ | `R3-C7: Plan blocks`, `Shoot Folio blocks`, `Post refuses` plus N9 | UI validation in three editors; SQL and edge validation have separate backend checks. |
| R3-C8 Offline unpublished placeholder restored as ready | N11 | No fixture read-failure mode after a successful unpublish. |

## Remaining runtime coverage limits

These gaps describe missing deterministic UI evidence, not known failures in the implemented source.
The phase 0 predictions are superseded by the phase 1–6 code and must not be read as current failures.

| Gap | Remaining trigger or assertion |
| --- | --- |
| N1 | A backup confirmation opened before the revision becomes fully filmed or posted. The UI suite lacks a stale-confirmation seed. |
| N2 | UTC display in a controlled negative-offset zone and rejection of a saved Plan date after a day change. No virtual clock or zone seam exists. |
| N3 | Foreign runs, transport loss after acceptance, terminal failure, and a fresh retry key. Fake-server run persistence exists; the UI suite lacks controlled response barriers. |
| N4 | Delayed or failed profile reads with an observable loading state. Immediate fixture reads cannot prove the absence of an onboarding flash. |
| N5 | Repeated decision failures and controlled acknowledgements for two revisions. The existing one-failure flag does not provide a full response queue. |
| N6 | Exact midnight and foreground rollover from empty or unavailable. Stale-pointer coverage proves only the post-boundary lookup. |
| N7 | Termination between profile save, generation acceptance, and make ready, including a day change. Durable handoff exists; deterministic interruption barriers do not. |
| N8 | Termination after replacement acceptance and before completion, followed by failed recovery reads. Ordinary pre-acceptance fixture failure has a different result. |
| N9 | Applying the SQL migrations and exercising the deployed HTTP/database path. Local Deno checks use injected clients; the optional rollback SQL test requires a local database. No live target is permitted. |
| N10 | A server-restored future package loaded through a specific weekly-summary response. The former duplicated client summary is gone, but the UI case does not isolate that hydration path. |
| N11 | Successful unpublish, termination, then unavailable-read relaunch. Authoritative empty results differ from a transport failure. |

## Phase 6 verification

`deno task ci:backend` passed: 403 tests passed, none failed, and two checks were ignored.
The local database transaction test had no local database URL; another generation test is already ignored in the suite.
The new rollback SQL assertions exist but were not executed against a database in this phase.
The requested Xcode build uses `DerivedData/Phase6` and Xcode 27.1 beta.
The build could not finish. Offline packages matched all seven pinned revisions, but Swift package manifest loading
failed with `sandbox-exec: sandbox_apply: Operation not permitted` in this restricted session.
All 85 app Swift files passed a syntax parse. This does not replace a successful build.
No e2e run, simulator action, live database access, migration application, or deployment occurs in phase 6.
Build and backend success do not establish runtime acceptance or zero creator-facing bugs.
