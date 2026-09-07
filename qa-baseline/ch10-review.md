# CH-10 independent review (test removals)

Recorded: 7 September 2026.
Reviewer did not implement the removals. `qa-baseline/ch10-test-removals.md` was read **after** `git diff`.
Repo: `/Users/prateekranka/Cowork/contenthelper` · branch `cursor/today-ui-prototype-cea4`
HEAD SHA: `20766cd90fd6338592d8fb7792395f566eda1205` (unchanged)
`CURRENT_PROJECT_VERSION`: `2026081102` (unchanged)
This review did **not** start CH-05, did **not** bump the build number, and did **not** touch Paper.

## Verdict

**PASS.** No production-module restore.

| Return | Value |
| --- | --- |
| pass/fail | **pass** |
| restore | **none** |

Working-tree delete is only the GFX duplicate test file. Production thumbnail helpers, pairing, and week-generation modules match HEAD.

## Scope checks

| Check | Result |
| --- | --- |
| Production `storyboard-thumbnail.ts` (shared + function re-export) | **ok** — both files present, **zero** git diff vs HEAD |
| GFX duplicate tests only | **ok** — deleted `supabase/functions/generate-storyboard-thumbnail/storyboard-thumbnail_test.ts` (148 lines of `Deno.test`). Function `index.ts` + re-export kept |
| SBT-2 | **ok** — `_shared/storyboard-thumbnail_test.ts:35` `storyboardRowsForCard falls back to top-level GeneratedDailyCard timelines` |
| `DevicePairingService.swift` | **ok** — intact, unstaged/unstaged diff empty, still in pbxproj Sources |
| UIT-6,8,9,10 remain | **ok** |
| UIT-7 | **ok** — still `XCTSkip` Folio-first body (`testCreatorTodayAndShootFolioAreReachableInInstalledApp`) |
| AOP-4, AOP-5, AOV-2, ONB-25 | **ok** — methods and assertion bodies still present |
| Week-generation production | **ok** — `supabase/functions/generate-week/` production files present, **zero** git diff vs HEAD |
| New test framework | **ok — none** (still XCTest + Deno.test; `deno.json` `test:backend` unchanged) |
| CH-05 / build number / Paper | **ok — not started / not bumped / not touched** |

## Production modules (must not restore)

Git `diff --diff-filter=D` names **one** path:

`supabase/functions/generate-storyboard-thumbnail/storyboard-thumbnail_test.ts`

That file imported the local re-export and duplicated SBT-1/3/4/5/6/7. It is a test file, not the production module.

Kept production:

| Path | Status vs HEAD |
| --- | --- |
| `supabase/functions/_shared/storyboard-thumbnail.ts` | unchanged |
| `supabase/functions/generate-storyboard-thumbnail/storyboard-thumbnail.ts` | unchanged (re-export of shared helpers) |
| `supabase/functions/generate-storyboard-thumbnail/index.ts` | unchanged |
| `CreatorContentOS/Data/DevicePairingService.swift` | unchanged (209 lines; `SupabaseTimestampParser` still in file) |
| `supabase/functions/generate-week/*.ts` excluding `*_test.ts` | unchanged (all production files still tracked) |

Shared SBT suite still has **7** `Deno.test` cases, including SBT-2 (unique top-level timeline fallback; no GFX counterpart).

## Survivors (method-level)

| ID | Artifact | Present |
| --- | --- | --- |
| SBT-2 | `_shared/storyboard-thumbnail_test.ts` top-level timeline fallback | **yes** |
| AOP-4 | `testWorkspaceScopedStoreDoesNotUseGlobalDoneFlag` — scoped store ignores `ch-onboarding-done=1` | **yes** |
| AOP-5 | `testOnboardingPresentationPolicyUsesProfileNotGlobalDone` — `.new` presents, `.established` does not | **yes** |
| AOV-2 | `testGatingMatrixLoadFailedPreservesEstablishedSnapshot` — `previousEstablished` + `shouldForceOnboardingFlow == false` | **yes** |
| ONB-25 | `testParsesReelURL` — `isReel`, `!needsProfileVerification`, key `instagram:reel:ABC123` | **yes** |
| UIT-6 | `testCreatorTodayInlinePackageIsReachableInInstalledApp` | **yes** |
| UIT-7 | `testCreatorTodayAndShootFolioAreReachableInInstalledApp` skip + unreachable Folio body | **yes** (skip kept) |
| UIT-8 | `testDebugFixtureManagerCanReachAndPublishWeeklyButton` + weekly approve/publish helpers | **yes** |
| UIT-9 | `testCreatorFallbackSheetCanOpenInInstalledApp` | **yes** |
| UIT-10 | `testCreatorBackupDecisionAppearsInArchiveInInstalledApp` | **yes** |

Installed suite is **5** methods (11 → 5). Removed skip-only methods are gone from the working tree (UIT-1…5, UIT-11). Weekly helpers still used by UIT-8 (`approveGeneratedWeekDays`, `waitForPublishButton`).

Removed Swift methods (HEAD still has them; working tree does not):

- AOV-3 `testPresentationPolicyNeverUsesGlobalDoneFlag`
- AOP-2 `testLoadFailedPreservesEstablishedSnapshot`
- ONB-29 `testClassifiesReelURLAsReelWithoutExpectedKind`

## Tests / framework

No new test **file** for CH-10. No `import Testing` / Quick / Nimble. Deno backend task is still `deno test … supabase/functions`.

This review did **not** re-run `deno task test:backend` or `xcodebuild` survivors. Implementer notes already recorded those survivor commands. Independent check here is tree + method-body presence vs HEAD.

## Held / mixed tree (not fails)

- Working tree also has CH-02 / CH-03 / CH-06 / CH-15 / onboarding edits. Left as-is.
- `AdaptiveOnboardingPersistenceTests` / `OnboardingTests` have extra non-CH-10 edits (mapper/launch cases). AOP-4/5 and ONB-25 bodies still match the retained contracts.
- pbxproj also drops other onboarding/You form file refs from other slices. Those paths are **not** git-deleted production modules from CH-10.
- CH-10 ledger also mentioned adding two script tests to the existing deno task. That add is **not** in this removal batch (`ch10-test-removals.md` records removals only). Not a fail for this review.
- Installed UI tests were compile-checked by the implementer, not executed on an installed candidate.

## Leftovers (not review fixes)

- UIT-7 skip remains for CH-15 current-path copy/edit proof.
- UIT-6 is still entry smoke, not script/caption copy proof.
