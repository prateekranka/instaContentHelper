#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
URL=$(grep '^MCO_SUPABASE_URL' CreatorContentOS/Config/Runtime.xcconfig | cut -d'=' -f2 | xargs)
KEY=$(grep '^MCO_SUPABASE_PUBLISHABLE_KEY' CreatorContentOS/Config/Runtime.xcconfig | cut -d'=' -f2 | xargs)
echo "runtime env: url_len=${#URL} key_len=${#KEY}"
export MCO_SUPABASE_URL="$URL"
export MCO_SUPABASE_PUBLISHABLE_KEY="$KEY"
exec scripts/build-testflight-release.sh
