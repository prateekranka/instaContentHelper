# Tracker deployment configuration

`railway.ts` describes the existing `mira-build-progress` project: one service,
one replica, `/health` readiness, and its persistent volume at `/data`.
Remote variables remain unmanaged. The write token is never imported into source.
Set `PORT=3000` and keep the public domain target port at 3000.

Run from `tracker` after linking the intended project and production environment:

```sh
railway config plan
railway config apply
railway up . --path-as-root --detach -m "Describe the release"
```

Review the plan before applying. Preserve the existing service, volume, variables,
and domain. The CLI evaluates this file; uploads alone do not apply infrastructure
changes. Use explicit project, environment, and service selectors outside this linked
directory. Verify deployment status and public reads after each upload. Never replace
a populated volume with seed data. The SDK is pinned as a development dependency.
