#!/bin/bash
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
root="$PWD"
udid=00008140-000611E83AD3001C
team=4JRB53LG5C
env_file="$root/work/keep/pr37-phone-3.env"
agent="$root/node_modules/.bin/agent-device"
bin="$HOME/.codex/bin"
if [[ "${1:-}" == --dry-run && $# == 1 ]]; then
  echo 'Load the phone environment from work/keep/pr37-phone-3.env (<hidden>).'
  echo 'Check for active claims, stop old agent-device daemons, and confirm zero phone claims.'
  echo 'Check the paired USB phone, lock state, and the XCTest runner signature for team 4JRB53LG5C.'
  exit 0
fi
if [[ "${1:-}" == --help && $# == 1 ]]; then
  echo 'Usage: scripts/mira-phone-setup.sh [--dry-run]'
  exit 0
fi
fail() { printf '%s\n' "$1" >&2; exit 1; }
(($# == 0)) || fail 'Use scripts/mira-phone-setup.sh --help.'
[[ -r "$env_file" && -x "$agent" ]] || fail 'Copy the phone environment and install the locked Node dependencies.'
set -a
source "$env_file" >/dev/null 2>&1
set +a
unset AGENT_DEVICE_DAEMON_BASE_URL AGENT_DEVICE_DAEMON_AUTH_TOKEN
[[ "${AGENT_DEVICE_IOS_TEAM_ID:-}" == "$team" ]] || fail 'Set the XCTest runner team to 4JRB53LG5C.'
phone_dir="${MIRA_E2E_PHONE_RUN_DIR:-$("$bin/evidence-path.sh" --root "$root/work/evidence" --label mira-phone-setup)}"
export AGENT_DEVICE_STATE_DIR="$phone_dir/agent-device"
export AGENT_DEVICE_IOS_RUNNER_DERIVED_PATH="$phone_dir/runner-derived"
export AGENT_DEVICE_IOS_RUNNER_LEASE_DIR="$phone_dir/runner-leases"
mkdir -p "$phone_dir"

claims() {
  "$agent" device status --platform ios --udid "$1" --json 2>/dev/null \
    | jq -er 'select(.success and (.data.claims | type == "array")) | .data.claims | length'
}
phone_claims="$(claims "$udid")" || fail 'Could not read the iPhone test claims.'
[[ "$phone_claims" == 0 ]] || fail 'Another test is using the iPhone.'
for simulator in 55806CE9-F67E-4C13-9A5E-CC33F6661EFE 9B8EA2C0-C0EC-413F-BA28-81E584D6E09C; do
  sim_claims="$(claims "$simulator")" || fail 'Could not read the simulator test claims.'
  [[ "$sim_claims" == 0 && ! -d "$HOME/.config/sim-guard/leases/$simulator" ]] \
    || fail 'Wait for the simulator tests to finish.'
done

stop_daemon() {
  "$agent" daemon stop --clean --state-dir "$1" >>"$phone_dir/setup.log" 2>&1 \
    || fail 'Could not stop an old agent-device daemon.'
}
stop_daemon "$HOME/.agent-device"
for search_root in "$HOME/.agent-device/dev" "$HOME"/scratch/mira-*/; do
  if [[ "$search_root" == "$HOME/.agent-device/dev" ]]; then
    [[ -d "$search_root" ]] || continue
  else
    [[ -e "$search_root/.git" ]] || continue
  fi
  while IFS= read -r -d '' daemon_file; do
    daemon_dir="${daemon_file%/*}"
    if [[ "$daemon_dir" != "$AGENT_DEVICE_STATE_DIR" ]]; then stop_daemon "$daemon_dir"; fi
  done < <(find "$search_root" \( -name .git -o -name node_modules -o -name 'DerivedData*' -o -name runner-derived \) \
    -prune -o -type f -name daemon.json -print0)
done
phone_claims="$(claims "$udid")" || fail 'Could not read the iPhone test claims.'
[[ "$phone_claims" == 0 ]] || fail 'Another test is using the iPhone.'

device="$(xcrun devicectl device info details --device "$udid" --json-output - --timeout 10 2>/dev/null)" \
  || fail 'Connect the iPhone with the USB cable.'
jq -e '
  .result.connectionProperties as $connection
  | ($connection.pairingState | ascii_downcase) == "paired"
    and (($connection.transportType | ascii_downcase) as $transport | $transport == "wired" or $transport == "usb")
' <<<"$device" >/dev/null 2>&1 || fail 'Connect the iPhone with the USB cable.'
lock="$(xcrun devicectl device info lockState --device "$udid" --json-output - --timeout 10 2>/dev/null)" \
  || fail 'Unlock your iPhone.'
jq -e '.result.deviceIsLocked == false and .result.unlockedSinceBoot == true' <<<"$lock" >/dev/null 2>&1 \
  || fail 'Unlock your iPhone.'
"$bin/disk-preflight.sh" >>"$phone_dir/setup.log" 2>&1 || fail 'The XCTest runner disk check failed.'

stop_runner() {
  "$agent" daemon stop --state-dir "$AGENT_DEVICE_STATE_DIR" >>"$phone_dir/setup.log" 2>&1
}
trap stop_runner EXIT
if ! "$agent" prepare ios-runner --platform ios --udid "$udid" --timeout 180000 --json \
    >"$phone_dir/runner.json" 2>"$phone_dir/runner.stderr.log"; then
  if rg -qi 'another (active )?session|DEVICE_IN_USE|already owned' "$phone_dir"/runner.{json,stderr.log}; then
    fail 'Another test is using the iPhone.'
  fi
  if rg -qi 'passcode|password.?protected|authentication required' "$phone_dir"/runner.{json,stderr.log}; then
    fail 'Type the iPhone passcode for XCTest on the phone.'
  fi
  if rg -qi 'device.?locked|screen.?locked|unlock' "$phone_dir"/runner.{json,stderr.log}; then
    fail 'Unlock your iPhone.'
  fi
  if rg -qi 'disconnect|not connected|device not found' "$phone_dir"/runner.{json,stderr.log}; then
    fail 'Connect the iPhone with the USB cable.'
  fi
  fail 'The XCTest runner could not start.'
fi
runner="$(find "$AGENT_DEVICE_IOS_RUNNER_DERIVED_PATH" -name '*-Runner.app' -type d -print -quit)"
[[ -n "$runner" ]] || fail 'The signed XCTest runner is missing.'
codesign -dv --verbose=4 "$runner" 2>&1 | rg -qx "TeamIdentifier=$team" \
  || fail 'The XCTest runner must sign with team 4JRB53LG5C.'
stop_runner || fail 'Could not release the prepared XCTest runner.'
trap - EXIT
phone_claims="$(claims "$udid")" || fail 'Could not read the iPhone test claims.'
[[ "$phone_claims" == 0 ]] || fail 'Another test is using the iPhone.'
echo 'The iPhone is ready.'
