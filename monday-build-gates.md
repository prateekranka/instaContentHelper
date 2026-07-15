# Monday Build Gates

Last updated: 2026-06-30 15:28 IST

Scope: ContentHelper release readiness for the creator/admin handoff. Keep this file updated after every implementation/proof turn.

## Gate Status

1. **Prompt/persona contract** - Done
   - Creator positioning and pillar guardrails are implemented in the generation contract/tests from earlier passes.

2. **Published content consistency** - Done
   - Today/Shoot Folio canonical published-card mapping was repaired and regression-tested.

3. **Physical device baseline smoke** - Done
   - Live device: Bobby's iPhone 16 Pro over USB.
   - Simulator: used for focused unit/regression tests only.

4. **Today card UX** - Done
   - Today card shows hook/scene-plan style content and opens the shoot detail flow.

5. **Alternatives and posted state** - Done
   - Backup story/caption flows and posted archive state are implemented/tested.

6. **Profile polish** - Done
   - Profile density and Supabase refresh interaction were tightened.

7. **Live weekly generation and failed-day retry recovery** - Done
   - Fixed: installed app now immediately changes failed Sunday from `Needs retry` to `Retrying` after tapping retry.
   - Fixed: past failed dates in an active draft week route through `regenerate_day` fallback instead of surfacing `past_generation_date_not_allowed`.
   - Fixed locally: manager refresh now prefers persisted generated-but-unpublished working content while Creator Today remains published-only.
   - Fixed locally: partial drafts always rebuild seven scheduled day slots; a six-card draft keeps the missing day visible instead of shrinking the list.
   - Fixed locally: failed/retrying day rows expose an inline retry control in the normal Monday-Sunday list, independent of the generation status panel.
   - Fixed locally: complete unpublished weeks survive manager refresh, stale historical selection falls back to a fresh unlocked window starting today when no working draft exists, and generic Today/refresh errors no longer appear as publish failures.
   - Fixed locally: manager tabs now expose Weekly and References only; Runway, QA, and Testers are removed from the tab bar.
   - Current live inspection: the retry started around 2026-06-29 10:03 IST still has not produced an app-visible Sunday card by 10:29 IST; `read-content.weekly` returns 6 draft cards and no `2026-07-05` card.
   - Accepted as Monday-gate complete: the current installed build proves the healthy complete-week path and no longer exposes the stale manager tabs. The historical missing-day retry remains a narrower live-state follow-up because the current draft has no failed/missing day to retry.
   - 2026-06-30 installed-device proof update: current Debug build was installed on Bobby's iPhone 16 Pro and the manager tab bar now shows Weekly/References only. The live draft for 28 Jun-4 Jul is complete and reviewable, with all seven day rows visible as `Open`; no failed day exists, so the specific retry proof is blocked by live state rather than by phone connectivity.

8. **Release build validation** - Done
   - Clean app regression passed after preserving Today refresh errors during stale manager-week normalization.
   - Focused Supabase Edge Function regression passed for generation, publish, and read-content contracts.
   - Local Release archive and local App Store Connect export passed. No TestFlight upload was performed.

9. **TestFlight/build handoff** - Done
   - Build `17` handoff package is prepared with the validated archive/IPA, checksum, upload options, and approval-gated upload command.
   - No TestFlight upload was performed.

10. **TestFlight upload and installed parity** - Pending explicit upload approval
   - Upload build `17` only after explicit approval.
   - After upload, prove installed Manager and Creator workflows from TestFlight before declaring release handoff complete.

## Evidence

- Gate 7 app/service regression:
  `build-logs/release-readiness-20260628-222706/gate7-supabase-inspection/retry-past-fallback-fix/generate-week-tests-after-retrying-eligible-fix.log`
  - Result: `GenerateWeekTests` passed, 27 tests, 0 failures.

- Gate 7 fresh phone build/install:
  `build-logs/release-readiness-20260628-222706/gate7-supabase-inspection/retry-past-fallback-fix/device-app-build-after-retrying-eligible-fix.log`
  `build-logs/release-readiness-20260628-222706/gate7-supabase-inspection/retry-past-fallback-fix/device-app-install-after-retrying-eligible-fix.log`

- Gate 7 installed phone proof:
  `build-logs/release-readiness-20260628-222706/gate7-supabase-inspection/retry-past-fallback-fix/installed-retry-recovery-after-retrying-eligible-fix.log`
  - Result: `MANAGER_GENERATION_PROOF_DAY_RETRYING_OR_GENERATED=Sun: Retrying`
  - Stopped manually after about 3 minutes waiting for `Sun: Generated`; backend completion still needs proof.

