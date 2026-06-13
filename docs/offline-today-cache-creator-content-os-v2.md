# Offline Today Cache - Creator Content OS V2

Slice 4 makes Creator Today read the published card through the repository boundary and keep working when Supabase is unavailable.

## Boundary

- `TodayCardRepository` remains the source of truth for live published cards.
- `TodayCacheStoring` is a small local snapshot cache under the data layer.
- `AppServices` hydrates Today from cache before repository refresh, then saves a fresh cache snapshot after a successful repository refresh or weekly publish.
- Views still read `services.todayCard` and `services.weekCards`; no view changes are required.

## Snapshot

The cache stores `CachedTodaySnapshot`:

- `todayCard`: the card Creator should see first.
- `weekCards`: the current published week card set for offline folio/history context.
- `cachedAt`: timestamp for future freshness logic.
- `source`: debug/source label such as `repository-refresh` or `week-publish`.

The file-backed store writes one JSON file per workspace and creator:

`today-{workspaceID}-{creatorID}.json`

This preserves the multi-creator/workspace model while v1 still exposes only Creator.

## Runtime

- Unpaired runtime stays fixture-backed.
- Paired runtime starts with fixture defaults, immediately applies a matching cache snapshot if one exists, then refreshes from Supabase.
- If the Today repository fails, the cached Today card and week cards remain on screen and `lastRepositoryError` records the refresh failure.

## Acceptance

Covered in `CreatorContentOSTests/PublishWeekFixtureAcceptanceTests.swift`:

- Publishing a week stores the published Today card and seven week cards in cache.
- Creator Today loads a cached published card.
- A failing Today repository does not replace the cached card.
