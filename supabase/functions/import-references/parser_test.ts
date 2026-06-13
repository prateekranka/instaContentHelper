import { parsedRowsFromCSV } from "./csv.ts";
import {
  classifyURL,
  normalizeInstagramHandle,
  normalizePlainHandle,
  normalizeURL,
} from "./normalization.ts";
import { checksumFor, parseReferenceImport } from "./parser.ts";
import { MAX_IMPORT_ROWS, RowLimitError } from "./types.ts";

Deno.test("normalizes handles and profile URLs before comparison", () => {
  assertEquals(normalizePlainHandle("@Sample.Creator/"), "sample.creator");
  assertEquals(
    normalizeInstagramHandle(
      "https://www.instagram.com/Sample_Creator/?utm_source=share",
    ),
    "sample_creator",
  );
  assertEquals(
    normalizeInstagramHandle("https://www.instagram.com/stories/creator/123"),
    null,
  );
  assertEquals(normalizePlainHandle("123456"), null);
  assertEquals(normalizePlainHandle("reel"), null);
});

Deno.test("normalizes URLs by stripping tracking params and trailing path slashes", () => {
  assertEquals(
    normalizeURL(
      "www.instagram.com/reel/ABC123/?utm_source=feed&igshid=abc&keep=1#frag",
    ),
    "https://www.instagram.com/reel/ABC123?keep=1",
  );
});

Deno.test("classifies story URLs as hard invalid references", () => {
  const result = classifyURL(
    "https://www.instagram.com/stories/creator/123456789/",
  );
  assertEquals(result.kind, "story");
  if (result.kind !== "story") {
    throw new Error("Expected story classification");
  }
  assertEquals(result.reason, "Story URLs can't be used as references.");
});

Deno.test("parses paste imports into account, reel, audio, invalid story, and unknown rows", async () => {
  const preview = await parseReferenceImport(
    [
      "@fit_over_sixty",
      "https://www.instagram.com/creator/reel/ABC123/?utm_source=x @SampleCreator",
      "https://www.instagram.com/reels/audio/987654/",
      "https://www.instagram.com/stories/creator/123",
      "remember towel transition",
    ].join("\n"),
    "paste",
  );

  assertEquals(preview.destination.watchlist_name, "Inspiration");
  assertEquals(preview.counts.total_rows, 5);
  assertEquals(preview.counts.clean_accounts, 1);
  assertEquals(preview.counts.clean_reels, 1);
  assertEquals(preview.counts.clean_audio, 1);
  assertEquals(preview.counts.needs_review, 2);
  assertEquals(preview.counts.invalid, 1);
  assertEquals(preview.counts.importable, 4);

  const account = preview.rows[0];
  assertEquals(account.classification, "account");
  assertEquals(account.status_on_confirm, "active");
  assertEquals(account.normalized_handle, "fit_over_sixty");
  assertEquals(account.handle, "@fit_over_sixty");

  const reel = preview.rows[1];
  assertEquals(reel.classification, "reel");
  assertEquals(reel.source_type, "reel_link");
  assertEquals(reel.status_on_confirm, "confirmed");
  assertEquals(reel.canonical_source_key, "instagram:reel:ABC123");
  assertEquals(reel.inferred_account?.normalized_handle, "samplecreator");
  assertEquals(reel.inferred_account?.conflict, true);
  assertEquals(reel.provenance.account_conflict, true);

  const audio = preview.rows[2];
  assertEquals(audio.classification, "audio");
  assertEquals(audio.source_type, "audio_link");
  assertEquals(audio.status_on_confirm, "confirmed");
  assertEquals(
    audio.canonical_source_key,
    "https://www.instagram.com/reels/audio/987654",
  );

  const story = preview.rows[3];
  assertEquals(story.preview_state, "invalid");
  assertEquals(story.invalid_reason, "Story URLs can't be used as references.");

  const unknown = preview.rows[4];
  assertEquals(unknown.classification, "unknown");
  assertEquals(unknown.source_type, "import_row");
  assertEquals(unknown.status_on_confirm, "needs_review");
  assertEquals(unknown.notes, "remember towel transition");
});

Deno.test("CSV parser treats content as data when there is no known header", () => {
  const rows = parsedRowsFromCSV([
    "https://www.instagram.com/reel/FIRST123/,first note",
    "@second_creator,second note",
  ].join("\n"));

  assertEquals(rows.length, 2);
  assertEquals(rows[0].lineNumber, 1);
  assertEquals(rows[0].values[0], "https://www.instagram.com/reel/FIRST123/");
  assertEquals(rows[0].unknownColumns?.column_2, "first note");
});

Deno.test("CSV imports preserve known and unknown columns in provenance", async () => {
  const csv = [
    "URL,Handle,Display Name,Notes,Tags,Region,Extra Context",
    '"https://www.instagram.com/reel/CSV123/?utm_campaign=x",@CSV_Mom,"CSV Mom","quoted, note","race|puma",USA,"keep raw"',
  ].join("\n");

  const preview = await parseReferenceImport(csv, "csv", "references.csv");
  assertEquals(preview.rows.length, 1);

  const row = preview.rows[0];
  assertEquals(row.classification, "reel");
  assertEquals(row.title, "CSV Mom");
  assertEquals(row.notes, "quoted, note");
  assertEquals(row.inferred_account?.normalized_handle, "csv_mom");
  assertEquals(row.provenance.filename, "references.csv");

  const csvColumns = row.provenance.csv_columns as Record<string, string>;
  assertEquals(
    csvColumns.url,
    "https://www.instagram.com/reel/CSV123/?utm_campaign=x",
  );
  assertEquals(csvColumns.handle, "@CSV_Mom");
  assertEquals(csvColumns.extra_context, "keep raw");

  const unknownColumns = row.provenance.unknown_columns as Record<
    string,
    string
  >;
  assertEquals(unknownColumns.extra_context, "keep raw");
});

Deno.test("checksum is stable across CRLF but changes when filename changes", async () => {
  const lf = await checksumFor(
    "@creator\nhttps://www.instagram.com/reel/A1/",
    "paste",
    null,
  );
  const crlf = await checksumFor(
    "@creator\r\nhttps://www.instagram.com/reel/A1/",
    "paste",
    null,
  );
  const renamed = await checksumFor(
    "@creator\nhttps://www.instagram.com/reel/A1/",
    "paste",
    "references.txt",
  );

  assertEquals(lf, crlf);
  assertNotEquals(lf, renamed);
});

Deno.test("rejects imports over the 500 row limit", async () => {
  const rawText = Array.from(
    { length: MAX_IMPORT_ROWS + 1 },
    (_, index) => `@creator_${index}`,
  ).join("\n");

  try {
    await parseReferenceImport(rawText, "paste");
  } catch (error) {
    assert(error instanceof RowLimitError, "Expected RowLimitError");
    assertEquals(error.rowCount, MAX_IMPORT_ROWS + 1);
    return;
  }

  throw new Error("Expected row limit rejection");
});

function assert(
  condition: unknown,
  message = "Assertion failed",
): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  if (!Object.is(actual, expected)) {
    throw new Error(
      message ??
        `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

function assertNotEquals<T>(actual: T, expected: T, message?: string): void {
  if (Object.is(actual, expected)) {
    throw new Error(
      message ??
        `Expected values to differ, both were ${JSON.stringify(actual)}`,
    );
  }
}
