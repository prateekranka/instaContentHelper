# Mira Phase E2 and E3 integration

## Source and branches

| Local branch | Commit | Change |
| --- | --- | --- |
| `claude/mira-e2e3` | `c53c9ad5c701bde3148f6f330dff3e9241f4d521` | Core layering fix |
| `claude/mira-e2e3` | `fe5439a222008af8871738d0c3e84bcd2c067054` | E3 merge and reviewed checklist wiring |
| `claude/mira-e1-cifix` | `7eac63bab4e3a5d18464f6973f1c0f2cb4f6a165` | Same layering patch on E1 alone in `../mira-e1-cifix` |

The integration starts from [E2 `c4441ad`](https://github.com/prateekranka/instaContentHelper/commit/c4441ad47fa15007a384dc80015e65f7a7dcd9f7) and merges [E3 `22a0ffd`](https://github.com/prateekranka/instaContentHelper/commit/22a0ffd5977aece98488c99279e03a5ef7cf2031). Both contain [E1 with Astra `2a1da96`](https://github.com/prateekranka/instaContentHelper/commit/2a1da964882b6180bf748e2dffec87ed226b17fa). GitHub confirmed those three source commits. Both new branches remain local. The E1-only fix and its integration counterpart have the same stable Git patch ID.

## Failure modes and repairs

- Core could fail to compile if fixtures read App launch flags or the store catches an App-only error. The unmodified E1 checkout reproduced that failure with all three missing symbols. The app now supplies fixture-session and creator ID values. Core owns `AIConsentRequired` and preserves the error message. Delayed fixture responses keep the injected settings for Astra’s permission withdrawal, account ownership and storyboard checks.
- A merge could drop app sources, navigation, or saved fields. Regeneration with XcodeGen 2.45.3 kept both phases and the embedded Share Extension. The Debug builds include both feature sets. My Brand keeps its E2 interview and brand document. Deals keeps its E3 brief review and tracker. Home can show an E2 pick and E3 deal cards together.
- A pick could send the wrong brief or fail to open the generated Reel when its storyboard uses a checklist revision. `pickIdea` now uses E3’s read-only `activeDealChecklist`. The most recently confirmed unpaid deal supplies its reviewed items. An empty checklist or no active deal omits the key. Draft deals and legacy Reel briefs stay out of the request. When the user accepts a pick, Mira checks the deal and checklist again. If the deal changed, Mira resets the pick and asks the user to request a new one. The generated Reel copies the reviewed brief and carries the same requirement IDs and revision into its shot list.

## Merge conflicts

| Files | Resolution |
| --- | --- |
| `project.pbxproj` | Regenerated from the E3 project spec with both sets of sources. Kept the existing app scheme and package pins. |
| `MiraPersistence.swift` | Kept four optional document fields from the two parents. |
| `MiraStore.swift` | Kept both phase extensions and reused the E3 active checklist for E2 picks. |
| `MiraReelProgress.swift` | Kept both phases’ actions and labels. |
| `MiraGenerationService.swift` | Kept E3’s typed brief transport, the Astra authorization and recovery path, and both daily limit messages. |
| `MiraRootView.swift` | Combined E2 account and pick state with E3 deal sheets, Home cards and shared-brief import. |
| `mira-journey.e2e.ts` and `mira-live-journey.e2e.ts` | Kept both suites. Added a sample case for the sent checklist, both Home cards and the mapped shot list. The existing E2 sample case checks omission. The E3 live case checks the shot list and reserves picture calls under the shared cap. |

The version 2 document keeps the optional keys `brandDoc`, `instagramResultsPermission`, `deals` and `dealBriefDraft`. This is additive. Older documents can omit all four keys. Earlier decoders can read the document and skip unknown keys. Saving it again in an older build can drop keys that build does not know. This compatibility assessment uses the decoders in source. Runtime reopen and downgrade checks remain blocked by the phone passcode.

## Checks

Check times use IST on 2026-11-28. The evidence directory is `work/evidence/mira-e2e3-integration/20261128T020230Z.0k71pK/`. The global evidence volume was unavailable. The worktree directory holds the logs, TLC traces, redacted build output and Xcode result bundles.

| Check | Result |
| --- | --- |
| [PR #47 Swift job](https://github.com/prateekranka/instaContentHelper/actions/runs/46093339366/job/140819071238), unmodified E1 | Reproduced at 07:38:28 on Ubuntu 24.04 x86_64 and Swift 6.4.1. Exit 1. Core could not resolve `DebugLaunchFlags`, `DebugLaunchConfiguration` or `AIConsentRequired`. See `swift-e1-baseline.*`. |
| Linux compile, E1-only fix | Passed at 07:39:42. Swift build time 38.40 s. See `swift-e1-fixed.*`. |
| Linux compile, E2 and E3 | Passed at 07:41:16. Swift build time 62.21 s. See `swift-e2e3.*`. |
| Agent rules | 8 of 8 passed on each branch. On integration, the proof rejected all 19 historical cases. |
| State-machine document | 19 Swift enums, 104 cases and zero mismatches. |
| TLA+ | TLC 1.7.4 passed 5 positive and 13 expected-negative configurations. `MiraReel` had 2,869,783 distinct states. The merge leaves the model inputs unchanged. |
| E1 generic simulator build | Passed at 07:41:02. Debug app contains arm64 and x86_64. |
| Integrated generic simulator build | Passed at 07:42:12. Debug app contains arm64 and x86_64 and embeds the Mira Share Extension. |
| Integrated generic device build | Passed at 07:41:19. The app and extension signatures and App Group verified locally. All five runtime configuration keys are present in the built app. |
| TesterArmy collection | e2e 0.15.2 and Node 22.23.2 collected 47 sample, 15 live, 5 consent and 1 Keep scenario. The sample count includes the new E2/E3 case. Collection started no engine. |

The Linux job pins Swift 6.4.1 in `.github/workflows/mira-core-checks.yml`. The local Docker image uses the same Ubuntu release, archive and checksum. A minimal base image required `libncurses6` and `libsqlite3-0` before Swift could start. The helper copies the Core package inputs from a read-only mount and runs the workflow command below. Colima stopped after both repaired builds.

```sh
MIRA_SWIFT_BIN="$PWD/work/swift/usr/bin/swift" bash scripts/mira-core-check.sh
python3 scripts/check-agent-rules.py
python3 scripts/prove-agent-rules.py
python3 scripts/check-state-machine-doc.py
JAVA_BIN=/opt/homebrew/opt/openjdk/bin/java bash specs/tla/run.sh
MIRA_E2E_FIXTURE_SESSION=e2e3-collect npx --no-install e2e list --config e2e.mira.config.ts
MIRA_E2E_E3_LIVE=1 MIRA_E2E_E3_PICK_READY=1 npx --no-install e2e list --config e2e.mira-live-journey.config.ts
```

The local Xcode toolchain was 27.2 (`27B52`, Swift 6.4.2). Both generic builds used the `CreatorContentOS` scheme. The simulator builds disabled signing. The device build used the Mac’s existing signing state. Xcode 26.3 compatibility and GitHub Actions on the repaired head remain pending.

## Fix2 phone scope

E2 and E3 share the same text and picture ledger. The E2 live journey reserves up to five pictures for its selected pick. If fewer than five picture slots remain, record the E3 live pick as **not run (picture limit not provable)** before launch. The E3 brief reading case needs no pictures. The Notes share extension case is outside this phone run because it completes a share from Notes.

## Phone and tracker

The XCTest passcode blocks install, Keep, runtime E2E, native sharing, screenshots and live checks. Live counts were zero across `brandDoc`, `pickIdea`, `dealBrief`, other text and pictures. The sample checklist scenario needs the existing D2 fixture endpoints. The built-in demo fixture still declines to verify brief mappings. VoiceOver, large text and dark mode remain unverified. The existing Insights endpoint still lacks best-post patterns.

The merged E2 live ledger caps the two phases at 2 `brandDoc`, 4 `pickIdea`, 10 pictures and 4 other text calls. Within that limit the E3 live ledger caps its cases at 3 `dealBrief` and 2 `pickIdea` submissions. Each Make reserves up to five pictures. The live checklist case requires a confirmed active deal and the E3 opt-in flags.

The public tracker confirmed updates for MIRA-037 at `2026-11-28T02:12:50.690Z`, MIRA-038 at `2026-11-28T02:12:51.114Z` and MIRA-039 at `2026-11-28T02:12:51.536Z`. The three cards are Working with the phone blocker and verified remote source links. [Mira tracker](https://mira-build-progress-production.up.railway.app)

## Fix2 iPhone result for PR #48

**RESULT FAIL**

Mira showed the Instagram results permission prompt in the E2 Not now fixture. The test supplied `-MCO_QA_INSTAGRAM_RESULTS not-now`. The app calls `DebugLaunchConfiguration.value` for that key, but the Debug allowlist omits it. The lookup returns nil and the app asks for a choice. This is an app fault in the Debug fixture path. The phone sequence stopped before PR #49. [App launch configuration](../../CreatorContentOS/App/DebugLaunchConfiguration.swift#L10) · [Mira permission lookup](../../CreatorContentOS/Mira/Views/MiraRootView.swift#L318)

The signed Debug build from `094b954` installed in place. The app source is identical at the later test-only commit `4635d95`. Xcode 27.2 (27B52), TesterArmy e2e 0.15.2, agent-device 0.21.20 and Node 22.23.2 used the USB iPhone 16 Pro. Both Keep checks confirmed AI permission Allowed and a connected Instagram account.

The E2 interview reached the confirmed document after two test repair rounds. The first attempt failed while entering the next answer. The second attempt reached the document editor but the keyboard concealed the confirm button. The third attempt confirmed the edited document. XCTest returned 14 nodes with its saved identifier, so the test stopped before the relaunch check. The separate ready/ask case found the visible Make button under the Home card identifier.

| Scenario | Result | Start IST | Duration | Evidence path |
| --- | --- | --- | --- | --- |
| Keep before install | PASS | 12:45:20 | 104.68 s | `pr48-keep-before/report.json` |
| Install in place | PASS | 12:47:06 | 2 s | `pr48-install.command.log` |
| Keep after install | PASS | 12:47:20 | 113.19 s | `pr48-keep-after-install/report.json` |
| E2 interview, first attempt | FAIL — text-entry verification | 12:49:28 | 101.79 s | `pr48-sample-e2e3-1-attempt-1/report.json` |
| E2 interview, second attempt | FAIL — keyboard obscured the confirm control | 12:52:05 | 287.35 s | `pr48-sample-e2e3-1-attempt-2/report.json` |
| E2 interview, third attempt | FAIL — saved document identifier matched 14 nodes | 12:58:11 | 273.39 s | `pr48-sample-e2e3-1-attempt-3/report.json` |
| E2 Instagram permission, disconnected / ask | PASS | 13:03:25 | 11.51 s | `pr48-sample-e2e3-owed-1/report.json` |
| E2 Instagram permission, ready / ask | FAIL — Make button identifier differed | 13:03:37 | 46.71 s | `pr48-sample-e2e3-owed-1/report.json` |
| E2 Instagram permission, ready / Not now | FAIL — the app ignored the Debug override and showed the prompt | 13:05:04 | 30.56 s | `pr48-sample-e2-not-now/report.json`, `pr48-instagram-override-source.txt` |
| Remaining sample, read-only consent, live and Keep after tests | Not run after the app fault | — | — | — |

Live AI counts were **0 text requests and 0 pictures**. The D2 fixture stopped. The final phone claim count was zero and the Tailscale routes matched the initial list.

### Fix2 checks still open

- The E2 brand document after relaunch, the remaining E2 and E3 samples, the shared sample suite, read-only consent, live generation, and Keep after tests.
- Production Instagram permission behavior. The confirmed fault concerns the Debug launch override.
- Phone behavior for PR #49.

Local evidence folder `/Users/prateekranka/.codex-runs/mira-fix-phone-20261128/evidence/fix2/20261128T050857Z.05oz1v`.

## Fix3 keyboard and iPhone result for PR #48

**RESULT BLOCKED**

The ordered phone sequence stopped during the pre-install Keep check on PR #47. TesterArmy could not start its XCTest runner. Its `xcodebuild build-for-testing` command failed and reported a provisioning-profile hint. PR #48 did not start its phone run.

The source head `4f6de4b` passed all six GitHub checks. All eight agent rule groups, the 19 historical rule proofs and both local Xcode builds passed for the app source at `3f703d3`.

| Scenario | Result | Start IST | Duration | Evidence path |
| --- | --- | --- | --- | --- |
| Keep before install, in-place install and Keep after install | Not run | — | — | `fix3-pr47-keep-before/report.json` |
| Sample scenarios, read-only consent, live and Keep after tests | Not run | — | — | `fix3-pr47-keep-before-retry/report.json` |

Live AI counts were **0 text requests and 0 pictures**. No live ledger was created. The final phone claim count was zero. No D2 fixture started. The Tailscale route list matched the initial list.

### Fix3 checks still open

- The physical iPhone install and account checks.
- Keyboard behavior, saved state and live journeys on the phone.
- Large Dynamic Type and VoiceOver behavior.

Local evidence folder `/Users/prateekranka/.codex-runs/mira-worker-1-20261128/evidence/fix3/20261128T074755Z.yiUedN`.


## Fix3b physical iPhone result for PR #48

**RESULT BLOCKED**

The PR #48 physical iPhone run did not start. The ordered phone sequence stopped at 14:42:03 IST on PR #47. After XCTest tapped **Stop this idea** in the S3 server-backoff case, the menu stayed open and the card stayed at **Waiting to try again**.

The PR #47 test-only keyboard changes were carried forward at `c2993a46f19bf2005a56cdb84575f994150f9b01`. The eight agent-rule groups and 19 proof checks passed on the carry-forward. GitHub confirmed the carry-forward commit on the PR branch.

| Scenario | Result | Start IST | Duration | Evidence path |
| --- | --- | --- | --- | --- |
| Signed device build and Keep before install | Not run | — | — | `fix3b-pr47-sample-remaining/report.json` |
| In-place install and Keep after install | Not run | — | — | `fix3b-pr47-sample-remaining/report.json` |
| Sample cases, five read-only consent checks, live and Keep after tests | Not run | — | — | `fix3b-pr47-sample-remaining/report.json` |

Live AI counts for PR #48 were **0 text requests and 0 pictures**.

### Not verified

- The signed device build at this revision and all physical iPhone behavior for this PR.

Final phone claims were zero. The fix3b D2 fixture stopped and Tailscale routes matched the baseline.

Local evidence folder `/Users/prateekranka/.codex-runs/mira-worker-3-20261128/evidence/fix3b/20261128T081057Z.9HGv7X`.

## PR #48 simulator result

**RESULT BLOCKED** on 28 November 2026 from 14:33 to 15:36 IST. Across 47 sample scenarios, 22 passed, 23 ended on test or runner failures, and two were phone only. The Debug build of `c2993a4` passed on sim-guard iPhone 1, iPhone 18 Pro with iOS 27.2. TesterArmy 0.15.2 used Light mode, the `worker-4` fixture session, and a local HTTPS D2 fixture.

The E2 interview passed with speech denied, all six answers typed, and the edited brand doc present after relaunch. The disconnected and ready / Ask permission cases passed. Not now and Allow each saved the expected guidance before XCTest interrupted the next check. The Home pick test could not locate the request field by its identifier. Deals displayed the parsed brand, fee, deadline, six deliverables, and disclosure. Its tests stopped before reaching controls below the captured viewport.

The shared E1 archive test passed after two test repair rounds. XCTest continued to interrupt the resume flow and several regression cases. The other sample passes include damaged-library recovery, edited-brief review, server-backoff stop, denied-speech typing, stale-shot approval, account ownership, and rejected-update retry. The later live E1 scrolling change at `e24a20a` landed after sample collection. [Verified archive test fix](https://github.com/prateekranka/instaContentHelper/commit/f40465e9429bd1ca6fac178dac0568fcd57b3353)

Phone only covers the five saved-account consent checks, the legacy paired-account consent case, signed Notes sharing, Photos with device clips, the physical keyboard, and live generation. The simulator made **0 live text requests and 0 live pictures**. The simulator driver and D2 fixture stopped.

The scenario table and start times are in `work/sim-result-pr48.md`. TesterArmy reports, failure details, screenshots, videos, and the redacted build log are in `work/evidence/sim-48/`.
