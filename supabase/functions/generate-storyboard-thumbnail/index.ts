import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  corsHeaders,
  jsonResponse,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";
import {
  generateStoryboardThumbnailsForCard,
  StorageCapableAdminClient,
  StoryboardThumbnailGenerationError,
} from "../_shared/storyboard-thumbnail-generation.ts";
import { STORYBOARD_THUMBNAIL_PROMPT_VERSION } from "../_shared/storyboard-thumbnail.ts";

type GenerateStoryboardThumbnailRequest = {
  creator_id?: string;
  daily_card_id?: string;
  row_index?: number;
  row_indexes?: number[];
  force?: boolean;
  revision_instructions?: string;
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

  if (!supabaseURL || !serviceRoleKey) {
    return jsonResponse({ error: "missing_function_secrets" }, 500);
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

  try {
    const result = await generateStoryboardThumbnailsForCard({
      admin,
      workspaceID: authResult.session.workspaceID,
      creatorID,
      dailyCardID,
      cardRecord: card as Record<string, unknown>,
      rowIndexes: rowIndexes ?? undefined,
      force: body.force === true,
      revisionInstructions: body.revision_instructions,
      persist: true,
    });

    if (result.skippedReason === "gemini_api_key_missing") {
      return jsonResponse({ error: "gemini_api_key_missing" }, 500);
    }

    return jsonResponse({
      daily_card_id: dailyCardID,
      assets: result.assets,
      generated_count: result.generatedCount,
      cached_count: result.cachedCount,
      model: result.model,
      prompt_version: result.promptVersion ?? STORYBOARD_THUMBNAIL_PROMPT_VERSION,
    });
  } catch (error) {
    const code = error instanceof StoryboardThumbnailGenerationError
      ? error.code
      : "storyboard_thumbnail_gemini_failed";
    const status = code === "storyboard_row_not_found"
      ? 404
      : code === "storyboard_thumbnail_upload_failed" ||
          code === "storyboard_thumbnail_save_failed"
      ? 500
      : 502;
    return jsonResponse({ error: code }, status);
  }
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
