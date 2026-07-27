import {
  DEFAULT_GEMINI_IMAGE_MODEL,
  GeminiImageGenerationError,
  generateGeminiImageWithFallback,
} from "./gemini-image.ts";
import { sha256Hex, SupabaseAdminClient } from "./device-auth.ts";
import {
  buildStoryboardThumbnailPrompt,
  cachedAssetForRow,
  mergeStoryboardThumbnailAsset,
  normalizeStoryboardThumbnailAssets,
  STORYBOARD_THUMBNAIL_PROMPT_VERSION,
  storyboardRowsForCard,
  StoryboardThumbnailAsset,
} from "./storyboard-thumbnail.ts";

export const STORYBOARD_THUMBNAIL_BUCKET = "storyboard-thumbnails";
export const DEFAULT_STORYBOARD_THUMBNAIL_CONCURRENCY = 2;
const MAX_STORYBOARD_THUMBNAIL_CONCURRENCY = 3;

export type StorageCapableAdminClient = SupabaseAdminClient & {
  storage: {
    from: (bucket: string) => {
      upload: (
        path: string,
        body: Uint8Array,
        options: Record<string, unknown>,
      ) => Promise<{ data: unknown; error: { message?: string } | null }>;
      getPublicUrl: (path: string) => {
        data: { publicUrl: string };
      };
    };
  };
};

export type GenerateStoryboardThumbnailsInput = {
  admin: StorageCapableAdminClient;
  workspaceID: string;
  creatorID: string;
  dailyCardID: string;
  cardRecord: Record<string, unknown>;
  rowIndexes?: number[];
  force?: boolean;
  revisionInstructions?: string;
  geminiAPIKey?: string | null;
  model?: string;
  persist?: boolean;
  concurrency?: number;
  generateImage?: typeof generateGeminiImageWithFallback;
};

export type GenerateStoryboardThumbnailsResult = {
  assets: StoryboardThumbnailAsset[];
  generatedCount: number;
  cachedCount: number;
  model: string;
  promptVersion: string;
  skippedReason?: string;
};

export class StoryboardThumbnailGenerationError extends Error {
  readonly code: string;

  constructor(code: string, options: { cause?: unknown } = {}) {
    super(code);
    this.name = "StoryboardThumbnailGenerationError";
    this.code = code;
    if (options.cause !== undefined) {
      (this as Error & { cause?: unknown }).cause = options.cause;
    }
  }
}

/**
 * Generate Gemini storyboard thumbnails for a persisted daily card and
 * optionally write `storyboard_thumbnail_assets` back to the row.
 *
 * Soft-skips when GEMINI_API_KEY is missing so day generation can still
 * complete; hard failures (upload/save/Gemini) throw StoryboardThumbnailGenerationError.
 */
