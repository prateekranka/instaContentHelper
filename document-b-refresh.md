# Document B — Test-Value Refresh (read-only)

**Role:** Document B owner (test-value reviewer)\
**Repo:** `/Users/prateekranka/Cowork/contenthelper`\
**Audit folder:** `/Users/prateekranka/Documents/Codex/2026-06-19/contenthelper-ui-audit`\
**Refresh date:** 2026-09-07 (IST)\
**Method:** Static body review only. **No test was run.** No builds, no git mutations, no deletions.

---

## 1. SHA and inventory status

| Field | Value |
|---|---|
| Pinned candidate SHA | `20766cd90fd6338592d8fb7792395f566eda1205` |
| Current HEAD SHA | `20766cd90fd6338592d8fb7792395f566eda1205` |
| Pinned main baseline | `1fc0df2aa2b4f5d79bb41d91dd6eec895c4963d3` |
| HEAD commit message | Stop generate_day from forcing lifestyle on books/movies profiles. |

**Inventory:** unchanged pending runtime collection. Appendix B’s 779-entry ledger at the pinned SHA was not recounted. Swift test methods, installed UI methods, and Deno registrations remain as previously inventoried until Step 8 executes collection.

**Unknown (not invented):** runtime pass/fail, flake rate, coverage %, mutation score, swiftlint/lizard availability.

---

## 2. Ranked candidate refresh (body-level confirmation)

### GFX-1…6 — Deno storyboard-thumbnail duplicates (Tier R)

**Re-export path:** `supabase/functions/generate-storyboard-thumbnail/storyboard-thumbnail.ts:1–12` re-exports the shared module from `../_shared/storyboard-thumbnail.ts`. Both test files import from their local `./storyboard-thumbnail.ts`, so GFX and SBT exercise the same implementation through the re-export seam.

| ID | File:line | Deno.test name | Maps to | Disposition |
|---|---|---|---|---|
| GFX-1 | `supabase/functions/generate-storyboard-thumbnail/storyboard-thumbnail_test.ts:10` | `storyboardRowsForCard derives rows from stored card timelines` | SBT-1 (`_shared/storyboard-thumbnail_test.ts:10`) | **remove** (retain SBT-1) |
| GFX-2 | `…/storyboard-thumbnail_test.ts:35` | `buildStoryboardThumbnailPrompt stays compact and excludes requested overlay text` | SBT-3 (`_shared/…:56`) | **remove** (retain SBT-3) |
| GFX-3 | `…/storyboard-thumbnail_test.ts:57` | `buildStoryboardThumbnailPrompt includes directed refresh instructions` | SBT-4 (`_shared/…:78`) | **remove** (retain SBT-4) |
| GFX-4 | `…/storyboard-thumbnail_test.ts:82` | `asset cache matches row, prompt hash, model, path, and URL` | SBT-5 (`_shared/…:103`) | **remove** (retain SBT-5) |
| GFX-5 | `…/storyboard-thumbnail_test.ts:107` | `mergeStoryboardThumbnailAsset replaces a row without disturbing others` | SBT-6 (`_shared/…:128`) | **remove** (retain SBT-6) |
| GFX-6 | `…/storyboard-thumbnail_test.ts:122` | `extractGeneratedImage handles interaction output image shape` | SBT-7 (`_shared/…:143`) | **remove** (retain SBT-7) |

**Body confirmation:** For each pair above, assertion bodies and test names match line-for-line (same fixtures, same `assertEquals`/`assert` calls). The only structural difference between the two files is that `_shared/storyboard-thumbnail_test.ts` contains an extra test SBT-2 at `:35–54` (`storyboardRowsForCard falls back to top-level GeneratedDailyCard timelines`) with no GFX counterpart.

| Retained | File:line | Why keep |
|---|---|---|
| **SBT-2** | `supabase/functions/_shared/storyboard-thumbnail_test.ts:35` | Unique top-level timeline fallback; absent from GFX file. **Must survive** any GFX removal batch. |
| SBT-1,3,4,5,6,7 | `_shared/storyboard-thumbnail_test.ts:10,56,78,103,128,143` | Superset duplicate targets for GFX-1…6. |

