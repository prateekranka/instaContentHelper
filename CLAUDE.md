# ContentHelper / Mira

Mira is the current native app. Start with the [README](README.md), [Mira implementation plan](docs/mira-implementation-plan.md), and [Mira handoff](docs/mira-handoff.md). Check [the latest Today and ideas evidence](docs/mira-evidence/2026-11-27-phase-d1.md) before working on those screens. For current source and verification status, check the files and revision for the task.

Earlier Creator Loop lifecycle and data ownership decisions are covered in [the redesign plan](docs/design/creator-loop-redesign.md) and [the flow and state specification](docs/design/creator-ios-v1-2026-10-18/flow-and-state-spec.md). The historical [design index](docs/design/creator-ios-v1-2026-10-18/README.md) links to the original PDF and boards.

## Working rules

- Keep the native SwiftUI iPhone app, scheme `CreatorContentOS`, and product `ContentHelper.app`.
- Follow the current Mira navigation and project notebook. Preserve independent pieces and editable approved versions when maintaining the earlier data contracts.
- Preserve existing work, saved revisions, media, filming progress, and platform posting records.
- App-owned UI is black, white, and neutral gray. Generated previews and uploaded media keep their color.
- Treat the new screens and social integrations as proposals until implemented and verified.
- Use TesterArmy `e2e` as the only framework for app behavior, UI, and complete flows. If it cannot cover a target, obtain the owner's explicit approval before another testing method.
- Never add unit tests, integration tests, or code comments unless the owner explicitly requests them.
- Inspect the current checkout, branch, local changes, simulator lease, and installed build before making changes or runtime claims. Do not reset shared work. Do not use FlowDeck.
- Do not commit credentials or private runtime configuration. Do not deploy, connect accounts, post content, or change external services without the owner's authorization for that action.
- Report verified results and their limits in short, plain sentences.

## Correction rules and enforcement

Run `python3 scripts/check-agent-rules.py` before handing off a change.
The same command runs in `.github/workflows/backend-checks.yml`.
`python3 scripts/prove-agent-rules.py` proves the checks against past mistakes locally and in CI.
Both commands require Python 3 and Git history containing `8ce636a` and its ancestors. They do not run the app.

| Rule | Enforcement and supported API |
| --- | --- |
| Keep one mutable day owner and one durable queue. Do not add stored day/package/progress copies to app services or views. | `DayStore` keeps private setters. `state_ownership` rejects added typed mutable owners. Use `DayStore.transition`, `DayStore.projection`, and `ContentIntent` through `AppServices`. |
| Reuse date formatters. Do not add per-call `DateFormatter` or `ISO8601DateFormatter` construction. | `formatter_allocation` rejects added allocations by file and declaration scope. Extend `SupabaseDateFormatting` and its mutex-protected formatter cache. |
| Read cached cards during presentation. | `card_projection` rejects added direct revision conversions and draft conversion calls outside the model owner. Use `DayStore.projection(for:revisionID:)`, `card(revisionID:)`, or `readyCards`. |
| Save snapshots asynchronously through the ordered service path. | `TodayCacheStoring` exposes only async saving, without a synchronous fallback. `snapshot_persistence` rejects restoring that fallback or adding synchronous app-flow saves. Use `AppServices.persistDaySnapshot` or `queueDaySnapshot` and `FileTodayCacheStore.saveSnapshotInBackground`. |
| Scroll controls through the shared helper, including sheet controls. | `scroll_controls` forbids raw `scrollUntilVisible` outside `scrollToControl` and checks its dock boundary calculation. Use `scrollToControl` or `tapVisibleControl` in `tests/pocket-support.ts`. |
| Preserve accessibility identifier ownership. Keep format and duration discoverable as one exact text value. | `accessibility_identity` rejects missing identifiers and added duplicate owners. The existing screen-catalog assertion for `Story · 10 sec` checks the text-node contract when the owner runs e2e. |

The source checks compare existing patterns with the fixed Step 5 baseline. They do not add exceptions
or permit new exception markers. Existing repeated patterns can stay while additions fail.
These are source checks, not a Swift type checker or runtime accessibility audit.
Keep the existing 600 ms filming tap guard. Timing changes require the owner's e2e run.
See [the correction report](docs/design/step6-correct.md) for evidence, limits, and separate commit groups.
