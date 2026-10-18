# ContentHelper change ledger — Step 2

One ledger. Prepared 7 September 2026. Write-only audit folder. No app source edits. No tests run. No git mutations. No deploys.

**Candidate SHA:** `20766cd90fd6338592d8fb7792395f566eda1205`\
**Live `origin/main`:** `1fc0df2aa2b4f5d79bb41d91dd6eec895c4963d3`\
**Branch:** `cursor/today-ui-prototype-cea4`\
**Native source:** `CreatorContentOS/` (HTML prototype is not the app)

Parent ack of this ledger is required before implementation. `accepted` means authorized after that ack. It does not mean already done.

---

## Decision A (binding, Bobby 7 Sep 2026)

Encoded here because `product-decision-2026-09-07.md` and `onboarding-contract-launch-A.md` are **absent**.

1. Keep Apple sign-in first.
2. Launch bar = time to first useful script / storyboard / caption package.
3. Sharing is measured separately.
4. Do not call generation a publication.
5. Mark-as-posted is not a shared post.
6. The Sept-2 60-second actual-share rule is **superseded for this launch** and **deferred, not deleted**.
7. CH-02 is in-scope: one short skippable choice screen; defer taste / production / context to existing You editors; preserve established profiles; no second profile subsystem.

---

## Sources

| Source | Status |
| --- | --- |
| `document-a-refresh.md` | Present. SHA pin holds. Call-graph refresh consumed. |
| `document-b-refresh.md` | Present. SHA pin holds. Test-value refresh consumed. No tests run. |
| `step-0-source-snapshot.md` | Present. Tools and build `2026081102` recorded. |
| `product-decision-2026-09-07.md` | Missing. Decision A encoded above. |
| `onboarding-contract-launch-A.md` | Missing. Decision A CH-02 contract encoded in CH-02. |
| `copy-ledger.md` / `copy-ledger-summary.md` | Missing. Does not block this ledger. CH-03 creates the copy ledger. |
| Plan §8 / Appendix A–C | Consumed from `.hermes/plans/contenthelper-release-first-cursor-20260907.md`. |

**Stale handoff correction (A-COR-1):** the claim that `write-content/index.ts:792-838` defaults omitted adaptive fields to empty is **stale**. Refresh: omitted fields are skipped; explicit null can still clear. Folded into CH-07. No extra CH-17 for the same write path.

**Runtime:** unknown. Hosted schema, hosted functions, hosted deletion, VoiceOver-on-device, clipboard round-trip, and TestFlight parity are not proven.

**Not two changes:** Document A and Document B agreeing is one row. “Slop / cleaner / fewer lines” is not a justification.

---

## Rank rule

1. Account / privacy / data loss\
2. Blocked creator outcome\
3. Misleading UI / listing\
4. Maintainability\

---

## Ranked rows

| Rank | ID | Decision | Class |
| --- | --- | --- | --- |
| 1 | CH-05 | accepted | Account deletion (implement). Hosted deletion **not** verified. |
| 2 | CH-06 | accepted | App privacy, consent, manifest. Hosted policy pages remain a host gate. |
| 3 | CH-08 | accepted | Keep lifecycle / isolation guards. |
| 4 | CH-07 | held | Profile omit-vs-null contract; **deploy held**. |
| 5 | CH-15 | accepted | Restore copy on Today inline Script/Caption. |
| 6 | CH-02 | accepted | One short skippable onboarding screen. |
| 7 | CH-01 | accepted | Keep September creator workflow as baseline. |
| 8 | CH-16 | accepted | Keep storyboard resize / VoiceOver. |
| 9 | CH-12 | accepted | Replace CozyStack listing; fill missing ASC fields. |
| 10 | CH-03 | accepted | Copy ledger then cut redundant prose. |
| 11 | CH-04 | accepted | New editable Paper file + state map. |
| 12 | CH-13 | accepted | New unused build number + signed Release artifact. |
| 13 | CH-14 | held | GitHub Discussions (feature off). |
| 14 | CH-10 | accepted | Named test removals only after survivor proof. |
| 15 | CH-17 | deferred | Sept-2 60s actual-share journey. |
| 16 | CH-09 | deferred | Refactor only after measured hotspots. |
| 17 | CH-11 | rejected | Do not add trial / paywall. |

