# Several pieces per date: plan

Status: option A approved by the owner on 2026-10-21. Phases 1 to 6 below are the build order. The owner confirmed on 2026-10-21 that several independent
pieces per date is still the product plan. The [flow and state spec](creator-ios-v1-2026-10-18/flow-and-state-spec.md)
and [the handover](../claude-handover.md) define the product rules. The [creator loop redesign](creator-loop-redesign.md)
stores one package per date today. This plan closes that gap without losing saved work.

## What the product needs

- A date holds zero, one, or many pieces. Each piece is independent.
- The creator can add a piece after other pieces on that date are approved, shot, or posted.
- Each piece keeps its own script, shots, filming progress, captions, revisions, and posting records.
- Today lists the day's unfinished pieces in the creator's chosen order.
- Plan lets the creator select a date, add a piece, open a piece, and move a piece to another date.
- Day review can approve several reviewed pieces at once ("Approve 2 pieces").
- The day summary counts pieces ("2 approved · 1 needs review").

## Where the code assumes one package per date

| Layer | Assumption today | Evidence |
| --- | --- | --- |
| Server table | `creator_days` has primary key `(workspace_id, creator_id, scheduled_date)` and one `current_revision_id`. | `20261020160000_creator_loop_revisions.sql` |
| Server index | `daily_cards_current_day_key` allows one current revision per creator and date. | same migration |
| Server functions | `replace_day`, generation, publish, unpublish, and package edits target a date and its one current revision. | `supabase/functions/replace-day`, `generate-week`, `update-ready-day-package`, `make-day-available`, `unpublish-day` |
| Client identity | `DayIdentity` is workspace, creator, and date. | `Models.swift` `DayIdentity` |
| Client store | `DayStore.days` is `[String: Day]`, keyed by date. Projections are cached by date. | `TodayCacheStore.swift` |
| Client lifecycle | One `Day` has one `revision` and one `lifecycle`. | `Models.swift` `Day` |
| Outbox | Only one generation intent can own a date. Replies are matched by date. | `AppServices.enqueueGeneration`, reconciliation by `scheduledDate` |
| Today | `AppServices.todayCard` returns one card. It has 127 uses. | `AppServices.swift` |
| Plan | One `displayedCard` per selected date. Choosing another idea asks to overwrite it. | `PlanHubView.swift` |
| Fixtures | `FakeServer` keeps one day pointer per date. | `FixtureRepositories.swift` |
| Tests | Plan tests expect an overwrite prompt. Loop tests read one package per date. | `tests/pocket-plan.e2e.ts`, `tests/pocket-loop.e2e.ts` |

Archive is already per revision (`archive_entries.daily_card_id` is unique). It does not need a new key.

## Options

### A. A piece is the unit; the date is a field on it (recommended)

- New server table `content_pieces`: `id`, workspace, creator, `scheduled_date`, `position`, `current_revision_id`,
  `generation_run_id`, `created_at`, `updated_at`, `removed_at`.
- `daily_cards` gains `piece_id`. Every revision belongs to one piece.
- The current-revision index becomes one current revision per piece.
- Client `Day` becomes `Piece` with identity workspace, creator, and piece ID. Lifecycle, revisions, and
  filming progress move with it unchanged.
- `DayStore` keeps pieces by ID and keeps an index from date to ordered piece IDs.
- Moving a piece to another date changes one field. Its revisions, media, and progress stay.

Good: it matches the spec, including "Move a piece" and "Duplicate a piece". Each piece has its own lifecycle,
so posting one piece cannot change another. The existing lifecycle rules carry over almost as written.
Cost: a new table, a new key in the outbox, and many call-site changes on the client.

### B. Keep one `Day` per date and give it a list of pieces

- `Day` keeps its date identity and holds `[Piece]`. Each piece has its own revision and lifecycle.
- The server keeps `creator_days` and adds a child table for pieces.

