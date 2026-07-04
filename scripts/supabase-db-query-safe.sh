#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

COOLDOWN_SECONDS="${SUPABASE_DB_CIRCUIT_BREAKER_WAIT_SECONDS:-130}"
STATE_FILE="supabase/.temp/db-query-circuit-breaker.lock"
PROJECT_REF="${SUPABASE_PROJECT_REF:-}"
if [ -z "$PROJECT_REF" ] && [ -f "supabase/.temp/project-ref" ]; then
  PROJECT_REF=$(tr -d '\n' < "supabase/.temp/project-ref")
fi

wait_for_previous_lockout() {
  if [ ! -f "$STATE_FILE" ]; then
    return
  fi
  last_failure=$(cat "$STATE_FILE" 2>/dev/null || echo "")
  case "$last_failure" in
    ''|*[!0-9]*) return ;;
  esac
  now=$(date +%s)
  elapsed=$((now - last_failure))
  if [ "$elapsed" -lt "$COOLDOWN_SECONDS" ]; then
    wait_seconds=$((COOLDOWN_SECONDS - elapsed))
    echo "Supabase DB auth circuit-breaker cooldown active; waiting ${wait_seconds}s before retrying." >&2
    sleep "$wait_seconds"
  fi
}

check_network_bans() {
  if [ "${SKIP_SUPABASE_NETWORK_BAN_CHECK:-0}" = "1" ] ||
    [ -z "$PROJECT_REF" ]; then
    return
  fi
  bans=$(supabase network-bans get --project-ref "$PROJECT_REF" --output-format json 2>/dev/null || true)
  case "$bans" in
    *'"banned_ipv4_addresses":[]'*) ;;
    *'"banned_ipv4_addresses":['*)
      echo "Supabase reports active network bans for this project; check the dashboard before retrying DB auth." >&2
      ;;
  esac
}

prepare_linked_connection() {
  if [ -n "${SUPABASE_DB_URL:-}" ] || [ -z "$PROJECT_REF" ]; then
    return
  fi
  if [ -n "${SUPABASE_DB_PASSWORD:-}" ]; then
    if [ "${SUPABASE_SKIP_POOLER:-0}" = "1" ]; then
      supabase link --project-ref "$PROJECT_REF" --password "$SUPABASE_DB_PASSWORD" --skip-pooler --yes >/dev/null
    else
      supabase link --project-ref "$PROJECT_REF" --password "$SUPABASE_DB_PASSWORD" --yes >/dev/null
    fi
  fi
}

run_query_once() {
  if [ -n "${SUPABASE_DB_URL:-}" ]; then
    supabase db query --db-url "$SUPABASE_DB_URL" "$@"
  else
    supabase db query --linked "$@"
  fi
}

is_auth_lockout_error() {
  grep -Eiq 'ECIRCUITBREAKER|failed SASL auth|cli_login_postgres|invalid SCRAM server-final-message|invalid_scram_server_final_message' "$1"
}

wait_for_previous_lockout
check_network_bans
prepare_linked_connection

stderr_file=$(mktemp)
if run_query_once "$@" 2>"$stderr_file"; then
  rm -f "$stderr_file" "$STATE_FILE"
  exit 0
fi

status=$?
if is_auth_lockout_error "$stderr_file"; then
  date +%s > "$STATE_FILE"
  echo "Supabase DB auth failed and may have triggered a temporary circuit breaker; waiting ${COOLDOWN_SECONDS}s before one retry." >&2
  sleep "$COOLDOWN_SECONDS"
  prepare_linked_connection
  if run_query_once "$@" 2>"$stderr_file"; then
    rm -f "$stderr_file" "$STATE_FILE"
    exit 0
  fi
  status=$?
fi

cat "$stderr_file" >&2
rm -f "$stderr_file"
exit "$status"
