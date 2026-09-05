# Adaptive creator onboarding — shared contracts

Status: orchestrator contracts pass. Implementers follow this file.
Do not implement the five polished screens or live generation handoff until workstream 2 lands persistence types.

Development agents only. Do **not** replace Gemini/DeepSeek generation with Grok or Composer.

Canonical live types (evolve these; do not add a second profile system):

- `CreatorProfileSummary` / `CreatorProfileUpdate` / `CreatorProfileRepository` in `CreatorContentOS/Data/AppRepositories.swift`
- `SupabaseCreatorProfileRow` in `CreatorContentOS/Data/SupabaseDTOs.swift`
- `OnboardingStep` / `OnboardingProgress` / `OnboardingCompletedData` in `CreatorContentOS/Features/Onboarding/OnboardingModels.swift`
- `OnboardingStoring` in `CreatorContentOS/Features/Onboarding/OnboardingStore.swift`
- `public.creator_profiles` in `supabase/migrations/20260605000000_initial_content_os_schema.sql`

`CreatorContentOS/Models/ContentQualityLearningLoop.swift` `CreatorProfile` is **not** the live persistence contract. Do not wire onboarding to it.

---

## A. Architecture decisions

1. **Evolve the existing 3-step onboarding.** Keep `OnboardingFlowView` / `OnboardingViewModel` / `OnboardingStore`. Expand steps. Do not add a parallel flow or a device-only done flag as source of truth.
2. **Account/workspace-scoped profile is source of truth.** `creator_profiles` (RLS already on) plus `WorkspaceContext`. Local UserDefaults may cache progress keyed by `workspaceID` + `creatorID` only.
3. **Auto-provisioned empty profile ≠ completed onboarding.** First Apple sign-in creates workspace + creator + member today, but **no** `creator_profiles` row. Live read then falls back to `CreatorProfileSummary.creatorFixture` (HYROX). That fallback is forbidden after this work.
4. **Gating after Sign in with Apple:** `authenticationPhase == .live` then load profile record. Present onboarding only for `new` or `partial`. Skip for `established`. On `loadFailed`, show Creator shell with retry; do not wipe an established profile.
5. **First idea skips Plan.** Confirm saves the profile, synthesizes a day brief from the confirmed record, calls existing `AppServices.generateDayCard` + `makeDayAvailable`, lands **Today** for the device-local date, Shoot Folio from Today. Plan tab stays in the shell. Do not open Plan. Do not require a handwritten brief. Do not publish to Instagram.
6. **Idempotent handoff.** Same creator + local today must not overwrite ready / edited / shot / posted / decision cards. Retry after generation failure keeps the saved profile.
7. **Generation stack stays.** `generate-week` `action=generate_day` remains the provider path. Prompt assembly must stop injecting the seed HYROX identity when the saved profile does not contain it.
8. **Additive schema only.** New columns on `creator_profiles`. Do not apply migrations to production or deploy Edge Functions in this program of work until a human says so.
9. **Preserve the live shell:** Today / Plan / You (`CreatorShellView`). Archive stays under You. Mockup extra tabs (Ideas, References, marketing stats) are out of scope.
10. **Instagram is optional later, not step 2.** Keep `OnboardingReference*` types for You / Intelligence import. The 5-step journey must complete without a reel, handle, or OAuth.

---

## B. State machine

Client presentation state (`CreatorOnboardingPresentation`):

| State | Meaning | UI |
| --- | --- | --- |
| `new` | Signed-in creator, no completed adaptive onboarding. Includes missing profile row after ensure-profile, and auto-provisioned empty active profile. | Full 5-step flow |
| `partial` | Progress saved, not confirmed. | Resume at saved step |
| `established` | Confirmed onboarding **or** legacy real profile (see migration policy). | Creator shell. No forced rewrite |
| `loadFailed` | Auth live, profile read failed. | Shell + retry. Do not treat as `new` if a previous `established` snapshot exists for this workspace |

`loadFailed` is client-only. Database `onboarding_state` is `new | partial | established`.

Do **not** use `UserDefaults` key `ch-onboarding-done` as the live gate. `OnboardingPresentationPolicy.shouldPresent` must read the workspace profile record (plus in-memory session dismiss). Soft skip may hide the flow for the current process only; next launch re-presents until `established`.

### Step enum (evolve `OnboardingStep`)

