# ContentHelper AI & privacy data inventory (CH-06)

**Type:** read-only inventory — proposal input for `privacy-account-contracts.md`\
**Prepared:** 7 September 2026 IST\
**Candidate SHA:** `20766cd90fd6338592d8fb7792395f566eda1205`\
**Native root:** `CreatorContentOS/`

This document lists **actual** client storage APIs, outbound AI paths, and personal fields observed in source. It does **not** approve App Privacy manifest reason codes — **Release archive + dependency `.xcprivacy` inspection is still required** before declaring `NSPrivacyAccessedAPIType` entries.

---

## 1. In-app privacy policy link

| Check | Result |
| --- | --- |
| Swift grep: `privacy`, `Privacy Policy`, `privacyPolicy` under `CreatorContentOS/` | **No matches** |
| Product-owned privacy URL in app | **None** (expected) |
| Other `openURL` usage | Intelligence reference links only (`IntelligenceHomeView.swift:14, 202, 417, 860`) — not a privacy policy |

**Contract implication:** CH-06 must add a new You → Account link. Do not reuse PipCount policy text or URL as ContentHelper’s policy.

---

## 2. Required-reason API candidates (client)

### 2.1 UserDefaults (`NSPrivacyAccessedAPICategoryUserDefaults`)

**Manifest status:** **Do not declare until archive inspection.** Map to an approved reason (e.g. CA92.1 only if inspection + legal review confirm fit).

| Key pattern | Purpose | File:line |
| --- | --- | --- |
| `ch-onboarding.{workspaceUUID}.{creatorUUID}.progress` | Scoped onboarding progress JSON | `OnboardingStore.swift:36-37, 45-62` |
| `ch-onboarding.{workspaceUUID}.{creatorUUID}.data` | Scoped onboarding completed data | `OnboardingStore.swift:69-86` |
| `ch-onboarding-progress` | Legacy global onboarding progress (DEBUG reset + legacy store) | `OnboardingStore.swift:138, 152-169, 212-214` |
| `ch-onboarding-done` | Legacy global completion flag | `OnboardingStore.swift:139, 147-148, 198, 214` |
| `ch-onboarding-data` | Legacy global completed data | `OnboardingStore.swift:140, 176-193, 205, 215` |
| `ch-accepted-day-generations` | Accepted async `generate_day` runs for poll-resume | `AcceptedDayGenerationStore.swift:23, 29-55` |
| `ch-plan-selected-date` | Plan calendar selection `yyyy-MM-dd` | `PlanSelectedDateStore.swift:14, 20-33` |
| `ch-ai-consent.{workspace}.{creator}` | **Proposed** — CH-06 consent version | `privacy-account-contracts.md` |

**Injection sites (defaults = `.standard`):**

| File:line | Usage |
| --- | --- |
| `OnboardingStore.swift:29, 143` | `UserDefaults = .standard` |
| `AcceptedDayGenerationStore.swift:25` | `UserDefaults = .standard` |
| `PlanSelectedDateStore.swift:16` | `UserDefaults = .standard` |
| `CreatorContentOSApp.swift:45, 146` | Legacy store / DEBUG reset |
| `YouAccountView.swift:238` | DEBUG onboarding reset |
| `YouCreatorVoiceView.swift:205, 232, 236` | Legacy completed data read/write |
| `AppServices.swift:195, 246, 275` | Accepted generation store default |

**Live scoped store:** `WorkspaceScopedOnboardingStore` used at runtime (`CreatorContentOSApp.swift:68-72`).

### 2.2 FileManager / file timestamps (`NSPrivacyAccessedAPICategoryFileTimestamp` — candidate)

**Manifest status:** **Do not declare until archive inspection** confirms the linked API is reported and a reason code is approved.

| Path / usage | Purpose | File:line |
| --- | --- | --- |
| `Application Support/.../TodayCache/today-{workspace}-{creator}.json` | Today + week card cache | `TodayCacheStore.swift:23-77` |
| `Application Support/.../Logs/generation.log` | Generation telemetry append | `GenerationLogFile.swift:8-38` |
| `Application Support/...` (benchmark) | DEBUG benchmark output | `BenchmarkBackgroundTask.swift:20, 36, 44` |

