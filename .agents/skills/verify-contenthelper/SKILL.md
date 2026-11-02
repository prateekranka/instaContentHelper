---
name: verify-contenthelper
description: Build, install, check, drive, and prove the ContentHelper (creatorOS) native SwiftUI iPhone app on the iOS simulator with TesterArmy e2e. Use before claiming any app change works, to screenshot or record a screen, to reproduce a bug, or to bug bash onboarding, Today, filming, Post, Plan, or You.
---

# Verify ContentHelper

Read the e2e skill first (`npx e2e guide` prints it). This skill only says
what is true of this app. The config is `e2e.config.ts` (one target,
`contenthelper-ios`, engine `@e2e-dev/mobile`, iOS). It runs one test file
per scenario, `tests/pocket-<suite>.e2e.ts`, picked by
`POCKET_E2E_SCENARIO`. `e2e.screens.config.ts` spreads it and adds the
screen catalog in `tests/pocket-screens.e2e.ts`. The scenario list is in
[docs/pocket-native-qa.md](../../../docs/pocket-native-qa.md).

## Launch

The app is not started by a command. e2e installs a built `.app` on an
already-booted simulator and launches it with fixture flags.

0. Point the tools at Xcode. On this Mac `xcode-select` names the
   Command Line Tools, so `simctl` and `xcodebuild` fail without this:
   `export DEVELOPER_DIR=/Applications/Xcode-27.1-beta.app/Contents/Developer`.
   Check with `xcrun simctl help`; skip it once `xcode-select -p` names Xcode.
1. Pick the simulator. The config defaults to the iPhone 18 Pro
   `7AEFF457-CBA5-4485-A13D-896E75169E07`; set `POCKET_E2E_DEVICE=<udid>`
   for another booted iPhone. It must already be booted:
   `xcrun simctl list devices booted`.
2. Build the Debug app (about 5 minutes cold, under 1 minute warm):

   ```bash
   xcodebuild -project CreatorContentOS.xcodeproj -scheme CreatorContentOS \
     -configuration Debug \
     -destination "id=${POCKET_E2E_DEVICE:-7AEFF457-CBA5-4485-A13D-896E75169E07}" \
     -derivedDataPath DerivedData/Verify build
   ```

3. Install it through e2e. This binds the exact device, so video is off
   for this run:

   ```bash
   POCKET_E2E_INSTALL=1 \
   POCKET_E2E_APP=$PWD/DerivedData/Verify/Build/Products/Debug-iphonesimulator/ContentHelper.app \
   POCKET_E2E_OUTPUT=$PWD/.e2e/proof/install \
   npx e2e run --grep 'Pocket opens'
   ```

Every later run launches the installed app with
`MCO_FORCE_FIXTURE_UI=1`, `MCO_FORCE_APP_MODE=creator`, and a fresh
`MCO_QA_SESSION`. Fixture mode needs no network, account, AI provider,
or `CreatorContentOS/Config/LocalRuntime.xcconfig`. Rebuild and
reinstall after every Swift change; a test change needs neither.

## Doctor

```bash
npx e2e list
POCKET_E2E_OUTPUT=$PWD/.e2e/proof/doctor npx e2e run --grep 'Pocket opens'
```

`list` loads the config and starts nothing; it fails on a config or
dependency problem (`npm ci` first in a fresh checkout). The run opens the
app through optional onboarding and pins `today.startFilming`; exit `0`
means the simulator, the installed build, and the fixture data all work.
`xcrun simctl get_app_container <udid> com.prateekranka.creatorcontenthelper`
failing means the app is not installed: go back to Launch step 3. Run
Doctor first whenever anything looks off, and again after any failed run.

## Drive

Scripted, the default: a test under `tests/`, one scenario per run.

```bash
POCKET_E2E_SCENARIO=<scenario> POCKET_E2E_SESSION=<unique-name> \
POCKET_E2E_OUTPUT=$PWD/.e2e/proof/<name> npx e2e run
```

The screen catalog (one screenshot and layout per screen, no video) is
`npx e2e run --config e2e.screens.config.ts`; it writes
`screen-catalog.json` and `screenshots/` under `POCKET_E2E_OUTPUT`.

