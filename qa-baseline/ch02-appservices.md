# CH-02 AppServices — first-idea voice deferral

Repo: `/Users/prateekranka/Cowork/contenthelper`  
Decision: `dec-20260907-002` (Launch-A)  
Handoff: `qa-baseline/ch02-appservices-handoff.md`  
Recorded: 7 September 2026

## Predicate (one sentence)

First-idea `generateDayCard` may run when `allowDeferredVoice` is true **and** the persisted profile is `established` with empty voice; Plan `generate_day` still requires configured voice (VG-6).

## What landed

`confirmOnboardingAndPrepareFirstIdea` passes `allowDeferredVoice: completedData.voiceDeferred` into `generateDayCard`. The gate is:

```
canGenerateContent || (allowDeferredVoice && onboardingState == .established && !voiceIsConfigured)
```

- Launch-A skip/continue (`voiceDeferred: true`, no fabricated positioning/rules) can generate the first idea.
- Mapper still omits canned voice when deferred. That empty voice is not marked as a saved preference.
- Overwrite, `makeDayAvailable`, isolation, retry, and ready-package skip guards are unchanged.

## Rejected from the handoff

The handoff asked to replace the global getter with:

```swift
var voiceDeferred: Bool {
    guard creatorProfileSummary.onboardingState == .established else { return false }
    return !voiceIsConfigured
}
```

**Rejected.** That would set `canGenerateContent` true for every established creator with empty voice, including Plan `generate_day`. The handoff did not prove Plan must change. Current product still requires voice there (VG-6).

`voiceDeferred` stays `false` for Plan / `canGenerateContent` / `voiceGateOpen`. You → Creator voice deferred hints that read `services.voiceDeferred` stay off until a later You slice.

## Not changed

- `voiceIsConfigured`
- `voiceGateOpen` structure
- Overwrite / publish / `makeDayAvailable` / first-idea skip-ready-package logic
- Schema, DTOs, backend, build number
- `prototypes/today-ui/index.html` (not edited in this slice)
- CH-05 / CH-06

## Tests

Simulator `FAE1FD16-D185-433C-AC85-544FF45F2C82`. **105 passed, 0 failed.** Full 359 not run.

| Suite | Result |
| --- | --- |
| VoiceGateTests | 9 passed (includes Plan established+empty-voice still `creator_voice_required`) |
| FirstIdeaHandoffTests | 15 passed (includes deferred-voice first-idea generate) |
| AdaptiveOnboardingPersistenceTests | 9 passed |
| AdaptiveOnboardingVerificationTests | 15 passed |
| OnboardingTests | 57 passed |

VG-6 still holds: Plan `generateDayCard` with established empty voice is rejected.  
AOP-6 / VG-8 intent: deferral does not dead-end first-idea generation, without writing fabricated voice as preference.
