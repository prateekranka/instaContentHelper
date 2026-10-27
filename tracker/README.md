# Mira workflow tracker

Public board: https://mira-build-progress-production.up.railway.app

Independent Node 24 / TypeScript / Fastify service. SQLite lives on a persistent volume at `/data/tracker.sqlite`; never deploy with an ephemeral database. Public reads expose only safe task summaries. Editing requires `TRACKER_WRITE_TOKEN` (at least 32 random characters). No secret enters frontend assets or Git.

Run `npm ci`, `npm run check`, and `npm test` in this directory. Set `TRACKER_WRITE_TOKEN` privately, then `npm start`. `/health` checks SQLite readability. The board fetches `/api/tasks` every 30 seconds, retains the last successful response on failure, and displays activity time separately from fetch time.

Deploy this directory to a separate Railway service, attach `/data`, set the secret through hosting secret storage, and expose an HTTPS domain. Run one replica. Set `PORT=3000` and target port 3000 on the domain. The pinned Railway SDK and [.railway/railway.ts](.railway/railway.ts) manage Dockerfile selection and `/health` readiness. Review `railway config plan` before applying configuration. Never include local `work/` data in deployment inputs.

`initial-state.json` is a safe public bootstrap snapshot of actual locally recorded tasks. On an empty database only, the server validates and transactionally imports its original server-generated timestamps and activity history. A populated volume is never replaced by this snapshot. This preserves pre-deployment activity without inventing new start/completion times. Later updates use the authenticated CLI. `node tracker/scripts/export-progress.mjs` from the repository root refreshes the public documentation snapshot and bootstrap file from `TRACKER_URL`.

Use `TRACKER_URL` and `TRACKER_WRITE_TOKEN` in the agent environment. From the repository root:

```sh
node tracker/scripts/mira-track.mjs update work/mutation.json
node tracker/scripts/mira-track.mjs flush
```

A mutation contains `id`, `note`, and changed task fields. Creation also requires `title`, `description`, `milestone`, and `criteria`. The server generates all timestamps. The CLI saves a stable idempotency key before sending. Failed requests remain in ignored `work/tracker-pending/`. Done requires a verification record, no blocker, and commit links for code tasks. Completion history survives reopening. Only attach commits after verifying their remote branch visibility.

## Backup and restore

Enable Railway volume backups. For an independent online backup, use SQLite's `.backup` command against `/data/tracker.sqlite`; copying only the main file while WAL writes occur is unsafe. Retain backups outside the running volume with restricted write access. To restore, stop the service, restore a verified SQLite backup to the volume, run `PRAGMA integrity_check`, and restart. Verify task IDs, history, unauthenticated-write rejection and authenticated idempotent update after restart. Never replace a populated volume with seed data. Seeds only create absent task IDs.

Public HTTPS, authenticated editing, desktop/mobile browser behavior and restart persistence passed on 2026-10-27. See [deployment evidence](../docs/mira-evidence/2026-10-27-tracker-deployment.md). Unit/API checks do not establish browser layout correctness.

## Recorded local verification

On 2026-10-26, TypeScript checking and the focused SQLite store test passed. TesterArmy e2e 0.21.3 verified desktop and 375-pixel mobile layouts, details/history, stale-data retention after a failed refresh, recovery, public reads, rejected anonymous writes, authenticated updates and idempotency conflicts. Screenshots were inspected. See [the progress record](../docs/mira-progress.md). These checks used a local server, not deployed infrastructure.

The deployed board is now authoritative. `work/tracker.sqlite` retains the earlier local board; do not use it for new progress updates. The write token and public `TRACKER_URL` are in ignored `work/tracker.env.local`; do not print or commit the token. `docs/mira-progress.json` is the safe public snapshot. The bootstrap preserved pre-deployment history. Failed CLI updates remain under root `work/tracker-pending/`; flush against the public board. In this managed cloud environment, Node network calls also need `NODE_USE_ENV_PROXY=1` to use the supplied proxy. Keep TLS verification enabled.
