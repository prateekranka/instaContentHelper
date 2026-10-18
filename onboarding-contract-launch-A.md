# Onboarding contract — Launch-A

**Decision:** `dec-20260907-002` (choice **A**). See `product-decision-2026-09-07.md`.\
**Decider / date:** Bobby, 7 September 2026 IST, explicit.\
**Status:** Authorized launch contract. **Not implemented.** This file is audit-only. Do not edit app source, tests, git, or Paper while recording it.\
**CH-02:** May proceed under this contract **after** the Step 2 change ledger is accepted. Do **not** implement `OnboardingFlowView` in the recording task.

Current implemented five-step persistence and first-idea guards live in the app repo file `docs/adaptive-creator-onboarding-contracts.md`. Launch-A **supersedes first-run presentation** (five mandatory stages). It **keeps** account-scoped profile, established-profile protection, first-idea idempotency, no-HYROX identity, and “preparing a recommendation is not Instagram publish.”

---

## 1. Launch bar (do not mix these)

| Measure | Launch-A |
|---|---|
| First-run success | Time to first **useful script / storyboard / caption package** |
| Actual sharing | Measured **separately**. **Not** the launch bar |
| Sign in with Apple | **Required** before first generation |
| Post path | External / manual publishing |
| Mark as posted | Local bookkeeping. **Not** a shared post |
| Generation as publication | **Forbidden** relabel |

A fixture card, empty Today, or a local posted flag is not a useful package.

---

## 2. Audience states

Gating still starts only after `authenticationPhase == .live`. Load the workspace `creator_profiles` row. Do **not** use device-global `ch-onboarding-done` as the live gate.

| State | Who | First-run UI | Profile writes | First idea |
|---|---|---|---|---|
| **First-run `new`** | Signed-in creator. No completed adaptive onboarding. Includes missing row after ensure-profile, and auto-provisioned empty active profile. | **One short skippable choice screen.** Not five stages. | May persist `partial` or confirmed launch-A completion. **Never** copy HYROX / `CreatorProfileSummary.creatorFixture`. | Allowed after Apple session. Skip or continue both must reach a first-package path without mandatory extra screens. |
| **Returning `partial`** | Progress or skip saved, not established. Same Apple account, later launch or retry. | Resume the **same one-screen** (recoverable). Do not restart a five-step gauntlet. Do not open a second flow. | Update the same profile. | Retry **reuses saved profile**. No second package for the same creator + local today if a ready / edited / shot / posted / decision card exists. |
| **Established** | Confirmed onboarding **or** legacy real profile (positioning or pillars already real — including bootstrap TestFlight / You-edited rows). | **No first-use screen.** Creator shell: Today / Plan / You. | **No new onboarding pass may overwrite.** You editors remain the only preference edits. | Do not run first-idea overwrite. Existing ready packages stay. Plan remains available for a new brief under existing overwrite guards. |
| **`loadFailed`** | Auth live, profile read failed. | Creator shell + retry. | Do not wipe. Do not treat as `new` if a previous `established` snapshot exists for this workspace. | No generation from a guessed empty profile. |

`loadFailed` is client-only. Database `onboarding_state` stays `new | partial | established`.

DEBUG `MCO_FORCE_ONBOARDING` may still show the flow for QA. It must **not** wipe or empty an established live profile. Fixture HYROX stays fixture-only (`isLiveSupabaseRuntime == false`).

---

## 3. Skippable one-screen (proposed first-use)

**Current evidence (do not pretend this already ships):** five steps in `OnboardingFlowView` — interests → taste examples → production constraints → context → review (`OnboardingStep` raw 0…4).

**Proposed launch first-use:** one short choice screen in the **existing** onboarding types (`OnboardingFlowView` / `OnboardingViewModel` / `OnboardingStore` / presentation policy). Evolve that flow. **No second onboarding subsystem. No new profile model.**

### Allowed on the screen

- One short choice (recommended: starting point Just starting / Already posting, and/or optional interest chips from the existing catalog).
- Skip control that is honest: setup can continue later in You.
- Visible Back / cancel that leaves **recoverable** state (`partial` or equivalent saved progress). Cancel does **not** mark `established`. Cancel does **not** generate. Cancel does **not** delete the profile.
- Continue that persists the chosen fields only, then runs the existing first-idea handoff.

### Forbidden as first-run gates

