# Document A refresh — changed-source / call-graph review

**Role:** Document A owner (read-only refresh).\
**Prepared:** 2026-09-07.\
**Repo:** `/Users/prateekranka/Cowork/contenthelper`\
**Baseline:** Appendix A in `.hermes/plans/contenthelper-release-first-cursor-20260907.md` (pinned snapshot).

---

## 1. SHA verification (re-run)

| Check | Command | Result | Matches pin? |
|---|---|---|---|
| Candidate HEAD | `git rev-parse HEAD` | `20766cd90fd6338592d8fb7792395f566eda1205` | Yes |
| Remote `main` | `git ls-remote origin main` | `1fc0df2aa2b4f5d79bb41d91dd6eec895c4963d3` | Yes |
| Remote candidate branch | `git ls-remote origin cursor/today-ui-prototype-cea4` | `20766cd90fd6338592d8fb7792395f566eda1205` | Yes |
| Merge base `HEAD` × `origin/main` | `git merge-base HEAD origin/main` | `1fc0df2aa2b4f5d79bb41d91dd6eec895c4963d3` | Yes (= main tip) |

**Conclusion:** SHAs unchanged. No delta file-by-file pass required. Consume Appendix A ledger as-is; this document refreshes only uncertain / runtime-unproven items from static source.

**Scope unchanged:** 32 commits, 128 files (78 added, 50 modified, 0 net deletions), merge base = current main.

---

## 2. Refreshed static confirmations

Evidence type: **static / inferred** unless labeled otherwise. No hosted Supabase, TestFlight, or simulator runs were performed.

### 2.1 `CreatorRoute.shootFolio` — handler only, no production launcher

| Layer | Finding | Citation |
|---|---|---|
| Route enum | `shootFolio(editing:)` exists | `CreatorContentOS/Models/Models.swift:510-512` |
| Destination handler | Shell resolves route → `ShootFolioView` | `CreatorContentOS/Navigation/CreatorShellView.swift:11-14` |
| Production launchers | **None found** — no `NavigationLink(value: CreatorRoute.shootFolio` or `.shootFolio(` in `CreatorContentOS/` production Swift | Grep across `CreatorContentOS/**/*.swift` (2026-09-07 refresh); Today links only to `.plan`: `TodayView.swift:98`, `:227`; `ShootFolioView.swift:170` links to Plan, not into itself |
| Tests only | `.shootFolio(editing:)` constructed in unit tests | `CreatorContentOSTests/TodayPlanEntryTests.swift:35-38`, `:51-52`, `:57-58` |
| Reachability | **Static:** Shoot Folio screen is implemented and wired as a navigation destination; **runtime-unproven** that any Release user path pushes it | Aligns with Appendix A §Screen inventory “Reachability correction” (~line 1911) |

**Disposition impact:** Confirms **CH-15** (restore copy/editor access); Shoot Folio copy/edit code exists but is not statically reachable from Today.

---

### 2.2 Today inline Script/Caption — read-only, no copy controls

| Layer | Finding | Citation |
|---|---|---|
| Today wiring | `TodayInlineExecutionPackage` embeds `GeneratedDayPlannedContent` | `TodayInlineExecutionPackage.swift:19-21`; called from `TodayView.swift:22` |
| Folder tabs | Script and Caption panels use `GeneratedScriptTimelineContent` and `InstagramCaptionPostContent` | `GeneratedDayPlannedContent.swift:110-122` |
| Script panel | Read-only row list; no buttons, no `UIPasteboard` | `GeneratedDayPlannedContent.swift:715-779` |
| Caption panel | `GeneratedReadOnlyField` for caption/CTA/hashtags/etc.; no copy UI | `GeneratedDayPlannedContent.swift:682-698`; helper at `:3-20` |
| Copy elsewhere | `UIPasteboard` only in `ShootFolioView` (unreachable launcher) | `ShootFolioView.swift:575`, `:657` |
| Inline package | No copy/pasteboard references | Grep on `TodayInlineExecutionPackage.swift`, `GeneratedDayPlannedContent.swift` — empty |

**Disposition impact:** Confirms **CH-15**.

---

### 2.3 `YouAccountView` — sign-out present; no account deletion

| Item | Finding | Citation |
|---|---|---|
| Sign-out | `YouAccountSignOutButton` calls `appState.signOut()` | `YouAccountView.swift:20`, `:250-279` |
| Account deletion | **Not found** in You/account surfaces or broader `CreatorContentOS/` | Grep `deleteAccount`, `Delete account`, `account deletion` — no matches |
| DEBUG-only extra | Onboarding reset block under `#if DEBUG` | `YouAccountView.swift:224-247` |

**Disposition impact:** Confirms **CH-05** (add deletion) and **CH-06** (privacy/consent gaps).

---

