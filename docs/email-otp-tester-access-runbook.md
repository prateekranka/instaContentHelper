# Email OTP Tester Access Runbook

ContentHelper now uses approved-email OTP sign-in for testers. Pairing codes are
kept as a backend compatibility boundary, but testers should not need them.

## Flow

1. Owner uses the backend/admin tester flow. The old Manager Control Testers
   tab is no longer on the primary bottom bar.
2. Owner invites an approved tester email.
3. Supabase sends an email OTP.
4. Tester enters the email and OTP in ContentHelper.
5. `exchange-auth-session` verifies the Supabase Auth user against
   `members.auth_user_id`.
6. The backend issues the existing device token for live runtime calls.
7. Sign out calls `revoke-device-session` and clears local session storage.

## Roles

- Owner: can invite, list, resend, and revoke editor testers.
- Editor tester: can use Manager Control and Creator mode with the existing
  owner/editor backend boundaries.
- Creator: cannot generate weeks or manage testers.

## Edge Functions

- `exchange-auth-session`: called with the Supabase Auth bearer session and no
  device token. Keep Supabase JWT gateway verification enabled.
- `manage-testers`: owner-only device-token function for list, invite, resend,
  and revoke. Deploy with JWT gateway verification disabled because it uses
  `x-mco-device-token`.
- `revoke-device-session`: device-token function used on sign out. Deploy with
  JWT gateway verification disabled.

All functions use the service role key only server-side.

## Local Smoke

1. Run migrations locally.
2. Serve functions locally with JWT verification disabled for local convenience:

   ```sh
   supabase functions serve --no-verify-jwt --env-file /tmp/mco-functions-local.env
   ```

3. Create or use an owner device session.
4. Call `manage-testers` with action `invite` and an email.
5. Read the local OTP from Mailpit/Inbucket.
6. Verify the OTP in the app or through Supabase Auth.
7. Call `exchange-auth-session` with the Auth session and confirm it returns a
   device token scoped to the workspace and creator.
8. Sign out and confirm `revoke-device-session` revokes the installation.

## Troubleshooting

- `tester_not_approved`: invite the email from the backend/admin tester flow.
- `member_revoked`: owner must re-invite or reactivate the tester.
- `invalid_auth_session`: request a fresh OTP.
- `device_session_failed`: inspect `exchange-auth-session` logs and confirm
  the member has a workspace, creator, role, and active status.
- No email: resend the code and confirm Supabase Auth SMTP settings.
