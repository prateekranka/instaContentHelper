# Mira implementation handoff

Branch: `codex/mira-ios-mvp` in `prateekranka/instaContentHelper`. Base: `1580a82`. Worktree: `/workspace/mira-ios-mvp`. Work used one agent. No TestFlight or App Store distribution occurred.

## Implemented source

The default native entry is now Mira. Today and Projects each own a typed navigation stack. Profile is a labelled toolbar action. The warm notebook palette supports light and dark appearance, scaled body text, native controls and text sharing. There are no active calendar, analytics, publishing, payment or video-editor destinations.

Today creates a project or resumes the last meaningful project and filming position. The quick-idea form exposes correctable filming time, location, style, equipment and separate Reel duration. It retains earlier ideas when requesting alternatives. Creators can add an idea and edit a script manually without AI access.

Projects retain script and storyboard revisions, approval/source dependencies, proposal jobs, undo checkpoints, shot progress and the last screen. Editing a script or confirmed requirement makes its dependent plan stale. New shots retain filmed status only when their content is unchanged; changed shots require review. A focused filming screen provides Previous, Next, Mark filmed and Make this easier. It does not capture or analyse media.

Contextual Ask Mira accepts typed or reviewed spoken requests and shows proposed changes before Apply. Newer edits prevent late responses from replacing current work. Cancelled or unrelated job responses cannot replace a project. Language corrections remain project-specific unless the creator explicitly remembers a preference.

The optional brief sheet preserves original text, source excerpts and unresolved details. Extracted requirements must be reviewed, applied and confirmed before generation uses them. Mappings say Included in the plan. Missing codes and unsupported health claims require correction or an explicit choice; they do not become invented output.

## Architecture and adaptations

- `CreatorContentOS/Mira/Core`: Codable models, validation, fixtures, cross-platform Observation coordinator and repository protocols/implementation. SwiftPM compiles this real implementation on Linux.
- `CreatorContentOS/Mira/Views`: native Today, Projects, project editor, script, storyboard, shooting and supporting sheets.
- `CreatorContentOS/Mira/Services`: URLSession Supabase adapter and bounded on-device speech input.
- `supabase/functions/mira-generation`: typed schemas, existing-provider adapter and durable job endpoint.
- `supabase/migrations/20261026170000_mira_generation_jobs.sql`: persistent jobs, idempotent enqueue and worker leases.
- `tracker`: independent Fastify/SQLite service and agent CLI.

The existing SwiftUI target, iOS 26 minimum, Supabase authentication, Keychain device credentials, consent flow, provider configuration and earlier source remain. The old dated-package persistence does not match Mira's project/revision contract, so Mira uses a separate versioned document repository. Earlier caches are not deleted or automatically reinterpreted as Mira projects.

The legacy Pocket interface remains available only through an explicit DEBUG fixture launch with both `MCO_FORCE_FIXTURE_UI=1` and `MCO_LEGACY_POCKET_UI=1`. Existing Pocket e2e configuration selects that route. Those tests do not establish Mira UI correctness.

## Persistence and privacy

Mira stores `mira-v2.json` and an atomic previous-save backup in the app's Application Support/Mira directory. The repository serializes writes and rejects stale sequences. It migrates the defined v1 envelope, refuses future versions, quarantines damaged documents and reports backup recovery instead of silently opening an empty library. Important transitions save immediately; typing is briefly debounced. Backgrounding flushes in-memory work.

The profile starts empty. Mamta is available only through the labelled demo action. Demo projects use explicit fixtures and never become a fallback after a live error. Demo brief extraction is deliberately limited and cannot certify brand mappings.

Microphone and speech permissions are requested only after tapping the microphone. Recording has a visible timer and 60-second bound. Hindi and English recognition are separate selections. On-device recognition is required; unavailable locales fall back to text rather than silently uploading audio. No raw-audio files are retained. Silence, permission denial, interruption and backgrounding leave text input available. Real Hinglish recognition quality is unverified.

## Backend configuration and deployment boundary

The owner confirmed reuse of existing Supabase server-side AI credentials on 2026-10-26. No provider key was created, copied into the app or printed.

Before this branch, the existing APIs generated dated packages and five plan ideas. This branch adds an independent `mira-generation` endpoint for three ideas, scripts, storyboards, revisions and requirement extraction. Existing generation functions are unchanged. The new endpoint uses the existing `MCO_AI_PROVIDER_ORDER`, `DEEPSEEK_API_KEY` / `OPENAI_API_KEY`, provider base URL and model configuration. `MIRA_MODEL` optionally overrides the selected model. No live model quality, cost or latency benchmark is claimed.

The new function disables gateway JWT checking because authentication is performed through the existing revocable device-token verifier. It checks creator/workspace membership and job ownership on every action. The database table and functions are inaccessible to anonymous/authenticated SQL roles; only the service role can operate them. No shared device credential is embedded in source.

Jobs persist their client UUID, normalized input and input revision. Repeating the same request UUID/input reuses its job; changed input conflicts. Enqueue allows ten new jobs per member per minute and two active jobs. Worker claims have a 90-second lease and three-attempt limit. Status/relaunch reconciliation reclaims interrupted workers. Unreconciled expired work is retired when a new request is enqueued after 15 minutes. Cancellation and result writes are conditional on current job/lease state. A lost provider response can still incur a repeat charge; this is not exactly-once provider execution.