```
interests = 0          // was categories
tasteExamples = 1      // was references
productionConstraints = 2
interestContext = 3
review = 4             // was confirm
```

Keep `Codable` raw `Int`. Decode unknown/legacy `references` raw value `1` as `tasteExamples` only after UI ships the new step 2. Until UI lands, workstream 2 must not break the 3-case switch: add new stored fields on progress/profile first; change `OnboardingStep` cases in the same PR as `OnboardingFlowView` switch updates (workstream 1), **after** persistence types exist.

Recommended sequence: workstream 2 lands record + repository without renaming `OnboardingStep`; workstream 1 renames/expands the enum and screens together.

### Session record (evolve `OnboardingProgress` / `OnboardingCompletedData`)

```
OnboardingRecord
  step: OnboardingStep
  interestIDs: [String]                 // catalog ids, order preserved
  customSubjects: [String]              // first-class; not a single Other slot
  startingPoint: justStarting | alreadyPosting | nil
  selectedTasteExampleIDs: [String]     // local pack ids
  formats: [talkingToCamera | voiceoverBroll | textLed | photoCarousel]
  timeToCreate: fiveToTen | tenToThirty | thirtyPlus | nil
  contentLanguage: String               // maps to language_preferences.primary
  showFace: Bool?
  useVoice: Bool?
  contextAnswers: [questionID: String]  // max two questions
  creatorNote: String?                  // optional; never log
  voiceDeferred: Bool                   // keep for You voice editor compatibility
```

Validation (step Continue):

1. Interests: ≥1 interest id **or** ≥1 custom subject; **starting point** (`just_starting` or `already_posting`) required. Custom subjects trim; reject blank. No max-3 hard cap; cap at 8 total (ids + customs).
2. Taste: ≥1 selected example from the current pack **or** user tapped refresh at least once and then selected. Allow refresh without a model call.
3. Production: ≥1 format, time bucket set, language non-blank (default `English`), face and voice each explicit yes/no.
4. Context: the 0–2 prompted questions may be skipped only if optional; if a prompted question is marked required by catalog, require non-blank. Creator note always optional.
5. Review: all of 1–3 valid. Confirm is the only transition to `established`.

---

## C. Field mapping into generation

On confirm, map `OnboardingRecord` → `CreatorProfileUpdate` **plus** new columns (see migration). Then synthesize `dayBrief` for `generateDayCard`.

| Onboarding field | Persistence | Generation read |
| --- | --- | --- |
| interest labels + custom subjects | `content_pillars` (string array, labels not gym/lifestyle/eating/recovery unless the creator chose those words) | `creator_profile.content_pillars`; day brief topic list |
| starting point | `starting_point` text | day brief: beginner vs already-posting constraint |
| taste example ids + titles | `taste_example_ids` jsonb | day brief style lines; **not** a live model call |
| formats | `production_formats` jsonb **and** `recurring_formats` (human labels) | prefer matching format in card; shootability |
| time to create | `time_to_create` text | `estimated_shoot_minutes` target (8 / 20 / 40) |
| content language | existing `language_preferences.primary` | caption/script language |
| showFace / useVoice | `on_camera_restrictions` jsonb `{show_face, use_voice}` | never_say / shooting constraints; no-face / no-VO variants |
| context answers | `recent_context` jsonb `{question_id, interest_id, answer}` | day brief personal facts |
| creator note | `creator_note` text | day brief extra; **never** in client_context logs or Edge logs |
| derived positioning | `positioning` | must be synthesized from the record; must **not** copy HYROX fixture text |
| derived voice rules | `voice_rules` | short rules from formats + starting point + taste (honest, specific, no hype). Enough that `voiceIsConfigured` becomes true so `canGenerateContent` is true without `voiceDeferred` UserDefaults |

`CreatorProfileUpdate` today encodes only positioning, voice_rules, content_pillars, caption_style, never_say, recurring_formats. Workstream 2 extends the Swift update + `write-content` + `read-content` + `SupabaseCreatorProfileRow` for the new columns. Existing You voice/categories editors must keep working: they send the old fields; new columns stay unchanged on those saves.

### First-idea day brief (client-synthesized, no Plan picker, no extra LLM)

