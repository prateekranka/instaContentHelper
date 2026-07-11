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
} from "../generate-storyboard-thumbnail/storyboard-thumbnail.ts";

type GenerateStoryboardThumbnailsRequest = {
  creator_id?: string;
  weekly_plan_id?: string;
  force?: boolean;
  max_rows?: number;
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

type WeekCardProgress = {
  daily_card_id: string;
  scheduled_date: string;
  assets: StoryboardThumbnailAsset[];
  generated_count: number;
  cached_count: number;
  remaining_count: number;
  failed_count: number;
};

type ImageGenerator = (
  apiKey: string,
  model: string,
  prompt: string,
) => Promise<{ data: string; mimeType: string; model?: string }>;

const CARD_SELECT = [
  "id",
  "workspace_id",
  "creator_id",
  "weekly_plan_id",
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
const DEFAULT_MAX_ROWS = 6;
const MAX_ROWS_PER_INVOCATION = 12;

if (import.meta.main) {
  Deno.serve((request) => handleGenerateStoryboardThumbnailsRequest(request));
}

export async function handleGenerateStoryboardThumbnailsRequest(
  request: Request,
  generateImage: ImageGenerator = defaultGenerateImage,
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

  let body: GenerateStoryboardThumbnailsRequest;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const creatorID = body.creator_id?.trim();
  const weeklyPlanID = body.weekly_plan_id?.trim();
  if (!creatorID || !weeklyPlanID) {
    return jsonResponse({ error: "invalid_thumbnail_week_payload" }, 400);
  }

  const maxRows = normalizedMaxRows(body.max_rows);

  const { data: weeklyPlan, error: planError } = await admin
    .from("weekly_plans")
    .select("id,workspace_id,creator_id,status")
    .eq("workspace_id", authResult.session.workspaceID)
    .eq("creator_id", creatorID)
    .eq("id", weeklyPlanID)
    .maybeSingle();

  if (planError) {
    return jsonResponse({ error: "weekly_plan_lookup_failed" }, 500);
  }
  if (!weeklyPlan || typeof weeklyPlan !== "object") {
    return jsonResponse({ error: "weekly_plan_not_found" }, 404);
  }

  const { data: cards, error: cardsError } = await admin
    .from("daily_cards")
    .select(CARD_SELECT)
    .eq("workspace_id", authResult.session.workspaceID)
    .eq("creator_id", creatorID)
    .eq("weekly_plan_id", weeklyPlanID)
    .order("scheduled_date", { ascending: true });

  if (cardsError) {
    return jsonResponse({ error: "daily_cards_lookup_failed" }, 500);
  }
  if (!Array.isArray(cards) || cards.length === 0) {
    return jsonResponse({ error: "weekly_plan_has_no_daily_cards" }, 404);
  }

  let generatedCount = 0;
  let cachedCount = 0;
  let remainingCount = 0;
  let failedCount = 0;
  let lastError: string | undefined;
  const cardProgress: WeekCardProgress[] = [];
  let shouldStopAfterCurrentCard = false;

  console.log(JSON.stringify({
    event: "storyboard_week_thumbnail_started",
    weekly_plan_id: weeklyPlanID,
    creator_id: creatorID,
    card_count: cards.length,
    force: body.force === true,
    max_rows: maxRows,
    model,
  }));

  for (const card of cards as Record<string, unknown>[]) {
    const dailyCardID = stringValue(card.id);
    const scheduledDate = stringValue(card.scheduled_date) ?? "";
    if (!dailyCardID) {
      continue;
    }

    const rows = storyboardRowsForCard(card);
    let assets = normalizeStoryboardThumbnailAssets(
      card.storyboard_thumbnail_assets,
    );
    let cardGeneratedCount = 0;
    let cardCachedCount = 0;
    let cardRemainingCount = 0;
    let cardFailedCount = 0;

    for (const row of rows) {
      const prompt = buildStoryboardThumbnailPrompt(card, row);
      const promptHash = await sha256Hex(JSON.stringify({
        version: STORYBOARD_THUMBNAIL_PROMPT_VERSION,
        model,
        daily_card_id: dailyCardID,
        row,
        prompt,
      }));

      const cached = body.force === true
        ? null
        : cachedAssetForRow(assets, row.row_index, promptHash, model);
      if (cached) {
        cardCachedCount += 1;
        cachedCount += 1;
        continue;
      }

      if (generatedCount >= maxRows) {
        cardRemainingCount += 1;
        remainingCount += 1;
        continue;
      }

      const start = performance.now();
      let image: { data: string; mimeType: string; model?: string };
      try {
        image = await generateImage(geminiAPIKey, model, prompt);
      } catch (error) {
        cardFailedCount += 1;
        failedCount += 1;
        cardRemainingCount += 1;
        remainingCount += 1;
        lastError = error instanceof GeminiImageGenerationError
          ? error.code
          : "storyboard_thumbnail_gemini_failed";
        console.error(JSON.stringify({
          event: "storyboard_week_thumbnail_gemini_failed",
          weekly_plan_id: weeklyPlanID,
          daily_card_id: dailyCardID,
          row_index: row.row_index,
          model,
          error: lastError,
        }));
        shouldStopAfterCurrentCard = true;
        break;
      }

      const latencyMs = Math.round(performance.now() - start);
      const bytes = base64ToBytes(image.data);
      const extension = image.mimeType === "image/png" ? "png" : "jpg";
      const storagePath = [
        authResult.session.workspaceID,
        creatorID,
        dailyCardID,
        `row-${row.row_index}-${promptHash.slice(0, 12)}.${extension}`,
      ].join("/");

      const { error: uploadError } = await admin.storage
        .from(BUCKET_NAME)
        .upload(storagePath, bytes, {
          contentType: image.mimeType,
          upsert: true,
        });
      if (uploadError) {
        return jsonResponse(
          { error: "storyboard_thumbnail_upload_failed" },
          500,
        );
      }

      const publicURL = admin.storage.from(BUCKET_NAME)
        .getPublicUrl(storagePath)
        .data.publicUrl;
      assets = mergeStoryboardThumbnailAsset(assets, {
        row_index: row.row_index,
        prompt_hash: promptHash,
        storage_path: storagePath,
        public_url: publicURL,
        model: image.model ?? model,
        prompt_version: STORYBOARD_THUMBNAIL_PROMPT_VERSION,
        status: "generated",
        generated_at: new Date().toISOString(),
      });

      const { error: updateError } = await admin
        .from("daily_cards")
        .update({ storyboard_thumbnail_assets: assets })
        .eq("workspace_id", authResult.session.workspaceID)
        .eq("creator_id", creatorID)
        .eq("id", dailyCardID);

      if (updateError) {
        return jsonResponse({ error: "storyboard_thumbnail_save_failed" }, 500);
      }

      generatedCount += 1;
      cardGeneratedCount += 1;
      console.log(JSON.stringify({
        event: "storyboard_week_thumbnail_generated",
        weekly_plan_id: weeklyPlanID,
        daily_card_id: dailyCardID,
        scheduled_date: scheduledDate,
        row_index: row.row_index,
        prompt_chars: prompt.length,
        latency_ms: latencyMs,
        bytes: bytes.byteLength,
        generated_count: generatedCount,
        max_rows: maxRows,
        model,
      }));
    }

    cardProgress.push({
      daily_card_id: dailyCardID,
      scheduled_date: scheduledDate,
      assets,
      generated_count: cardGeneratedCount,
      cached_count: cardCachedCount,
      remaining_count: cardRemainingCount,
      failed_count: cardFailedCount,
    });

    if (shouldStopAfterCurrentCard) {
      break;
    }
  }

  const complete = remainingCount === 0 && failedCount === 0;
  console.log(JSON.stringify({
    event: "storyboard_week_thumbnail_completed",
    weekly_plan_id: weeklyPlanID,
    generated_count: generatedCount,
    cached_count: cachedCount,
    remaining_count: remainingCount,
    failed_count: failedCount,
    complete,
    last_error: lastError,
  }));

  return jsonResponse({
    weekly_plan_id: weeklyPlanID,
    cards: cardProgress,
    generated_count: generatedCount,
    cached_count: cachedCount,
    remaining_count: remainingCount,
    failed_count: failedCount,
    complete,
    model,
    prompt_version: STORYBOARD_THUMBNAIL_PROMPT_VERSION,
    last_error: lastError,
  });
}

export function normalizedMaxRows(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return DEFAULT_MAX_ROWS;
  }
  return Math.max(
    1,
    Math.min(MAX_ROWS_PER_INVOCATION, Math.floor(value)),
  );
}

async function defaultGenerateImage(
  apiKey: string,
  model: string,
  prompt: string,
): Promise<{ data: string; mimeType: string; model?: string }> {
  return await generateGeminiImageWithFallback({
    apiKey,
    model,
    prompt,
  });
}

function base64ToBytes(value: string): Uint8Array {
  return Uint8Array.from(atob(value), (char) => char.charCodeAt(0));
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}
