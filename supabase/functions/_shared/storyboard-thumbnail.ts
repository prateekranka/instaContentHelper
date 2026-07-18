export const STORYBOARD_THUMBNAIL_PROMPT_VERSION = "storyboard_thumbnail_v1";

export type StoryboardThumbnailAsset = {
  row_index: number;
  prompt_hash: string;
  storage_path?: string;
  public_url?: string;
  model?: string;
  prompt_version?: string;
  status?: string;
  generated_at?: string;
};

export type StoryboardThumbnailRow = {
  row_index: number;
  timecode: string;
  visual_shot: string;
  what_to_show: string;
  audio_dialogue: string;
  on_screen_text: string;
};

export function storyboardRowsForCard(
  card: Record<string, unknown>,
): StoryboardThumbnailRow[] {
  const postInstructions = asRecord(card.post_instructions) ?? {};
  const sceneList = recordArray(card.scene_list);
  // Prefer nested post_instructions timelines (DB shape); fall back to
  // top-level timelines from GeneratedDailyCard / API response shapes.
  const shotTimeline = firstNonEmptyRecordArray(
    postInstructions.shot_timeline,
    card.shot_timeline,
  );
  const voiceoverTimeline = firstNonEmptyRecordArray(
    postInstructions.voiceover_timeline,
    card.voiceover_timeline,
  );
  const onScreenTextTimeline = firstNonEmptyRecordArray(
    postInstructions.on_screen_text_timeline,
    card.on_screen_text_timeline,
  );
  const fallbackText = stringArray(card.on_screen_text);
  const fallbackScriptLines = scriptLines(stringValue(card.script));
  const rowCount = Math.max(
    sceneList.length,
    shotTimeline.length,
    voiceoverTimeline.length,
    onScreenTextTimeline.length,
    fallbackText.length,
  );

  return Array.from({ length: rowCount }, (_, index) => {
    const scene = sceneList[index];
    const shot = shotTimeline[index];
    const voiceover = voiceoverTimeline[index];
    const text = onScreenTextTimeline[index];

    return {
      row_index: index,
      timecode: firstString(
        stringValue(shot?.timestamp),
        stringValue(voiceover?.timestamp),
        stringValue(text?.timestamp),
        stringValue(scene?.duration),
        `Scene ${index + 1}`,
      ),
      visual_shot: firstString(
        stringValue(shot?.shot),
        stringValue(shot?.title),
        stringValue(scene?.title),
        "Shot not specified",
      ),
      what_to_show: firstString(
        stringValue(shot?.video_portion),
        stringValue(shot?.videoPortion),
        stringValue(shot?.detail),
        stringValue(shot?.title),
        stringValue(scene?.title),
        "Show the main action clearly.",
      ),
      audio_dialogue: firstString(
        stringValue(voiceover?.voiceover),
        stringValue(voiceover?.detail),
        stringValue(voiceover?.title),
        fallbackScriptLines[index],
        "No voiceover specified.",
      ),
      on_screen_text: firstString(
        stringValue(text?.on_screen_text),
        stringValue(text?.onScreenText),
        stringValue(text?.text),
        stringValue(text?.detail),
        fallbackText[index],
        "No on-screen text.",
      ),
    };
  });
}

export function buildStoryboardThumbnailPrompt(
  card: Record<string, unknown>,
  row: StoryboardThumbnailRow,
  revisionInstructions?: string,
): string {
  const title = firstString(stringValue(card.title), "Untitled Reel");
  const pillar = firstString(stringValue(card.content_pillar), "creator story");
  const hook = firstString(
    stringValue(card.hook),
    stringValue(asRecord(card.post_instructions)?.hook),
    title,
  );

  return [
    "Create one photorealistic 16:9 storyboard thumbnail for a mobile Instagram Reel production table.",
    "No captions, no readable text, no logos, no watermarks, no UI chrome.",
    "Style: natural phone-video frame, candid creator content, realistic Indian fitness/lifestyle creator, warm indoor or outdoor light.",
    `Reel title: ${title}`,
    `Content pillar: ${pillar}`,
    `Reel hook: ${hook}`,
    `Time: ${row.timecode}`,
    `Visual / shot type: ${row.visual_shot}`,
    `What to show: ${row.what_to_show}`,
    `Dialogue context: ${row.audio_dialogue}`,
    revisionInstructions
      ? `Refresh direction: ${revisionInstructions}`
      : undefined,
    "Make the frame immediately understandable as the visual reference for this row, with clean composition and enough negative space for editing notes outside the image.",
  ].filter((line): line is string => !!line).join("\n");
}

