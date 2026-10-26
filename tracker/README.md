# Mira workflow tracker

Independent Node 24 / TypeScript / Fastify service. SQLite lives on a persistent volume at `/data/tracker.sqlite`; never deploy with an ephemeral database. Public reads expose only safe task summaries. Editing requires `TRACKER_WRITE_TOKEN` (at least 32 random characters). No secret enters frontend assets or Git.

Run `npm ci`, `npm run check`, and `npm test` in this directory. Set `TRACKER_WRITE_TOKEN` privately, then `npm start`. `/health` checks SQLite readability. The board fetches `/api/tasks` every 30 seconds, retains the last successful response on failure, and displays activity time separately from fetch time.

Deploy this directory to a separate Railway service, attach `/data`, set the secret through hosting secret storage, and expose an HTTPS domain. Run one replica. Never include local `work/` data in deployment inputs.

Use `TRACKER_URL` and `TRACKER_WRITE_TOKEN` in the agent environment. From the repository root:

```sh
node tracker/scripts/mira-track.mjs update work/mutation.json
node tracker/scripts/mira-track.mjs flush
```

A mutation contains `id`, `note`, and changed task fields. Creation also requires `title`, `description`, `milestone`, and `criteria`. The server generates all timestamps. The CLI saves a stable idempotency key before sending. Failed requests remain in ignored `work/tracker-pending/`. Done requires a verification record, no blocker, and commit links for code tasks. Completion history survives reopening. Only attach commits after verifying their remote branch visibility.

## Backup and restore

Enable Railway volume backups. For an independent online backup, use SQLite's `.backup` command against `/data/tracker.sqlite`; copying only the main file while WAL writes occur is unsafe. Retain backups outside the running volume with restricted write access. To restore, stop the service, restore a verified SQLite backup to the volume, run `PRAGMA integrity_check`, and restart. Verify task IDs, history, unauthenticated-write rejection and authenticated idempotent update after restart. Never replace a populated volume with seed data. Seeds only create absent task IDs.

Deployment, public access and restart checks remain pending until recorded on the board. Unit/API checks do not establish browser layout correctness.

## Recorded local verification

On 2026-10-26, TypeScript checking and the focused SQLite store test passed. TesterArmy e2e 0.21.3 verified desktop and 375-pixel mobile layouts, details/history, stale-data retention after a failed refresh, recovery, public reads, rejected anonymous writes, authenticated updates and idempotency conflicts. Screenshots were inspected. See [the progress record](../docs/mira-progress.md). These checks used a local server, not deployed infrastructure.

The independent local board is at `work/tracker.sqlite` in the repository root. Its write token is in ignored `work/tracker.env.local`; do not print or commit it. `docs/mira-progress.json` is the safe public snapshot. Pending publication updates are retained under root `work/tracker-pending/`. Set the real public `TRACKER_URL` before flushing them after deployment. No public URL has been established. Use a fresh Railway authentication flow when the owner is ready; the previous activation code expired.