export async function generateStoryboardThumbnailsForCard(
  input: GenerateStoryboardThumbnailsInput,
): Promise<GenerateStoryboardThumbnailsResult> {
  const geminiAPIKey = input.geminiAPIKey?.trim() ||
    Deno.env.get("GEMINI_API_KEY")?.trim() ||
    null;
  const model = input.model?.trim() ||
    Deno.env.get("GEMINI_IMAGE_MODEL")?.trim() ||
    DEFAULT_GEMINI_IMAGE_MODEL;

  if (!geminiAPIKey) {
    return {
      assets: normalizeStoryboardThumbnailAssets(
        input.cardRecord.storyboard_thumbnail_assets,
      ),
      generatedCount: 0,
      cachedCount: 0,
      model,
      promptVersion: STORYBOARD_THUMBNAIL_PROMPT_VERSION,
      skippedReason: "gemini_api_key_missing",
    };
  }

  const rows = storyboardRowsForCard(input.cardRecord);
  const targets = (input.rowIndexes ?? rows.map((row) => row.row_index))
    .filter((rowIndex) => rowIndex >= 0 && rowIndex < rows.length);
  const uniqueTargets = Array.from(new Set(targets)).sort((left, right) =>
    left - right
  );
  if (uniqueTargets.length === 0) {
    throw new StoryboardThumbnailGenerationError("storyboard_row_not_found");
  }

  let assets = normalizeStoryboardThumbnailAssets(
    input.cardRecord.storyboard_thumbnail_assets,
  );
  let generatedCount = 0;
  let cachedCount = 0;
  const revisionInstructions = normalizedRevisionInstructions(
    input.revisionInstructions,
  );

  const preparedRows = await Promise.all(uniqueTargets.map(async (rowIndex) => {
    const row = rows[rowIndex];
    const prompt = buildStoryboardThumbnailPrompt(
      input.cardRecord,
      row,
      revisionInstructions,
    );
    const promptHash = await sha256Hex(JSON.stringify({
      version: STORYBOARD_THUMBNAIL_PROMPT_VERSION,
      model,
      daily_card_id: input.dailyCardID,
      row,
      prompt,
      revision_instructions: revisionInstructions,
    }));

    return { rowIndex, prompt, promptHash };
  }));

  const rowsToGenerate = preparedRows.filter(({ rowIndex, promptHash }) => {
    const cached = input.force
      ? null
      : cachedAssetForRow(assets, rowIndex, promptHash, model);
    if (cached) {
      cachedCount += 1;
      return false;
    }
    return true;
  });

  const generatedResults = await runOrderedBounded(
    rowsToGenerate,
    normalizedConcurrency(input.concurrency),
    (prepared) =>
      generateAndUploadStoryboardThumbnail(
        input,
        prepared,
        geminiAPIKey,
        model,
        revisionInstructions,
        input.generateImage ?? generateGeminiImageWithFallback,
      ),
  );

  const failedResult = generatedResults.find((result) => !result.ok);
  if (failedResult && !failedResult.ok) {
    throw failedResult.error;
  }

  const generatedAssets = generatedResults
    .filter((result): result is { ok: true; value: StoryboardThumbnailAsset } =>
      result.ok
    )
    .map((result) => result.value)
    .sort((left, right) => left.row_index - right.row_index);
  for (const asset of generatedAssets) {
    assets = mergeStoryboardThumbnailAsset(assets, asset);
  }
  generatedCount = generatedAssets.length;

  if (input.persist !== false) {
    const { error: updateError } = await input.admin
      .from("daily_cards")
      .update({ storyboard_thumbnail_assets: assets })
      .eq("workspace_id", input.workspaceID)
      .eq("creator_id", input.creatorID)
      .eq("id", input.dailyCardID);

    if (updateError) {
      throw new StoryboardThumbnailGenerationError(
        "storyboard_thumbnail_save_failed",
        { cause: updateError },
      );
    }
  }

  return {
    assets,
    generatedCount,
    cachedCount,
    model,
    promptVersion: STORYBOARD_THUMBNAIL_PROMPT_VERSION,
  };
}

type PreparedStoryboardThumbnailRow = {
  rowIndex: number;
  prompt: string;
  promptHash: string;
};

export type OrderedSettledResult<T> =
  | { ok: true; value: T }
  | { ok: false; error: unknown };

