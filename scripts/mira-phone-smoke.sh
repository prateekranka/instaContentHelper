#!/bin/bash
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
root="$PWD"
bin="$HOME/.codex/bin"
udid=00008140-000611E83AD3001C
team=4JRB53LG5C
bundle=com.prateekranka.creatorcontenthelper
app="${MIRA_E2E_APP:-}"
dry=0
e4=0
[[ ! -f CreatorContentOS/Mira/Views/MiraDeliveryView.swift ]] || e4=1
fail() { printf '%s\n' "$1" >&2; exit 1; }
while (($#)); do
  case "$1" in
    --app)
      (($# >= 2)) && [[ -n "$2" ]] || fail 'Set --app to the signed Debug iPhone app.'
      app="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    --help) echo 'Usage: scripts/mira-phone-smoke.sh --app APP [--dry-run]'; exit 0 ;;
    *) fail "Unknown option $1." ;;
  esac
done

if ((dry)); then
  printf '1. Prepare the paired iPhone and its signed XCTest runner.\n'
  printf '2. Keep before install: AI Allowed and Instagram connected.\n'
  printf '3. Install over %s using %s.\n' "$bundle" "${app:-the signed Debug iPhone app}"
  printf '4. Keep after install.\n'
  printf '5. Check Home insights on iPhone. Run one ideas-only job through the live QA API (3 text attempts, 0 pictures, 0 Reel drafts).\n'
  printf '6. Open and close the real keyboard without editing a field.\n'
  printf '7. Open and cancel the share sheet without selecting a destination.\n'
  if ((e4)); then printf '8. Cancel Photos and join sample clips in an isolated E4 fixture.\n'
  else printf '8. Omit the E4 clip check on this branch.\n'; fi
  printf '9. Keep after tests. Record step times and AI totals.\n'
  exit 0
fi

[[ -n "$app" ]] || fail 'Set --app to the signed Debug iPhone app.'
if [[ "$app" != /* ]]; then app="$root/$app"; fi
plist="$app/Info.plist"
[[ -f "$plist" ]] || fail 'The signed Debug iPhone app is missing.'
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$plist")" == "$bundle" ]] \
  || fail 'The app bundle ID does not match the installed Mira app.'
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleSupportedPlatforms:0' "$plist")" == iPhoneOS ]] \
  || fail 'Use an app built for a physical iPhone.'
codesign --verify "$app" 2>/dev/null || fail 'Use a signed app build.'
codesign -dv --verbose=4 "$app" 2>&1 | rg -qx "TeamIdentifier=$team" \
  || fail 'The app must sign with team 4JRB53LG5C.'
rg -Fq 'row.attempts < 3' supabase/functions/mira-generation/index.ts \
  && rg -Fq '(input.operation === "todayIdea" || input.operation === "pickIdea")' supabase/functions/mira-generation/index.ts \
  || fail 'Could not prove the live text and picture limits for this branch.'

env_file="$root/work/keep/pr37-phone-3.env"
[[ -r "$env_file" ]] || fail 'Copy the phone environment to work/keep/pr37-phone-3.env.'
set -a
source "$env_file" >/dev/null 2>&1
set +a
[[ "${AGENT_DEVICE_IOS_TEAM_ID:-}" == "$team" ]] || fail 'Set the XCTest runner team to 4JRB53LG5C.'
[[ -n "${MCO_LIVE_CREATOR_ID:-}" && -n "${MCO_LIVE_DEVICE_TOKEN:-}" && -n "${MCO_SUPABASE_PUBLISHABLE_KEY:-}" ]] \
  || fail 'Supply the existing isolated live QA credentials before running phone smoke.'
unset AGENT_DEVICE_DAEMON_BASE_URL AGENT_DEVICE_DAEMON_AUTH_TOKEN
unset MIRA_E2E_D2_ENDPOINT MIRA_D2_FIXTURE_CONTROL MIRA_E2E_CONSENT_FIXTURE

export MIRA_E2E_PHONE_RUN_DIR="$("$bin/evidence-path.sh" --root "$root/work/evidence" --label mira-phone-smoke)"
run="$MIRA_E2E_PHONE_RUN_DIR"
export AGENT_DEVICE_STATE_DIR="$run/agent-device" AGENT_DEVICE_IOS_RUNNER_DERIVED_PATH="$run/runner-derived"
export AGENT_DEVICE_IOS_RUNNER_LEASE_DIR="$run/runner-leases"
export MIRA_E2E_DEVICE="$udid" MIRA_E2E_BUNDLE="$bundle" MIRA_E2E_INSTALL=0 MIRA_E2E_APP="$app"
export MIRA_E2E_FIXTURE_SESSION="mira-t2-phone-$$" MIRA_E2E_DRIVER_SESSION="mira-t2-phone-$$"
export MIRA_E2E_LIVE_LEDGER_DIR="$run/live-ledger" MIRA_E2E_LIVE_REQUEST_LIMIT=3 MIRA_E2E_LIVE_PICTURE_LIMIT=0
export MIRA_E2E_PHONE_E4="$e4"
mkdir -p "$MIRA_E2E_LIVE_LEDGER_DIR" "$HOME/.config/sim-guard/leases"
lock="$HOME/.config/sim-guard/leases/$udid"
mkdir "$lock" 2>/dev/null || fail 'Another test is using the iPhone.'
printf 'Evidence: %s\n' "$run"
started=$SECONDS
printf 'step\tseconds\texit\n' >"$run/times.tsv"

cleanup() {
  local result=$?
  trap - EXIT INT TERM
  set +e
  if [[ -d "$AGENT_DEVICE_STATE_DIR" ]]; then
    node_modules/.bin/agent-device daemon stop --clean --state-dir "$AGENT_DEVICE_STATE_DIR" \
      >"$run/cleanup.log" 2>&1 || { echo 'Could not release the XCTest runner.' >&2; result=1; }
  fi
  rmdir "$lock" || result=1
  if [[ ! -f "$MIRA_E2E_LIVE_LEDGER_DIR/live-requests.jsonl" ]]; then
    : >"$MIRA_E2E_LIVE_LEDGER_DIR/live-requests.jsonl"
  fi
  jq -s '{
    textRequestsReserved: (map(.calls // 0) | add // 0),
    pictureSlotsReserved: (map(.pictureSlots // 0) | add // 0),
    picturesObserved: (map(.pictures // 0) | add // 0)
  }' "$MIRA_E2E_LIVE_LEDGER_DIR/live-requests.jsonl" >"$run/live-counts.json" || result=1
  printf 'total\t%s\t%s\n' "$((SECONDS - started))" "$result" >>"$run/times.tsv"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

step() {
  local name="$1" start=$SECONDS result=0
  shift
  "$@" || result=$?
  printf '%s\t%s\t%s\n' "$name" "$((SECONDS - start))" "$result" >>"$run/times.tsv"
  if ((result)); then
    if [[ "$name" != setup ]]; then echo "Phone smoke stopped at $name. See $run." >&2; fi
    exit "$result"
  fi
  printf '%s passed in %s seconds.\n' "$name" "$((SECONDS - start))"
}

scenario() {
  local folder="$run/$1" title="$2" config="${3:-e2e.mira-live-journey.config.ts}"
  mkdir -p "$folder"
  local selects=(--config "$config" --tag @phone-smoke --grep "$title")
  npx --no-install e2e list "${selects[@]}" --reporter json >"$folder/selection.json" 2>"$folder/selection.stderr.log" \
    && jq -e '.pairs | length == 1' "$folder/selection.json" >/dev/null || return 1
  "$bin/command-watchdog.sh" --timeout-seconds 900 --stdout "$folder/e2e.stdout.log" --stderr "$folder/e2e.stderr.log" -- \
    npx --no-install e2e run "${selects[@]}" --output "$folder" --reporter list,markdown --video=off \
    --trace=retain-on-failure \
    && jq -e '.run.summary | .selected == 1 and .passed == 1' "$folder/report.json" >/dev/null
}

install_over() {
  xcrun devicectl device info apps --device "$udid" --timeout 15 --json-output - 2>"$run/app-check.stderr.log" \
    | jq -e --arg bundle "$bundle" 'any(.result.apps[]; .bundleIdentifier == $bundle)' >/dev/null \
    && xcrun devicectl device install app --device "$udid" "$app" --timeout 120 >"$run/install.log" 2>&1
}

keep='^Smoke Keep preserves AI permission and the connected Instagram account$'
step setup scripts/mira-phone-setup.sh
step keep-before scenario keep-before "$keep"
step install-over install_over
step keep-after-install scenario keep-after-install "$keep"
step home-insights scenario home-insights '^Smoke checks Home insights$'
MIRA_E2E_SMOKE_LIVE_IDEAS=1 step live-ai scenario live-ai '^Smoke returns three ideas from one live QA job$' e2e.mira-api.config.ts
step keyboard scenario keyboard '^Keyboard Profile closes with Done without editing the saved name$'
step share-sheet scenario share-sheet '^Smoke opens and cancels the share sheet for a saved Reel$'
if ((e4)); then
  step e4-clips scenario e4-clips '^Smoke opens and cancels Photos and joins sample clips in the E4 fixture$'
else
  printf 'e4-clips-absent\t0\tskipped\n' >>"$run/times.tsv"
fi
step keep-after-tests scenario keep-after-tests "$keep"