Implementation-facing set after parent ack: **CH-05, CH-06, CH-02, CH-15, CH-03, CH-04, CH-12, CH-13**. Keeps in the same wave: **CH-01, CH-08, CH-16**. CH-10 may proceed only as listed batches after Step 8 proof.

---

## CH-05 — Add in-app account deletion

| Field | Content |
| --- | --- |
| **ID** | CH-05 |
| **evidence** | Static: `YouAccountView.swift` sign-out only (`:20`, `:250-279`). Grep of `CreatorContentOS/` found no `deleteAccount` / “Delete account”. Session sign-out is not account deletion. Apple App Store Review 5.1.1. Document A §2.3. Step 0: no hosted deletion check. |
| **user/compliance failure** | Apple sign-in creates a real account. The creator cannot delete that account in the app. Review can reject the app. |
| **proposed delta** | Add in-app deletion on You → Account: consequences, cancel, confirm, pending, failure, retry, success. Backend must derive creator/workspace from the authenticated session, not a client-supplied account id. Remove retained personal data per policy. Revoke Apple auth / session. Clear local state only after success. No cross-account delete. No fake success. |
| **smallest alternative** | App Store “account deletion URL” only, with no in-app flow. Rejected: 5.1.1 requires in-app deletion when the app creates accounts. |
| **affected callers/data** | `YouAccountView`; new session-scoped delete path; `creator_profiles` / workspace / session / local caches; Apple credential revoke. No endpoint exists yet to review. |
| **retained invariant/test** | Account isolation; sign-out still works; established packages of other accounts untouched; truthful failure/retry. Do not use a real creator account. |
| **validation** | Local isolated disposable-account checks, labeled as local. **Hosted deletion is not verified.** Submission stays held until hosted proof of delete / retain / revoke / isolate / retry. |
| **rollback** | Remove the You control and client call. Leave any additive backend unused. Do not claim deletion works. |
| **decision** | **accepted** (implement after parent ack). Hosted verify remains open. Do not mark hosted deletion verified. |

---

## CH-06 — Privacy link, App Privacy manifest, AI consent

| Field | Content |
| --- | --- |
| **ID** | CH-06 |
| **evidence** | Static: no app-owned `.xcprivacy` under `CreatorContentOS/` or `project.yml`. No in-app privacy-policy URL in Swift. ASC: empty privacy-policy URL; App Privacy unpublished. `privacy.contenthelper.in` describes **PipCount**. Automatic AI paths: storyboard `.task` at `GeneratedDayPlannedContent.swift:167-169`; Plan idea generation. Apple 5.1.2. Document A §2.4. |
| **user/compliance failure** | Creator cannot open a ContentHelper privacy policy in the app. Third-party AI can receive personal data without a recorded consent boundary. Archive privacy reasons are unverified. |
| **proposed delta** | (1) App-owned privacy manifest with approved reasons that match actual APIs, including UserDefaults. Inspect the archived `.app`, not source existence alone. (2) In-app ContentHelper privacy link. (3) Explicit consent before sharing personal data with AI providers, including automatic outbound paths; consent version; refuse / retry. (4) Prefer new ContentHelper routes on the existing support/privacy host. Preserve PipCount URLs. Do not replace the host root with ContentHelper-only content. |
| **smallest alternative** | ASC URL only, no in-app link and no consent. Rejected: 5.1.2 and the in-app gap remain. |
| **affected callers/data** | `YouAccountView` / You surfaces; `GeneratedDayPlannedContent` thumbnail `.task`; Plan idea generation; `project.yml` resource; ASC privacy fields (also CH-12); hosted pages (host approval). |
| **retained invariant/test** | PipCount policy URLs stay valid. No guessed NSPrivacyAccessedAPIType reasons. Do not log private notes, tokens, or raw personal prompts. |
| **validation** | Archive inspect of app + dependency manifests. In-app link opens the ContentHelper policy. Consent accept / decline / retry on generate and automatic thumbnail / Plan-idea paths. Host page read-back for **both** apps after host approval. |
| **rollback** | Remove app link and manifest; restore prior ASC privacy fields. Do not leave ContentHelper pointed at PipCount copy. |
| **decision** | **accepted** for app manifest, in-app link, and consent UX. Hosted page write is a **host gate** (not claimed done). |

---

## CH-08 — Keep lifecycle guards

