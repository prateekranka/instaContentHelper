# Mira E4 and E5 integration

## Source

Branch `claude/mira-e4e5` merges E5 Insights into E4 Reel delivery. The merge is
`e0155836240475dd12b3868cac5f24a86d4482b5`. GitHub returned the exact refs for
both parents and the shared E2 and E3 base. The integration branch stays local.

| Source | Verified GitHub commit |
| --- | --- |
| E4 Reel delivery | [`c42da19`](https://github.com/prateekranka/instaContentHelper/commit/c42da19f51a68c45007c1fa013c9354d16f626db) |
| E5 Insights | [`5b50a86`](https://github.com/prateekranka/instaContentHelper/commit/5b50a86de5bc8c0505c967f1221a88ecd4595ac3) |
| E2 and E3, with E1 and Astra | [`c6e5822`](https://github.com/prateekranka/instaContentHelper/commit/c6e58221f255f52c4f0877a3206ef34b06ca5e5e) |

## Conflicts and compatibility

| Git conflict | Resolution |
| --- | --- |
| `CreatorContentOS.xcodeproj/project.pbxproj` | Regenerated with XcodeGen 2.45.3. Kept all E4 sources and clip fixtures and added all three E5 sources. Preserved the existing shared scheme and package pins. |
| `MiraGenerationService.swift` | Kept E4 `briefCheck` and `brandNote` and E5 `dailyNote`. All three use the shared Astra authorization path. The delivery requests keep their paired-account check. |
| `mira-journey.e2e.ts` | Kept four E4 sample scenarios and ten E5 sample scenarios. |
| `mira-live-journey.e2e.ts` | Kept three E4 and one E5 live scenario. E5 keeps its separate request ledger. The other live journeys suppress the automatic note. |

- Home keeps the pick card, deal cards, How you’re doing, Mira noticed and What worked. E5 actions use the existing consent and review gates. E4 keeps clip import and matching, local join and playback, brief review and approved fixes, the Instagram share sheet and the WhatsApp draft and confirmations.
- Confirming a post records **Posted**. The E5 response adds captions and counts. A verified **You’re live** state requires an identity or link for the exact Reel. These captions and counts cannot establish that match. The brand tracker still advances after the creator confirms sending.
- The document stays at version 2. The merge adds no saved keys over E4. Relative to the shared base, E4 adds only the optional project keys `dealID` and `delivery`. E5 state stays in memory. Earlier decoders can skip those keys. Saving again in an earlier build can drop unknown keys. This is a source assessment. The passcode blocks device reopen and downgrade checks.
- `instagram-insights` keeps its response states, metric fields, legacy saves totals and device authorization. The optional `snapshots` field includes the weekly baseline and current result when available. The current result can include up to five ranked recent posts. With only posts, the wire response keeps the old `no_data` fields and adds the posts for the new app. An HTTP 400 on the expanded Meta media request falls back to the legacy saves query.
- [State diagrams and tables](../state-machines.md) include both phases. Existing TLA+ models cover approval, job transitions, picture reservations and Today limits. The merge changes no rule in those models.

## Verification

Times are India Standard Time on 2026-11-28. Durable local evidence is under
`work/evidence/mira-e4e5-integration/20261128T030453Z.dxqSOI/`, called
`$MIRA_EVIDENCE` below. The shared evidence volume was unavailable.

| Check | Result | Evidence under `$MIRA_EVIDENCE` |
| --- | --- | --- |
| Linux Swift CI reproduction | Passed at 08:46:36 on Ubuntu 24.04.5 x86_64 with the CI-pinned Swift 6.4.1 and verified archive checksum. Core build time was 49.35 s. | `linux/Dockerfile`, `linux-image-build.*`, `linux-swift.*` |
| Deno `ci:backend` | Passed at 08:39:12 with Deno 2.8.1. Type checks only. | `deno.*` |
| Mira API E2E | 46 passed and 2 hosted cases skipped at 08:41:17. TesterArmy 0.15.2, Node 22.23.2 and Supabase CLI 2.121.0. The run used the seeded local Supabase stack and simulated AI providers. | `api-seeded-reports/`, `api-seeded.*`, `seed-api.sql` |
| Instagram Insights API E2E | 3 passed at 08:45:24. The real Edge handler used local PostgREST and simulated Meta replies. The checks covered device authorization, baseline and ranking, legacy `no_data` fields with posts, and the legacy saves fallback. | `insights-reports/`, `insights-final.*`, `seed-insights.sql`, `insights-fixture.ts`, `insights.e2e.ts` |
| Agent rules | 8 of 8 passed at 08:39:14. The proof rejected all 19 historical cases at 08:39:44. | `check-agent-rules.*`, `prove-agent-rules.*` |
| State-machine document | Passed at 08:39:45. 26 Swift enums, 137 cases and zero mismatches. | `check-state-machine-doc.*` |
| TLA+ | TLC 1.7.4 passed at 08:40:19. Five positive and 13 expected-negative configurations. The Reel model covered 2,869,783 distinct states. | `tla.*`, `tla/` |
| Generic iOS device Debug build | Passed at 08:39:47. The arm64 app and embedded Share Extension signatures verified. All five required runtime settings are present. | `build-device.*`, `native-artifacts.txt` |
| Generic iOS Simulator Debug build | Passed at 08:40:32. The app contains arm64 and x86_64 and embeds the Share Extension. | `build-sim.*`, `native-artifacts.txt` |
| TesterArmy collection | All eight tracked files collected. 61 sample, 19 live journey, 1 standalone live, 5 consent, 1 Keep, 1 install, 48 Mira API and 2 tracker cases. Collection starts no engine. | `collect-e2e.mira*.out`, `collect-tracker-verified.out` |

The isolated Supabase stack stopped at 08:46:10. The Colima profile stopped at
08:47:36. Both local stores were preserved.

The first local Mira API run had 19 failures because the fresh database lacked
its fixture workspace, creators and member. The seeded setup passed. The
Insights fixture also needed explicit local service-role table grants and
idempotent seed rows. Those grants apply only to the isolated copy of Supabase
and are outside the deployment. A matcher unavailable in TesterArmy 0.15.2
was replaced with an equality assertion on the returned saves metric.

Xcode 27.2 build `27B52` and Swift 6.4.2 built the `CreatorContentOS` scheme.
The device build used local signing. The simulator build disabled signing.
Neither build used a device or booted a simulator. Xcode 26.3 CI and app
runtime are pending. Phone install, Keep checks, native E2E, Photos, Instagram,
WhatsApp, screenshots and live checks are blocked by the XCTest passcode.
This integration made zero live AI requests. The E4 and E5 phone plans retain
their separate caps. [E4 phone plan](2026-11-28-phase-e4.md) · [E5 phone plan](2026-11-28-phase-e5.md)

### Reproduce the local checks

Run from the integration checkout with the task evidence path set. Use the
isolated `mira-e4e5-local` Supabase config and local credentials only. The
evidence directory contains the isolated configuration, SQL seed files, build
wrapper and Insights fixture. Keep shell tracing off.

```sh
deno task ci:backend
python3 scripts/check-agent-rules.py
python3 scripts/prove-agent-rules.py
python3 scripts/check-state-machine-doc.py
JAVA_BIN=/opt/homebrew/opt/openjdk/bin/java TLA_OUTPUT_DIR="$MIRA_EVIDENCE/tla" bash specs/tla/run.sh

colima start --profile mira-s4-20261127
export DOCKER_HOST="unix://$HOME/.colima/mira-s4-20261127/docker.sock"
docker build --platform linux/amd64 -t mira-e4e5-swift-ci:6.4.1 "$MIRA_EVIDENCE/linux"
docker run --rm --platform linux/amd64 -v "$PWD:/source:ro" -w /ci mira-e4e5-swift-ci:6.4.1 bash -euc '
  mkdir -p CreatorContentOS/Mira scripts
  cp /source/Package.swift .
  cp -R /source/CreatorContentOS/Mira/Core CreatorContentOS/Mira/
  cp /source/scripts/mira-core-check.sh scripts/
  MIRA_SWIFT_BIN="$PWD/work/swift/usr/bin/swift" bash scripts/mira-core-check.sh
'

supabase --workdir "$MIRA_EVIDENCE/local-supabase" start -x vector >/dev/null
docker exec -i supabase_db_mira-e4e5-local psql -U postgres -d postgres -X -v ON_ERROR_STOP=1 < "$MIRA_EVIDENCE/seed-api.sql"
mira_local_status=$(supabase --workdir "$MIRA_EVIDENCE/local-supabase" status -o json)
export MIRA_API_E2E_LOCAL_SERVICE_ROLE=$(jq -er .SERVICE_ROLE_KEY <<<"$mira_local_status")
export MIRA_API_E2E_LOCAL_ANON=$(jq -er .ANON_KEY <<<"$mira_local_status")
unset mira_local_status
export MIRA_API_E2E_LOCAL_PORT=54321 MIRA_API_E2E_LIVE=0 MIRA_API_E2E_LIVE_TODAY=0
MIRA_API_E2E_OUTPUT="$MIRA_EVIDENCE/api-repro" npx --no-install e2e run --config e2e.mira-api.config.ts
docker exec -i supabase_db_mira-e4e5-local psql -U postgres -d postgres -X -v ON_ERROR_STOP=1 < "$MIRA_EVIDENCE/seed-insights.sql"
npx --no-install e2e run --config "$MIRA_EVIDENCE/e2e.insights.config.ts"
unset MIRA_API_E2E_LOCAL_SERVICE_ROLE MIRA_API_E2E_LOCAL_ANON MIRA_API_E2E_LOCAL_PORT
supabase --workdir "$MIRA_EVIDENCE/local-supabase" stop
colima stop --profile mira-s4-20261127

python3 "$MIRA_EVIDENCE/build.py" device
python3 "$MIRA_EVIDENCE/build.py" sim
for config in e2e.mira*.config.ts; do
  MIRA_E2E_FIXTURE_SESSION=e4e5-collect npx --no-install e2e list --config "$config"
done
(cd tracker && PATH="/opt/homebrew/opt/node@26/bin:$PATH" ./node_modules/.bin/e2e list --config e2e.config.ts)
```

## Live deployment after merge

Claude owns this step after the reviewed integration reaches the deployment
branch. The existing runbook identifies live project `zogvvrxhiwozjmufvddu`.
Run the single-function deploy from the merged checkout. The client uses the
existing in-function device-token check, so preserve the gateway setting.
[Instagram deployment runbook](../instagram-insights-runbook.md#6-deploy)

```sh
supabase functions deploy instagram-insights \
  --project-ref zogvvrxhiwozjmufvddu --no-verify-jwt --use-api --jobs 1
supabase functions list --project-ref zogvvrxhiwozjmufvddu
```

Confirm that `instagram-insights` is active with the new version. In the approved
paired-account smoke check, verify the old app still shows the existing metrics
or no-data state. With eligible recent media, verify the new app also shows
What worked. The deploy needs no migrations, secret updates or other functions.
No live backend call or deployment ran during integration.

## Tracker

The public tracker confirmed MIRA-040 at `2026-11-28T03:17:35.009Z` and
MIRA-041 at `2026-11-28T03:17:35.424Z`. Both cards remain Working with the
phone blocker, verified results and GitHub links to their respective source
commits. The readback is in `tracker-verified.jsonl`. [Mira tracker](https://mira-build-progress-production.up.railway.app)

### Fix2 phone scope

Use the bundled E4 clips for matching, joining and on-screen brief fixes. The
Instagram and WhatsApp handoff cases and the Notes share case are outside this
run because their full flows leave Mira. The phone run does not save to Photos.
The E4 live review and note need the real, eligible Reels named in the E4 phone
plan. The E4 live pick needs an open deal and the reviewed Instagram data choice.
The E5 live action can reopen a Reel with a saved Today batch. If the picture
budget for that path is unknown, record **not run (picture limit not provable)**
before opening the live case. The new Instagram Insights function stays
undeployed.

## Fix2 iPhone result for PR #49

**RESULT BLOCKED**

The ordered phone sequence stopped at an app fault in PR #48. Mira ignored the E2 Not now Debug launch override and showed the Instagram results permission prompt. The protocol bars a phone run on PR #49 after this app fault.

| Scenario | Result | Start IST | Duration | Evidence path |
| --- | --- | --- | --- | --- |
| Keep before install, in-place install and Keep after install | Not run | — | — | `pr48-sample-e2-not-now/report.json` |
| Sample, read-only consent, live and Keep after tests | Not run | — | — | `pr48-instagram-override-source.txt` |

The latest integrated test and app source at `dbd39a6` passed all eight agent-rule groups and all 19 historical checks. The state-machine document matched all 137 Swift states. Xcode 27.2 passed both the generic simulator and signed device builds. The six GitHub checks passed at that head.

Live AI counts were **0 text requests and 0 pictures**. The phone had zero claims. The fixture stopped and the Tailscale routes matched the original list.

### Fix2 checks still open

- PR #49 phone behavior and account preservation.
- E4 and E5 live behavior. The Instagram Insights function change stays undeployed.

## Fix3 keyboard and iPhone result for PR #49

**RESULT BLOCKED**

The ordered phone sequence stopped during the pre-install Keep check on PR #47. TesterArmy could not start its XCTest runner. Its `xcodebuild build-for-testing` command failed and reported a provisioning-profile hint. PR #49 did not start its phone run.

The source head `1434adf` passed all six GitHub checks. All eight agent rule groups, the 19 historical rule proofs and both local Xcode builds passed for the app source at `1434adf`.

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
