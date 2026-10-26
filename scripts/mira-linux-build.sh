#!/usr/bin/env bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
if ! command -v swift >/dev/null || ! command -v xtool >/dev/null; then
  echo 'Build blocked: put full-mode Swift and xtool on PATH. See docs/mira-toolchain.md.' >&2
  exit 1
fi
build_configuration="${CONFIGURATION:-Debug}"
case "$build_configuration" in
  Debug|Release) ;;
  *) echo 'CONFIGURATION must be Debug or Release.' >&2; exit 1 ;;
esac
CONFIGURATION="$build_configuration" sh scripts/require-live-release-bootstrap.sh
python3 - <<'PY'
import os, plistlib
from pathlib import Path
source=Path('omarchy-xtool/Info.plist')
info=plistlib.loads(source.read_bytes())
for key in ('MCO_SUPABASE_URL','MCO_SUPABASE_PUBLISHABLE_KEY'):
    info[key]=os.environ.get(key,'')
destination=Path('omarchy-xtool/Info.local.plist')
destination.write_bytes(plistlib.dumps(info))
PY
cd omarchy-xtool
ulimit -n 65536
xtool dev build --configuration "${build_configuration,,}"
