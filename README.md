# instaContentHelper

Native iPhone-only SwiftUI app for Creator Content OS V2.

The app is currently fixture-first, with Supabase-ready repository boundaries and local Edge Functions for device pairing and weekly publishing.

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