File existence checks and directory creation only — no explicit `resourceValues(forKeys: .creationDateKey)` in app source grep; still verify archive for indirect API use via Foundation.

### 2.3 Keychain (not a Privacy Manifest “required reason API” category; disclose in policy)

| Item | File:line |
| --- | --- |
| Paired device session blob | `RuntimeConfigurationStore.swift:116-143, 170-205` |
| `SecItemCopyMatching` / `SecItemAdd` / `SecItemUpdate` / `SecItemDelete` | `RuntimeConfigurationStore.swift:170-205` |

Stores: project URL, publishable key, workspace/creator/member ids, device token, display name, email.

### 2.4 UIPasteboard (user-initiated copy — not an automatic outbound AI path)

| Surface | File:line |
| --- | --- |
| Shoot Folio script copy | `ShootFolioView.swift:575, 657` |
| Not Today sheet | `NotTodaySheet.swift:243` |
| DEBUG benchmark summary | `DayGenerationBenchmarkView.swift:126` |

Disclose in privacy policy as on-device clipboard write on explicit user action.

### 2.5 Not observed in app source (grep negative)

| API | Notes |
| --- | --- |
| Core Location | No `CLLocation` usage |
| Photo Library | No `PHPhotoLibrary` |
| Camera / mic capture | No `AVCapture` in grep set |
| App Tracking / IDFA | No `ATTrackingManager` / advertising identifier |
| iCloud KVS | No `NSUbiquitousKeyValueStore` |

Re-verify in Release archive — dependencies may add APIs.

### 2.6 Dependency privacy manifests (not app-owned)

Observed in build artifacts only, e.g. `swift-crypto_Crypto.bundle/PrivacyInfo.xcprivacy` inside `.xcarchive` / DerivedData. **CH-13 archive step** must merge dependency declarations with app-owned manifest.

**No app-owned `.xcprivacy`** under `CreatorContentOS/` or `project.yml` at candidate SHA.

---

## 3. Outbound AI / provider paths

All paths below require **device session** auth to Supabase Edge Functions unless noted. Backend selects provider from env (DeepSeek / OpenAI / Gemini).

### 3.1 Summary table

| ID | Edge Function | Client entry | Automatic? | Primary providers (backend) |
| --- | --- | --- | --- | --- |
| AI-01 | `generate-week` (`generate_day`, `regenerate_day`) | `SupabaseDayGenerationRepository.generateDay` / `regenerateDay` → `AppServices.generateDayCard` | No — user taps Generate (first idea included) | DeepSeek, OpenAI (`generation.ts`) |
| AI-02 | `generate-plan-ideas` | `SupabasePlanDayIdeaRepository.generatePlanDayIdeas` → `AppServices.fetchPlanDayIdeasWithTimeout` | **Yes** — Plan empty-day load | DeepSeek primary, OpenAI fallback (`plan-ideas.ts:84-104`) |
| AI-03 | `generate-storyboard-thumbnail` | `SupabaseDayGenerationRepository.generateStoryboardThumbnails` → `AppServices.prepareStoryboardThumbnailsForVisibleCard` | **Yes** — `.task` on storyboard panel | Google Gemini image (`gemini-image.ts`, `storyboard-thumbnail-generation.ts`) |
| AI-04 | `generate-week` (full week publish) | `AppServices.publishWeekWithOneTransientRetry` | No — explicit week publish | Same as AI-01 |
| AI-05 | Reference import / review | `import-references`, `review-reference` | No — user-initiated | **No LLM call found** in function source grep |

### 3.2 AI-01 — `generate_day` / `regenerate_day`

**Client invoke:** `SupabaseRepositories.swift:487-541`, `433-484` → Edge Function `generate-week`.

**Trigger surfaces:**

- Plan day Generate (`AppServices.generateDayCard`, `AppServices.swift:887+`)
- Onboarding first idea handoff (via same `generateDayCard` path)
- Regenerate day with guidance

**Request body (client-supplied):**

