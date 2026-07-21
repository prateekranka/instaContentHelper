# Sign in with Apple activation

Status: resolved
Blocked by: None

Parent: [spec.md](../spec.md) · seam **Auth activation**

## What to build

A Creator can open ContentHelper and sign in with **Sign in with Apple** only. After Apple Auth succeeds, the existing Auth session → exchange → device token pipeline still runs, and the Creator lands in a live session. First successful Apple sign-in auto-provisions a Creator workspace/membership (no allowlist). A valid prior device session restores on launch. Sign-out revokes the device session and clears local Auth so the next screen is Sign in with Apple again. Email OTP, pairing-code sign-in, and “tester not approved” dead ends are gone from the product path.

## Acceptance criteria

- [x] Sign-in screen shows ContentHelper brand + Sign in with Apple only (no email OTP UI).
- [x] Successful Apple Auth completes Auth session → exchange → Keychain device session and enters the live app as Creator.
- [x] First Apple sign-in with no existing member auto-provisions Creator membership/workspace; there is no allowlist / “tester not approved” gate.
- [x] Cold launch restores a valid prior device session without forcing sign-in again.
- [x] Sign-out revokes the device session, clears local Auth, and returns to Sign in with Apple.
- [x] Existing OTP accounts that sign in with Apple are not blocked by a special in-app link-email migration flow.
- [x] Tests at the authentication runtime/session seam cover: Apple success path (credential may be stubbed), first-launch auto-provision, restore, and sign-out clearing the live phase.

## Blocked by

None — can start immediately.

## Comments

## Answer

### Done
- **SignInView** — ContentHelper brand + native `SignInWithAppleButton` only; email/OTP UI and approved-tester copy removed.
- **AuthenticationService / AppState** — Apple id_token → `signInWithIdToken(provider: .apple)` → existing `exchangeAuthenticatedSession`; OTP request/verify removed from the product API; phases are `restoring | signedOut | signingIn | live | failed`.
- **exchange-auth-session** — No membership → auto-provision workspace + creator + member (`role: creator`, `status: active`); existing bound members keep the prior success path; `tester_not_approved` no longer returned for empty membership.
- **Entitlements** — `CreatorContentOS/CreatorContentOS.entitlements` with `com.apple.developer.applesignin`; wired via `project.yml` / XcodeGen for bundle `com.prateekranka.creatorcontenthelper`.
- **Tests** — `AuthenticationRuntimeTests` cover Apple success (stubbed token), first-launch creator session, restore, sign-out; Deno exchange tests cover auto-provision.

### How to verify
1. `deno test --allow-env supabase/functions/exchange-auth-session/index_test.ts`
2. `xcodegen generate`
3. `xcodebuild test -scheme CreatorContentOS -destination 'platform=iOS Simulator,id=<sim>' -only-testing:CreatorContentOSTests/AuthenticationRuntimeTests`
4. Manual: cold launch → Sign in with Apple → live Creator shell; kill/relaunch restores; Profile sign-out returns to Apple sign-in.

### Dashboard / Apple provider follow-ups (required for live Apple Auth)
These are **outside the app binary** and must be configured before TestFlight/device Apple sign-in works:

1. **Apple Developer** — Enable Sign in with Apple on App ID `com.prateekranka.creatorcontenthelper` (capability already reflected in entitlements).
2. **Supabase Auth → Apple provider (hosted project)** — Enable Apple; set Client IDs to include the iOS bundle id `com.prateekranka.creatorcontenthelper`; add Services ID + secret key if using web/callback flows; for native id_token, bundle id as client id is the usual path.
3. **Allow new Auth users** — Hosted `[auth] enable_signup` (or equivalent Dashboard “Allow new users”) must allow Apple first-time users; local `config.toml` still has `enable_signup = false` and `[auth.external.apple] enabled = false`.
4. **Nonce / Hide My Email** — Prefer `skip_nonce_check = true` for native Apple if GoTrue nonce encoding mismatches; consider `email_optional = true` so Hide My Email / missing email does not block Auth.
5. **Deploy** — Redeploy `exchange-auth-session` so auto-provision runs in production.
6. **Existing OTP accounts** — No in-app link flow: an Apple identity creates a **new** `auth.users` row unless ops rebind `members.auth_user_id` (or link identities in Dashboard) to the prior member.
