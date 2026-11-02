# Feature map

One file per user-facing feature of ContentHelper, from the creator's
point of view. Each names the test that pins it, the ids that matter, the
proof, and its bug-bash charters. The screen list and the flow spec for
the next design are in
[docs/design/creator-ios-v1-2026-10-18/](../../../../docs/design/creator-ios-v1-2026-10-18/).

| Feature | How to reach it | Test | Scenarios | Status |
| --- | --- | --- | --- | --- |
| [Onboarding](onboarding.md) | First launch | `tests/pocket-onboarding.e2e.ts` | `onboarding`, `retry`, `slow` | tested |
| [Today and filming](today-filming.md) | Today tab, Start filming | `tests/pocket-today.e2e.ts`, `tests/pocket-alternatives.e2e.ts` | `ready`, `alternatives` | tested |
| [Post](post.md) | Finish the last shot | `tests/pocket-today.e2e.ts` | `ready`, `sync-error` | tested |
| [Plan](plan.md) | Plan tab | `tests/pocket-plan.e2e.ts` | `plan` | tested |
| [You and creator voice](creator-voice.md) | You tab, or Plan's voice setup | `tests/pocket-plan.e2e.ts`, `tests/pocket-screens.e2e.ts` | `plan`, catalog | tested |
| Large text, long content, reduced motion, empty, welcome | Launch flags | `tests/pocket-accessibility.e2e.ts` | `large`, `long`, `motion`, `empty`, `welcome` | tested |
