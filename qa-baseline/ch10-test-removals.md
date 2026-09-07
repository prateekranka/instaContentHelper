# CH-10 test removals

Recorded: 7 September 2026, ~20:04–20:07 IST.
Repo: `/Users/prateekranka/Cowork/contenthelper`
HEAD SHA: `20766cd90fd6338592d8fb7792395f566eda1205` (unchanged)
`CURRENT_PROJECT_VERSION`: `2026081102` (unchanged)

Survivor proof ran before each removal batch. No candidate was kept because proof failed.

## Removed

| ID | Removed artifact | Retained protection | Post-removal command | Result |
| --- | --- | --- | --- | --- |
| GFX-1 | `generate-storyboard-thumbnail/storyboard-thumbnail_test.ts` Deno.test `storyboardRowsForCard derives rows from stored card timelines` | SBT-1 | `deno test …/_shared/storyboard-thumbnail_test.ts` then `deno task test:backend` | pass (7 SBT; 393 backend) |
| GFX-2 | same file: `buildStoryboardThumbnailPrompt stays compact…` | SBT-3 | same | pass |
| GFX-3 | same file: `buildStoryboardThumbnailPrompt includes directed refresh…` | SBT-4 | same | pass |
| GFX-4 | same file: `asset cache matches row, prompt hash…` | SBT-5 | same | pass |
| GFX-5 | same file: `mergeStoryboardThumbnailAsset replaces a row…` | SBT-6 | same | pass |
| GFX-6 | same file: `extractGeneratedImage handles interaction output image shape` | SBT-7 | same | pass |
| AOV-3 | `AdaptiveOnboardingVerificationTests.testPresentationPolicyNeverUsesGlobalDoneFlag` | AOP-4 + AOP-5 | `-only-testing:…/testWorkspaceScopedStoreDoesNotUseGlobalDoneFlag` + `-only-testing:…/testOnboardingPresentationPolicyUsesProfileNotGlobalDone` | pass |
| AOP-2 | `AdaptiveOnboardingPersistenceTests.testLoadFailedPreservesEstablishedSnapshot` | AOV-2 | `-only-testing:…/testGatingMatrixLoadFailedPreservesEstablishedSnapshot` | pass |
| ONB-29 | `OnboardingTests.testClassifiesReelURLAsReelWithoutExpectedKind` | ONB-25 (`testParsesReelURL`) | `-only-testing:…/testParsesReelURL` | pass |
| UIT-1 | `InstalledContentHelperUITests.testInstalledSessionExposesManagerAccess` | UIT-6, UIT-8, UIT-9, UIT-10 | `xcodebuild … build-for-testing` (compile) | pass |
| UIT-2 | `…testInstalledManagerGenerateReviewPublishAndCreatorToday` | UIT-6, UIT-8, UIT-9, UIT-10 | same | pass |
| UIT-3 | `…testInstalledManagerGenerateReviewSurfaceWithoutPublishing` | UIT-6, UIT-8, UIT-9, UIT-10 | same | pass |
| UIT-4 | `…testInstalledManagerRetriesFailedDay` | UIT-6, UIT-8, UIT-9, UIT-10 | same | pass |
| UIT-5 | `…testInstalledManagerPublishesExistingGeneratedWeekAndCreatorToday` | UIT-6, UIT-8, UIT-9, UIT-10 | same | pass |
| UIT-11 | `…testManagerWeekStartMenuExcludesPastDates` | UIT-6, UIT-8, UIT-9, UIT-10 | same | pass |

**GFX note:** Entire duplicate file `supabase/functions/generate-storyboard-thumbnail/storyboard-thumbnail_test.ts` deleted after SBT survivor run. Production re-export module kept. `_shared/storyboard-thumbnail_test.ts` kept including **SBT-2**.

**UIT note:** Orphaned manager-journey helpers removed after grep showed zero callers outside deleted skip bodies. Survivors: UIT-6, UIT-7 (skipped, kept), UIT-8, UIT-9, UIT-10. Helpers kept for UIT-8 weekly approval/publish and UIT-9/10 creator flows.

## Kept because survivor proof failed

None.

## Explicitly not removed (CH-10 scope)

| ID | Reason |
| --- | --- |
| UIT-7 | Replace deferred to CH-15; skip body kept |
| SBT-2 | Unique top-level timeline fallback; must survive |
| DevicePairingService.swift | Out of scope |
| GWSN-13/14, GWPS-4…9, pair-device, ONB-32…35 | Out of scope for this batch |

## Commands (exact)

```bash
# GFX survivor + backend
cd /Users/prateekranka/Cowork/contenthelper
deno test --allow-env --allow-read --allow-net=0.0.0.0:8000,127.0.0.1:8000,localhost:8000 \
  supabase/functions/_shared/storyboard-thumbnail_test.ts
deno task test:backend

# Swift survivors (pre- and post-removal)
xcodebuild -project CreatorContentOS.xcodeproj -scheme CreatorContentOS \
  -destination "platform=iOS Simulator,id=FAE1FD16-D185-433C-AC85-544FF45F2C82" \
  -derivedDataPath ".derivedData/ch10" \
  -only-testing:CreatorContentOSTests/AdaptiveOnboardingPersistenceTests/testWorkspaceScopedStoreDoesNotUseGlobalDoneFlag \
  -only-testing:CreatorContentOSTests/AdaptiveOnboardingPersistenceTests/testOnboardingPresentationPolicyUsesProfileNotGlobalDone \
  -only-testing:CreatorContentOSTests/AdaptiveOnboardingVerificationTests/testGatingMatrixLoadFailedPreservesEstablishedSnapshot \
  -only-testing:CreatorContentOSTests/OnboardingTests/testParsesReelURL \
  test

# UIT compile check
xcodebuild -project CreatorContentOS.xcodeproj -scheme CreatorContentOS \
  -destination "platform=iOS Simulator,id=FAE1FD16-D185-433C-AC85-544FF45F2C82" \
  -derivedDataPath ".derivedData/ch10" build-for-testing
```

## Count delta

| Suite | Before (baseline) | After CH-10 | Delta |
| --- | --- | --- | --- |
| Deno `test:backend` | 395 pass, 1 ignored | 393 pass, 1 ignored | GFX duplicate file removed (6 tests) |
| CreatorContentOSTests | — | — | −3 Swift methods (AOV-3, AOP-2, ONB-29) |
| InstalledContentHelperUITests methods | 11 | 5 | −6 skip-only methods (UIT-1…5, UIT-11) |

Installed UI tests were not executed (no installed-candidate path); compile-only verification.
