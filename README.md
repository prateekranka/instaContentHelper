# ContentHelper

## Mira implementation branch

The [Mira implementation plan](docs/mira-implementation-plan.md) supersedes earlier product directions for the `codex/mira-ios-mvp` branch. [Current progress and verification](docs/mira-progress.md) distinguish implemented tracker source from pending public deployment and native work. The existing iOS app remains preserved; the new Mira journey is not yet implemented. [Linux toolchain setup and blockers](docs/mira-toolchain.md) record the pinned adapter and required Apple SDK/device access.

ContentHelper is a native iPhone app built with SwiftUI. The Xcode target and scheme are `CreatorContentOS`. The app bundle is `ContentHelper.app`.

## Latest creator design and Claude handover

Start with [the complete Claude handover](docs/claude-handover.md) and [the complete screen review PDF](output/pdf/contenthelper-creator-ios-screens-2026-10-18.pdf). The PDF contains all 40 screen concepts on 10 pages. [Download the actual PDF](https://raw.githubusercontent.com/prateekranka/instaContentHelper/main/output/pdf/contenthelper-creator-ios-screens-2026-10-18.pdf) if the browser preview is unavailable.

The [design index](docs/design/creator-ios-v1-2026-10-18/README.md) includes all 10 final PNG boards. Read the [flow and state specification](docs/design/creator-ios-v1-2026-10-18/flow-and-state-spec.md) for the accepted behavior: Today / Plan / You, several pieces per date, approval of reviewed versions, later edits, and monochrome UI with color media. These latest decisions supersede older one-package-per-day rules. The screen concepts and social integration proposals are not yet native implementation or runtime proof.

## Existing native implementation

The creator workflow is Today → Plan → Shoot Folio. Today shows the daily idea. Plan prepares ideas for selected dates. Shoot Folio contains the filming steps and post text. “Mark as posted” records local completion; it does not publish to Instagram.

Read [the current project state and collaborator handoff](docs/project-state-2026-10-18.md) before starting work. The latest source includes the Pocket interface, adaptive onboarding, AI consent, editable post text, and package restoration work.

## iPhone development

Use a Mac with Xcode and the iOS 26 SDK or later. The deployment target is iOS 26.0. The project is checked in, so open it directly:

```sh
open CreatorContentOS.xcodeproj
```

Build an unsigned Debug simulator app:

```sh
xcodebuild -project CreatorContentOS.xcodeproj -scheme CreatorContentOS \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath work/DerivedData CODE_SIGNING_ALLOWED=NO build
```

If you change `project.yml`, regenerate the project with `xcodegen generate`. Select your development team for a physical device build.

Runtime overrides belong in `CreatorContentOS/Config/LocalRuntime.xcconfig`, which is ignored by Git. Use `CreatorContentOS/Config/LocalRuntime.sample.xcconfig` as the template. Obtain the Supabase URL and publishable key through a private channel. Keep provider and service-role secrets on the backend.

## Native app checks

Install the locked Node dependencies with `npm ci`. Use TesterArmy e2e for app behavior and UI checks. Set the exact ID of an idle, booted simulator and the path of the app you just built:

```sh
export POCKET_E2E_DEVICE='<idle-booted-simulator-UDID>'
export POCKET_E2E_APP="$PWD/work/DerivedData/Build/Products/Debug-iphonesimulator/ContentHelper.app"
export POCKET_E2E_OUTPUT="$PWD/work/evidence/pocket-install"
POCKET_E2E_INSTALL=1 npx e2e run --grep 'Pocket opens'

POCKET_E2E_SCENARIO=plan POCKET_E2E_OUTPUT="$PWD/work/evidence/pocket-plan" npx e2e run
```

Always set these variables; the recovered configuration retains paths from earlier development sessions. Read [the native QA guide](docs/pocket-native-qa.md) for scenarios and proof limits. Read [the current handoff](docs/project-state-2026-10-18.md) for the latest verification status.

## Backend development

The backend uses Supabase Edge Functions and SQL migrations. Linux can run backend checks and web prototypes. It cannot build the native iPhone app.

Run the existing backend checks with Deno:

```sh
deno task ci:backend
```

The tests permit only the local listener used by the Edge Function harness. They do not call provider endpoints.

For a local Supabase stack, start Docker through Colima on macOS:

```sh
colima start --cpu 4 --memory 8 --disk 60
supabase start -x vector
```

Stop local services:

```sh
supabase stop --no-backup
colima stop
```

This source update does not deploy Supabase functions, change the database, or publish a TestFlight build.

## Prototypes

`prototypes/today-ui` contains the earlier Pocket shell. `prototypes/creator-directions-2026-10-02` contains the later interface directions and its own preview instructions. These prototypes are separate from the native app.
