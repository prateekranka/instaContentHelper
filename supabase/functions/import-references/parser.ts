import { parsedRowsFromCSV, parsedRowsFromPaste } from "./csv.ts";
import {
  classifyURL,
  displayHandle,
  extractHandleTokens,
  extractURLs,
  normalizeInstagramHandle,
  normalizePlainHandle,
} from "./normalization.ts";
import {
  MAX_IMPORT_ROWS,
  type ParsedInputRow,
  PARSER_VERSION,
  ReferenceImportInputType,
  ReferenceImportPreview,
  ReferenceImportRow,
  RowLimitError,
  WATCHLIST_NAME,
} from "./types.ts";

export async function parseReferenceImport(
  rawText: string,
  inputType: ReferenceImportInputType,
  filename?: string | null,
): Promise<ReferenceImportPreview> {
  const rows = inputRows(rawText, inputType);

  if (rows.length > MAX_IMPORT_ROWS) {
    throw new RowLimitError(rows.length);
  }

  const parsedRows = rows.map((row, index) =>
    classifyInputRow(row, inputType, filename, index)
  );
  const previewChecksum = await checksumFor(rawText, inputType, filename);

  return {
    parser_version: PARSER_VERSION,
    preview_checksum: previewChecksum,
    destination: {
      watchlist_name: WATCHLIST_NAME,
    },
    counts: countsForRows(parsedRows),
    rows: parsedRows,
  };
}

