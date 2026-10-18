# ContentHelper privacy & account contracts (CH-05 / CH-06)

**Type:** implementation proposal — not shipped code\
**Prepared:** 7 September 2026 IST\
**Candidate SHA:** `20766cd90fd6338592d8fb7792395f566eda1205`\
**Binding product gate:** `dec-20260907-002` (Launch-A) — Apple sign-in stays; launch bar = first useful package\
**Ledger ack:** `change-ledger-accepted.md` — CH-05 / CH-06 accepted; hosted proof **held**

Companion inventory: `ai-data-inventory.md`.

---

## Scope

| ID | In scope (this contract) | Held (do not claim done) |
| --- | --- | --- |
| **CH-05** | In-app deletion UX; session-scoped client delete path; local clear **after** hosted success; isolation on sign-out / delete / switch | Disposable-account **hosted** deletion proof; App Store submit |
| **CH-06** | App-owned privacy manifest; in-app ContentHelper policy link; versioned AI consent (including automatic outbound); logging rules | Hosted policy page write; DNS / live route changes |
| **CH-07** | Record omit-vs-null profile update risk for later fixture only | No handler deploy; no fixture in this task |

---

## CH-05 — In-app account deletion

### Compliance target

Apple App Store Review Guideline **5.1.1(v)** — apps that support account creation must offer account deletion **inside the app**.

Current state: `YouAccountView` exposes sign-out only (`YouAccountView.swift:250-279`). No delete control. Sign-out ≠ deletion.

### UX contract (You → Account)

Add a destructive **Delete account** flow on the existing Account screen. States:

| State | Creator sees | Must not happen |
| --- | --- | --- |
| **Idle** | Delete account control below Sign out | Delete enabled in fixture / unsigned mode |
| **Consequences** | Plain-language list: hosted profile, packages, references, device pairing, local cache; deletion is permanent; Apple sign-in link may remain until Apple revokes | Legal wall of text; PipCount cross-app claims |
| **Confirm** | Typed confirm OR second tap (pick one in Paper CH-04); Cancel returns with no server call | Pre-filled confirm that looks accidental |
| **Pending** | Non-dismissible progress; Sign out disabled | Fake success spinner |
| **Failure** | Actionable error; **Retry**; account still active | “Deleted” copy when server failed |
| **Success** | Short confirmation; return to signed-out shell | Local wipe before server ack |

Copy must never say deletion succeeded unless the hosted delete endpoint returned success for **this** session’s creator/workspace.

### Backend contract (new — proposal only)

**New Edge Function (name TBD):** `delete-account` or `delete-creator-account`.

| Rule | Requirement |
| --- | --- |
| Auth | Device session via existing `verifyDeviceSession` (`supabase/functions/_shared/device-auth.ts`) |
| Identity | Derive `workspace_id`, `creator_id`, `member_id` from authenticated session — **reject** client-supplied account ids used as authority |
| Body | May accept `confirm: true` only; no `creator_id` override |
| Scope | Delete or anonymize rows per retention policy for **this** creator/workspace only |
| Sessions | Revoke all device installations for member (same pattern as `manage-testers` revoke + `revoke-device-session`) |
| Apple | Trigger Supabase Auth user deletion or documented revoke path so `userDeleted` can fire |
| Response | `{ deleted: true }` or stable error codes (`account_delete_failed`, `session_revoke_failed`, etc.) |
| Idempotency | Second delete on already-deleted account → safe terminal state, not cross-account effect |

**Hosted verification:** still **held**. Local disposable-account checks are labeled local only. Do not mark CH-05 hosted verify closed until Bobby/Grok run staged proof.

### Client orchestration contract

1. **Pre-call:** Show consequences + confirm. Do not clear local data.
2. **Call:** Session-scoped delete endpoint with live device token (same header pattern as `AuthenticationService.signOut`, `AuthenticationService.swift:132-139`).
3. **On success only:**
   - Revoke local session (reuse sign-out path: `revoke-device-session`, keychain clear, Supabase local sign-out — `AuthenticationService.swift:120-151`).
   - Clear workspace-scoped local stores (see Local state table below).
   - Drop in-flight generation work for the deleted session (see Isolation).
4. **On failure:** Keep session; show retry. No local wipe.
5. **Remote delete without in-app initiation:** Preserve existing **ART-18** behavior — Supabase `userDeleted` → `AppState.observeAuthenticationChanges` → `finishLocalSignOut()` (`AppState.swift:179-184`, `AuthenticationRuntimeTests.testRemoteUserDeletedEventReturnsToSignedOutShell`). Do not regress this path.

