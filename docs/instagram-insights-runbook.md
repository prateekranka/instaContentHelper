# Instagram Insights Runbook

Setup for the "How you're doing" feature: connecting a creator's Instagram
(Professional) account, reading account-level insights, and shipping to a pilot
before Meta App Review clears the public audience.

Related code:
- Migration `supabase/migrations/20261101120000_instagram_insights.sql`
- Edge functions `instagram-connect`, `instagram-insights`, `instagram-disconnect`
- Shared logic `supabase/functions/_shared/instagram.ts`
- iOS screen `CreatorContentOS/Features/You/HowYouAreDoingView.swift`

## 0. What you get without App Review

Insights permissions require Meta App Review for the general public. You do **not**
need review to build and pilot:

- A Meta app in **Development mode** can grant insights scopes to **app roles and
  test users** (admins/developers/testers — roughly up to 25). You, Mamta, and a
  handful of pilot creators use the **real** API immediately.
- Everyone else sees the app's manual / "Sample data" fallback until review clears.

Submit App Review in parallel; flip to the public audience when approved. No
credential scraping — connecting is always the creator's own OAuth consent.

## 1. Create the Meta app

1. developers.facebook.com → **Create app** → business/other as prompted.
2. Add the **Instagram** product → **Instagram API with Instagram Login**
   (a.k.a. *Business Login for Instagram*). This path connects Creator/Business
   accounts directly with Instagram credentials — **no Facebook Page required**.
3. Under Instagram → API setup with Instagram login, note the **Instagram app ID**
   and **Instagram app secret** (these are the Instagram-scoped credentials, not
   the top-level Facebook app id/secret).

## 2. Permissions (scopes)

Request exactly:

- `instagram_business_basic` — identity + `account_type` + media list
- `instagram_business_manage_insights` — followers / reach / media saves

Do **not** request publishing/messaging scopes; we only read insights.

## 3. OAuth redirect URI

The iOS app drives OAuth in `ASWebAuthenticationSession` with callback scheme
`creatorcontenthelper://ig-auth`.

Meta's **Valid OAuth Redirect URIs** allowlist historically wants an `https://`
URL, so register **both** of these as the setup allows:

- Primary (recommended): an `https://` bridge you control (e.g. a tiny hosted page
  or an edge function) that receives `?code=...` and 302-redirects to
  `creatorcontenthelper://ig-auth?code=...`. This is the robust path if Meta
  rejects custom schemes.
- If the dashboard accepts a custom scheme directly, `creatorcontenthelper://ig-auth`
  may be used without the bridge.

Whatever you register must match the `redirect_uri` sent at authorize time and
again at code exchange (`INSTAGRAM_REDIRECT_URI`, below).

## 4. Add pilot test users (Development mode)

Meta app → **App roles / Roles** → add each pilot creator's Instagram account as a
**tester** (they accept the invite in their Instagram app under Settings →
Website permissions / Apps and websites). Only these accounts can connect while
the app is in Development mode. Each must be a **Professional (Creator/Business)**
account — personal accounts cannot return insights (the app shows the
"Professional account needed" state for those).

## 5. Supabase function secrets

Set these for the edge functions (never in the app or in git):

```sh
supabase secrets set \
  INSTAGRAM_APP_ID=your-instagram-app-id \
  INSTAGRAM_APP_SECRET=your-instagram-app-secret \
  INSTAGRAM_REDIRECT_URI=https://your-bridge/ig-auth   # must match the dashboard + authorize call
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are already present for existing
functions. `instagram-connect` returns `missing_function_secrets` (500) if the
IG secrets are absent.

## 6. Deploy

`instagram-connect`, `instagram-insights`, `instagram-disconnect` are already in
the `FUNCTIONS` list of `scripts/deploy-live-supabase.sh`. Deploy with the
standard script (see the Live Supabase runbook), which also pushes the new
migration:

```sh
scripts/deploy-live-supabase.sh
```

Verify the two tables exist: `creator_instagram_connections`,
`creator_account_insight_snapshots`.

## 7. Connect flow (what the app does)

1. Creator taps **Connect Instagram** on *You → How you're doing*.
2. App opens `https://www.instagram.com/oauth/authorize` in
   `ASWebAuthenticationSession` with `client_id`, `redirect_uri`,
   `response_type=code`, `scope=instagram_business_basic,instagram_business_manage_insights`,
   and a random `state`.
3. On consent, the callback delivers `?code=...` to `creatorcontenthelper://ig-auth`.
4. App POSTs `{ creator_id, code }` to **`instagram-connect`**, which exchanges the
   code for a long-lived token server-side and stores it in
   `creator_instagram_connections` (token never returned to the device).
5. **`instagram-insights`** fetches followers / 7-day reach / 7-day saves, writes a
   snapshot, computes week-over-week deltas against the previous snapshot, derives
   one nudge, and returns the view model. Deltas appear from the **second** fetch
   onward (the first establishes the baseline).

## 8. Token lifecycle

Long-lived tokens last ~60 days. `instagram-insights` refreshes lazily when a
token is within 7 days of expiry (`needsRefresh` → `ig_refresh_token`). A tester
who refreshes insights at least every ~60 days never needs to reconnect. (A
scheduled pg_cron refresh is a later hardening, not required for the pilot.)

## 9. App Review (for the public audience)

Submit in parallel with the pilot. Prepare:

- **Business verification** of the owning organization.
- A **screencast** showing the real connect flow and where each scope's data is
  used in-app (the "How you're doing" screen).
- A written **justification** per scope: `instagram_business_basic` (identify the
  account and confirm it's Professional) and `instagram_business_manage_insights`
  (show followers/reach/saves back to the creator).
- A test Professional account for the reviewer.

On approval, switch the app to **Live mode** / advanced access; any Professional
account can then connect.

## 10. Troubleshooting

- `missing_function_secrets` → IG secrets not set (step 5).
- `instagram_connect_failed` (502) → bad `code`, redirect-URI mismatch, or app not
  in a state that allows the tester. Confirm `INSTAGRAM_REDIRECT_URI` matches the
  dashboard and the authorize call exactly.
- App shows **"Professional account needed"** → the connected account is personal;
  switch it to Creator/Business in Instagram settings.
- App shows **"Permission needed"** → the insights scope was not granted, or the
  account isn't a tester while in Development mode.
- No deltas yet → only one snapshot exists; deltas start on the next fetch.
- "Saves" missing while followers/reach show → account-level saves don't exist in
  the API; it's summed from recent media `saved` and can be unavailable
  (the snapshot is marked `data_quality = partial`).
