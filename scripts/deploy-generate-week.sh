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

require_env SUPABASE_PROJECT_REF

if [ -z "${SUPABASE_ACCESS_TOKEN:-}" ] && [ "${ALLOW_SUPABASE_CLI_SESSION:-0}" != "1" ]; then
  cat >&2 <<EOF
error: missing SUPABASE_ACCESS_TOKEN.

Set SUPABASE_ACCESS_TOKEN, or set ALLOW_SUPABASE_CLI_SESSION=1 if this machine is already authenticated with supabase login.
EOF
  exit 1
fi

supabase functions deploy generate-week \
  --project-ref "$SUPABASE_PROJECT_REF" \
  --no-verify-jwt \
  --use-api \
  --jobs 1

echo "Deployed generate-week Edge Function to project $SUPABASE_PROJECT_REF."
