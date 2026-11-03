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

  // Supabase serves function HTML as text/plain on the default domain, so a
  // JS redirect page shows up as raw source. A 302 to the callback scheme is
  // what ASWebAuthenticationSession intercepts.
  return new Response(null, {
    status: 302,
    headers: {
      Location: target.toString(),
      "Cache-Control": "no-store",
    },
  });
});
