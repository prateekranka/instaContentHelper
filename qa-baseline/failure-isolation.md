# Step 2 — Baseline failure isolation

Recorded: 7 September 2026.
Repo: `/Users/prateekranka/Cowork/contenthelper`
HEAD: `20766cd90fd6338592d8fb7792395f566eda1205` (verified; native source not edited).
xcresult: `qa-baseline/Baseline.xcresult` — 359 collected, 356 passed, 3 failed, 0 skipped. Five assertion failures, 0 unexpected.

Do **not** delete or soften these three tests.

## Return line

1. `AdaptiveOnboardingVerificationTests.testConfirmOnboardingSuccessUsesMakeDayAvailableAndLandsToday` — fixture `raceWeekToday` already counts as a usable Today card, so handoff skips.
2. `DayLifecycleTests.testFirstIdeaPromotionUsesMakeDayAvailableNotInstagramPublish` — same skip: fixture Today is already ready.
3. `YouFeatureTests.testContentCategorySelectionMapsPresetAndCustomPillars` — `"Fitness"` is not a starter catalog label, so it becomes Other and drops `"Custom niche"`.
CH-15 independent: **yes**.

---

## 1. `testConfirmOnboardingSuccessUsesMakeDayAvailableAndLandsToday`

- File:line: `CreatorContentOSTests/AdaptiveOnboardingVerificationTests.swift:289`
- xcresult: `AdaptiveOnboardingVerificationTests/testConfirmOnboardingSuccessUsesMakeDayAvailableAndLandsToday()`
- Message: `Expected completed handoff, got skippedExistingReady`

### Expected vs actual

The test calls `confirmOnboardingAndPrepareFirstIdea` on fixture-backed `AppServices` and requires:

- result `.completed(navigatedToday: true)`
- `makeDayAvailable` called once for `2026-09-05`

Actual: `.skippedExistingReady`. The later `makeDayAvailable` count asserts never run.

Nearby production (`AppServices.confirmOnboardingAndPrepareFirstIdea`):

1. `OnboardingFirstIdeaHandoffPlanner.plan` sees no `dayBriefGeneratedCards` row, so `shouldGenerate == true`.
2. Then `hasUsableReadyTodayPackage` returns true when the scheduled date is Today, the in-memory `todayCard` title is not the loading placeholder, and `scenes` is not empty.
3. That path calls `skipFirstIdeaHandoffForExistingReady` and never `generateDayCard` / `makeDayAvailable`.

`makeServices` (same file, ~429) uses `AppServices.fixtureBacked` + `FixtureTodayCardRepository()`. `fixtureBacked` seeds `todayCard: DailyCard.raceWeekToday` unless `MCO_FORCE_EMPTY_TODAY=1`. Race week title is `"Race week has entered the house"` with four scenes. That is a usable ready Today card. The fixture onboarding path incorrectly seeds a ready Today card, so first-idea skips.

### Dependency cone (Cone A)

Shared product path: first-idea confirm → `hasUsableReadyTodayPackage` → skip instead of generate + `makeDayAvailable`.

| Surface | Role |
| --- | --- |
| `AppServices.confirmOnboardingAndPrepareFirstIdea` | persist established, then generate / skip / make-available |
| `OnboardingFirstIdeaHandoffPlanner` | skip when package status is already ready/published (not the gate that fired here) |
| `AppServices.hasUsableReadyTodayPackage` | skip when fixture/live Today already has scenes (the gate that fired) |
| `OnboardingViewModel.confirmFirstIdea` / `CreatorContentOSApp` | `.completed` and `.skippedExistingReady` both succeed the UI |
| `FixtureTodayCardRepository` / `DailyCard.raceWeekToday` | default fixture Today |
| `AppServices.fixtureBacked` | default `todayCard = .raceWeekToday` |

Already covered (keep this test anyway):

- Success with empty Today: `FirstIdeaHandoffTests.testConfirmOnboardingGeneratesBooksMoviesWhenTodayEmpty` sets `todayCard = .emptyTodayPlaceholder`, then asserts `.completed`, one generate, one `makeDayAvailable`.
- Skip when race week is present: `FirstIdeaHandoffTests.testConfirmOnboardingSkipsReadyRaceWeekTodayWhenFlagOff` and `testConfirmOnboardingSkipsWhenTodayCardHasUsableReadyPackage`.
- Skip when a published package row exists: `AdaptiveOnboardingVerificationTests.testFirstIdeaIdempotencySkipsReadyPackage`.

### Disposition

**Fixture / test-data mismatch**, not a live first-idea product bug.

- New live users start from `liveBacked` Today (`"Checking today's plan"`, empty scenes). That does not trip `hasUsableReadyTodayPackage`.
- Fixture / `MCO_FORCE_FIXTURE_UI` launches with race week. Skip is then the intended product behavior.
- This test still encodes the empty-Today success contract (`makeDayAvailable` + land Today). Keep the assertion. Do not change skip logic to make the fixture path generate over a ready card.

---

## 2. `testFirstIdeaPromotionUsesMakeDayAvailableNotInstagramPublish`

- File:line: `CreatorContentOSTests/DayLifecycleTests.swift:375`
- xcresult: `DayLifecycleTests/testFirstIdeaPromotionUsesMakeDayAvailableNotInstagramPublish()`
- Message: `Expected completed first-idea handoff`

### Expected vs actual

Same `confirmOnboardingAndPrepareFirstIdea` call, with `FixtureTodayCardRepository()` and no `todayCard = .emptyTodayPlaceholder`.

Expected: `.completed`, then `makeDayAvailableCallCount == 1` and `publishWeekCallCount == 0` (promote with `makeDayAvailable`, not week Instagram publish).

