# Creator loop lifecycle

Phase 0 contract for the approved [creator loop redesign](creator-loop-redesign.md).
This document describes the required behavior. It does not claim that the current app implements it.
All work in this phase is local. No Supabase changes or deployments are required.

## Identity and saved work

A `Day` belongs to one workspace, creator, and calendar date (`yyyy-MM-dd`).
A revision identifies one generated content package. Replacement creates a new revision ID.
A date has one current revision pointer. Older revisions and their filming progress remain addressable.
Many historical revisions for a date are valid; two current revisions are not.

Today selects the current calendar date. Plan selects the date the creator taps.
Parse and display a date-only value in UTC. Determine the current date using the existing creator-day policy.
Do not convert a stored date-only value through the device time zone when displaying it.
A day change changes the Today selection. It does not change any saved Day or intent's date.
If a first idea finishes for a past date, keep it on that original Day.
Do not show it as today's package. A new idea for today requires a new request.

The outbox is the saved queue of unfinished requests. It contains the five intent kinds in the approved plan:

| Intent | Target and saved input | Completion |
| --- | --- | --- |
| `generate` | Creator, date, requested revision identity, brief, idempotency key, accepted run identity when available | Server returns the complete draft, terminal failure, or revision removal. |
| `replaceDay` | Creator, date, old revision, new request identity, brief, prior progress reference, idempotency key | One server transaction accepts replacement; the same intent follows its run to completion. |
| `firstIdea` | Creator, original date, onboarding preferences and profile handoff, requested revision, brief, idempotency key | The profile is saved, generation completes, and that revision becomes ready. |
| `editPackage` | Creator, date, revision, edit action and values, expected version, idempotency key | Server returns the canonical package and lifecycle, or rejects the request. |
| `decide` | Creator, date, exact revision, decision or explicit undo action, immutable decision snapshot, idempotency key | Server confirms the decision or undo against that revision. |

An empty Day has no revision to target. Save its requested revision identity with the generation intent.
The server must bind its accepted revision ID to that identity before dependent work replays.
Do not send dependent edits or decisions against a placeholder ID.

The approved intent list does not name separate approval or unpublish intents.
This contract uses `editPackage` with an explicit `makeReady` or `returnToDraft` action for those transitions.
It uses `decide` with an explicit undo action for Undo posted.
These action names describe the contract; they are not new API endpoints in Phase 0.
Later client and server phases must use the same action contract.

Persist an intent before presenting its optimistic result or sending its request.
Replay the same key after a timeout, connection loss, relaunch, or missing answer.
A new brief or explicit new attempt after a terminal failure creates a new key.
Do not reuse a failed run for a new brief.

## Day states

| State | Meaning | Allowed content actions |
| --- | --- | --- |
| `empty` | A successful authoritative read says the date has no current package. | Generate, or complete a pending first idea. |
| `generating(run)` | A saved request is awaiting acceptance, running, or awaiting its final answer. The run can initially lack a server run ID. | Observe progress and plan another date. Retry observation with the same intent. |
| `draft` | A complete generated revision exists. It is not available on Today. | Review, edit, make ready, or confirm replacement. |
| `ready` | A revision is approved for its date. It has no active final decision or filmed shots. | Film, edit, copy real text, decide for a text-only package, choose a backup, skip, unpublish, or confirm replacement. |
| `filming(progress)` | The ready revision owns shot marks. Progress can be partial or complete. | Mark shots, resume filming, edit shot lines and durations, copy, post when complete, unpublish, or confirm replacement. |
| `decided(posted \| backup \| skipped)` | The creator confirmed an outcome for this revision. A posting decision records an immutable history snapshot. | View, copy, light edit where allowed, explicit Undo posted, unpublish, or confirm replacement. |
| `unavailable` | The app cannot determine the authoritative state and has no usable snapshot for this date. | Try again. Retain the last known revision, progress, and pending intents as recovery data. |