Workstream 2 owns `OnboardingFirstIdeaBriefBuilder`. Pure function. Input: confirmed `OnboardingRecord`. Output: non-empty `dayBrief` string for `generateDayCard`. Include interests, starting point, selected example titles, formats, time, language, face/voice limits, context answers, optional note. Do not include Instagram URLs. Do not include HYROX/fitness unless those interests were selected.

### generate_day identity rules (workstream 2)

In `supabase/functions/generate-week/generation.ts`:

- `buildPromptMessages` / `buildGenerationGuidance.creator_positioning` currently hardcode the Indian mother / HYROX / gym-lifestyle-eating-recovery identity.
- For `action=generate_day` (and regenerate of that day), **use the loaded `creator_profile` row**. If positioning/pillars exist, they win. If they do not mention HYROX, do not mention HYROX.
- Do not use `CreatorProfileSummary.creatorFixture` or bootstrap seed copy as a missing-profile fallback.
- `CONTENT_PILLARS` gym/lifestyle/eating/recovery remains valid for the bootstrap TestFlight creator. For generate_day, accept any non-blank pillar string that matches a saved content_pillar **or** one of the four legacy values. Do not coerce Books → gym.

Existing provider keys, models, and Edge function names stay.

### Voice gate

Completing step 5 must make `AppServices.voiceIsConfigured == true` via saved positioning + voice_rules. Do not rely on `UserDefaults` `voiceDeferred` for the first-idea path. You voice editor can still clear/replace those fields later.

---

## D. Migration policy

New file only, e.g. `supabase/migrations/20260905120000_adaptive_creator_onboarding.sql`.

Additive columns on `public.creator_profiles` (names exact):

```
onboarding_state text not null default 'new'
  check (onboarding_state in ('new', 'partial', 'established'))
onboarding_step integer
onboarding_version integer not null default 1
onboarding_completed_at timestamptz
starting_point text
  check (starting_point is null or starting_point in ('just_starting', 'already_posting'))
custom_subjects jsonb not null default '[]'::jsonb
taste_example_ids jsonb not null default '[]'::jsonb
production_formats jsonb not null default '[]'::jsonb
time_to_create text
  check (time_to_create is null or time_to_create in ('five_to_ten', 'ten_to_thirty', 'thirty_plus'))
on_camera_restrictions jsonb not null default '{}'::jsonb
recent_context jsonb not null default '[]'::jsonb
creator_note text
first_idea_handoff jsonb not null default '{}'::jsonb
```

Backfill:

```
UPDATE creator_profiles
SET onboarding_state = 'established',
    onboarding_completed_at = COALESCE(onboarding_completed_at, updated_at)
WHERE status = 'active'
  AND onboarding_state = 'new'
  AND (
    length(trim(coalesce(positioning, ''))) > 0
    OR jsonb_array_length(coalesce(content_pillars, '[]'::jsonb)) > 0
  );
```

This marks the bootstrap HYROX seed and any You-edited profile as established. Empty auto-provisioned rows stay `new`.

Do not change existing positioning/voice/pillars of established rows during backfill.

`language_preferences` already exists; do not duplicate.

`write-content` `update_creator_profile` today returns **404** if no active row. Change to **upsert**: if none, insert `status=active`, `version=1`, `onboarding_state=new` (or `partial`/`established` when the payload says so), workspace-scoped. Never insert HYROX defaults.

`exchange-auth-session` auto-provision: after creator+member insert, insert an empty active profile (`onboarding_state=new`, empty pillars, null positioning). Do not copy `20260606043000_live_bootstrap_seed.sql`.

`SupabaseCreatorProfileRepository.activeProfileSummary`: if profile is null, return an empty summary (displayName from session, empty positioning/rules/pillars). **Never** `.creatorFixture`.

Fixture repository used by DEBUG fixture UI may keep `.creatorFixture` for the sample athlete **only** when `isLiveSupabaseRuntime == false`. Live and first-run tests must not.

---

## E. Idempotency — first idea

`AppServices.confirmOnboardingAndPrepareFirstIdea(record:scheduledDate:)` (name exact). Owned by workstream 2. Thin method on existing `AppServices`; heavy logic in `OnboardingFirstIdeaHandoff` helper in Data/. Do not add a new catch-all service type.

Sequence:

1. Persist confirmed profile (`established`, `onboarding_completed_at=now()`, progress cleared). If persist fails: stay on review, keep `partial`, do not mark complete.
2. Build day brief. Persist `first_idea_handoff` `{ scheduled_date, status: "preparing", brief_fingerprint }` without logging `creator_note` or context answer text. Fingerprint = hash of brief.
3. Inspect today's card (session `dayBriefGeneratedCards` / `weekCards` / `todayCard`):
   - status in `DayPackageLifecycleStatus.readyOrDecision` → status `skipped_existing_ready`, navigate Today, do not generate.
   - card exists and looks user-edited (title/script/caption differ from last generated draft if known) → same skip.
   - `AcceptedDayGenerationStore` has an in-flight run for that date → resume poll, then `makeDayAvailable` if still draft.
   - else `generateDayCard(scheduledDate:dayBrief:confirmOverwrite: false)`.
4. On generate success: `makeDayAvailable(scheduledDate:)`. If date is local today, Today refresh already happens inside `makeDayAvailable`. Navigate `pendingCreatorTab = .today`. Do **not** set `.plan`. Do **not** set `pendingFirstDayHandoff` that opens Plan idea launcher.
5. On generate or make-available failure: profile remains `established`. `first_idea_handoff.status = "failed"`. UI offers Retry (same method). Retry may replace a **draft** from a failed first-idea attempt; still must not unpublish ready/decision cards (`confirmOverwrite` stays false unless status is draft-like).
6. Preparing a recommendation is not Instagram publish. `makeDayAvailable` only promotes the daily card to the ready package.

Replace `OnboardingFirstDayHandoff.dayBrief == nil → Plan`. Keep the struct until UI is updated, then stop calling `handoffFirstDayFromOnboarding` for this path.

---

## F. Account isolation

- All reads/writes go through `WorkspaceContext` (workspace_id, creator_id, member_id) as today.
- Local cache keys: `ch-onboarding.{workspaceID}.{creatorID}.progress` (optional). Remove global `ch-onboarding-done` as gate. Sign-out (`AppState.finishLocalSignOut`) must drop in-memory onboarding UI state. Next account must load **its** profile, not the previous UserDefaults blob.
- RLS stays enabled; Edge Functions keep service-role + device session checks. Do not weaken policies.
- Switching Apple users on one device: different `auth_user_id` → different workspace from auto-provision → different profile. Do not share `OnboardingStore.standard`.

---

## G. Logging

Allowed: interest ids, format ids, time bucket, language code, face/voice booleans, taste example ids, onboarding_state, scheduled_date, daily_card_id, error codes.

Forbidden: `creator_note`, `recent_context` answer text, raw profile positioning dumps in client_context. `SupabaseGenerationClientContext` stays non-sensitive.

---

## H. Catalogs (local, no model on Next)

Workstream 1 owns catalog files. Workstream 2 persists selected ids/labels only.

Interest catalog (replace `OnboardingCategories.starter` / keep You `ContentCategoryOption.catalog` in sync via one shared catalog type owned by WS1 after WS2 lands pillars as free strings):

- lifestyle, fitness-wellness, books, movies-tv, fashion-beauty, food-cooking, travel, business-career, gaming, art-creativity, parenting
- Custom subjects: tag-style add, first-class, stored in `custom_subjects` and appended to `content_pillars` labels

Taste packs: `OnboardingExamplePacks.swift`. ≥3 examples per interest; refresh shuffles local remaining items. Selection stores example `id` + title snapshot in progress.

Context questions: `OnboardingContextQuestions.swift`. Filter by selected interest ids; show at most two; plus optional note.

Formats / time / language / face-voice: enums in `OnboardingModels.swift`.

---

## I. File ownership

Until a workstream's files have landed on the branch, **no other workstream edits them**.

### Workstream 2 — persistence + first-idea integration (goes first)

Owns until landed:

- `docs/adaptive-creator-onboarding-contracts.md` (may patch if schema names slip; do not reopen product scope)
- `supabase/migrations/20260905120000_adaptive_creator_onboarding.sql` (timestamp may bump; additive only)
- `supabase/functions/write-content/index.ts` (+ `acceptance.ts` / tests for upsert)
- `supabase/functions/read-content/index.ts` (return new columns)
- `supabase/functions/exchange-auth-session/index.ts` (+ tests: empty profile insert)
- `supabase/functions/generate-week/generation.ts` (generate_day identity; no HYROX default)
- `supabase/functions/generate-week/generation-validation.ts` (generate_day pillar allow-list)
- `supabase/functions/generate-week/generation_test.ts` / related generate_day tests that assert profile-driven identity
- `CreatorContentOS/Data/AppRepositories.swift` (`CreatorProfileSummary`, `CreatorProfileUpdate`, repository protocol if extra methods needed)
- `CreatorContentOS/Data/SupabaseDTOs.swift` (`SupabaseCreatorProfileRow`)
- `CreatorContentOS/Data/WriteContentDTOs.swift`
- `CreatorContentOS/Data/DeviceReadDTOs.swift` if profile read shape changes
- `CreatorContentOS/Data/SupabaseRepositories.swift` (`SupabaseCreatorProfileRepository` empty fallback)
- `CreatorContentOS/Fixtures/FixtureRepositories.swift` only the profile repository empty vs fixture split
- `CreatorContentOS/App/AppServices.swift` (`confirmOnboardingAndPrepareFirstIdea`, `voiceDeferred`/`gating` read from profile, **no** new catch-all type)
- `CreatorContentOS/App/AppState.swift` (stop Plan-first handoff; Today tab; sign-out must not leak onboarding)
- `CreatorContentOS/App/CreatorContentOSApp.swift` (gating uses profile state, not global UserDefaults)
- `CreatorContentOS/Features/Onboarding/OnboardingStore.swift` (workspace-scoped cache; not the live gate)
- New helper files under `CreatorContentOS/Data/`:
  - `OnboardingFirstIdeaBriefBuilder.swift`
  - `OnboardingFirstIdeaHandoff.swift`
  - `CreatorOnboardingState.swift` (presentation enum + mapping from profile)
- Tests: `CreatorContentOSTests/AdaptiveOnboardingPersistenceTests.swift`, `CreatorContentOSTests/FirstIdeaHandoffTests.swift`, `CreatorContentOSTests/SupabaseWriteContentDTOTests.swift` (extend), `supabase/functions/write-content` tests, `exchange-auth-session` tests, generate_day identity tests

Must not edit: `OnboardingFlowView.swift`, example pack catalogs, PocketSheet chrome, Today/Shoot Folio layout, `project.yml` unless a new Swift file is missing from the folder (folder is already included).

### Workstream 1 — onboarding UI (after WS2 types compile)

Owns:

- `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift`
- `CreatorContentOS/Features/Onboarding/OnboardingViewModel.swift`
- `CreatorContentOS/Features/Onboarding/OnboardingModels.swift` (step enum + catalogs + validation)
- New: `OnboardingExamplePacks.swift`, `OnboardingContextQuestions.swift`, step subviews if split **in the Onboarding folder**
- `CreatorContentOS/Features/You/YouContentCategoriesView.swift` / `ContentCategorySelection.swift` only to stay consistent with the shared interest catalog
- `CreatorContentOSTests/OnboardingTests.swift` for step validation and presentation (preserve existing reference-parser tests)

Must not edit: Data/, supabase/functions, migrations, AppServices first-idea method body, generate-week.

Preserve uncommitted reference-field unification (single draft, auto-add) already in the working tree if still present. Instagram refs are **not** a required step; parser may remain for You.

### Workstream 3 — tests and verification (after WS2, overlapping WS1 only on test files WS1 does not touch)

Owns:

- Running `CreatorContentOS` scheme tests and `deno task ci:backend`
- New: `CreatorContentOSTests/AdaptiveOnboardingVerificationTests.swift` (gating matrix, account isolation, idempotency, no HYROX leak, Today land)
- Extending `VoiceGateTests.swift`, `CreatorShellNavigationTests.swift`, `DayLifecycleTests.swift`, `GenerationContractsTests.swift` **after** WS2 lands APIs
- Test plans / fixture flags: `MCO_RESET_ONBOARDING` must reset workspace-scoped cache, not only global keys

Must not concurrently edit WS2 DTO/migration files or WS1 view files. If a test requires a hook, add it in the verification test file or ask WS2 for a test seam.

### Shared freeze

`project.yml` — do not add targets. New Swift under `CreatorContentOS/` is auto-included.

Do not edit: Instagram OAuth, trend platform, scraping, cron, auto-publish, analytics dashboard, nav redesign, voice recorder, paywall, PlanHub layout except removing first-run auto-Plan if WS2/AppState already stopped the handoff.

---

## J. Out of scope