- Mandatory typing.
- Handles, reel URLs, Instagram verify, reference links.
- Taste-pack stage, production form, context questionnaire, review gauntlet as **required** pre-conditions.
- Voice-personality questionnaire or voice-learning.
- Plan as the first-run destination.
- Handwritten daily brief.

Skip with **zero fields** is allowed. That is not Sept-2 “shared post in 60 seconds.” It is “do not block the first useful package on forms.”

Soft-skip today is process-only (`OnboardingViewModel.softSkip` + toast “Set up later — we'll ask again next launch”). Launch-A skip must leave recoverable state and a clear later path in **You**, not a silent trap that re-imposes five steps.

---

## 4. You-surface destinations for deferred prefs

Defer taste, detailed production prefs, and optional context to **existing** You editors. Do not add `YouRoute` cases for a parallel onboarding.

Hub: `YouView` block “Generation inputs”. Routes: `YouRoute` in `CreatorContentOS/Models/Models.swift`.

| Deferred preference | You row (current copy) | Route | View | Existing profile fields |
|---|---|---|---|---|
| Interests, starting point, custom subjects, **taste-like style** | Interests & style | `.contentCategories` | `YouContentCategoriesView` | `content_pillars`, `starting_point`, `custom_subjects`, `taste_example_ids` |
| Detailed production prefs (formats, time, language, face/voice) | Content preferences | `.productionPreferences` | `YouProductionPreferencesView` | `production_formats`, `time_to_create`, `language_preferences.primary`, `on_camera_restrictions` |
| Optional context / note | Current reads & watches | `.currentContext` | `YouCurrentContextView` | `recent_context`, `creator_note` |
| Voice (never a first-run gate) | Creator voice | `.creatorVoice` | `YouCreatorVoiceView` | `positioning`, `voice_rules`, `caption_style` |
| References / handles / links (never a first-run gate) | References | `.references` | `YouReferencesView` | existing reference import; keep `OnboardingReference*` for You/Intelligence only |

**Taste packs:** catalog remains `OnboardingExamplePacks.swift` (local, no model on Next). There is **no** dedicated You taste screen today. Do **not** invent a second subsystem. Attach any later taste-pack editing to **Interests & style**. First-run must not require a taste tap.

You editors already save onto the same `creator_profiles` row. Keep that. Existing You voice/categories saves must not wipe Launch-A columns they do not edit.

---

## 5. First-idea predicate vs overwrite / publish / generation guards

Reuse `AppServices.confirmOnboardingAndPrepareFirstIdea` and `OnboardingFirstIdeaHandoffPlanner`. Do not add a catch-all service type. Do not add a second generator.

### Predicate — when first idea **may** generate

All of:

1. Sign in with Apple completed; session live.
2. Profile persist for this confirm/skip-complete **succeeded** (or a prior saved profile for this workspace already exists on retry).
3. Scheduled date is device-local today (existing first-idea date rule).
4. No existing package for that creator + date in `DayPackageLifecycleStatus.readyOrDecision` (`published`, `in_decision`, `shot`, `posted`, `used_backup`, `saved_for_tomorrow`, `skipped_intentionally`).
5. No user-edited draft for that date (title/script/caption differ from last generated snapshot).
6. `generateDayCard(..., confirmOverwrite:)` is **false**, except the narrow retry case below.
7. Day brief is non-empty. If the creator skipped with zero fields, use an **honest generic starter brief**, not HYROX fixture copy, and not silent “learned” prefs (see §6).

Then: `makeDayAvailable` for that date; land **Today**. Do not set Plan. Do not open Shoot Folio as a required extra tab (inline Today package is the current shell).

### Overwrite guards — when first idea **must not** generate

| Condition | Action |
|---|---|
| Established profile receiving a new onboarding pass | Do not overwrite profile. Do not generate a replacement first idea. |
| Ready or Decision card for local today | `skipped_existing_ready`. Navigate Today. `confirmOverwrite: false`. |
| User-edited draft | Same skip. |
| In-flight accepted generation for that date | Resume poll; then `makeDayAvailable` if still draft. Do not start a duplicate run. |
| Persist failed | Stay `partial`. Do not mark complete. Do not generate. |

**Retry after generation failure:** profile remains saved (`established` or the Launch-A completed/partial record already written). Retry calls the same method. Retry may replace a **draft-like** leftover from that failed first-idea attempt only (`confirmOverwrite` true iff `first_idea_handoff.status == failed` AND status is draft-like). Retry must **not** unpublish ready/decision cards.

### Publish guards — never the first-idea path

- `makeDayAvailable` promotes a daily card to the **ready package**. It is **not** Instagram publish.
- Do not publish to Instagram from onboarding or first idea.
- External/manual posting remains the post path after the creator has the package.
- Mark as posted / Mark posted is Archive **Decision** bookkeeping only.

### Generation guards — keep, do not fake

- Provider path stays `generate-week` `action=generate_day`. Do not replace Gemini/DeepSeek with Grok/Composer.
- `generate_day` identity uses the loaded `creator_profile` row. If positioning/pillars do not mention HYROX, do not mention HYROX.
- Do not use `CreatorProfileSummary.creatorFixture` as a missing-profile fallback on live/first-run.
- `canGenerateContent` / voice gate must **not** force a voice questionnaire. Do **not** write fabricated positioning/voice_rules solely to flip `voiceIsConfigured` and then show You → Creator voice as **Saved**. Prefer honest `voiceDeferred` (or equivalent) so first idea can run without pretending voice was learned.
- Plan overwrite of a ready package still requires the existing explicit Overwrite confirmation. First-idea is not that path.

---

## 6. Provenance — do not mark fabricated defaults as learned preference

| Source | How to persist / show |
|---|---|
| Creator tapped a choice on the one-screen | Real preference. Save those fields only. |
| Creator skipped with empty choice | Leave preference columns empty/null. `onboarding_state` may become completed-for-launch or `partial` per ledger; empty is not “learned taste.” |
| Generic starter brief (allowed so first package can generate) | Label as starter / prefill in UI and in stored provenance. Not a selected taste example. Not a learned pillar. |
| `VoicePrefill.positioning` / canned `voiceRules` / captionStyle | **Prefill only.** Existing `voicePrefilled` flag is the honesty bit. You voice subtitle must **not** read “Saved” for canned prefill. Do not set `voicePrefilled` and then treat the row as creator-authored voice. |
| HYROX / gym-lifestyle-eating-recovery fixture | Forbidden on first-run and skip. Allowed only in DEBUG fixture UI. |
| Bootstrap established TestFlight profile | **Preserve.** Backfill already marks real positioning/pillars as `established`. Launch-A must not rewrite those rows. |
| Taste example ids never chosen | Do not invent pack ids. |

If You needs a status line for skipped first-run: “Not set” / “Finish in You,” never “Saved” for empty or canned fields.

Logging: interest ids, format ids, onboarding_state, scheduled_date, error codes allowed. Forbidden: `creator_note`, context answer text, raw positioning dumps.

---

## 7. Paper (constraint; this task does not edit Paper)

Paper file (handoff Step 3): `ContentHelper — Launch screens and states — 2026-09-07`.

| Layer | What to show | Label |
|---|---|---|
| **Current-state evidence** | The **five-step** journey as it exists in the candidate (`OnboardingFlowView` steps 0–4, progress “Step N of 5”, Review → Preparing your first idea). | Current. Not the launch target. |
| **Proposed launch target** | The **one skippable choice screen**, skip/Back recoverable states, You destinations for deferred prefs, first useful package on Today. | Proposed. Do not draw it as already shipping. |

Do not replace current-state artboards with the proposal. Do not hide five-step evidence because Launch-A deferred it. Debug-only / unreachable routes stay marked debug.

---

## 8. Invariants carried forward

- Shell stays Today / Plan / You. Archive stays under You.
- Account/workspace-scoped profile is source of truth (`WorkspaceContext` + `creator_profiles` RLS).
- Additive schema only. No hosted migration/deploy in this contract.
- One package per creator/day. Retries, relaunches, and repeated taps do not duplicate work or erase a ready package.
- Switching Apple users on one device must not leak the previous profile cache.
- No mandatory Instagram OAuth, voice recorder, paywall, or guest-auth for this launch.

---

## 9. Implementation order (later)

1. Step 2 change ledger accepts CH-02 citing this file + `dec-20260907-002`.
2. Apply the reduced first-use in existing onboarding types and existing You editors.
3. Preserve legacy `OnboardingStep` decoding so partial five-step progress does not crash; map it into recoverable Launch-A / You resume rather than forcing remaining stages.
4. Verification: first-run skip, first-run one choice, returning `partial`, established untouched, retry no duplicate, Back/cancel recoverable, provenance honest, Today land, no HYROX leak.

Until the ledger is accepted, CH-02 stays recorded, not coded.
