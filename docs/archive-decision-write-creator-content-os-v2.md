# Archive Decision Write - Creator Content OS V2

Slice 5 makes Creator's Today decision write into Archive.

## Decision Model

`DailyDecision` carries the final state plus the user-visible output line:

- `shot`: shot today, ready to post
- `posted`: posted
- `usedBackup`: 10-second story or caption-only post
- `savedForTomorrow`: saved this card for tomorrow
- `skippedIntentionally`: skipped after decision

`Can shoot today` remains an intent signal. The persisted positive completion state is `shot`.

## App Flow

- `ShootFolioView` can mark the current card as `shot`.
- `NotTodaySheet` commits one of the lightweight fallback decisions directly:
  - 10-second story
  - Caption-only post
  - Save for tomorrow
  - Skip intentionally
- `AppServices.completeTodayImmediately(with:)` optimistically updates:
  - `todayCard.completionState`
  - `archiveEntries`
  - the local Today cache
- Repository sync then updates the daily card and upserts one `archive_entries` row for the daily card.

## Supabase

Archive writes are idempotent by `daily_card_id`.

Migration `20260605090000_allow_shot_archive_decisions.sql` adds `shot` as an allowed `archive_entries.decision`, matching the existing `daily_cards.status` value.

## Acceptance

Covered in `CreatorContentOSTests/TodayCardAndPostedFlowTests.swift`:

- Backup decision writes a specific Archive output line.
- Shot decision writes a positive Archive entry.
- Repository failure still leaves the local Archive and Today card with Creator's decision.