`loading` is a presentation condition during a read. It is not another saved Day state.
An unavailable Day can retain a last known lifecycle for recovery. It must not expose that data as a ready package.
If a valid snapshot proves the state, a network failure keeps that state with an offline indicator.
A missing or unpublished placeholder never proves `ready`.

Legacy `shot` completion maps to `filming(complete)`, not `decided(posted)`.
Legacy backup and intentional-skip decisions map to `decided(backup)` and `decided(skipped)`.
The legacy `savedForTomorrow` value must retain its original revision and date during migration.
It is not permission to rewrite an intent's target date or erase history.

## Legal transitions

This table is exhaustive for cross-state moves. All unlisted moves are rejected.
The next table defines legal updates that keep the same state.
“No new intent” permits replay of an existing intent; it does not permit dropping it.

| From | To | Trigger and guard | Outbox effect |
| --- | --- | --- | --- |
| `empty` | `generating(run)` | User selects an idea, or first-idea recovery finds a saved request. No other generation owns this date. | Save `generate` or `firstIdea` before sending. |
| `draft`, `ready`, `filming`, `decided` | `generating(run)` | User confirms replacement. Save the old revision and progress. Server accepts the atomic replacement. A pending local request can show generation progress without clearing that saved data. | Save one `replaceDay`; never save an independent unpublish request for replacement. |
| `generating(run)` | `draft` | Server returns a complete package for this creator, date, request, and revision. | Complete `generate` or `replaceDay`. Keep `firstIdea` pending until approval completes. |
| `generating(run)` | `empty` | Server ends generation without a draft and confirms no current revision exists. | Record terminal failure, then acknowledge the failed intent as finished. A retry creates a new intent. |
| `generating(run)` | `draft`, `ready`, `filming`, `decided` | Failure recovery receives an authoritative answer restoring the prior revision, or a fresh read proves an existing committed result. Restore that revision's progress and decision. | Finish the old intent only on an authoritative terminal result. Do not issue a new decision to guess recovery. |
| `draft` | `ready` or `filming(progress)` | User approves the complete revision and the server accepts `makeReady`. Restore saved progress if this revision has filmed shots. First-idea recovery promotes an existing complete draft instead of generating again. | Save `editPackage(makeReady)`, or continue the existing `firstIdea` with the same identity. |
| `ready` | `filming(progress)` | User marks a shot. Starting the filming screen alone need not change the saved state. | No server intent for a local shot mark; save progress atomically with the Day snapshot. |
| `ready` | `decided(posted)` | User confirms a post for a package that needs no filming. The revision and real text exist. | Save `decide(posted)` with the exact revision and history snapshot. |
| `filming(complete)` | `decided(posted)` | User confirms that the post is live. | Save `decide(posted)`. Finishing filming alone does not claim a post. |
| `ready`, `filming(partial)` | `decided(backup)` | User confirms a backup as posted. Previewing a backup does not decide anything. Backup eligibility still holds at confirmation time. | Save `decide(backup)` with the original revision and selected backup snapshot. |
| `ready`, `filming(partial)` | `decided(skipped)` | User explicitly confirms a skip. | Save `decide(skipped)`. |
| `decided(posted)` | `filming(complete)` or `ready` | User chooses Undo posted. Return to filmed content or a text-only ready package. Keep the historical posting snapshot. | Save `decide(undoPosted)` against the same revision. |
| `ready`, `filming`, `decided` | `draft` | User explicitly confirms Unpublish, and the server accepts `returnToDraft`. Clear the active decision. Retain historical decisions and saved progress under their revision. | Save `editPackage(returnToDraft)`. |
| Any known state | `unavailable` | A read or recovery fails and no valid snapshot can establish this date's state. A different date's cached card is not usable. | No new intent. Retain every pending intent and prior recovery record. |
| `unavailable` | `empty`, `generating`, `draft`, `ready`, `filming`, `decided` | Try again, foreground, relaunch, day change, or network return produces a valid snapshot or authoritative answer for this exact date. | Replay saved intents. Complete only those the server explicitly resolves. |
| Any state | `empty`, `generating`, `draft`, `ready`, `filming`, `decided` | Initial hydration, a refresh, or another session's committed change returns an authoritative version for this Day. Reject stale or mismatched answers. Reconcile pending local work before displaying the result. This row permits server reconciliation, not arbitrary user transitions. | No new intent. Keep pending work unless the answer explicitly acknowledges its key or removes its target revision. |
| Any state | `empty` | Server explicitly confirms that the current revision no longer exists and no replacement is current. Keep historical revisions and archive records. | Finish intents targeting the removed revision with the explicit removal result. Do not clear other revisions' intents. |

