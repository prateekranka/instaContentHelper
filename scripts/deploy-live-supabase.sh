#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

FUNCTIONS="exchange-auth-session pair-device revoke-device-session send-auth-email manage-testers publish-week read-content write-content import-references review-reference generate-week generate-storyboard-thumbnail generate-storyboard-thumbnails"

require_env() {
  name="$1"
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    echo "error: missing $name" >&2
    exit 1
  fi
}

require_env SUPABASE_PROJECT_REF

COOLDOWN_SECONDS="${SUPABASE_DB_CIRCUIT_BREAKER_WAIT_SECONDS:-130}"
DB_PUSH_LOCK_FILE="supabase/.temp/db-push-circuit-breaker.lock"

wait_for_db_auth_lockout() {
  if [ ! -f "$DB_PUSH_LOCK_FILE" ]; then
    return
  fi
  last_failure=$(cat "$DB_PUSH_LOCK_FILE" 2>/dev/null || echo "")
  case "$last_failure" in
    ''|*[!0-9]*) return ;;
  esac
  now=$(date +%s)
  elapsed=$((now - last_failure))
  if [ "$elapsed" -lt "$COOLDOWN_SECONDS" ]; then
    wait_seconds=$((COOLDOWN_SECONDS - elapsed))
    echo "Supabase DB auth circuit-breaker cooldown active; waiting ${wait_seconds}s before retrying migrations." >&2
    sleep "$wait_seconds"
  fi
}

check_network_bans() {
  if [ "${SKIP_SUPABASE_NETWORK_BAN_CHECK:-0}" = "1" ]; then
    return
  fi
  bans=$(supabase network-bans get --project-ref "$SUPABASE_PROJECT_REF" --output-format json 2>/dev/null || true)
  case "$bans" in
    *'"banned_ipv4_addresses":[]'*) ;;
    *'"banned_ipv4_addresses":['*)
      echo "Supabase reports active network bans for this project; check the dashboard before retrying DB auth." >&2
      ;;
  esac
}

run_with_db_auth_cooldown() {
  wait_for_db_auth_lockout
  stderr_file=$(mktemp)
  if "$@" 2>"$stderr_file"; then
    rm -f "$stderr_file" "$DB_PUSH_LOCK_FILE"
    return 0
  fi
  status=$?
  if grep -Eiq 'ECIRCUITBREAKER|failed SASL auth|cli_login_postgres|invalid SCRAM server-final-message|invalid_scram_server_final_message' "$stderr_file"; then
    date +%s > "$DB_PUSH_LOCK_FILE"
    echo "Supabase DB auth failed and may have triggered a temporary circuit breaker; waiting ${COOLDOWN_SECONDS}s before one retry." >&2
    sleep "$COOLDOWN_SECONDS"
    if "$@" 2>"$stderr_file"; then
      rm -f "$stderr_file" "$DB_PUSH_LOCK_FILE"
      return 0
    fi
    status=$?
  fi
  cat "$stderr_file" >&2
  rm -f "$stderr_file"
  return "$status"
}

if [ -z "${SUPABASE_ACCESS_TOKEN:-}" ] && [ "${ALLOW_SUPABASE_CLI_SESSION:-0}" != "1" ]; then
  cat >&2 <<EOF
error: missing SUPABASE_ACCESS_TOKEN.

Set SUPABASE_ACCESS_TOKEN, or set ALLOW_SUPABASE_CLI_SESSION=1 if this machine is already authenticated with supabase login.
EOF
  exit 1
fi

if [ "${SKIP_MIGRATIONS:-0}" != "1" ]; then
  check_network_bans
  if [ -n "${SUPABASE_DB_URL:-}" ]; then
    run_with_db_auth_cooldown supabase db push --db-url "$SUPABASE_DB_URL" --yes
  elif [ -n "${SUPABASE_DB_PASSWORD:-}" ]; then
    if [ "${SUPABASE_SKIP_POOLER:-0}" = "1" ]; then
      supabase link --project-ref "$SUPABASE_PROJECT_REF" --password "$SUPABASE_DB_PASSWORD" --skip-pooler --yes
    else
      supabase link --project-ref "$SUPABASE_PROJECT_REF" --password "$SUPABASE_DB_PASSWORD" --yes
    fi
    run_with_db_auth_cooldown supabase db push --linked --password "$SUPABASE_DB_PASSWORD" --yes
  else
    supabase link --project-ref "$SUPABASE_PROJECT_REF" --yes
    run_with_db_auth_cooldown supabase db push --linked --yes
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
