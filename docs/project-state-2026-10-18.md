# Project state and collaborator handoff — 18 October 2026

## Source of truth

Repository: https://github.com/prateekranka/instaContentHelper

The laptop checkout at `/Users/prateekranka/Cowork/contenthelper` contained the latest native source found during this audit. It was on `cursor/today-ui-prototype-cea4` at `b299a16edf50b145a74aa1308b853568cdaa4322`, with later uncommitted source edits through 7 October 2026.

GitHub `main` was at `1fc0df2aa2b4f5d79bb41d91dd6eec895c4963d3`. It was 33 commits behind that development branch. Pull request #18 still described a throwaway prototype, although its branch had grown into the native app implementation.

The update preserves those 33 commits and records the later laptop work in a new commit. It was prepared in a separate checkout, `contenthelper-sync-20261018`, so the original dirty checkout remains intact.

## Included work

- Pocket interface across Today, Plan, Shoot Folio, onboarding, Archive, and You.
- Adaptive onboarding, AI consent, Creator Voice, and daily idea preparation from the existing development branch.
- Later native source for package restoration, cached drafts, edited post text, fixture persistence, and DEBUG launch controls.
- Existing TesterArmy e2e suites, screen catalog, locked Node dependencies, and native QA instructions.
- October interface prototypes and existing product, copy, privacy, and decision documents.

The native source and existing test files were copied without feature changes. README and ignore rules were updated for collaborator setup. Deno now uses automatic npm resolution so the recovered Node test setup can coexist with backend checks. Historical `qa-baseline` files remain in Git; their local deletion was not treated as a product change. Local credentials, agent state, screenshots, reports, build products, and caches were excluded.

## Other copies

| Location | Finding | Decision |
| --- | --- | --- |
| Laptop primary checkout | Latest source; working changes through 7 October | Used for this update |
| Laptop storyboard-card worktree | `0cc43fdec29235c1819f6dd4e5fa3225943153a2`, July release work; untracked family guides | Preserved; not used as the native source |
| `linux-ghar-ki-machine` | 17 historical ContentHelper worktree snapshots; copied Git pointers still refer to Mac paths | Compared source hashes with Git history; preserved originals |
| Linux unique files | 42 older source, prototype, and experiment files absent as exact blobs from local Git history; latest unique code from 3 August | Saved in the local audit evidence; not merged into the October implementation |

Linux snapshots include old weekly-generation experiments and an alternative Pocket implementation. Their newer file variants are not evidence of a newer complete app. Most source matches older branches or the former `main`. The audit also found local Supabase metadata dated 13 August; it was excluded from source archives and publication.

A separate `contenthelper-site` directory has its own Git history and no GitHub origin. It is not the native app repository and was not combined with this update.

## Verification

- Native Debug simulator build: passed with Xcode 27.1 beta, using the generic iOS Simulator destination and code signing disabled. Both simulator architectures compiled. The build reported existing warnings: an actor-isolation call in the debug bootstrap, suggestions to use immutable variables, and skipped App Intents metadata. No simulator was started or changed.
- Existing backend validation: `deno task ci:backend` passed; 393 tests passed, 0 failed, and 1 was ignored.
- Node setup: `npm ci --ignore-scripts` passed using the recovered lock file.
- TesterArmy screen catalog: `npx e2e list --config e2e.screens.config.ts` loaded all seven tests. Listing does not execute UI tests.
- Changed-file credential-pattern scan: no matching private keys, common provider tokens, GitHub tokens, or JWTs found. This was a pattern scan, not a full security audit.
- Staged whitespace check: passed. Imported Markdown hard breaks were preserved using explicit line breaks.
- Native source and existing test files: matched the laptop snapshot byte for byte. The original laptop source files were rechecked and remained unchanged.

The earlier October QA reports are historical evidence. They do not establish runtime behavior for this recovered checkout. Package restoration still needs a fresh build, installation, and focused e2e run. Real Apple sign-in, live AI generation, external publication, and physical iPhone behavior require separate checks.

## Collaborator setup

Clone this repository and use `main` after the update. Follow the root README for the native build and backend checks. The native app needs macOS; Linux can run the backend and web prototypes.

Ask the repository owner for runtime configuration through a private channel. Never put service-role keys, provider keys, signing credentials, or local runtime overrides in commits.

Start by installing the new Debug build on an idle simulator. Run the Plan package creation and restart-restoration case in `tests/pocket-screens.e2e.ts`, then the standard `plan` and `ready` scenarios. Use the exact simulator ID, app path, and a new output directory for each run.
