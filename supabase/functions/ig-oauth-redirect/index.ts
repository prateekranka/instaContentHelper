// Public OAuth bridge for Instagram Business Login.
//
// Meta's dashboard requires an https redirect URI, but the iOS app needs the
// custom scheme (creatorcontenthelper://ig-auth) so ASWebAuthenticationSession
// can capture the result. This function is the registered https redirect: it
// receives ?code (or ?error) from Instagram and forwards to the app scheme.
//
// No auth: it's the public landing hit inside the login web sheet. Deploy with
// --no-verify-jwt (the deploy script's default).

const APP_SCHEME = "creatorcontenthelper://ig-auth";

Deno.serve((request: Request): Response => {
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  const error = url.searchParams.get("error") ??
    url.searchParams.get("error_message");

  const target = new URL(APP_SCHEME);
  if (error) {
    target.searchParams.set("error", error);
  } else if (code) {
    target.searchParams.set("code", code);
  }
  if (state) target.searchParams.set("state", state);

  const href = target.toString();
  // A plain 302 to a custom scheme isn't reliably followed inside web sheets,
  // so redirect via JS (with a tap-through fallback) which ASWebAuthenticationSession
  // intercepts dependably.
  const html =
    `<!doctype html><html><head><meta charset="utf-8">` +
    `<meta name="viewport" content="width=device-width, initial-scale=1">` +
    `<title>Returning to ContentHelper</title></head>` +
    `<body style="font-family:-apple-system,system-ui,sans-serif;padding:2rem;text-align:center;color:#111">` +
    `<p>Returning to ContentHelper…</p>` +
    `<p><a href="${href}" style="color:#111">Tap to continue</a></p>` +
    `<script>location.replace(${JSON.stringify(href)});</script>` +
    `</body></html>`;

  return new Response(html, {
    status: 200,
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
});
