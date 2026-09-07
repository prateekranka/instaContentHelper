# CH-02 UI review — Launch-A one-screen

Repo: `/Users/prateekranka/Cowork/contenthelper`  
Contract: `onboarding-contract-launch-A.md` (`dec-20260907-002`)  
Reviewed: `OnboardingFlowView`, `OnboardingViewModel`, `OnboardingStore` / presentation policy  
Recorded: 7 September 2026  
This review did **not** redesign onboarding.

## Verdict

**ok**

The live first-use UI is one skippable screen. It does not show five steps.

## Scope checks

| Check | Result | Evidence |
| --- | --- | --- |
| One skippable screen | **ok** | `OnboardingFlowView` renders `launchChoiceStep` only. `OnboardingLaunchPresentation.stepCount = 1`. |
| You later | **ok** | Helper: “You can add taste, production prefs, and voice anytime under You.” Skip toast COPY-0431: “You can finish setup in You.” You hub still has Interests & style, Content preferences, Current reads & watches, Creator voice, References. |
| No mandatory handles | **ok** | Launch screen has starting-point chips + interest chips only. No handle / reel / URL field. `launchContinueEnabled` is true with zero fields. |
| Established profiles not overwritten | **ok** (live gate) | `OnboardingPresentationPolicy.shouldPresent(.established)` is false. DEBUG `MCO_FORCE_ONBOARDING` can still show the screen; `confirmOnboardingAndPrepareFirstIdea` will persist if that path is used. Flag only. |
| Generic starter labeled | **ok** (brief provenance) | Zero-field skip uses `OnboardingFirstIdeaBriefBuilder.genericStarterBrief`, which says it is a generic starter, not learned taste or voice. No on-screen “starter” badge. Flag only. |
| C12 toast honest | **ok** | COPY-0431 applied. Skip no longer says “we'll ask again next launch.” **Set up later** runs first-idea handoff, then You is the later path. |
| Cancel recoverable | **ok** | **Not now** → `cancelSetup()`: local progress saved, `sessionDismissed`, no generate, not `established`. Next launch restores chips on the same one screen. |
| Five steps still showing? | **no** | Progress a11y is “Step 1 of 1”. `OnboardingStep` enum still has cases 0…4 for legacy decode. Persisted steps 1…4 normalize to the launch screen. |

## Controls

| Control | Persists | Generates | Profile | Next launch |
| --- | --- | --- | --- | --- |
| **Show my first idea** | Yes | Yes | `established`; voice omitted when deferred | No first-use screen |
| **Set up later** | Yes | Yes (same handoff) | Same | Same |
| **Not now** | Local progress | No | Unchanged server state | Same one screen, restored picks |

`completedData()` always sets `voiceDeferred: true`, `voicePrefilled: nil`.

## Flags (not fails)

- `OnboardingStep` and unused step helpers (taste / production / context / review) remain in the ViewModel for You / legacy tests. They are not first-run screens.
- You hub voice row already says **Not set** when voice is empty (honest). Creator Voice *editor* deferred hints read `services.voiceDeferred`, which AppServices still keeps `false` so Plan stays gated. Later You polish.
- DEBUG force-onboarding can still call confirm and write an established row. Live shell does not present that path.
- Cancel recovery is local store progress, not a server `partial` row.
- `prototypes/today-ui/index.html` was already dirty in the tree. This review did not edit it.

## Out of scope (not started)

CH-05, CH-06, build number, onboarding redesign, AppState/DTO/backend.
