# Step 1 — Baseline verification results

Recorded: 7 September 2026, ~18:28–18:38 IST.
Repo: `/Users/prateekranka/Cowork/contenthelper`
Mode: no app source edits. No stash, reset, clean, rebase, commit, xcodegen generate, Release archive, or GitHub Discussions enable. Native `CreatorContentOS/` stayed clean. Dirty `prototypes/today-ui/index.html` and untracked QA files were left in place.

## Identity

| Item | Value |
| --- | --- |
| HEAD SHA | `20766cd90fd6338592d8fb7792395f566eda1205` |
| HEAD subject | Stop generate_day from forcing lifestyle on books/movies profiles. |
| Native dirty | none (`CreatorContentOS/`, `CreatorContentOSTests/`, `InstalledContentHelperUITests/`, `project.yml` empty porcelain) |
| Simulator | ContentHelper QA · iPhone 16 · iOS 26.5 (23F77) |
| UDID | `FAE1FD16-D185-433C-AC85-544FF45F2C82` (from `xcrun simctl list devices available`; not invented) |
| Xcode | 26.6 (build 17F113) |
| Deno | 2.8.1 |
| `CURRENT_PROJECT_VERSION` | left at `2026081102` |

## Deno `check:backend`

- Result: **pass** (exit 0)
- Collection: 81 files type-checked (`deno check supabase/functions/*/*.ts supabase/functions/_shared/*.ts`)
- Skips / failures: none
- Elapsed: **0.882 s** wall
- Log: `qa-baseline/logs/deno-check-backend.log`
- File list: `qa-baseline/logs/deno-check-files.txt`

## Deno `test:backend`

- Command: `deno task test:backend`
- Permissions (unchanged, not broadened): `--allow-env --allow-read --allow-net=0.0.0.0:8000,127.0.0.1:8000,localhost:8000` scoped to `supabase/functions`
- Result: **pass** (exit 0)
- Collection: **396** tests discovered across 35 files; **395 passed**, **0 failed**, **1 ignored**
- Deno-printed duration: 1 s; wall: **2.829 s**
- Ignored: `generate-week status returns partial progress when one day failed and six days were saved` in `supabase/functions/generate-week/index_test.ts` (`ignore: true`). A sibling test immediately above already covers partial-progress status. No extra network allowlist was added.
- Log: `qa-baseline/logs/deno-test-backend.log`

## Extra script tests (not covered by `test:backend`)

Same bounded pattern as existing tasks: `--allow-env --allow-read` (the `test:backend` pair, without net). Not `--allow-all`. Write was not granted: benchmark `Deno.mkdir` / `Deno.writeTextFile` run only under `import.meta.main`. Worker `fetch` runs only when `processJob` is not stubbed; these tests stub it.

| File | Ran? | Result | Counts | Elapsed | Log |
| --- | --- | --- | --- | --- | --- |
| `scripts/day-generation-under-60-benchmark_test.ts` | ran | pass | 4 passed, 0 failed | 0.532 s wall (44 ms tests) | `qa-baseline/logs/deno-script-benchmark-test.log` |
| `scripts/workers/generate-day-worker_test.ts` | ran | pass | 8 passed, 0 failed | 0.839 s wall (377 ms tests) | `qa-baseline/logs/deno-script-worker-test.log` |

## xcodebuild Debug tests

Command (existing `CreatorContentOS.xcodeproj`, no `xcodegen generate`):

```
xcodebuild -project CreatorContentOS.xcodeproj -scheme CreatorContentOS \
  -destination "platform=iOS Simulator,id=FAE1FD16-D185-433C-AC85-544FF45F2C82" \
  -derivedDataPath ".../qa-baseline/DerivedData" \
  -resultBundlePath ".../qa-baseline/Baseline.xcresult" \
  test
```

- Configuration: Debug tests (scheme TestAction `buildConfiguration = Debug`). **Release archive was not run.**
- Result: **fail** (exit 65, `** TEST FAILED **`)
- Collection: **359** tests
- Passed: **356**
- Failed tests: **3** (5 assertion failures, 0 unexpected)
- Skips: **0** (`skippedTests: 0` in xcresult summary)
- Elapsed: **152.000 s** wall; XCTest body **9.220 s**; IDE testing window **47.078 s**
- xcresult: `/Users/prateekranka/Documents/Codex/2026-06-19/contenthelper-ui-audit/qa-baseline/Baseline.xcresult`
- Log: `qa-baseline/logs/xcodebuild-test.log`
- Failure excerpt: `qa-baseline/logs/xcodebuild-failures.txt`
- Summary JSON: `qa-baseline/logs/xcresult-summary.json`