async function generateAndUploadStoryboardThumbnail(
  input: GenerateStoryboardThumbnailsInput,
  prepared: PreparedStoryboardThumbnailRow,
  geminiAPIKey: string,
  model: string,
  revisionInstructions: string | undefined,
  generateImage: typeof generateGeminiImageWithFallback,
): Promise<StoryboardThumbnailAsset> {
  const { rowIndex, prompt, promptHash } = prepared;
  const start = performance.now();
  let image: { data: string; mimeType: string; model: string };
  try {
    image = await generateImage({
      apiKey: geminiAPIKey,
      model,
      prompt,
    });
  } catch (error) {
    const code = error instanceof GeminiImageGenerationError
      ? error.code
      : "storyboard_thumbnail_gemini_failed";
    console.error(JSON.stringify({
      event: "storyboard_thumbnail_gemini_failed",
      daily_card_id: input.dailyCardID,
      row_index: rowIndex,
      model: error instanceof GeminiImageGenerationError ? error.model : model,
      upstream_status: error instanceof GeminiImageGenerationError
        ? error.status
        : undefined,
      provider_code: error instanceof GeminiImageGenerationError
        ? error.providerCode
        : undefined,
      error: code,
      detail: error instanceof GeminiImageGenerationError
        ? error.providerMessage ??
          String((error as Error & { cause?: unknown }).cause ?? "")
        : undefined,
    }));
    throw new StoryboardThumbnailGenerationError(code, { cause: error });
  }

  const latencyMs = Math.round(performance.now() - start);
  const bytes = base64ToBytes(image.data);
  const extension = image.mimeType === "image/png" ? "png" : "jpg";
  const storagePath = [
    input.workspaceID,
    input.creatorID,
    input.dailyCardID,
    `row-${rowIndex}-${promptHash.slice(0, 12)}.${extension}`,
  ].join("/");

  const { error: uploadError } = await input.admin.storage
    .from(STORYBOARD_THUMBNAIL_BUCKET)
    .upload(storagePath, bytes, {
      contentType: image.mimeType,
      upsert: true,
    });
  if (uploadError) {
    console.error(JSON.stringify({
      event: "storyboard_thumbnail_upload_failed",
      daily_card_id: input.dailyCardID,
      row_index: rowIndex,
      error: uploadError.message ?? "upload_failed",
    }));
    throw new StoryboardThumbnailGenerationError(
      "storyboard_thumbnail_upload_failed",
      { cause: uploadError },
    );
  }

  const publicURL = input.admin.storage.from(STORYBOARD_THUMBNAIL_BUCKET)
    .getPublicUrl(storagePath)
    .data.publicUrl;
  const asset: StoryboardThumbnailAsset = {
    row_index: rowIndex,
    prompt_hash: promptHash,
    storage_path: storagePath,
    public_url: publicURL,
    model: image.model,
    prompt_version: STORYBOARD_THUMBNAIL_PROMPT_VERSION,
    status: "generated",
    generated_at: new Date().toISOString(),
  };
  console.log(JSON.stringify({
    event: "storyboard_thumbnail_generated",
    daily_card_id: input.dailyCardID,
    row_index: rowIndex,
    model: image.model,
    prompt_version: STORYBOARD_THUMBNAIL_PROMPT_VERSION,
    prompt_chars: prompt.length,
    has_revision_instructions: Boolean(revisionInstructions),
    latency_ms: latencyMs,
    bytes: bytes.byteLength,
    source: "shared_storyboard_generation",
  }));
  return asset;
}

/**
 * Run already ordered work with bounded concurrency. Once a failure settles,
 * no additional work is claimed; already launched siblings are still awaited.
 * Returned settlements retain their original input order so callers can apply
 * deterministic error precedence independent of completion timing.
 */
export async function runOrderedBounded<T, R>(
  items: readonly T[],
  concurrency: number,
  task: (item: T) => Promise<R>,
): Promise<OrderedSettledResult<R>[]> {
  if (!Number.isInteger(concurrency) || concurrency < 1) {
    throw new Error("bounded concurrency must be a positive integer");
  }

  const results: Array<OrderedSettledResult<R> | undefined> = new Array(
    items.length,
  );
  let nextIndex = 0;
  let failureObserved = false;

  async function worker(): Promise<void> {
    while (true) {
      if (failureObserved) {
        return;
      }
      const index = nextIndex++;
      if (index >= items.length) {
        return;
      }
      try {
        results[index] = { ok: true, value: await task(items[index]) };
      } catch (error) {
        results[index] = { ok: false, error };
        failureObserved = true;
      }
    }
  }

  await Promise.all(
    Array.from({ length: Math.min(concurrency, items.length) }, () => worker()),
  );
  return results.filter(
    (result): result is OrderedSettledResult<R> => result !== undefined,
  );
}

function normalizedConcurrency(value: number | undefined): number {
  if (value === undefined || !Number.isFinite(value)) {
    return DEFAULT_STORYBOARD_THUMBNAIL_CONCURRENCY;
  }
  return Math.min(
    MAX_STORYBOARD_THUMBNAIL_CONCURRENCY,
    Math.max(1, Math.floor(value)),
  );
}

function normalizedRevisionInstructions(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim().replace(/\s+/g, " ");
  if (!trimmed) {
    return undefined;
  }
  return trimmed.slice(0, 600);
}

function base64ToBytes(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}