### Local state — clear only after deletion success

| Store | Keys / paths | Source lines |
| --- | --- | --- |
| Keychain paired session | `RuntimeKeychainKey.pairedDeviceSession` | `RuntimeConfigurationStore.swift:116-143` |
| Legacy onboarding (global) | `ch-onboarding-progress`, `ch-onboarding-done`, `ch-onboarding-data` | `OnboardingStore.swift:137-140, 202-205` |
| Scoped onboarding | `ch-onboarding.{workspace}.{creator}.progress\|data` | `OnboardingStore.swift:36-37, 94-97` |
| Accepted async generations | `ch-accepted-day-generations` | `AcceptedDayGenerationStore.swift:23, 49-50` |
| Plan calendar selection | `ch-plan-selected-date` | `PlanSelectedDateStore.swift:14, 32-33` |
| Today file cache | `Application Support/.../TodayCache/today-{workspace}-{creator}.json` | `TodayCacheStore.swift:58-77` |
| Generation debug log | `Application Support/.../Logs/generation.log` | `GenerationLogFile.swift:5-15` |
| AI consent (CH-06) | New key — see CH-06 | — |

Sign-out today resets runtime to fixtures (`AppState.finishLocalSignOut`, `AppState.swift:206-214`) but does **not** clear UserDefaults caches or Today file cache. Deletion success must be stricter than sign-out.

### Isolation contract (CH-08 alignment)

Applies to delete, sign-out, and account switch:

| Scenario | Required behavior |
| --- | --- |
| In-flight `generate_day` / poll | Cancel client polling; ignore late responses unless session + creator still match |
| In-flight `regenerate_day` | Same |
| Automatic storyboard `.task` (`GeneratedDayPlannedContent.swift:167-169`) | Gate on live session + consent; abort if session ends mid-flight |
| Plan idea fetch | Abort / discard if session changed |
| Cross-account | Never apply generation result to a different `creator_id` / `workspace_id` |
| Post-delete generation | Must not write to deleted creator rows |

Reuse existing generation lease / identity checks where present; add explicit session-generation token if Grok needs a single choke point in `AppServices`.

### What deletion is not

- Sign-out alone (`YouAccountView.swift:250-279`)
- DEBUG onboarding reset (`YouAccountView.swift:224-247`)
- Tester revoke via Admin (`manage-testers` action `revoke`) — different surface
- Hosted proof from local-only runs

---

## CH-06 — Privacy manifest, policy link, AI consent

### Privacy manifest (`.xcprivacy`)

**Rule:** Declare only what the **Release archive** actually uses. Source grep is inventory input, not approval.

| Step | Owner | Action |
| --- | --- | --- |
| 1 | Implementation | Add app-owned `PrivacyInfo.xcprivacy` + `project.yml` resource entry |
| 2 | CH-13 archive | Inspect `ContentHelper.app` **and** embedded dependency bundles for merged manifests |
| 3 | Compliance | Map each `NSPrivacyAccessedAPIType` to an approved reason code — **do not guess CA92.1** |

Until archive inspection completes: **do not declare** UserDefaults or FileTimestamp APIs in the shipping manifest. Candidate call sites are listed in `ai-data-inventory.md`.

Dependency manifests already present in builds (e.g. `swift-crypto` `PrivacyInfo.xcprivacy` in archive bundles) are not a substitute for an app-owned manifest.

### In-app privacy policy link

**Current state:** No ContentHelper privacy URL in Swift (grep `privacy`, `Privacy Policy`, `privacyPolicy` — no matches under `CreatorContentOS/`).

**Contract:**

| Surface | Control | URL source |
| --- | --- | --- |
| You → Account | `Privacy policy` row opens Safari | Constant in `PrivacyPolicyLinks.swift` (new) — **placeholder until host approval** |
| ASC (CH-12) | Same canonical URL | Filled when host route exists |

Expected: **none today** — confirmed.

Do not point ContentHelper at PipCount policy copy. PipCount URLs must remain valid on the shared host (`change-ledger-accepted.md` CH-06 hold).

### Hosting (held — needs Bobby approval)

**Preference:** New ContentHelper routes on existing support/privacy hosts (e.g. path under `privacy.contenthelper.in`), **without** replacing PipCount root content.

| Requirement | Detail |
| --- | --- |
| Approval | Bobby approval before any live DNS / page edit |
| Read-back | After publish, read-back for **both** PipCount and ContentHelper pages |
| This task | **No live DNS change.** Contract URLs stay `TBD` until approved |

Proposed placeholder paths (not live):