The app saves the request before enqueue. Reconnection reuses that request UUID. Terminal failure offers a new explicit request; unknown connectivity keeps the saved request recoverable. Revisions become proposals. SQL guarantees were tested locally; production application is still pending.

The owner explicitly approved deployment of this reviewed endpoint/jobs-table addition on 2026-10-26. That API review is complete. The secure Supabase CLI login is waiting for its one-time browser verification code. The migration and endpoint have **not** yet been deployed to the existing project. Live generation is not verified.

The [public workflow tracker](https://mira-build-progress-production.up.railway.app) is deployed in the owner's selected Railway workspace. It runs separately from Supabase with one replica and a persistent `/data` volume. Public API and desktop/mobile browser checks passed on 2026-10-27. All 18 task records, timestamps and history survived a service restart. [Deployment evidence](mira-evidence/2026-10-27-tracker-deployment.md) records the scope and results.

## Repeatable checks

From the repository root:

```sh
bash scripts/mira-core-check.sh
deno task ci:backend
python3 scripts/mira-sql-check.py
```

The core script uses Swift on PATH or the locally extracted pinned toolchain. It keeps caches within ignored `work/`. The SQL script uses an isolated, digest-pinned PostgreSQL 17 container, minimal compatible ownership tables and the actual new migration. It removes its task-owned container. It does not touch Supabase or an existing database.

Tracker checks:

```sh
cd tracker
npm ci
npm run check
npm test
```

Start the tracker with a private `TRACKER_WRITE_TOKEN` and persistent `TRACKER_DB`, then use its TesterArmy e2e configuration. The API e2e case needs the write token in its environment. Browser tests need no model provider. Do not put the token in command arguments or tracked files. See [tracker operations](../tracker/README.md).

## Recorded evidence

| Check | Result |
| --- | --- |
| Linux Swift domain tests | 12 passed, including real saved-project/position reopen, migration, corrupt recovery, future-version protection, stale sequences, script/shot history, stale proposals and ignored unconfirmed briefs |
| Cross-platform coordinator | Compiled with the domain module on Linux; 12 tests include save-failure gating |
| Backend type-check and regression suite | 398 passed, 0 failed, 1 ignored; includes 5 new Mira tests |
| PostgreSQL migration/job checks | Passed: idempotency, lease exclusion, interrupted recovery, retry bound, cancellation, anonymous table/function denial |
| Native source syntax | Swift frontend parse passed; this is not native type-checking or linking |
| Tracker | TypeScript, store test, desktop/mobile/details/stale refresh and authenticated API e2e passed locally; screenshots inspected |
| Production tracker | Public HTTPS, rejected anonymous edits, authenticated idempotency, desktop/mobile/details/stale recovery and restart persistence passed on 2026-10-27 |
| Full native build, native UI, speech, accessibility | Unverified |
| Live Supabase generation and generative quality | Unverified; endpoint not deployed |

GitHub Actions also passed both [Backend checks](https://github.com/prateekranka/instaContentHelper/actions/runs/40376400864) and [Mira workflow contracts](https://github.com/prateekranka/instaContentHelper/actions/runs/40376400564) for commit `ecb276718b8265c7c414cf14539998176441641b`.

Detailed timestamps, per-task criteria and pushed commit links are in [the progress snapshot](mira-progress.md). Native screenshots do not exist. The committed screenshots show only the tracker.

## omarchy build boundary

The project adapter uses the pinned `omarchy-apple-dev` converter. Run `python3 scripts/mira-generate-adapter.py` after Xcode project changes. The wrapper preserves relative source links, existing Supabase dependency pins, private bootstrap materialization and the new Mira group. The converter otherwise incorrectly excludes that newly added group.

Run `bash scripts/mira-linux-build.sh` for a configured full-mode host. The wrapper enforces the existing live bootstrap guard for Release, then calls `xtool dev build`. It never distributes the result. Apple sign-in entitlements still require appropriate provisioning/signing.

The owner said not to require an Xcode archive or physical device for this run. No further request for either is needed. The pinned upstream no-Xcode SwiftUI documentation nevertheless identifies NavigationStack, Binding and Environment limitations. This app uses those APIs; that route cannot currently establish a complete Mira native build. Full-mode SDK/xtool are absent here. This limitation is recorded instead of presenting Linux parsing as a working iPhone app. See [the toolchain record](mira-toolchain.md).

The tracker bootstrap snapshot preserves the local server's actual activity timestamps/history on an empty first-deployment database. It is schema-validated and imported transactionally. A populated production volume is never overwritten from source on restart. Both store tests passed, including import preservation and rejection of invalid timestamps.

## Content and native acceptance still to verify

The live content rubric must cover ten minutes at home alone; Hindi input with explicit English output; everyday Hinglish; no tripod; moving all shots from gym to home; missing codes; unsupported health claims; sparse profiles; and script edits after two filmed shots. Tests validate deterministic contracts and state, not live generation quality.

Native acceptance remains: small-screen and large Dynamic Type layouts, VoiceOver order, light/dark and increased contrast, Reduce Motion, keyboard/microphone interaction, long content, offline reopen, edits/generation across relaunch and speech in quiet/noisy rooms. Use TesterArmy e2e when a supported native target exists. Mamta's usability session is human validation and has not occurred.
