import {
  DEFAULT_GEMINI_IMAGE_MODEL,
  GeminiImageGenerationError,
} from "./gemini-image.ts";
import {
  generateStoryboardThumbnailsForCard,
  runOrderedBounded,
  StorageCapableAdminClient,
  StoryboardThumbnailGenerationError,
} from "./storyboard-thumbnail-generation.ts";
import {
  buildStoryboardThumbnailPrompt,
  STORYBOARD_THUMBNAIL_PROMPT_VERSION,
  storyboardRowsForCard,
} from "./storyboard-thumbnail.ts";
import { sha256Hex } from "./device-auth.ts";

Deno.test("storyboard generation bounds provider work and merges assets by row", async () => {
  const state = makeAdmin();
  let inFlight = 0;
  let maxInFlight = 0;
  const startedRows: number[] = [];

  const result = await generateStoryboardThumbnailsForCard({
    ...baseInput(state),
    rowIndexes: [2, 0, 1],
    generateImage: async ({ model, prompt }) => {
      const rowIndex = rowIndexFromPrompt(prompt);
      startedRows.push(rowIndex);
      inFlight += 1;
      maxInFlight = Math.max(maxInFlight, inFlight);
      await wait(rowIndex === 0 ? 25 : rowIndex === 1 ? 5 : 1);
      inFlight -= 1;
      return { data: btoa(`image-${rowIndex}`), mimeType: "image/jpeg", model };
    },
  });

  assertEquals(maxInFlight, 2);
  assertEquals(startedRows, [0, 1, 2]);
  assertEquals(result.assets.map((asset) => asset.row_index), [0, 1, 2]);
  assertEquals(result.generatedCount, 3);
  assertEquals(state.updatedAssets?.map((asset) => asset.row_index), [0, 1, 2]);
});

Deno.test("storyboard generation deduplicates target rows before generation", async () => {
  const state = makeAdmin();
  const generatedRows: number[] = [];

  const result = await generateStoryboardThumbnailsForCard({
    ...baseInput(state),
    rowIndexes: [1, 1, 0, 1, 0],
    generateImage: async ({ model, prompt }) => {
      const rowIndex = rowIndexFromPrompt(prompt);
      generatedRows.push(rowIndex);
      return { data: btoa(`image-${rowIndex}`), mimeType: "image/jpeg", model };
    },
  });

  assertEquals(generatedRows, [0, 1]);
  assertEquals(result.generatedCount, 2);
  assertEquals(result.assets.map((asset) => asset.row_index), [0, 1]);
  assertEquals(state.uploadedPaths.length, 2);
});

Deno.test("storyboard generation skips matching cached rows", async () => {
  const state = makeAdmin();
  const model = DEFAULT_GEMINI_IMAGE_MODEL;
  const cardRecord = cardWithRows(1);
  const row = storyboardRowsForCard(cardRecord)[0];
  const prompt = buildStoryboardThumbnailPrompt(cardRecord, row);
  const promptHash = await sha256Hex(JSON.stringify({
    version: STORYBOARD_THUMBNAIL_PROMPT_VERSION,
    model,
    daily_card_id: "daily-card",
    row,
    prompt,
    revision_instructions: undefined,
  }));
  const cachedAsset = {
    row_index: 0,
    prompt_hash: promptHash,
    storage_path: "workspace/creator/daily-card/row-0-cached.jpg",
    public_url: "https://example.com/cached.jpg",
    model,
  };

  const result = await generateStoryboardThumbnailsForCard({
    ...baseInput(state),
    model,
    cardRecord: { ...cardRecord, storyboard_thumbnail_assets: [cachedAsset] },
    rowIndexes: [0],
    generateImage: async () => {
      throw new Error("cached rows must not invoke the provider");
    },
  });

  assertEquals(result.generatedCount, 0);
  assertEquals(result.cachedCount, 1);
  assertEquals(result.assets, [cachedAsset]);
  assertEquals(state.uploadedPaths, []);
});

Deno.test("storyboard generation mixes cached and generated rows without changing output order", async () => {
  const state = makeAdmin();
  const model = DEFAULT_GEMINI_IMAGE_MODEL;
  const cardRecord = cardWithRows(3);
  const row = storyboardRowsForCard(cardRecord)[1];
  const prompt = buildStoryboardThumbnailPrompt(cardRecord, row);
  const promptHash = await sha256Hex(JSON.stringify({
    version: STORYBOARD_THUMBNAIL_PROMPT_VERSION,
    model,
    daily_card_id: "daily-card",
    row,
    prompt,
    revision_instructions: undefined,
  }));
  const cachedAsset = {
    row_index: 1,
    prompt_hash: promptHash,
    storage_path: "workspace/creator/daily-card/row-1-cached.jpg",
    public_url: "https://example.com/cached-row-1.jpg",
    model,
    prompt_version: STORYBOARD_THUMBNAIL_PROMPT_VERSION,
    status: "generated",
    generated_at: "2026-07-27T00:00:00.000Z",
  };
  const generatedRows: number[] = [];

  const result = await generateStoryboardThumbnailsForCard({
    ...baseInput(state),
    model,
    cardRecord: { ...cardRecord, storyboard_thumbnail_assets: [cachedAsset] },
    rowIndexes: [2, 1, 0],
    generateImage: async ({ model, prompt }) => {
      const rowIndex = rowIndexFromPrompt(prompt);
      generatedRows.push(rowIndex);
      return { data: btoa(`image-${rowIndex}`), mimeType: "image/jpeg", model };
    },
  });

  assertEquals(generatedRows, [0, 2]);
  assertEquals(result.generatedCount, 2);
  assertEquals(result.cachedCount, 1);
  assertEquals(result.assets.map((asset) => asset.row_index), [0, 1, 2]);
  assertEquals(state.updatedAssets?.map((asset) => asset.row_index), [0, 1, 2]);
});