| Field | Personal? | Source |
| --- | --- | --- |
| `creator_id` | Identifier | Session context — server must re-verify |
| `scheduled_date` | Low | User-selected date |
| `day_brief` / `day_guidance` | **Yes** — user free text | Plan idea or typed brief |
| `client_context` | Metadata only | UI surface, char counts — `SupabaseRepositories.swift:451-458, 501-508` |

**Server-side prompt input (loaded from DB + request):** compacted in `generation.ts:741-827`:

| Category | Fields sent to AI |
| --- | --- |
| Creator profile | `display_name`, `positioning`, `voice_rules`, `caption_style`, `never_say`, `weekly_routine`, `family_race_travel_context`, `language_preferences` |
| Weekly setup | `location`, schedules, `shooting_constraints`, `no_go_topics`, `notes`, travel/energy fields |
| References | `confirmed_references`, `reference_extractions` (truncated) |
| Context | `brand_briefs`, `key_moments`, existing week cards, archive / idea bank (via snapshot) |
| Day target | `scheduled_date`, weekday, `day_guidance` / day brief |

**Destinations:** DeepSeek chat completions or OpenAI Responses API (`generation.ts:2453-2497`).

**Logging (allowed today):** `brief_chars=`, `guidance_chars=` — not brief text (`SupabaseRepositories.swift:442, 494`).

### 3.3 AI-02 — `generate-plan-ideas`

**Client invoke:** `SupabaseRepositories.swift:950-974` → `generate-plan-ideas`.

**Trigger:** `AppServices.loadPlanDayIdeasIfNeeded` (`AppServices.swift:820+`) when Plan shows empty day — **automatic** after profile/setup available.

**Request body** (`SupabasePlanDayIdeasRequest`, `SupabaseRepositories.swift:993-1016`):

| Field | Personal? | Max size (client/server) |
| --- | --- | --- |
| `content_pillars` | Preference | Array |
| `voice_configured` | Boolean | — |
| `reference_count` | Count | — |
| `positioning` | **Yes** | 400 chars (`PlanDayIdeaPayloadLimits`, `PlanDayIdeaBuilder.swift:13`) |
| `voice_rules` | **Yes** | 400 chars |
| `caption_style` | **Yes** | 200 chars |
| `no_go_topics` | **Yes** | 200 chars |
| `reference_labels` | **Yes** — reference titles | 10 × 80 chars |

Built from `PlanDaySetupSummary.from(profile:intelligenceHome:)` (`PlanDayIdeaBuilder.swift:51-80`).

**Destinations:** DeepSeek (primary), OpenAI fallback (`plan-ideas.ts`).

**Fallback without AI:** On timeout/error, on-device `PlanDayIdeaBuilder.buildIdeas` (`AppServices.swift:841-845`) — no outbound call.

### 3.4 AI-03 — `generate-storyboard-thumbnail`

**Client invoke:** `SupabaseRepositories.swift:559-586`.

**Automatic trigger:**

```167:169:CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift
            .task(id: storyboardPreparationTaskID) {
                guard missingThumbnailCount > 0 else { return }
                await services.prepareStoryboardThumbnailsForVisibleCard(dailyCardID: card.id)
```

**Request body:**

| Field | Personal? |
| --- | --- |
| `creator_id`, `daily_card_id` | Identifiers |
| `row_indexes`, `force` | Control |
| `revision_instructions` | **Yes** — if user requested refresh |

**Server loads card** (`generate-storyboard-thumbnail/index.ts:23-35`): `title`, `content_pillar`, `scene_list`, `script`, `on_screen_text`, `post_instructions`, timelines.

**Prompt content** (`storyboard-thumbnail.ts:100-128`): reel title, pillar, hook, per-row visual shot, what to show, **dialogue context** (voiceover/script lines), optional revision text.

**Destination:** Google Gemini image generation (`gemini-image.ts` via `storyboard-thumbnail-generation.ts`).

**Manual path:** Same function via visuals button (`GeneratedDayPlannedContent.swift:187+`) — still requires consent under CH-06 contract.

### 3.5 AI-04 — Full week generation (`publishWeek`)

**Client:** `AppServices.publishWeekWithOneTransientRetry` (`AppServices.swift:1867+`).

Same backend stack as AI-01 with full-week snapshot. User-initiated. Lower priority for launch consent copy but **same consent version** should cover it.