| Field | Content |
| --- | --- |
| **ID** | CH-08 |
| **evidence** | Plan §1 invariants and Appendix A G3: one package per creator/day; overwrite confirmation; `makeDayAvailable` vs Instagram publish; first-idea skip if today already ready/edited. Profile updates use direct scoped table writes (`write-content/index.ts:725-797`), not `write_content` RPC. Document A §2.8. |
| **user/compliance failure** | Duplicate generation or silent overwrite can destroy a ready / edited package. Cross-account writes would leak or wipe data. |
| **proposed delta** | Keep lease, identity, tenant-isolation, overwrite, cancel, and recovery guards. Narrow a predicate only when CH-02 first-idea gating requires it. Do not “simplify” the Release vs DEBUG `DebugLaunchFlags` split. |
| **smallest alternative** | Leave all predicates untouched, including a first-idea block caused by optional voice. Worse for CH-02; do not use that as a reason to delete isolation guards. |
| **affected callers/data** | `AppServices` generation dispatch; `OnboardingFirstIdeaHandoff`; `makeDayAvailable`; `write-content` profile branch; Plan overwrite alerts. |
| **retained invariant/test** | DLT-8 (first idea uses `makeDayAvailable`, never `publishWeek`); FirstIdeaHandoff / DayLifecycle overwrite and isolation tests; generation_already_running. |
| **validation** | Existing lifecycle tests after any narrow predicate edit. Retry must not unpublish a ready card. Sign-out / delete / switch must drop in-flight writes. |
| **rollback** | Restore the previous predicate. |
| **decision** | **accepted** (keep). |

---

## CH-07 — Additive profile compatibility; omit-vs-null; deploy held

| Field | Content |
| --- | --- |
| **ID** | CH-07 |
| **evidence** | **A-COR-1:** handoff Step 6 wording that `write-content/index.ts:792-838` defaults omitted adaptive fields to empty is **stale**. At pinned HEAD that range is response + normalizer start. `normalizedCreatorProfileUpdate` **skips** `undefined` (`:805-809`, `:827-829`, `:841-845`, `:903-905`). Explicit `null` on arrays → `[]` (`:1000-1003`). Explicit present JSON objects use `?? {}` (`:912-942`). Insert defaults at `:751-762` are a different path. iOS omits unset keys (`WriteContentDTOs.swift:94-123`). `generate-plan-ideas` scopes `creators`, not `creator_profiles`. Hosted migration/functions **unverified**. Migration `20260905120000_adaptive_creator_onboarding.sql` is additive **plus** a backfill data update. |
| **user/compliance failure** | An old client that omits adaptive keys while editing another field must not wipe taste / production / context. An explicit clear must still work. A new client against an old server can fail or store incomplete profiles. Local smoke is not hosted proof. |
| **proposed delta** | Require all three: (1) preserve existing adaptive values on **omission**; (2) retain an explicit **validated** clear path; (3) keep **insert defaults separate from update** semantics. Fixture later for omitted vs explicit-null. Do **not** deploy this row now. Do not call the migration compatible only because columns are additive. |
| **smallest alternative** | Ship the client now and “watch production.” Rejected. |
| **affected callers/data** | `write-content/index.ts` `updateCreatorProfile` / `normalizedCreatorProfileUpdate`; `exchange-auth-session`; `read-content` select; `generate-week`; `generate-plan-ideas`; iOS `SupabaseCreatorProfileRepository`; `creator_profiles` rows; backfill of `onboarding_state`. |
| **retained invariant/test** | Established profiles must not be rewritten to empty. CH-02 must reuse this profile, not a second store. Additive columns stay on rollback. |
| **validation** | Fixture omitted-key update vs explicit-null vs insert, against the candidate handler, **before** any deploy. Then hosted schema/function read-back. Old-client/new-server and new-client/old-server. Then explicit production approval. |
| **rollback** | Roll back functions/client. Keep additive columns/data. Do not drop columns to match old code. |
| **decision** | **held** (deploy and hosted proof). Fixture is later, not a deploy. |

---

## CH-15 — Restore main-package copy; editor only if scene edit is lost

