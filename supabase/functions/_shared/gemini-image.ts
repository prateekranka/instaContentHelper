export const DEFAULT_GEMINI_IMAGE_MODEL = "gemini-3.1-flash-lite-image";
export const FALLBACK_GEMINI_IMAGE_MODEL = "gemini-3.1-flash-image";
export const GEMINI_API_REVISION = "2026-05-20";

export type GeneratedGeminiImage = {
  data: string;
  mimeType: string;
};

export type GeminiImageRequestOptions = {
  apiKey: string;
  model: string;
  prompt: string;
  aspectRatio?: string;
  imageSize?: string;
  mimeType?: string;
  fetchImpl?: typeof fetch;
};

export class GeminiImageGenerationError extends Error {
  readonly code: string;
  readonly status?: number;
  readonly model: string;
  readonly providerCode?: string;
  readonly providerMessage?: string;

  constructor(
    code: string,
    model: string,
    options: {
      status?: number;
      cause?: unknown;
      providerCode?: string;
      providerMessage?: string;
    } = {},
  ) {
    super(code);
    this.name = "GeminiImageGenerationError";
    this.code = code;
    this.model = model;
    this.status = options.status;
    this.providerCode = options.providerCode;
    this.providerMessage = options.providerMessage;
    if (options.cause !== undefined) {
      (this as Error & { cause?: unknown }).cause = options.cause;
    }
  }
}

export async function generateGeminiImageWithFallback(
  options: GeminiImageRequestOptions,
): Promise<GeneratedGeminiImage & { model: string }> {
  const models = uniqueModels([
    options.model,
    FALLBACK_GEMINI_IMAGE_MODEL,
  ]);
  let lastError: GeminiImageGenerationError | null = null;

  for (const model of models) {
    try {
      const image = await generateGeminiImage({
        ...options,
        model,
      });
      return { ...image, model };
    } catch (error) {
      if (error instanceof GeminiImageGenerationError) {
        lastError = error;
        if (!shouldFallbackToNextModel(error)) {
          throw error;
        }
        continue;
      }
      throw error;
    }
  }

  throw lastError ?? new GeminiImageGenerationError(
    "storyboard_thumbnail_gemini_failed",
    options.model,
  );
}

export async function generateGeminiImage(
  options: GeminiImageRequestOptions,
): Promise<GeneratedGeminiImage> {
  const fetchImpl = options.fetchImpl ?? fetch;
  const response = await fetchImpl(
    "https://generativelanguage.googleapis.com/v1beta/interactions",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": options.apiKey,
        "Api-Revision": GEMINI_API_REVISION,
      },
      body: JSON.stringify({
        model: options.model,
        input: [{ type: "text", text: options.prompt }],
        response_format: {
          type: "image",
          mime_type: options.mimeType ?? "image/jpeg",
          aspect_ratio: options.aspectRatio ?? "16:9",
          image_size: options.imageSize ?? "1K",
        },
      }),
    },
  );

  const responseBody = await response.json().catch(() => null);
  if (!response.ok) {
    const providerError = geminiErrorDetails(responseBody);
    throw new GeminiImageGenerationError(
      "storyboard_thumbnail_gemini_failed",
      options.model,
      {
        status: response.status,
        cause: providerError.code,
        providerCode: providerError.code,
        providerMessage: providerError.message,
      },
    );
  }

  const image = await resolveGeneratedImage(responseBody, fetchImpl);
  if (!image) {
    throw new GeminiImageGenerationError(
      "storyboard_thumbnail_missing_image",
      options.model,
      {
        cause: responseBody && typeof responseBody === "object"
          ? Object.keys(responseBody as Record<string, unknown>)
          : [],
      },
    );
  }
  return image;
}

export async function resolveGeneratedImage(
  response: unknown,
  fetchImpl: typeof fetch = fetch,
): Promise<GeneratedGeminiImage | null> {
  const direct = await imageFromUnknown(
    asRecord(response)?.output_image,
    fetchImpl,
  );
  if (direct) {
    return direct;
  }

  return await findImage(response, new Set<unknown>(), fetchImpl);
}

export function geminiErrorCode(value: unknown): string {
  return geminiErrorDetails(value).code;
}

function geminiErrorDetails(
  value: unknown,
): { code: string; message?: string } {
  if (!value || typeof value !== "object") {
    return { code: "unknown" };
  }
  const error = (value as Record<string, unknown>).error;
  if (!error || typeof error !== "object") {
    return { code: "unknown" };
  }
  const record = error as Record<string, unknown>;
  const code = record.status ?? record.code ?? record.message;
  const normalizedCode = typeof code === "string" && code.trim()
    ? code.trim()
    : String(code ?? "unknown");
  const message = typeof record.message === "string" && record.message.trim()
    ? sanitizeProviderMessage(record.message)
    : undefined;
  return { code: normalizedCode, message };
}

function sanitizeProviderMessage(message: string): string {
  return message
    .replace(/AIza[\w-]{20,}/g, "[REDACTED]")
    .replace(/Bearer\s+\S+/gi, "Bearer [REDACTED]")
    .slice(0, 500);
}

function shouldFallbackToNextModel(error: GeminiImageGenerationError): boolean {
  if (error.code === "storyboard_thumbnail_missing_image") {
    return true;
  }
  const cause = String(
    (error as Error & { cause?: unknown }).cause ?? "",
  ).toUpperCase();
  return [
    "NOT_FOUND",
    "INVALID_ARGUMENT",
    "FAILED_PRECONDITION",
    "PERMISSION_DENIED",
    "UNAVAILABLE",
    "RESOURCE_EXHAUSTED",
  ].some((code) => cause.includes(code)) ||
    (error.status !== undefined && error.status >= 400);
}

function uniqueModels(models: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const model of models) {
    const trimmed = model.trim();
    if (!trimmed || seen.has(trimmed)) continue;
    seen.add(trimmed);
    result.push(trimmed);
  }
  return result;
}

async function findImage(
  value: unknown,
  seen: Set<unknown>,
  fetchImpl: typeof fetch,
): Promise<GeneratedGeminiImage | null> {
  if (!value || typeof value !== "object" || seen.has(value)) {
    return null;
  }

  seen.add(value);
  const image = await imageFromUnknown(value, fetchImpl);
  if (image) {
    return image;
  }

  if (Array.isArray(value)) {
    for (const item of value) {
      const found = await findImage(item, seen, fetchImpl);
      if (found) {
        return found;
      }
    }
    return null;
  }

  for (const item of Object.values(value as Record<string, unknown>)) {
    const found = await findImage(item, seen, fetchImpl);
    if (found) {
      return found;
    }
  }
  return null;
}

async function imageFromUnknown(
  value: unknown,
  fetchImpl: typeof fetch,
): Promise<GeneratedGeminiImage | null> {
  const record = asRecord(value);
  if (!record) {
    return null;
  }

  const mimeType = stringValue(record.mime_type) ??
    stringValue(record.mimeType) ??
    "image/jpeg";
  if (!mimeType.startsWith("image/")) {
    return null;
  }

  const data = stringValue(record.data);
  if (data) {
    return { data, mimeType };
  }

  const uri = stringValue(record.uri);
  if (!uri) {
    return null;
  }

  const response = await fetchImpl(uri);
  if (!response.ok) {
    return null;
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.byteLength === 0) {
    return null;
  }
  return {
    data: bytesToBase64(bytes),
    mimeType: response.headers.get("content-type")?.startsWith("image/")
      ? response.headers.get("content-type")!
      : mimeType,
  };
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : undefined;
}
