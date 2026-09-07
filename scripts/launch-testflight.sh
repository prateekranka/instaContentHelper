#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

# Resolve runtime bootstrap values: LocalRuntime.xcconfig overrides the base file.
resolve() {
  key="$1"
  local_file="CreatorContentOS/Config/LocalRuntime.xcconfig"
  base_file="CreatorContentOS/Config/Runtime.xcconfig"
  for file in "$local_file" "$base_file"; do
    if [ -f "$file" ]; then
      value=$(awk -F= -v k="$key" '$1 ~ k {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}' "$file")
      if [ -n "$value" ]; then
        printf '%s' "$value"
        return 0
      fi
    fi
  done
  printf '%s' ""
}

URL=$(resolve MCO_SUPABASE_URL)
KEY=$(resolve MCO_SUPABASE_PUBLISHABLE_KEY)
echo "runtime env: url_len=${#URL} key_len=${#KEY}"
export MCO_SUPABASE_URL="$URL"
export MCO_SUPABASE_PUBLISHABLE_KEY="$KEY"
exec scripts/build-testflight-release.sh
