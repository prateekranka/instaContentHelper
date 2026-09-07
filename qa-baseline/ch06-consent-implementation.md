# CH-06 consent implementation (local only)

Repo: `/Users/prateekranka/Cowork/contenthelper`  
Decision: `dec-20260907-002` (Launch-A)  
Contracts: `privacy-account-contracts.md`, `ai-data-inventory.md`, `change-ledger-accepted.md`  
Recorded: 7 September 2026 IST  
Simulator used for tests: ContentHelper QA · `FAE1FD16-D185-433C-AC85-544FF45F2C82`

## Predicate (one sentence)

Live outbound AI (`generate_day` / `regenerate_day`, `generate-plan-ideas`, storyboard thumbnail prep) waits for versioned consent `contenthelper-ai-consent-v1`; decline records the refusal and blocks those calls until Allow from the same surface or You → Account.

## Where the sheet is shown

Root presenter: `CreatorContentOSAppView` `.aiConsentSheet()` (onboarding + Creator shell).

| Trigger | Automatic? | Sheet? |
| --- | --- | --- |
| Plan / first-idea **Generate** (`generateDayCard`) | No | Yes, if current version is not accepted |
| Plan **regenerate** | No | Yes, if current version is not accepted |
| Plan empty-day **ideas** (`refreshPlanDayIdeas`) | Yes | Yes on first undecided live load; **no** re-prompt after decline |
| Storyboard panel `.task` (`prepareStoryboardThumbnailsForVisibleCard`) | Yes | Yes on first undecided live load; **no** re-prompt after decline |
| **Prepare visuals / Refresh** | No | Yes, including after a prior decline (retry) |
| You → Account **Allow AI partners** | No | Yes (retry / first grant) |

Fixture / sample runtime (`isLiveSupabaseRuntime == false`) does not share with partners, so the gate does not block fixture `generateDayCard`.

## What Skip / Not now does

- Button copy: **Allow** / **Not now**. Swipe-dismiss of an undecided sheet counts as **Not now**.
- Writes `ch-ai-consent.{workspace}.{creator}` with `decision=declined`, `consentVersion=contenthelper-ai-consent-v1`, destinations `deepseek`, `openai`, `gemini`.
- No live call to day generation, plan-ideas, or thumbnail partners.
- Plan still shows **on-device** idea lines (local builder). Missing storyboard images stay missing.
- Retry later: tap Generate or Visuals again (sheet returns), or You → Account → **Allow AI partners**.
- Allow writes `decision=accepted` for the same version, clears consent error banners, bumps `aiConsentEpoch` so Plan ideas and the storyboard `.task` retry.

## Privacy policy row

You → Account → **Privacy policy**. URL constant is `nil`. Label: **Policy page not published yet**. Not tappable. Does **not** open `privacy.contenthelper.in` or any PipCount page.

## Held / not in this slice

- CH-05 account deletion
- `PrivacyInfo.xcprivacy` / `NSPrivacyAccessedAPIType` reason codes
- Live privacy/support hosts, PipCount URLs, DNS
- Deploy, build number (`2026081102` unchanged)
- `prototypes/today-ui/index.html` (untouched)

## Files

**New**

| File | Role |
| --- | --- |
| `CreatorContentOS/Data/AIConsentStore.swift` | Versioned, workspace+creator UserDefaults store + in-memory test store |
| `CreatorContentOS/Config/PrivacyPolicyLinks.swift` | Nil URL + unpublished subtitle |
| `CreatorContentOS/Features/Privacy/AIConsentCopy.swift` | Purpose/destination copy + error code |
| `CreatorContentOS/Features/Privacy/AIConsentSheet.swift` | Sheet + root presenter |
| `CreatorContentOS/App/AppServices+AIConsent.swift` | Gate, accept/decline, logging |
| `CreatorContentOS/Features/You/YouAccountPrivacyBlock.swift` | Account privacy + retry |

**Thin edits**

| File | Change |
| --- | --- |
| `CreatorContentOS/App/AppServices.swift` | Store wiring; first-line gates on generate/regenerate, plan ideas, thumbnails |
| `CreatorContentOS/App/CreatorContentOSApp.swift` | `.aiConsentSheet()` |
| `CreatorContentOS/Features/You/YouAccountView.swift` | Inserts privacy block |
| `CreatorContentOS/Features/Daily/PlanHubView.swift` | Live consent hint; refresh ideas after Allow |
| `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift` | Consent epoch on `.task`; show consent error; Visuals retry |
| `CreatorContentOS.xcodeproj/project.pbxproj` | xcodegen include of new files |
| `CreatorContentOSTests/VoiceGateTests.swift` | Live accept/decline/outbound skip tests |
| `CreatorContentOSTests/YouFeatureTests.swift` | Store, version, unpublished policy tests |

Logging on consent lines: action, version, surface name only. No notes, tokens, or raw prompts.

## Tests

Simulator `FAE1FD16-D185-433C-AC85-544FF45F2C82`. DerivedData `/tmp/ch06-consent-derived`. **22 passed, 0 failed.**

| Suite | Result |
| --- | --- |
| VoiceGateTests | 17 passed (existing voice gates + live consent block/allow/decline + plan ideas + storyboard prep + You Account retry) |
| YouFeatureTests (new methods only) | 5 passed (unpublished policy, copy/version, scoped store, accept/decline, old version) |

Full YouFeatureTests class was **not** used as the gate: `testContentCategorySelectionMapsPresetAndCustomPillars` still fails from earlier category mapping (not this slice).

## Risks

- Live-only gate: fixture QA will not see the sheet unless the runtime is live.
- First-idea live generate still fails once if the creator has not allowed yet; onboarding **Retry** (or Allow on the sheet, then Retry) is the recovery.
- Hosted policy page remains unpublished by design.
