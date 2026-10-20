# Creator loop server contract

Implemented through phase 6, including round 4 generation recovery, history protection, repost persistence, and shot validation. Local changes only.
No live migration or deployment is authorized.
The approved scope is section 3 of `creator-loop-redesign.md`.

## Records and invariants

- `daily_cards.id` is the revision ID. Each successful generation inserts a new row with a new ID.
- `creator_days` has one row per `(workspace_id, creator_id, scheduled_date)`.
- `creator_days.current_revision_id` points at the current revision. It can be null before the first successful generation.
- `daily_cards.is_current` controls mutation eligibility. Replacement acceptance clears it immediately; the day pointer can retain that archived revision for recovery. An insert points to the new current revision.
- `creator_days.generation_run_id` points at the latest generation run. Read its status before treating the day as generating.
- `daily_cards.generation_run_id` identifies the run that made the revision. A run can create at most one revision per date.
- Superseded revisions stay in `daily_cards` with `status = archived` and `is_current = false`.
- Superseding a revision preserves its content, decision fields, references, and filming data. New revisions start with fresh thumbnail assets.
- Historical revision content and identity cannot be changed. Thumbnail completion can still attach assets to its exact revision.
- `archive_entries.daily_card_id` remains the exact revision ID. Its unique constraint remains the decision upsert key.
- `archive_entries.title_snapshot`, `caption_snapshot`, and `decision_at` record the package at the decision.
- A current revision permits Undo posted: `posted` changes to `shot` with a new `decision_at`.
- Undo keeps the archive entry ID and its title and caption snapshots, even if the current package text has changed.
- A repeat posted decision on the current revision returns the stored entry, including its original timestamp and text.
- Once a revision is replaced, its archive entry is frozen for every decision type. Exact retries return the saved entry without writes.
- A replacement without a prior decision creates an archive entry with `decision = replaced`. It does not claim the content was posted.
- Current Today and Plan reads filter on `is_current`. Archive reads use snapshots and do not join mutable card text.

`creator_days` and the new SQL RPCs are available only to `service_role`.
HTTP functions keep device-token authentication and workspace and creator checks.
No model endpoint, model input contract, prompt, or provider setting changes in this phase.

## HTTP: `generate-week`

Existing actions and fields remain accepted. Full-week generation remains retired.

| Action | Input |
| --- | --- |
| `generate_day` | Existing `creator_id`, `scheduled_date`, `day_brief`, `mock`, and `response_mode`; optional `idempotency_key`. |
| `regenerate_day` | Existing `creator_id`, `weekly_plan_id`, `scheduled_date`, `preserve_manual_edits`, `day_guidance`, `input_overrides`, `mock`, and `response_mode`; optional `idempotency_key`. |
| `status` | Existing `generation_id` and optional `creator_id`. |

An idempotency key is a nonblank string with at most 200 characters after trimming.
The key is unique within a workspace and creator, across dates and generation actions.
If an old caller omits it, the server assigns a fresh UUID key. Such separate requests are separate generation intents.
Clients must save a key before the first request to obtain replay protection after a lost response.

The request identity includes the normalized action, date, brief or guidance, edit preservation, mock flag,
input overrides, and explicit target revision. Regeneration also includes the plan ID.
Transport mode is excluded. A synchronous request can be retried in asynchronous mode with the same key.
Object key order does not affect identity. Existing brief length limits remain in effect.

- Same key and identity: return the existing run or saved result. Do not start another worker.
- Same key and different identity: return HTTP 409, `idempotency_key_conflict`.
- New brief: use a new key. This creates a new run.
- New key for a day with an active run: close the previous run with `generation_superseded` and start a new run.
- Ready or decided current revisions require `replace-day`, or the existing explicit unpublish flow.
- A failed run stays closed. A retry requires a new key.

Synchronous success keeps the existing draft response, including `daily_card.id`.
It adds `idempotency_key` and, for replacement, `replaced_daily_card_id`.
Asynchronous success remains HTTP 202 with `generation_id`, `weekly_plan_id`, `status = running`,
`target_scheduled_date`, and `poll_after_seconds`. It adds the same key and replacement fields.
A replay adds `replayed = true`. Completed replays return the saved draft snapshot.
Failed replays return HTTP 200 with `status = failed`, the run ID, `error`, and `poll_after_seconds = null`.
A running replay returns HTTP 202 and the existing run ID.

