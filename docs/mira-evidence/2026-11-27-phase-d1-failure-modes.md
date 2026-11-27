# Phase D1 failure modes — Today, colors, text size, wait screen, idea cards (2026-11-27)

Written before the code. Scope: app only, no AI calls added, no server change. Source: context/04-ux-review-2026-11-26.md items 4–8 and Bobby's choices of 2026-11-27 (black, white and neutral gray; work like Phase A).

## Today screen (T)

- T1. The text box shows only one line, so long text goes out of view. Expected: 2–4 visible lines, then it scrolls inside the box.
- T2. The hint text is the only label. Expected: a visible label "What can you film today?" above the box.
- T3. The microphone asks for permission when Today opens. Expected: permission only after a tap on the microphone.
- T4. The microphone records, but the words do not get into the box, or they replace text that she typed. Expected: the spoken words are added after her text, and she can edit them before she taps the main button.
- T5. Speech is denied or not available. Expected: a short message, an "Open Settings" button, and the text box still works.
- T6. She leaves the screen while recording. Expected: recording stops.
- T7. A chip adds text that the request reader does not understand. Expected: Gym, Home, Outside, 10 min and 20 min each set the place or the time in the saved constraints.
- T8. Two place chips or two time chips stay on at the same time. Expected: one place and one time at most. A second tap on a chip removes its words.
- T9. "Continue" shows for an empty project (for example "Untitled Reel" with no idea). Expected: no Continue card for a project with no idea, no cards and no script.
- T10. "Continue" goes away for a project that has idea cards still loading. Expected: it stays, so she can go back to the wait.
- T11. There is more than one main button. Expected: one filled button ("Make today's Reel"); Continue is a smaller card under it.

## Plan step by step and the demo (P)

- P1. "Plan step by step" stays on Today. Expected: it is only in Profile.
- P2. It switches tab without warning. Expected: its button says it opens in Projects, and the sheet closes before the tab changes.
- P3. The demo button opens under the Profile sheet. Expected: the sheet closes, then the demo opens on Today.
- P4. A saved project is deleted or changed by the move. Expected: no saved data changes. Old "Untitled Reel" projects stay in Projects.

## Colors and text (C)

- C1. Text boxes show as black boxes with no edge in dark mode. Expected: a filled box with a visible edge in light and dark mode.
- C2. Olive or sage color stays on app-owned controls. Expected: black, white and neutral gray only. Shot pictures and media keep their color.
- C3. Main button text has low contrast. Expected: white on near-black in light mode, black on near-white in dark mode.
- C4. Text buttons look like plain labels. Expected: a visible button shape on "Change something", "Try again", "Continue" and the Projects row actions.
- C5. The fixed 18-point root font stays, so Dynamic Type does nothing. Expected: system text styles everywhere, so the text grows with the phone setting.
- C6. Large Dynamic Type cuts off text or hides the main button. Expected: text wraps and the page scrolls.

## Wait screen (W)

- W1. The screen shows a pulsing "AI is thinking" animation. Expected: static step marks only.
- W2. The screen shows steps that did not happen. Expected: in D1 the server sends no sub-steps, so only "Finding an idea" shows as the current step until the whole card is ready. D2 adds the real sub-steps.
- W3. No time estimate. Expected: "About 1 minute" while any idea is not ready.
- W4. A ready card waits for the other cards. Expected: each card shows as soon as it is ready.
- W5. No haptic, or a haptic on every card, or a haptic when an old project reopens with ready cards. Expected: one success haptic when the first idea becomes ready in this session.
- W6. A failed card blocks the others. Expected: "Try again" on that card only.
- W7. A reconnect error shows only as a spinner. Expected: the error text and a Reconnect button.

## Idea cards (I)

- I1. She does not see that ideas 2 and 3 exist. Expected: the next card shows at the edge of the screen.
- I2. The position marker does not fill on idea 3. Expected: "1 of 3" text and three idea buttons that show the selected one.
- I3. The position text and the shown card do not agree after a swipe or a tap. Expected: they always agree.
- I4. Cards that are not ready show an empty page. Expected: placeholder cards with the step list.
- I5. Swiping inside a long card scrolls the wrong way. Expected: left and right move between cards; up and down scroll inside one card.
- I6. The first ready card does not show when the first card is still loading. Expected: the view moves to the first ready card once, as before.
- I7. Reduce Motion is on, but cards slide. Expected: no slide animation for jumps.
- I8. Existing identifiers (`mira.today.page.N`, `mira.today.make`, `mira.today.request`) are lost. Expected: all kept, so the old e2e scenarios still work.

## How each is checked

TesterArmy e2e (simulator, demo fixture service, light and dark mode) for T1, T2, T7, T8, T9, T11, P1–P4, C1–C4, W3, W4, W6, I1–I4, I8. Source reading for T3–T6, W1, W2, W5, I5–I7, because the simulator has no microphone, no haptic and no live server steps. C5/C6 at one large Dynamic Type size in the simulator if the e2e tool can set it; otherwise "not verified".
