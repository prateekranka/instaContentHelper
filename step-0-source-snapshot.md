# Step 0 — Source and tool snapshot

Recorded: 7 September 2026, 18:25 IST.
Repo tree used: `/Users/prateekranka/Cowork/contenthelper`.
Mode: read-only. No app source edited. No stash, reset, clean, rebase, fetch-with-write, commit, push, deploy, or discard.

Remote: `https://github.com/prateekranka/instaContentHelper.git` (public).

## Live vs pinned SHAs

| Ref | Pinned (plan) | Live (this snapshot) | Status |
| --- | --- | --- | --- |
| Local branch | `cursor/today-ui-prototype-cea4` | `cursor/today-ui-prototype-cea4` | match |
| Candidate HEAD | `20766cd90fd6338592d8fb7792395f566eda1205` | `20766cd90fd6338592d8fb7792395f566eda1205` | match |
| Live `origin/main` (`git ls-remote`) | `1fc0df2aa2b4f5d79bb41d91dd6eec895c4963d3` | `1fc0df2aa2b4f5d79bb41d91dd6eec895c4963d3` | match |
| Local cache `origin/main` | same as live | `1fc0df2aa2b4f5d79bb41d91dd6eec895c4963d3` | cache not stale; no fetch needed |
| Live remote branch `cursor/today-ui-prototype-cea4` | `20766cd9…` | `20766cd90fd6338592d8fb7792395f566eda1205` | match; local tracks origin, not ahead/behind |
| `git merge-base HEAD origin/main` | current main | `1fc0df2aa2b4f5d79bb41d91dd6eec895c4963d3` | current main is the merge base |

HEAD subject: `Stop generate_day from forcing lifestyle on books/movies profiles.` (2026-09-05 23:46 IST).

Geometry vs current main (names only, not executed as a review): 32 commits ahead, 0 behind; `128 files changed, 23739 insertions, 1747 deletions`. Matches the plan.

Native source of the app is `CreatorContentOS/`, not `prototypes/today-ui/`.

## Native dirty check

`git status --porcelain=v1` on `CreatorContentOS/`, `CreatorContentOSTests/`, `InstalledContentHelperUITests/`, and `project.yml`: empty.

No uncommitted native source. Step 0 STOP condition not triggered. Preserve the rest of the worktree.

## Dirty-work exclusions (do not commit or delete)

`git diff --stat HEAD`: only `prototypes/today-ui/index.html` (`318` hunk lines: `+181 / -137`). Not staged.

Porcelain `-uall` counted 1 modified tracked file and 11,554 untracked paths at first read. Almost all untracked paths are `.derivedData/` index/cache files (11,445). `.gitignore` ignores `DerivedData/` (capital D) and `build-logs/`, not `.derivedData/`.

### Prototype (preserve; not native app)

- Modified tracked: `prototypes/today-ui/index.html`
- Untracked screenshots: `artifacts/prototypes/today-ui/` (v1–v3, riff, shell, empty-today)

### Native app source

- None dirty. Do not treat the HTML prototype as native.

### QA / local evidence / scratch (preserve; do not auto-commit)

- `.asc/` — IPA, xcarchive, App Store profiles, smoke screenshots
- `.maestro/` — README, config, `flows/signed-out-launch-smoke.yaml`
- Untracked `scripts/maestro.sh`
- `.scratch/` — first-run onboarding, pocket-sheet, prototype-feedback issue maps
- `.hermes/plans/contenthelper-release-first-cursor-20260907.md`
- `.codex/config.toml` (Maestro MCP approvals only; no tokens in the file)
- `artifacts/adaptive-onboarding-qa/` — screenshots plus `live-generate-day-evidence-run.json`
- Repo-root PNG captures: `contenthelper-persisted-gemini-storyboard.png.png`, `contenthelper-selected-day-published.png.png`, `contenthelper-today-published-card.png.png`
- `.derivedData/` — local Xcode index/cache (11,445 untracked files)
- Appeared during this snapshot window (parallel read-only work; preserve): `document-a-refresh.md`, `document-b-refresh.md`

### Secrets / signing / ignored local config (do not commit or print)

- Untracked signing/export: `.asc/profiles/*.mobileprovision`, archive `embedded.mobileprovision`, `.asc/artifacts/ContentHelper.ipa`, `.asc/artifacts/ContentHelper.xcarchive/`
- Gitignored and present: `CreatorContentOS/Config/LocalRuntime.xcconfig`
- Gitignored and absent here: `supabase/.env`, `supabase/functions/.env`
- `gh auth status` showed a redacted token line; not copied into this file

Do not stash, reset, clean, or delete any of the above to make later steps easier.

## Repo instructions that affect execution

- Root `AGENTS.md`: not present in this repo.
- Root `CONTEXT.md`: present. Product language: Creator, Today, Shoot Folio, Plan, ready package, Archive, Sign in with Apple. Native iPhone creator loop.
- `project.yml`: present. `CURRENT_PROJECT_VERSION: "2026081102"`. `MARKETING_VERSION: "1.0"`. Release pre-build script calls `scripts/require-live-release-bootstrap.sh`.
- `scripts/require-live-release-bootstrap.sh`: present and executable. Release builds must have a live `https://` `MCO_SUPABASE_URL` and a real `MCO_SUPABASE_PUBLISHABLE_KEY`. Localhost / placeholder values fail Release.
- `README.md`: local iOS via `xcodegen generate`; backend via `deno task ci:backend`.
- No root `package.json`. No `Makefile`.
- GitHub workflow: `.github/workflows/backend-checks.yml` only.