Good: fewer renames, and the date-level summary has a natural home.
Bad: every piece change rewrites the whole date. Moving a piece to another date means moving it between two
records, which can lose work if one write fails. Two pieces on one date share one version stamp, so a stale
answer for one piece can block the other. This repeats the "several copies of one thing" root cause that the
redesign removed.

### C. Store extra pieces as extra dates with a suffix

Rejected. It breaks date parsing, Today selection, and the server's date checks, and it cannot move a piece.

## Recommendation

Choose option A. The date summary ("Day approved · 2 pieces") becomes a read-only projection over that date's
pieces. It is never stored, so it cannot drift.

Use client-generated piece IDs. The app creates the piece ID before it saves the intent, and the server accepts
that ID on first create (idempotent). This keeps the outbox rule "persist before send" and removes the need to
bind a local piece to a server piece later.

## Phases

Each phase ends with all e2e tests passing, the same as the earlier work. Live migration and deploy need the
owner's yes.

1. **Server: add pieces behind the current API.** Add `content_pieces` and `daily_cards.piece_id`. Migrate each
   `creator_days` row to one piece at position 0 (see migration below). Keep `creator_days` as a compatibility
   table mirrored from position 0 by a trigger so current clients still work. Change the current-revision index
   to one per piece. Add `piece_id` to every response. Update the database test and backend CI. The app does not change yet.
2. **Fake server and contracts.** Teach `FakeServer` pieces with the same rules. Add `piece_id` to request and
   response DTOs. Old fixtures load as one piece per date.
3. **Client model.** Rename `Day` to `Piece` and key `DayStore` by piece ID with a date index. Outbox intents
   carry `pieceID`; the "one generation per date" guard becomes "one generation per piece". Cache schema 4
   migrates each saved `Day` to one `Piece`. The UI still shows one piece per date, so screens and tests do not
   change in this phase.
4. **Plan: add and open pieces.** The selected date lists its pieces. "Add a piece" creates a new piece and
   starts the idea launcher for it. "Choose another idea" on a piece replaces only that piece and keeps the
   overwrite prompt. Add "Move to another date".
5. **Today: several pieces.** Today lists the day's unfinished pieces in the creator's order. Filming, Post, and
   backups act on the selected piece. Replace `todayCard` with a selected-piece projection, one screen at a time.
6. **Day review and approval.** Review day lists each piece with its review state. "Approve N pieces" approves the
   selected reviewed pieces together and keeps earlier approvals. The day summary uses the actual counts.

The spec also says an edit to an approved piece makes a new draft and keeps the approved version until the
replacement is approved. The current model keeps one current revision. Add an `approved_revision_id` per piece in
phase 6, or plan it as its own change.

## Phase status

Done means the implementation exists locally. PostgreSQL execution and app runtime acceptance remain separate.

- **Phase 1: Done locally (2026-10-21).** Migration `20261021140000_content_pieces.sql` adds pieces,
  backfills all revisions, checks counts and pointers, and enforces one current revision per piece.
- Optional client piece IDs now pass through generation, replacement, package edits, make ready,
  unpublish, and decisions. Legacy date-only calls select position 0. Revision and day responses include piece IDs.
- `creator_days` remains a table with its constraints. A trigger mirrors position 0 from `content_pieces`.
  This preserves existing dependencies while all current mutation RPCs use the piece as their source.
- The queue lane cap counts jobs per generation run. Two pieces use separate runs and remain permitted.
- Backend CI passed: 410 tests passed, none failed, and two checks were ignored. Local DB harness changes are included. The owner still needs to apply
  `supabase db reset --local` and run `creator-loop-db_test.ts`. No live migration or deploy occurred.
- **Phase 2: Done locally (2026-10-21).** Native request and response DTOs accept optional piece IDs.
  Supabase and fixture repositories pass supplied IDs through and retain their existing date-only methods.
  FakeServer stores pieces by ID, with date, position, revision, and generation pointers. Replacement and
  lifecycle mutations affect one piece. Foreign scope and revision targets use the phase 1 error codes.
  Saved version 1 fake-server state migrates to one position-0 piece per date, including historical revisions,
  archive entries, and saved run results. Legacy reads still project position 0; all-piece reads are opt-in.
