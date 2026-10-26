# Mira toolchain record

Worktree: `/workspace/mira-ios-mvp`. Branch: `codex/mira-ios-mvp`. Base: `1580a82b59955289aca4e590f0b18343fe52e7b4`.

Inspection on 2026-10-26 found Debian 13 x86_64, approximately 30 GiB free, Node 24.19.0, no installed Swift/xtool, no Darwin SDK, and no exposed USB bus or connected iPhone. Existing app target remains iOS 26.0. Existing SwiftUI source, Supabase infrastructure and tests are preserved.

## Pins

| Component | Selection |
| --- | --- |
| omarchy-apple-dev | `ceda63aa6ff04fc2e550a7c6a7eb13aa6cacd4de` |
| Installer's xtool fork | `f300489f3a3fddbd9fb598ba6cf69eb24a494527` (not installed) |
| Installer's macro server | `cb003a1763b08947dd37376ed8240cbfb4745c32` (not installed) |
| Swift | 6.4.1 release, Ubuntu 24.04 x86_64 distribution |
| Swift archive SHA-256 | `7d246c7114077ad01dba4ad897628446ada4c489d6c7dbcf39ae3f25cbe17e8b` (observed download digest) |
| Apple SDK | Not supplied. Full mode requires a matching Xcode 27 archive from the owner's Apple account. |

Tooling is cloned into an independent ignored Git checkout at `work/omarchy-apple-dev`. Swift is extracted into `work/swift`, preserving `usr/`. `work/swift/usr/bin/swift --version` confirms Swift 6.4.1. `swift sdk list --swift-sdks-path /workspace/mira-ios-mvp/work/swift-sdks` reports no SDKs installed. This does not establish native build success.

Read upstream README, GETTING-STARTED and docs/DISTROS at the pinned revision. On Debian, use its user-only route after installing the documented distribution equivalents. This host currently also lacks `libimobiledevice-1.0` development metadata. Do not select experimental no-xcode mode: it cannot support this application's SwiftUI navigation and binding requirements.

## Existing project adapter

Generated with:

```sh
python3 work/omarchy-apple-dev/tools/xcodeproj2xtool.py \
  CreatorContentOS.xcodeproj --target CreatorContentOS --out omarchy-xtool
```

`omarchy-xtool` references the existing source using relative symlinks. It does not copy or replace app source. Regenerate it after Xcode project changes.

Warnings that require attention before a native build or distribution:

- The Xcode `Require Live Release Bootstrap` script does not run automatically under xtool. `scripts/mira-linux-build.sh` invokes the existing guard before a Release build.
- Debug pairing build settings do not translate. Configure runtime access privately; never copy a device token into tracked plists.
- Supabase bootstrap values are empty in the generated plist. The build wrapper materializes them from the environment into an ignored plist. The wrapper rejects missing live bootstrap for Release.
- Entitlements are not applied by `xtool dev` signing. Apple sign-in requires appropriate entitlements and provisioning. Use upstream documented signing on a configured host. Development compilation alone does not establish Apple sign-in.
- Asset handling, resource bundles and the current Supabase package graph require native build verification. This adapter has not yet compiled the app.

## Build and device verification

After the owner supplies the matching Xcode archive, complete full-mode installation with the upstream installer. Preserve the host's actual HOME; do not use another HOME as an installation shortcut. Confirm `swift sdk list` contains `darwin`. Keep the Swift toolchain's clang first on PATH. Run:

```sh
bash scripts/mira-linux-build.sh
```

For a live release build, set the existing Supabase bootstrap environment privately and use `CONFIGURATION=Release`. No wrapper uploads a build or submits to TestFlight or the App Store.

After authenticated Apple provisioning and initial USB trust, use upstream `device-run.sh` from `omarchy-xtool`. Follow the existing TesterArmy testing gate for device flows. No simulator, Xcode preview, native UI, speech, accessibility or physical-device success is claimed from Linux source inspection.
