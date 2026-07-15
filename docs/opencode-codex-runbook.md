# Codex-Orchestrated OpenCode Passes

Use OpenCode for narrow implementation passes after Codex has diagnosed the
problem and selected the approach. Codex remains responsible for reviewing the
diff and proving the result.

## Standard sequence

### 1. Codex before OpenCode

1. Run `git status --short`. Treat every existing change as user-owned.
2. Diagnose and plan locally. Do not ask OpenCode to explore the repository.
3. Copy `docs/templates/opencode-implementation-brief.md` into the task's
   ignored evidence directory and fill in concrete context, allowed paths,
   acceptance checks, and prohibitions.
4. Confirm each test selector before putting it in the brief. For Xcode, inspect
   the test target and method name; do not infer selectors from prose.
5. Prefer one workstream. Split work only when allowed paths and verification
   resources are disjoint.

### 2. Run OpenCode

```sh
scripts/run-opencode-pass.sh \
  --task retry-day-fix \
  --brief build-logs/evidence-retry-day/implementation-brief.md \
  --allow-path CreatorContentOS/App/AppServices.swift \
  --allow-path CreatorContentOSTests/TodayCardAndPostedFlowTests.swift \
  --timeout-seconds 1200
```

The wrapper always uses non-interactive stdin, DeepSeek V4 Pro medium by
default, JSON event output, a wall-clock timeout, and a repository lock. It
prints one final result line with the evidence directory.

Do not bypass the lock merely to save time. `OPENCODE_PARALLEL=1` is permitted
only when the workstreams have disjoint allowed paths and do not compete for a
simulator, database, build directory, or other mutable resource.

### 3. Codex after OpenCode

1. Read `result.json`, `stderr.log`, `changed-during-run.txt`, and
   `scope-violations.txt`.
2. Review the actual diff critically. Scope compliance is not correctness.
3. Repair weak work directly or issue one narrower follow-up brief.
4. Run focused verification yourself, sequentially when checks share build
   state or external resources.
5. Report both the OpenCode evidence and Codex verification evidence.

Never automatically reset, stash, clean, or revert after a bad pass. The
worktree may contain unrelated user changes; inspect and repair only the files
in scope.

## Result handling

| Result | Meaning | Next action |
| --- | --- | --- |
| `done`, exit 0 | OpenCode exited cleanly and stayed in scope | Review diff and verify |
| `dry_run`, exit 0 | Evidence path and inputs were validated | Inspect evidence, then run for real |
| `opencode_failed` | OpenCode returned nonzero | Read stderr; retry once only if the cause is transient or the brief can be narrowed materially |
| `timeout`, exit 124 | The process group exceeded the bound | Inspect its last events; narrow or implement directly |
| `scope_violation`, exit 3 | A path outside the allow-list changed | Inspect it; do not revert blindly; repair directly |
| exit 2 before evidence | Another pass holds the lock | Wait, or prove workstreams are disjoint before overriding |

If OpenCode stalls in broad reading, goes interactive, refuses the task, or
produces a weak patch, stop relying on it and finish directly. A second pass is
useful only when the new brief is materially narrower.

If the same error occurs twice, stop retrying. Research three to five plausible
fixes, choose the smallest defensible one, record the choice in task evidence,
and only then continue.

## Evidence layout

Each run writes under:

`build-logs/opencode-passes/<task>-<timestamp>-<pid>/`

Important files:

- `brief.md` and `effective-prompt.md`: requested and actual instructions
- `command.txt` and `metadata.json`: reproducible invocation data
- `stdout.jsonl` and `stderr.log`: machine events and diagnostics
- `git-status-before.txt` / `git-status-after.txt`: worktree context
- `manifest-before.tsv` / `manifest-after.tsv`: content hashes
- `changed-during-run.txt`: files changed during this pass, including files
  already dirty before it
- `scope-violations.txt`: changed paths outside the allow-list
- `result.json`: final status, exit codes, timestamps, and evidence path

The harness detects and reports out-of-scope writes; it never undoes them.

## Harness proof

```sh
bash -n scripts/run-opencode-pass.sh scripts/tests/run-opencode-pass-tests.sh
scripts/tests/run-opencode-pass-tests.sh
scripts/run-opencode-pass.sh \
  --task workflow-proof \
  --brief docs/templates/opencode-implementation-brief.md \
  --allow-path docs/templates/opencode-implementation-brief.md \
  --dry-run
```