| Field | Content |
| --- | --- |
| **ID** | CH-15 |
| **evidence** | Static: Today uses `TodayInlineExecutionPackage` → `GeneratedDayPlannedContent`. Script panel read-only (`GeneratedDayPlannedContent.swift:715-779`). Caption panel read-only (`:682-698`). `UIPasteboard` only in `ShootFolioView.swift:575`, `:657`. No production `CreatorRoute.shootFolio` launcher in `CreatorContentOS/` (handler in `CreatorShellView.swift:11-14`; tests only in `TodayPlanEntryTests.swift`). Backup copy is a different sheet, not the main package. UIT-6 is entry smoke, not copy proof. UIT-7 is a skipped Folio-first journey. Document A §2.1–2.2. Runtime copy round-trip **unknown**. |
| **user/compliance failure** | Creator can see a script and caption and cannot copy them from Today. Scene edit lives on an unreachable Shoot Folio. Launch bar (Decision A) is time to a **usable** package, not a generated card. |
| **proposed delta** | Reproduce on the candidate, then add copy actions on the **existing inline** Script and Caption surfaces, reusing existing copy formatting / “Copied” feedback (`CopyBlock` / `ScriptTimelineCopyBlock`). Do **not** add a production Shoot Folio launcher. Add a **narrow** editor entry only if scene/script edit is otherwise lost. Do not duplicate the package screen. Do not restore old Folio-first chrome. Sharing / external post is **not** this row (see CH-17). Mark-as-posted is not a shared post. Do not call generation a publication. |
| **smallest alternative** | Wire Today Edit to `CreatorRoute.shootFolio`. Rejected as the primary fix: Folio is unreachable by design of the inline Today path; copy belongs on the surface the creator already sees. |
| **affected callers/data** | `GeneratedDayPlannedContent`; `TodayInlineExecutionPackage`; `TodayView`; optional narrow push to existing `ShootFolioView` editor if scene edit is otherwise lost; UIT-7 replace in existing installed suite; TPE-3 / TPE-5 after the navigation decision. |
| **retained invariant/test** | UIT-6 remains smoke only; a pass is **not** CH-15 acceptance. CH-16 resize control stays. Backup copy path stays. DLT-8: first idea still does not Instagram-publish. |
| **validation** | Simulator/device: copy exact script and caption from Today inline tabs; current date/card identity; if editor is added, save / cancel / failure. Runtime still unknown until that run. Do not use external share as this row’s pass. |
| **rollback** | Revert the narrow copy/editor patch. |
| **decision** | **accepted**. |

---

## CH-02 — Reduce first-run to one skippable choice screen

| Field | Content |
| --- | --- |
| **ID** | CH-02 |
| **evidence** | Current flow: five mandatory steps after Apple sign-in (interests, taste, production, context, review) in `OnboardingFlowView` / `OnboardingViewModel`. Decision A (Bobby 7 Sep 2026) unblocks the product gate that previously held this row. Established-profile policy already exists (`OnboardingPresentationPolicy`, workspace-scoped store). `ch-onboarding-done` UserDefaults is not the live gate. |
| **user/compliance failure** | Five mandatory screens delay the first useful package. Taste / production / context already have You editors. A second profile system would split and can overwrite saved preferences. |
| **proposed delta** | After Apple sign-in, one short **skippable** choice screen. Move taste, production, and context to existing You editors (`YouContentCategoriesView`, `YouProductionPreferencesView`, `YouCurrentContextView`, voice/references as today). Reuse `OnboardingFlowView`, `OnboardingViewModel`, store, presentation policy, and `creator_profiles`. Preserve established / legacy profiles. No second profile subsystem. No mandatory typing, handles, reference links, or voice questionnaire. First-idea path must not wait on optional voice/reference. Keep a later route to add preferences. Do not mark a fixture/default profile as learned preference. Launch bar = time to first useful package, not an Instagram share. |
| **smallest alternative** | Skip onboarding entirely for everyone. Weaker: new creators get no honest starting choice; Decision A asks for one short skippable screen. |
| **affected callers/data** | `OnboardingFlowView`, `OnboardingViewModel`, `OnboardingModels` / `OnboardingStep`, `OnboardingStore`, `OnboardingPresentationPolicy`, `OnboardingFirstIdeaHandoff`, You editors, `generateDayCard` / `makeDayAvailable`. Paper current-state artboards keep the five-step record labeled as current, not as the target. |
| **retained invariant/test** | AOP-4 / AOP-5 / AOV-2 (established vs new; scoped store vs global flag). FirstIdeaHandoff: no overwrite of ready/edited/shot/posted. Legacy enum decode. CH-07 omit semantics. Do not force onboarding on `loadFailed` with a previous established snapshot. |
| **validation** | First-run, skip, returning established, resume partial, retry after failed first idea, relaunch does not resurrect discarded mandatory steps. Paper target matches the one-screen contract. Copy rows in CH-03. |
| **rollback** | Restore five-step `OnboardingFlowView` switch and presentation for `new` / `partial`. Do not rewrite established rows. |
| **decision** | **accepted**. |

