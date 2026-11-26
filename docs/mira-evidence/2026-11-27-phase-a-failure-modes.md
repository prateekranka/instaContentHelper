# Phase A failure modes (written before code, 2026-11-27)

Scope: "Your words" approval gate, plain words, short-term Done screen. Source: `claude/phase-a-brief.md` and `context/04-ux-review-2026-11-26.md` (P0 1 and 3, P1 9). Owner choice 1A: after changed words are approved, one more AI call (`reviseStoryboard`) updates the shot words.

Verification method: TesterArmy e2e on the simulator with the demo fixture service, plus `scripts/check-agent-rules.py` and a native simulator build. No unit tests.

## Approval gate

| # | Failure mode | Expected behavior | Check |
|---|---|---|---|
| G1 | "Make this one" opens filming with words she did not approve. | It opens "Your words". `approvedScriptID` stays empty until "Sounds like me". | e2e: tap "Make this one", see "Your words", no filming screen. |
| G2 | The app closes on "Your words". On reopen she lands in filming. | Resume returns to "Your words" while the words are not approved. | e2e: relaunch on "Your words". |
| G3 | An old project that was approved and filming before Phase A loses its approval or progress. | Saved approval, filmed shots and position stay as they are. | e2e: old saved project reopen (existing scenario). |
| G4 | She taps "Sounds like me" two times fast and two filming screens open. | One navigation push. The button is disabled while a request runs. | Source review; e2e single screen after tap. |
| G5 | She taps "Sounds like me" while "Make it simpler" is still running. | "Sounds like me", "Make it simpler" and "Change it" are disabled while a request runs. Cancel is available. | e2e on demo (fixture delay) where possible; source review. |
| G6 | "Make it simpler" or "Change it" fails (network, provider, validation). | Her current words stay. Plain error "Mira could not finish. Try again?" and a Try again button. | e2e: demo failure trigger if available; else source review. |
| G7 | The new version replaces her words without approval. | The new version shows as "Mira's new version" with "Use this" / "Keep mine". | e2e: tap "Make it simpler", see both buttons. |
| G8 | "Use this" deletes the old words. | The old script stays in `scripts` as a revision. | Source review of `apply`; e2e: Undo returns old words (if shown). |
| G9 | "Change it" sends an empty text. | The send button is disabled until the text has words. | e2e. |
| G10 | Words change, but shots keep the old words. | On "Sounds like me", if the shot list is stale, Mira makes one `reviseStoryboard` call and applies it, then opens filming. | e2e on demo: after "Use this" + "Sounds like me", filming is not stale. |
| G11 | The shot update call fails after approval. | Approval stays saved. She sees "Mira could not update your shots. Try again?". Filming does not open with stale shots. | Source review; demo if a trigger exists. |
| G12 | A late AI answer for an older version replaces newer words. | Existing input-revision checks reject it. | Existing contract; source review. |
| G13 | Extra AI calls happen without a tap. | Only "Make it simpler", "Change it" and (after changed words) the shot update make calls. | Source review. |
| G14 | AI consent is not given. | The existing consent path shows; no call is made. | Existing behavior; source review. |

## Done screen

| # | Failure mode | Expected behavior | Check |
|---|---|---|---|
| D1 | No ending after the last shot. | When all shots are filmed, a "Finish" button opens the Done screen. | e2e. |
| D2 | The count is wrong. | "N clips filmed" counts filmed shots of the current shot list. | e2e on 3-shot demo. |
| D3 | The caption is empty or missing. | Show the caption of the approved words. If empty, hide Copy caption and say "No caption yet". | Source review. |
| D4 | Copy caption copies nothing. | The caption goes to the clipboard and the button says "Copied". | e2e (label change). |
| D5 | Instagram is not installed. | "Open Instagram" opens the Instagram App Store page. Mira never posts. | Source review; simulator has no Instagram (fallback path). |
| D6 | The clip order does not match the shots. | The list is the shot list in order, with a check mark for each filmed shot. | e2e. |
| D7 | Returning to Done after relaunch loses the screen. | Filming resume still works; Done opens again from "Finish". | e2e relaunch. |

## Plain words

| # | Failure mode | Expected behavior | Check |
|---|---|---|---|
| W1 | An old engineering label is still visible. | All 9 rows of review item 9 are changed. | grep + e2e text checks. |
| W2 | e2e scenarios break because labels changed. | Update the journey to the new labels in the same change. | e2e. |
| W3 | Removing "Read constraints from my request" removes a needed feature. | The constraints form stays editable by hand. | Source review. |
| W4 | Accessibility identifiers are missing or duplicate. | New main buttons have unique `mira.*` identifiers. | `check-agent-rules.py`. |

## Not verified in Phase A

Physical device, live AI quality of "Make it simpler" and "Change it", VoiceOver order, large Dynamic Type, opening the real Instagram app.
