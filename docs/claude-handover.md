# ContentHelper / creatorOS: Claude handover

## Repository and first action

Repository: [prateekranka/instaContentHelper](https://github.com/prateekranka/instaContentHelper). Use the latest `main` branch.

Read this file, visually inspect the full screen review, then summarize your understanding and wait for the owner's next task. This handover alone does not authorize implementation, publishing, deployments, or account changes.

The native source is already in this repository. The screen concepts, research, specifications, prompts, and complete PDF are now included with it. You do not need the old Codex conversations to understand the current direction.

## Complete screen review

- Repository file: [`output/pdf/contenthelper-creator-ios-screens-2026-10-18.pdf`](../output/pdf/contenthelper-creator-ios-screens-2026-10-18.pdf).
- [Open the PDF on GitHub](https://github.com/prateekranka/instaContentHelper/blob/main/output/pdf/contenthelper-creator-ios-screens-2026-10-18.pdf).
- [Download the actual PDF bytes](https://raw.githubusercontent.com/prateekranka/instaContentHelper/main/output/pdf/contenthelper-creator-ios-screens-2026-10-18.pdf).
- The complete file is 17,891,637 bytes, with 10 pages, four screen concepts per page, and 40 screen concepts in total.
- SHA-256: `0eda869068df5bd42200cc1422328ee1ab500c4c1ac8652cfd13e8a96e372330`.

This is the actual PDF stored in Git, not a large-file pointer or a local-only link. Visually inspect every page. The PDF is image based, so a text extractor can return little useful content. If a PDF viewer or GitHub connection cannot display it, use all 10 final PNG boards from the design index. If your session cannot retrieve either format, tell the owner exactly what you could not open; do not claim to have reviewed the screens.

| PDF page | Screen IDs | Final PNG board |
| --- | --- | --- |
| 1 | 01-04 | [First use](design/creator-ios-v1-2026-10-18/01-first-use.png) |
| 2 | 05-08 | [Daily creation and approval](design/creator-ios-v1-2026-10-18/02-daily-create-approve.png) |
| 3 | 09-12 | [Plan and dates](design/creator-ios-v1-2026-10-18/03-plan-review-dates.png) |
| 4 | 13-16 | [Editing and versions](design/creator-ios-v1-2026-10-18/04-edit-and-versions.png) |
| 5 | 17-20 | [Filming and media](design/creator-ios-v1-2026-10-18/05-film-and-attach.png) |
| 6 | 21-24 | [Publishing proposals](design/creator-ios-v1-2026-10-18/06-publish-platforms.png) |
| 7 | 25-28 | [Past work and later edits](design/creator-ios-v1-2026-10-18/07-history-safe-edits.png) |
| 8 | 29-32 | [You and accounts](design/creator-ios-v1-2026-10-18/08-you-and-connections.png) |
| 9 | 33-36 | [Day approval and recovery](design/creator-ios-v1-2026-10-18/09-day-review-and-recovery.png) |
| 10 | 37-40 | [Preferences and privacy](design/creator-ios-v1-2026-10-18/10-preferences-and-privacy.png) |

Each PDF page was rendered and compared with its final PNG during this publication. All 10 matched exactly, with a maximum pixel-channel difference of zero. Representative creation and daily-approval pages were visually inspected again. This proves the PDF includes the final boards; it does not prove the native app matches them.

## Read in this order

1. [Design index](design/creator-ios-v1-2026-10-18/README.md) and the complete screen PDF.
2. [Flow, approval, revision, recovery, and layout specification](design/creator-ios-v1-2026-10-18/flow-and-state-spec.md).
3. [Screen index and routes](design/creator-ios-v1-2026-10-18/screen-index.md).
4. [Social integration proposals and access conditions](design/creator-ios-v1-2026-10-18/platform-integrations.md).
5. [Visual audit and proof limits](design/creator-ios-v1-2026-10-18/visual-audit.md).
6. [Market context](research/market-context-2026-10-17.md) and [the source research PDF](research/micro-creator-co-pilot-market-research-2026-10-17.pdf).
7. [Recorded native source recovery and verification](project-state-2026-10-18.md), then [the root setup instructions](../README.md).
8. [Historical consolidated context](context/contenthelper-context-2026-10-18.md), only if more background is needed.

The owner's latest instruction takes priority. The accepted decisions below and the latest flow specification supersede older one-package-per-date rules in `PRODUCT.md`, earlier research maps, and historical records. The flow specification defines exact behavior and shared layout rules when a raster detail is approximate.

## Accepted product decisions

- Start with the creator alone. Keep the three destinations Today / Plan / You.
- A selected date can contain several independent content pieces. A creator can add another piece after earlier pieces are approved, shot, or posted.
- Main route: choose date, create, review, approve, film, mark as shot, post, revisit, and edit.
- Approve one reviewed piece or a reviewed group. Daily approval shows the actual selected count. Adding a piece preserves previous approvals and shows what still needs review.
- Approval saves a version. It is not an immutable lock and does not authorize publishing. Later edits create a draft revision while preserving approved versions, media, filming progress, and previous posting records.
- Keep media attached to stable shot identities when shots are reordered. Preserve unaffected captured shots when the script or shot list changes.
- Generated shot previews are planning images, not captured footage. Captured clips are not a finished edited video. Direct posting requires selected final media.
- Photo and carousel pieces share the review and approval model, with suitable media language instead of false filming claims.
- All app-owned UI is black, white, and neutral gray. Generated shot previews and uploaded photos or videos retain color. State must also use text or icons.
- Preserve the owner's removal of helper clutter from the four-screen concept. Align primary black buttons through a shared safe-area layout. Filming controls use Previous and Pause.
- Onboarding is short and skippable. Retain topic and content language through Apple sign-in and consent. Ask for AI-data consent before outbound AI work. Declining AI keeps manual tools and saved work usable.
- Instagram and TikTok connections, direct publishing, and insights remain proposals subject to platform access and review. Research the selected API version again before implementation.
- Keep verified Posted, Processing, Finish in platform app, Failed, result unknown, and Marked posted by you distinct for each platform. Existing Mark as posted is local tracking.

## Product purpose and scope

The research proposes an AI creative director and strategist for self-managed micro creators, roughly 10,000-100,000 followers. Mamta, a 60-year-old Indian fitness and Hyrox creator, is the proposed first pilot.

Help creators choose content that fits their identity, decide what to say, and shoot it in their own voice and language with their available energy and equipment. Identity, strategy, suitable trends, and practical shooting guidance lead. Editing, advanced analytics, deals, payments, and agency administration are later research directions, not automatic launch requirements.

Market size, pricing, competitor gaps, and growth outcomes remain hypotheses. Edits already includes storyboards, scripts or teleprompter cues, clips, and notes; do not claim those features alone are unique.

## Native project and recorded verification

- App: native SwiftUI iPhone app. Xcode project and scheme: `CreatorContentOS`. Build product: `ContentHelper.app`. Deployment target: iOS 26.0.
- Backend: Supabase Edge Functions and SQL migrations. Provider credentials belong on the backend.
- Recovered source base: `a3642dd8aa85cb1c7f26a9c0f1ea99ce22e53b44`. The design publication adds documents and assets on top of that base, without changing native source, backend code, or existing tests.
- Before this upload, all 112 relevant native, Xcode-project, and test files in the original checkout matched the recovered published checkout byte for byte.
- The October 18 source recovery recorded a successful unsigned Debug simulator build with Xcode 27.1 beta, 393 backend tests passed, one ignored, seven loadable e2e catalog tests, and successful GitHub backend CI. These are recorded results from that source recovery.
- Runtime e2e did not run during the source sync. Old installed-app package-loss and simulator-lease reports are historical and do not prove the current source fails.
- This design upload verifies file integrity, PDF completeness, documentation links, and GitHub availability. It does not establish current installed-app behavior, real Apple sign-in, live AI generation, external publication, or physical-device behavior.

The root README contains build and environment setup instructions. Runtime overrides such as `CreatorContentOS/Config/LocalRuntime.xcconfig`, provider keys, service-role keys, signing data, agent state, caches, build products, and local QA recordings are not publication inputs. Obtain required configuration privately from the owner.

## Testing and working rules

1. Check the current checkout, branch, and local changes before editing. Do not reset, clean, or overwrite shared work.
2. Use TesterArmy `e2e` for app behavior, UI, and complete flows. Read [the native QA guide](pocket-native-qa.md) and the existing e2e configuration first. If e2e cannot cover the target, obtain the owner's explicit approval before using another method.
3. Do not add unit tests, integration tests, or code comments unless the owner explicitly requests them. Existing tests can be run when relevant.
4. Before runtime checks, verify the exact idle simulator lease, install the matching Debug build, and record the device and build identity. Do not use FlowDeck.
5. Distinguish source checks, build checks, installed runtime checks, physical-device checks, platform publication, and cloud sync. Report only what the evidence supports.
6. Keep credentials and personal runtime data outside commits. Do not make deployments, account connections, live posts, or external account changes from this handover alone.

## Pending work, only when the owner asks

- Install a matching current Debug build on an available simulator.
- Use `tests/pocket-screens.e2e.ts` to verify onboarding, Story 10s, Reel 30s, Reel 60s, and photo/carousel packages through Plan.
- Verify that titles, formats, durations, and saved state survive an app restart. Complete the existing `plan`, `ready`, and other catalog scenarios.
- Compare the native app with the accepted 40-screen specification and propose implementation slices before making design changes.
- Fix observed issues, then update editable design frames from current runtime evidence.

The 40-screen package contains raster concepts and specifications. It is not a native implementation or an editable Pen design. The older editable Pen file remains outside this repository and was not re-audited for this handover. It is not required to open the complete screen review.

## Included supporting material

- All final boards, earlier board versions, exact generation and refinement prompts, packaging script, static measurements, and design specification: `docs/design/creator-ios-v1-2026-10-18/`.
- Market research PDF, working interpretation, earlier flow maps, reference audit, and user-marked four-screen iterations: `docs/research/`.
- The authoritative user-edited four-screen reference is `docs/research/visual-proposal-2026-10-18/contenthelper-creator-flow-concept-v3.png`.
- [Artifact manifest](design/creator-ios-v1-2026-10-18/artifact-manifest.json) records file sizes and SHA-256 hashes for the publication inputs.

Earlier local evidence directories and machine-specific paths in historical reports are not needed to view the design package. Treat them as prior records rather than files that every collaborator must have.
