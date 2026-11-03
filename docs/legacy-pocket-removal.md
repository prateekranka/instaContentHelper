# Retired Pocket client removal

The owner requested removal of the old Today / Plan / Shoot Folio implementation. Mira is now the only app entry in both Debug and Release.

## Scope

- Remove Creator and Admin shells, Pocket screens and design components, the old onboarding and account settings screens, and their debug launch routes.
- Remove client-only dated-content models, repositories, fixtures, cache, outbox, reference importing, notifications, and background generation benchmark.
- Remove the retired Pocket E2E suites and configuration. Keep the Mira demo journey, move its shared mobile helpers to `tests/mobile-support.ts`, and make Mira the default E2E configuration.
- Remove deleted Swift files from the checked-in Xcode project and remove the benchmark task identifier from both app manifests.
- Retain Apple authentication, existing Keychain sessions, workspace-scoped AI consent records, provider disclosure, Instagram OAuth and insights, and Mira's existing project repository. Sign-in uses Mira components.
- Keep backend functions, migrations, historical documents, historical native test sources, and prototypes. No cloud changes or stored-data deletion occur.

## Failure modes to check

1. Deleted source files remain in the Xcode target or surviving code references removed types.
2. A stale debug flag can still select the retired shell.
3. Removing the old runtime breaks Apple authentication, AI consent, or Instagram insights.
4. Root lifecycle callbacks still refresh dated packages, replay old work, or register a deleted background task.
5. Default E2E configuration targets removed screens, or the Mira journey loses its mobile helpers.
6. Mira project persistence changes or old saved data is removed.

## Verification

- All six repository source-rule groups passed. Their 12 historical/reconstructed regression cases still fail as expected under `python3 scripts/prove-agent-rules.py`.
- Swift syntax parsing passed for all 34 remaining app source files. This is syntax evidence, not compilation or type checking.
- The checked-in Xcode project parses; all 115 object references are valid, and its 34 Swift build entries resolve exactly to the remaining app sources.
- The retired client types, routes, refresh callbacks and benchmark registration are absent from active app source.
- Mira core/persistence, Keychain/session storage, AI-consent storage, and Instagram data services match the baseline byte for byte. Backend source is unchanged.
- `npm ci --ignore-scripts --cache work/npm-cache --no-audit --no-fund` passed. `npx e2e list --reporter json` loads the existing Mira journey on `mira-ios` through the default configuration. Listing does not execute it.
- `git diff --check` passed.

Native compilation and the existing Mira TesterArmy journey require macOS/Xcode and a matching booted simulator; this Linux environment has no Swift toolchain, Xcode or simulator. No native runtime, real Apple sign-in, live provider or live Instagram check was run. Source checks do not establish native runtime behavior.

The public tracker update is retained in the ignored local pending queue. This session has no tracker write credentials, so the public board was not changed.