---

## CH-01 — Keep September creator workflow as baseline

| Field | Content |
| --- | --- |
| **ID** | CH-01 |
| **evidence** | Step 0 + Document A: HEAD `20766cd9…`, main `1fc0df2a…`, 32 commits, 128 files (78 added, 50 modified, 0 net deletions). Native `CreatorContentOS/` clean. Last uploaded binary is August `2026081102`, not this candidate. |
| **user/compliance failure** | Rebuilding from the August upload or from stale main would drop Today / Plan / You, ready packages, and persistence work. |
| **proposed delta** | Implement from this candidate SHA. Do not start from the August binary. Do not treat `prototypes/today-ui/index.html` as native. Preserve dirty prototype/QA files (do not stash/reset/clean). |
| **smallest alternative** | Ship August TestFlight as 1.0. Rejected: it is the wrong product snapshot. |
| **affected callers/data** | Whole candidate vs main delta. Uncommitted prototype/QA excluded from native edits. |
| **retained invariant/test** | Today / Plan / You shell; existing visual system; account isolation; one package per creator/day. |
| **validation** | Re-read SHAs before implementation. Native dirty check on `CreatorContentOS/` stays empty except accepted edits. |
| **rollback** | Isolated patch restore; do not reset the worktree to “help” the audit. |
| **decision** | **accepted** (keep). |

---

## CH-16 — Keep storyboard resize and VoiceOver adjustment

| Field | Content |
| --- | --- |
| **ID** | CH-16 |
| **evidence** | Static at pinned HEAD: `sceneResizeHandle` at `GeneratedDayPlannedContent.swift:288`; drag clamp `:338-358`; `accessibilityLabel("Resize scene column")` + `accessibilityAdjustableAction` `:360-370`. Document A §2.5. Device VoiceOver behavior **unproven**. |
| **user/compliance failure** | Removing the control would block column resize and VoiceOver adjustment on the storyboard the creator uses. |
| **proposed delta** | Keep the control. Represent drag / adjustment in Paper (CH-04). Respect Reduce Motion on folder-tab transitions (`:90-104`). Do not call those transitions non-animated. |
| **smallest alternative** | Delete as “dead UI.” Rejected: source shows a live render call, gesture, and accessibility action. |
| **affected callers/data** | `GeneratedDayPlannedContent` storyboard panel; CH-15 copy work must not delete this handle. |
| **retained invariant/test** | No deletion of `:288` / `:338-370`. Visual/VoiceOver check when CH-15 is verified. |
| **validation** | Drag plus VoiceOver increment/decrement on device when runtime collection runs. |
| **rollback** | Not applicable unless a later patch removes it; restore those lines. |
| **decision** | **accepted** (keep). Deletion is rejected. |

---

## CH-12 — Store listing: ContentHelper, not CozyStack

| Field | Content |
| --- | --- |
| **ID** | CH-12 |
| **evidence** | Live ASC app `6777027653`, bundle `com.prateekranka.creatorcontenthelper`, version 1.0 `PREPARE_FOR_SUBMISSION`, no build attached. `asc validate` 29 blocking errors. Semantic: description / keywords / promotional text describe **CozyStack**. Empty privacy URL and subtitle. Missing support URL, review details, category, content-rights, availability, screenshots, age-rating fields. Plan §2. |
| **user/compliance failure** | Store page describes the wrong product. Reviewer and customer cannot tell what ContentHelper is. Presence validation did not catch this. |
| **proposed delta** | Replace CozyStack text with the actual creator product. No “automatic posting,” “learns your voice,” growth guarantees, or subscriptions. Fill support/privacy URLs (ContentHelper-specific; see CH-06 host gate), review contact, category, content rights, territories, age rating, App Privacy, screenshots of the **final** candidate. Answer rights/age/privacy from actual behavior. |
| **smallest alternative** | Fix validator errors with suggested defaults and leave CozyStack sentences. Rejected: semantic lie remains. |
| **affected callers/data** | ASC version 1.0 metadata; screenshots; App Privacy nutrition; CH-06 URLs; CH-13 selected build. |
| **retained invariant/test** | Draft before-values retained. PipCount listing/URLs untouched. |
| **validation** | ASC read-back. Re-run `asc validate`. Human semantic pass (not zero-errors only). Screenshots match the candidate, not August. |
| **rollback** | Restore saved draft before-values. |
| **decision** | **accepted**. |

