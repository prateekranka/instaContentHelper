# Reference Watchlist Import Implementation Spec: Mamta Content OS V2

This spec defines the build-ready slice for importing Instagram inspiration accounts, reel/audio links, CSV rows, and ambiguous references into the Admin Intelligence system.

The product rule is intentionally simple:

`Paste/upload -> Preview -> Confirm -> Intelligence updates`

There is one ingestion workflow, one fixed watchlist, and one review destination.

## Scope

Build this for Prateek/Admin Mode only.

Included:

- Paste text import.
- CSV upload from Files.
- Edge Function parser as source of truth.
- Fixed destination watchlist named `Inspiration`.
- Clean explicit accounts become active benchmark creators.
- Clean reel/audio URLs become confirmed source references.
- Accounts inferred from reel/post URLs become candidate benchmark creators.
- Unknown/ambiguous rows go into `Needs your call`.
- Story URLs are rejected and not stored.
- Duplicate detection with collapsed preview details.
- Review actions for `Needs your call`: Approve, Dismiss, Edit, Open link.
- Live Supabase runtime only.

Out of scope:

- Instagram scraping.
- Instagram login/session use.
- Automatic trend/pattern/idea generation.
- Multiple watchlists.
- Mamta Mode visibility.
- Analytics dashboard.
- Optimistic review mutations.

## Product Decisions

- Single entry point: `Reference Import`.
- Input methods: paste text and CSV file upload.
- Destination: always `Inspiration`.
- Confirmation required before writes.
- Import preview is mostly read-only.
- Preview can remove rows, but does not support per-row tag/status editing.
- CSV unknown columns are preserved in provenance.
- Edge Function parser is the source of truth.
- iOS reads CSV/plain text as `String`; parsing happens server-side.
- Max import size is 500 non-empty rows.
- Confirm sends raw input again and reparses.
- Confirmation should be transactional where possible.
- Review actions wait for server confirmation.
- Store light audit fields only, no analytics system.

## Classification Rules

| Input | Classification | Write on Confirm | Status |
| --- | --- | --- | --- |
| `@handle` | Account | `benchmark_creators` + `watchlist_benchmark_creators` | `active` |
| `handle` | Account | `benchmark_creators` + `watchlist_benchmark_creators` | `active` |
| Instagram profile URL | Account | `benchmark_creators` + `watchlist_benchmark_creators` | `active` |
| Instagram reel URL | Reel | `source_references`; inferred account as candidate if handle is available | reference `confirmed`, account `candidate` |
| Instagram post URL | Reel/Post reference | `source_references`; inferred account as candidate if handle is available | reference `confirmed`, account `candidate` |
| Recognizable audio URL | Audio | `source_references` | `confirmed` |
| Non-Instagram URL | Unknown | `source_references` | `needs_review` |
| Ambiguous text/row | Unknown | `source_references` | `needs_review` |
| Useful notes without handle/URL | Unknown | `source_references` | `needs_review` |
| Instagram story URL | Invalid | no write | invalid preview row |

Specific content references that are clean are accepted because the admin pasted them intentionally. Approval later means a review action only for unknown rows or inferred candidate accounts.

Confirmed reel/audio references should appear lightly in `Source Pulse`, not in `Ready for this week`, `Idea candidates`, Weekly Plan, or Daily Cards.

## Duplicate Rules

Account duplicates:

- Normalize before compare:
  - trim whitespace
  - lowercase
  - remove leading `@`
  - remove Instagram URL wrapper
  - remove trailing slash
  - remove query params/fragments
- Duplicate key:
  - `workspace_id`
  - `creator_id`
  - `platform = instagram`
  - `normalized_handle`

URL duplicates:

- Normalize before compare:
  - trim whitespace
  - lowercase host only
  - remove fragments
  - remove tracking query params
  - remove trailing slash
- Instagram canonical keys:
  - `instagram:reel:<shortcode>`
  - `instagram:post:<shortcode>`