Actual: `.skippedExistingReady` at the `guard case .completed` on line 375. The unique `publishWeek == 0` asserts never run.

Same production gate as test 1: planner would generate; `hasUsableReadyTodayPackage` skips because `todayCard` is race week.

### Dependency cone

Same Cone A as test 1. Extra intent: day-lifecycle promotion must not call `WeeklyPlanRepository.publishWeek`.

Already covered in part: `FirstIdeaHandoffTests.testConfirmOnboardingGeneratesBooksMoviesWhenTodayEmpty` asserts one `makeDayAvailable` on the empty-Today path. It does not assert `publishWeek == 0`. This test is still the only one that names that anti-contract. Keep it.

### Disposition

**Fixture / test-data mismatch.** Same seed hole as test 1. Not a second product bug. Keep the assertion.

---

## 3. `testContentCategorySelectionMapsPresetAndCustomPillars`

- File:line: `CreatorContentOSTests/YouFeatureTests.swift:8–10` (three asserts, one test)
- xcresult: `YouFeatureTests/testContentCategorySelectionMapsPresetAndCustomPillars()`
- Messages:
  - selectedIDs `["travel", "other"]` vs `["fitness", "travel", "other"]` (line 8)
  - customOtherLabel `"Fitness"` vs `"Custom niche"` (line 9)
  - pillars `["Travel", "Fitness"]` vs `["Fitness", "Travel", "Custom niche"]` (line 10)

### Expected vs actual

Input pillars: `["Fitness", "Travel", "Custom niche"]`.

`ContentCategorySelection.from` maps through `YouInterestsSelection.from`, which matches each pillar **label** (case-insensitive) against `OnboardingInterestCatalog.starter`.

Starter catalog (current HEAD):

- `fitness-wellness` → `"Fitness & Wellness"` (not `fitness` / `"Fitness"`)
- `travel` → `"Travel"`

So `"Travel"` is a preset. `"Fitness"` is not. `"Custom niche"` is not. Both unmatched labels become `customSubjects`. `from` then keeps at most one Other slot: first custom only.

Actual:

- `interestIDs` = `["travel"]`
- first custom = `"Fitness"` → `selectedIDs = ["travel", "other"]`, `customOtherLabel = "Fitness"`
- `"Custom niche"` dropped (no second Other slot)
- `resolvedContentPillars()` = Travel catalog label + Other text = `["Travel", "Fitness"]`

### Dependency cone (Cone B)

| Surface | Role |
| --- | --- |
| `OnboardingInterestCatalog.starter` | onboarding chips + You interests chips |
| `YouInterestsSelection.from` | You editor + this mapper |
| `ContentCategorySelection.from` | **legacy** three-id picker |
| `YouSetupMeta.categoriesSubtitle` | Plan generation-input summary |
| `PlanGenerationInputsSummary.categoriesMeta` | Plan → You categories subtitle |
| `YouContentCategoriesView` / `YouView.interestsSubtitle` | live You editor uses `YouInterestsSelection`, not this legacy picker |

Already covered (keep this test anyway):

- Catalog + custom on the live You mapper: `OnboardingTests.testYouInterestsSelectionMapsCatalogAndCustomSubjects` (`Books` / `Movies & TV` / `Pottery`).
- Onboarding fitness id is `fitness-wellness`: `OnboardingTests.testContextQuestionsDifferForFitnessVersusBooks`, taste packs, `AdaptiveOnboardingVerificationTests` books/fitness completed data.

Sibling `testContentCategorySelectionEnforcesMaxThree` still **constructs** ids `fitness` / `travel` / `food` by hand. It does not go through `from`, so it still passes. That does not make `fitness` a catalog id.

### Disposition

**Fixture / test-data mismatch** against the current interest catalog. Keep the assertion until catalog, legacy mapper, and this test agree.

Not a 5-step onboarding UI bug: onboarding and You interests already use `"Fitness & Wellness"` / `fitness-wellness`.

Product side effect if left as-is: a stored pillar literally `"Fitness"` (old data) maps to custom Other, not the Fitness & Wellness chip, and a third pillar after Travel + Fitness is dropped in the **legacy Plan subtitle** helper. You editor (`YouInterestsSelection`) would keep both customs. That is a mapper/catalog drift, not a reason to weaken this test.

---

## CH-15 (Today copy buttons)

**Independent: yes.**

Copy/edit on main Today Script/Caption is `GeneratedDayPlannedContent` → `GeneratedReadOnlyField` / `GeneratedScriptTimelineContent`. Copy already exists on Shoot Folio and Not Today backup. None of that shares `confirmOnboardingAndPrepareFirstIdea`, `hasUsableReadyTodayPackage`, `makeDayAvailable`, or `ContentCategorySelection.from`.

These three failures do not block CH-15. CH-15 does not fix them.

---

## CH-02 (onboarding) blockers?

**Do not treat these three as product blockers for the five onboarding screens.**

- Tests 1–2: empty-Today generate + `makeDayAvailable` already passes in `FirstIdeaHandoffTests`. Live new users are empty-Today. Fixture race week skip is intended. CH-02 must not weaken these asserts and must not “fix” skip by overwriting a ready Today card. If CH-02 adds fixture-backed first-idea tests, set `todayCard = .emptyTodayPlaceholder` (or `MCO_FORCE_EMPTY_TODAY`) when the case needs generate.
- Test 3: onboarding chips already use `OnboardingInterestCatalog`. Do not retarget CH-02 at restoring a `fitness` preset id unless You/Plan catalog work is in scope. Keep the assert as a canary.

Keep all three tests. Fix later by test setup (empty Today) and/or catalog–mapper agreement, not by softening expected values.