---

## CH-03 — Copy ledger, then remove redundant UI prose

| Field | Content |
| --- | --- |
| **ID** | CH-03 |
| **evidence** | Appendix C copy notes (C2 desktop “Clicking”; C4 title duplication; C5 provider jargon; C9 “Generation inputs”; C11 Archive “Completed”; backup “streak” copy). No `copy-ledger.md` exists yet. Plan Step 4 format: `screen/state \| existing text \| keep/cut/rewrite \| proposed text \| information/action/safety job \| evidence`. Decision A: do not call generation a publication; mark-as-posted is not a shared post. |
| **user/compliance failure** | Extra reading hides the next action. Provider jargon and wrong verbs mislead (Approve as if Instagram; “published card” vs ready package). |
| **proposed delta** | Extract every static user-facing string. Fill the copy ledger. Cut duplicate headings, decorative slogans, and instructions the control already shows. Keep safety, navigation, dates, units, consequences, recovery, and accessibility labels. Generated package text is content, not chrome. Apply Decision A vocabulary: generation ≠ publication; posted flag ≠ shared post. |
| **smallest alternative** | Cut words without a ledger. Rejected: can remove recovery or consent text. |
| **affected callers/data** | Native Swift / localization; onboarding (CH-02); Today / Plan / You; CH-15 copy-button labels; Paper (CH-04). |
| **retained invariant/test** | Accessibility labels that name resize / Back / destructive confirm stay unless a ledger row replaces them with an equal job. |
| **validation** | Every changed string has a ledger row. Visual + VoiceOver pass on touched screens. Revert by copy-ledger ID. |
| **rollback** | Revert the specific copy row. |
| **decision** | **accepted**. |

---

## CH-04 — New editable Paper file and full state map

| Field | Content |
| --- | --- |
| **ID** | CH-04 |
| **evidence** | User requires a complete editable design inventory. Plan Step 3: new file `ContentHelper — Launch screens and states — 2026-09-07`. Do not overwrite an unrelated Paper file. Paper MCP was refused during the earlier audit; opening the file in Paper Desktop is the recovery path. Appendix C is the screen/state input. |
| **user/compliance failure** | Without an editable map, onboarding/privacy/deletion/copy proposals cannot be reviewed as screens. Screenshots-as-artboards fail the requirement. |
| **proposed delta** | Create that **new** Paper file. Index: screen/state ID → source route → artboard → current/proposed. Include current five-step onboarding as **current**, and Decision A one-screen + You editors + deletion/consent as **proposed**, labeled as proposals. Accessibility variants. Pocket Sheet tokens. Grok verifies editability on a real label/component. |
| **smallest alternative** | HTML prototype or screenshot board. Rejected: user asked for editable Paper. |
| **affected callers/data** | Paper file only. No app source. Unreachable Shoot Folio states marked existing/unreachable until runtime. |
| **retained invariant/test** | Unrelated open Paper files untouched. Five-step current artboards retained even after CH-02 ships. |
| **validation** | Manifest has no unexplained missing reachable screen/state. File ID/link recorded. One edited label/component proves editability. |
| **rollback** | Leave the new file; do not write into other files. |
| **decision** | **accepted**. Connection failure = Step 3 blocked, not a reason to skip the deliverable. |

---

## CH-13 — New build number and signed current Release artifact

| Field | Content |
| --- | --- |
| **ID** | CH-13 |
| **evidence** | Step 0: `project.yml` `CURRENT_PROJECT_VERSION` `2026081102`; `Info.plist` uses that variable. Last ASC upload is the same number (11 August). No September signed Release candidate. Release bootstrap: `scripts/require-live-release-bootstrap.sh` rejects localhost/placeholder. |
| **user/compliance failure** | A new upload cannot reuse `2026081102`. Shipping August as “this candidate” would be a false build. |
| **proposed delta** | Allocate and verify an **unused** build number. `xcodegen generate` after `project.yml` change. Archive/sign/export this candidate with live Release bootstrap. Confirm no DEBUG flags, no localhost. Then request upload approval. Select only that build in ASC. |
| **smallest alternative** | Re-upload 2026081102. Impossible if ASC still holds it as used. |
| **affected callers/data** | `project.yml`, generated `project.pbxproj`, `Info.plist`, archive, ASC build. Privacy manifest (CH-06) must be in the archive. |
| **retained invariant/test** | Release bootstrap gate stays. DEBUG fixture/admin shell stays `#if DEBUG`. |
| **validation** | Archive identity, entitlements, privacy manifests, version string, ASC processing read-back. Debug green ≠ Release ready. |
| **rollback** | Do not submit the new binary. Keep `2026081102` recorded as the last **uploaded** number until the new one processes. |
| **decision** | **accepted**. Upload/submit remain separate explicit approvals. |