Generation errors, validation errors, and persistence errors close runs with `completed_at`.
A status poll closes a stale single-day worker with `generation_stale`. It does not resume that worker.
The existing worker heartbeat rules determine status-poll staleness.
A keyed replay or server claim also closes a running run after ten minutes without a database update.
Revision insertion and the completed run snapshot commit in one transaction. Worker interruption after insertion cannot leave a saved draft behind a running run. Finalization can enrich an already completed snapshot; failure writes still apply only to running runs. Database guards reject reopening a terminal run.

A queued request rejected with `past_generation_date_not_allowed` is terminal. The native outbox restores the day from generating. An unaccepted firstIdea request retargets to the creator's current today, saves that date, and replays. Other generation intents stop and show that the day has passed.

Additional errors:

| HTTP | Code | Meaning |
| --- | --- | --- |
| 400 | `invalid_idempotency_key` | The supplied key is blank, not text, or too long. |
| 409 | `idempotency_key_conflict` | The key belongs to another request identity. |
| 409 | `replace_day_required` | The day has a ready or decided current revision. |
| 409 | `generation_run_closed` | A superseded or closed run tried to persist. |
| 404 | `generation_run_not_found` | The scoped run does not exist. |
| 500 | `generation_lookup_failed` | Replay lookup failed. |

Existing validation and authentication errors remain. A late worker cannot overwrite the newer run's revision.

## HTTP: `replace-day`

POST input:

```json
{
  "creator_id": "<uuid>",
  "scheduled_date": "2026-10-21",
  "daily_card_id": "<optional expected revision uuid>",
  "day_brief": "A new brief for this day",
  "idempotency_key": "<saved intent key>",
  "response_mode": "async",
  "mock": false
}
```

`day_brief` is required. `response_mode` defaults to `sync`.
The key is optional for consistency with old generation callers, but clients should always supply it.
The optional revision ID acts as an expected-current-revision check. The server finds the plan from the current day.
The server permits replacement inside a published or locked plan without unlocking the other days.

One SQL transaction archives the old revision, removes its ready status, and inserts the running generation record.
The transaction does not call an AI provider. Provider work starts only after that transaction commits.
If the transaction fails, it rolls back all three changes. A provider failure after acceptance closes the run;
it leaves the archived revision and its filming data available for recovery.
The old revision remains the day pointer until the new revision is saved. Acceptance sets its status to archived and is_current to false. Late decisions and undo return historical_revision_immutable, even before provider work finishes. Exact historical retries still return the saved entry.

Success and replay responses match the day-generation responses above.
`replaced_daily_card_id` identifies the old revision. Same-key replay checks occur before current-state validation.
An old replacement request can therefore replay after its replacement is current.

Errors include the generation errors above, `day_brief_required` (400), `past_generation_date_not_allowed` (400),
`daily_card_not_found` (404, including an expected revision mismatch), `weekly_plan_not_found` (404),
and the existing authentication, creator lookup, and generation persistence errors.

## HTTP: `update-ready-day-package`

Inputs stay `creator_id`, either `daily_card_id` or `scheduled_date`, and `package`.
If both target fields are supplied, both must match the current revision.
The package remains a partial update. Omitted fields stay unchanged.

For each supplied `title`, `why_today`, `caption`, `script`, `backup_story`, `backup_caption_only`,
or `shootability`:

- Reject empty or whitespace-only text with HTTP 400, `blank_package_text`.
- Reject null and non-string values with HTTP 400, `invalid_package_text`.
- Return the failing field name as `field`. Do not write any part of the patch.

Both the HTTP boundary and the SQL function enforce this rule.
Backup text is stored as a JSON string when supplied; existing JSON objects survive when the field is omitted.
Existing numeric behavior remains.

If `scene_list` is supplied, it must be an array. Each element must be an object with:

- `id`: a UUID string in canonical 8-4-4-4-12 hexadecimal form, case insensitive.
- `title`: a string.
- `duration`: a string, including the client's existing `"5 sec"` form.
- `dialogue`: an optional string. An omitted value and an empty string are valid; explicit null is invalid.

