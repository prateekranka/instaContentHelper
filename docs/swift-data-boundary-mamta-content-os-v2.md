# Swift Data Boundary: Mamta Content OS V2

This slice introduces the app-side repository boundary while keeping the normal visible app experience fixture-safe.

## Runtime Mode

Current visible runtime remains fixture-backed unless a paired session already exists in Keychain:

- `MamtaContentOS/App/MamtaContentOSApp.swift` creates `AppRuntime`.
- `AppRuntime` loads a paired session from Keychain when present.
- Without a paired session, `AppServices.preview` and `AppRepositories.fixture` are used.
- No pairing UI, Supabase auth UI, or required live network read is exposed yet.

## Repository Contract

Repository protocols live in:

- `MamtaContentOS/Data/AppRepositories.swift`

Main contracts:

- `TodayCardRepository`
- `WeeklyPlanRepository`
- `ReferenceRepository`
- `IntelligenceRepository`
- `CreatorProfileRepository`
- `ArchiveRepository`

The shared context object is `WorkspaceContext`, currently seeded with stable fixture IDs for Mamta's workspace, creator, and member.

## Fixture Runtime

Fixture implementations live in:

- `MamtaContentOS/Fixtures/FixtureRepositories.swift`

They return the existing fixture objects and preserve the current UI behavior:

- Today card loads from `DailyCard.raceWeekToday`.
- Weekly Control loads from `WeeklyPlan.raceWeek` and `WeeklyIdea.raceWeekBank`.
- Intelligence loads from `IntelligenceHome.raceWeekLibrary`.
- Archive loads from `ArchiveEntry.fixtures`.
- Today decisions and weekly idea selection route through repository methods.

## Supabase Boundary

Supabase Swift is now added through XcodeGen:

- `project.yml`
- Resolved package: `supabase-swift` `2.46.0`

Live wiring lives in:

- `MamtaContentOS/Data/SupabaseClientFactory.swift`
- `MamtaContentOS/Data/SupabaseDTOs.swift`
- `MamtaContentOS/Data/SupabaseRepositories.swift`
- `MamtaContentOS/Data/RuntimeConfigurationStore.swift`
- `MamtaContentOS/Data/DevicePairingService.swift`

These files define:

- `SupabaseRuntimeConfiguration`
- `SupabaseContentTable`
- `SupabaseRepositoryBundleFactory`
- `SupabaseBootstrapConfiguration`
- `PairedDeviceSession`
- `RuntimeConfigurationStore`
- `DevicePairingService`
- DTO rows for daily cards, weekly plans, weekly setup, ideas, references, patterns, trends, audio options, creator profile, and archive.
- Live repository types matching the fixture protocols.

Runtime still stays on fixtures until a device has been paired and a valid session exists in Keychain.

Current live repository coverage:

- Today reads `daily_cards` for the current date.
- Week reads the latest published `weekly_plans` row plus its `daily_cards`.
- Idea bank reads `ideas`.
- Weekly publish invokes the `publish-week` Edge Function, then reflects a soft-locked plan in app state.
- Source pulse reads `source_references`.
- Intelligence reads `patterns`, `trends`, `audio_options`, and `ideas`.
- Creator profile reads the active `creator_profiles` row.
- Archive reads and upserts `archive_entries`.

The direct decision/archive write path is useful for dev/admin verification. Production device-paired writes should still move through Edge Functions before this is exposed to Mamta's phone.

Device pairing path:

- Local config keys come from `MamtaContentOS/Config/Runtime.xcconfig`, optional `LocalRuntime.xcconfig`, app Info.plist keys, or process environment.
- Keychain-backed project URL, publishable key, workspace context, and device token storage are in place.
- Invite exchange is scaffolded through `supabase/functions/pair-device/index.ts`.

Still needed before relying on live device runtime:

- Deploy and verify `pair-device` against a real Supabase project.
- Deploy and verify `publish-week` against a real Supabase project.
- Add Edge Functions for privileged creator daily decisions.
- RLS grants or function read paths reviewed against the exact device-token access model.

## Next Slice

Add offline Today cache from the synced daily card, still keeping Mamta's visible flow simple.
