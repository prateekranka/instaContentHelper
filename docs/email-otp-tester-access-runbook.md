# Email OTP Tester Access Runbook

ContentHelper now uses approved-email OTP sign-in for testers. Pairing codes are
kept as a backend compatibility boundary, but testers should not need them.

## Flow

1. Owner uses the Testers tab in Manager Control for editor testers, or the
   backend/admin tester flow when operating outside the app.
2. Owner invites an approved editor tester email, or binds an existing active
   creator member to Supabase Auth for creator-only access.
3. Supabase sends an email OTP from the editor invite/resend path, or after the
   bound creator requests a code in the app.
4. Tester enters the email and OTP in ContentHelper.
5. `exchange-auth-session` verifies the Supabase Auth user against
   `members.auth_user_id`.
6. The backend issues the existing device token for live runtime calls.
7. Sign out calls `revoke-device-session` and clears local session storage.

## Roles

- Owner: can invite, list, resend, and revoke editor testers.
- Editor tester: can use Manager Control and Creator mode with the existing
  owner/editor backend boundaries.
- Creator: can use Creator mode after OTP exchange, but cannot generate weeks,
  manage testers, or become an editor/admin through the creator binding path.

## Edge Functions

- `exchange-auth-session`: called with the Supabase Auth bearer session and no
  device token. Keep Supabase JWT gateway verification enabled.
- `manage-testers`: owner-only device-token function for list, invite, resend,
  revoke, and `bind_creator`. Deploy with JWT gateway verification disabled
  because it uses `x-mco-device-token`.
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

## Creator Auth Binding

Use this only for an existing active `members.role = 'creator'` row. It creates
or finds the Supabase Auth user by normalized email and updates only that
creator member's `auth_user_id`; the update is constrained with
`role = 'creator'` and returns a stable error instead of converting an
editor/admin member.

Owner device-token request:

```sh
curl "$SUPABASE_URL/functions/v1/manage-testers" \
  -H "content-type: application/json" \
  -H "x-mco-device-token: $OWNER_DEVICE_TOKEN" \
  -d '{"action":"bind_creator","email":"creator@example.com","display_name":"Creator"}'
```

Expected response:

```json
{
  "creator_member": {
    "email": "creator@example.com",
    "role": "creator",
    "status": "active"
  },
  "auth_bound": true
}
```

After binding, the creator requests an OTP from the app and completes the normal
`exchange-auth-session` flow. Do not include service-role keys, device tokens,
Supabase Auth JWTs, OTPs, or raw creator email addresses in handover evidence.

Redacted evidence for live handover should capture:

- Member check: `role=creator`, `has_auth_user_id=true`, `status=active`.
- Auth exchange check: `member_role=creator`, expected workspace/creator IDs,
  and a nonempty redacted `device_installation_id`.
- Runtime check: ContentHelper opens Creator mode after OTP exchange and does
  not expose Manager-only generate/tester controls.

## Troubleshooting

- `tester_not_approved`: invite the email from the backend/admin tester flow.
- `member_revoked`: owner must re-invite or reactivate the tester.
- `creator_member_not_found`: confirm the email belongs to an existing active
  creator-role member in the target workspace; do not use editor invite for a
  creator handover.
- `creator_member_revoked`: reactivate or recreate the creator member before
  binding.
- `creator_auth_bind_failed`: retry after confirming Supabase Auth availability
  and the member has no conflicting active auth binding in the workspace.
- `invalid_auth_session`: request a fresh OTP.
- `device_session_failed`: inspect `exchange-auth-session` logs and confirm the
  member has a workspace, creator, role, and active status.
- No email: resend the code from the Testers tab or backend/admin flow and
  confirm Supabase Auth SMTP settings.