Reject a malformed array or shot with HTTP 400, `invalid_package_scene_list`, and `field = scene_list`.
For an invalid shot, include its zero-based `shot_index`. Invalid list types have no shot index.
No part of a rejected patch is written. An omitted `scene_list` keeps the stored shots;
an empty array remains valid. This validation checks types, without new nonblank, duration-format, or uniqueness rules.
Additional shot metadata is retained, including the current client's `number` and `symbol` fields.
The edge function, SQL RPC, and `FakeServer` enforce the same shot shape. Native stored-card and generation decoders process each shot separately; a malformed shot cannot discard valid siblings.
Round 4 updates the phase 6 validation function in the new `20261021100000_round4_creator_loop_recovery.sql` migration.
Earlier migrations remain unchanged. Replacing the SQL function preserves its service-only execution grants.

A valid edit keeps the revision ID and ready status. It cannot change an existing posted archive snapshot.
Historical revision IDs cannot target package edits. A date selects only its current ready revision.

Success keeps `daily_card_id`, `scheduled_date`, `status`, `weekly_plan_id`, `title`, and `caption`.
Existing error codes remain: `invalid_update_ready_day_package_payload` (400), `daily_card_not_found` (404),
`daily_card_not_ready` (409), `daily_card_incomplete` (400),
`update_ready_day_package_conflict` (409), and `update_ready_day_package_failed` (500).

## HTTP: `write-content`

Existing inputs remain accepted for `complete_today` and `upsert_archive_decision`.
`daily_card_id` always means an exact revision ID.

`complete_today` now saves the card decision and its archive snapshot in one SQL transaction.
It keeps its `daily_card` result and adds `archive_entry`.
`upsert_archive_decision` still returns `archive_entry`.
Both results add `title_snapshot`, `caption_snapshot`, and `decision_at` to that entry.

The revision ID is the upsert key. Replays do not create duplicate archive entries.
Both actions permit a decision change on the current revision, including `posted` to `shot`.
For that undo, the archive entry keeps its ID, title snapshot, and caption snapshot.
It receives a new `decision_at`. An omitted time uses the server clock, not the previous card decision time.
`complete_today` changes the current card and its archive entry in the same transaction.
`upsert_archive_decision` keeps its archive-only write behavior.
After Unpublish and Make ready, another posted decision restores the live card status and decision time from the stored archive entry. It keeps one archive row and its existing snapshots.
A same-decision retry keeps the stored decision time. A repeated current `posted` decision keeps the entire stored archive entry.

A replaced revision cannot receive an undo, a different decision, or changed archive metadata.
Changes to any replaced entry return HTTP 409, `historical_revision_immutable`, including posted history.
This includes a late first decision for an entry whose stored decision is `replaced`.
An exact historical retry must match the saved decision, archive date, output line, thumbnail flag,
and decision time when supplied. It returns the saved archive entry without updating either revision.
Decision writes lock the day before the revision, in the same order as replacement.
Replacement and undo therefore cannot change the archive at the same time.

Other write actions keep their existing contracts.
The previous SQL implementation is retained as a private helper for those unrelated actions.
Its direct execute grant is removed from API roles, including `service_role`.

## HTTP: `read-content`

Existing `today` and `weekly` actions return current revisions only, with the existing response shapes.
Existing `archive` returns decided entries and excludes internal `replaced` entries.
Each archive entry adds `revision_id`, `title_snapshot`, `caption_snapshot`, and `decision_at`.
The existing nested `daily_cards.title` field now comes from `title_snapshot`.
The nested object also supplies the frozen caption. Old clients keep their existing title field.

New action `days` accepts the existing `creator_id` field. Owner, editor, and creator roles can use it.
It returns one consistent SQL snapshot:

```json
{
  "days": [{
    "scheduled_date": "2026-10-21",
    "current_revision_id": "<uuid or null>",
    "generation_id": "<latest run uuid or null>",
    "revision": {},
    "generation": {
      "generation_id": "<uuid>",
      "status": "running",
      "error_code": null,
      "idempotency_key": "<key>",
      "completed_at": null
    },
    "updated_at": "<timestamp>"
  }]
}
```

`revision` is the stored current card or null. `generation` is the latest run summary or null.
No row means the day has no stored revision or generation yet. Empty results return `days = []`.
Lookup failure returns HTTP 500, `days_lookup_failed`. Existing read errors remain.

## Existing lifecycle functions

`publish-day` / SQL `publish_day_atomic`, `make-day-available` / SQL `make_day_available`,
and `unpublish-day` / SQL `unpublish_day` keep their inputs and outputs.
Their SQL lookups now select only the current revision and lock it before mutation.
An explicit historical revision ID returns `daily_card_not_found`.
`unpublish_day` keeps existing archive snapshots and clears the current card's live decision fields.
`publish_day_atomic.archived_card_count` remains present. Historical rows are already archived when superseded.

