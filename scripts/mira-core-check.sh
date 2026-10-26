#!/usr/bin/env bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
swift_tool="${MIRA_SWIFT_BIN:-swift}"
if ! command -v "$swift_tool" >/dev/null; then
  swift_tool="$task_root/work/swift/usr/bin/swift"
fi
export XDG_CACHE_HOME="$task_root/work/xdg-cache"
export CLANG_MODULE_CACHE_PATH="$task_root/work/clang-cache"
exec "$swift_tool" test --jobs 4 --scratch-path work/core-build \
  --cache-path work/swift-cache --config-path work/swift-config \
  --security-path work/swift-security --swift-sdks-path work/swift-sdks --disable-sandbox
