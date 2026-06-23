import { handleSendAuthEmail } from "./index.ts";

Deno.test("send-auth-email rejects non-POST requests", async () => {
  const response = await handleSendAuthEmail(
    new Request("http://localhost/send-auth-email", { method: "GET" }),
  );

  assertEquals(response.status, 405);
  assertEquals((await response.json()).error, "method_not_allowed");
});

Deno.test("send-auth-email requires delivery and hook secrets", async () => {
  const response = await handleSendAuthEmail(sendRequest(), {
    env: { get: () => undefined },
  });

  assertEquals(response.status, 500);
  assertEquals((await response.json()).error, "missing_email_secrets");
});

Deno.test("send-auth-email rejects invalid webhook signatures", async () => {
  const response = await handleSendAuthEmail(sendRequest(), {
    env: envWithSecrets(),
    verifyPayload: () => {
      throw new Error("bad signature");
    },
  });

  assertEquals(response.status, 401);
  assertEquals((await response.json()).error, "invalid_hook_signature");
});

Deno.test("send-auth-email rejects invalid OTP payloads", async () => {
  const response = await handleSendAuthEmail(sendRequest(), {
    env: envWithSecrets(),
    verifyPayload: () => ({
      user: { email: "tester@example.com" },
      email_data: {
        token: "abc123",
        email_action_type: "magiclink",
      },
    }),
  });

  assertEquals(response.status, 400);
  assertEquals((await response.json()).error, "invalid_email_payload");
});

Deno.test("send-auth-email sends a six-digit OTP email", async () => {
  const sentMessages: Record<string, unknown>[] = [];
  const response = await handleSendAuthEmail(sendRequest(), {
    env: envWithSecrets(),
    verifyPayload: () => ({
      user: { email: "old@example.com", new_email: "tester@example.com" },
      email_data: {
        token: "111111",
        token_new: "654321",
        email_action_type: "magiclink",
      },
    }),
    sendEmail: (_resendKey, message) => {
      sentMessages.push(message);
      return Promise.resolve({});
    },
  });

  assertEquals(response.status, 200);
  assertEquals(sentMessages.length, 1);
  assertEquals(sentMessages[0].to, ["tester@example.com"]);
  assertEquals(
    sentMessages[0].subject,
    "654321 is your ContentHelper sign-in code",
  );
  assertIncludes(String(sentMessages[0].text), "654321");
  assertIncludes(String(sentMessages[0].html), "654321");
});

Deno.test("send-auth-email surfaces delivery failures", async () => {
  const response = await handleSendAuthEmail(sendRequest(), {
    env: envWithSecrets(),
    verifyPayload: () => ({
      user: { email: "tester@example.com" },
      email_data: {
        token: "123456",
        email_action_type: "magiclink",
      },
    }),
    sendEmail: () => Promise.resolve({ error: { message: "rejected" } }),
  });

  assertEquals(response.status, 502);
  assertEquals((await response.json()).error, "email_delivery_failed");
});

function sendRequest(): Request {
  return new Request("http://localhost/send-auth-email", {
    method: "POST",
    body: "{}",
  });
}

function envWithSecrets() {
  return {
    get(name: string) {
      return name === "RESEND_API_KEY"
        ? "resend-test-key"
        : name === "SEND_EMAIL_HOOK_SECRET"
        ? "v1,whsec_test-hook-secret"
        : undefined;
    },
  };
}

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

function assertIncludes(actual: string, expected: string): void {
  if (!actual.includes(expected)) {
    throw new Error(`Expected ${JSON.stringify(actual)} to include ${expected}`);
  }
}
