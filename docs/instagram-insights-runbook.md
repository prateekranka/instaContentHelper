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

## Login type: Instagram API with Unified login (no Facebook Page)

Newer Meta apps can't use *API setup with Instagram login*. Meta's replacement is
**API setup with Unified login**: the creator logs in with **Instagram or
Facebook** and shares their Instagram professional account with the app.
**No Facebook Page is needed.** Under the hood this is Facebook Login for
Business with a **System-user access token (SUAT)** configuration.

Consequences:
- Each creator needs an Instagram **Professional** (Creator or Business) account.
  Personal accounts can't share insights. Switching is free in Instagram settings.
- The **app** must be connected to a **business portfolio** (Meta requires it for
  Unified login).
- Credentials are the **top-level Meta app** id and secret (App settings → Basic).
- The code exchange returns a business integration system-user token. Its lifetime
  comes from the configuration (choose *Never*).
- The account is found with `GET /me/assigned_instagram_accounts`. All Graph calls
  go to `graph.facebook.com` (version from `INSTAGRAM_GRAPH_VERSION`, default `v24.0`).
- Older **User access token** configurations still work: `instagram-connect` falls
  back to the Page-linked lookup (`/me/accounts`) when no assigned account exists.

Docs: [Unified login overview](https://developers.facebook.com/documentation/instagram-platform/instagram-api-with-unified-login),
[authentication](https://developers.facebook.com/documentation/instagram-platform/instagram-api-with-unified-login/authentication),
[permissions](https://developers.facebook.com/documentation/instagram-platform/instagram-api-with-unified-login/permissions).

## 0. What you get without App Review

Saving a configuration gives **Standard Access**, which works only for people with
a role on the app (admins, developers, testers). Pilot creators get the real API
immediately once they have a role. Public creators need **Advanced Access** through
App Review and the app in **Live mode**.

## 1. Meta app

Pick an app that is **connected to a business portfolio**. Use cases → *Manage
messaging & content on Instagram* → Customize → **API setup with Unified login**.
If the page says "Business portfolio selection is mandatory", connect a portfolio
first (App settings → Basic → Business portfolio).

## 2. Login configuration and permissions

On **API setup with Unified login → 1. Configure your app**:

1. **Create new configuration.** Token type: **System-user access token (SUAT)**.
   Expiration: **Never**. Business assets: **Instagram account** (required).
2. Permissions: keep `instagram_basic` and **add `instagram_manage_insights`**
   (the default configuration does not include it). Remove publishing, messaging,
   comments and ads permissions; Mira only reads.
3. Select the registered redirect URL (step 3) and **Save**.
4. Note the **Configuration ID**. It goes in the app config as
   `INSTAGRAM_LOGIN_CONFIG_ID` (step 5).

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

Register it under **API setup with Unified login → Redirect URL** (it also shows in
Facebook Login for Business → Settings → Valid OAuth Redirect URIs), and use the identical value for:
- the client's `INSTAGRAM_REDIRECT_URI` (`LocalRuntime.xcconfig`), and
- the `INSTAGRAM_REDIRECT_URI` Supabase secret (step 5).

## 4. Add pilot test users (Development mode)

Meta app → **App roles → Roles** → add each pilot creator (Tester role). They
accept the invite. Each needs an Instagram Creator or Business account. No
Facebook Page is needed.

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
   `response_type=code`, `override_default_response_type=true`, `config_id`, and a
   random `state`. The creator logs in with Instagram or Facebook and picks their
   Instagram account.
3. The bridge forwards `?code=…&state=…` to `creatorcontenthelper://ig-auth`.
   The app rejects the callback if `state` doesn't match.
4. App POSTs `{ creator_id, code, redirect_uri }` to **`instagram-connect`**, which
   exchanges the code for a token, finds the Instagram account via
   `/me/assigned_instagram_accounts` (or, for older user-token configurations,
   upgrades to a long-lived token and uses `/me/accounts`), and stores it in
   `creator_instagram_connections`. The token is never returned to the device.
5. **`instagram-insights`** fetches followers / 7-day reach / 7-day saves, writes a
   snapshot, and computes week-over-week deltas against the newest snapshot that
   is at least ~6.5 days old. Deltas appear once a week of history exists.

## 8. Token lifecycle

With the SUAT configuration and *Never* expiration, the token lasts until the
creator removes the app or moves the Instagram account to another portfolio.
Older user-token configurations last ~60 days. When the stored token has expired (or Graph returns an OAuthException), the app
shows **"Permission needed"** and the creator reconnects.

## 9. App Review (for the public audience)

Prepare:

- **Business verification** of the owning organization.
- A **screencast** of the real connect flow and where each permission's data is
  used (the "How you're doing" screen).
- A written **justification** per permission: `instagram_basic`,
  `instagram_manage_insights`.
- A test Instagram Creator or Business account.

On approval, switch the app to **Live mode**.

## 10. Troubleshooting

- `missing_function_secrets` → secrets not set (step 5).
- `instagram_connect_failed` (502) → bad `code`, redirect-URI mismatch, wrong app
  secret, or the user isn't a tester in Development mode. The redirect URI must
  match exactly in the dashboard, the app config, and the secret.
- `instagram_account_not_linked` → the creator did not share an Instagram
  professional account during login, or the account is personal. Switch to a
  Creator or Business account in Instagram settings, then connect again.
- `instagram_permission_denied` / **"Permission needed"** → a permission wasn't
  granted, the token expired, or the account isn't a tester.
- No deltas yet → less than a week of snapshots.
- "Saves" missing while followers/reach show → account-level saves don't exist in
  the API; it's summed from recent media `saved` and can be unavailable
  (the snapshot is marked `data_quality = partial`).