- Phase 2 review fix: only an explicit `piece_id` bypasses the soft-lock 409; date-only requests remain blocked unless recovering.
- Phase 2 changes no screens, accessibility identifiers, outbox intents, or client cache schema.
  Build, source-check, and e2e results are recorded below.
- **Phase 3: Done locally (2026-10-21).** `Piece` uses workspace, creator, and piece ID as identity.
  Scheduled date and position belong to the piece. `DayStore` owns pieces by ID and an ordered date index.
  Cached card projections use piece IDs. Existing date lookups, `todayCard`, and screens still select position 0.
- Outbox intents save a device-created piece ID before send. Generation ownership and reply reconciliation
  use piece IDs. Schema 4 loads saved days at position 0 and binds local pieces through shared revision IDs,
  including archive revisions. Binding retains revision history, filming marks, decisions, and queued work.
  Migrated generation intents retain date-only request identity so their saved idempotency keys still replay.
- Older cache schemas remain readable. Migration keeps a recovery copy until the schema 4 snapshot saves atomically.
  Focused Swift typechecking and source checks are the phase 3 gates. The owner runs the full build and unchanged e2e suites separately.
- **Phase 4: Done locally (2026-10-22).** Plan lists pieces in position order with `plan.piece.<position>` choices.
  It remembers the selected piece for each scoped date through the Plan selection store. One piece keeps the
  existing package view, with Add a piece and Move to another date. Add opens the existing launcher;
  cancelling saves no piece. The first saved generation intent creates the extra piece ID and appends it.
- Generation, retry, replacement, package editing, approval, and unpublish target the selected Plan piece.
  An unloaded date's first generation uses a date-only request, then binds to the server's position-0 piece.
  This also handles an older empty local placeholder. Extra pieces use device-created IDs.
- The new move RPC and edge route retain piece/revision identity and saved work, append at the target,
  compact source positions, and maintain both compatibility mirrors. FakeServer follows the same contract.
  A durable move intent survives relaunch and reuses its request key. Running generation defers a move.
- New e2e cases cover two pieces across relaunch, independent replacement, movement with filming marks,
  independent generation failure/retry, and blank shot lines with retained shot order.
  Post script copy and Plan script saves retain blank lines. The blank-line regression compares exact clipboard values.
  The two existing Post relaunch assertions ignore trailing whitespace on both sides because iOS snapshot values can trim it.
- Phase 4 source and focused Swift checks passed. Backend CI passed 427 tests with no failures and two ignored checks.
  The TypeScript check has the same three `scroll-view` declaration errors on HEAD and the changed test sources.
  Full app build, e2e (including largest Dynamic Type), and PostgreSQL execution remain owner gates.
  See [the phase 4 design notes](several-pieces-phase4-report.md) for the move contract and the first-piece rule.
- **Phase 4 review fixes, round 1 (2026-10-22):** `ensurePiece` retains phase 3 defaults. Date-only first-piece
  identity is explicit in generation paths, including onboarding generation and first-idea retargeting.
  Plan copy checks open the Script tab. The retry test opens the short Caption panel before reading the light-edit script.
  Move choices start at today; Previous week is absent on the first week. Permanent move rejections leave the outbox,
  while running generation and temporary failures retain their request with a correct message.
  Idea settings uses sentence case. Storyboard feedback hides unavailable configuration codes.
  The supplied runtime failures were inspected; runtime checks are not rerun in this review.
- **Phase 4 review fixes, rounds 2 to 5 (2026-10-22):** Plan panels keep each child's accessibility identifier, and
  the agent rule check rejects a container identifier that overrides its children. Post keeps Save and Cancel in a
  fixed row below bounded editors, and the active editor scrolls into view. An empty lifecycle placeholder yields to a
  real piece on the same date, and a date never keeps two pieces at one position. Cancel after "Add a piece" returns
  to the package title. Tests scroll before each assertion and address shots and dates by their own identifiers.