Scenarios: `ready`, `onboarding`, `retry`, `slow`, `plan`,
`alternatives`, `empty`, `large`, `long`, `motion`, `sync-error`,
`welcome`. Each one selects its suite and launch flags in
`e2e.config.ts`. Use `screen.getByTestId(...)` for every control in the
feature map; the ids are SwiftUI `accessibilityIdentifier`s. The config
has no model, so tests use no `agent.*` steps.

Use the helpers in `tests/pocket-support.ts`; they encode how this app
behaves under automation:

- `startFromOnboarding(app, screen)`: every creator journey starts here.
- `scrollToControl(screen, locator, direction?, bottom?)`: scrolls the
  app's own scroll view until the control is fully above the floating tab
  bar, and waits for it to stop moving. Use it, not
  `screen.scrollUntilVisible`, before tapping something near an edge.
- `dismissKeyboard(screen, '<id>.keyboardDone')`: taps the keyboard Done
  button where it is now, and retries until the keyboard is gone.
- `tapEditorControl` and `tapVisibleControl`: tap by fresh geometry when
  the runner reports a false overlap.
- `selectTab(screen, 'Today' | 'Plan' | 'You')`.

Live, over MCP: `.mcp.json` registers `npx e2e mcp` for Claude Code. It
loads in a new session. Then `open_session`, `observe`, the verbs, and
`locate` before any new locator. A live session launches the installed
app without the scenario flags; use it to look and to try locators, and
prove behavior with a scripted run.

## Evidence

Always pass `POCKET_E2E_OUTPUT`. Without it, the config writes into
`work/pocket-native-build/20261002T181853Z.kT7Urb/`, an old task folder.
Each run writes `report.json` there; each test gets
`artifacts/contenthelper-ios/<test>/default/attempt-0/` with numbered
`screenshots/` (the `app.screenshot` names), `video/video.mp4` with
`video.gesture-telemetry.json` (every tap and swipe with its point), and
on failure `failure/screen.txt` (the accessibility tree at failure) and
`failure.png`. `.e2e/proof/` is gitignored and survives later runs.

A proof drives the real user path from onboarding, captures the action
and the state after it, and checks side effects. The app saves fixture
state in its simulator container:

```bash
D=$(xcrun simctl get_app_container <udid> com.prateekranka.creatorcontenthelper data)
ls "$D/Library/Application Support/CreatorContentOS/FixtureQA/<session>/"
P="$D/Library/Preferences/com.contenthelper.fixture.<session>.plist"
plutil -extract archive raw -o - "$P" | base64 -D   # JSON list, newest first
```

The folder holds `today-<ids>.json` (one file): `todayCard` (`title`, `script`,
`caption`, `scenes`, `scheduledDate`) and `weekCards` (the Plan days).
The plist holds `archive` (the You history; each entry has a
`decision` such as `posted` or `usedBackup`, newest first, after seeded
entries) and `published-content`, both JSON stored as data.
Shot progress shows only on screen: prove it with a relaunch, as
`tests/pocket-alternatives.e2e.ts` does.
A session name never touches a real creator's data.

## Bug bash

Not set up. `e2e explore` needs a model, and the config has none. To
start one, write an untracked `e2e.bugbash.config.ts` that spreads
`e2e.config.ts`, adds a model under `agents`, and adds
`tests/bugbash/**` to the tests glob. Add `.e2e/bugbash/` to
`.gitignore`. Then run the charters from [features/](features/). Only one
explorer can run at a time, because all runs share one simulator. A finding
is a bug only once `tests/bugbash/<slug>.e2e.ts` fails with
`ASSERTION_FAILED` on the assertion that encodes it.

## Cleanup

The runner terminates the app at the end of a run; `close_session` does
the same for a live session. Never erase the simulator, reset its
keychain, or shut it down: other work uses it. Fixture sessions are
namespaced, so old ones are harmless; to remove one, delete its
`FixtureQA/<session>/` folder and its
`com.contenthelper.fixture.<session>.plist`. Keep `.e2e/proof/`: that is
the evidence.

## Helpers

None beyond `tests/pocket-support.ts`. The e2e CLI, `xcodebuild`, and
`xcrun simctl` do the rest.
