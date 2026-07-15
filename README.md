# instaContentHelper

Native iPhone-only SwiftUI app for Creator Content OS V2.

The app is fixture-safe by default for local development, with live Supabase runtime, approved-email OTP sign-in, manager tooling, and Edge Functions for the TestFlight path.

## Local iOS

```sh
xcodegen generate
open CreatorContentOS.xcodeproj
```

The app target is `CreatorContentOS`, iOS 26.0+.

## Local Supabase

Docker is run locally through Colima. Start the local stack without the vector log collector:

```sh
colima start --cpu 4 --memory 8 --disk 60
supabase start -x vector
```

Stop local services:

```sh
supabase stop --no-backup
colima stop
```

Runtime Supabase URL/key overrides should go in `CreatorContentOS/Config/LocalRuntime.xcconfig`, which is gitignored. Use `CreatorContentOS/Config/LocalRuntime.sample.xcconfig` as the template.

## Backend verification

Run the same type-check and hermetic contract suite used by pull requests:

```sh
deno task ci:backend
```

The test task permits only the local listener used by the Edge Function harness. Provider endpoints are not reachable from this suite.
