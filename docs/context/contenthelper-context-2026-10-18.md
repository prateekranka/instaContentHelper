# ContentHelper consolidated context — 2026-10-18

## Context ownership

This file preserves the October 18 context consolidation. The owner later moved the active conversation to a fresh chat because the old chat was difficult to load on an iPad. Older chats are historical sources; they do not have exclusive working ownership. For a portable project handover, start with [the Claude handover](../claude-handover.md). Local checkout paths and thread IDs below are historical references, not required setup paths.

## Verified local source state

- Repository: `https://github.com/prateekranka/instaContentHelper`.
- Current checkout: `/Users/prateekranka/Cowork/contenthelper`, branch `cursor/today-ui-prototype-cea4`, HEAD `b299a16edf50b145a74aa1308b853568cdaa4322`. It retains the original shared changes. Do not reset it.
- Published checkout: `/Users/prateekranka/Cowork/contenthelper-sync-20261018`, branch `sync/contenthelper-latest-20261018`, HEAD `a3642dd8aa85cb1c7f26a9c0f1ea99ce22e53b44`. It is clean. Its local `origin/main` reference points to the same commit.
- All 100 files under published `CreatorContentOS` and all seven files under published `tests` match the current checkout byte for byte. No additional current Swift files are missing from the published checkout.
- The source sync retained existing development history. It included the Pocket UI and package-restoration work through October 7. It excluded local credentials, agent state, generated reports, caches, and build products. It retained historical `qa-baseline` files.
- The source thread reported GitHub `main` at `a3642dd8` after a verified push. This consolidation checked local references and saved evidence; it did not make a new network query.

## App decisions

### Latest creator design direction, October 18

The user authorized multiple content pieces per date, approval by piece or by reviewed day, later edits with saved revisions, and the continuing Shot/Posted workflow. This replaces the older one-package-per-date product rule. Approval is a saved version, not an immutable lock. App-owned UI is monochrome; generated shot previews and uploaded photos/videos retain color.

The new proposal has 40 screen concepts in `docs/design/creator-ios-v1-2026-10-18/README.md`, with daily state rules, a screen index, current social API research, exact prompts and a static visual audit. The review PDF is `output/pdf/contenthelper-creator-ios-screens-2026-10-18.pdf`. Instagram/TikTok publishing, account access and metrics are proposed conditional integrations, not implemented or connected features. Native implementation and e2e remain separate work.

### Existing implementation and earlier scope

- ContentHelper is a native SwiftUI iPhone app. Its Xcode scheme is `CreatorContentOS`; its app bundle is `ContentHelper.app`.
- The creator workflow is Today → Plan → Shoot Folio. “Mark as posted” records local completion and does not publish to Instagram.
- The current implementation covers Today, Plan, Shoot Folio, adaptive onboarding, Archive, You, AI consent, editable post text, cache recovery, fixture persistence, and package restoration.
- The recorded launch scope retains Apple sign-in, one short skippable choice screen, optional preferences in You, and a first useful script/storyboard/caption package. Sharing is separate work.
- Older Linux experiments were preserved separately. They were not merged into the October implementation. The sync evidence records 17 historical snapshots and 42 unique source files preserved.

## October 18 verification evidence

Evidence directory: `work/evidence/contenthelper-github-sync/20261018T105013Z.ESx73e`.

- `sync-verification.json` records commit `a3642dd8`, no drift in the original source snapshot, 393 backend tests passed, zero failed, one ignored, and seven loadable screen-catalog tests.
- `native-build.stdout.log` ends with `** BUILD SUCCEEDED **`. This was an unsigned Debug simulator build with Xcode 27.1 beta. Existing warnings remain, including an actor-isolation warning in the debug bootstrap.
- `github-ci.stdout.log` records successful backend workflow `39121334488` for the published version.
- `collaborator-invitation.json` records a write-access invitation for `@nikhilranka`. The source thread reported it pending acceptance. Acceptance was not rechecked here.
- Runtime E2E tests were not run during that sync. Compilation and test listing do not prove installed app behavior.

The new successful build supersedes this thread's earlier “source remains unbuilt” conclusion. The October 7 simulator lease reports are historical and must not be treated as current device ownership.

## Remaining runtime and design work

1. Verify the current simulator lease and install the October 18 Debug build that matches the published source. The build product is under the evidence directory at `DerivedData/Build/Products/Debug-iphonesimulator/ContentHelper.app`.
2. Use TesterArmy `e2e` to run `from onboarding, create and restore four Story, Reel, and photo packages through Plan` in `tests/pocket-screens.e2e.ts`.
3. Prove the Story 10-second, Reel 30-second, Reel 60-second, and photo/carousel packages survive a same-session app restart with their original title, format, duration, and saved state.
4. Run the existing `plan` and `ready` scenarios and complete the remaining screen-catalog checks on the installed build. Use e2e as the only app behavior/UI framework.
5. Fix observed issues, then refresh the editable Pen document from current runtime evidence.

The prior installed-app run lost the October 8 package after restart. Evidence is in `work/evidence/contenthelper-break-ui/20261007-onboarding-plan/catalog-goal-run-13-plan-relaunch/report.json`. That run used an older installed app and does not prove the current source fix fails.

This thread's Pen artifact is `/Users/prateekranka/.pencil/documents/61f97ad2-a3bf-4ae1-b04f-5d8c4cb32c42/pencil-new.pen`. Prior audit evidence records 95 editable screen frames, three reusable components, four motion boards, no screenshot image nodes, and no unfinished placeholders. It was not re-audited during this context import. Access `.pen` contents only through Pencil tools.

## Market research input

The user supplied Nikhil Ranka's October 17 Micro-Creator Co-Pilot market research. The unchanged PDF is preserved at `docs/research/micro-creator-co-pilot-market-research-2026-10-17.pdf`; its working interpretation is `docs/research/market-context-2026-10-17.md`. The thesis is strategy and creative direction for self-managed micro creators, with creator identity and practical shooting guidance at the centre and deal administration later. Treat its market sizes, pricing, competitor gaps, and agency comparisons as hypotheses that need validation. The import does not change accepted launch scope.

## Primary handoff

The published project handoff is `/Users/prateekranka/Cowork/contenthelper-sync-20261018/docs/project-state-2026-10-18.md`. It contains setup instructions, the recorded build and backend results, and the remaining native runtime checks. Real Apple sign-in, live AI generation, external publication, and physical iPhone behavior require separate evidence.