- Instagram OAuth / required reel+profile step
- Replacing generation providers with Grok or Composer
- New app shell or tab bar (Today / Ideas / References / Profile mockup)
- Second `CreatorProfile` model (`ContentQualityLearningLoop`)
- Device-only `ch-onboarding-done` as source of truth
- New catch-all `AppServices` type
- Applying migrations to production / deploying functions
- Plan as first-run destination
- Handwritten daily brief
- Publishing to Instagram from onboarding
- Overwriting established HYROX/TestFlight profiles
- Voice recorder, paywall, analytics, trend scraping, cron rebuilds

---

## K. Gap list vs current onboarding

| Current | Required |
| --- | --- |
| 3 steps: categories, Instagram refs, confirm | 5 steps: interests+starting point+custom, local taste examples, formats/time/language/face-voice, ≤2 context questions + note, review |
| Gate = UserDefaults `ch-onboarding-done` (device-global) | Gate = workspace `onboarding_state` |
| Soft skip session + resume progress in UserDefaults | Soft skip session-only; progress mirrored to profile `partial` |
| Categories max 3; Other is one text field; Fitness-first catalog | Mockup interests; custom subjects first-class |
| Step 2 requires reel URL + profile handle + Instagram verify | No Instagram required; local example packs |
| Confirm copies category labels onto existing profile (async, ignore failure) then Plan idea launcher | Confirm must succeed persist; auto first idea; Today |
| `finishAndGenerateFirstDay` marks local complete **before** profile save | Persist first; complete only after save |
| `write-content` 404 without profile row | Upsert empty/active profile |
| Auto-provision has no profile row; live read → HYROX fixture | Auto-provision empty `new` profile; empty fallback |
| `generate_day` system prompt hardcodes HYROX identity; pillars gym/lifestyle/eating/recovery | Profile-driven; pillars = creator interests |
| Handoff `pendingCreatorTab = .plan`, `dayBrief = nil` | `pendingCreatorTab = .today`, synthesized brief, `makeDayAvailable` |
| Voice gate uses UserDefaults `voiceDeferred` | Saved positioning + voice_rules from onboarding |
| You categories / voice still the editor for pillars/voice | Keep; map new fields; do not force established users through onboarding |
| Shell Today / Plan / You | Keep |

Uncommitted local work (preserve; not this contracts pass): unified onboarding reference draft + parser tests in `OnboardingFlowView.swift`, `OnboardingViewModel.swift`, `OnboardingReferenceParsing.swift`, `OnboardingTests.swift`.

---

## L. Debug / tests

- `MCO_RESET_ONBOARDING=1` still allowed in DEBUG launch; must clear workspace-scoped cache **and** not delete an established live profile unless a dedicated debug action says so. Prefer resetting local presentation so the flow shows, without UPDATE of production rows.
- `MCO_FORCE_ONBOARDING=1` (DEBUG only): present the full five-step flow even when the loaded profile is `established` (including fixture HYROX). Does **not** wipe or empty the profile Today card. Soft skip still hides the flow for the current process; completing still calls `confirmOnboardingAndPrepareFirstIdea`. Combine with `MCO_FORCE_FIXTURE_UI=1` for simulator QA screenshots.
- `MCO_FORCE_EMPTY_TODAY=1` (DEBUG only): with fixture UI, start Today empty (no scenes, no seeded draft) so confirm runs `generateDayCard` + `makeDayAvailable`. Combine with `MCO_FORCE_ONBOARDING=1` to prove books/movies first idea without overwriting the HYROX card when the flag is off.
- `MCO_SLOW_FIRST_IDEA=1` (DEBUG only): slow fixture first-idea generation (~3.5s) for screenshot capture. Default off.
- `MCO_FAIL_FIRST_IDEA=1` (DEBUG only): fail fixture first-idea generation with recoverable human copy on Review. Default off.
- Fixture UI (`MCO_FORCE_FIXTURE_UI`) may show onboarding with in-memory store.
- Hermetic: `deno task ci:backend`. iOS: scheme `CreatorContentOS` / target `CreatorContentOSTests`.
- Do not log personal notes in tests' print/debug either.

---

## M. Implementer invocation order

1. `/onboarding-persistence` — types, migration, upsert, gating, generate_day identity, first-idea handoff, unit tests.
2. `/onboarding-ui` — five screens bound to landed types.
3. `/onboarding-verification` — run suites, gap tests, no HYROX leak, Today + Shoot Folio path.