A successful first idea can move through `generating → draft → ready` in one replay pass.
Each intermediate result must remain recoverable if the process stops between server answers.
An optimistic decision retains its pending marker until the server acknowledges it.
A failed decision does not undo the creator's local choice.
A rejected package edit retains the previous canonical package and exposes the error.

## Same-state updates and external events

| State or event | Required result | Outbox effect |
| --- | --- | --- |
| `generating`: accepted, still running, timeout, or connection loss | Keep the request and accepted run identity. Poll or replay the same operation. A missing answer is not terminal failure. | Keep the existing intent. |
| `draft`, `ready`, `filming`, or `decided`: valid light edit | Apply the canonical server answer to the same revision in every screen. Preserve shot identity and marks. Posted history snapshots stay unchanged. | Save `editPackage`; order it with other intents targeting this revision. |
| Blank script or caption edit | Block Save and show a useful validation message. The fake and real server reject any bypass. Do not display a deletion that the server ignored. | No intent from a blocked editor; a rejected request finishes with an explicit validation error. |
| `filming`: another shot mark or scene rename | Keep marks on stable shot IDs. A rename does not create a new shot. Completion keeps the package in `filming(complete)`. | No new server intent for local progress; save the snapshot. |
| Script or duration edit | Edit dialogue on its shot. Build full script from shot lines. Derive every cumulative timecode from durations. Never map a changed paragraph back onto shots by line index. | Save `editPackage` with shot changes. |
| Backup preview, copy, navigation, or cancelled overwrite | Keep the current revision, lifecycle, and progress. Copy only stored script, caption, or audio text. | None. |
| Day change | Select the new Today Day, including when the previous selection was empty or unavailable. Load its saved revision or fetch it. Retain all older Days. | Replay the whole creator's saved queue; do not filter it to today. |
| Relaunch | Restore the versioned snapshot and all intents before new network work. Load the profile before deciding whether onboarding is required. Restore Plan's selected date unless it is now past. | Start the single replay loop. Do not start a competing first-idea or accepted-run recovery task. |
| Foreground or network return | Refresh stale, empty, or unavailable Today. Reconcile server results by creator, date, revision, and request identity. | Wake the same replay loop. Repeated wake events cannot create another loop. |
| A new Day loads while an older decision still fails | Keep both Days and both decisions independently. A new decision cannot replace an older pending slot. | Append a separate `decide` intent; preserve ordering per revision. |
| Another creator's accepted run or answer arrives | Ignore it for the active creator. Keep each creator's saved work isolated. | Never replay or acknowledge another creator's intent. |
| Terminal generation failure | Display the failure, resolve that failed request, and permit a new attempt with a new key immediately. | Finish the failed intent; never resume its dead run on the first retry. |

## Invariants