**Do not** delete `_shared/storyboard-thumbnail.ts` or the shared test file when removing GFX duplicates.

---

### UIT-1…5, UIT-11 — Installed UI manager journeys (Tier O)

All six methods throw `XCTSkip` on line 1 of the method body before any executable assertion. Unreachable code below the skip provides no executed regression guard.

| ID | File:line | Method | Skip line | Disposition |
|---|---|---|---|---|
| UIT-1 | `InstalledContentHelperUITests/InstalledContentHelperUITests.swift:8` | `testInstalledSessionExposesManagerAccess` | `:9` | **remove** (after helper reference check) |
| UIT-2 | `…:13` | `testInstalledManagerGenerateReviewPublishAndCreatorToday` | `:14` | **remove** (after helper reference check) |
| UIT-3 | `…:97` | `testInstalledManagerGenerateReviewSurfaceWithoutPublishing` | `:98` | **remove** (after helper reference check) |
| UIT-4 | `…:189` | `testInstalledManagerRetriesFailedDay` | `:190` | **remove** (after helper reference check) |
| UIT-5 | `…:209` | `testInstalledManagerPublishesExistingGeneratedWeekAndCreatorToday` | `:210` | **remove** (after helper reference check) |
| UIT-11 | `…:435` | `testManagerWeekStartMenuExcludesPastDates` | `:436` | **remove** (after helper reference check) |

Skip message (UIT-1…5, UIT-11): `"Manager tools removed from Creator Profile (ticket 04); Admin shell retirement is ticket 07."`

**Retained protection:** UIT-6 (entry smoke), UIT-8 (DEBUG fixture admin), UIT-9/10 (creator fallback/archive). Do not remove shared helpers until grep confirms zero remaining callers outside deleted skip bodies.

---

### UIT-7 — Skipped Folio-first journey (Tier O)

| ID | File:line | Body evidence | Disposition |
|---|---|---|---|
| UIT-7 | `InstalledContentHelperUITests/InstalledContentHelperUITests.swift:278` | `:279` throws `XCTSkip("Retired Folio-first Today path (ticket 09 slice 6); use testCreatorTodayInlinePackageIsReachableInInstalledApp.")`. Unreachable body expects `Open today's Shoot Folio`, Script/Caption tabs — obsolete navigation. | **replace** skipped method with current-path copy/edit proof in existing suite (CH-15); do not revive Folio-first route solely to pass this test. |

---

### UIT-6 — Entry smoke, not copy proof (Tier E keep with caveat)

| ID | File:line | Body evidence | Disposition |
|---|---|---|---|
| UIT-6 | `InstalledContentHelperUITests/InstalledContentHelperUITests.swift:257` | `:265–268` accepts **any** of: `today.package.content`, Storyboard label, `Give me other ideas`, or `Plan today's content`. `:270–272` asserts only that one path matched. | **keep** as narrow entry smoke. **Not** proof of script/caption copy or edit. Do not use pass as CH-15 acceptance. |

---

### AOV-3 vs AOP-5 and AOP-4 (Tier R / Tier E)

| ID | File:line | Body evidence | Disposition |
|---|---|---|---|
| AOV-3 | `CreatorContentOSTests/AdaptiveOnboardingVerificationTests.swift:70` | `:71–73` seeds `UserDefaults` with `ch-onboarding-done=1`. **Never** passes `defaults` into `OnboardingPresentationPolicy` or `WorkspaceScopedOnboardingStore`. `:75–86` only calls pure `OnboardingPresentationPolicy.shouldPresent(presentation:sessionDismissed:)` for `.new` / `.established`. | **remove** (misleading setup; assertions duplicate AOP-5) |
| AOP-5 | `CreatorContentOSTests/AdaptiveOnboardingPersistenceTests.swift:86` | `:87–98` — identical pure-policy `.new`/`.established` assertions **without** the unused defaults setup. | **keep** |
| AOP-4 | `CreatorContentOSTests/AdaptiveOnboardingPersistenceTests.swift:71` | `:72–83` injects `defaults` into `WorkspaceScopedOnboardingStore` and asserts `isComplete()` is false despite global done flag. | **keep** (real scoped-store global-flag guard) |

