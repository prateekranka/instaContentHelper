# Mira repository instructions

## Owner's testing policy

- Do not write, generate, restore or run unit tests for this app, backend, tracker
  or supporting scripts. Do not add unit-test targets, frameworks or runners.
  This owner instruction supersedes earlier unit-test requirements in the plan
  and historical documentation. Never add unit tests after writing implementation.
- Prefer end-to-end (E2E) tests as the main way to verify behavior. Use them to
  check complex features through realistic scenarios of medium or high complexity,
  including relevant failure and recovery paths, rather than only a simple success.
- E2E checks must produce reviewable, reproducible artifacts. Preserve the command,
  setup and fixture prerequisites, environment/version details, expected and observed
  behavior, and relevant traces, screenshots or recordings. Exclude secrets.
- Before implementing work that requires testing a system in isolation, first list
  its failure modes. Then write the implementation. Use the approved non-unit
  verification method for those failure modes.
- Avoid tautological tests that repeat implementation logic and tests whose only
  purpose is detecting code changes.
- For a bug fix, add a regression scenario only when existing behavior checks leave
  a real coverage gap.
- Use the repository's existing TesterArmy E2E gate for supported app/UI flows.
  Compilation, type checks and static inspection are useful supporting checks but
  do not establish runtime behavior. Report unavailable native checks accurately.

## Workflow

Work without subagents. Keep the public Mira tracker updated with actual timestamps,
verification results, blockers and remotely verified GitHub commit links.
