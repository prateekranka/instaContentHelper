# Runtime Config and Device Pairing: Mamta Content OS V2

This slice adds local runtime configuration and a device-pairing path without changing product views.

## Local Runtime Configuration

Runtime keys are read in this order:

1. Process environment:
   - `MCO_SUPABASE_URL`
   - `MCO_SUPABASE_PUBLISHABLE_KEY`
2. Generated app Info.plist keys with the same names.

The Xcode project now uses:

- `MamtaContentOS/Config/Runtime.xcconfig`
- optional local override `MamtaContentOS/Config/LocalRuntime.xcconfig`
- example file `MamtaContentOS/Config/LocalRuntime.sample.xcconfig`

`LocalRuntime.xcconfig` is ignored by git. Blank values and unresolved build-setting placeholders are treated as missing config, so the app keeps running on fixture data.

## Stored Pairing Session

Paired device sessions are stored in Keychain:

- service: `com.prateekranka.MamtaContentOS.runtime`
- account: `paired-device-session`
- accessibility: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`

The stored session contains:

- Supabase project URL
- publishable key
- workspace ID
- creator ID
- member ID
- device installation ID
- device token
- display labels for workspace/creator
- role and paired timestamp

## Client Pairing Service

Client pairing lives in:

- `MamtaContentOS/Data/DevicePairingService.swift`

It invokes the Supabase Edge Function `pair-device` with:

```json
{
  "invite_code": "MAMTA-CODE",
  "device_name": "iPhone",
  "platform": "ios"
}
```

On success it:

1. Builds a `PairedDeviceSession`.
2. Saves the session to Keychain.
3. Creates Supabase-backed repositories for the paired workspace/creator.

No pairing UI is exposed yet.

## Edge Function

Server-side pairing lives in:

- `supabase/functions/pair-device/index.ts`

The function:

1. Normalizes and SHA-256 hashes the invite code.
2. Finds a valid `device_invites` row.
3. Verifies the invite is active, not expired, and under its use limit.
4. Creates a `members` row with the invite role.
5. Creates a `device_installations` row with only a hash of the raw device token.
6. Returns the raw device token once so the app can store it in Keychain.

The service role key is used only inside the Edge Function. It must never ship in the iOS app.

## Current Runtime Behavior

`MamtaContentOSApp` creates an `AppRuntime` on launch:

- no paired session: fixture repositories and fixture data
- paired session: Supabase repository bundle seeded with fixture fallback state, followed by repository refresh

Because no view-level pairing UI exists yet, normal simulator runs still open the same fixture-backed screens.

## Follow-Up Before Live Device Runtime

The current schema RLS helpers are Supabase Auth based. Device-token authorization should be completed before relying on direct live reads/writes from Mamta's phone.

Recommended next backend slice:

1. Deploy and verify `pair-device` and `publish-week`.
2. Move creator daily decisions behind Edge Functions.
3. Decide whether live read paths use device-token Edge Functions or a narrow RLS policy strategy.
4. Add a hidden/dev pairing surface or admin-only pairing command after the backend path is verified.
