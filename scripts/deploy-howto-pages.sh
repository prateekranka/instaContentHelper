#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! npx --yes wrangler@4 whoami >/dev/null 2>&1; then
  echo "Cloudflare auth required. Run: npx wrangler login"
  exit 1
fi

npx --yes wrangler@4 pages deploy howto \
  --project-name=contenthelper-howto \
  --commit-dirty=true

echo
echo "Next: attach custom domain howto.contenthelper.in"
echo "  wrangler pages project list"
echo "  Cloudflare Dashboard → Workers & Pages → contenthelper-howto → Custom domains → howto.contenthelper.in"
echo "DNS for contenthelper.in is already on Cloudflare (annabel/shane.ns.cloudflare.com)."