export function normalizeStoryboardThumbnailAssets(
  value: unknown,
): StoryboardThumbnailAsset[] {
  const assets: StoryboardThumbnailAsset[] = [];
  for (const asset of recordArray(value)) {
    const rowIndex = numberValue(asset.row_index);
    const promptHash = stringValue(asset.prompt_hash);
    if (
      rowIndex === undefined || !Number.isInteger(rowIndex) || rowIndex < 0 ||
      !promptHash
    ) {
      continue;
    }
    assets.push({
      row_index: rowIndex,
      prompt_hash: promptHash,
      storage_path: stringValue(asset.storage_path),
      public_url: stringValue(asset.public_url),
      model: stringValue(asset.model),
      prompt_version: stringValue(asset.prompt_version),
      status: stringValue(asset.status),
      generated_at: stringValue(asset.generated_at),
    });
  }
  return assets.sort((left, right) => left.row_index - right.row_index);
}

export function cachedAssetForRow(
  assets: StoryboardThumbnailAsset[],
  rowIndex: number,
  promptHash: string,
  model: string,
): StoryboardThumbnailAsset | null {
  return assets.find((asset) =>
    asset.row_index === rowIndex &&
    asset.prompt_hash === promptHash &&
    asset.model === model &&
    asset.public_url &&
    asset.storage_path
  ) ?? null;
}

export function mergeStoryboardThumbnailAsset(
  assets: StoryboardThumbnailAsset[],
  asset: StoryboardThumbnailAsset,
): StoryboardThumbnailAsset[] {
  return [
    ...assets.filter((existing) => existing.row_index !== asset.row_index),
    asset,
  ].sort((left, right) => left.row_index - right.row_index);
}

export function extractGeneratedImage(
  response: unknown,
): { data: string; mimeType: string } | null {
  const direct = imageFromUnknown(asRecord(response)?.output_image);
  if (direct) {
    return direct;
  }

  return findImage(response, new Set<unknown>());
}

function findImage(
  value: unknown,
  seen: Set<unknown>,
): { data: string; mimeType: string } | null {
  if (!value || typeof value !== "object" || seen.has(value)) {
    return null;
  }

  seen.add(value);
  const image = imageFromUnknown(value);
  if (image) {
    return image;
  }

  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findImage(item, seen);
      if (found) {
        return found;
      }
    }
    return null;
  }

  for (const item of Object.values(value as Record<string, unknown>)) {
    const found = findImage(item, seen);
    if (found) {
      return found;
    }
  }
  return null;
}

function imageFromUnknown(
  value: unknown,
): { data: string; mimeType: string } | null {
  const record = asRecord(value);
  if (!record) {
    return null;
  }
  const data = stringValue(record.data);
  const mimeType = stringValue(record.mime_type) ??
    stringValue(record.mimeType) ??
    "image/jpeg";
  if (!data || !mimeType.startsWith("image/")) {
    return null;
  }
  return { data, mimeType };
}

function scriptLines(script?: string): string[] {
  return (script ?? "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
}

function recordArray(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value)
    ? value.filter((item): item is Record<string, unknown> => !!asRecord(item))
    : [];
}

function firstNonEmptyRecordArray(
  ...values: unknown[]
): Record<string, unknown>[] {
  for (const value of values) {
    const rows = recordArray(value);
    if (rows.length > 0) {
      return rows;
    }
  }
  return [];
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.map(stringValue).filter((item): item is string => !!item)
    : [];
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function firstString(...values: (string | undefined)[]): string {
  return values.find((value) => value && value.trim().length > 0) ?? "";
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : undefined;
}

function numberValue(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : undefined;
}
