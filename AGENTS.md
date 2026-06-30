# AGENTS.md

## Cursor Cloud specific instructions

This repo has two deliverables: a native iOS/SwiftUI app (`CreatorContentOS`, target
`ContentHelper`) and a Supabase backend (`supabase/`: Postgres + Deno/TypeScript Edge
Functions). Standard commands live in `README.md` and `docs/` (notably
`docs/local-supabase-docker-creator-content-os-v2.md` and `docs/e2e-qa-runbook.md`).

### Scope on the Linux cloud VM

- The **iOS app cannot be built/run/tested here** — it requires macOS + Xcode
  (`xcodegen generate`, `xcodebuild`, `simctl`). Treat it as out of scope on this VM.
- The runnable/testable scope on Linux is the **Supabase backend**: the Deno Edge
  Functions, their tests, and the local Supabase stack.

### Tooling (already provisioned in the VM snapshot)

- **Deno 2** at `/home/ubuntu/.deno/bin` (added to `PATH` via `~/.bashrc`).
- **Docker CE** configured with the `fuse-overlayfs` storage driver and the
  containerd-snapshotter feature disabled (required for Docker 29 in this VM).
- **Supabase CLI** in `/usr/local/bin`. Note the CLI is a shim that forwards to a
  co-located `supabase-go` binary — both `/usr/local/bin/supabase` and
  `/usr/local/bin/supabase-go` must be present.

### Starting services (not done by the update script)

- **Docker daemon is not auto-started** (no systemd in this container). Start it once
  per session before using Supabase, e.g. `sudo dockerd` in a background/tmux session.
- **Local Supabase stack:** `supabase start -x vector` (the `-x vector` skips the log
  collector, which fails to mount the Docker socket here). Stop with `supabase stop`.
  Endpoints: API `http://127.0.0.1:54321`, DB `postgresql://postgres:postgres@127.0.0.1:54322/postgres`,
  Studio `:54323`, Mailpit/Inbucket `:54324`. Get local keys with `supabase status -o env`.

### Testing / running the backend

- **Unit tests:** `deno test --allow-all supabase/functions/`. One test
  (`generate-week` "async mode returns running and schedules background generation")
  fails under Deno's resource-leak sanitizer because it intentionally fires a
  background fetch that is not awaited; the other 55 pass. This is a test/runtime
  interaction, not an environment problem.
- **Serving functions for end-to-end:** the container started by `supabase start`
  serves functions, but to inject env vars (e.g. mock AI) run a local serve that
  overrides it:
  `printf 'MCO_AI_MOCK=1\n' > /tmp/mco-functions-local.env`
  then `supabase functions serve --no-verify-jwt --env-file /tmp/mco-functions-local.env`.
  `MCO_AI_MOCK=1` makes `generate-week` produce deterministic mock content, so no
  DeepSeek/OpenAI keys are needed for local E2E.
- **Acceptance E2E** (full seed → pair-device → generate-week → publish-week, over HTTP):
  run with keys from `supabase status -o env`:
  `SUPABASE_URL=http://127.0.0.1:54321 FUNCTIONS_URL=http://127.0.0.1:54321/functions/v1 MCO_SUPABASE_PUBLISHABLE_KEY=$PUBLISHABLE_KEY SUPABASE_SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY deno run --allow-all supabase/functions/generate-week/acceptance.ts`
  (and `supabase/functions/write-content/acceptance.ts`).
- The `scripts/qa/live-e2e-qa.ts` and `scripts/*-smoke.ts` scripts target a **live**
  Supabase project and need real `MCO_SUPABASE_*` keys; they are not part of local setup.
