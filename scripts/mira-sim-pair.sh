#!/bin/bash
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
root="$PWD"
guard="$HOME/.codex/skills/sim-guard/sim-guard.sh"
bin="$HOME/.codex/bin"
pool="$HOME/.config/sim-guard/pool"
lease_root="$HOME/.config/sim-guard/leases"
one=55806CE9-F67E-4C13-9A5E-CC33F6661EFE
two=9B8EA2C0-C0EC-413F-BA28-81E584D6E09C
sims=2
app=
dry=0
filters=()
while (($#)); do
  case "$1" in
    --sims|--app|--tag|--exclude-tag|--grep)
      if (($# < 2)) || [[ -z "$2" ]]; then echo "Missing value for $1." >&2; exit 2; fi
      case "$1" in
        --sims) sims="$2" ;;
        --app) app="$2" ;;
        *) filters+=("$1" "$2") ;;
      esac
      shift 2 ;;
    --dry-run) dry=1; shift ;;
    --help) echo 'Usage: scripts/mira-sim-pair.sh [--sims 1|2] [--app APP] [--tag TAGS] [--exclude-tag TAGS] [--grep REGEX] [--dry-run]'; exit 0 ;;
    *) echo "Unknown option $1." >&2; exit 2 ;;
  esac
done
case "$sims" in
  1) devices=("$two"); slots=(2) ;;
  2) devices=("$one" "$two"); slots=(1 2) ;;
  *) echo 'Use --sims 1 or --sims 2.' >&2; exit 2 ;;
esac
fail() { printf '%s\n' "$1" >&2; exit 1; }
fixture_session="mira-t2-$(date -u +%Y%m%dT%H%M%S)-$$"
export MIRA_E2E_FIXTURE_SESSION="$fixture_session"
e2e=(npx --no-install e2e)
selection=(--config e2e.mira.config.ts ${filters[@]+"${filters[@]}"} --exclude-tag @phone-only)
if ((dry)); then
  printf 'App: %s\n' "${app:-Build one Debug simulator app.}"
  printf 'Selection:'; printf ' %q' "${selection[@]}"; printf '\n'
  for index in "${!devices[@]}"; do
    printf 'iPhone %s (%s)' "${slots[index]}" "${devices[index]}"
    if ((sims == 2)); then printf ' --shard %s/2' "$((index + 1))"; fi
    printf ' with its own runner, fixture port, CA and report.\n'
  done
  echo 'Wait for both reports, write summary.md and summary.json, and release resources.'
  exit 0
fi
[[ -x node_modules/.bin/e2e ]] || fail 'Install the locked Node dependencies with npm ci.'
run="$("$bin/evidence-path.sh" --root "$root/work/evidence" --label mira-sim-pair)"
printf 'Evidence: %s\n' "$run"
started=$SECONDS
locks=()
leased=()
workers=()
fixtures=()