### 2.4 Privacy manifest and in-app policy link

| Item | Finding | Citation |
|---|---|---|
| App-owned `.xcprivacy` | **None** under `CreatorContentOS/` or top-level project sources | `find CreatorContentOS -name '*.xcprivacy'` — empty; no `PrivacyInfo.xcprivacy` in `project.yml` / xcodeproj grep |
| Dependency manifests only | `PrivacyInfo.xcprivacy` from SPM (e.g. swift-crypto) in DerivedData/build artifacts | Not app-owned |
| In-app privacy-policy URL/link | **Not found** in `CreatorContentOS/**/*.swift` | Grep `privacy`, `Privacy Policy`, `privacyPolicy` — no product link |

**Disposition impact:** Confirms **CH-06**.

---

### 2.5 Storyboard resize / VoiceOver adjustment — still present

| Control | Finding | Citation |
|---|---|---|
| Resize handle render | `sceneResizeHandle` in storyboard table | `GeneratedDayPlannedContent.swift:288` |
| Drag gesture | Column width clamped on drag | `:338-358` |
| VoiceOver | `accessibilityLabel("Resize scene column")` + `accessibilityAdjustableAction` increment/decrement | `:360-370` |

**Disposition impact:** Confirms **CH-16** (keep; do not delete).

---

### 2.6 `write-content` profile update — mixed-version / omitted-field semantics

| Topic | Finding | Citation |
|---|---|---|
| Branch routing | `update_creator_profile` → `updateCreatorProfile`, **not** `write_content` RPC | `write-content/index.ts:172-174`; RPC only for other actions `:193`, `:214` |
| Update path | Direct scoped `.from("creator_profiles").update(update)` | `:780-787` |
| **Omitted fields** | Skipped — `if (value === undefined) continue` for scalars, arrays, adaptive columns | `normalizedCreatorProfileUpdate`: `:805-809`, `:827-829`, `:903-905`, `:841-845`, etc. |
| **Explicit null on arrays** | `normalizedTextArray(null)` → `[]` — would clear if client sends `null` | `:1000-1003` |
| **Explicit null on JSON objects** | `on_camera_restrictions ?? {}`, `first_idea_handoff ?? {}`, `language_preferences ?? {}` when field is **present** | `:912-921`, `:923-931`, `:934-942` |
| iOS encoder | Profile updates omit unset keys (`encodeIfPresent` / conditional encode) | `WriteContentDTOs.swift:94-123`; repository invokes edge function `write-content` `:1111-1115` |

**Appendix A alignment:** §3.1 (~lines 604-606) already states omitted fields are deliberately skipped. **Correction to handoff Step 6 wording:** the cited range `index.ts:792-838` now spans the successful-update **response** (`:794-797`) and the **start** of `normalizedCreatorProfileUpdate`, which **preserves** omitted keys — it does **not** default omitted adaptive fields to empty arrays. Residual mixed-version risk is narrower: **explicit** `null` / empty payloads and **insert** paths (`:751-762`), not omission alone. **Runtime-unproven** against staged/old clients.

**Disposition impact:** **CH-07** unchanged (verify with fixtures + hosted schema); refine proof to explicit-null vs omitted-field matrix.

---

### 2.7 `generate-plan-ideas` scopes `creators`, not `creator_profiles`

| Check | Finding | Citation |
|---|---|---|
| Optional creator gate | `.from("creators").select("id")` with workspace + active filters | `generate-plan-ideas/index.ts:96-110` |
| Profile table | Not queried in handler | Full `index.ts` read — no `creator_profiles` reference |

**Disposition impact:** Confirms Appendix A G3 (~line 547). **CH-07** backend deploy checklist unchanged.

---

### 2.8 Profile updates — direct scoped table writes (server), not `write_content` RPC

| Path | Finding | Citation |
|---|---|---|
| Server | `updateCreatorProfile` uses admin client direct insert/update on `creator_profiles` | `write-content/index.ts:725-797` |
| Other write actions | Still use `admin.rpc("write_content", …)` | `:193`, `:214` |
| iOS | `SupabaseCreatorProfileRepository.updateProfile` → `functions.invoke("write-content", …)` with `update_creator_profile` action | `SupabaseRepositories.swift:1110-1116` |

Static edge: app → Edge Function → **direct table write** (not RPC). Authorization is service-role + session checks upstream — **runtime-unproven** for isolation.

**Disposition impact:** Confirms Appendix A G3; supports **CH-07** / **CH-08** guard retention.

---

## 3. Uncommitted / non-native work (exclude from app-source audit)

**Dirty tracked (non-native):**

| Path | Status |
|---|---|
| `prototypes/today-ui/index.html` | Modified (+181/−137 vs HEAD) — HTML prototype, not `CreatorContentOS/` |

**Untracked (representative groups — not app source):**