---

### AOP-2 vs AOV-2 (Tier R merge)

| ID | File:line | Body evidence | Disposition |
|---|---|---|---|
| AOP-2 | `CreatorContentOSTests/AdaptiveOnboardingPersistenceTests.swift:41` | `:42–60` — same established fixture, `loadFailed: true`, asserts `previousEstablished` inside `.loadFailed`. | **merge → AOV-2** (weaker) |
| AOV-2 | `CreatorContentOSTests/AdaptiveOnboardingVerificationTests.swift:47` | `:48–66` — same fixture and `previousEstablished` assert. **Additional** `:67` — `XCTAssertFalse(presentation.shouldForceOnboardingFlow)`. | **keep** (richer survivor) |

---

### ONB-29 vs ONB-25 (Tier R)

| ID | File:line | Body evidence | Disposition |
|---|---|---|---|
| ONB-25 | `CreatorContentOSTests/OnboardingTests.swift:482` | Same URL `https://www.instagram.com/reel/ABC123/`. Asserts `:487–489` — `isReel`, `!needsProfileVerification`, canonical key `instagram:reel:ABC123`. | **keep** |
| ONB-29 | `CreatorContentOSTests/OnboardingTests.swift:518` | Same parser call and URL `:519–521`. Asserts only `:522` — `isReel`. Strict subsumption by ONB-25. | **remove** (retain ONB-25) |

---

### DevicePairingService.swift — do not wholesale delete

| Symbol | File:line | Live usage | Disposition |
|---|---|---|---|
| `SupabaseTimestampParser` | `CreatorContentOS/Data/DevicePairingService.swift:80–119` | `DevicePairingService.swift:73` decodes pairing timestamps; `AuthenticationService.swift:213` parses Apple auth exchange `pairedAt`. | **keep file**; extract parser if invite service retires later |
| `DevicePairingService` (invite wrapper) | `DevicePairingService.swift:137+` | No production caller found in prior audit; DPS-1/2/5 are conditional-retirement only. | **uncertain** for service block; **never** recommend deleting the whole file while parser is live |

---

### ci:backend / deno task test:backend scope

From `deno.json:3–5`:

```json
"test:backend": "deno test … supabase/functions",
"ci:backend": "deno task check:backend && deno task test:backend"
```

**Confirmed:** discovery root is `supabase/functions` only.

**Not discovered by ci:backend** — the two script test files under `scripts/`:

1. `scripts/day-generation-under-60-benchmark_test.ts`
2. `scripts/workers/generate-day-worker_test.ts`

Step 7/8 require explicit collection of these with their bounded permissions; extending `test:backend` or the CI workflow is a gap, not a reason to delete them silently.

---

## 3. Retained-protection ID summary (for removal batches)

When removing any candidate above, these IDs must still detect the same failure class:

| Removed candidate | Retained protection |
|---|---|
| GFX-1…6 | SBT-1, **SBT-2**, SBT-3, SBT-4, SBT-5, SBT-6, SBT-7 |
| UIT-1…5, UIT-11 | UIT-6, UIT-8, UIT-9, UIT-10 (+ future CH-15 copy/edit proof) |
| UIT-7 (replace, not bare delete) | UIT-6 smoke + new inline copy/edit assertions |
| AOV-3 | AOP-5 + AOP-4 |
| AOP-2 | AOV-2 |
| ONB-29 | ONB-25 |

---

## 4. What Step 8 must execute before any removal

Per plan Step 8 (`contenthelper-release-first-cursor-20260907.md:182–213`):

