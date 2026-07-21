# Sign in with Apple product rules

Type: grilling
Status: resolved
Blocked by: 05

## Question

What are the product rules for Sign in with Apple as the only auth — identity, first launch, existing OTP users, and who is allowed in once Testers UI is out of scope?

Depends on [Sign in with Apple + current auth (research)](05-sign-in-with-apple-research.md).

## Answer

### Pipeline

- **Apple replaces only the front door.** Keep **Auth session → exchange → device token** (`exchange-auth-session` + Keychain device session) as today.
- Drop email OTP UI (`requestEmailOTP` / `verifyEmailOTP` / approved-tester copy).
- Technical path (from research): native Apple `id_token` → supabase-swift `signInWithIdToken` → existing exchange.

### Who may enter

- **No allowlist.** Sign in with Apple is enough; remove the “must be on allowlist / tester_not_approved” product rule.
- **First Apple sign-in:** **auto-provision** workspace / Creator / member for that Auth user, then issue device token. No dead-end “not approved” screen.
- Provisioned role: **Creator only** (no owner/editor/scout in destination UX). Plan/generate are Creator capabilities — no Manager role gate.

### Existing OTP users

- **No special link-old-email migration product.** They use Sign in with Apple; may get a new auto-provisioned Creator if Apple Auth user doesn’t already map. Ops may rebind data later outside this destination.

### Sign-in UI

- **ContentHelper** brand + **Sign in with Apple** only.

### Sign out

- Keep current behavior: revoke device session + clear local Auth/Keychain → Sign in with Apple screen.
