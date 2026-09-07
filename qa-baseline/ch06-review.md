# CH-06 independent review (local AI consent)

Recorded: 7 September 2026.
Reviewer did not implement the slice. `qa-baseline/ch06-consent-implementation.md` was read **after** `git status` / `git diff`.
Repo: `/Users/prateekranka/Cowork/contenthelper` · branch `cursor/today-ui-prototype-cea4`
Simulator: ContentHelper QA · `FAE1FD16-D185-433C-AC85-544FF45F2C82`
This review did **not** implement CH-05 deletion, did **not** add `PrivacyInfo.xcprivacy` reason codes, and did **not** edit PipCount hosts.

## Verdict

**PASS.** No review code fix.

| Return | Value |
| --- | --- |
| pass/fail | **pass** |
| `project.yml` ok | **yes** (folder source `CreatorContentOS`; all six new Swift files are under that tree) |
| automatic paths gated | **yes** (`generate-plan-ideas` and storyboard `.task`) |

## Scope checks

| Check | Result |
| --- | --- |
| New Swift files in `project.yml` **and** pbxproj | **ok** |
| Consent version `contenthelper-ai-consent-v1` | **ok** |
| Decline blocks `generate_day`, `generate-plan-ideas`, automatic storyboard `.task` | **ok** (live only) |
| Grant retry from You → Account | **ok** (`Allow AI partners` → sheet; `acceptAIConsent` bumps `aiConsentEpoch`) |
| Privacy policy does not open PipCount | **ok** (`privacyPolicyURL == nil`; row is static text) |
| No new notes/tokens/raw-prompt logging | **ok** |
| Fixture/DEBUG does not call live partners without consent; does not brick fixture UI | **ok** |
| Tests in existing files | **ok** (no new test **file**) |
| CH-05 deletion | **ok — not started** |
| Privacy manifest reason codes | **ok — not guessed / not added** (held) |
| PipCount hosts / deploy / build number | **ok — not touched** (`2026081102`) |

## Project membership

`project.yml` uses `sources: - CreatorContentOS` (directory glob, dated 11 August). It does not list files one by one. That is enough: the next `xcodegen generate` would still pick up the new files.

pbxproj already compiles all six (file refs + `PBXSourcesBuildPhase`):

| File | Role |
| --- | --- |
| `CreatorContentOS/Data/AIConsentStore.swift` | Versioned store, key `ch-ai-consent.{workspace}.{creator}` |
| `CreatorContentOS/Config/PrivacyPolicyLinks.swift` | Nil policy URL |
| `CreatorContentOS/Features/Privacy/AIConsentCopy.swift` | Purpose/destination copy + `ai_consent_required` |
| `CreatorContentOS/Features/Privacy/AIConsentSheet.swift` | Sheet + root `.aiConsentSheet()` |
| `CreatorContentOS/App/AppServices+AIConsent.swift` | Gate, accept/decline, consent log line |
| `CreatorContentOS/Features/You/YouAccountPrivacyBlock.swift` | Account privacy + retry |

No uncompiled orphan Swift files in this slice.

xcodegen was **not** re-run in this review (pbxproj is not stale for these files).

## Gates (live)

`requireAIConsent` returns immediately when `isLiveSupabaseRuntime == false`. Live calls check current version + `accepted` before the repository invoke.

| Path | Automatic? | Gate |
| --- | --- | --- |
| `generateDayCard` | No | `requireAIConsent(.generateDay)` before `dailyGeneration.generateDay` |
| `regeneratedDailyCard` | No | `requireAIConsent(.regenerateDay)` before `regenerateDay` |
| `refreshPlanDayIdeas` | **Yes** | Consent **before** `fetchPlanDayIdeasWithTimeout`; on fail, local `PlanDayIdeaBuilder` lines stay |
| `prepareStoryboardThumbnailsForVisibleCard` | **Yes** (`.task`) | `promptIfDeclined: false`; returns without calling the thumbnail repo |
| `generateStoryboardThumbnails` (Prepare visuals / Refresh) | No | `promptIfDeclined: true` (retry after decline) |

Storyboard `.task` id includes `aiConsentEpoch`, so Allow can retry prep.

Decline writes `decision=declined` for `contenthelper-ai-consent-v1` with destinations `deepseek`, `openai`, `gemini`. Swipe-dismiss of an undecided sheet also records decline.