### 3.6 Non-AI outbound (disclose in policy; separate from AI consent)

| Function | Data | File:line |
| --- | --- | --- |
| `exchange-auth-session` | Device name, platform, installation id | `AuthenticationService.swift:187-195` |
| `revoke-device-session` | Installation id | `AuthenticationService.swift:132-139` |
| `write-content` | Profile updates, card edits | `SupabaseRepositories.swift` (write path) |
| `read-content` | Profile, cards, references | Repository refresh |
| `import-references` | Instagram URLs / metadata | `AppServices.previewReferenceImport` |
| Supabase Auth | Apple identity, email | Sign in with Apple |

---

## 4. Personal data fields — cross-path matrix

| Data class | AI-01 day gen | AI-02 plan ideas | AI-03 thumbnails | Stored locally | Sent to Supabase (non-AI) |
| --- | --- | --- | --- | --- | --- |
| Apple email / display name | Indirect via profile snapshot | No | No | Keychain session | Auth / exchange |
| Positioning / voice rules | Yes | Yes | No (indirect via generated script) | Profile + onboarding cache | `creator_profiles` |
| Day brief / guidance | Yes | No (ideas only) | No | Plan idea cache | Generation logs |
| Script / voiceover lines | Yes (generation) | No | Yes (dialogue context in prompt) | Today cache, cards | `daily_cards` |
| Scene / storyboard text | Yes | No | Yes | Today cache | `daily_cards` |
| Reference labels / extractions | Yes | Labels only | No | Intelligence home | `source_references` |
| Notes / weekly setup | Yes | No | No | Profile | `creator_profiles` / weekly setup |
| Device token | No | No | No | Keychain | Edge auth header |

---

## 5. Consent coverage map (CH-06)

| Surface | Must block when consent declined |
| --- | --- |
| Plan → Generate day | AI-01 |
| Onboarding first idea | AI-01 |
| Plan empty-day ideas load | AI-02 |
| Today / Plan storyboard panel appear (missing thumbs) | AI-03 |
| Manual “Visuals” thumbnail refresh | AI-03 |
| Week publish generation | AI-04 |

**Re-consent trigger:** bump `consentVersion` when providers, fields, or policy URL change.

---

## 6. Logging & retention inventory

| Sink | Content today | CH-06 rule |
| --- | --- | --- |
| `GenerationLogFile` | Action, ids, char counts, errors | Never add brief, profile, script, tokens |
| `print("[ContentHelperAuth]")` | Phase transitions only (`AppState.swift:217-220`) | No email in Release |
| `print("[ContentHelperGenerationRepository]")` | Same as log file | Keep |
| Backend Edge logs | Some tests assert no `prompt` in logs (`generate-week/index_test.ts:3333`) | Maintain on deploy |

**Deletion (CH-05):** clear `generation.log` and Today cache file on successful account delete (`privacy-account-contracts.md`).

---

## 7. Archive inspection checklist (before manifest submit)

1. Build Release archive (CH-13).
2. Run `find ContentHelper.app -name '*.xcprivacy'`.
3. Merge app + embedded bundle declarations.
4. For each `NSPrivacyAccessedAPIType` in merged output, trace to app or dependency origin.
5. Assign Apple-approved reason codes — **no guessing CA92.1**.
6. If an API appears only in a dependency, document dependency name + version.
7. Re-run after any SPM update.

---

## 8. Open questions (inventory gaps)

| # | Gap | Owner |
| --- | --- | --- |
| IQ-1 | Full list of profile columns included in `GenerationInputSnapshot` load path | Grok / backend |
| IQ-2 | Whether `import-references` live Instagram probe sends handles to Meta/third parties | Backend review |
| IQ-3 | Exact Gemini model id and data-processing terms for storyboard images | Bobby / ops |
| IQ-4 | Whether Release build links FileTimestamp APIs not visible in Debug source grep | Archive inspect |
| IQ-5 | ASC App Privacy nutrition labels mapping from this inventory | CH-12 owner |

---

*End of AI & privacy data inventory. Read-only source audit. Manifest reason codes require archive inspection — do not declare until complete.*
