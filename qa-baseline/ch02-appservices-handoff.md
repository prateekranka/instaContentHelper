# CH-02 AppServices handoff (Grok)

Repo: `/Users/prateekranka/Cowork/contenthelper`  
Decision: `dec-20260907-002` (Launch-A)  
Scope: **`AppServices.swift` only** — CH-02 onboarding slice must not edit this file.

## Why handoff is required

Launch-A skip/continue persists onboarding with `voiceDeferred: true` and **does not** write fabricated `positioning` / `voice_rules` (`OnboardingProfileMapper` change in `CreatorOnboardingState.swift`).

`generateDayCard` still gates on `canGenerateContent`, which today requires either configured voice **or** deferred voice:

```swift
// AppServices.swift ~239-257 (current)
var voiceDeferred: Bool {
    false  // hard-coded — ignores profile + onboarding record
}

var voiceGateOpen: Bool {
    !voiceIsConfigured && !voiceDeferred
}
```

After an honest Launch-A confirm, `voiceIsConfigured` is false and `voiceDeferred` stays false → first idea hits `creator_voice_required`.

## Exact predicate change (Grok)

Replace the hard-coded `voiceDeferred` getter with profile-backed deferral for established creators who have not set voice yet:

```swift
var voiceDeferred: Bool {
    guard creatorProfileSummary.onboardingState == .established else {
        return false
    }
    return !voiceIsConfigured
}
```

**Do not change** `voiceIsConfigured`, `voiceGateOpen` structure, `confirmOnboardingAndPrepareFirstIdea`, overwrite guards, publish guards, or `generateDayCard` overwrite logic.

## Expected behavior after change

| Profile state | `voiceIsConfigured` | `voiceDeferred` | `canGenerateContent` |
| --- | --- | --- | --- |
| Launch-A skip/continue just saved (empty voice) | false | true | **true** |
| Creator saved voice in You | true | false | true |
| `new` / `partial` before confirm | false | false | false |

## Tests that unblock after this lands

- New Launch-A skip path calling `confirmOnboardingAndPrepareFirstIdea` with zero fields + `voiceDeferred: true` (manual QA + future test).
- `VoiceGateTests.testLegacyUserDefaultsDeferralDoesNotOpenVoiceGate` may need revisiting if product still stores legacy UserDefaults deferral — Launch-A uses profile state instead.

## Out of scope for this handoff

- No schema / DTO changes.
- No change to first-idea overwrite / ready-package guards.
- `voicePrefilled` UI draft in You remains separate (`YouCreatorVoiceView`).