## Privacy policy

`PrivacyPolicyLinks.privacyPolicyURL` is `nil`. You → Account row is `AXStaticText` (`you.account.privacyPolicy`), not a button. Copy: **Policy page not published yet**. No `pipcount` string. No `privacy.contenthelper.in` open.

## Logging

`logAIConsentEvent` prints action, version, optional surface name (`generate_day` / `regenerate_day` / `plan_ideas` / `storyboard_thumbnail`). It does not log briefs, notes, tokens, or raw prompts.

## Fixture / DEBUG

Fixture `AppServices.fixtureBacked` defaults `isLiveSupabaseRuntime: false`, so generate is not blocked by consent. Fixture storyboard stub throws `storyboard_thumbnail_generation_not_configured` (pre-existing; `.task` uses `try?`). `testGenerateDayCardAllowedWhenVoiceConfigured` still passes on fixture.

Live DEBUG on this QA sim is gated (see sim).

## Tests

No new test file. Additions are in existing `VoiceGateTests.swift` and `YouFeatureTests.swift`.

Independent run (not the 359-suite), DerivedData `/tmp/ch06-review-derived`, destination ContentHelper QA:

```
xcodebuild test -project CreatorContentOS.xcodeproj -scheme CreatorContentOS \
  -destination 'platform=iOS Simulator,id=FAE1FD16-D185-433C-AC85-544FF45F2C82' \
  -derivedDataPath /tmp/ch06-review-derived \
  -only-testing:CreatorContentOSTests/VoiceGateTests \
  -only-testing:CreatorContentOSTests/YouFeatureTests/testPrivacyPolicyLinkStaysUnpublished \
  -only-testing:CreatorContentOSTests/YouFeatureTests/testAIConsentVersionAndCopyCoverPartnersWithoutBackendJargon \
  -only-testing:CreatorContentOSTests/YouFeatureTests/testAIConsentStoreScopesByWorkspaceAndCreator \
  -only-testing:CreatorContentOSTests/YouFeatureTests/testAIConsentRecordsAcceptedAndDeclinedForCurrentVersion \
  -only-testing:CreatorContentOSTests/YouFeatureTests/testAIConsentOldVersionDoesNotAllowOutbound
```

**22 passed, 0 failed** (VoiceGateTests 17 + five YouFeature methods). Full `YouFeatureTests` class was not run (`testContentCategorySelectionMapsPresetAndCustomPillars` is a known earlier fail, not this slice).

## Sim spot-check

Device `FAE1FD16-D185-433C-AC85-544FF45F2C82`. Runtime on Account: **Supabase Live**, **Gemini Live**. Argent teardown scoped to that UDID.

| Step | Result |
| --- | --- |
| You → Account | Privacy + AI partners rows present. Status **Not decided yet**. **Allow AI partners** retry control present. |
| Privacy policy | Not tappable. **Policy page not published yet.** |
| Plan empty day 8 Sep 2026 | Automatic ideas path presented **Allow AI partners** sheet. Local on-device idea lines still listed. |
| **Not now** | Sheet dismissed. Hint remains: `Allow AI partners first. You can also allow this later in You → Account.` Idea chips stay local (`your niche` builder copy). No live generate started. |

Screens: `qa-baseline/screens/ch06-you-account-privacy.png`, `ch06-plan-consent-sheet.png`, `ch06-plan-after-decline.png`.

Voice is **Not set** on this account, so Plan Generate chips stay dim after decline (voice gate before consent). The automatic plan-ideas sheet already proved the live outbound block.

## Held / mixed tree (not fails)

- CH-05 Delete account: not in You Account.
- `PrivacyInfo.xcprivacy`: not added (archive inspect + reason codes still held).
- Hosted policy URL still TBD.
- Working tree also has CH-02 / CH-03 / CH-15 edits. Left as-is.

## Leftovers (not review fixes)

- After decline, `refreshPlanDayIdeas` caches local ideas; Allow bumps `aiConsentEpoch` but does not clear that cache, so live plan-ideas may stay local until the setup fingerprint changes. Generate and storyboard `.task` still retry. Out of the three allowed review-fix classes.
- You → Account **Allow AI partners** sits under the tab bar on this phone size.
- No dedicated `regenerate_day` unit test (code path is gated).
- `generate-week` in `SupabaseRepositories` is not called from `AppServices` in this tree.
