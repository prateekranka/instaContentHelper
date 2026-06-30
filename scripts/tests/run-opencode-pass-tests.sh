#!/bin/bash
set -u

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
RUNNER="$ROOT_DIR/scripts/run-opencode-pass.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/opencode-pass-tests.XXXXXX")
REPO="$TEST_ROOT/repo"
FAKE_BIN="$TEST_ROOT/fake-opencode"
PASSED=0
FAILED=0

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

pass() {
  PASSED=$((PASSED + 1))
  echo "PASS $1"
}

fail() {
  FAILED=$((FAILED + 1))
  echo "FAIL $1" >&2
}

latest_run() {
  find "$REPO/build-logs/opencode-passes" -mindepth 1 -maxdepth 1 -type d |
    LC_ALL=C sort | tail -1
}

write_fake() {
  local mode=$1
  local exit_code=${2:-0}
  cat > "$FAKE_BIN" <<EOF
#!/bin/bash
case "$mode" in
  success)
    printf '{"type":"text","text":"fake success"}\\n'
    ;;
  fail)
    echo "fake failure" >&2
    exit $exit_code
    ;;
  slow)
    sleep 20
    ;;
  change)
    printf 'allowed change\\n' > "\$FAKE_REPO/allowed/target.txt"
    printf 'scope violation\\n' > "\$FAKE_REPO/outside.txt"
    printf '{"type":"text","text":"changed files"}\\n'
    ;;
esac
EOF
  chmod +x "$FAKE_BIN"
}

run_runner() {
  OPENCODE_REPO_DIR="$REPO" \
  OPENCODE_LOG_DIR="$REPO/build-logs/opencode-passes" \
  OPENCODE_LOCK_DIR="$REPO/.git/test-opencode-lock" \
  OPENCODE_BIN="$FAKE_BIN" \
  FAKE_REPO="$REPO" \
    "$RUNNER" "$@"
}

mkdir -p "$REPO/allowed" "$REPO/build-logs/opencode-passes"
git -C "$REPO" init -q
printf 'build-logs/\n' > "$REPO/.gitignore"
printf '# Brief\n\nMake the narrow test change.\n' > "$REPO/brief.md"
printf 'before\n' > "$REPO/allowed/target.txt"
git -C "$REPO" add .gitignore brief.md allowed/target.txt
git -C "$REPO" -c user.name=Test -c user.email=test@example.invalid commit -qm baseline

echo "OpenCode pass harness tests"

write_fake success
: > "$TEST_ROOT/invocation-marker"
rm "$TEST_ROOT/invocation-marker"
OPENCODE_BIN="$TEST_ROOT/does-not-exist" run_runner \
  --task dry-run \
  --brief "$REPO/brief.md" \
  --allow-path allowed/target.txt \
  --dry-run >/dev/null
status=$?
run_dir=$(latest_run)
if [[ $status -eq 0 &&
      -f "$run_dir/result.json" &&
      -f "$run_dir/effective-prompt.md" &&
      -f "$run_dir/manifest-before.tsv" &&
      -f "$run_dir/manifest-after.tsv" ]]; then
  pass "dry-run creates complete evidence without invoking OpenCode"
else
  fail "dry-run evidence"
fi

rm -rf "$REPO/build-logs/opencode-passes"/*
(
  cd "$TEST_ROOT" || exit 1
  OPENCODE_REPO_DIR=repo \
  OPENCODE_LOG_DIR=build-logs/opencode-passes \
  OPENCODE_LOCK_DIR=.git/test-opencode-lock \
  OPENCODE_BIN="$FAKE_BIN" \
    "$RUNNER" \
      --task relative-paths \
      --brief repo/brief.md \
      --allow-path allowed/target.txt \
      --dry-run >/dev/null
)
status=$?
run_dir=$(latest_run)
if [[ $status -eq 0 && -f "$run_dir/brief.md" ]]; then
  pass "caller-relative repository and brief paths resolve once"
else
  fail "relative path regression"
fi

rm -rf "$REPO/build-logs/opencode-passes"/*
write_fake success
run_runner \
  --task success \
  --brief "$REPO/brief.md" \
  --allow-path allowed/target.txt 2>&1 | cat >/dev/null
status=${PIPESTATUS[0]}
run_dir=$(latest_run)
if [[ $status -eq 0 &&
      -s "$run_dir/stdout.jsonl" &&
      -f "$run_dir/stderr.log" &&
      -f "$run_dir/command.txt" &&
      -f "$run_dir/changed-during-run.txt" ]]; then
  pass "successful run records machine-readable evidence"
else
  fail "successful run evidence"
fi

rm -rf "$REPO/build-logs/opencode-passes"/*
write_fake fail 42
run_runner \
  --task nonzero \
  --brief "$REPO/brief.md" \
  --allow-path allowed/target.txt >/dev/null 2>&1
status=$?
if [[ $status -eq 42 ]]; then
  pass "OpenCode nonzero exit is preserved"
else
  fail "expected exit 42, got $status"
fi

rm -rf "$REPO/build-logs/opencode-passes"/*
write_fake slow
started=$(date +%s)
run_runner \
  --task timeout \
  --brief "$REPO/brief.md" \
  --allow-path allowed/target.txt \
  --timeout-seconds 1 >/dev/null 2>&1
status=$?
elapsed=$(( $(date +%s) - started ))
if [[ $status -eq 124 && $elapsed -lt 10 ]]; then
  pass "timeout returns 124 and stops the process group"
else
  fail "timeout expected exit 124 in under 10s, got $status in ${elapsed}s"
fi

rm -rf "$REPO/build-logs/opencode-passes"/*
mkdir "$REPO/.git/test-opencode-lock"
write_fake success
run_runner \
  --task locked \
  --brief "$REPO/brief.md" \
  --allow-path allowed/target.txt >/dev/null 2>&1
status=$?
rm -rf "$REPO/.git/test-opencode-lock"
if [[ $status -eq 2 ]]; then
  pass "lock contention fails fast"
else
  fail "lock contention expected exit 2, got $status"
fi

rm -rf "$REPO/build-logs/opencode-passes"/*
git -C "$REPO" reset -q --hard HEAD
rm -f "$REPO/outside.txt"
write_fake change
run_runner \
  --task scope \
  --brief "$REPO/brief.md" \
  --allow-path allowed/target.txt >/dev/null 2>&1
status=$?
run_dir=$(latest_run)
if [[ $status -eq 3 ]] && grep -qx 'outside.txt' "$run_dir/scope-violations.txt"; then
  pass "out-of-scope changes are reported without reverting them"
else
  fail "scope violation expected exit 3 and outside.txt evidence"
fi

echo "$PASSED passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
