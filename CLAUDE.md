# ContentHelper / creatorOS

Read [the complete Claude handover](docs/claude-handover.md) before changing this project.

## Start with the screens

- Open the [complete screen review PDF](output/pdf/contenthelper-creator-ios-screens-2026-10-18.pdf). It has 10 pages and 40 screen concepts.
- Visually read every page. This PDF contains images; text extraction alone does not show the designs.
- If the PDF viewer cannot open it, inspect all 10 final PNG boards in [the design index](docs/design/creator-ios-v1-2026-10-18/README.md). Files ending in `-initial.png` are earlier drafts.
- Read the [flow and state specification](docs/design/creator-ios-v1-2026-10-18/flow-and-state-spec.md). Its behavior and layout rules take priority over approximate raster details.

## Working rules

- Keep the native SwiftUI iPhone app, scheme `CreatorContentOS`, and product `ContentHelper.app`.
- Keep Today / Plan / You, several independent pieces per date, and editable approved versions. These latest decisions replace older one-package-per-day rules.
- Preserve existing work, saved revisions, media, filming progress, and platform posting records.
- App-owned UI is black, white, and neutral gray. Generated previews and uploaded media keep their color.
- Treat the new screens and social integrations as proposals until implemented and verified.
- Use TesterArmy `e2e` as the only framework for app behavior, UI, and complete flows. If it cannot cover a target, obtain the owner's explicit approval before another testing method.
- Never add unit tests, integration tests, or code comments unless the owner explicitly requests them.
- Inspect the current checkout, branch, local changes, simulator lease, and installed build before making changes or runtime claims. Do not reset shared work. Do not use FlowDeck.
- Do not commit credentials or private runtime configuration. Do not deploy, connect accounts, post content, or change external services without the owner's authorization for that action.
- Report verified results and their limits in short, plain sentences.