- **Phase 5: Done locally (2026-10-22).** Today selects unfinished pieces in position order and saves
  each date's selection under its workspace and creator. With one unfinished piece, the choice list is absent.
  Ready pieces keep the existing main card and action. A selected draft opens its own piece in Plan.
- Today, filming, Shoot Folio, Post, backups, and skip use the selected piece. Open filming and Post screens
  retain that piece ID. Posting advances Today while Post keeps the posted piece available for copy and Undo.
  When no unfinished piece remains, Today keeps the existing completed-package presentation.
- Screen reads no longer use `todayCard`. `todayPieceProjection(pieceID:)` is the common accessor
  into the existing piece/revision cache. `selectedTodayCard` supplies the existing empty placeholder.
  A deprecated `todayCard` alias forwards existing callers into the same projection and store import path.
  Progress transitions and durable package/decision intents carry piece IDs. Thumbnail requests carry the
  piece ID and exact revision ID. No second mutable package owner or cache schema is added.
- Added e2e sources cover a posted piece beside a retained draft through relaunch, a held decision beside
  an edit to another piece, selected-piece Post copy/edit/Undo, and selection/filming isolation at normal
  and largest Dynamic Type. The screen catalog adds the two-piece Today and filming states.
  The DEBUG-only `MCO_FAIL_TODAY_DECISION_SYNC` flag holds decision failures until cleared.
  Existing e2e test bodies and shared helper behavior are unchanged; imports and new tests/helpers are additive.
- Focused Swift typechecking passed for all 14 changed Swift files. All six agent-rule groups passed.
  TypeScript has the same three `scroll-view` errors as HEAD, with no new errors. The direct npm command
  could not resolve the registry, so both source sets used the same cached TypeScript compiler through npx.
  `git diff --check` passed.
- **Phase 6 remains open.** Day review and approval keep their existing behavior.

## Phase 2 validation

- `python3 scripts/check-agent-rules.py` passed all six groups with zero violations.
- The Debug app built in `DerivedData/Verify` with Xcode 27.1 beta.
- On that installed build, all 12 e2e groups, 35 loop tests, and 7 screen tests passed (run `p2full-212119`, 2026-10-21).
- Backend CI passed 410 tests, and the local database test passed.

## Phase 3 validation

- `python3 scripts/check-agent-rules.py` passed all six groups with zero violations.
- The Debug app built in `DerivedData/Verify` and was installed and checked on the simulator.
- Run `p3full-224709` (2026-10-21): 11 of 12 groups, 35 loop tests, and 7 screen tests passed. The ready group
  failed one known, intermittent check (script blank lines after relaunch, also seen before phase 3). Two reruns
  of the ready group passed (`p3re-ready-235139`, `p3re-ready-235314`). The bug is queued for phase 4.

## Phase 4 validation

- `python3 scripts/check-agent-rules.py` passed all six groups with zero violations.
- The Debug app built in `DerivedData/Verify` and was installed and checked on the simulator.
- Run `p4final-054055` (2026-10-22): all 12 groups and 38 loop tests passed. The screen catalog passed 7 of 7 in
  `p4final-screens3-115027`; earlier screen runs failed only on app launch timeouts while the Mac was overloaded.
- Backend CI passed 427 tests. The move migration was applied to the local database only, and the local database test passed.

## Phase 5 validation

- `python3 scripts/check-agent-rules.py` passed all six groups with zero violations.
- The Debug app built in `DerivedData/Verify` and was installed and checked on the simulator.
- Review round 1 moved Plan's piece controls above the storyboard. Existing Plan tests failed, so that move was
  reverted. The largest-text Today test now opens the Caption tab before "Add a piece" and scrolls up to the filming action.
- Run `p5full-142139` (2026-10-22): 10 of 12 groups, 37 of 41 loop tests, and 7 of 8 screen tests passed while
  other simulators held the Mac load near 150. Every failure was a runner transport loss, an app launch timeout,
  or a test timeout. Reruns at low load passed all of them: `p5re-plan-161504` (3 of 3), `p5re-loop-161504`
  (R3-L3, R3-L4, R3-C3), `p5re2-screens-164123` (two-piece Today), and `p5re3-loop-203222` (piece move).