---

## CH-14 — GitHub Discussions publication

| Field | Content |
| --- | --- |
| **ID** | CH-14 |
| **evidence** | Step 0: `hasDiscussionsEnabled: false` / `has_discussions: false`; GraphQL count 0. `gh` logged in as `prateekranka` with `repo` scope; Discussions **feature** is still off. Plan asked for two review discussions plus full read-back. |
| **user/compliance failure** | External review comments cannot land in GitHub Discussions. Claiming local files are published discussions would be false. |
| **proposed delta** | After explicit approval **and** Discussions enabled, publish Document A and B (or this ledger + appendices) without truncating inventories. Read back every chunk. If still blocked, keep publication-ready local files. |
| **smallest alternative** | Enable Discussions and publish without read-back. Rejected: plan requires identity check of bodies. |
| **affected callers/data** | GitHub repo `prateekranka/instaContentHelper` Discussions. Not app source. |
| **retained invariant/test** | Local ledger remains the execution source if publication stays blocked. |
| **validation** | Both URLs; full paginated bodies; SHA pins present; reconstruction matches local files. |
| **rollback** | Do not claim published. Leave Discussions off if that was the prior state. |
| **decision** | **held** (feature blocked). Auth/feature gate. |

---

## CH-10 — Remove or merge only named test candidates

| Field | Content |
| --- | --- |
| **ID** | CH-10 |
| **evidence** | Document B body review, no execution. GFX-1…6 duplicate SBT-1/3/4/5/6/7 through re-export; **SBT-2 must survive**. AOV-3 unused defaults + duplicate of AOP-5; keep AOP-4 and AOP-5. ONB-29 subsumed by ONB-25. AOP-2 weaker than AOV-2; merge into AOV-2. UIT-1…5, UIT-11 skip on line 1; remove after helper grep. UIT-7 replace as part of CH-15, do not revive Folio-first. UIT-6 keep as smoke only. `DevicePairingService.swift` keeps `SupabaseTimestampParser` (Apple `pairedAt` in `AuthenticationService.swift:213`). `deno.json` `test:backend` is `supabase/functions` only; `scripts/day-generation-under-60-benchmark_test.ts` and `scripts/workers/generate-day-worker_test.ts` are outside it. TPE-3/TPE-5 still name `.shootFolio` (reconcile after CH-15). Runtime pass/fail **unknown**. |
| **user/compliance failure** | Duplicate/skipped tests raise upkeep and can be mistaken for coverage. Silent deletion can hide a real contract. |
| **proposed delta** | After Step 8 survivor proof, in small batches: remove GFX-1…6 (keep SBT-2); remove AOV-3; remove ONB-29; merge AOP-2 into AOV-2; remove UIT-1…5 and UIT-11 after helper grep (keep UIT-6/8/9/10). Replace UIT-7 inside CH-15. Add the two script tests to the **existing** deno task/workflow. No new test framework. No new test files unless separately approved. Do not delete `DevicePairingService.swift`. |
| **smallest alternative** | Delete all skipped UI tests now. Rejected: no survivor proof; helpers may still be referenced. |
| **affected callers/data** | `generate-storyboard-thumbnail/storyboard-thumbnail_test.ts`; AdaptiveOnboarding* tests; `OnboardingTests.swift`; `InstalledContentHelperUITests.swift`; `deno.json` / `.github/workflows/backend-checks.yml`; TPE tests after CH-15. |
| **retained invariant/test** | SBT-1, **SBT-2**, SBT-3–7; AOP-4, AOP-5, AOV-2; ONB-25; UIT-6/8/9/10; `SupabaseTimestampParser`. Restore any removal that hides a contract. |
| **validation** | Step 8: run affected tests after each batch. Helper grep before UIT helper deletion. Do not treat UIT-6 pass as CH-15. |
| **rollback** | Restore the deleted test body from git. |
| **decision** | **accepted** (plan authorized). Deletions execute only after survivor proof. No test run yet. |

