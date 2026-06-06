#!/bin/sh
set -eu

if [ "${CONFIGURATION:-}" != "Release" ]; then
  exit 0
fi

invalid=0
message=""
publishable_key="${MCO_SUPABASE_PUBLISHABLE_KEY:-}"

case "${MCO_SUPABASE_URL:-}" in
  ""|\$\(*|*YOUR-PROJECT-REF*|http://127.0.0.1*|http://localhost*)
    invalid=1
    message="${message}
- MCO_SUPABASE_URL must be a live https Supabase project URL."
    ;;
  https://*)
    ;;
  *)
    invalid=1
    message="${message}
- MCO_SUPABASE_URL must start with https:// for Release/TestFlight builds."
    ;;
esac

case "$publishable_key" in
  ""|\$\(*|*YOUR-PUBLISHABLE*|*YOUR-ANON*)
    invalid=1
    message="${message}
- MCO_SUPABASE_PUBLISHABLE_KEY must be the live publishable or anon key."
    ;;
esac

if [ "${#publishable_key}" -lt 20 ]; then
  invalid=1
  message="${message}
- MCO_SUPABASE_PUBLISHABLE_KEY is too short to be a real Supabase key."
fi

if [ "$invalid" -ne 0 ]; then
  cat >&2 <<EOF
error: Release/TestFlight builds require live Supabase bootstrap configuration.
$message

Set these in MamtaContentOS/Config/Runtime.xcconfig or pass them to xcodebuild:
  MCO_SUPABASE_URL=https://<project-ref>.supabase.co
  MCO_SUPABASE_PUBLISHABLE_KEY=<publishable-or-anon-key>
EOF
  exit 1
fi
