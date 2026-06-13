import { Resend } from "npm:resend";
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";

type AuthEmailPayload = {
  user: {
    email?: string;
    new_email?: string;
  };
  email_data: {
    token: string;
    token_new?: string;
    email_action_type: string;
  };
};

const jsonHeaders = { "Content-Type": "application/json" };

export async function handleSendAuthEmail(
  request: Request,
  env: { get(name: string): string | undefined } = Deno.env,
): Promise<Response> {
  if (request.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: jsonHeaders,
    });
  }

  const resendKey = env.get("RESEND_API_KEY");
  const rawHookSecret = env.get("SEND_EMAIL_HOOK_SECRET");
  if (!resendKey || !rawHookSecret) {
    return new Response(JSON.stringify({ error: "missing_email_secrets" }), {
      status: 500,
      headers: jsonHeaders,
    });
  }

  const body = await request.text();
  let payload: AuthEmailPayload;
  try {
    const secret = rawHookSecret.replace(/^v1,whsec_/, "");
    payload = new Webhook(secret).verify(
      body,
      Object.fromEntries(request.headers),
    ) as AuthEmailPayload;
  } catch {
    return new Response(JSON.stringify({ error: "invalid_hook_signature" }), {
      status: 401,
      headers: jsonHeaders,
    });
  }

  const recipient = payload.user.new_email || payload.user.email;
  const token = payload.email_data.token_new || payload.email_data.token;
  if (!recipient || !/^\d{6}$/.test(token)) {
    return new Response(JSON.stringify({ error: "invalid_email_payload" }), {
      status: 400,
      headers: jsonHeaders,
    });
  }

  const resend = new Resend(resendKey);
  const { error } = await resend.emails.send({
    from: "ContentHelper <auth@contenthelper.in>",
    to: [recipient],
    subject: `${token} is your ContentHelper sign-in code`,
    html: otpEmailHTML(token),
    text:
      `Your ContentHelper sign-in code is ${token}. It expires in 10 minutes.`,
  });

  if (error) {
    return new Response(JSON.stringify({ error: "email_delivery_failed" }), {
      status: 502,
      headers: jsonHeaders,
    });
  }

  return new Response("{}", { status: 200, headers: jsonHeaders });
}

function otpEmailHTML(token: string): string {
  return `<!doctype html>
<html><body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#17263a;line-height:1.5">
  <h2>Sign in to ContentHelper</h2>
  <p>Enter this six-digit code in the ContentHelper app:</p>
  <p style="font-size:32px;font-weight:700;letter-spacing:8px;margin:24px 0">${token}</p>
  <p>This code expires in 10 minutes and can only be used once.</p>
  <p>If you did not request this code, you can ignore this email.</p>
</body></html>`;
}

if (import.meta.main) {
  Deno.serve((request) => handleSendAuthEmail(request));
}