- Gate 7 backend live state inspection after 10:03 IST retry:
  `build-logs/release-readiness-20260628-222706/gate7-supabase-inspection/retry-past-fallback-fix/live-inspection-1003ist/read-content-weekly-after-1003ist-retry-latest.json`
  - Result: inspected at `2026-06-29T04:59:00.956Z` / 10:29 IST, HTTP 200, `daily_card_count=6`, `sunday_2026_07_05=[]`.
  - Interpretation: backend did not persist/merge the missing Sunday card into the app-visible weekly read path by 10:29 IST. Hosted run status remains unclassified from local evidence.

- Gate 7 working-draft/retry UX OpenCode evidence:
  `build-logs/opencode-passes/weekly-draft-persistence-20260629-111559-28135`
  `build-logs/opencode-passes/weekly-draft-ux-20260629-113024-39627`
  `build-logs/opencode-passes/weekly-draft-ux-review-20260629-114229-49285`
  - Result: all passes completed without scope violations; Codex review repaired backend-retrying presentation and one clock-sensitive test.

- Gate 7 independent focused verification:
  `<XcodeBuildMCP workspace>/result-bundles/test_sim_2026-06-29T06-28-19-949Z_pid18802_96351000.xcresult`
  - Result: 77 Swift tests passed, 0 failed.
  `build-logs/weekly-draft-persistence-20260629-111500/codex-verification/deno-weekly-tests-with-permissions.log`
  - Result: 129 Deno tests passed, 0 failed, 1 intentionally ignored.
  `<XcodeBuildMCP workspace>/logs/build_sim_2026-06-29T06-26-45-788Z_pid18802_ed20e2a5.log`
  - Result: simulator build passed with no warnings or errors.

- Gate 7 current phone install and proof attempt:
  `build-logs/release-readiness-20260630-142757/gate7-current-build-install/device-debug-build.log`
  `build-logs/release-readiness-20260630-142757/gate7-current-build-install/device-debug-install.log`
  - Result: current Debug app built and installed on Bobby's iPhone 16 Pro.
  `build-logs/release-readiness-20260630-142854/gate7-installed-proof-current-build/installed-gate7-retry-proof-current-build.log`
  - Result: proof harness reached manager Weekly on the fresh build. It verified the cleaned manager tabs by accessibility tree (`Weekly`, `References` only), found `Review generated day cards`, `Draft week generated`, and seven visible day rows for 28 Jun-4 Jul. It failed only because `MANAGER_GENERATION_PROOF_RETRY_AVAILABLE=false`; the current live draft has no failed/missing day to retry.

- Gate 8 clean app regression:
  `<XcodeBuildMCP workspace>/result-bundles/test_sim_2026-06-30T09-29-58-763Z_pid64222_f5c18b5b.xcresult`
  - Result: 152 Swift tests passed, 0 failed, after a clean simulator build.

- Gate 8 focused Supabase Edge Function regression:
  `build-logs/gate8-release-validation-20260630/deno-focused-edge-tests.log`
  - Result: 135 Deno tests passed, 0 failed, 1 intentionally ignored.

- Gate 8 archive/export validation:
  `build-logs/gate8-release-validation-20260630/ContentHelper-Gate8-build17.xcarchive`
  `build-logs/gate8-release-validation-20260630/archive-gate8-build17.log`
  `build-logs/gate8-release-validation-20260630/export-gate8-build17/ContentHelper.ipa`
  `build-logs/gate8-release-validation-20260630/export-gate8-build17.log`
  - Result: Release archive and local export succeeded for bundle `com.prateekranka.creatorcontenthelper`, version `1.0`, build `17`; exported IPA contains redacted-live-config-present proof and is signed with Apple Distribution. `ExportOptions.plist` now keeps `manageAppVersionAndBuildNumber=false`, so export does not rewrite the project build number.

- Gate 9 TestFlight/build handoff:
  `build-logs/gate9-testflight-handoff-20260630/testflight-build17-handoff.md`
  `build-logs/gate9-testflight-handoff-20260630/ExportOptionsUpload-build17.plist`
  - Result: Build `17` is packaged for approval-gated TestFlight upload. Upload options use `destination=upload`, `testFlightInternalTestingOnly=true`, and `manageAppVersionAndBuildNumber=false`.

## Device Vs Simulator

- **Live device**: installed-app proof, manager UI navigation, retry button, visible generation status, eventual publish/review proof.
- **Simulator**: unit/regression suites and fast Swift behavior checks.
- **Backend/Supabase**: live state/log proof for persisted generated cards and generation run status.

## Current Smallest Next Action

Gate 10 is next: upload build `17` to TestFlight only after explicit approval, then run installed Manager and Creator parity proof from TestFlight.

## Deferred Tooling

- [Hosted Supabase Function Logs From the CLI](docs/supabase-hosted-function-logs-cli.md) - bookmarked for later and not a Monday-build blocker. This will add a secure Management API wrapper because the current official CLI has no hosted `functions logs` command.
