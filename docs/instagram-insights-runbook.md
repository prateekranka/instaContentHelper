# Instagram Insights Runbook

Setup for the "How you're doing" feature: connecting a creator's Instagram
(Professional) account, reading account-level insights, and shipping to a pilot
before Meta App Review clears the public audience.

Related code:
- Migration `supabase/migrations/20261101120000_instagram_insights.sql`
- Edge functions `instagram-connect`, `instagram-insights`, `instagram-disconnect`,
  `ig-oauth-redirect`
- Shared logic `supabase/functions/_shared/instagram.ts`
- iOS screen `CreatorContentOS/Mira/Views/MiraInsightsView.swift`, config
  `CreatorContentOS/Data/InstagramOAuth.swift`

## Login type: Facebook Login for Business ("Unified login")

Newer Meta apps can't use *API setup with Instagram login*; the dashboard shows
"API setup with Instagram login is not available for newer apps". So the creator
signs in with **Facebook Login for Business**, and we read the Instagram
professional account that is **linked to one of their Facebook Pages**.

Consequences:
- Each creator needs an Instagram **Professional** (Creator or Business) account
  **linked to a Facebook Page** they manage. Without that, connect returns
  `instagram_account_not_linked` and the app explains how to fix it.
- Credentials are the **top-level Meta app** id and secret
  (App settings → Basic), not Instagram-scoped ones.
- All Graph calls go to `graph.facebook.com` (version from the
  `INSTAGRAM_GRAPH_VERSION` secret, default `v24.0`).

## 0. What you get without App Review

Insights permissions require Meta App Review for the general public. You do **not**
need review to build and pilot:

- A Meta app in **Development mode** can grant these permissions to **app roles and
  test users** (admins/developers/testers). You and a handful of pilot creators
  use the **real** API immediately.
- Everyone else sees the app's "Sample data" fallback until review clears.

Submit App Review in parallel; flip to the public audience when approved. No
credential scraping. Connecting is always the creator's own OAuth consent.

## 1. Meta app

The app is **Mira - AI PR Agency** (app id `2420286265379388`). It has the
*Manage messaging & content on Instagram* use case, set up with Unified login.

## 2. Login configuration and permissions

Facebook Login for Business takes its permissions from a **configuration**:

1. Use cases → Instagram → **API setup with Unified login** → *Configure your app*,
   or Facebook Login for Business → **Configurations** → *Create configuration*.