cleanup() {
  local result=$? cleanup_result=0 index slot
  set +e
  trap - EXIT INT TERM
  for index in "${!workers[@]}"; do
    kill -TERM "${workers[index]}" 2>/dev/null
    wait "${workers[index]}" 2>/dev/null
  done
  for slot in "${slots[@]}"; do
    if [[ -d "$run/iphone-$slot/agent-device" ]]; then
      node_modules/.bin/agent-device daemon stop --clean --state-dir "$run/iphone-$slot/agent-device" \
        >>"$run/cleanup.log" 2>&1 || cleanup_result=1
    fi
  done
  for index in "${!fixtures[@]}"; do
    kill "${fixtures[index]}" 2>/dev/null
    wait "${fixtures[index]}" 2>/dev/null
  done
  for index in "${!leased[@]}"; do
    "$guard" release "${leased[index]}" --keep-apps >>"$run/cleanup.log" 2>&1 || cleanup_result=1
  done
  for index in "${!locks[@]}"; do
    rmdir "${locks[index]}" || cleanup_result=1
  done
  for slot in "${slots[@]}"; do
    rm -f "$run/iphone-$slot/tls/"{ca.key,ca.srl,server.key,server.csr}
  done
  if ((cleanup_result)); then
    echo "Simulator cleanup failed. See $run/cleanup.log." >&2
    if ((result == 0)); then result=1; fi
  fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

unset AGENT_DEVICE_DAEMON_BASE_URL AGENT_DEVICE_DAEMON_AUTH_TOKEN
unset AGENT_DEVICE_IOS_PROVISIONING_PROFILE AGENT_DEVICE_IOS_SIGNING_IDENTITY AGENT_DEVICE_IOS_TEAM_ID
unset MIRA_E2E_INSTALL MIRA_E2E_CONSENT_FIXTURE MIRA_E2E_D2_ENDPOINT MIRA_D2_FIXTURE_CONTROL
"${e2e[@]}" list "${selection[@]}" >"$run/selection.txt" 2>&1 || fail "Test selection failed. See $run/selection.txt."
mkdir -p "$lease_root"
"$guard" preflight >"$run/sim-guard.log" 2>&1 || fail "Sim Guard preflight failed. See $run/sim-guard.log."
for index in "${!devices[@]}"; do
  udid="${devices[index]}"
  slot="${slots[index]}"
  awk -v udid="$udid" '$1 == udid { found=1 } END { exit !found }' "$pool" || fail "iPhone $slot is missing from the Sim Guard pool."
  mkdir "$lease_root/$udid" || fail "Another test has the iPhone $slot lease."
  locks+=("$lease_root/$udid")
  printf '%s\n' "$udid" >"$run/pool-$slot"
  xcrun simctl list devices --json | jq -e --arg id "$udid" \
    'any(.devices[][]; .udid == $id and .state == "Shutdown" and .isAvailable)' >/dev/null \
    || fail "Sim Guard iPhone $slot is busy or unavailable."
  SIM_GUARD_CONFIG="$run/pool-$slot" "$guard" acquire >>"$run/sim-guard.log" 2>&1 \
    || fail "Could not acquire Sim Guard iPhone $slot. See $run/sim-guard.log."
  leased+=("$udid")
  "$bin/simulator-preflight.sh" --udid "$udid" >>"$run/sim-guard.log" 2>&1 \
    || fail "Simulator preflight failed for iPhone $slot. See $run/sim-guard.log."
done
if [[ -z "$app" ]]; then
  derived="$run/DerivedData"
  "$bin/xcode-proof-preflight.sh" --source-root "$root" --evidence-dir "$run" \
    --udid "${devices[0]}" --derived-data-path "$derived" >"$run/build-preflight.log" 2>&1 \
    || fail "Xcode preflight failed. See $run/build-preflight.log."
  "$bin/disk-preflight.sh" >>"$run/build-preflight.log" 2>&1 \
    || fail "Disk preflight failed. See $run/build-preflight.log."
  result_bundle="$run/Build.xcresult"
  "$bin/command-watchdog.sh" --timeout-seconds 1200 --stdout "$run/build.stdout.log" --stderr "$run/build.stderr.log" -- \
    xcodebuild -quiet -project CreatorContentOS.xcodeproj -scheme CreatorContentOS \
      -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived" \
      -resultBundlePath "$result_bundle" CODE_SIGNING_ALLOWED=NO \
      PRODUCT_BUNDLE_IDENTIFIER=com.prateekranka.creatorcontenthelper.codexverify build \
    || fail "The simulator build failed. See $run/build.stderr.log."
  app="$derived/Build/Products/Debug-iphonesimulator/ContentHelper.app"
elif [[ "$app" != /* ]]; then
  app="$root/$app"
fi
bundle="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")"
[[ -n "$bundle" ]] || fail 'The simulator app has no bundle identifier.'
export MIRA_E2E_APP="$app" MIRA_E2E_BUNDLE="$bundle" MIRA_E2E_INSTALL=0

start_fixture() {
  local slot="$1" udid="$2" dir="$run/iphone-$1" tls="$run/iphone-$1/tls" port
  mkdir -p "$tls"
  {
    openssl req -new -newkey rsa:2048 -nodes -x509 -sha256 -days 2 -subj "/CN=Mira $fixture_session iPhone $slot CA" \
      -keyout "$tls/ca.key" -out "$tls/ca.pem" -config <(printf '%s\n' '[req]' 'distinguished_name=dn' \
      'x509_extensions=ca' '[dn]' '[ca]' 'basicConstraints=critical,CA:TRUE' 'keyUsage=critical,keyCertSign,cRLSign' \
      'subjectKeyIdentifier=hash')
    openssl req -new -newkey rsa:2048 -nodes -subj '/CN=localhost' -keyout "$tls/server.key" -out "$tls/server.csr"
    openssl x509 -req -sha256 -days 2 -in "$tls/server.csr" -CA "$tls/ca.pem" -CAkey "$tls/ca.key" \
      -CAcreateserial -out "$tls/server.pem" -extfile <(printf '%s\n' 'basicConstraints=critical,CA:FALSE' \
      'keyUsage=critical,digitalSignature,keyEncipherment' 'extendedKeyUsage=serverAuth' 'subjectAltName=DNS:localhost,IP:127.0.0.1')
    xcrun simctl keychain "$udid" add-root-cert "$tls/ca.pem"
  } >"$dir/tls.log" 2>&1
  MIRA_D2_FIXTURE_TLS_DIR="$tls" MIRA_D2_FIXTURE_PORT=0 node tests/fixtures/mira-d2-server.mjs >"$dir/fixture.log" 2>&1 &
  fixtures+=("$!")
  for ((check=0; check<50; check++)); do
    port="$(head -n 1 "$dir/fixture.log")"
    if [[ "$port" =~ ^[0-9]+$ ]]; then
      curl --noproxy '*' --cacert "$tls/ca.pem" -fsS --max-time 2 "https://127.0.0.1:$port/health" >"$dir/health.json" \
        && printf '%s\n' "$port" >"$dir/port" && return
    fi
    kill -0 "${fixtures[${#fixtures[@]}-1]}" 2>/dev/null || break
    sleep 0.1
  done
  fail "The D2 fixture did not start for iPhone $slot. See $dir/fixture.log."
}

for index in "${!devices[@]}"; do
  udid="${devices[index]}"
  slot="${slots[index]}"
  mkdir -p "$run/iphone-$slot"
  xcrun simctl install "$udid" "$app" >"$run/iphone-$slot/install.log" 2>&1 \
    || fail "The app install failed on iPhone $slot. See $run/iphone-$slot/install.log."
  start_fixture "$slot" "$udid"
done
for index in "${!devices[@]}"; do
  slot="${slots[index]}"
  dir="$run/iphone-$slot"
  shard=()
  if ((sims == 2)); then shard=(--shard "$((index + 1))/2" --pass-with-no-tests); fi
  endpoint="https://127.0.0.1:$(cat "$dir/port")"
  AGENT_DEVICE_STATE_DIR="$dir/agent-device" AGENT_DEVICE_IOS_RUNNER_DERIVED_PATH="$dir/runner-derived" \
  AGENT_DEVICE_IOS_RUNNER_LEASE_DIR="$dir/runner-leases" MIRA_E2E_FIXTURE_SESSION="$fixture_session-$slot" \
  MIRA_E2E_DRIVER_SESSION="$fixture_session-$slot" MIRA_E2E_DEVICE="${devices[index]}" \
  MIRA_E2E_D2_ENDPOINT="$endpoint" MIRA_D2_FIXTURE_CONTROL="$endpoint" NODE_EXTRA_CA_CERTS="$dir/tls/ca.pem" \
  "$bin/command-watchdog.sh" --timeout-seconds 2400 --stdout "$dir/e2e.stdout.log" --stderr "$dir/e2e.stderr.log" -- \
    "${e2e[@]}" run "${selection[@]}" ${shard[@]+"${shard[@]}"} \
    --output "$dir" --trace=retain-on-failure --video=off --reporter list,markdown --max-failures 1 &
  workers+=("$!")
done

for index in "${!workers[@]}"; do
  code=0
  wait "${workers[index]}" || code=$?
  printf '%s\n' "$code" >"$run/iphone-${slots[index]}/exit"
done
workers=()
python3 - "$run" "$((SECONDS - started))" "${slots[@]}" <<'PY'
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
summary = {"wallSeconds": int(sys.argv[2]), "shards": [], "scenarios": []}
lines = ["# Mira simulator results", "", f"Wall time: {summary['wallSeconds']} s.", "",
         "| iPhone | Scenario | Result | Error code | Seconds |", "| --- | --- | --- | --- | --- |"]
failed = False
for slot in sys.argv[3:]:
    directory = root / f"iphone-{slot}"
    shard = {"iPhone": int(slot), "exitCode": int((directory / "exit").read_text()), "errors": []}
    summary["shards"].append(shard)
    try:
        document = json.loads((directory / "report.json").read_text())
        report = document.get("run", document)
        shard["errors"] = [error.get("code") for error in report.get("errors", [])]
        for result in report["results"]:
            if result.get("selected") is False:
                continue
            attempts = result.get("attempts", [])
            error = result.get("error") or (attempts[-1].get("error") if attempts else None) or {}
            elapsed = result.get("durationMs") or sum(attempt.get("durationMs", 0) for attempt in attempts)
            row = {"iPhone": int(slot), "file": result["file"], "title": " › ".join(result["titlePath"]),
                   "result": result["status"], "errorCode": error.get("code"), "durationMs": elapsed}
            summary["scenarios"].append(row)
            title = row["title"].replace("|", r"\|")
            lines.append(f"| {slot} | {title} | {row['result']} | {row['errorCode'] or ''} | {elapsed / 1000:.1f} |")
            failed |= row["result"] in {"failed", "timed-out", "interrupted"}
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        shard["errors"].append("REPORT_UNAVAILABLE")
    failed |= bool(shard["exitCode"] or shard["errors"])
    if shard["exitCode"] or shard["errors"]:
        lines.append(f"| {slot} | Shard | failed | {', '.join(filter(None, shard['errors'])) or shard['exitCode']} | |")
if not summary["scenarios"]:
    failed = True
    lines.extend(["", "No scenarios ran."])
summary["passed"] = not failed
(root / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
(root / "summary.md").write_text("\n".join(lines) + "\n")
print(root / "summary.md")
sys.exit(int(failed))
PY