Deno.test("ordered bounded scheduler validates its normalized-concurrency seam", async () => {
  let thrown: unknown;
  try {
    await runOrderedBounded([0], 0, async (value) => value);
  } catch (error) {
    thrown = error;
  }
  assert(
    thrown instanceof Error &&
      thrown.message === "bounded concurrency must be a positive integer",
    "invalid scheduler concurrency should fail before claiming work",
  );
});

Deno.test("storyboard generation waits for launched tasks and does not persist partial assets on failure", async () => {
  const state = makeAdmin();
  let successfulTaskSettled = false;
  const model = DEFAULT_GEMINI_IMAGE_MODEL;

  let thrown: unknown;
  try {
    await generateStoryboardThumbnailsForCard({
      ...baseInput(state),
      rowIndexes: [0, 1],
      concurrency: 2,
      generateImage: async ({ model, prompt }) => {
        const rowIndex = rowIndexFromPrompt(prompt);
        if (rowIndex === 0) {
          throw new GeminiImageGenerationError(
            "storyboard_thumbnail_gemini_failed",
            model,
            { status: 502, providerCode: "UNAVAILABLE" },
          );
        }
        await wait(20);
        successfulTaskSettled = true;
        return {
          data: btoa("successful-image"),
          mimeType: "image/jpeg",
          model,
        };
      },
    });
  } catch (error) {
    thrown = error;
  }

  if (!(thrown instanceof StoryboardThumbnailGenerationError)) {
    throw new Error("Expected StoryboardThumbnailGenerationError");
  }
  assertEquals(thrown.code, "storyboard_thumbnail_gemini_failed");
  assert(successfulTaskSettled, "launched task was not awaited");
  assertEquals(state.updatedAssets, undefined);
});

Deno.test("storyboard generation stops claiming rows after an observed failure", async () => {
  const state = makeAdmin();
  let releaseRowOne!: () => void;
  let resolveRowOneStarted!: () => void;
  let resolveRowZeroFailed!: () => void;
  let rowTwoInvoked = false;
  const rowOneGate = new Promise<void>((resolve) => {
    releaseRowOne = resolve;
  });
  const rowOneStarted = new Promise<void>((resolve) => {
    resolveRowOneStarted = resolve;
  });
  const rowZeroFailed = new Promise<void>((resolve) => {
    resolveRowZeroFailed = resolve;
  });

  const generation = generateStoryboardThumbnailsForCard({
    ...baseInput(state),
    rowIndexes: [0, 1, 2],
    concurrency: 2,
    generateImage: async ({ model, prompt }) => {
      const rowIndex = rowIndexFromPrompt(prompt);
      if (rowIndex === 0) {
        resolveRowZeroFailed();
        throw new GeminiImageGenerationError(
          "storyboard_thumbnail_gemini_failed",
          model,
          { status: 502, providerCode: "UNAVAILABLE" },
        );
      }
      if (rowIndex === 1) {
        resolveRowOneStarted();
        await rowOneGate;
        return { data: btoa("row-one-image"), mimeType: "image/jpeg", model };
      }
      rowTwoInvoked = true;
      return { data: btoa("row-two-image"), mimeType: "image/jpeg", model };
    },
  });
  const settledGeneration = generation.then(
    () => ({ ok: true as const }),
    (error) => ({ ok: false as const, error }),
  );

  await Promise.all([rowOneStarted, rowZeroFailed]);
  await Promise.resolve();
  await Promise.resolve();
  assert(!rowTwoInvoked, "row 2 was claimed after row 0 failed");

  releaseRowOne();
  const settled = await settledGeneration;
  assert(!settled.ok, "failed batch unexpectedly succeeded");
  if (settled.ok) {
    return;
  }
  if (!(settled.error instanceof StoryboardThumbnailGenerationError)) {
    throw new Error("Expected StoryboardThumbnailGenerationError");
  }
  assertEquals(settled.error.code, "storyboard_thumbnail_gemini_failed");
  assertEquals(state.updatedAssets, undefined);
});