- `https://privacy.contenthelper.in/contenthelper` — policy (TBD)
- `https://support.contenthelper.in/contenthelper` — support (CH-12, TBD)

### AI consent contract

Apple **5.1.2** — disclose and obtain permission before sharing personal data with third-party AI.

#### Consent store (new)

| Field | Type | Notes |
| --- | --- | --- |
| `consentVersion` | String | Bump when policy or destinations change |
| `acceptedAt` | ISO8601 | Per device |
| `destinationsAcknowledged` | `[String]` | e.g. `deepseek`, `openai`, `gemini` |

Persist in UserDefaults under workspace+creator scoped key, e.g. `ch-ai-consent.{workspace}.{creator}` — same scoping pattern as `WorkspaceScopedOnboardingStore` (`OnboardingStore.swift:36-37`).

#### Consent UI (short language)

Must state **purpose** and **destination** in plain words, e.g.:

> ContentHelper sends your creator profile, day briefs, scripts, and storyboard notes to AI partners (DeepSeek, OpenAI, Google Gemini) to generate scripts, captions, plan ideas, and storyboard images. Nothing is posted for you.

Buttons: **Allow** / **Not now**. Decline blocks outbound calls until accepted. **Retry** available from the same surface that triggered generation.

#### Gated outbound paths (must all check consent)

| Path | Trigger | Automatic? |
| --- | --- | --- |
| `generate_day` / `regenerate_day` | Plan / onboarding first idea / explicit Generate | User-initiated (still requires consent before first call) |
| `generate-plan-ideas` | Plan empty-day ideas (`AppServices` → `fetchPlanDayIdeasWithTimeout`, `AppServices.swift:849-874`) | **Yes** — fires when Plan loads empty day |
| `generate-storyboard-thumbnail` | `GeneratedDayPlannedContent` `.task` (`GeneratedDayPlannedContent.swift:167-169`) → `prepareStoryboardThumbnailsForVisibleCard` | **Yes** — fires when thumbnails missing |

Consent must cover **automatic** paths, not only explicit Generate.

#### Logging contract

| Allowed | Forbidden |
| --- | --- |
| Action name, date, char counts, generation ids, error codes | Private notes, tokens, raw prompts, full profile JSON, email |
| Existing pattern: `brief_chars=`, `guidance_chars=` (`SupabaseRepositories.swift:442, 494`) | Logging `dayBrief`, `voice_rules`, `positioning`, script body |

Applies to `GenerationLogFile` (`GenerationLogFile.swift`) and `print` diagnostics. Backend already avoids logging raw prompts in some tests (`generate-week/index_test.ts:3333`); client must match.

---

## CH-07 — Held note (omit vs null)

**Do not deploy.** Record for later fixture only.

| Risk | Evidence |
| --- | --- |
| Old client omits adaptive profile keys on update | `normalizedCreatorProfileUpdate` skips `undefined` (`write-content/index.ts:805-809`, `:827-829`, `:841-845`, `:903-905`) |
| Explicit `null` can clear arrays | `:1000-1003` |
| iOS omits unset keys | `WriteContentDTOs.swift:94-123` |

**Fixture later (not this task):** omitted-key update vs explicit-null vs insert, against candidate handler, before any hosted deploy.

**CH-05 deletion** must not rely on CH-07 deploy. Profile wipe on delete is a dedicated delete-account handler concern.

---

## AppServices integration split (for Grok)

**Problem:** `AppServices.swift` is ~2715 lines. CH-05 and CH-06 must land without two agents editing the same file concurrently.

**Smallest split:** New types + extensions; **thin hooks only** in `AppServices.swift`.

```
AppServices.swift                    ← Grok: 3–5 line delegations only
AppServices+AccountDeletion.swift    ← deletion orchestration (new)
AppServices+AIConsent.swift          ← consent gate wrappers (new)
AccountDeletionService.swift         ← session-scoped delete API (new)
AIConsentStore.swift                 ← versioned UserDefaults store (new)
AIConsentPrompt.swift                ← shared SwiftUI sheet (new)
PrivacyPolicyLinks.swift             ← URL constants (new, TBD until host)
LocalAccountDataCleaner.swift        ← post-success wipe list (new)
```

**Grok-owned touch points in `AppServices.swift` (thin):**

```swift
// Pseudocode — exact names at implementation
func deleteAccount() async throws { try await accountDeletion.deleteAccount() }
func requireAIConsent(for surface: AIConsentSurface) async throws { ... }
```

Existing methods keep bodies; add **first-line** consent check:

- `generateDayCard` (`AppServices.swift:887+`)
- `prepareStoryboardThumbnailsForVisibleCard` (`AppServices.swift:1096+`)
- `loadPlanDayIdeasIfNeeded` / `fetchPlanDayIdeasWithTimeout` (`AppServices.swift:820+`, `:849+`)

Do **not** move unrelated generation logic in this pass (CH-09 deferred).

---

## Files to touch when implementation is approved

### CH-05

| File | Change |
| --- | --- |
| `CreatorContentOS/Features/You/YouAccountView.swift` | Delete account UI + states |
| `CreatorContentOS/Features/You/YouAccountDeletionFlow.swift` | **New** — consequences / confirm / pending / retry |
| `CreatorContentOS/App/AppServices+AccountDeletion.swift` | **New** |
| `CreatorContentOS/Data/AccountDeletionService.swift` | **New** — Edge Function client |
| `CreatorContentOS/Data/LocalAccountDataCleaner.swift` | **New** |
| `CreatorContentOS/App/AppState.swift` | Wire success → clean + sign-out; preserve `userDeleted` path |
| `CreatorContentOS/App/AppServices.swift` | Thin delegation + in-flight cancel token |
| `CreatorContentOS/Data/AuthenticationService.swift` | Reuse revoke/sign-out; optional shared helper |
| `supabase/functions/delete-account/index.ts` | **New** — session-scoped deletion |
| `supabase/functions/delete-account/index_test.ts` | **New** |
| `CreatorContentOSTests/AuthenticationRuntimeTests.swift` | Extend — deletion success + ART-18 regression |
| `CreatorContentOSTests/AccountDeletionTests.swift` | **New** — local disposable account (labeled local) |

### CH-06

| File | Change |
| --- | --- |
| `CreatorContentOS/PrivacyInfo.xcprivacy` | **New** — after archive inspection |
| `project.yml` | Resource + build setting |
| `CreatorContentOS/Config/PrivacyPolicyLinks.swift` | **New** |
| `CreatorContentOS/Data/AIConsentStore.swift` | **New** |
| `CreatorContentOS/Features/Privacy/AIConsentPrompt.swift` | **New** |
| `CreatorContentOS/App/AppServices+AIConsent.swift` | **New** |
| `CreatorContentOS/Features/You/YouAccountView.swift` | Privacy policy link row |
| `CreatorContentOS/App/AppServices.swift` | Thin consent gates at three outbound paths |
| `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift` | Optional — surface consent error from gated `.task` |
| `CreatorContentOSTests/AIConsentTests.swift` | **New** — accept / decline / retry |

### Not in this wave

- PipCount site content
- GitHub Discussions (CH-14 off)
- Hosted deploy without explicit approval
- CH-07 handler edits

---

## Open questions (Bobby / Grok only)

| # | Question | Blocks |
| --- | --- | --- |
| OQ-1 | **Hosted policy URL** — exact path on `privacy.contenthelper.in` (or alternate host)? | In-app link constant, ASC CH-12 |
| OQ-2 | **Support URL** — same host pattern for CH-12? | ASC metadata |
| OQ-3 | **Delete retention** — hard delete vs anonymize for packages, references, archive? | `delete-account` handler schema |
| OQ-4 | **Apple Auth deletion** — Supabase `auth.admin.deleteUser` vs revoke-only? | Whether `userDeleted` always fires |
| OQ-5 | **Consent version string** — initial value and bump policy? | `AIConsentStore` |
| OQ-6 | **NSPrivacyAccessedAPIType reason codes** — which Apple reason applies to each API after archive inspect? | Shipping manifest |
| OQ-7 | **Confirm pattern** — typed `DELETE` vs double confirmation? | Paper CH-04 + You UI |
| OQ-8 | **Error codes** — stable `delete-account` response codes for UX copy? | Failure / retry strings |

---

## Validation checklist (post-implementation, pre-submit)

- [ ] Disposable local account: delete → signed out → relaunch → cannot access old packages (labeled **local**)
- [ ] ART-18: inject `userDeleted` → signed-out shell, fixtures runtime (existing test passes)
- [ ] Consent decline blocks `generate_day`, Plan ideas, and automatic thumbnails
- [ ] Consent accept → all three paths proceed
- [ ] Archive inspect: app + dependency `.xcprivacy` merged; no guessed reasons
- [ ] In-app privacy link opens approved ContentHelper page (after host gate)
- [ ] PipCount URLs still valid (read-back both apps)
- [ ] Hosted deletion proof (**held**) — do not check until explicit approval

---

*End of privacy & account contracts. Proposal only. No app source edited in this task.*
