import {
  FALLBACK_GEMINI_IMAGE_MODEL,
  GEMINI_API_REVISION,
  GeminiImageGenerationError,
  generateGeminiImage,
  generateGeminiImageWithFallback,
  resolveGeneratedImage,
} from "./gemini-image.ts";

Deno.test("resolveGeneratedImage reads inline output_image data", async () => {
  const image = await resolveGeneratedImage({
    output_image: {
      type: "image",
      data: "abc123",
      mime_type: "image/jpeg",
    },
  });
  assertEquals(image, { data: "abc123", mimeType: "image/jpeg" });
});

Deno.test("resolveGeneratedImage reads image blocks nested in steps", async () => {
  const image = await resolveGeneratedImage({
    status: "completed",
    steps: [
      {
        type: "model_output",
        content: [
          {
            type: "image",
            data: "nested-bytes",
            mime_type: "image/png",
          },
        ],
      },
    ],
  });
  assertEquals(image, { data: "nested-bytes", mimeType: "image/png" });
});

Deno.test("resolveGeneratedImage fetches uri delivery when data is absent", async () => {
  const fetchImpl = ((input: RequestInfo | URL) => {
    const url = String(input);
    assertEquals(url, "https://example.com/generated.jpg");
    return Promise.resolve(
      new Response(Uint8Array.from([1, 2, 3, 4]), {
        status: 200,
        headers: { "content-type": "image/jpeg" },
      }),
    );
  }) as typeof fetch;

  const image = await resolveGeneratedImage({
    steps: [
      {
        type: "model_output",
        content: [
          {
            type: "image",
            uri: "https://example.com/generated.jpg",
            mime_type: "image/jpeg",
          },
        ],
      },
    ],
  }, fetchImpl);

  assertEquals(image?.mimeType, "image/jpeg");
  assertEquals(image?.data, btoa(String.fromCharCode(1, 2, 3, 4)));
});

Deno.test("generateGeminiImage uses documented image response format and Api-Revision", async () => {
  let seenBody: Record<string, unknown> = {};
  let seenApiRevision: string | null = null;
  let seenApiKey: string | null = null;
  const fetchImpl = ((input: RequestInfo | URL, init?: RequestInit) => {
    assertEquals(
      String(input),
      "https://generativelanguage.googleapis.com/v1beta/interactions",
    );
    const headers = new Headers(init?.headers);
    seenApiRevision = headers.get("Api-Revision");
    seenApiKey = headers.get("x-goog-api-key");
    seenBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
    return Promise.resolve(
      Response.json({
        status: "completed",
        output_image: {
          type: "image",
          data: "inline-image",
          mime_type: "image/jpeg",
        },
      }),
    );
  }) as typeof fetch;

  const image = await generateGeminiImage({
    apiKey: "test-key",
    model: "gemini-3.1-flash-lite-image",
    prompt: "storyboard frame",
    fetchImpl,
  });

  assertEquals(image.data, "inline-image");
  assertEquals(seenApiRevision, GEMINI_API_REVISION);
  assertEquals(seenApiKey, "test-key");
  const responseFormat = seenBody.response_format as Record<string, unknown>;
  assertEquals(responseFormat.type, "image");
  assertEquals("delivery" in responseFormat, false);
  assertEquals(responseFormat.image_size, "1K");
  assertEquals(responseFormat.aspect_ratio, "16:9");
});

Deno.test("generateGeminiImage preserves sanitized provider failure details", async () => {
  const secret = `AIza${"x".repeat(32)}`;
  const fetchImpl = (() =>
    Promise.resolve(
      Response.json({
        error: {
          status: "INVALID_ARGUMENT",
          message: `Unsupported response field delivery; key=${secret}`,
        },
      }, { status: 400 }),
    )) as typeof fetch;

  let thrown: unknown;
  try {
    await generateGeminiImage({
      apiKey: "test-key",
      model: "gemini-3.1-flash-lite-image",
      prompt: "storyboard frame",
      fetchImpl,
    });
  } catch (error) {
    thrown = error;
  }

  if (!(thrown instanceof GeminiImageGenerationError)) {
    throw new Error("Expected GeminiImageGenerationError");
  }
  assertEquals(thrown.status, 400);
  assertEquals(thrown.providerCode, "INVALID_ARGUMENT");
  assertEquals(
    thrown.providerMessage,
    "Unsupported response field delivery; key=[REDACTED]",
  );
});

Deno.test("generateGeminiImageWithFallback switches model after primary failure", async () => {
  const models: string[] = [];
  const fetchImpl = ((input: RequestInfo | URL, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body)) as Record<string, unknown>;
    const model = String(body.model);
    models.push(model);
    if (model === "gemini-3.1-flash-lite-image") {
      return Promise.resolve(
        Response.json({
          error: { status: "NOT_FOUND", message: "model not found" },
        }, { status: 404 }),
      );
    }
    return Promise.resolve(
      Response.json({
        status: "completed",
        output_image: {
          type: "image",
          data: "fallback-image",
          mime_type: "image/jpeg",
        },
      }),
    );
  }) as typeof fetch;

  const image = await generateGeminiImageWithFallback({
    apiKey: "test-key",
    model: "gemini-3.1-flash-lite-image",
    prompt: "storyboard frame",
    fetchImpl,
  });

  assertEquals(image.data, "fallback-image");
  assertEquals(image.model, FALLBACK_GEMINI_IMAGE_MODEL);
  assertEquals(models, [
    "gemini-3.1-flash-lite-image",
    FALLBACK_GEMINI_IMAGE_MODEL,
  ]);
});

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Assertion failed:\nactual: ${JSON.stringify(actual)}\nexpected: ${
        JSON.stringify(expected)
      }`,
    );
  }
}
