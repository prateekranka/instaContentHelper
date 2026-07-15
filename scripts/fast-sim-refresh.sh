#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PROJECT_PATH="${MCO_XCODE_PROJECT:-$ROOT_DIR/CreatorContentOS.xcodeproj}"
SCHEME="${MCO_XCODE_SCHEME:-CreatorContentOS}"
CONFIGURATION="${MCO_XCODE_CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${MCO_DERIVED_DATA_PATH:-$ROOT_DIR/DerivedData/FastSimRefresh}"
APP_NAME="${MCO_APP_NAME:-ContentHelper}"
BUNDLE_ID="${MCO_BUNDLE_ID:-}"
LOG_DIR="${MCO_BUILD_LOG_DIR:-$ROOT_DIR/build-logs}"
SIMULATOR_UDID="${MCO_SIMULATOR_UDID:-${1:-}}"
SKIP_ASSETS="${MCO_FAST_SKIP_ASSETS:-1}"
RESTART_MIRROR="${MCO_RESTART_SERVE_SIM:-1}"

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

restart_mirror() {
  if [ "$RESTART_MIRROR" = "1" ]; then
    MCO_FORCE_SERVE_SIM_RESTART=1 "$ROOT_DIR/scripts/serve-sim-browser.sh" "$SIMULATOR_UDID"
  fi
}

require_tool xcrun
require_tool xcodebuild

if [ -z "$SIMULATOR_UDID" ]; then
  SIMULATOR_UDID=$(find_booted_simulator)
fi

if [ -z "$SIMULATOR_UDID" ]; then
  cat >&2 <<EOF
error: no booted iPhone simulator found.

Boot a simulator first or pass a UDID:
  MCO_SIMULATOR_UDID=<udid> scripts/fast-sim-refresh.sh
  scripts/fast-sim-refresh.sh <udid>
EOF
  exit 1
fi

mkdir -p "$LOG_DIR"
BUILD_LOG="$LOG_DIR/fast-sim-refresh-$(date +%Y%m%d-%H%M%S).log"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION-iphonesimulator/$APP_NAME.app"

if [ "$RESTART_MIRROR" = "1" ]; then
  screen -S "${MCO_SERVE_SIM_SESSION:-mco-serve-sim}" -X quit >/dev/null 2>&1 || true
  pkill -f "serve-sim.*${SIMULATOR_UDID}" >/dev/null 2>&1 || true
  pkill -f "node .*/serve-sim/dist/serve-sim\\.js .*${SIMULATOR_UDID}" >/dev/null 2>&1 || true
  pkill -f "serve-sim-bin ${SIMULATOR_UDID}" >/dev/null 2>&1 || true
fi

BUILD_SETTINGS="ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO SWIFT_COMPILATION_MODE=wholemodule"
if [ "$SKIP_ASSETS" = "1" ]; then
  BUILD_SETTINGS="$BUILD_SETTINGS EXCLUDED_SOURCE_FILE_NAMES=Assets.xcassets"
fi

if command -v xattr >/dev/null 2>&1 && [ -d "$DERIVED_DATA_PATH/Build/Products" ]; then
  xattr -cr "$DERIVED_DATA_PATH/Build/Products" >/dev/null 2>&1 || true
fi

echo "Building $SCHEME for simulator $SIMULATOR_UDID"
echo "Build log: $BUILD_LOG"

# shellcheck disable=SC2086
if ! xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "id=$SIMULATOR_UDID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -jobs 1 \
  $BUILD_SETTINGS \
  build > "$BUILD_LOG" 2>&1; then
  echo "error: xcodebuild failed. Tail of $BUILD_LOG:" >&2
  tail -n 80 "$BUILD_LOG" >&2 || true
  restart_mirror
  exit 1
fi

if [ ! -d "$APP_PATH" ]; then
  echo "error: built app not found at $APP_PATH" >&2
  restart_mirror
  exit 1
fi

if [ -z "$BUNDLE_ID" ]; then
  BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")
fi

xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"

add_launch_env() {
  name="$1"
  value=$(eval "printf '%s' \"\${$name:-}\"")
  if [ -n "$value" ]; then
    eval "export SIMCTL_CHILD_$name=\$value"
  fi
}

add_launch_env MCO_SUPABASE_URL
add_launch_env MCO_SUPABASE_PUBLISHABLE_KEY
add_launch_env MCO_DEBUG_PAIRED_WORKSPACE_ID
add_launch_env MCO_DEBUG_PAIRED_CREATOR_ID
add_launch_env MCO_DEBUG_PAIRED_MEMBER_ID
add_launch_env MCO_DEBUG_PAIRED_DEVICE_INSTALLATION_ID
add_launch_env MCO_DEBUG_PAIRED_DEVICE_TOKEN
add_launch_env MCO_DEBUG_PAIRED_CREATOR_DISPLAY_NAME
add_launch_env MCO_DEBUG_PAIRED_MEMBER_ROLE
add_launch_env MCO_FORCE_FIXTURE_UI
add_launch_env MCO_FORCE_APP_MODE
add_launch_env MCO_FORCE_SCREEN

xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID"

restart_mirror

cat <<EOF
fast simulator refresh complete
app=$APP_PATH
build_log=$BUILD_LOG
simulator_udid=$SIMULATOR_UDID
EOF
