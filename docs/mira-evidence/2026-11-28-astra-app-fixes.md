# Astra app fixes

## Failure modes and planned checks

| Finding | Failure mode to check |
| --- | --- |
| M01 | Undo hides filmed marks and moves the current shot on the same list. |
| M02 | A missing fixture session or marker lets a sample test stop an account request. |
| M03 | Undo leaves the second card’s title, idea or filming constraints on the first card’s plan. |
| M04 | Updating stale shots approves changed words without the creator’s choice. |
| M05 | Filming displays unapproved dialogue, or rejects a valid script whose spoken text starts with the hook. |
| M06 | A proposal made in Projects enters filming without Use this. |
| M13 | A refused request submits its words after the creator withdraws AI permission. |
| M14 | A saved request sends one account’s words from a second account. |
| M15 | A debug permission override unlocks real generation. |
| M16 | Opening Today filming changes the Projects section for that Reel. |
| M17 | A rejected update loses its Retry action. |
| M18 | Speech permission becomes allowed but the mic button cannot request undecided microphone access. |
| M19 | Instagram permission recovery has no connection action. |

## Fix and regression evidence

| Finding | Fix | TesterArmy scenario | Result before device acceptance |
| --- | --- | --- | --- |
| M01 | Undo restores approval while keeping filmed marks, review marks, and the current shot for the same storyboard ID. | B2 marks two shots, undoes approval, relaunches, approves, and checks that shot three and both marks remain. | Signed build and bounded model pass. |
| M02 | The sample suite requires a named session. Each cleanup checks the fixture marker before opening a batch. Fixture mode has no live generation service for real projects. | Run B5 without a session. Run the normal B5 with the fixture marker and check that its sample idea stops. | The no-session run exited 2 before device startup at 05:50:44 IST. |
| M03 | A card checkpoint saves the previous title, idea ID, and constraints with the script and shots. | Make two cards with different locations and filming times. Undo the second and inspect the title, selected idea, and plan explanation. | Signed build passes. |
| M04 | Both Update shot list buttons route unapproved words to explicit approval. | Apply revised words, open Shots, tap Update shot list, and check that Sounds like me appears before generation. | Signed build and bounded model pass. |
| M05 | Start, filming, progress controls, and Done require a storyboard whose dialogue matches the approved script. | The D2 picture and filming case uses the existing [recorded live response](../../tests/fixtures/mira-recorded-today.json) with the hook already at the start of `spoken`. Other D2 cards cover whitespace, curly and straight quotes, and a silent shot. A separate sample applies different dialogue and checks an already open filming screen. | Signed build passes. Native comparison remains to be exercised. |
| M06 | Your words tracks the exact ID it starts. Projects proposals need Use this. | Start a Projects proposal, return to Your words, wait for the reply, and verify the current board stays active until Use this. | Signed build and bounded model pass. |
| M13 | Real starts re-read permission before sending. A refused request that later loses permission becomes stopped with saved input. | The fixture returns busy before simulating permission withdrawal on the retry. Check the stopped card and saved-words message. | Signed build passes. The fixture covers the state transition without changing live permission. |
| M14 | Save the creator ID with the job. An account mismatch leaves the request saved for its owner. An unowned legacy job performs a status-only lookup. | Relaunch the sample notebook with a second synthetic account and verify the saved unsent card shows This belongs to another account. | Signed build passes. |
| M15 | Live services always use persisted account consent. The debug override uses isolated fixture defaults. | Launch the paired build with each debug override, then read the existing Allowed status in Profile. The test does not generate. | Signed build passes. |
| M16 | Each tab remembers its own project section. Saved Projects sections and active Today destinations use the existing file keys. | Select Projects Script and open Today filming for the same Reel. Switch tabs and relaunch. | Signed build passes. |
| M17 | A rejected shot update keeps Try again available and hides the change controls. | Reject the first sample update, dismiss the alert, and retry to reach filming. | Signed build passes. |
| M18 | A return from Settings with speech allowed and microphone access undecided makes the microphone action available. | Run the existing denied-speech test without changing permissions. This phone cannot exercise the Settings recovery branch with its current denial. | Signed build passes. |
| M19 | Permission needed offers Connect again through the existing connection step. A cancelled connection shows the previous result. | Open the permission-needed fixture, tap Connect again, and verify the fixture-only response. | Signed build passes. |

## Saved state