1. One Day has one current revision at a time. One generation or replacement owns that date at a time.
2. Today, Plan, Filming, Post, and Archive read from one `DayStore`. Async results update their original Day and revision.
3. Replacement creates a new revision ID. It cannot reuse a posted revision's row or overwrite its history.
4. Posted history never changes. Capture the title, caption, revision, decision, and decision time in the posting record.
5. Undo and unpublish change the active lifecycle. They do not rewrite a prior posting snapshot.
6. Shot marks belong to stable shot IDs within a revision. Renames, retries, and failed replacement preserve them.
7. Save the prior revision and progress before replacement. Neither a placeholder nor local stack variables are recovery storage.
8. An intent never expires because its date is past, including `firstIdea`, decisions, and replacement recovery.
9. An intent leaves the queue only after an explicit server result: done, done with terminal failure or rejection, or target revision removed.
10. A timeout, transport error, old run age, or relaunch is not such a result. Resolve old accepted runs with the server.
11. The former two-hour accepted-run cutoff is a migration regression to track, not a date or age expiry rule for the new outbox.
12. Every intent has its own idempotency key, creator, date, revision identity, payload, and replay status. No global pending-decision slot exists.
13. One replay loop owns retries. It handles a first-idea accepted run and its promotion as one operation.
14. Old cache fields can be absent. Decode them with explicit defaults and migrate recoverable card IDs, decisions, and progress.
15. Keep undecodable cache data aside. Do not overwrite the only recovery copy during a later refresh.
16. Cache the lifecycle and schema version. A current-date placeholder cannot restore ready-card actions.
17. Never show a past cached package as Today. A pending decision for that package still replays against that original revision.
18. The fixture server persists content, revisions, progress, profile preferences, and first-idea handoff per `MCO_QA_SESSION`.
19. A fixture card visible as editable must exist in its writable repository. Today must resolve by current date, not a stale pointer.
20. Fixture and real servers share input validation, canonical answers, lifecycle rules, and error behavior.
21. Blank package text is rejected consistently. Successful saves display and copy the canonical saved text after navigation and relaunch.
22. Shots own their dialogue and duration. A one-word change cannot shift later shots or erase the last shot's dialogue.
23. Hide easier backups after all shots are complete or the revision is posted. Check eligibility again when applying a decision.
24. Copy actions never copy empty-state instructions, scene directions, labels, or invented placeholder dialogue.
25. Profile loading cannot present onboarding for an established creator. Profile failure has its own recovery state.
26. All app-owned UI stays monochrome. Keep Dynamic Type and every existing accessibility identifier working.

## E2e scenarios and handoff

The scenarios are in `tests/pocket-loop.e2e.ts`. Helpers are in `tests/pocket-support.ts`.
Each test creates a unique fixture session. Relaunch keeps that same session and explicitly replaces launch arguments.
The tests use TesterArmy mobile UI actions, clipboard reads, and relaunch only.
They do not call Supabase or write simulator files from the test process.
Tests assert the required behavior; they do not mark open bugs as expected passes or skip them.

`MCO_LOOP_SCENARIO` is a DEBUG-only seed selector. It requires fixture mode and a session.
The seed runs once per session. Relaunch must read the edited saved state instead of reseeding it.

| Seed | Starting data |
| --- | --- |
| `initial` | No extra seed. Exercises the app's existing initial Today fixture and onboarding paths. |
| `ready` | The ten-shot storyboard in the writable fixture store for today, plus a separate ready revision for tomorrow. |
| `line-script` | The ready seed with one distinct creator-written script line per shot and the original timed voiceover still present. |
| `blank-copy` | The ready seed without script, caption, audio notes, or dialogue timelines. |
| `stale-pointer` | A ready package for today plus yesterday's stored Today pointer. Tests post-midnight date resolution without changing the clock. |
| `legacy-cache` | The ready seed plus a fully filmed cache and pending `shot` decision in the old format, without `unsyncedDecision.card`. |
| `old-decision` | Today's ready revision plus yesterday's separate revision and a cached pending posted decision targeting yesterday's card. |