---

## CH-17 — Sept-2 60-second actual-share (deferred)

| Field | Content |
| --- | --- |
| **ID** | CH-17 |
| **evidence** | Plan §3 older rule: zero fields, actual shared post within 60 seconds, visible Back/retry, independent repeat. Decision A (Bobby 7 Sep 2026): that rule is superseded **for this launch** and deferred, not deleted. Launch bar is time to first useful package. Sharing measured separately. |
| **user/compliance failure** | If treated as this launch’s bar, the app would need guest-auth / capture / export / Instagram share work that is not in the implementation-facing set. If deleted from the ledger, the original promise is lost. |
| **proposed delta** | Do not implement an actual-share-within-60s journey in this launch. Do not fold it into CH-15 or CH-02. Keep the row. Measure sharing later with a separate scope. |
| **smallest alternative** | Relabel generation or mark-as-posted as “publication.” Rejected by Decision A. |
| **affected callers/data** | None this launch. Future share / export / guest-auth would be a new ledger row. |
| **retained invariant/test** | DLT-8 remains: first idea is `makeDayAvailable`, not Instagram publish. Mark-as-posted stays a local decision. |
| **validation** | Not this launch. A later share program needs its own proof of an actual shared post. |
| **rollback** | Not applicable. |
| **decision** | **deferred** (not deleted). |

---

## CH-09 — Refactor measured hotspots only

| Field | Content |
| --- | --- |
| **ID** | CH-09 |
| **evidence** | Large files (`AppServices.swift`, `OnboardingViewModel.swift`, `OnboardingFlowView.swift`, `generation.ts`) are size signals, not complexity measurements. `swiftlint` and `lizard` missing (Step 0). No hotspot measure this pass. Quentin Cody metrics are review signals, not a rewrite order. |
| **user/compliance failure** | Unrelated splits delay launch and can break dispatch / state machines. |
| **proposed delta** | After a supported measure on **touched** functions only, allow a small refactor that improves the approved contract. No repository-wide split. No new lint ecosystem. |
| **smallest alternative** | Split every file over 500 lines. Rejected. |
| **affected callers/data** | Only functions already in an accepted row’s diff. |
| **retained invariant/test** | Unchanged public contracts; source diff limited to the hotspot. |
| **validation** | Tool/version + before/after. Behavior tests for that contract. |
| **rollback** | Revert the isolated refactor. |
| **decision** | **deferred** until measure. |

---

## CH-11 — Do not add trial / paywall

| Field | Content |
| --- | --- |
| **ID** | CH-11 |
| **evidence** | No StoreKit / RevenueCat / paywall / trial path in native or backend source. Live ASC: no IAP products, no subscription groups. Linked ineligible-trial bug is not this app. Document A CH-11 N/A. Plan §7. |
| **user/compliance failure** | Adding “Start Free Trial” would promise a product that does not exist and can lie about eligibility. |
| **proposed delta** | Do not add a trial or paywall. Record the linked bug as not applicable. A future paid launch is separate scope and must use real StoreKit eligibility. |
| **smallest alternative** | Add a fake trial CTA for screenshots. Rejected. |
| **affected callers/data** | None. |
| **retained invariant/test** | Search/ASC empty-catalog evidence in this ledger. |
| **validation** | Re-check ASC products before any later paid work. |
| **rollback** | Not applicable. |
| **decision** | **rejected** (do not add). |

---

## Explicit non-rows (same evidence, not extra IDs)

| Topic | Where it lives |
| --- | --- |
| write-content omit vs explicit-null | CH-07 (not a second ID) |
| No production Shoot Folio launcher | CH-15 (do not add one) |
| DevicePairingService.swift keep | CH-10 |
| Two script tests on existing deno task | CH-10 |
| Generation ≠ publication; posted ≠ shared | Decision A; CH-03; CH-15; CH-17 |
| TPE-3 / TPE-5 `.shootFolio` tests | CH-15 navigation + CH-10 survivor/reconcile |
| Hosted deletion proof | CH-05 validation (open) |
| PipCount URL coexistence | CH-06 |

---

*End of change ledger. Runtime unknown. Hosted deletion not verified. CH-07 not to deploy.*
