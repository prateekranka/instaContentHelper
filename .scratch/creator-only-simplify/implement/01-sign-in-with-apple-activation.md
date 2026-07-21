# Sign in with Apple activation

Status: ready-for-agent
Blocked by: None

Parent: [spec.md](../spec.md) · seam **Auth activation**

## What to build

A Creator can open ContentHelper and sign in with **Sign in with Apple** only. After Apple Auth succeeds, the existing Auth session → exchange → device token pipeline still runs, and the Creator lands in a live session. First successful Apple sign-in auto-provisions a Creator workspace/membership (no allowlist). A valid prior device session restores on launch. Sign-out revokes the device session and clears local Auth so the next screen is Sign in with Apple again. Email OTP, pairing-code sign-in, and “tester not approved” dead ends are gone from the product path.

## Acceptance criteria

- [ ] Sign-in screen shows ContentHelper brand + Sign in with Apple only (no email OTP UI).
- [ ] Successful Apple Auth completes Auth session → exchange → Keychain device session and enters the live app as Creator.
- [ ] First Apple sign-in with no existing member auto-provisions Creator membership/workspace; there is no allowlist / “tester not approved” gate.
- [ ] Cold launch restores a valid prior device session without forcing sign-in again.
- [ ] Sign-out revokes the device session, clears local Auth, and returns to Sign in with Apple.
- [ ] Existing OTP accounts that sign in with Apple are not blocked by a special in-app link-email migration flow.
- [ ] Tests at the authentication runtime/session seam cover: Apple success path (credential may be stubbed), first-launch auto-provision, restore, and sign-out clearing the live phase.

## Blocked by

None — can start immediately.

## Comments
