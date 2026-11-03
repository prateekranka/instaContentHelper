---
name: verify-contenthelper
description: Verify the native Mira iPhone app through its existing TesterArmy E2E journey and report build and runtime evidence separately.
---

# Verify ContentHelper / Mira

Read the repository E2E skill first. Mira is the only native flow. The old Pocket Today / Plan / Shoot Folio client and its scenarios have been removed. The default `e2e.config.ts` exports `e2e.mira.config.ts`, which selects `tests/mira-journey.e2e.ts` and the `mira-ios` target.

## Prerequisites

Use macOS with Xcode and the iOS 26 SDK or later. Follow the applicable disk and simulator preflights. Select an already-booted, idle simulator and a matching Debug build. Do not boot, shut down, erase, or reset a shared simulator. Linux source checks do not establish native compilation or UI behavior.

Install locked dependencies with `npm ci --ignore-scripts`. Set an explicitly writable npm cache if the account's default cache is unavailable.

## Build and run

Build the checked-in `CreatorContentOS.xcodeproj`, scheme `CreatorContentOS`. The product is `ContentHelper.app`. Keep DerivedData and test evidence in durable task-owned directories.

Set these values for the exact build and simulator:

```bash
export MIRA_E2E_DEVICE='<idle-booted-simulator-UDID>'
export MIRA_E2E_APP='<absolute-path-to-matching-ContentHelper.app>'
export MIRA_E2E_BUNDLE='<bundle-identifier-of-that-build>'
export MIRA_E2E_OUTPUT='<durable-task-owned-evidence-directory>'
MIRA_E2E_INSTALL=1 npx e2e run
```

The default bundle is `com.prateekranka.creatorcontenthelper.codexverify`; override it if the build uses another identifier. Install mode disables video. After installation, unset `MIRA_E2E_INSTALL` and run `npx e2e run` for the recorded journey. Rebuild and reinstall after Swift changes.

`npx e2e list --reporter json` loads the configuration and catalog without launching an engine or app. It does not verify behavior.

## Existing coverage

The deterministic journey opens Mira, explicitly chooses Mamta's demo notebook, obtains three ideas, chooses one, creates a hook/script/caption, makes a shot list, marks a shot filmed, and reopens the app to confirm retained filming progress. It captures named ideas, script, and filming screenshots. Demo generation makes no live provider request.

Mira demos use the existing local project repository. Use a dedicated verification simulator/bundle; do not assume the fixture launch flag isolates or clears real local projects. Never silently replace a live failure with demo content.

Use `tests/mobile-support.ts` for `scrollToControl` and `tapVisibleControl`. The helpers account for the actual scroll view, pinned controls, keyboard, and stable hit geometry. Do not use raw screen-wide scrolling to reach covered controls.

## Evidence and limits

Preserve exact source/build identity, simulator, commands, prerequisites, expected and observed results, screenshots, traces, and video where available. Keep private media, tokens, and signing data out of Git.

Apple sign-in, scoped AI consent, real provider generation, Instagram OAuth/live metrics, voice recognition, accessibility, dark appearance, and physical-device behavior need their own supported runtime evidence. A passing demo or source check does not establish them. No new unit suites are permitted; follow AGENTS.md.

## Historical feature notes

The files in [features/](features/) describe the retired Pocket app. They remain historical references and must not be used as current Mira routes, identifiers, test commands, or acceptance results.
