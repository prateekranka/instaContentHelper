# Creator loop redesign

Status: approved plan; phases 0–6 implemented locally on `redesign/creator-loop`.
Phase 6 starts from `816fa58`. Runtime acceptance remains with the separate e2e runner.
This document records the implemented design. It does not claim all e2e groups pass.

## Why the loop changed

Earlier bug hunts found repeated failures with five root causes:

| Root cause | Result |
| --- | --- |
| Screens kept separate copies of one day. | Saved edits, lifecycle, and filming progress drifted. |
| Four stores kept unfinished work under different rules. | Pending decisions and first ideas were overwritten or expired. |
| Replacement used separate unpublish and generate calls. | An interruption left a half-complete replacement. |
| Generation reused a revision row. | Old archive entries displayed replacement content. |
| Fixtures implemented separate persistence rules. | Fixture results differed from the server contract. |

Script text and timeline dialogue also competed for ownership of shot lines and timecodes.

## Implemented design

### One record per day

`Day` belongs to a workspace, creator, and date. It keeps the current revision,
previous revisions, lifecycle, server version, and filming progress for each revision.
`Day.transition` validates moves before replacing the stored value.
`DayStore` owns those records and archive entries. Today, Plan, Filming, and Post
read projections of that store. Screen selections and transient loading errors remain presentation state.

The cache stores a schema version, a `DayStoreSnapshot`, and its outbox.
The current schema version is 3. Old cache fields decode with defaults.
Undecodable files move to a separate recovery file before another snapshot is saved.
Today selects the current calendar date; a past cached package cannot become today's package.

### One durable outbox

`ContentOutbox.swift` defines `ContentIntent` and its replay results.
The five intent kinds are `decide`, `editPackage`, `generate`, `replaceDay`, and `firstIdea`.
`editPackage` has `update`, `makeReady`, and `returnToDraft` actions.
Undo posted is a decision intent against the same revision.

`AppServices` persists each intent before sending it or displaying an optimistic decision.
One replay loop processes the queue on launch, foreground, day change, and network return.
A generation response binds dependent requests from their local requested ID to the returned revision ID.
The client saves accepted run IDs and polls the same run after an interruption.
Dates and elapsed time do not expire intents.
Success, explicit revision removal, and terminal generation failure resolve intents.
A past-date rejection is terminal. An unaccepted first idea retargets to current today and replays. Other rejected generation intents leave generating and show the error. Other errors retain the request for replay and expose the error.

The separate pending-first-idea and accepted-generation stores are gone.
Small decoding models remain for one-time migration of their old UserDefaults values.
The legacy pending-decision decoder remains for cache migration and its regression seed.
Migration deletes old keys only after the new snapshot saves successfully.

### Server revision and mutation rules

Each successful generation inserts a new `daily_cards` revision.
`creator_days` points at its current revision and latest generation run.
Archive entries keep their exact revision ID, title snapshot, caption snapshot, and decision time.
Replacement acceptance clears the old revision's `is_current` flag immediately. A replaced revision cannot change its history. Current posted undo keeps the stored text snapshots.

`replace-day` archives the prior revision and accepts the new generation in one transaction.
Provider work runs after that transaction. A failed provider run leaves the accepted prior revision archived;
the app retains its content and progress as recovery data without presenting it as ready.
A failure before acceptance leaves the prior server state intact.
Generation keys bind to request identity. A changed brief requires a new key.
Revision insertion and the completed run snapshot commit together. Terminal runs stay closed; finalization can enrich a completed snapshot.

Package edits reject blank or invalid text. Both SQL and the edge function validate every supplied shot.
Each shot requires a UUID string `id` and string `title` and `duration`; `dialogue` is optional and must be a string when supplied.
The existing client metadata fields remain valid. The new migration leaves earlier migrations unchanged.
See [the server contract](creator-loop-server-contract.md) for error codes and response fields.

### One fake server for fixtures

`FakeServer` owns saved revisions, day pointers, runs, archive entries, profile preferences, and plans.
Its saved state is isolated by `MCO_QA_SESSION`.
Fixture repositories send the same request DTOs and decode the same response DTOs as the Supabase repositories.
The fake server enforces revision identity, generation keys, lifecycle guards, and package validation.
It does not call a live service. Existing test setup adapters that still have callers remain supported.

### Shots own dialogue and duration

`ShotScene` keeps stable identity, dialogue, and duration.
`ShotScript` builds the full script and cumulative timecodes from those shots.
Legacy script and timeline fields are normalized into shot content on load.
Editors show one line per numbered shot. Shorter input retains later shot lines;
extra lines join the final shot. A blank line clears only that shot's dialogue.
Duration edits change subsequent cumulative timecodes.
No `scriptReplacesTimeline` flag remains.

## Phase status

“Done” below means the implementation work exists locally. Build, backend, and runtime evidence are separate gates.

| Phase | State | Delivered work |
| --- | --- | --- |
| 0 | Done | Lifecycle contract, loop scenarios, and session-isolated regression seeds. |
| 1 | Done | Revision rows, archive snapshots, atomic replacement, keyed runs, and package edit validation. |
| 2 | Done | `DayStore`, lifecycle transitions, projections, and versioned cache migration. |
| 3 | Done | One durable outbox and one replay loop; legacy saved-work migration. |
| 4 | Done | Durable `FakeServer` behind fixture repositories. |
| 5 | Done | Shot-owned dialogue, duration, stable identity, and derived script timing. |
| 6 | Done | Dead-code cleanup, outbox filename and project reference, shot validation, test-source repairs, and current documentation. |

Phase 6 runs `xcodebuild` with `DerivedData/Phase6` and `deno task ci:backend`.
Backend CI passed with 403 tests, no failures, and two ignored checks.
The build remains blocked by restricted Swift package manifest sandbox execution.
All 85 app Swift files passed a syntax parse; this does not replace the build gate.
The simulator owner runs the 12 existing e2e groups and the loop suite separately.
The R3-C5 assertion now targets scene 1. The R3-C7 Post script clear uses selection and the keyboard delete key.
These source changes require a new runtime run before either fix can be called verified on a device.
Source review and backend checks do not establish zero creator-facing bugs.
See [the lifecycle document](creator-loop-lifecycle.md) for coverage limits.

The 17 UI items from step 4 remain later work. They are outside these implementation phases.

## Out of scope

- Live migrations, live database access, Supabase deployment, and production conversion.
- Onboarding questions, AI prompts, and screen redesign.
- Commits, pushes, and git history changes during phase 6.

The stopped patch job's saved patch and stash remain historical references.
The implemented lifecycle, outbox, fake server, and shot model define the current design.
