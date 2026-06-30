#!/bin/bash
set -u

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/run-opencode-pass.sh \
    --task <slug> \
    --brief <file> \
    --allow-path <repo-relative-path> [--allow-path <path> ...] \
    [--timeout-seconds <seconds>] [--dry-run]

Environment overrides:
  OPENCODE_BIN       OpenCode executable (default: opencode)
  OPENCODE_MODEL     Model (default: opencode-go/deepseek-v4-pro)
  OPENCODE_VARIANT   Variant (default: medium)
  OPENCODE_LOG_DIR   Evidence root (default: build-logs/opencode-passes)
  OPENCODE_REPO_DIR  Repository root (default: parent of this script)
  OPENCODE_PARALLEL  Set to 1 only for intentionally disjoint workstreams
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

json_escape() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

absolute_existing_file() {
  local input=$1
  local candidate

  case "$input" in
    /*) candidate=$input ;;
    *)  candidate="$CALLER_DIR/$input" ;;
  esac

  if [[ ! -f "$candidate" && "$input" != /* ]]; then
    candidate="$REPO_DIR/$input"
  fi
  [[ -f "$candidate" ]] || return 1

  (
    CDPATH= cd -- "$(dirname -- "$candidate")" &&
      printf '%s/%s\n' "$(pwd -P)" "$(basename -- "$candidate")"
  )
}

normalize_allowed_path() {
  local input=$1
  local normalized

  case "$input" in
    "$REPO_DIR") normalized="." ;;
    "$REPO_DIR"/*) normalized=${input#"$REPO_DIR"/} ;;
    /*) return 1 ;;
    *) normalized=${input#./} ;;
  esac

  normalized=${normalized%/}
  [[ -n "$normalized" ]] || normalized="."
  case "/$normalized/" in
    */../*|*/./*) return 1 ;;
  esac
  printf '%s\n' "$normalized"
}

write_manifest() {
  local output=$1
  local path
  local hash
  local unsorted="${output}.unsorted"

  : > "$unsorted"
  while IFS= read -r -d '' path; do
    [[ -f "$path" ]] || continue
    case "$REPO_DIR/$path" in
      "$RUN_DIR"/*) continue ;;
    esac
    hash=$(shasum -a 256 -- "$path" | awk '{print $1}') || hash=ERROR
    printf '%s\t%s\n' "$path" "$hash" >> "$unsorted"
  done < <(git ls-files -co --exclude-standard -z)
  LC_ALL=C sort -t $'\t' -k1,1 "$unsorted" > "$output"
  rm -f "$unsorted"
}

path_is_allowed() {
  local changed=$1
  local allowed

  for allowed in "${ALLOWED_PATHS[@]}"; do
    if [[ "$allowed" == "." || "$changed" == "$allowed" || "$changed" == "$allowed/"* ]]; then
      return 0
    fi
  done
  return 1
}

finish() {
  if [[ ${LOCK_ACQUIRED:-0} -eq 1 ]]; then
    rm -rf -- "$LOCK_DIR"
  fi
}

finish_from_signal() {
  finish
  trap - EXIT
  exit 130
}

CALLER_DIR=$(pwd -P)
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
TASK=""
BRIEF_INPUT=""
TIMEOUT_SECONDS=${OPENCODE_TIMEOUT_SEC:-1200}
DRY_RUN=0
ALLOWED_INPUTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)
      [[ $# -ge 2 ]] || { usage; exit 1; }
      TASK=$2
      shift 2
      ;;
    --brief)
      [[ $# -ge 2 ]] || { usage; exit 1; }
      BRIEF_INPUT=$2
      shift 2
      ;;
    --allow-path)
      [[ $# -ge 2 ]] || { usage; exit 1; }
      ALLOWED_INPUTS+=("$2")
      shift 2
      ;;
    --timeout-seconds)
      [[ $# -ge 2 ]] || { usage; exit 1; }
      TIMEOUT_SECONDS=$2
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ "$TASK" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] ||
  die "--task must be an alphanumeric slug"
[[ -n "$BRIEF_INPUT" ]] || die "--brief is required"
[[ ${#ALLOWED_INPUTS[@]} -gt 0 ]] || die "at least one --allow-path is required"
[[ "$TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] ||
  die "--timeout-seconds must be a positive integer"

REPO_INPUT=${OPENCODE_REPO_DIR:-"$SCRIPT_DIR/.."}
REPO_DIR=$(CDPATH= cd -- "$REPO_INPUT" 2>/dev/null && pwd -P) ||
  die "repository directory not found: $REPO_INPUT"
cd "$REPO_DIR" || die "cannot enter repository: $REPO_DIR"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
  die "not a git worktree: $REPO_DIR"

BRIEF_FILE=$(absolute_existing_file "$BRIEF_INPUT") ||
  die "brief file not found: $BRIEF_INPUT"

ALLOWED_PATHS=()
for input in "${ALLOWED_INPUTS[@]}"; do
  normalized=$(normalize_allowed_path "$input") ||
    die "allowed path must stay inside the repository: $input"
  ALLOWED_PATHS+=("$normalized")
done

OPENCODE_BIN=${OPENCODE_BIN:-opencode}
OPENCODE_MODEL=${OPENCODE_MODEL:-opencode-go/deepseek-v4-pro}
OPENCODE_VARIANT=${OPENCODE_VARIANT:-medium}
LOG_ROOT=${OPENCODE_LOG_DIR:-"$REPO_DIR/build-logs/opencode-passes"}
if [[ "$LOG_ROOT" != /* ]]; then
  LOG_ROOT="$REPO_DIR/$LOG_ROOT"
fi

if [[ -n ${OPENCODE_LOCK_DIR:-} ]]; then
  LOCK_DIR=$OPENCODE_LOCK_DIR
else
  LOCK_PATH=$(git rev-parse --git-path opencode-pass.lock)
  [[ "$LOCK_PATH" == /* ]] || LOCK_PATH="$REPO_DIR/$LOCK_PATH"
  LOCK_DIR=$LOCK_PATH
fi

LOCK_ACQUIRED=0
trap finish EXIT
trap finish_from_signal HUP INT TERM
if [[ ${OPENCODE_PARALLEL:-0} != 1 ]]; then
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "error: another OpenCode pass holds $LOCK_DIR" >&2
    echo "Wait for it to finish. Use OPENCODE_PARALLEL=1 only for verified disjoint paths." >&2
    exit 2
  fi
  LOCK_ACQUIRED=1
  {
    printf 'pid=%s\n' "$$"
    printf 'task=%s\n' "$TASK"
    printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$LOCK_DIR/owner"
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RUN_DIR="$LOG_ROOT/${TASK}-${TIMESTAMP}-$$"
mkdir -p "$RUN_DIR" || die "cannot create evidence directory: $RUN_DIR"

cp "$BRIEF_FILE" "$RUN_DIR/brief.md"
printf '%s\n' "${ALLOWED_PATHS[@]}" > "$RUN_DIR/allowed-paths.txt"

{
  cat <<'EOF'
You are the first implementation pass. Implement the narrow brief below.

Operating constraints:
- Edit only the declared allowed paths.
- Do not explore the repository broadly; use the supplied context and inspect only necessary dependencies.
- Do not commit, push, deploy, reset, stash, clean, or start interactive programs.
- Run only the focused checks named in the brief.
- If blocked, stop and report the blocker instead of broadening scope.
- End with files changed, checks run, and remaining uncertainty.

Allowed paths:
EOF
  sed 's/^/- /' "$RUN_DIR/allowed-paths.txt"
  printf '\nImplementation brief:\n\n'
  cat "$BRIEF_FILE"
} > "$RUN_DIR/effective-prompt.md"

START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
git status --short > "$RUN_DIR/git-status-before.txt"
write_manifest "$RUN_DIR/manifest-before.tsv"

COMMAND=(
  "$OPENCODE_BIN" run
  --dir "$REPO_DIR"
  --model "$OPENCODE_MODEL"
  --variant "$OPENCODE_VARIANT"
  --dangerously-skip-permissions
  --format json
)

{
  printf 'command='
  printf '%q ' "${COMMAND[@]}"
  printf '<effective-prompt>\n'
  printf 'stdin=/dev/null\n'
  printf 'timeout_seconds=%s\n' "$TIMEOUT_SECONDS"
} > "$RUN_DIR/command.txt"

{
  printf '{\n'
  printf '  "task": "%s",\n' "$(json_escape "$TASK")"
  printf '  "repo_dir": "%s",\n' "$(json_escape "$REPO_DIR")"
  printf '  "model": "%s",\n' "$(json_escape "$OPENCODE_MODEL")"
  printf '  "variant": "%s",\n' "$(json_escape "$OPENCODE_VARIANT")"
  printf '  "timeout_seconds": %s,\n' "$TIMEOUT_SECONDS"
  printf '  "dry_run": %s,\n' "$([[ $DRY_RUN -eq 1 ]] && echo true || echo false)"
  printf '  "started_utc": "%s"\n' "$START_UTC"
  printf '}\n'
} > "$RUN_DIR/metadata.json"

OPENCODE_EXIT=0
TIMED_OUT=0
if [[ $DRY_RUN -eq 1 ]]; then
  printf '{"type":"dry_run","message":"OpenCode was not invoked"}\n' > "$RUN_DIR/stdout.jsonl"
  : > "$RUN_DIR/stderr.log"
else
  set -m
  "${COMMAND[@]}" "$(cat "$RUN_DIR/effective-prompt.md")" \
    </dev/null >"$RUN_DIR/stdout.jsonl" 2>"$RUN_DIR/stderr.log" &
  OPENCODE_PID=$!

  (
    sleep "$TIMEOUT_SECONDS"
    if kill -0 "$OPENCODE_PID" 2>/dev/null; then
      : > "$RUN_DIR/timeout"
      kill -TERM -- "-$OPENCODE_PID" 2>/dev/null ||
        kill -TERM "$OPENCODE_PID" 2>/dev/null || true
      sleep 3
      kill -KILL -- "-$OPENCODE_PID" 2>/dev/null ||
        kill -KILL "$OPENCODE_PID" 2>/dev/null || true
    fi
  ) &
  WATCHER_PID=$!

  wait "$OPENCODE_PID"
  OPENCODE_EXIT=$?
  kill -TERM -- "-$WATCHER_PID" 2>/dev/null ||
    kill -TERM "$WATCHER_PID" 2>/dev/null || true
  wait "$WATCHER_PID" 2>/dev/null || true
  set +m

  if [[ -f "$RUN_DIR/timeout" ]]; then
    TIMED_OUT=1
    OPENCODE_EXIT=124
  fi
fi

git status --short > "$RUN_DIR/git-status-after.txt"
write_manifest "$RUN_DIR/manifest-after.tsv"

awk -F '\t' '
  NR == FNR { before[$1] = $2; next }
  {
    after[$1] = $2
    if (!($1 in before) || before[$1] != $2) print $1
  }
  END {
    for (path in before) if (!(path in after)) print path
  }
' "$RUN_DIR/manifest-before.tsv" "$RUN_DIR/manifest-after.tsv" |
  LC_ALL=C sort -u > "$RUN_DIR/changed-during-run.txt"

: > "$RUN_DIR/scope-violations.txt"
while IFS= read -r changed; do
  [[ -n "$changed" ]] || continue
  path_is_allowed "$changed" || printf '%s\n' "$changed" >> "$RUN_DIR/scope-violations.txt"
done < "$RUN_DIR/changed-during-run.txt"

FINAL_EXIT=$OPENCODE_EXIT
STATUS=done
if [[ $TIMED_OUT -eq 1 ]]; then
  STATUS=timeout
elif [[ $OPENCODE_EXIT -ne 0 ]]; then
  STATUS=opencode_failed
elif [[ -s "$RUN_DIR/scope-violations.txt" ]]; then
  STATUS=scope_violation
  FINAL_EXIT=3
elif [[ $DRY_RUN -eq 1 ]]; then
  STATUS=dry_run
fi

END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
{
  printf '{\n'
  printf '  "status": "%s",\n' "$STATUS"
  printf '  "opencode_exit_code": %s,\n' "$OPENCODE_EXIT"
  printf '  "final_exit_code": %s,\n' "$FINAL_EXIT"
  printf '  "scope_violation": %s,\n' "$([[ -s "$RUN_DIR/scope-violations.txt" ]] && echo true || echo false)"
  printf '  "started_utc": "%s",\n' "$START_UTC"
  printf '  "ended_utc": "%s",\n' "$END_UTC"
  printf '  "evidence_dir": "%s"\n' "$(json_escape "$RUN_DIR")"
  printf '}\n'
} > "$RUN_DIR/result.json"

printf 'result=%s exit=%s evidence=%s\n' "$STATUS" "$FINAL_EXIT" "$RUN_DIR"
exit "$FINAL_EXIT"