The existing `e2e.config.ts` selects one legacy suite from `POCKET_E2E_SCENARIO`.
TesterArmy positional file arguments only narrow that configuration; they cannot add this new file.
The config is outside Phase 0 ownership, so it is unchanged.
When the simulator owner runs this group, use a runner-owned config beside `e2e.config.ts` with this override:

```ts
import base from './e2e.config';
import type { E2EConfig } from 'e2e';

export default {
  ...base,
  tests: 'tests/pocket-loop.e2e.ts',
} satisfies E2EConfig;
```

For example, if the simulator owner names that config `e2e.loop.config.ts`, run:

```sh
npx e2e run tests/pocket-loop.e2e.ts --config e2e.loop.config.ts
```

The runner must use the app built with these DEBUG seeds and hold the simulator exclusively.
The file registers 32 scenarios, including the parameterized shot/posted and missing-copy cases.
These scenarios were authored but were not run in Phase 0, as requested.
TypeScript compilation is required only if a project `tsconfig` exists.

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
| R1-5 Dead accepted runs and creator ownership | N3 | Fixture resume does not model those server answers or identities. |
| R1-6 Profile first; no premature onboarding | `R1-6: an established creator` plus N4 | Partial: established relaunch. Delayed profile ordering is not injected. |
| R1-7 Plan keeps tapped day, rejects past saved day, isolates async results | `R1-7: Plan keeps the tapped day`, `an async generation stays` plus N2 | Partial: selection, relaunch, and async generation. Past saved selection needs a day-change seam. |
| R1b-1 Failed decision retained and retried | `R1b-1: a failed posted decision` plus N5 | Partial: one failure and successful replay after relaunch. Repeated refresh failures need a controllable failure queue. |
| R1b-2 No past cached Today; retry and day/foreground refresh | N5, N6 | Stale-pointer coverage is tracked separately under R3-C4. |
| R1b-3 Creator script lines win | `R1b-3: the Script tab uses the creator lines` | First and last shot assertions. |
| R1b-4 Failed replace restores old idea | `R1b-4 R2-4: failed replacement restores the title` | Normal recoverable fixture failure. |
| R1b-5 First idea retries after close or failure | `R1b-5 R3-C6: a failed first idea` plus N7 | Partial: relaunch after an observable failure. Mid-request termination needs a barrier. |
| R2-1 Old unsynced decision keeps its card after midnight | `R2-1: an older pending decision` plus N6 | Seeded post-boundary state: replay yesterday's decision while today's package stays ready. Exact day-change delivery remains uncovered. |
| R2-2 Retry preparing first idea; promote complete draft | N7 | Current fixture profile/handoff is not durable and has no preparing/completed-draft seed contract. |
| R2-3 Retain accepted run on timeout/network; remove ended or old runs | N3 | New contract supersedes age-based expiry; see invariant 11. |
| R2-4 Restore decision and scene marks after failed overwrite | `R2-4: a failed replacement restores a posted decision`, `R1b-4 R2-4` plus N8 | Partial: normal failure. Persisted interruption and recovery-network failure need a barrier. |
| R2-5 Refresh empty/unavailable Today on new day | N6 | No virtual date or network-failure seam. |
| R2-6 Edited script takes precedence; unedited timing stays | `R1b-3: the Script tab`, `R2-6: an unedited script` | Distinct lines plus all ten original timed rows. |
| R2-7 Fixture archive keyed by card; Plan edits update saved draft | `R3-L1 R2-7: posting a replacement`, `R2-7: a future caption edit` | Two archive revisions, saved/copyable caption, and relaunch. |
| R3-L1 Posted history changes on replacement | `R3-L1 R2-7: posting a replacement` plus N9 | Partial: fixture archive behavior. Real revision-row reuse is not exercised. |
| R3-L2 Interrupted first idea lost after midnight | N7 | No controlled date change or durable fixture handoff. |
| R3-L3 Word/paragraph edit shifts shot dialogue | `R3-L3: one word`, `R3-L3: a paragraph edit` | Supplied ten-shot, nine-line fixture; assert shot two and final dialogue. |
| R3-L4 Saved durations leave old timecodes | `R3-L4: a saved scene duration` | Assert first range and cumulative next range after relaunch. |
| R3-F1 New decision overwrites old unsynced decision | `R3-F1: a new decision cannot erase` | Seed yesterday's pending A, observe its failed retry, decide B, then require both archive records after relaunch. |
| R3-F2 Interrupted overwrite loses progress | N8 | No deterministic server-acceptance or failed-recovery barrier. |
| R3-F3 First-idea and accepted-run recovery collide | N7 | No shared accepted-run/profile synchronization barrier. |
| R3-F4 First retry resumes terminal dead run | N3 | Fixture resume always returns a generated result. |
| R3-C1 Old cache cannot decode pending card | `R3-C1: an old pending-decision cache` | Legacy file is seeded in-app before normal cache loading. Assert filmed state and archive replay. |
| R3-C2 Restored published future package displays old edit | N10 | Existing fixture weekly repository returns no restored generation summary. |
| R3-C3 Fixture draft resurrects Posted | `R3-C3: edit, unpublish, and make ready` | Edit a posted revision, unpublish, approve, and relaunch. |
| R3-C4 Fixture Today keeps yesterday | `R3-C4: a stale fixture pointer` plus N6 | Seeded post-boundary state and relaunch; exact midnight notification remains uncovered. |
| R3-C5 Initial ready fixture absent from writable store | `R3-C5: the initial ready fixture` | Uses `initial`, without the writable `ready` seed. |
| R3-C6 Fixture preferences/handoff lost on relaunch | `R3-C6: onboarding interests`, `R1b-5 R3-C6: a failed first idea` plus N7 | Selected interest and failed first-idea recovery. Preparing handoff interruption remains uncovered. |
| R3-C7 Blank edit contracts differ | `R3-C7: Plan blocks`, `Shoot Folio blocks`, `Post refuses` plus N9 | UI validation in three editors. Real SQL behavior remains uncovered. |
| R3-C8 Offline unpublished placeholder restored as ready | N11 | No fixture read-failure mode after a successful unpublish. |

