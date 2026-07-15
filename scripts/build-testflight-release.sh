#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

require_env() {
  name="$1"
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    echo "error: missing $name" >&2
    exit 1
  fi
}

require_env MCO_SUPABASE_URL
require_env MCO_SUPABASE_PUBLISHABLE_KEY

mkdir -p build-logs
STAMP=$(date +%Y%m%d_%H%M%S)
ARCHIVE_PATH="build-logs/ContentHelper_Release_${STAMP}.xcarchive"
EXPORT_DIR="build-logs/testflight-upload-${STAMP}"
EXPORT_PLIST="${EXPORT_OPTIONS_PLIST:-ExportOptions.plist}"
LOG_DIR="build-logs"

echo "Archiving ContentHelper for TestFlight..."
MCO_SUPABASE_URL="$MCO_SUPABASE_URL" \
MCO_SUPABASE_PUBLISHABLE_KEY="$MCO_SUPABASE_PUBLISHABLE_KEY" \
xcodebuild archive \
  -project CreatorContentOS.xcodeproj \
  -scheme CreatorContentOS \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -jobs 1 \
  COMPILER_INDEX_STORE_ENABLE=NO \
  SWIFT_COMPILATION_MODE=wholemodule \
  | tee "$LOG_DIR/archive_testflight_${STAMP}.log"

echo "Exporting and uploading to App Store Connect / TestFlight..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -allowProvisioningUpdates \
  | tee "$LOG_DIR/upload_testflight_${STAMP}.log"

echo "TestFlight upload complete."
echo "Archive: $ARCHIVE_PATH"
echo "Export:  $EXPORT_DIR"
