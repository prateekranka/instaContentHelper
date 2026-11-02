# Public tracker deployment — 2026-10-27

Public URL: https://mira-build-progress-production.up.railway.app

The owner selected shewhoknows's Projects. The tracker runs in its own Railway
project, separately from the existing Supabase backend. It has one service replica
and a persistent 5 GB volume mounted at `/data`. SQLite uses
`/data/tracker.sqlite`. The listener and public domain both use port 3000.
The write credential is stored privately in Railway and ignored local configuration.

## Verification

All times below are UTC. These results describe the tracker only.

- At 03:13:58, the hosted API passed its TesterArmy e2e case: public reads,
  rejected anonymous editing, authenticated updates, duplicate-safe timestamps and
  history, and a conflict for changed input with the same mutation key.
- Before and after a service restart, the complete task arrays and last-activity
  timestamp matched exactly. All 18 tasks retained their fields, creation/start/update/
  completion timestamps and full history. The comparison excluded the fetch timestamp.
- At 03:18:32, the public browser case passed through TesterArmy e2e 0.21.3.
  It checked desktop and 375-pixel phone layouts, three columns, task details and
  history, mobile column switching, no horizontal overflow, retained stale data after
  an aborted refresh, and recovery on the next successful refresh.
- The hosted [desktop screenshot](tracker-public-desktop.png) and
  [phone screenshot](tracker-public-mobile.png) were visually inspected. They show
  the board before its deployment card was completed. They are not native app images.
- TypeScript checking passed after updating `@fastify/static` to 10.1.7.
  `npm audit --omit=dev` reported zero known production dependency vulnerabilities.

The initial public HTTP error came from Railway assigning port 8080 while the domain
targeted 3000. Explicit `PORT=3000` corrected it. Browser checks initially failed
because Chromium did not trust the managed environment's current proxy CA. Importing
that existing CA and running the browser in the same execution resolved it. TLS
verification remained enabled. The public API used the environment's standard CA trust.

## Source and operations

[Pushed deployment configuration and dependency patch](https://github.com/prateekranka/instaContentHelper/commit/e3e3cd53096d5f6fefc05ec9c9df0884ab93aed2).
Remote branch visibility was verified. The pinned Railway SDK manages Dockerfile
selection, `/health` readiness, one replica and the existing volume. Its reviewed
plan changed only Dockerfile selection and the readiness path. It preserved the
service, volume, public domain and remote variables. New Railway services do not
read the deprecated `railway.json` format; it was replaced with `.railway/railway.ts`.

The bootstrap imported actual pre-deployment task timestamps and history once.
Later progress updates use the authenticated CLI. A failed network update remained
queued and was confirmed after retry through the supplied proxy. A populated volume
is never overwritten from the source bootstrap.

The final release [4164474b-ffc7-458d-a1e6-775171b93fa3](https://railway.com/project/e82480bd-eb6d-4903-8527-cb039d0b4dc0/service/d802a54a-ae8e-49bf-b9aa-245d228f70d2?id=4164474b-ffc7-458d-a1e6-775171b93fa3)
reached `SUCCESS` with `/health` readiness enabled. The public health check returned
200. All 18 task IDs, original timestamps and history remained present after this
deployment, including authenticated progress updates made after the bootstrap.

Native build/runtime, speech, accessibility and live Supabase generation remain
unverified. The owner waived archive/device access. The separately approved backend
deployment still requires completion of Supabase CLI sign-in.
