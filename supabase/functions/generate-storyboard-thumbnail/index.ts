import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  corsHeaders,
  jsonResponse,
  sha256Hex,
  SupabaseAdminClient,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";
import {
  DEFAULT_GEMINI_IMAGE_MODEL,
  GeminiImageGenerationError,
  generateGeminiImageWithFallback,
} from "../_shared/gemini-image.ts";
import {
  buildStoryboardThumbnailPrompt,
  cachedAssetForRow,
  mergeStoryboardThumbnailAsset,
  normalizeStoryboardThumbnailAssets,
  STORYBOARD_THUMBNAIL_PROMPT_VERSION,
  storyboardRowsForCard,
  StoryboardThumbnailAsset,
} from "./storyboard-thumbnail.ts";

type GenerateStoryboardThumbnailRequest = {
  creator_id?: string;
  daily_card_id?: string;
  row_index?: number;
  row_indexes?: number[];
  force?: boolean;
  revision_instructions?: string;
};

type StorageCapableAdminClient = SupabaseAdminClient & {
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

const CARD_SELECT = [
  "id",
  "workspace_id",
  "creator_id",
  "scheduled_date",
  "title",
  "content_pillar",
  "scene_list",
  "script",
  "on_screen_text",
  "post_instructions",
  "storyboard_thumbnail_assets",
].join(",");

const BUCKET_NAME = "storyboard-thumbnails";

if (import.meta.main) {
  Deno.serve((request) => handleGenerateStoryboardThumbnailRequest(request));
}

export async function handleGenerateStoryboardThumbnailRequest(
  request: Request,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const geminiAPIKey = Deno.env.get("GEMINI_API_KEY");
  const model = Deno.env.get("GEMINI_IMAGE_MODEL")?.trim() ||
    DEFAULT_GEMINI_IMAGE_MODEL;

  if (!supabaseURL || !serviceRoleKey) {
    return jsonResponse({ error: "missing_function_secrets" }, 500);
  }
  if (!geminiAPIKey) {
    return jsonResponse({ error: "gemini_api_key_missing" }, 500);
  }

  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false },
  }) as StorageCapableAdminClient;

  const authResult = await verifyDeviceSession(request, admin, [
    "owner",
    "editor",
  ]);
  if ("response" in authResult) {
    return authResult.response;
  }

  let body: GenerateStoryboardThumbnailRequest;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const creatorID = body.creator_id?.trim();
  const dailyCardID = body.daily_card_id?.trim();
  if (!creatorID || !dailyCardID) {
    return jsonResponse({ error: "invalid_thumbnail_payload" }, 400);
  }

  const rowIndexes = normalizedRowIndexes(body);
  if (rowIndexes === null) {
    return jsonResponse({ error: "invalid_thumbnail_payload" }, 400);
  }
  const revisionInstructions = normalizedRevisionInstructions(
    body.revision_instructions,
  );

  const { data: card, error: cardError } = await admin
    .from("daily_cards")
    .select(CARD_SELECT)
    .eq("workspace_id", authResult.session.workspaceID)
    .eq("creator_id", creatorID)
    .eq("id", dailyCardID)
    .maybeSingle();

  if (cardError) {
    return jsonResponse({ error: "daily_card_lookup_failed" }, 500);
  }
  if (!card || typeof card !== "object") {
    return jsonResponse({ error: "daily_card_not_found" }, 404);
  }

  const cardRecord = card as Record<string, unknown>;
  const rows = storyboardRowsForCard(cardRecord);
  const targets = (rowIndexes ?? rows.map((row) => row.row_index))
    .filter((rowIndex) => rowIndex >= 0 && rowIndex < rows.length);
  if (targets.length === 0) {
    return jsonResponse({ error: "storyboard_row_not_found" }, 404);
  }

  let assets = normalizeStoryboardThumbnailAssets(
    cardRecord.storyboard_thumbnail_assets,
  );
  let generatedCount = 0;
  let cachedCount = 0;

  for (const rowIndex of targets) {
    const row = rows[rowIndex];
    const prompt = buildStoryboardThumbnailPrompt(
      cardRecord,
      row,
      revisionInstructions,
    );
    const promptHash = await sha256Hex(JSON.stringify({
      version: STORYBOARD_THUMBNAIL_PROMPT_VERSION,
      model,
      daily_card_id: dailyCardID,
      row,
      prompt,
      revision_instructions: revisionInstructions,
    }));

    const cached = body.force
      ? null
      : cachedAssetForRow(assets, rowIndex, promptHash, model);
    if (cached) {
      cachedCount += 1;
      continue;
    }

    const start = performance.now();
    let image: { data: string; mimeType: string; model: string };
    try {
      image = await generateGeminiImageWithFallback({
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
        daily_card_id: dailyCardID,
        row_index: rowIndex,
        model,
        error: code,
        detail: error instanceof GeminiImageGenerationError
          ? String((error as Error & { cause?: unknown }).cause ?? "")
          : undefined,
      }));
      return jsonResponse({ error: code }, 502);
    }
    const latencyMs = Math.round(performance.now() - start);
    const bytes = base64ToBytes(image.data);
    const extension = image.mimeType === "image/png" ? "png" : "jpg";
    const storagePath = [
      authResult.session.workspaceID,
      creatorID,
      dailyCardID,
      `row-${rowIndex}-${promptHash.slice(0, 12)}.${extension}`,
    ].join("/");

    const { error: uploadError } = await admin.storage
      .from(BUCKET_NAME)
      .upload(storagePath, bytes, {
        contentType: image.mimeType,
        upsert: true,
      });
    if (uploadError) {
      console.error(JSON.stringify({
        event: "storyboard_thumbnail_upload_failed",
        daily_card_id: dailyCardID,
        row_index: rowIndex,
        error: uploadError.message ?? "upload_failed",
      }));
      return jsonResponse({ error: "storyboard_thumbnail_upload_failed" }, 500);
    }

    const publicURL = admin.storage.from(BUCKET_NAME)
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
    assets = mergeStoryboardThumbnailAsset(assets, asset);
    generatedCount += 1;
    console.log(JSON.stringify({
      event: "storyboard_thumbnail_generated",
      daily_card_id: dailyCardID,
      row_index: rowIndex,
      model,
      prompt_version: STORYBOARD_THUMBNAIL_PROMPT_VERSION,
      prompt_chars: prompt.length,
      has_revision_instructions: Boolean(revisionInstructions),
      latency_ms: latencyMs,
      bytes: bytes.byteLength,
    }));
  }

  const { error: updateError } = await admin
    .from("daily_cards")
    .update({ storyboard_thumbnail_assets: assets })
    .eq("workspace_id", authResult.session.workspaceID)
    .eq("creator_id", creatorID)
    .eq("id", dailyCardID);

  if (updateError) {
    return jsonResponse({ error: "storyboard_thumbnail_save_failed" }, 500);
  }

  return jsonResponse({
    daily_card_id: dailyCardID,
    assets,
    generated_count: generatedCount,
    cached_count: cachedCount,
    model,
    prompt_version: STORYBOARD_THUMBNAIL_PROMPT_VERSION,
  });
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

function normalizedRowIndexes(
  body: GenerateStoryboardThumbnailRequest,
): number[] | null | undefined {
  if (Array.isArray(body.row_indexes)) {
    const indexes = body.row_indexes
      .filter((value) => Number.isInteger(value) && value >= 0);
    return indexes.length === body.row_indexes.length
      ? Array.from(new Set(indexes))
      : null;
  }

  if (body.row_index === undefined) {
    return undefined;
  }

  return Number.isInteger(body.row_index) && body.row_index >= 0
    ? [body.row_index]
    : null;
}

function base64ToBytes(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}
