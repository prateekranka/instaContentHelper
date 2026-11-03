# ContentHelper

## Product direction

Mira is an AI-assisted creative partner for creators. The goal is to help a creator develop an idea, write it, plan and film it, and prepare it for sharing on Instagram or another social platform.

The native Mira app provides a project notebook, ideas, scripts, shot plans, filming progress, and contextual assistance. Its generation source and database migration are included in this repository but have not been verified as deployed. It does not publish to social platforms. See [the Mira handoff](docs/mira-handoff.md) for the original implementation details and verification limits.

Mira is the only native app flow in Debug and Release. The retired Today / Plan / Shoot Folio client, debug routes, dated-content cache and outbox, and background benchmark have been removed. Historical design documents and backend APIs remain in the repository; existing saved data is not deleted. See [the removal record](docs/legacy-pocket-removal.md).

## Collaborating

- Treat `main` as the shared product baseline. Start a short-lived branch from the latest `main` for each task, for example `prateek/idea-prompts` or `nikhil/creator-insights`.
- Open a pull request with a clear description, test evidence, and known limitations. Request review from the other collaborator. GitHub does not let an author approve their own pull request.
- Keep branches small and merge them after approval and the required checks. Delete a task branch only after its changes are safely merged or preserved.
- Write down handoffs and blockers in the pull request so work can continue across time zones. Never commit credentials, private user media, or local runtime settings.
- Use TesterArmy e2e for supported app behavior and preserve existing test files. The legacy unit-test source remains for history; the Mira Xcode scheme does not enable its old unit-test target. Follow [the repository testing policy](AGENTS.md).

ContentHelper is a native iPhone app built with SwiftUI. Its Xcode target and scheme are `CreatorContentOS`, and its app bundle is `ContentHelper.app`.

## Historical creator design and handover

The earlier Creator Loop design is preserved in [the complete Claude handover](docs/claude-handover.md) and [the complete screen review PDF](output/pdf/contenthelper-creator-ios-screens-2026-10-18.pdf). The PDF contains all 40 screen concepts on 10 pages. [Download the actual PDF](https://raw.githubusercontent.com/prateekranka/instaContentHelper/main/output/pdf/contenthelper-creator-ios-screens-2026-10-18.pdf) if the browser preview is unavailable.

The [design index](docs/design/creator-ios-v1-2026-10-18/README.md) includes all 10 final PNG boards. Read the [flow and state specification](docs/design/creator-ios-v1-2026-10-18/flow-and-state-spec.md) for the accepted behavior: Today / Plan / You, several pieces per date, approval of reviewed versions, later edits, and monochrome UI with color media. These documents describe the retired client direction. They are historical references, not current Mira navigation or runtime proof.

## Existing native implementation

Mira opens Today and Projects, with Profile in the toolbar. Projects contain ideas, script and shot-list revisions, filming progress, and reviewed AI proposals. Profile provides Apple sign-in, AI permission, and Instagram insights. Local projects remain usable without sign-in.

Read [the Mira implementation plan](docs/mira-implementation-plan.md) and [the Mira handoff](docs/mira-handoff.md), noting their dated verification records.

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
export MIRA_E2E_DEVICE='<idle-booted-simulator-UDID>'
export MIRA_E2E_APP="$PWD/work/DerivedData/Build/Products/Debug-iphonesimulator/ContentHelper.app"
export MIRA_E2E_BUNDLE='com.prateekranka.creatorcontenthelper'
export MIRA_E2E_OUTPUT="$PWD/work/evidence/mira-journey"
MIRA_E2E_INSTALL=1 npx e2e run
```

The default configuration runs `tests/mira-journey.e2e.ts`. It verifies the labelled demo from ideas through filming and retained progress after reopening. It uses no live AI provider. Set the exact simulator, bundle, and matching build path for each run. See [the removal record](docs/legacy-pocket-removal.md) for verification limits.

## Mira AI providers

Mira accepts the same app request regardless of which supported backend provider is selected. Provider-specific request and response handling lives in `supabase/functions/mira-generation/adapters.ts`; Mira validates every result against the same contract. Supported adapters are DeepSeek, OpenAI, and Google Gemini. Other provider APIs need a new adapter and a consent and privacy review before they receive creator data.

Select a provider on the server with `MIRA_AI_PROVIDER=deepseek`, `openai`, or `gemini`. When unset, Mira keeps the existing `MCO_AI_PROVIDER_ORDER` behavior and selects the first configured DeepSeek or OpenAI provider. Gemini selection requires `GEMINI_API_KEY` and an explicitly configured model ID in `MIRA_GEMINI_MODEL` or `MIRA_MODEL`. The Gemini-specific setting takes precedence. DeepSeek and OpenAI use their existing server-side keys and model settings; `MIRA_MODEL` can override their configured model. The app contains no provider keys.

Mira uses one selected provider per job; it does not automatically send the same request to a second provider. Configuration alone does not deploy the endpoint. Verify the current disclosure and obtain the appropriate consent before changing a live provider. The existing consent names DeepSeek, OpenAI, and Google Gemini.

Run the endpoint system scenarios with `npm ci --ignore-scripts` and `npx e2e run --config e2e.mira-api.config.ts`. They exercise the HTTP endpoint and device authorization using simulated database and provider services. They do not verify a deployed Supabase database or live model output.

## Backend development

The backend uses Supabase Edge Functions and SQL migrations. Linux can run backend checks and web prototypes. It cannot build the native iPhone app.

Run the existing backend checks with Deno:

```sh
deno task ci:backend
```

This task performs backend type checks; it does not run the existing test files or call live provider endpoints.

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