- Tooling/scratch: `.asc/`, `.codex/`, `.derivedData/`, `.hermes/`, `.maestro/`, `.scratch/**`
- QA artifacts: `artifacts/adaptive-onboarding-qa/*.png`, `artifacts/adaptive-onboarding-qa/live-generate-day-evidence-run.json`, `artifacts/prototypes/`
- Root screenshots: `contenthelper-*.png.png`
- Script helper: `scripts/maestro.sh`

Native app source remains **`CreatorContentOS/`** plus committed Supabase/functions/migrations/tests per Appendix A.

---

## 4. Appendix A corrections (this refresh only)

| ID | Prior / handoff claim | Refresh result |
|---|---|---|
| A-COR-1 | Handoff Step 6: `write-content/index.ts:792-838` “defaults omitted adaptive fields to empty arrays” | **Stale line citation.** At pinned HEAD, `:792-838` is mostly response + normalizer entry; **omitted** fields are skipped (`continue` on `undefined`). Risk remains for **explicit** `null`/empty and insert/backfill — not for omission alone. Appendix A §3.1 was already more accurate. |
| A-COR-2 | (none) | All other refreshed items **confirm** Appendix A / G1–G3 / reachability notes without contradiction. |

No full 128-row ledger rewrite.

---

## 5. Recommended change-ledger dispositions (CH-01…CH-16)

Static refresh only — does not replace Step 1 runtime collection or Step 2 Grok consolidation.

| ID | Refresh stance | Notes from this pass |
|---|---|---|
| **CH-01** | **Keep** | SHAs pinned; 128-file baseline still valid. |
| **CH-02** | **Hold for product gate** | Unchanged; not re-litigated here. |
| **CH-03** | **Proceed when copy ledger starts** | No new prose findings. |
| **CH-04** | **Proceed** | Paper deliverable independent of this refresh. |
| **CH-05** | **Add (confirmed gap)** | Sign-out only; no deletion flow in source. |
| **CH-06** | **Add (confirmed gap)** | No app-owned manifest; no in-app policy link. |
| **CH-07** | **Keep + narrow test matrix** | Confirm omitted-vs-null profile payloads; hosted state still unverified. |
| **CH-08** | **Keep guards** | Direct profile write path confirmed static. |
| **CH-09** | **Defer until measure** | No new hotspot data. |
| **CH-10** | **Hold** | Document B scope; TPE tests reference unreachable `.shootFolio` routes — merge/remove only with runtime reachability decision. |
| **CH-11** | **No action** | Still N/A. |
| **CH-12** | **Keep** | ASC/listing work unchanged. |
| **CH-13** | **Keep** | Build artifact gap unchanged. |
| **CH-14** | **Hold** | Access blocker unchanged. |
| **CH-15** | **Add/fix (confirmed gap)** | Inline read-only; Shoot Folio handler-only. |
| **CH-16** | **Keep** | Resize + VoiceOver control verified at cited lines. |

---

## 6. Open uncertainties (runtime / hosted — not resolved here)

1. **Shoot Folio reachability** — static: no launcher; runtime: confirm no deep link, programmatic push, or DEBUG-only path in Release builds.
2. **Main-package copy round-trip** — requires simulator/device proof for Script/Caption tabs on Today.
3. **External publication / “actual shared post”** — not observable from source.
4. **Hosted Supabase** — migration applied?, `generate-plan-ideas` deployed?, function versions vs candidate.
5. **Profile mixed-version** — fixture tests for omitted vs explicit-null adaptive fields on established profiles.
6. **Account deletion backend** — no endpoint/UI exists to review yet.
7. **Privacy manifest in Release archive** — must inspect built `.app` bundle, not source tree alone.
8. **AI consent boundaries** — storyboard `.task` thumbnail prep and Plan idea generation outbound paths need runtime consent UX proof (**CH-06**).
9. **September Release test pass** — no refreshed execution evidence in this pass.
10. **TPE-3 / TPE-5 tests** — assert `.shootFolio` entry routes that may no longer match product navigation; reconcile after **CH-15** fix or mark obsolete.

---

## 7. Evidence boundary

| Proven statically (this refresh) | Not proven |
|---|---|
| SHA pin, merge-base geometry | Hosted DB/functions deployment |
| Handler vs launcher for Shoot Folio | VoiceOver/drag behavior on device |
| Read-only inline Script/Caption | Clipboard content correctness |
| Sign-out without deletion | Account deletion E2E |
| No app-owned xcprivacy in repo | Archive-embedded privacy manifests |
| `creators` scope in generate-plan-ideas | Provider call success on hosted env |
| Direct table write branch for profile update | RLS/isolation under live traffic |
| Storyboard resize source controls present | Reduce Motion / tab animation UX |

---

*End of Document A refresh.*
