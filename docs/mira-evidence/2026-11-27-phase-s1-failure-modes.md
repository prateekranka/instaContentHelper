# Phase S1 failure modes — the 5 state bugs B1–B5 (2026-11-27)

Written before the code. Scope: app only. No new AI calls, no server change, no saved-format change, no deploy. Source: claude/phase-s1-brief.md, claude/state-machines-plan.md and the TLA+ models in claude/state-machines-tla.md.

Words used here:
- "Approved" means that the active script is the approved script (`approvedScriptID == activeScriptID`, and a script exists).
- "Current shot list" means that a shot list exists and it is not out of date (`storyboardIsStale` is false).
- "Can film" means approved and a current shot list.

## Facts checked in the code before the design

- `MiraStage` is not a stored field. `MiraProject.stage` is computed. The saved file does not contain the stage, so a new stage does not change the saved format.
- The server refuses a start with HTTP 409 and `{"error":"rate_limited"}` for two causes: more than 3 active jobs, or more than 10 new jobs in one minute (`mira_enqueue`). A refused start makes no AI call and makes no job row.
- The server answers HTTP 404 and `{"error":"not_found"}` when it has no row for the job ID (and also when the creator is not found).
- A new `MiraGenerationState` case would change the saved format. The fix for B4 does not add one. "Waiting to start" is kept in memory only. The saved job stays `working`.

## B1 — Film from the Projects shot list without approval

- B1.1 The shot list shows "Start filming" when the words are not approved. Expected: it shows "Approve your words", which opens Your words.
- B1.2 `MiraStore.startFilming` sets `startedFilming` when the words are not approved. Expected: it does nothing.
- B1.3 "Mark filmed" changes progress when the words are not approved. Expected: `toggleFilmed` does nothing.
- B1.4 The step-by-step path breaks. "Make shot list" already approves the script, so the shot list must still show "Start filming" there. Expected: no change for an approved project.
- B1.5 "Approve your words" opens a screen with no approve button. Expected: Your words, with "Sounds like me".
- B1.6 After approval from that path, the app opens filming two times or adds extra screens. Expected: one filming screen on top of Your words.

## B2 — The filming screen stays open after the words change

- B2.1 Undo, a restored script or an edit removes the approval, and the open filming screen still shows shots and "Mark filmed". Expected: the screen shows "Your words changed. Approve them first." and one button, "Approve your words". No shot controls, no "Mark filmed".
- B2.2 The check runs only when the screen is first made. Expected: the check is part of what the screen shows, so it updates at once when the project changes, also when the screen comes back from another tab.
- B2.3 "Approve your words" from the filming screen adds a second Your words screen and later a second filming screen. Expected: it goes back to the Your words screen if it is under filming; else it puts Your words in place of filming.
- B2.4 The app reopens on filming with words that are not approved. Expected: `restoredNavigation` drops a filming or Done screen that cannot film. `resumePath` and `todayResumePath` open Your words instead of filming.
- B2.5 The Done screen shows "Open Instagram" with words that are not approved. Expected: the same message and button as filming.
- B2.6 Saved filming progress is lost because of the check. Expected: the check only hides controls. `filmed`, `needsReview`, `shotIndex` and `startedFilming` stay as they are.

## B3 — The stage says "Ready to film" before approval

- B3.1 Right after "Make this one", the Continue card and the Projects row say "Start filming". Expected: stage "Words to approve", next step "Approve your words".
- B3.2 A project that has all shots filmed, but the approval was undone, says "Filming complete" and drops out of Continue. Expected: the approval stage comes before "complete".
- B3.3 The new stage changes old saved projects. Expected: no saved field changes. An old project only gets a different label until she approves.
- B3.4 Continue opens the wrong screen for the new stage. Expected: Continue opens Your words.
- B3.5 Projects without a shot list, or with an out-of-date one, change label. Expected: "Choosing an idea", "Writing the script" and "Planning shots" stay as before.

## B4 — Endless "Mira is making it" after a refused start

- B4.1 "Make today's Reel" starts a second batch while 3 ideas are still being made. Expected: while a batch has ideas in progress, the main button says "See today's ideas" and opens those ideas. No new batch, no new project.
- B4.2 The main button opens an archived project, or a project that only has old finished cards. Expected: only a project that is not archived and has ideas in progress.
- B4.3 A refused start (409 `rate_limited`) shows "Mira is making it" with a spinner. Expected: "Waiting to start…" and a short line that Mira starts it when another idea is done.
- B4.4 The waiting job is never sent again. Expected: it is sent again by itself when one of her jobs ends (succeeded, failed or stopped). As a backup, it is also sent again every 20 seconds while the app is open.
- B4.5 The waiting job is sent again with a new job ID or new input, so the server sees a new job. Expected: the same job (same ID, same input, same revision). No new AI call is made for a refused start.
- B4.6 The waiting backup sends forever. Expected: at most 30 backup sends (about 10 minutes). Then the card shows "Mira is busy. Tap Reconnect to try again." with Reconnect.
- B4.7 Other 409 answers (for example `job_conflict` or `stale_shot_list`) become "waiting". Expected: only `rate_limited` (and 429) means waiting. Other answers keep the old error text.
- B4.8 A stopped or replaced job is sent again from the waiting list. Expected: a send happens only if the job is still the current job of that card or project and is still `working`.
- B4.9 After a relaunch, the waiting list is empty and the card shows "Mira is making it" for ever. Expected: opening the cards sends the start again (existing reconnect). A new refusal puts it back to "Waiting to start…". Known short gap: while that first start is in flight, the card shows "Mira is making it".
- B4.10 A refused start in Your words (for example "Make it simpler" while 3 ideas are in progress) shows "Mira is writing a new version…" for ever. Expected: the same "Waiting to start…" rule for the project job.

## B5 — Stop on a job that the server never accepted

- B5.1 Stop gets 404 `not_found` and the job stays `working`. Expected: the job becomes `cancelled`. The card shows "This idea was stopped." with "Try again". Your words shows "Mira could not finish. Try again?" with "Keep mine".
- B5.2 The stop removes her words or an earlier card output. Expected: the script, the previous card output and all saved work stay.
- B5.3 A waiting job is stopped, and later the waiting list sends it again. Expected: the stop removes it from the waiting list, and a send checks that the job is still `working`.
- B5.4 Other errors on Stop (no network, 503) are shown as stopped. Expected: only `not_found` means stopped. Other errors keep the old message, "Could not confirm the stop".
- B5.5 Known limit: if a start is in flight when she stops, and that start arrives at the server after the stop, the server can make one job that the app does not show. Its result is not used (the app job is `cancelled`). This needs the S4 server work to close fully.

## How each item is checked

- TLA+: MiraReel (B1, B2, B3, B5) and MiraTodayLimit (B4) are changed to match the code. TLC must pass FilmingNeedsApproval, StageRespectsGate, WorkingIsReal, StopAlwaysStops, WordsHasNextStep, NeverOverLimit and AllFinishWithoutReconnect.
- TesterArmy e2e: one scenario for each bug, in light and dark mode. B4 and B5 use two new demo requests: "Demo busy server" (the demo service refuses idea 3 two times with the same answer as a 409 `rate_limited`, and ideas 1 and 2 take about 15 and 27 seconds) and "Demo stop unknown" (the demo service always refuses idea 3, and a stop gets the same answer as a 404 `not_found`).
- `python3 scripts/check-agent-rules.py`, and the Xcode Debug simulator build on the Mac.
- Not checked by these: a real phone, live AI, VoiceOver, large text.