Deno.test("storyboard generation is target-count agnostic and clamps concurrency", async () => {
  const upperState = makeAdmin();
  let upperInFlight = 0;
  let upperMaxInFlight = 0;
  const upperResult = await generateStoryboardThumbnailsForCard({
    ...baseInput(upperState),
    cardRecord: cardWithRows(4),
    rowIndexes: [3, 0, 2, 1],
    concurrency: 99,
    generateImage: async ({ model, prompt }) => {
      const rowIndex = rowIndexFromPrompt(prompt);
      upperInFlight += 1;
      upperMaxInFlight = Math.max(upperMaxInFlight, upperInFlight);
      await wait(5);
      upperInFlight -= 1;
      return { data: btoa(`image-${rowIndex}`), mimeType: "image/jpeg", model };
    },
  });

  assertEquals(upperMaxInFlight, 3);
  assertEquals(
    upperResult.assets.map((asset) => asset.row_index),
    [0, 1, 2, 3],
  );

  const lowerState = makeAdmin();
  let lowerInFlight = 0;
  let lowerMaxInFlight = 0;
  await generateStoryboardThumbnailsForCard({
    ...baseInput(lowerState),
    concurrency: 0,
    generateImage: async ({ model, prompt }) => {
      const rowIndex = rowIndexFromPrompt(prompt);
      lowerInFlight += 1;
      lowerMaxInFlight = Math.max(lowerMaxInFlight, lowerInFlight);
      await wait(2);
      lowerInFlight -= 1;
      return { data: btoa(`image-${rowIndex}`), mimeType: "image/jpeg", model };
    },
  });
  assertEquals(lowerMaxInFlight, 1);
});

Deno.test("storyboard generation reports the earliest normalized-row failure", async () => {
  const state = makeAdmin();
  let thrown: unknown;
  try {
    await generateStoryboardThumbnailsForCard({
      ...baseInput(state),
      rowIndexes: [1, 0],
      concurrency: 2,
      generateImage: async ({ prompt }) => {
        const rowIndex = rowIndexFromPrompt(prompt);
        if (rowIndex === 0) {
          await wait(20);
          throw new Error("row-zero-failure");
        }
        throw new Error("row-one-failure");
      },
    });
  } catch (error) {
    thrown = error;
  }

  if (!(thrown instanceof StoryboardThumbnailGenerationError)) {
    throw new Error("Expected StoryboardThumbnailGenerationError");
  }
  const cause = (thrown as Error & { cause?: unknown }).cause;
  assert(
    cause instanceof Error && cause.message === "row-zero-failure",
    "completion timing changed normalized-row error precedence",
  );
  assertEquals(state.updatedAssets, undefined);
});

function baseInput(state: FakeAdminState) {
  return {
    admin: state.admin,
    workspaceID: "workspace",
    creatorID: "creator",
    dailyCardID: "daily-card",
    cardRecord: cardWithRows(3),
    geminiAPIKey: "test-key",
    persist: true,
  };
}

function cardWithRows(count: number): Record<string, unknown> {
  return {
    title: "Test reel",
    content_pillar: "fitness",
    post_instructions: {
      shot_timeline: Array.from({ length: count }, (_, index) => ({
        timestamp: `${index}-${index + 1} sec`,
        shot: `Shot ${index}`,
        video_portion: `Show row ${index}`,
      })),
      voiceover_timeline: Array.from({ length: count }, (_, index) => ({
        voiceover: `Dialogue ${index}`,
      })),
      on_screen_text_timeline: Array.from({ length: count }, (_, index) => ({
        on_screen_text: `TEXT ${index}`,
      })),
    },
  };
}

function rowIndexFromPrompt(prompt: string): number {
  const match = prompt.match(/What to show: Show row (\d+)/);
  if (!match) {
    throw new Error(`Missing row index in prompt: ${prompt}`);
  }
  return Number(match[1]);
}

function makeAdmin(): FakeAdminState {
  const uploadedPaths: string[] = [];
  let updatedAssets: Array<{ row_index: number }> | undefined;
  const query = {
    update(values: Record<string, unknown>) {
      updatedAssets = values.storyboard_thumbnail_assets as Array<{
        row_index: number;
      }>;
      return query;
    },
    eq() {
      return query;
    },
  };
  const storage = {
    from() {
      return {
        async upload(path: string) {
          uploadedPaths.push(path);
          return { data: null, error: null };
        },
        getPublicUrl(path: string) {
          return { data: { publicUrl: `https://example.com/${path}` } };
        },
      };
    },
  };
  const admin = {
    from() {
      return query;
    },
    storage,
  } as unknown as StorageCapableAdminClient;
  return {
    admin,
    uploadedPaths,
    get updatedAssets() {
      return updatedAssets;
    },
  };
}

type FakeAdminState = {
  admin: StorageCapableAdminClient;
  uploadedPaths: string[];
  readonly updatedAssets: Array<{ row_index: number }> | undefined;
};

function wait(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

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
