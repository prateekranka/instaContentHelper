import {
  buildStoryboardThumbnailPrompt,
  cachedAssetForRow,
  extractGeneratedImage,
  mergeStoryboardThumbnailAsset,
  normalizeStoryboardThumbnailAssets,
  storyboardRowsForCard,
} from "./storyboard-thumbnail.ts";

Deno.test("storyboardRowsForCard derives rows from stored card timelines", () => {
  const rows = storyboardRowsForCard({
    title: "Strength story",
    content_pillar: "gym",
    scene_list: [{ title: "Opening", duration: "0-3 sec" }],
    post_instructions: {
      hook: "The biggest lie after 40.",
      shot_timeline: [{
        timestamp: "0-3 sec",
        shot: "Close-up talking head",
        video_portion: "Direct eye contact.",
      }],
      voiceover_timeline: [{ voiceover: "I believed that too." }],
      on_screen_text_timeline: [{ on_screen_text: "I BELIEVED THAT TOO." }],
    },
  });

  assertEquals(rows.length, 1);
  assertEquals(rows[0].timecode, "0-3 sec");
  assertEquals(rows[0].visual_shot, "Close-up talking head");
  assertEquals(rows[0].what_to_show, "Direct eye contact.");
  assertEquals(rows[0].audio_dialogue, "I believed that too.");
  assertEquals(rows[0].on_screen_text, "I BELIEVED THAT TOO.");
});

Deno.test("buildStoryboardThumbnailPrompt stays compact and excludes requested overlay text", () => {
  const [row] = storyboardRowsForCard({
    title: "Strength story",
    content_pillar: "gym",
    post_instructions: {
      shot_timeline: [{ timestamp: "0-3 sec", shot: "Close-up" }],
      voiceover_timeline: [{ voiceover: "The line." }],
      on_screen_text_timeline: [{ on_screen_text: "ON SCREEN" }],
    },
  });

  const prompt = buildStoryboardThumbnailPrompt(
    { title: "Strength story" },
    row,
  );

  assert(prompt.length < 1200);
  assert(prompt.includes("No captions"));
  assert(prompt.includes("16:9"));
  assert(!prompt.includes("ON SCREEN"));
});

Deno.test("buildStoryboardThumbnailPrompt includes directed refresh instructions", () => {
  const [row] = storyboardRowsForCard({
    title: "Strength story",
    content_pillar: "gym",
    post_instructions: {
      shot_timeline: [{ timestamp: "0-3 sec", shot: "Close-up" }],
      voiceover_timeline: [{ voiceover: "The line." }],
      on_screen_text_timeline: [{ on_screen_text: "ON SCREEN" }],
    },
  });

  const prompt = buildStoryboardThumbnailPrompt(
    { title: "Strength story" },
    row,
    "Make it a brighter gym close-up with more natural light.",
  );

  assert(prompt.length < 1200);
  assert(
    prompt.includes(
      "Refresh direction: Make it a brighter gym close-up with more natural light.",
    ),
  );
});

Deno.test("asset cache matches row, prompt hash, model, path, and URL", () => {
  const assets = normalizeStoryboardThumbnailAssets([
    {
      row_index: 1,
      prompt_hash: "abc",
      storage_path: "path/image.jpg",
      public_url: "https://example.com/image.jpg",
      model: "gemini-3.1-flash-lite-image",
    },
  ]);

  assert(
    cachedAssetForRow(assets, 1, "abc", "gemini-3.1-flash-lite-image") !==
      null,
  );
  assertEquals(
    cachedAssetForRow(assets, 0, "abc", "gemini-3.1-flash-lite-image"),
    null,
  );
  assertEquals(
    cachedAssetForRow(assets, 1, "def", "gemini-3.1-flash-lite-image"),
    null,
  );
});

Deno.test("mergeStoryboardThumbnailAsset replaces a row without disturbing others", () => {
  const merged = mergeStoryboardThumbnailAsset([
    { row_index: 0, prompt_hash: "old" },
    { row_index: 1, prompt_hash: "keep" },
  ], {
    row_index: 0,
    prompt_hash: "new",
    public_url: "https://example.com/new.jpg",
  });

  assertEquals(merged.length, 2);
  assertEquals(merged[0].prompt_hash, "new");
  assertEquals(merged[1].prompt_hash, "keep");
});

Deno.test("extractGeneratedImage handles interaction output image shape", () => {
  const image = extractGeneratedImage({
    output_image: {
      data: "aW1hZ2U=",
      mime_type: "image/jpeg",
    },
  });

  assertEquals(image?.data, "aW1hZ2U=");
  assertEquals(image?.mimeType, "image/jpeg");
});

function assert(value: boolean, message = "assertion failed"): void {
  if (!value) {
    throw new Error(message);
  }
}

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Assertion failed:\nactual: ${JSON.stringify(actual)}\nexpected: ${
        JSON.stringify(expected)
      }`,
    );
  }
}