Parent orchestrator stays on Grok 4.6. These three agents are Composer 2.5 Fast development agents only.

---

## N. Remaining limitations / QA evidence

- **Live first-idea generate (Edge `generate_day`):** **Completed locally.** Books/movies `creator_profiles` row seeded; `generate-week` `action=generate_day` at `http://127.0.0.1:54321/functions/v1/generate-week` returned a real card (title snippet: "My Saturday evening wind-down order: book first, movie second"; books/movies in copy; no HYROX). Evidence: `artifacts/adaptive-onboarding-qa/live-generate-day-evidence.json`. Functions served with `/tmp/mco-functions-live-local.env` (not committed). Smoke used `MCO_DEEPSEEK_MODEL=deepseek-chat` on the deno process (`deepseek-v4-flash` fails JSON locally). Latest rerun: sync `200` / `draft` in ~55s. Linked remote project `zogvvrxhiwozjmufvddu` is production; do not apply migration or run onboarding smoke there without human approval.
- **Human rerun (local, after valid provider secrets):**

  ```bash
  colima start --cpu 4 --memory 8 --disk 60
  cd /path/to/contenthelper
  supabase start -x vector
  supabase db push --local --include-all --yes
  printf 'DEEPSEEK_API_KEY=<your-key>\nMCO_AI_PROVIDER_ORDER=deepseek,openai\nMCO_DEEPSEEK_MODEL=deepseek-chat\n' > /tmp/mco-functions-live-local.env
  supabase functions serve --no-verify-jwt --env-file /tmp/mco-functions-live-local.env
  # new terminal:
  eval "$(supabase status -o env)"
  export FUNCTIONS_URL="${API_URL}/functions/v1"
  deno run --allow-env --allow-net --allow-read scripts/onboarding-books-movies-live-smoke.ts \
    | tee artifacts/adaptive-onboarding-qa/live-generate-day-evidence.json
  ```

  Expect `generate_status: 200`, `content_pillar` in `books` / `movies-tv`, and no HYROX in title/script/caption. Hermetic prompt proof already passes: `deno test supabase/functions/generate-week/generation_test.ts --filter "books profile"`.
- **Fixture confirm idempotency:** With `MCO_FORCE_FIXTURE_UI=1` alone, confirming onboarding skips generating a new books/movies card when Today already has the HYROX ready package (by design; see idempotency rules in section E). Use **`MCO_FORCE_EMPTY_TODAY=1`** with fixture UI + force onboarding to prove personalized first idea without clobbering the HYROX card.
- **Preparing UI:** The "Preparing your first idea…" state on review is too brief to capture reliably. Use **`MCO_SLOW_FIRST_IDEA=1`** (DEBUG only) with empty Today to slow fixture generation for screenshots. Default off.
- **Generation failure QA:** Use **`MCO_FAIL_FIRST_IDEA=1`** (DEBUG only) with empty Today to show Review retry with human copy (no raw error codes).
- **Shoot Folio:** In this shell, Shoot Folio opens inline on Today (storyboard expand), not as a separate tab.
- **Migration gate:** `supabase/migrations/20260905120000_adaptive_creator_onboarding.sql` must not be applied to production without human approval.
- **QA launch (DEBUG) — empty Today first idea:**

  ```bash
  MCO_SIMULATOR_UDID=FAE1FD16-D185-433C-AC85-544FF45F2C82 \
  MCO_FORCE_FIXTURE_UI=1 \
  MCO_FORCE_ONBOARDING=1 \
  MCO_FORCE_EMPTY_TODAY=1 \
  scripts/fast-sim-refresh.sh
  ```

  Optional capture helpers (combine with the above):

  ```bash
  MCO_SLOW_FIRST_IDEA=1    # slow "Preparing your first idea…" for screenshots
  MCO_FAIL_FIRST_IDEA=1    # Review retry with human copy (not for happy path)
  ```

  Screenshot evidence lives in `artifacts/adaptive-onboarding-qa/`.

- **QA launch (DEBUG) — idempotency over HYROX (no new card):**

  ```bash
  MCO_SIMULATOR_UDID=FAE1FD16-D185-433C-AC85-544FF45F2C82 \
  MCO_FORCE_FIXTURE_UI=1 \
  MCO_FORCE_ONBOARDING=1 \
  scripts/fast-sim-refresh.sh
  ```