export async function checksumFor(
  rawText: string,
  inputType: ReferenceImportInputType,
  filename?: string | null,
): Promise<string> {
  const normalizedPayload = JSON.stringify({
    parser_version: PARSER_VERSION,
    input_type: inputType,
    filename: filename?.trim() || null,
    raw_text: rawText.replace(/\r\n/g, "\n").trim(),
  });
  const bytes = new TextEncoder().encode(normalizedPayload);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function countsForRows(rows: ReferenceImportRow[]) {
  const totalRows = rows.length;
  const duplicates =
    rows.filter((row) => row.preview_state === "duplicate").length;
  const invalid = rows.filter((row) => row.preview_state === "invalid").length;
  const needsReview =
    rows.filter((row) => row.preview_state === "needs_review").length +
    rows.filter((row) => row.inferred_account && row.preview_state === "clean")
      .length;
  const cleanAccounts =
    rows.filter((row) =>
      row.preview_state === "clean" && row.classification === "account"
    ).length;
  const cleanReels =
    rows.filter((row) =>
      row.preview_state === "clean" && row.classification === "reel"
    ).length;
  const cleanAudio =
    rows.filter((row) =>
      row.preview_state === "clean" && row.classification === "audio"
    ).length;

  return {
    total_rows: totalRows,
    clean_accounts: cleanAccounts,
    clean_reels: cleanReels,
    clean_audio: cleanAudio,
    needs_review: needsReview,
    duplicates,
    invalid,
    importable: totalRows - duplicates - invalid,
  };
}

function inputRows(
  rawText: string,
  inputType: ReferenceImportInputType,
): ParsedInputRow[] {
  return inputType === "csv"
    ? parsedRowsFromCSV(rawText)
    : parsedRowsFromPaste(rawText);
}

function classifyInputRow(
  inputRow: ParsedInputRow,
  inputType: ReferenceImportInputType,
  filename: string | null | undefined,
  rowIndex: number,
): ReferenceImportRow {
  const values = inputRow.values.map((value) => value.trim()).filter(Boolean);
  const rawInput = inputRow.rawInput.trim();
  const joined = values.join(" ");
  const urls = extractURLs(joined);
  const baseProvenance = provenanceFor(inputRow, inputType, filename);

  for (const url of urls) {
    const urlClassification = classifyURL(url);
    if (urlClassification.kind === "story") {
      return {
        client_row_id: `line-${inputRow.lineNumber}`,
        line_number: inputRow.lineNumber,
        raw_input: rawInput,
        type_chip: "Unknown",
        classification: "unknown",
        source_type: "import_row",
        status_on_confirm: "needs_review",
        title: "Instagram story URL",
        url: urlClassification.url,
        notes: null,
        preview_state: "invalid",
        duplicate_reason: null,
        invalid_reason: urlClassification.reason,
        provenance: {
          ...baseProvenance,
          classification: "invalid_story",
          confidence: 1,
          invalid_reason: urlClassification.reason,
        },
      };
    }
  }

  if (urls.length > 0) {
    const primaryURL = urls[0];
    const urlClassification = classifyURL(primaryURL);
    const explicitHandle = findBestHandle(inputRow, joined);

    switch (urlClassification.kind) {
      case "profile":
        return accountRow(inputRow, inputType, filename, rowIndex, {
          normalizedHandle: urlClassification.normalizedHandle,
          handle: urlClassification.handle,
          title: titleFromColumns(inputRow) ?? urlClassification.handle,
          url: urlClassification.url,
          confidence: 0.95,
          extraProvenance: { private_like_url: urlClassification.privateLike },
        });

      case "reel":
      case "post": {
        const normalizedInferredHandle = explicitHandle ??
          urlClassification.inferredHandle ?? null;
        const inferred = normalizedInferredHandle
          ? {
            handle: displayHandle(normalizedInferredHandle),
            normalized_handle: normalizedInferredHandle,
            title: displayHandle(normalizedInferredHandle),
            conflict: Boolean(
              explicitHandle &&
                urlClassification.inferredHandle &&
                explicitHandle !== urlClassification.inferredHandle,
            ),
          }
          : null;

        return {
          client_row_id: `line-${inputRow.lineNumber}`,
          line_number: inputRow.lineNumber,
          raw_input: rawInput,
          type_chip: "Reel",
          classification: "reel",
          source_type: "reel_link",
          status_on_confirm: "confirmed",
          handle: null,
          normalized_handle: null,
          canonical_source_key: urlClassification.canonicalKey,
          title: titleFromColumns(inputRow) ??
            (urlClassification.kind === "post"
              ? "Instagram post reference"
              : "Instagram reel reference"),
          url: urlClassification.url,
          notes: notesFromColumns(inputRow),
          preview_state: "clean",
          duplicate_reason: null,
          invalid_reason: null,
          provenance: {
            ...baseProvenance,
            classification: urlClassification.kind,
            confidence: 0.92,
            canonical_source_key: urlClassification.canonicalKey,
            inferred_handle: inferred?.normalized_handle ?? null,
            account_conflict: inferred?.conflict ?? false,
          },
          inferred_account: inferred,
        };
      }

      case "audio":
        return {
          client_row_id: `line-${inputRow.lineNumber}`,
          line_number: inputRow.lineNumber,
          raw_input: rawInput,
          type_chip: "Audio",
          classification: "audio",
          source_type: "audio_link",
          status_on_confirm: "confirmed",
          canonical_source_key: urlClassification.canonicalKey,
          title: titleFromColumns(inputRow) ?? "Instagram audio reference",
          url: urlClassification.url,
          notes: notesFromColumns(inputRow),
          preview_state: "clean",
          duplicate_reason: null,
          invalid_reason: null,
          provenance: {
            ...baseProvenance,
            classification: "audio",
            confidence: 0.88,
            canonical_source_key: urlClassification.canonicalKey,
          },
        };

      case "non_instagram":
      case "malformed_instagram":
        return unknownRow(inputRow, inputType, filename, {
          title: urlClassification.kind === "non_instagram"
            ? "Non-Instagram reference"
            : "Instagram URL needs review",
          url: urlClassification.url,
          confidence: 0.5,
          classification: urlClassification.kind,
          canonicalSourceKey: urlClassification.kind === "non_instagram"
            ? urlClassification.canonicalKey
            : null,
        });
    }
  }

  const normalizedHandle = findBestHandle(inputRow, joined);
  if (normalizedHandle) {
    return accountRow(inputRow, inputType, filename, rowIndex, {
      normalizedHandle,
      handle: displayHandle(normalizedHandle),
      title: titleFromColumns(inputRow) ?? displayHandle(normalizedHandle),
      url: null,
      confidence: 0.9,
      extraProvenance: {},
    });
  }

  return unknownRow(inputRow, inputType, filename, {
    title: "Needs your call",
    url: null,
    confidence: 0.4,
    classification: "unknown",
    canonicalSourceKey: null,
  });
}

function accountRow(
  inputRow: ParsedInputRow,
  inputType: ReferenceImportInputType,
  filename: string | null | undefined,
  rowIndex: number,
  options: {
    normalizedHandle: string;
    handle: string;
    title: string;
    url: string | null;
    confidence: number;
    extraProvenance: Record<string, unknown>;
  },
): ReferenceImportRow {
  return {
    client_row_id: `line-${inputRow.lineNumber}`,
    line_number: inputRow.lineNumber,
    raw_input: inputRow.rawInput.trim(),
    type_chip: "Account",
    classification: "account",
    status_on_confirm: "active",
    handle: options.handle,
    normalized_handle: options.normalizedHandle,
    canonical_source_key: null,
    title: options.title,
    url: options.url,
    notes: notesFromColumns(inputRow),
    region: stringColumn(inputRow, "region"),
    tags: tagsFromColumns(inputRow),
    preview_state: "clean",
    duplicate_reason: null,
    invalid_reason: null,
    provenance: {
      ...provenanceFor(inputRow, inputType, filename),
      classification: "account",
      confidence: options.confidence,
      normalized_handle: options.normalizedHandle,
      row_index: rowIndex,
      ...options.extraProvenance,
    },
  };
}

function unknownRow(
  inputRow: ParsedInputRow,
  inputType: ReferenceImportInputType,
  filename: string | null | undefined,
  options: {
    title: string;
    url: string | null;
    confidence: number;
    classification: string;
    canonicalSourceKey: string | null;
  },
): ReferenceImportRow {
  return {
    client_row_id: `line-${inputRow.lineNumber}`,
    line_number: inputRow.lineNumber,
    raw_input: inputRow.rawInput.trim(),
    type_chip: "Unknown",
    classification: "unknown",
    source_type: "import_row",
    status_on_confirm: "needs_review",
    title: titleFromColumns(inputRow) ?? options.title,
    url: options.url,
    notes: notesFromColumns(inputRow) ?? inputRow.rawInput.trim(),
    canonical_source_key: options.canonicalSourceKey,
    preview_state: "needs_review",
    duplicate_reason: null,
    invalid_reason: null,
    provenance: {
      ...provenanceFor(inputRow, inputType, filename),
      classification: options.classification,
      confidence: options.confidence,
      canonical_source_key: options.canonicalSourceKey,
    },
  };
}

function findBestHandle(
  inputRow: ParsedInputRow,
  joined: string,
): string | null {
  const columnHandle = stringColumn(inputRow, "handle");
  if (columnHandle) {
    const normalized = normalizeInstagramHandle(columnHandle);
    if (normalized) return normalized;
  }

  for (const value of inputRow.values) {
    const trimmed = value.trim();
    if (trimmed.includes(" ")) continue;
    const normalized = normalizeInstagramHandle(trimmed);
    if (normalized) return normalized;
  }

  return extractHandleTokens(joined)[0] ?? null;
}

function provenanceFor(
  inputRow: ParsedInputRow,
  inputType: ReferenceImportInputType,
  filename: string | null | undefined,
): Record<string, unknown> {
  const provenance: Record<string, unknown> = {
    raw_input: inputRow.rawInput.trim(),
    import_source: inputType,
    filename: filename?.trim() || null,
    parser_version: PARSER_VERSION,
  };

  if (inputRow.columns) {
    provenance.csv_columns = inputRow.columns;
  }

  if (
    inputRow.unknownColumns && Object.keys(inputRow.unknownColumns).length > 0
  ) {
    provenance.unknown_columns = inputRow.unknownColumns;
  }

  return provenance;
}

function titleFromColumns(inputRow: ParsedInputRow): string | null {
  return stringColumn(inputRow, "display_name");
}

function notesFromColumns(inputRow: ParsedInputRow): string | null {
  return stringColumn(inputRow, "notes");
}

function tagsFromColumns(inputRow: ParsedInputRow): string[] {
  const tags = stringColumn(inputRow, "tags");
  if (!tags) return [];

  return tags
    .split(/[|,;]/)
    .map((tag) => tag.trim())
    .filter(Boolean)
    .slice(0, 12);
}

function stringColumn(inputRow: ParsedInputRow, key: string): string | null {
  const value = inputRow.columns?.[key]?.trim();
  return value && value.length > 0 ? value : null;
}