- The piece move test took 220 of its 240 seconds in phase 4. Its limit is now 360 seconds, like the other phase 4 loop test.
- No server files changed in phase 5.

## Migrating saved work without loss

- **Server:** for each `creator_days` row, insert one `content_pieces` row with the same workspace, creator, and
  date, position 0, and the same `current_revision_id` and `generation_run_id`. Set `piece_id` on every
  `daily_cards` row for that creator and date, current and previous. Archive rows already point at a revision, so
  they need no change. Run it in one transaction, and check row counts before and after.
- **Client cache:** schema 4 turns each saved `Day` into one `Piece`. To match the server, the client binds a local
  piece to a server piece by any revision ID they share. Revision IDs are global UUIDs, so this match is exact.
  Pending outbox intents get the matching piece ID before replay. The old cache file is kept as a recovery copy
  until the new snapshot saves, as today.
- **Old app versions:** the mirrored `creator_days` table keeps answering for them until no supported client uses it.

## E2e test changes

- `pocket-plan.e2e.ts`: the overwrite test stays for replacing one piece. Add a test that adds a second piece to
  the same date and checks that both stay after relaunch.
- `pocket-loop.e2e.ts`: existing tests keep passing in phases 1 to 3. In phases 4 to 6, add tests for these cases:
  - Post one piece while another on the same date stays a draft.
  - A failed generation for one piece does not touch the other piece.
  - Moving a piece keeps its filming marks.
  - A pending decision on one piece replays after relaunch while the other piece is edited.
- `pocket-today.e2e.ts` and the screen catalog: add a Today screen with two pieces, and the day review screen with
  "Approve 2 pieces".
- The scroll and accessibility rules from step 6 apply to the new screens. Each piece row needs its own stable
  identifier, for example with the piece ID or position in it.

## Risks

- `todayCard` has 127 uses. Change it in phase 5 behind one selected-piece projection, not with search and replace.
- Two pieces on one date can generate at the same time. Check how the day-job lane cap
  (`claim_queued_day_job`) treats two runs for one creator and date before phase 4.
- Notifications, reminders, and the weekly plan were checked in phase 5. See the audit below.

## Phase 5 date-reader audit

| Reader | Phase 5 result |
| --- | --- |
| Today data | Both production and fixture `creatorDays` reads already request `include_all_pieces`. Today now selects from the ordered pieces rather than the date's position-0 pointer. |
| Notifications and reminders | The app has one local Today reminder per workspace and creator, through `TodayNotificationScheduler`. Scheduling now chooses the first unfinished, ready piece with no filming decision, in position order. It does not depend on the selected piece or position 0. Posting, using a backup, skipping, and unpublishing reschedule from the remaining pieces. It cancels when none qualifies. The existing single-piece reminder policy, time, permission flow, and copy remain. There is no separate active reminder reader. |
| Weekly ready cards | `DayStore.readyCards` and `AppServices.weekCards` now include every ready piece, ordered by date and position, through the existing piece-keyed card cache. |
| Legacy weekly plan and generated week summary | `weeklyPlan.days`, `DayStore.packages`, and `latestGenerationSummary` retain the position-0 compatibility projection. These APIs represent seven date slots and their existing review/approval actions. Position 0 is the defined compatibility representative for each slot; it is not the date's complete content list. Expanding these review states and approval counts belongs to phase 6, which this task leaves unchanged. Creator Plan's piece list already reads all ordered pieces and writes its selected piece. Today, filming, and Post do not use the legacy weekly projection. |
| Legacy repository reads | Date-only `today` and `weekly` repository methods remain compatibility fallbacks when a repository does not implement the all-piece `days` read. Both current production and fixture repositories implement that read. Initializer parameters and publish response fields named `todayCard` remain transport/seed inputs; they are not screen projections. |

Several independent pieces per date remains the product rule. A position-0 compatibility reader must not
supply a total-piece count or determine whether all pieces on a date are complete.