### Expected failure checkpoints

These are source-derived expectations for the simulator owner, not observed test results.

| Open finding | Assertion that should expose it on the current code |
| --- | --- |
| R3-F1 | Yesterday's archive title must still exist after B's decision and relaunch. |
| R3-L3 | Shot two must retain its original dialogue after the first line changes; shot ten must retain its closing dialogue. |
| R3-L4 | Shot one must show `0-8 sec`; shot two must start at `8` after the saved duration edit. |
| R3-C1 | Legacy-cache launch must keep `Get post text` and replay the pending decision into Archive. |
| R3-C3 | After edit, unpublish, approval, and relaunch, Today must not say `View posted content`. |
| R3-C4 | Today must display `Loop stale-pointer package`, rather than yesterday's title. |
| R3-C5 | Saving the initial fixture edit must leave edit mode and survive relaunch. A `daily_card_not_found` error is a failure. |
| R3-C6 | The Books interest must stay selected after relaunch. A failed first idea must retry into a ready Today. |
| R3-C7 | Plan and Shoot Folio must disable a blank save. Post must reject it and keep the saved text. |

The archive replacement case can pass on fixtures while the real-row bug remains open.
The future-caption case does not reproduce the restored-summary-only bug.
Keep gaps N9 and N10 open even if those UI scenarios pass.

## Not covered by e2e

These are limits of the current app and fixture seams, not a claim that TesterArmy cannot support future scenarios.
No other test framework is authorized or used in this phase.