2. Token type: **User access token** (not System-user access token).
3. Permissions, exactly:
   - `instagram_basic` (read the account id and username)
   - `instagram_manage_insights` (followers / reach / media saves)
   - `pages_show_list` (find the Page the Instagram account is linked to)
   - `pages_read_engagement` (read the Page's linked Instagram account)
4. Note the **Configuration ID**. It goes in the app config as
   `INSTAGRAM_LOGIN_CONFIG_ID` (step 5).

Do **not** add publishing or messaging permissions; we only read insights.

## 3. OAuth redirect URI (via the https bridge)

The iOS app drives OAuth in SwiftUI's `WebAuthenticationSession` with callback
scheme `creatorcontenthelper://ig-auth`. Meta's redirect field **rejects custom
schemes**, so the **`ig-oauth-redirect`** edge function is an https bridge:

> Facebook → `https://<project-ref>.functions.supabase.co/ig-oauth-redirect?code=…&state=…`
> → the function forwards to `creatorcontenthelper://ig-auth?code=…&state=…`
> → the app's login sheet captures it.

The **one redirect URL** used in all three places is:

```
https://zogvvrxhiwozjmufvddu.functions.supabase.co/ig-oauth-redirect
```

Register it in **Facebook Login for Business → Settings → Valid OAuth Redirect
URIs**, and use the identical value for:
- the client's `INSTAGRAM_REDIRECT_URI` (`LocalRuntime.xcconfig`), and
- the `INSTAGRAM_REDIRECT_URI` Supabase secret (step 5).

## 4. Add pilot test users (Development mode)

Meta app → **App roles → Roles** → add each pilot creator's **Facebook** account
(Tester role). They accept the invite on Facebook. Each must manage a Facebook
Page with a linked Instagram Professional account.

## 5. Config and secrets

Supabase function secrets (never in the app or in git):

```sh
supabase secrets set --project-ref zogvvrxhiwozjmufvddu \
  INSTAGRAM_APP_ID=2420286265379388 \
  INSTAGRAM_REDIRECT_URI=https://zogvvrxhiwozjmufvddu.functions.supabase.co/ig-oauth-redirect
```

Set `INSTAGRAM_APP_SECRET` (the Meta app secret from App settings → Basic) with a
hidden prompt so it never lands in shell history:

```sh
read -rs "IG_SECRET?Paste Meta app secret: " && echo && supabase secrets set --project-ref zogvvrxhiwozjmufvddu --env-file <(printf 'INSTAGRAM_APP_SECRET=%s\n' "$IG_SECRET"); unset IG_SECRET
```

`instagram-connect` returns `missing_function_secrets` (500) if these are absent.

iOS `CreatorContentOS/Config/LocalRuntime.xcconfig` (gitignored):

```
INSTAGRAM_APP_ID = 2420286265379388
INSTAGRAM_REDIRECT_URI = https:/$()/zogvvrxhiwozjmufvddu.functions.supabase.co/ig-oauth-redirect
INSTAGRAM_LOGIN_CONFIG_ID = <configuration id from step 2>
```

Without `INSTAGRAM_LOGIN_CONFIG_ID` the app falls back to a plain `scope=` login,
which Facebook Login for Business apps ignore.

## 6. Deploy

`scripts/deploy-live-supabase.sh` deploys every function folder and pushes
pending migrations (see the Live Supabase runbook):

```sh
SUPABASE_PROJECT_REF=zogvvrxhiwozjmufvddu ALLOW_SUPABASE_CLI_SESSION=1 scripts/deploy-live-supabase.sh
```

To redeploy only the Instagram functions:

```sh
SUPABASE_PROJECT_REF=zogvvrxhiwozjmufvddu ALLOW_SUPABASE_CLI_SESSION=1 SKIP_MIGRATIONS=1 \
  SUPABASE_FUNCTIONS="instagram-connect instagram-insights instagram-disconnect ig-oauth-redirect" \
  scripts/deploy-live-supabase.sh
```

## 7. Connect flow (what the app does)

1. Creator taps **Connect Instagram** on Profile → How you're doing.
2. App opens `https://www.facebook.com/dialog/oauth` in
   `WebAuthenticationSession` with `client_id`, `redirect_uri`,
   `response_type=code`, `config_id`, and a random `state`.
3. The bridge forwards `?code=…&state=…` to `creatorcontenthelper://ig-auth`.
   The app rejects the callback if `state` doesn't match.
4. App POSTs `{ creator_id, code, redirect_uri }` to **`instagram-connect`**, which
   exchanges the code for a user token, upgrades it to a long-lived token
   (`fb_exchange_token`), finds the Instagram account via `/me/accounts`
   (`instagram_business_account`), and stores it in
   `creator_instagram_connections`. The token is never returned to the device.
5. **`instagram-insights`** fetches followers / 7-day reach / 7-day saves, writes a
   snapshot, and computes week-over-week deltas against the newest snapshot that
   is at least ~6.5 days old. Deltas appear once a week of history exists.

## 8. Token lifecycle

Facebook long-lived user tokens last ~60 days and can't be refreshed server-side.
When the stored token has expired (or Graph returns an OAuthException), the app
shows **"Permission needed"** and the creator reconnects.

## 9. App Review (for the public audience)

Prepare:

- **Business verification** of the owning organization.
- A **screencast** of the real connect flow and where each permission's data is
  used (the "How you're doing" screen).
- A written **justification** per permission: `instagram_basic`,
  `instagram_manage_insights`, `pages_show_list`, `pages_read_engagement`.
- A test Facebook account with a Page and linked Instagram Professional account.

On approval, switch the app to **Live mode**.

## 10. Troubleshooting

- `missing_function_secrets` → secrets not set (step 5).
- `instagram_connect_failed` (502) → bad `code`, redirect-URI mismatch, wrong app
  secret, or the user isn't a tester in Development mode. The redirect URI must
  match exactly in the dashboard, the app config, and the secret.
- `instagram_account_not_linked` → no Page with a linked Instagram Professional
  account. Link one in Instagram → Settings → Account type and tools / Sharing to
  other apps, or in the Page's settings.
- `instagram_permission_denied` / **"Permission needed"** → a permission wasn't
  granted, the token expired, or the account isn't a tester.
- No deltas yet → less than a week of snapshots.
- "Saves" missing while followers/reach show → account-level saves don't exist in
  the API; it's summed from recent media `saved` and can be unavailable
  (the snapshot is marked `data_quality = partial`).