## Service-only SQL RPCs

Each RPC accepts one `payload jsonb` argument. HTTP handlers supply the authenticated scope.
Business errors return `{error, status}`. Transport/database errors become the HTTP persistence errors above.

| Function | Payload | Success |
| --- | --- | --- |
| `start_day_generation` | `workspace_id`, `creator_id`, `weekly_plan_id`, `scheduled_date`, `member_id`, `model`, `input_snapshot`, `idempotency_key`, `request_identity`; optional `preserve_manual_edits` | Full stored run plus `replayed`. |
| `replace_day` | Same payload; optional expected `daily_card_id` | Full stored run plus `replayed` and `replaced_daily_card_id`. |
| `persist_day_revision` | `workspace_id`, `creator_id`, `generation_id`, `card` containing generated package fields | Full stored new revision. Replay returns that run's existing revision. |
| `read_creator_days` | `workspace_id`, `creator_id` | The `days` object above. |

The start RPCs can return `invalid_generation_payload` (400), `weekly_plan_not_found` (404),
`date_not_in_plan` (400), `daily_card_not_found` (404), `existing_published_week_locked` (409),
`replace_day_required` (409), and `idempotency_key_conflict` (409).
Persistence can return `generation_run_not_found` (404) and `generation_run_closed` (409).
Database guards raise `generation_run_closed`, `revision_identity_immutable`,
`historical_revision_immutable`, or `archive_revision_immutable` when a caller attempts a prohibited direct mutation.
The archive guard also rejects direct updates and deletes of replaced entries.
The correction is in `20261020162000_allow_current_revision_posted_undo.sql`.
The phase 1 migrations remain unchanged.

## Proposed movement of existing live rows

Do not run this section against a live project without separate approval.
The new migrations contain the following conversion for a future reviewed deployment:

1. Back up the database and stop generation and lifecycle writes during the conversion.
2. Keep every existing `daily_cards.id`. Treat each surviving row as one revision.
3. Remove the per-plan/date uniqueness constraint. Keep all existing foreign-key targets.
4. Choose one current row per creator and date, ordered by `updated_at DESC`, `created_at DESC`, then ID.
5. Create `creator_days` pointers and set `is_current` only on those selected rows.
6. Copy each archive row's currently linked title, caption, and decision time into the new snapshot columns.
7. Keep existing generation runs with null keys. New keyed intents never attach to those legacy runs.
8. Verify counts, pointer ownership, posted archive snapshots, and active-run recovery before enabling writes.

Earlier generations that were overwritten or deleted cannot be reconstructed from the surviving row.
An old archive that already points at overwritten text cannot recover its original title or caption from this migration.
Recover those values from a trusted backup or historical export before the conversion if they are available.
Conflicting existing rows need product review before accepting the deterministic current-row selection above.
The conversion does not invent missing history.

## Local checks

Run Deno checks from `supabase/functions` or the repository root:

```sh
deno task ci:backend
```

If Docker and a local Supabase stack are available, run `supabase start` and `supabase db reset --local`.
Then run the rollback-only database transaction test against that local database:

```sh
MCO_LOCAL_DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  deno test --allow-env --allow-read --allow-run=psql supabase/functions/_shared/creator-loop-db_test.ts
```

The database test refuses remote URLs. It rolls back its fixture data.
It rejects malformed scene lists and shots without changing any revision fields.
It accepts empty lists and current client shots, including optional dialogue and retained metadata.
The edge-function Deno tests cover all required field types, optional dialogue, later invalid shots,
the current Swift payload, and SQL error-code and shot-index forwarding without a database connection.
It checks current posted undo through both decision actions, new undo timestamps, retained text snapshots,
and safe retries. It rejects decision changes and metadata changes for replaced posted and shot revisions.
It also checks direct archive mutation and deletion guards, frozen posted snapshots, late undecided writes,
revision insertion, replacement rollback, filming data, key conflicts, persistence replay, run closure,
the day pointer, and service-only RPC grants.
Without `MCO_LOCAL_DATABASE_URL`, it is reported as ignored. This is not proof that migrations applied.
If the local URL cannot be reached, report that result separately. Do not use a live project as a fallback.
