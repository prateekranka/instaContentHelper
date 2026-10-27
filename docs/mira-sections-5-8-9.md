# Mira plan sections 5, 8 and 9

The owner selected these plan sections on 2026-10-27. This record describes source
implementation and domain verification. Native build, UI, speech and accessibility
verification remain open under the existing archive/device waiver.

[Pushed implementation](https://github.com/prateekranka/instaContentHelper/commit/27d54bc2d3722be53a14e4e269e799da363f355f)
and [passing GitHub Actions](https://github.com/prateekranka/instaContentHelper/actions/runs/40478325363).
The Swift and PostgreSQL jobs both passed for this exact source commit.

## Section 5 — navigation and screens

- Today and Projects retain independent typed paths and the selected tab. Today
  prioritizes the last unfinished project the creator visited. Continue and project
  rows resume its saved editor or focused filming position.
- Quick ideas retain editable time/location/style/equipment assumptions and distinguish
  filming time from Reel duration. Each concept offers Use this idea and Adjust this
  idea. Adjustment includes that concept in an editable request and retains old ideas.
- Script supports manual hook, words, caption, runtime and language-label editing;
  revisions and restoration remain available. The language label does not translate
  the words. Contextual Ask Mira handles rewriting.
- Make shot list confirms the current source script. A new shot list becomes the
  selected project section. The script/shot picker persists its selection.
- Shot overview, expandable instructions, voiceover, requirement mappings and stale-plan
  warnings remain. Generation controls are disabled while an earlier request runs.
- Shooting keeps one shot visible with previous/next, filmed/review status and contextual
  simplification. Store commands own progress changes and persist the current position.
- Projects exposes Rename, Archive/Unarchive, confirmed Delete and Resume. Deleted
  projects are removed from both saved navigation paths.

Native screen layout and interaction have not been run. These source changes do not
establish successful SwiftUI type-checking, rendering or device behavior.

## Section 8 — state, revisions and persistence

The versioned document now stores optional typed navigation and per-project editor
state. Earlier v2 documents remain readable without these fields. The legacy last-position
record remains a restoration fallback. Invalid routes to deleted projects are removed.

Atomic writes, serialized repository access, sequence protection, debounced typing and
immediate important saves remain. A missing primary file now triggers recovery from an
existing backup instead of opening an empty library. Recovery reports a notice. Corrupt
or future-version backups stay preserved and block an empty replacement.

Undo checkpoints also preserve shot index, filming state and source-script approval.
When a generated shot list changes length, undo can restore the original filming position.
Unchanged-shot matching consumes each old shot at most once. Requirement mapping IDs are
rewritten in one pass, so generated ID swaps retain the correct source shot. Changed shots
keep separate review status and cannot acquire another shot's filmed credit.

Generation remains separate from user stages. Manual editing remains local. AI revisions
remain proposals; late responses retain their input revision, and stale plans stay visible.
The backend contract, provider setup and deployment status were not changed in this pass.

## Section 9 — native architecture

`CreatorContentOSApp` owns `MiraDependencies`. Its live factory creates one repository
actor and one observable store, and supplies generation and speech factories. The same
repository implements project and profile persistence so the document remains atomic.
`MiraStore` requires an injected repository and contains no filesystem-default construction.

The generation adapter accepts a URLSession. Native authentication and consent checks
remain in the dependency boundary. Demo generation stays explicit. Its deterministic
service moved into the cross-platform core, alongside the typed routes, models, workflow,
validation and persistence abstraction. No component-specific view models were added.

Speech controls use the injected `MiraSpeechInputService` interface. The implementation
owns permissions and recording lifetime. A stopped or dismissed attempt cannot start
recording after permission returns, and callbacks from an old recording cannot update
the current transcript. Native speech behavior is still unverified.

Existing app resources remain in the shipping target; these changes add no resources.
Core fixtures are Swift values, so they need no bundle lookup. No `Bundle.main` substitute
for SwiftPM resources was introduced. Existing source-file membership is retained.

## Verification

`bash scripts/mira-core-check.sh` passed 19 tests across two suites with Swift 6.4.1.
The seven new regressions are in [MiraPriorityTests.swift](../Tests/MiraCoreTests/MiraPriorityTests.swift):

1. Reopen independent tabs and the selected editor.
2. Restore legacy navigation and discard deleted-project routes.
3. Recover a missing primary save with an explicit notice.
4. Preserve corrupt/future backups without opening an empty replacement.
5. Keep identities and filmed credit distinct for repeated shot content.
6. Preserve requirement mappings when generated shot IDs swap.
7. Restore position and approval after undoing a shorter shot list.

The first sandboxed compiler run hit a local CFSocket error and timed out. The same
checks passed with local IPC available. This was not an application test failure.
The seven priority regressions passed again after the final recovery-error correction;
GitHub Actions then passed the complete core suite for the pushed source commit.
The Swift frontend parsed all native Mira views/services and the app entry without syntax
errors. Parsing is not native type-checking, linking or runtime verification.

Full native build and TesterArmy native UI checks remain unverified. Existing toolchain
limitations are recorded in [the toolchain record](mira-toolchain.md). No archive or device
access was requested again. The [public tracker](https://mira-build-progress-production.up.railway.app)
records timestamps, pushed commits and remaining acceptance on MIRA-019 through MIRA-021.
