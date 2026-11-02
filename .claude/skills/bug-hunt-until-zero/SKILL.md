---
name: bug-hunt-until-zero
description: Decide when code is actually done. Runs three independent high-effort bug hunters in rounds; each confirmed bug gets fixed and the hunt repeats until one full round finds zero confirmed bugs. Use when asked to "find all the bugs", "keep reviewing until clean", or to answer "how do I know this is done?" for a branch, diff, or module.
---

# Bug hunt until zero

A single review always finds something new. This skill turns that into a
stopping rule: keep hunting in rounds until three independent hunters all
come back empty in the same round. Based on a prompt shared by @argofowl.

## Scope first

Name the target before the first round: a diff (`git diff <base>...HEAD`),
a set of files, or a module. Hunters only report bugs inside it. Read the
project's own instructions (CLAUDE.md, AGENTS.md, README) and pass the
relevant rules to every hunter.

## One round

1. **Hunt.** Start three hunters in parallel, each at the highest
   reasoning effort available, each with no memory of earlier rounds. If
   your agent cannot run subagents, run three separate passes yourself
   with a fresh read each time. Give each hunter a different lens so they
   do not repeat each other:
   - Logic and data: wrong results, edge cases, state that gets lost or
     duplicated, off-by-one, null and empty input.
   - Failure paths: errors swallowed, retries, timeouts, partial writes,
     concurrency and ordering, cancellation.
   - Contracts: callers and callees that disagree, broken invariants,
     API, schema, or UI behavior that no longer matches its spec or tests.
   Each hunter is read-only and returns, for every bug: file and line, the
   exact input or state that triggers it, what goes wrong, and how sure it is.
2. **Confirm.** For every reported bug, prove it before fixing: a failing
   test, a reproduction command, or a precise trace through the code.
   Reject style notes, speculative risks, and duplicates. Only confirmed
   bugs count.
3. **Fix.** Fix confirmed bugs one at a time, smallest change first. Run
   the project's checks (build, lint, tests) after each fix. Do not let two
   hunters edit the same files at once.
4. **Repeat.** Start the next round with fresh hunters against the updated
   code.

## When to stop

- **Done:** one full round where all three hunters report zero confirmed bugs.
- **Stop and ask:** after 5 rounds, or when the same area keeps producing
  new bugs (a sign it needs redesign, not patches), or when a fix needs a
  product decision.

## Report

- Rounds run, and confirmed bugs per round.
- Each fix: the bug, the file, and the proof it was real.
- Reported issues you rejected, and why.
- What the hunt did not cover (areas outside scope, untested platforms).
