#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

FUNCTIONS="pair-device publish-week read-content write-content import-references review-reference"

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

if [ "${SKIP_MIGRATIONS:-0}" != "1" ]; then
  if [ -n "${SUPABASE_DB_URL:-}" ]; then
    supabase db push --db-url "$SUPABASE_DB_URL" --yes
  elif [ -n "${SUPABASE_DB_PASSWORD:-}" ]; then
    supabase link --project-ref "$SUPABASE_PROJECT_REF" --password "$SUPABASE_DB_PASSWORD" --yes
    supabase db push --linked --password "$SUPABASE_DB_PASSWORD" --yes
  else
    supabase link --project-ref "$SUPABASE_PROJECT_REF" --yes
    supabase db push --linked --yes
  fi
fi

if [ -n "${SUPABASE_SECRETS_ENV_FILE:-}" ]; then
  supabase secrets set --project-ref "$SUPABASE_PROJECT_REF" --env-file "$SUPABASE_SECRETS_ENV_FILE"
fi

for function_name in $FUNCTIONS; do
  supabase functions deploy "$function_name" \
    --project-ref "$SUPABASE_PROJECT_REF" \
    --no-verify-jwt \
    --use-api \
    --jobs 1
done

if [ "${RUN_LIVE_SMOKE:-0}" = "1" ]; then
  deno run --allow-env --allow-net scripts/live-write-boundary-smoke.ts
fi

echo "Live Supabase deploy script completed for project $SUPABASE_PROJECT_REF."
