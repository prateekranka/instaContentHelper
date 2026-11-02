---
name: motion-durations
description: Pick how long an interaction or animation should take, and whether it should animate at all, on web, SwiftUI, UIKit, or React Native. Use when choosing or reviewing a duration, spring, or transition timing, or when someone asks "how fast should this animate?".
---

# Motion durations

Pick the duration from what the element is and how often people see it.
Based on Emil Kowalski's published duration guidelines. For the full
build and review workflow, use `animate`, `review-animations`, and
`find-animation-opportunities`.

## Step 1: How often will someone see it?

| Frequency | Decision |
| --- | --- |
| 100+ times a day (keyboard shortcuts, tab switches, core navigation) | No animation, or nearly none |
| Occasional (sheets, menus, toasts, settings) | Standard animation |
| Rare or first time (onboarding, success, empty states) | You may add delight |

If it fails this step, ship an instant state change and stop.

## Step 2: Pick the duration

| Element | Duration |
| --- | --- |
| Micro-interactions (press, toggle, checkbox) | 100-150ms |
| Standard UI (tooltips, dropdowns, menus) | 150-250ms |
| Modals, drawers, sheets | 200-300ms |
| Page or screen transitions | 300-400ms |

Rule: UI animation stays under 300ms. Only page transitions and
marketing or explanatory motion go longer, and each needs a reason.

## Step 3: Pick the curve

- Entering or leaving: ease-out. Never ease-in on UI.
- Moving on screen: ease-in-out.
- Anything the user can drag, flick, or reverse: a spring, not a fixed duration.

## Platform values

| Platform | Short (press) | Standard | Sheet or modal |
| --- | --- | --- | --- |
| CSS | `transition: transform 120ms cubic-bezier(0.23, 1, 0.32, 1)` | `200ms` same curve | `250ms` same curve |
| SwiftUI | `.animation(.easeOut(duration: 0.12), value:)` | `.easeOut(duration: 0.2)` or `.snappy(duration: 0.2)` | `.spring(duration: 0.3, bounce: 0.1)` |
| UIKit | `UIView.animate(withDuration: 0.12, delay: 0, options: .curveEaseOut)` | `0.2` | `UISpringTimingParameters(dampingRatio: 0.9)` over `0.3` |
| React Native Reanimated | `withTiming(v, { duration: 120, easing: Easing.out(Easing.cubic) })` | `duration: 200` | `withSpring(v, { duration: 300, dampingRatio: 0.9 })` |

On Apple platforms, system navigation pushes, sheets, and alerts already
have tuned timing. Do not override them unless the design needs it.

## Always ship with the animation

- Reduced motion: keep fades and color changes, drop movement and scale.
  SwiftUI reads `@Environment(\.accessibilityReduceMotion)`, CSS uses
  `@media (prefers-reduced-motion: reduce)`.
- Rapid triggers (toggles, toasts): use transitions or springs that
  retarget from the current value, not keyframes that restart.

## Output

State the frequency tier, the duration, and the curve in one line each,
then write the code.
