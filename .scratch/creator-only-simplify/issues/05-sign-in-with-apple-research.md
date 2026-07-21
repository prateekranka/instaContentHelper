# Sign in with Apple + current auth (research)

Type: research
Status: resolved

## Question

How does the current approved-email OTP / Supabase auth path work in this app, and what is the concrete integration path for Sign in with Apple as the only sign-in on this SwiftUI + Supabase stack?

Deliverable: a short cited markdown summary (current auth surfaces, session model, Apple + Supabase options, migration notes for existing tester accounts).

## Answer

Full cited research: [assets/05-sign-in-with-apple-research.md](../assets/05-sign-in-with-apple-research.md)

**Facts for ticket 06:**

1. **Today’s gate:** approved-email OTP with `shouldCreateUser: false` → `exchange-auth-session` binds `auth.users.id` → `members.auth_user_id` → issues **device token** (`x-mco-device-token`) for Edge Functions.
2. **App gate:** UI is live only when `authenticationPhase == .live`; roles/workspace/creator attach at exchange.
3. **Apple not implemented:** no entitlements / Sign in with Apple UI; best technical fit is native Apple `id_token` → supabase-swift `signInWithIdToken` → **same exchange/device-token path**.
4. **Allowlisting today:** membership row required (`tester_not_approved` if missing); Testers UI / `manage-testers` is OTP-email oriented and not on main Admin tabs (DEBUG-only screen).
5. **Migration hinge:** existing OTP users break unless `members.auth_user_id` is rebound to the Apple-linked Auth user (email alone is not enough if Apple hides email / new Auth user).
6. **Legacy pairing** still exists server-side but has no production UI — out of destination; don’t revive for Apple.