- Audio canonical key:
  - normalized URL for v1.
- Duplicate key:
  - `workspace_id`
  - `creator_id`
  - `source_type`
  - `canonical_source_key`

Dismissed/poor-fit items still block re-import. Preview should show duplicates collapsed with reasons:

- `Already active`
- `Already candidate`
- `Previously dismissed`
- `Previously marked poor fit`
- `Already confirmed`

## Mixed Row Rules

If a row contains both a handle and a reel/post URL:

- Treat the reel/post URL as primary.
- Create a confirmed `source_references` row.
- Infer account as `candidate` if useful.
- Preserve full raw row in provenance.

If the explicit handle and URL-inferred handle disagree:

- Save the reel/post as confirmed.
- Put the account conflict into `Needs your call`.

CSV column names are hints, not rules. Parser classifies by content first:

- Plain handle in `url` column -> Account.
- Reel URL in `handle` column -> Reel.
- Unknown column containing a recognizable Instagram URL -> classify correctly.
- Preserve original column/value in provenance.

## Database Changes

Add migration:

`supabase/migrations/YYYYMMDDHHMMSS_reference_import.sql`

Implementation note:

- The current `source_references.status` check constraint does not include `needs_review`.
- This must be fixed before building the review queue or Edge Function writes, otherwise unknown/ambiguous import rows cannot be saved cleanly.
- The migration below intentionally replaces the existing status constraint rather than treating `needs_review` as a UI-only state.

Required changes:

```sql
alter table public.benchmark_creators
  add column if not exists normalized_handle text;

alter table public.source_references
  add column if not exists canonical_source_key text;

alter table public.source_references
  drop constraint if exists source_references_status_check;

alter table public.source_references
  add constraint source_references_status_check
  check (status in ('added', 'needs_review', 'analyzing', 'analyzed', 'confirmed', 'dismissed', 'archived'));

create unique index if not exists benchmark_creators_unique_normalized_handle_idx
  on public.benchmark_creators(workspace_id, creator_id, lower(coalesce(platform, '')), normalized_handle)
  where normalized_handle is not null;

create unique index if not exists source_references_unique_canonical_source_idx
  on public.source_references(workspace_id, creator_id, source_type, canonical_source_key)
  where canonical_source_key is not null;

create index if not exists benchmark_creators_review_queue_idx
  on public.benchmark_creators(workspace_id, creator_id, status, updated_at desc);

create index if not exists source_references_review_queue_idx
  on public.source_references(workspace_id, creator_id, status, updated_at desc);
```

Backfill considerations:

- Existing `benchmark_creators.handle` values should be normalized into `normalized_handle`.
- Existing `source_references.source_url` values can leave `canonical_source_key` null unless a one-off backfill parser is added. Null values bypass the unique index.

## RPC Details

Use Edge Functions for request handling and auth, but use Postgres RPC for transactional confirm writes.

Add RPC:

`public.confirm_reference_import(payload jsonb) returns jsonb`

Responsibility:

- Validate workspace/creator relationship.
- Find or create `Inspiration` watchlist.
- Upsert explicit account/profile rows into `benchmark_creators`.
- Upsert inferred candidate accounts into `benchmark_creators`.
- Link accounts to `watchlist_benchmark_creators`.
- Upsert clean source references into `source_references`.
- Save unknown/ambiguous rows into `source_references` with `status = needs_review`.
- Reject invalid rows and report them without writing.
- Preserve provenance.
- Return final counts and saved IDs.

Transaction behavior:

- A Postgres function runs inside a transaction by default.
- If any unexpected write fails, raise an exception so the import fails with no partial write.
- Edge Function should catch the error and return `import_failed_nothing_saved`.

Optional later RPC:

`public.review_reference_item(payload jsonb) returns jsonb`

This can also be implemented directly in the `review-reference` Edge Function using service role if the mutation remains small.

## Edge Function: import-references

Path:

`supabase/functions/import-references/index.ts`

Support files:

- `supabase/functions/import-references/parser.ts`
- `supabase/functions/import-references/csv.ts`
- `supabase/functions/import-references/normalization.ts`
- `supabase/functions/import-references/types.ts`
- `supabase/functions/import-references/parser_test.ts`

Auth:

- Reuse `verifyDeviceSession`.
- Allowed roles: `owner`, `editor`.
- Even though UI access is Admin Mode only, server should still reject non-admin paired roles.

Request:

```json
{
  "mode": "preview",
  "creator_id": "uuid",
  "input_type": "paste",
  "raw_text": "@creator\nhttps://instagram.com/reel/ABC123/",
  "filename": null
}
```

```json
{
  "mode": "confirm",
  "creator_id": "uuid",
  "input_type": "csv",
  "raw_text": "handle,notes\ncreator,Good warmup style",
  "filename": "inspiration.csv",
  "preview_checksum": "sha256..."
}
```

Preview response:

```json
{
  "parser_version": "reference-import-v1",
  "preview_checksum": "sha256...",
  "destination": {
    "watchlist_name": "Inspiration"
  },
  "counts": {
    "total_rows": 24,
    "clean_accounts": 10,
    "clean_reels": 5,
    "clean_audio": 1,
    "needs_review": 3,
    "duplicates": 4,
    "invalid": 1,
    "importable": 19
  },
  "rows": [
    {
      "client_row_id": "line-1",
      "line_number": 1,
      "raw_input": "@creator",
      "type_chip": "Account",
      "classification": "account",
      "normalized_handle": "creator",
      "canonical_source_key": null,
      "title": "@creator",
      "url": null,
      "notes": null,
      "status_on_confirm": "active",
      "preview_state": "clean",
      "duplicate_reason": null,
      "invalid_reason": null,
      "provenance": {
        "raw_input": "@creator",
        "import_source": "paste",
        "parser_version": "reference-import-v1",
        "classification": "account",
        "confidence": 0.95
      }
    }
  ]
}
```

Confirm response:

```json
{
  "parser_version": "reference-import-v1",
  "destination": {
    "watchlist_id": "uuid",
    "watchlist_name": "Inspiration"
  },
  "counts": {
    "imported": 18,
    "needs_review": 3,
    "duplicates_skipped": 7,
    "invalid": 2
  },
  "toast": "Imported 18. 3 need review. 7 duplicates skipped. 2 could not be imported."
}
```

Errors:

- `invalid_json`
- `missing_raw_text`
- `invalid_input_type`
- `row_limit_exceeded`
- `creator_not_found`
- `checksum_mismatch`
- `story_urls_not_allowed`
- `import_failed_nothing_saved`
- `role_not_allowed`

Checksum:

- Preview checksum is SHA-256 of normalized parser input plus parser version.
- Confirm reparses raw input.
- If provided checksum differs, return:
  - `Import changed. Preview again before confirming.`

## Edge Function: review-reference

Path:

`supabase/functions/review-reference/index.ts`

Auth:

- Reuse `verifyDeviceSession`.
- Allowed roles: `owner`, `editor`.

Request:

```json
{
  "creator_id": "uuid",
  "item": {
    "kind": "benchmark_creator",
    "id": "uuid"
  },
  "action": "approve"
}
```

```json
{
  "creator_id": "uuid",
  "item": {
    "kind": "source_reference",
    "id": "uuid"
  },
  "action": "edit",
  "edit": {
    "target_type": "reel",
    "handle": null,
    "url": "https://instagram.com/reel/ABC123/",
    "notes": "Useful transition"
  }
}
```

Actions:

- `approve`
- `dismiss`
- `edit`

`Open link` is client-side only and does not call the function.

Action behavior:

| Item | Action | Result |
| --- | --- | --- |
| candidate account | approve | `benchmark_creators.status = active` |
| candidate account | dismiss | `benchmark_creators.status = poor_fit` |
| unknown source | approve | `source_references.status = confirmed` |
| unknown source | dismiss | `source_references.status = dismissed` |
| unknown -> account edit | edit | create/update account, link to Inspiration, dismiss old import row |
| unknown -> reel edit | edit | update/create `source_references.source_type = reel_link`, `status = confirmed` |
| unknown -> audio edit | edit | update/create `source_references.source_type = audio_link`, `status = confirmed` |

Review provenance:

```json
{
  "reviewed_at": "ISO-8601",
  "review_action": "approve",
  "reviewed_by_member_id": "uuid",
  "resolved_as": "benchmark_creator",
  "resolved_benchmark_creator_id": "uuid"
}
```

Response:

```json
{
  "item_id": "uuid",
  "kind": "source_reference",
  "action": "edit",
  "result_status": "confirmed",
  "toast": "Reference confirmed."
}
```

## Parser Details

Parser version:

`reference-import-v1`

Input types:

- `paste`
- `csv`

CSV known columns:

- `handle`
- `url`
- `display_name`
- `notes`
- `tags`
- `region`

CSV unknown columns:

- Preserve under `provenance.unknown_columns`.
- Do not block import.

Provenance fields:

- `raw_input`
- `import_source`
- `filename`
- `csv_columns`
- `unknown_columns`
- `imported_at`
- `parser_version`
- `classification`
- `confidence`
- `normalized_handle`
- `canonical_source_key`
- `inferred_handle`
- `duplicate_reason`
- `invalid_reason`

Story URL rule:

- Any `instagram.com/stories/...` row is invalid.
- Error copy:
  - `Story URLs can't be used as references.`
- Invalid story rows are not stored.

Malformed Instagram URLs:

- Save as Unknown `needs_review` unless clearly a Story URL.

Private account URLs:

- Allowed.
- Store as unverified in provenance.
- Explicit profile/account imports still become `active`.

Priority defaults:

- Explicit account/profile import: `priority_score = 50`.
- Inferred candidate account from reel/post: `priority_score = 25`.
- `mamta_relevance_score = null`.

## Swift File and Module Changes

Update:

- `MamtaContentOS/Data/AppRepositories.swift`
  - Add `referenceImport: any ReferenceImportRepository`.
- `MamtaContentOS/App/AppServices.swift`
  - Add import/review state and methods.
- `MamtaContentOS/Data/SupabaseClientFactory.swift`
  - Construct `SupabaseReferenceImportRepository`.
- `MamtaContentOS/Data/SupabaseRepositories.swift`
  - Add `SupabaseReferenceImportRepository`.
  - Update Intelligence counts to include live benchmark creator count.
  - Update Source Pulse query to include confirmed imported reel/audio references.
  - Update Needs your call query to include source refs with `needs_review` and benchmark creators with `candidate`.
- `MamtaContentOS/Data/SupabaseDTOs.swift`
  - Add request/response DTOs for import preview, confirm, review.
- `MamtaContentOS/Models/Models.swift`
  - Add import/review models.
- `MamtaContentOS/Features/Intelligence/IntelligenceHomeView.swift`
  - Add Reference Import entry point.
  - Make `Needs your call` chronological with type chips.
  - Add navigation to Benchmark Creators if needed.

Add:

- `MamtaContentOS/Features/Intelligence/ReferenceImportView.swift`
- `MamtaContentOS/Features/Intelligence/ReferenceImportPreviewView.swift`
- `MamtaContentOS/Features/Intelligence/ReferenceReviewEditSheet.swift`
- `MamtaContentOS/Features/Intelligence/BenchmarkCreatorsView.swift`
- `MamtaContentOS/Data/ReferenceImportDTOs.swift`
- `MamtaContentOS/Data/ReferenceImportRepository.swift`

Suggested Swift models:

```swift
struct ReferenceImportPreview: Codable, Hashable, Sendable {
    var parserVersion: String
    var previewChecksum: String
    var destination: ReferenceImportDestination
    var counts: ReferenceImportCounts
    var rows: [ReferenceImportRow]
}

struct ReferenceImportRow: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var lineNumber: Int
    var rawInput: String
    var typeChip: ReferenceImportTypeChip
    var classification: String
    var title: String
    var url: String?
    var notes: String?
    var previewState: ReferenceImportPreviewState
    var duplicateReason: String?
    var invalidReason: String?
}

enum ReferenceImportTypeChip: String, Codable, Sendable {
    case account = "Account"
    case reel = "Reel"
    case audio = "Audio"
    case unknown = "Unknown"
}

enum ReferenceImportPreviewState: String, Codable, Sendable {
    case clean
    case needsReview = "needs_review"
    case duplicate
    case invalid
}
```

Repository:

```swift
protocol ReferenceImportRepository: Sendable {
    func previewImport(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String?,
        context: WorkspaceContext
    ) async throws -> ReferenceImportPreview

    func confirmImport(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String?,
        previewChecksum: String,
        context: WorkspaceContext
    ) async throws -> ReferenceImportConfirmResult

    func reviewItem(
        _ request: ReferenceReviewRequest,
        context: WorkspaceContext
    ) async throws -> ReferenceReviewResult
}
```

Fixture runtime:

- This feature only works in live Supabase runtime.
- Fixture implementation should throw:
  - `Connect live workspace to import references.`
- UI may show the entry disabled if runtime is fixture-backed.

## UI States

Entry point:

- Admin Mode -> Intelligence -> top action or Library row -> `Reference Import`.
- Hidden from Mamta Mode.
- Disabled in fixture runtime.

Import screen states:

1. Empty
   - Paste field.
   - `Choose CSV` button.
   - `Preview Import` disabled until input exists.

2. Input ready
   - Shows source label: `Paste` or filename.
   - `Preview Import`.
   - `Clear`.

3. Preview loading
   - Disable actions.
   - Show quiet progress.

4. Preview ready
   - Summary counts.
   - Sections:
     - clean rows shown normally.
     - `Needs your call` rows shown normally.
     - duplicates collapsed.
     - invalid rows collapsed or visible if present.
   - Actions:
     - `Import clean rows`
     - `Edit paste`

5. Confirming
   - Disable preview row removal and confirm.
   - Show row-independent saving state.

6. Success
   - Toast:
     - `Imported 18. 3 need review. 7 duplicates skipped.`
   - Refresh Intelligence Home.
   - Pop back or stay with completed summary. Recommended: stay with completed summary and a `Done` action.

7. Error
   - Show toast or inline message.
   - Preserve input.
   - Do not write partial rows on confirm failure.

Needs your call:

- One chronological list, newest first.
- Type chips:
  - Account
  - Reel
  - Audio
  - Unknown
- Row actions:
  - Approve
  - Dismiss
  - Edit
  - Open link
- Mutating actions wait for server confirmation.
- Open link uses external URL and does not mutate.

Edit sheet:

- Compact sheet.
- Fields:
  - type picker: Account, Reel, Audio, Unknown
  - handle field for Account
  - URL field for Reel/Audio/Unknown
  - notes field
- Save behavior:
  - Unknown -> Account creates/updates benchmark creator, links Inspiration, dismisses old import row.
  - Unknown -> Reel/Audio confirms source reference.
  - Manual correction counts as approval.

## Visual Direction

Keep the Training Folio direction:

- Premium editorial fitness journal.
- Warm, calm, precise.
- No dense SaaS import tables.
- Use thin-rule rows.
- Keep duplicates collapsed.
- Keep provenance out of the primary rows.
- Use small chips, not heavy cards.
- Use sparse Liquid Glass only for floating controls or sheet chrome if needed.

## Tests

Edge Function parser tests:

- `@handle` -> Account.
- `handle` -> Account.
- `instagram.com/handle` -> Account.
- private-looking profile URL -> Account active, unverified provenance.
- `instagram.com/reel/ABC123` -> Reel confirmed.
- `instagram.com/p/ABC123` -> Reel/Post confirmed.
- reel URL with inferred handle -> candidate account.
- mixed row handle + reel -> reel primary, account candidate.
- conflicting handle + URL handle -> reel confirmed, account conflict needs review.
- `instagram.com/stories/...` -> invalid story error.
- malformed Instagram URL -> Unknown needs review.
- non-Instagram URL -> Unknown needs review.
- notes-only CSV row -> Unknown needs review.
- CSV known columns map correctly.
- CSV unknown columns preserved.
- classify by content, not column name.
- duplicate handle normalization.
- duplicate URL normalization.
- dismissed/poor-fit duplicates remain duplicates.
- row limit over 500 returns error.
- empty trimmed rows do not count toward 500.
- confirm checksum mismatch returns error.

Edge Function integration tests against local Supabase:

- Preview does not write rows.
- Confirm creates `Inspiration` if missing.
- Confirm uses existing `Inspiration` if present.
- Confirm writes explicit accounts active.
- Confirm writes inferred accounts candidate.
- Confirm writes clean reel/audio confirmed.
- Confirm writes unknown rows needs_review.
- Confirm rejects story URLs without saving them.
- Confirm returns correct counts.
- Confirm is transactional on forced insert failure.
- Review approve candidate account -> active.
- Review dismiss candidate account -> poor_fit.
- Review approve unknown source -> confirmed.
- Review dismiss unknown source -> dismissed.
- Edit Unknown -> Account resolves old row and creates/updates account.
- Edit Unknown -> Reel/Audio confirms source.

Swift tests:

- Import preview DTO decode.
- Confirm result DTO decode.
- Review result DTO decode.
- File import text handoff preserves contents.
- UI state transitions:
  - empty -> input ready -> loading -> preview ready.
  - confirm success toast.
  - confirm failure preserves input.
- Fixture runtime disables or errors clearly.

Manual acceptance test:

1. Pair/live-configure Admin device.
2. Switch to Prateek/Admin Mode.
3. Open Intelligence.
4. Open Reference Import.
5. Paste mixed input:
   - 2 account handles.
   - 1 Instagram profile URL.
   - 2 reel URLs.
   - 1 non-Instagram URL.
   - 1 ambiguous note.
   - 1 duplicate.
   - 1 story URL.
6. Preview shows:
   - clean accounts.
   - clean reels.
   - Unknown rows.
   - collapsed duplicate.
   - invalid story row.
7. Confirm import.
8. Toast reports imported, needs-review, duplicate, and invalid counts.
9. Source Pulse shows confirmed reel/audio references lightly.
10. Needs your call shows candidate accounts and unknown rows in chronological order with chips.
11. Approve a candidate account; it leaves Needs your call.
12. Dismiss another candidate account; it becomes poor_fit and leaves Needs your call.
13. Edit Unknown -> Reel; it becomes confirmed and appears in Source Pulse.
14. Mamta Mode remains unchanged.

## Build Order

1. Add migration for normalized/canonical keys and `needs_review` status.
2. Build TypeScript parser and Deno tests.
3. Add `import-references` preview mode.
4. Add RPC and confirm mode.
5. Add `review-reference` function.
6. Add Swift DTOs and repository boundary.
7. Add Supabase repository implementation.
8. Add Import screen and CSV file importer.
9. Update Intelligence `Needs your call` and Source Pulse.
10. Add compact edit sheet and review actions.
11. Run local Supabase validation.
12. Run Swift tests.
13. Run simulator acceptance test.

## Rollout Notes

- This is safe to ship to TestFlight because it is Admin-only and live-Supabase-only.
- If Supabase runtime is missing, the UI should not pretend import worked.
- No Mamta-facing behavior should change.
- No imported raw source should become a Daily Card without a later intelligence/planning step.