| Gap | Uncovered trigger or assertion | Reason and required seam |
| --- | --- | --- |
| N1 | Direct decision refusal after shot/posted, including a backup confirmation opened earlier | The UI hides the command. No fixture seed opens an old backup sheet against a changed revision. Add a stale-confirmation scenario before claiming the service guard is tested. |
| N2 | UTC formatting in a negative-offset device zone; rejection of a saved Plan selection that became past | Launch arguments do not provide a documented app-day/time-zone clock. Do not change the shared simulator clock or zone. Add an app-owned virtual clock and a persisted-selection seed. |
| N3 | Dead/foreign accepted runs; timeout/network preservation; terminal failure followed by a fresh brief; former two-hour cleanup | Fixture generation has no acceptance/polling protocol or terminal/transport result queue. `resumeAcceptedDayGeneration` fabricates a completed result. Add the fake-server run contract in phases 1, 3, and 4. A new launch seed alone would not exercise the live repository branch. |
| N4 | Profile read finishes after another request; no onboarding flash during that delay | Fixture profile reads are immediate. A post-launch hidden assertion cannot prove that onboarding never flashed. Add delayed-profile and failed-profile scenarios with an observable loading state. |
| N5 | Repeated decision retry failure, two simultaneously failed decisions, stale cache plus a failed Today read | The existing failure flag fails only once per process. It cannot fail both A and B, control server acknowledgements, or fail a Today read. The `old-decision` seed covers A failing followed by B succeeding. Add a persisted response queue for the remaining variants. |
| N6 | Exact midnight notification; foreground refresh from empty/unavailable; automatic A-to-B fixture rollover | TesterArmy can foreground and relaunch, but this app has no controllable calendar-day seam. The stale-pointer seed tests the post-boundary lookup only. Add an app-owned day-change control and observable refresh result. |
| N7 | Kill between profile save and generation acceptance; preparing handoff with/without a completed draft; next-day handoff; accepted-run/profile recovery race | Current pending-first-idea storage uses standard defaults, while fixture profile handoff is process-local. Do not seed global pending data into another agent's session. Add session-isolated durable handoff and accepted-run barriers. A close after the visible failure is covered; exact mid-request recovery is not. |
| N8 | Kill after replacement acceptance but before generation finishes; failed generation plus failed old-revision recovery | A slow UI progress indicator does not prove the server crossed the unpublish/acceptance boundary. No fixture barrier pauses at that boundary or rejects recovery publication. Add transaction-stage controls. Normal failed replacement is covered separately. |
| N9 | Real server reuses a posted row, changes archive snapshots, or accepts blank edits differently | Fixture UI runs never reach the real SQL/function persistence contract. No live service access is allowed. The local backend owner must provide a matching local fake/real contract before these UI assertions count as server regression proof. |
| N10 | Future published package loaded only through `latestGenerationSummary`, then edited | `FixtureWeeklyPlanRepository.currentWeeklyContent` returns `generatedDraft: nil`. Its persisted packages use a different hydration path. A future fixture edit test cannot reproduce this branch. Add a restored-published-summary response to the fake server. |
| N11 | Successful Unpublish, process termination, offline relaunch, then placeholder actions | There is no supported Today-read transport failure launch flag. `MCO_FORCE_EMPTY_TODAY` returns an authoritative missing-card response, which is a different branch. Add a persisted unavailable-read response and lifecycle snapshot seed. |

## Phase 0 verification limits

No e2e tests, app builds, simulator commands, or live-backend commands run as part of this phase.
The other agent owns the simulator. Open-bug assertions remain ordinary required assertions for that agent to run.
Static review predicts failure points; only an actual run can establish that an open bug fails for the intended reason.
The launch seeds use the current cache and fixture snapshot formats. Their migration is part of phases 2 through 4.
The scoped `git diff --check` and source audit passed. The audit checked all five Phase 0 files for trailing whitespace.
It also checked the new code for added comments and counted all 35 supplied finding rows.
No project `tsconfig.json` exists, so `npx tsc --noEmit -p .` was skipped as instructed.