## Tool path / version table

Checked with `which` / `--version`. Nothing installed.

| Tool | Path | Version / notes |
| --- | --- | --- |
| deno | `/opt/homebrew/bin/deno` | 2.8.1 (V8 14.9.207.2-rusty, TypeScript 6.0.3) |
| xcodegen | `/opt/homebrew/bin/xcodegen` | 2.45.3 |
| xcodebuild | `/usr/bin/xcodebuild` | Xcode 26.6, build 17F113 |
| Xcode developer dir | `/Applications/Xcode.app/Contents/Developer` | `xcode-select -p` |
| iOS SDKs (read-only `-showsdks`) | n/a | iOS 26.5 (`iphoneos26.5`), Simulator iOS 26.5 |
| Swift | Apple toolchain | Swift 6.3.3 |
| gh | `/opt/homebrew/bin/gh` | 2.89.0 (2026-03-26) |
| cursor-agent | `/Users/prateekranka/.local/bin/cursor-agent` → `~/.local/share/cursor-agent/versions/2026.08.31-4057e58/cursor-agent` | 2026.08.31-4057e58 |
| swiftlint | missing | expected missing; no complexity claims from it |
| lizard | missing | expected missing; no complexity claims from it |

## Cursor child model slugs (this installation)

Evidence, not a claim that a child ran.

1. This Cursor session’s Task/subagent allow-list: `inherit`, `composer-2.5`, `composer-2.5-fast`, `cursor-grok-4.6-xhigh`.
2. `cursor-agent --list-models` on this Mac includes `composer-2.5`, `composer-2.5-fast`, `cursor-grok-4.6-xhigh`, `cursor-grok-4.6-xhigh-fast`, plus many other CLI models.

Step 0 did not launch Composer 2.5 Fast. Do not claim it ran here.

Orchestrator for this step: Cursor Grok 4.6 (this session).

## CI / test commands discovered (names only; not executed)

Deno tasks (`deno.json`):

- `check:backend`
- `test:backend`
- `ci:backend`
- `benchmark:day-generation-under-60`

GitHub Actions:

- workflow `backend-checks.yml` / job `Deno contracts` → `deno task ci:backend`

Xcode / project (from `project.yml` and README):

- `xcodegen generate`
- scheme `CreatorContentOS` (build + `CreatorContentOSTests`)
- scheme `InstalledContentHelperUITests`
- pre-build: `scripts/require-live-release-bootstrap.sh` (Release only)

Local scripts present (not run):

- `scripts/tests/run-opencode-pass-tests.sh`
- `scripts/run-opencode-pass.sh`
- `scripts/onboarding-books-movies-live-smoke.ts`
- `scripts/live-weekly-setup-smoke.ts`
- `scripts/live-write-boundary-smoke.ts`
- `scripts/day-generation-under-60-benchmark.ts`
- `scripts/day-generation-under-60-benchmark_test.ts`
- `scripts/day-generation-reliability-experiment.ts`
- `scripts/ai-day-generation-prompt-benchmark.ts`
- `scripts/build-testflight-release.sh`
- `scripts/launch-testflight.sh`
- `scripts/fast-sim-refresh.sh`
- untracked `scripts/maestro.sh`

No `npm test`. No `make test`.

## Build number vs last uploaded 2026081102

`project.yml` `CURRENT_PROJECT_VERSION` is `2026081102`.

`CreatorContentOS/Info.plist` `CFBundleVersion` is `$(CURRENT_PROJECT_VERSION)`.

This matches the last uploaded App Store Connect build `2026081102`. A later upload needs a newly verified unused number. Do not bump in Step 0.

## GitHub auth / Discussions

- `gh auth status`: logged in to github.com as `prateekranka` via keyring. Git protocol https. Scopes reported: `delete_repo`, `gist`, `read:org`, `repo`, `workflow`. Token value not recorded.
- Repo Discussions: `hasDiscussionsEnabled: false` / `has_discussions: false`. GraphQL `discussions.totalCount` is 0.
- Discussions were not enabled. Status only.

This blocks later GitHub Discussions publication. It does not block Step 1 read-only reviews.

## Step 1 may proceed?

Yes. This snapshot matches the pinned SHAs. Native `CreatorContentOS/` is clean. Required tools (`deno`, `xcodegen`, Xcode/`xcodebuild`, `gh`, `cursor-agent`) are present. `swiftlint` and `lizard` are missing as expected.

Step 1 must use this tree and these SHAs. Triage uncommitted prototype/QA files separately from the 32-commit main→HEAD delta. Do not start from the August uploaded binary.

## Blocker (one line)

None for Step 1; GitHub Discussions stay off for later publication, and a new TestFlight upload still needs a build number other than `2026081102`.