The library version and existing keys stay the same. M03 adds one optional field to `MiraUndo` for the prior card context. Undo can restore that context after relaunch. M14 adds one optional `creatorID` to `MiraJob` so an unsent request keeps its owner across relaunch. New data remains readable by older builds. Old saved jobs can read existing server status. Jobs without known ownership cannot send their text as a new request. The automatic shot-update job ID lives in memory. After relaunch, a completed update can be reviewed in Projects.

## Reproduction and local checks

- Source baseline `0530a3f92a20692c1c5d1ddafa514b9154b777f0` matched remote main on 28 November. The branch is local.
- `python3 scripts/check-agent-rules.py` passed all eight groups. `python3 scripts/prove-agent-rules.py` rejected 19 example violations. `python3 scripts/check-state-machine-doc.py` matched 71 cases across 11 enums. `git diff --check` passed. See `work/evidence/astra-app/rules.log`.
- `JAVA_BIN=/opt/homebrew/opt/openjdk/bin/java TLA_OUTPUT_DIR="$PWD/work/evidence/astra-app/tla" bash specs/tla/run.sh` passed five positive models and 13 expected negative cases. The Reel model checked 2,669,648 distinct states. See `work/evidence/astra-app/tla-java.log`.
- Xcode 27.2 (`27B52`) and Swift 6.4.2 built and signed `ContentHelper.app` for Bobby’s iPhone. The build passed at 05:55:50 IST. Code-signature verification passed. The runtime presence check found all five values without recording their contents. See `work/evidence/astra-app/build-verify.log` and `device-runtime-presence.txt`. Xcode 26.3 is not installed in this environment.
- TesterArmy 0.15.2, agent-device 0.21.20, and Node 22.23.2 targeted Bobby’s iPhone 16 Pro over USB on iOS 27.2.1. `work/run-astra-app-phone.sh` uses the supplied signed runner setup and a task-owned driver directory. It installs only when the named pre-install Keep report passes.
- For the D2 cases, start `node tests/fixtures/mira-d2-server.mjs` with `MIRA_D2_FIXTURE_PORT=18817` and the phone-reachable HTTPS fixture URL in `MIRA_E2E_D2_ENDPOINT`. The local runner supplies the matching control origin and the named sample-library session.

```sh
bash work/run-astra-app-phone.sh keep-before keep
bash work/run-astra-app-phone.sh install install keep-before
bash work/run-astra-app-phone.sh keep-after-install keep
bash work/run-astra-app-phone.sh sample sample
bash work/run-astra-app-phone.sh consent consent
bash work/run-astra-app-phone.sh live live --grep '^Astra live smoke'
bash work/run-astra-app-phone.sh keep-after-tests keep
```

The live smoke reserves three text requests for one Today batch. Keep its ledger if the run needs a retry. Sample tests use local text and picture fixtures. The real Instagram reconnect and any permission changes are outside the test scenarios. Screenshots from runs go to `work/evidence/astra-app/shots/` with flat filenames.

## Bobby’s iPhone

All times are on 28 November 2026 in India Standard Time. Each Keep check requires Profile to show Allowed and Instagram Insights to show `@prateekranka` on a normal launch.

| Gate or retry | Start IST | Result |
| --- | --- | --- |
| Pre-install Keep | 05:43:19 | `device.openApp` timed out after 25 seconds. The runner log reports an XCTest automation-mode timeout. |
| Pre-install Keep, longer launch window | 05:49:52 | `device.openApp` timed out after 60 seconds. The runner log reports the same XCTest error. |
| Pre-install Keep, fresh runner | 05:56:23 | The fresh runner timed out during preparation. The app launch then returned, but the snapshot failed before the tab bar check. The driver rejected automatic cleanup of the task-owned DerivedData path. |
| Pre-install Keep, scoped runner cache | 05:58:11 | A separate session held the phone. TesterArmy stopped before launch. |

The wired device stayed paired and reported a compatible Developer Disk Image. The hardware driver log identifies `com.apple.dt.XCTest.XCTFuture` code 1000. The diagnostic excerpts are in `work/evidence/astra-app/xctest-automation-errors.log`. The driver stores setup and execution errors in its runner log. [Agent Device runner diagnostics](https://github.com/callstack/agent-device/blob/main/website/docs/docs/commands.md#prepare-apple-runner)

The phone remained claimed by the separate session at 06:03:06 IST. This task initiated no in-place install, live text requests, or live pictures. It made no permission changes. The pre-install Keep check did not verify either account value. The post-install and post-test Keep checks, B1–B5, S2/S3/D2, the new phone scenarios, and the live smoke await device access. The sample collection found 31 scenarios. The consent collection found five scenarios. The no-session refusal is the only executed regression result. The flat phone screenshot folder is empty.