`InstalledContentHelperUITests` **not run**. Reason: no installed-candidate path (no TestFlight/IPA install under this isolated DerivedData Debug test). Scheme `CreatorContentOS` only executes `CreatorContentOSTests`.

### Failing tests (preserve; do not weaken)

1. `AdaptiveOnboardingVerificationTests.testConfirmOnboardingSuccessUsesMakeDayAvailableAndLandsToday`
   - `Expected completed handoff, got skippedExistingReady`
   - `AdaptiveOnboardingVerificationTests.swift:289`
2. `DayLifecycleTests.testFirstIdeaPromotionUsesMakeDayAvailableNotInstagramPublish`
   - `Expected completed first-idea handoff`
   - `DayLifecycleTests.swift:375`
3. `YouFeatureTests.testContentCategorySelectionMapsPresetAndCustomPillars`
   - actual `selectedIDs` `["travel", "other"]` vs expected `["fitness", "travel", "other"]`
   - actual `customOtherLabel` `"Fitness"` vs expected `"Custom niche"`
   - actual pillars `["Travel", "Fitness"]` vs expected `["Fitness", "Travel", "Custom niche"]`
   - `YouFeatureTests.swift:8–10`

### Known failures isolated to a dependency cone

Do **not** weaken these assertions.

**Cone A — first-idea / `makeDayAvailable` + fixture Today already ready (tests 1–2)**

- Both tests call `confirmOnboardingAndPrepareFirstIdea` with `FixtureTodayCardRepository()`.
- That repository returns `DailyCard.raceWeekToday` unless `MCO_FORCE_EMPTY_TODAY=1`.
- `OnboardingFirstIdeaHandoffPlanner` / `hasUsableReadyTodayPackage` then returns `skippedExistingReady` instead of generate + `makeDayAvailable` + `.completed`.
- The tests still require `.completed` and a `makeDayAvailable` call. That contract is the thing that failed. Keep it.

**Cone B — You category mapping vs onboarding interest catalog (test 3)**

- `ContentCategorySelection.from` maps pillars through `OnboardingInterestCatalog.starter`.
- `"Fitness"` is not a starter label, so it becomes custom/`other`. `"Custom niche"` then has no second other slot.
- The test still expects a `fitness` preset id. Keep that assertion until the catalog and the You mapper agree.

## Today copy/edit reproduction

- Launch: Debug app `com.prateekranka.creatorcontenthelper` on the same simulator after tests.
- Fixture flag: `SIMCTL_CHILD_MCO_FORCE_FIXTURE_UI=1`. No wipe. No hosted delete. Did not tap Mark posted / Mark all as shot.
- Observed card: fixture **Race week has entered the house** (not a shared live post). 0 of 4 scenes shot. Script/Caption tabs present.

**Observed (copy/edit gap):**

- Main Today Script tab shows four read-only lines (`plan.package.panel.script`). Accessibility tree has **no** Copy, Edit, TextEditor, or pasteboard control.
- Main Today Caption tab selects `plan.package.tab.caption`. Panel `plan.package.panel.caption` is empty because `GeneratedReadOnlyField` hides blank values and the race-week fixture DailyCard has no caption/CTA/cover/hashtag fields. **No** copy or edit control.
- Today overflow menu is Plan-only. No copy action.
- Source match: Today uses `GeneratedDayPlannedContent` → `GeneratedReadOnlyField` / `GeneratedScriptTimelineContent`. Copy exists on Shoot Folio / Not Today backup, not on main Today Script/Caption.

**Blocker (non-fatal for the gap):**

- System alert **Apple Account Verification** appeared twice. Dismissed with **Not Now**. Did not open Settings. Did not enter a password. Screenshots: `01-launch.png`, `04-apple-account-verification-recurring.png`.

Screenshots (`qa-baseline/screens/`):

| File | What it shows |
| --- | --- |
| `01-launch.png` | Today behind Apple Account Verification |
| `02-today-storyboard.png` | Today Storyboard / Script / Caption tabs; no copy on storyboard |
| `03-today-script.png` | Script tab, read-only lines, no copy/edit |
| `04-apple-account-verification-recurring.png` | Recurring account alert during Caption tap |
| `05-today-caption.png` | Caption tab selected; empty read-only panel; no copy/edit |

## Not run (by instruction)

- Release archive
- `InstalledContentHelperUITests` (no installed-candidate path)
- `xcodegen generate` (existing xcodeproj built)
- swiftlint / lizard (missing; not installed)
- GitHub Discussions enable
- Flowdeck

## HEAD after this step

Still `20766cd90fd6338592d8fb7792395f566eda1205`. Native source still clean. Prototype HTML still dirty.
