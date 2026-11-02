# Onboarding

Optional setup on first launch. The creator can skip it, or pick a
starting point and interests, then gets a first idea on Today.

## Sub-features

- Starting point: one choice of `onboarding.startingPoint.just_starting`
  or `onboarding.startingPoint.already_posting`.
- Interests: toggles such as `onboarding.interest.books` and
  `onboarding.interest.fitness-wellness`.
- `onboarding.generateFirstDay` makes the first idea from the choices;
  `onboarding.setUpLater` skips setup and still makes one.
- A failed first idea shows `onboarding.retryFirstIdea`. A slow one
  disables both buttons until it arrives.

## How to get to it (user POV)

First launch. In tests, `MCO_FORCE_ONBOARDING=1` with
`MCO_FORCE_EMPTY_TODAY=1`, which every scenario except `welcome` and
`empty` sets.

## Driving it with e2e

`POCKET_E2E_SCENARIO=onboarding` taps the choices; `retry` sets
`MCO_FAIL_FIRST_IDEA_ONCE=1`; `slow` sets `MCO_SLOW_FIRST_IDEA=1`. Every
other suite starts with `startFromOnboarding(app, screen)`, which taps
`onboarding.setUpLater`.

## Proof

`today.startFilming` and `today.package.title` are visible, and
`onboarding.setUpLater` is gone. A choice is proven with
`toBeSelected()`, not with a screenshot. `onboarding.setUpLater` is at
least 44 points tall.

## Charters

```
onboarding-choices|ios|fuzzer|From first launch, tap every starting point and interest many times in fast order, then generate; report a choice that does not stick, a double first idea, or a stuck spinner
onboarding-failure|ios|recovery|With MCO_FAIL_FIRST_IDEA_ONCE=1, fail the first idea, then retry, skip, and relaunch; report a dead end or a lost choice
```

## Gotchas

- The first idea can take up to 45 seconds in `slow`; use
  `toBeVisible({ timeout: 45_000 })`, not a sleep.
- After onboarding, a relaunch must pass `-MCO_FORCE_ONBOARDING 0` or
  onboarding comes back.
