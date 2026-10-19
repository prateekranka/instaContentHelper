---
name: better
description: Push the current task or a given prompt toward a deeper, more expert version of itself. Use only when the user types /better or $better.
---

# Better

Before rewriting or redoing anything, answer four questions about the task:

1. **Expert move.** What would a top professional in this field do that the user has not asked for?
2. **Raw material.** What is the most direct source they would start from, rather than summaries or memory?
3. **Methods.** Which specific methods and tools would they use?
4. **Outside proof.** What, other than the agent's or the user's opinion, would show the result is right?

## Case A: a prompt that has not started

Answer the four questions, then give a rewritten prompt that includes the answers. Do not carry out the task.

## Case B: work already in progress

1. Answer the four questions for the current task.
2. Rewrite the brief, folding in the user's earlier feedback.
3. If the rewrite changes the goal or scope, spends money, or needs new access, stop and ask the user before acting.
4. Otherwise redo the work from the raw material with the named methods, run the outside proof, and report what it showed, including any limits.

## ContentHelper notes

- Raw material: the 40-screen boards and `flow-and-state-spec.md`, the current source, the installed simulator build, and a creator's real use.
- Outside proof for app behavior is TesterArmy e2e on a matching Debug build. Compilation needs Xcode on macOS. A Linux session can only typecheck Foundation code and run backend checks.
- Deployments, account connections, paid CI time and external service changes need the owner's approval first.
