#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SESSION_NAME="${MCO_SERVE_SIM_SESSION:-mco-serve-sim}"
SERVE_SIM_URL="${MCO_SERVE_SIM_URL:-http://localhost:3200}"
LOG_DIR="${MCO_BUILD_LOG_DIR:-$ROOT_DIR/build-logs}"
SIMULATOR_UDID="${MCO_SIMULATOR_UDID:-${1:-}}"
SERVE_SIM_JS="${MCO_SERVE_SIM_JS:-}"
FORCE_RESTART="${MCO_FORCE_SERVE_SIM_RESTART:-0}"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: missing required tool: $1" >&2
    exit 1
  fi
}

find_booted_simulator() {
  xcrun simctl list devices booted |
    sed -n '/iPhone/s/.*(\([0-9A-Fa-f-][0-9A-Fa-f-]*\)) (Booted).*/\1/p' |
    head -n 1
}

find_cached_serve_sim_js() {
  find "$HOME/.npm/_npx" -path '*/node_modules/serve-sim/dist/serve-sim.js' -type f 2>/dev/null |
    head -n 1
}

require_tool xcrun
require_tool curl
require_tool screen

if [ -z "$SERVE_SIM_JS" ]; then
  SERVE_SIM_JS=$(find_cached_serve_sim_js || true)
fi

if [ -n "$SERVE_SIM_JS" ] && [ -f "$SERVE_SIM_JS" ]; then
  require_tool node
else
  require_tool npx
fi

if [ -z "$SIMULATOR_UDID" ]; then
  SIMULATOR_UDID=$(find_booted_simulator)
fi

if [ -z "$SIMULATOR_UDID" ]; then
  cat >&2 <<EOF
error: no booted iPhone simulator found.

Boot a simulator first or pass a UDID:
  MCO_SIMULATOR_UDID=<udid> scripts/serve-sim-browser.sh
  scripts/serve-sim-browser.sh <udid>
EOF
  exit 1
fi

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/serve-sim-$(date +%Y%m%d-%H%M%S).log"

if [ "$FORCE_RESTART" != "1" ] && curl -sS -m 2 -o /dev/null -w '%{http_code}' "$SERVE_SIM_URL" | grep -q '^200$'; then
  cat <<EOF
serve-sim ready
url=$SERVE_SIM_URL
simulator_udid=$SIMULATOR_UDID
screen_session=$SESSION_NAME
log=already-running
EOF
  exit 0
fi

screen -S "$SESSION_NAME" -X quit >/dev/null 2>&1 || true
pkill -f "serve-sim.*${SIMULATOR_UDID}" >/dev/null 2>&1 || true
pkill -f "node .*/serve-sim/dist/serve-sim\\.js .*${SIMULATOR_UDID}" >/dev/null 2>&1 || true
pkill -f "serve-sim-bin ${SIMULATOR_UDID}" >/dev/null 2>&1 || true
sleep 1

ROOT_DIR="$ROOT_DIR" \
SIMULATOR_UDID="$SIMULATOR_UDID" \
LOG_FILE="$LOG_FILE" \
SERVE_SIM_JS="$SERVE_SIM_JS" \
  screen -dmS "$SESSION_NAME" /bin/sh -lc '
    cd "$ROOT_DIR"
    if [ -n "$SERVE_SIM_JS" ] && [ -f "$SERVE_SIM_JS" ]; then
      node "$SERVE_SIM_JS" "$SIMULATOR_UDID" > "$LOG_FILE" 2>&1
    else
      npx --yes serve-sim@latest "$SIMULATOR_UDID" > "$LOG_FILE" 2>&1
    fi
  '

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if curl -sS -m 2 -o /dev/null -w '%{http_code}' "$SERVE_SIM_URL" | grep -q '^200$'; then
    cat <<EOF
serve-sim ready
url=$SERVE_SIM_URL
simulator_udid=$SIMULATOR_UDID
screen_session=$SESSION_NAME
log=$LOG_FILE
EOF
    exit 0
  fi
  sleep 1
done

cat >&2 <<EOF
error: serve-sim did not become ready.
url=$SERVE_SIM_URL
simulator_udid=$SIMULATOR_UDID
screen_session=$SESSION_NAME
log=$LOG_FILE
EOF

sed -n '1,120p' "$LOG_FILE" >&2 || true
exit 1
