# Several pieces per date: phase 4 design notes

Phase 4 adds pieces to Plan: add a piece, choose another idea for one piece, and move a piece to another date.
Several independent pieces per date remains the product rule. Validation is in [the plan](several-pieces-per-date-plan.md).

## Delivered behavior

Plan uses DayStore's position order and remembers a selected piece for each workspace, creator, and date.
Multiple pieces have separate `plan.piece.<position>` choices. One piece keeps the existing package presentation.
Add a piece opens the existing idea launcher. Cancelling creates no piece. A device ID is allocated while
saving the first extra-piece generation intent. If that save fails, an empty unsaved record is removed.
Generation, retries, replacement, light edits, approval, unpublish, and thumbnail lookup use the selected piece.
The overwrite prompt remains for replacing that piece. Existing Today, Post, and review projections still use position 0.
New controls use PocketSheet type and spacing tokens, vertical expansion, minimum 44-point targets, and shared test scroll helpers.
The move sheet starts at today and has scrollable date choices and week navigation. Earlier dates are not offered.


## Move RPC and durable replay

`move-piece` calls service-only `move_content_piece(payload jsonb)` in the new local migration.
The request contains creator, piece, expected source date, target date, and idempotency key.
Authenticated workspace scope comes from the device session. The HTTP handler checks the active creator.

The RPC locks the request key and both dates in calendar order. Date locks match piece creation's locks.
It rechecks scope, removal, and source under lock. A running generation defers the move without consuming the key.
This includes running legacy jobs linked to one of the piece's revisions.
The client orders the move after earlier generation and before later work for that piece.
Other failed edits or decisions remain queued and receive the new date after acknowledgement.
Repository reads check local change versions before rebinding dates or positions. An older answer cannot move a piece back.

The piece appends at the target. Source positions are compacted from 0 in ascending order, including any older gaps.
The partial unique position index stays active and valid. Position-0 triggers update the compatibility mirrors.
An empty source loses its `creator_days` row. Same-date requests keep their position.
Piece and revision IDs, status, content, shot identity/order, progress, and decisions remain.
All revisions move together. Job dates and saved run result dates follow their revisions.
Archive rows retain original decision dates, frozen text, and revision links.

Older job uniqueness by plan/date and run/date would reject valid moves into an occupied date.
The migration replaces those two restrictions with lookup indexes. Run/day-index uniqueness remains;
the job writer now uses that key. The revision foreign key remains and is checked at transaction completion.
The local rollback harness explicitly forces deferred constraints before rollback.
The job lane cap still counts live jobs per generation run, so two piece runs do not supersede each other.

The same transaction saves normalized request identity and result in `content_piece_moves`.
An exact retry returns the saved result with `replayed = true`. It does not move again or append again.
A changed request with the same key is rejected. API roles cannot write the replay table directly.
The historical guard permits only the move RPC's date-only changes while its private transaction marker is active.
FakeServer persists the same replay records and follows the same ordering, preservation, and error rules.

| Status | Code | Meaning |
| --- | --- | --- |
| 400 | `invalid_piece_id` | Missing or invalid piece ID. |
| 400 | `invalid_move_piece_payload` | Invalid scope, source/target date, or key. |
| 404 | `piece_not_found` | No stored piece. |
| 409 | `piece_scope_mismatch` | Wrong workspace or creator. |
| 409 | `piece_removed` | Removed piece. |
| 409 | `piece_date_conflict` | Source changed. |
| 409 | `piece_generation_running` | Generation must finish; retry keeps the same key. |
| 409 | `idempotency_key_conflict` | Key already identifies different input. |
| 500 | `move_piece_failed` | RPC transport or unexpected persistence failure. |

Existing device authentication, role, and creator lookup errors remain.
The complete wire shape is in [the server contract](creator-loop-server-contract.md).

## Unloaded first-piece edge case

Chosen option: send a date-only generation request for an unloaded date's first piece.
DayStore marks the local placeholder for binding; the outbox persists this date-only request identity.
The server selects or creates position 0. The client binds the server ID before installing the reply.
This also covers older empty local position-0 placeholders. Existing saved generation identities keep their replay rules.
Extra pieces use explicit device IDs. Completed generation also reads the server position before presentation,
so a target date with additional server pieces does not retain an assumed local position.
