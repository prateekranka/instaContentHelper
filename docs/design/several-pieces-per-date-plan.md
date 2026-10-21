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
- Phases 3 to 6 remain open.

## Phase 2 validation

- `python3 scripts/check-agen## Phase 2 validation

- `python3 scripts/check-agent-rules.py` passed all six groups with zero violations.
- The Debug app built in `DerivedData/Verify` with Xcode 27.1 beta.
- On that installed build, all 12 e2e groups, 35 loop tests, and 7 screen tests passed (run `p2full-212119`, 2026-10-21).
- Backend CI passed 410 tests, and the local database test passed.

for each `creator_days` row, insert one `content_pieces` row with the same workspace, creator, and
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
- Notifications, reminders, and the weekly plan read one package per date. Check them in phase 5.
