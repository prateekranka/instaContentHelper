# CH-02 implementation — Launch-A one-screen onboarding

Repo: `/Users/prateekranka/Cowork/contenthelper`  
Decision: `dec-20260907-002`  
Contract: `onboarding-contract-launch-A.md`  
Ledger ack: `change-ledger-accepted.md` (2026-09-07)

## What shipped

### One screen asks

- **Starting point (optional):** Just starting / Already posting chips.
- **Interest topics (optional):** catalog chips from `OnboardingInterestCatalog.starter`.
- **Helper copy:** deferred taste, production prefs, and voice live under **You → Generation inputs**.
- **No** taste pack, production form, context questionnaire, review gauntlet, handles, or reference import on first run.
- **No** mandatory typing field on the launch screen.

Primary: **Show my first idea**  
Secondary skip: **Set up later** (same handoff path; toast COPY-0431 aligned)  
Cancel: **Not now** (persist local progress; no generate; recoverable next launch)

### Skip behavior

| Control | Persists | Generates first idea | Profile | Next launch |
| --- | --- | --- | --- | --- |
| **Set up later** | Yes (current chips, may be empty) | Yes — via existing `confirmOnboardingAndPrepareFirstIdea` | `established` with chosen fields only; voice omitted when deferred | No first-use screen (unless DEBUG force) |
| **Show my first idea** | Same | Yes | Same | Same |
| **Not now** | Local `partial` progress | No | Unchanged server state | Same one-screen with restored picks |

Skip/continue with **zero fields** uses `OnboardingFirstIdeaBriefBuilder.genericStarterBrief` (labeled starter, not HYROX, not learned taste).

Voice: `completedData()` always sets `voiceDeferred: true`, `voicePrefilled: nil`. Mapper skips canned voice when deferred.

### Legacy five-step

- `OnboardingStep` enum + decoder unchanged.
- Persisted steps `1…4` normalize to the launch screen on restore; saved answers kept for You/deferred editing.

### Files touched

| Area | Files |
| --- | --- |
| UI | `OnboardingFlowView.swift` |
| ViewModel | `OnboardingViewModel.swift` |
| Models / validation | `OnboardingModels.swift` |
| Store / policy comments | `OnboardingStore.swift` |
| Brief + mapper (onboarding handoff) | `OnboardingFirstIdeaBriefBuilder.swift`, `CreatorOnboardingState.swift` |
| Tests | `OnboardingTests.swift`, `AdaptiveOnboardingPersistenceTests.swift` |
| Handoff | `qa-baseline/ch02-appservices-handoff.md` |

**Not edited:** `AppServices.swift`, `AppState.swift`, DTOs, backend, build number, `prototypes/today-ui/index.html`.

### AppServices handoff

**Yes.** See `qa-baseline/ch02-appservices-handoff.md` — `voiceDeferred` must read established + empty voice or skip/continue first idea fails `creator_voice_required`.

### Tests updated

- `OnboardingTests`: added launch-A validation/normalization/generic-brief tests; updated back-navigation, five-step reference, soft-skip copy tests.
- `AdaptiveOnboardingPersistenceTests`: split mapper voice deferred vs not-deferred expectations.

**Kept unchanged:** persistence round-trip, workspace isolation, custom-subject, no-HYROX brief, first-idea handoff, voice-deferral gate tests (pending AppServices), established-profile gating in `AdaptiveOnboardingVerificationTests`.

### Test run (onboarding-only)

103 tests passed (7 Sep 2026, simulator `FAE1FD16-D185-433C-AC85-544FF45F2C82`):

- `OnboardingTests` (57)
- `AdaptiveOnboardingPersistenceTests`
- `AdaptiveOnboardingVerificationTests` (+ empty-today fix for success handoff test)
- `FirstIdeaHandoffTests`
- `VoiceGateTests`

Skip-first-idea with zero fields still needs AppServices `voiceDeferred` handoff before live QA.