1. **Baseline:** Capture or confirm pre-change test registry from pinned source; do not weaken assertions because baseline had known failures.
2. **Per removal batch:** Review candidate body **and** cited retained test; demonstrate equivalent failure detection; if not demonstrable, **keep**.
3. **Run affected tests** after each small batch; restore any removal that hides a contract.
4. **Backend:** `deno task check:backend` && `deno task test:backend` (supabase/functions only).
5. **Script tests (explicit, separate):** run the two `scripts/` test files above with required bounded permissions — not covered by `ci:backend` today.
6. **iOS:** `xcodebuild test` on dedicated simulator for `CreatorContentOS` scheme; separately discover/run `InstalledContentHelperUITests` when device prerequisites met.
7. **Release archive:** separate Release build/archive with production bootstrap — Debug green ≠ Release ready.
8. **Record:** collection counts, skips, failures, elapsed time, environment, exact result bundle paths.
9. **Helper hygiene (UIT):** grep for manager-journey helpers; remove only when zero callers remain outside deleted skip bodies.
10. **No new test files/fixtures** without explicit approval.

**No test was run in this refresh.** Markdown audit alone is not execution.

---

## 5. Disposition rollup (refreshed candidates only)

| ID | Disposition |
|---|---|
| GFX-1…6 | remove (after SBT survivor proof in Step 8) |
| SBT-2 | **keep** (unique; must survive) |
| SBT-1,3,4,5,6,7 | keep |
| UIT-1…5, UIT-11 | remove (after helper reference check + Step 8 runs) |
| UIT-7 | replace / merge into CH-15 current-path proof |
| UIT-6 | keep (entry smoke only) |
| AOV-3 | remove (retain AOP-5, AOP-4) |
| AOP-5, AOP-4 | keep |
| AOP-2 | merge → AOV-2 |
| AOV-2 | keep |
| ONB-29 | remove (retain ONB-25) |
| ONB-25 | keep |
| DevicePairingService.swift | keep file; parser live — no wholesale deletion |

---

## 6. Metrics (unchanged / unknown)

| Metric | Status |
|---|---|
| Appendix B entry count (779) | unchanged (SHA match) |
| Swift `@Test` / `func test` count | unchanged pending Step 8 collection |
| Installed UI method count | unchanged pending Step 8 collection |
| Deno `Deno.test` registrations under `supabase/functions` | unchanged pending Step 8 collection |
| Runtime pass rate | **unknown** |
| Flake rate | **unknown** |
| Coverage | **unknown** |
| Mutation testing | **unknown** |
| swiftlint / lizard | **unknown** (may be absent) |

---

## 7. Ranked removal candidates still needing survivor proof (Step 8)

Priority order for coordinator execution:

1. **GFX-1…6** — run `deno task test:backend`; confirm SBT-1/3/4/5/6/7 + **SBT-2** green; then delete GFX file duplicates only.
2. **AOV-3** — run AdaptiveOnboarding* tests; confirm AOP-5 + AOP-4 green; remove misleading defaults setup.
3. **ONB-29** — run OnboardingTests; confirm ONB-25 green.
4. **AOP-2** — run AdaptiveOnboarding* tests; confirm AOV-2 green (includes `shouldForceOnboardingFlow`).
5. **UIT-1…5, UIT-11** — helper reference grep; run InstalledContentHelperUITests; confirm UIT-6/8/9/10 (+ CH-15 when added) green; remove skip-only methods and orphaned helpers only.

**UIT-7** is not a bare removal — replace with CH-15 copy/edit proof before deleting skip body.

---

## 8. Gaps that matter more than removals

These lack sufficient executed proof and outrank duplicate cleanup for release risk:

| Gap | Why it matters more |
|---|---|
| **CH-15 copy/edit** | Inline Today script/caption are read-only; no installed proof that main package text copies or edits persist. UIT-6 and retired UIT-7 do not cover this. |
| **Account deletion + consent (CH-05/06)** | In-app deletion, AI consent boundaries, privacy manifest accuracy — no local/hosted execution evidence in this refresh. |
| **Script tests outside ci:backend** | `scripts/day-generation-under-60-benchmark_test.ts` and `scripts/workers/generate-day-worker_test.ts` are not in routine CI; latency/worker regressions can slip. |
| **Hosted mixed-version write-content** | Omitted adaptive fields on profile update from old clients — static audit flagged; needs fixture reproduction against candidate handler. |
| **Installed TestFlight parity** | Prior evidence blocked on creator auth binding; manager skip tests do not substitute. |

---

*End of Document B refresh. No test was run.*
