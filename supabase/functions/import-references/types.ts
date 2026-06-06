export const PARSER_VERSION = "reference-import-v1";
export const WATCHLIST_NAME = "Inspiration";
export const MAX_IMPORT_ROWS = 500;

export type ReferenceImportInputType = "paste" | "csv";
export type ReferenceImportMode = "preview" | "confirm";
export type ReferenceImportClassification =
  | "account"
  | "reel"
  | "audio"
  | "unknown";
export type ReferenceImportPreviewState =
  | "clean"
  | "needs_review"
  | "duplicate"
  | "invalid";
export type ReferenceImportTypeChip = "Account" | "Reel" | "Audio" | "Unknown";
export type SourceReferenceType = "reel_link" | "audio_link" | "import_row";

export type ReferenceImportRow = {
  client_row_id: string;
  line_number: number;
  raw_input: string;
  type_chip: ReferenceImportTypeChip;
  classification: ReferenceImportClassification;
  source_type?: SourceReferenceType;
  status_on_confirm: "active" | "confirmed" | "needs_review";
  handle?: string | null;
  normalized_handle?: string | null;
  canonical_source_key?: string | null;
  title: string;
  url?: string | null;
  notes?: string | null;
  region?: string | null;
  tags?: string[];
  preview_state: ReferenceImportPreviewState;
  duplicate_reason?: string | null;
  invalid_reason?: string | null;
  provenance: Record<string, unknown>;
  inferred_account?: InferredAccount | null;
};

export type InferredAccount = {
  handle: string;
  normalized_handle: string;
  title: string;
  conflict?: boolean;
};

export type ReferenceImportCounts = {
  total_rows: number;
  clean_accounts: number;
  clean_reels: number;
  clean_audio: number;
  needs_review: number;
  duplicates: number;
  invalid: number;
  importable: number;
};

export type ReferenceImportPreview = {
  parser_version: string;
  preview_checksum: string;
  destination: {
    watchlist_name: string;
  };
  counts: ReferenceImportCounts;
  rows: ReferenceImportRow[];
};

export type ParsedInputRow = {
  lineNumber: number;
  rawInput: string;
  values: string[];
  columns?: Record<string, string>;
  unknownColumns?: Record<string, string>;
};

export class RowLimitError extends Error {
  readonly rowCount: number;

  constructor(rowCount: number) {
    super(`Import has ${rowCount} rows. The limit is ${MAX_IMPORT_ROWS}.`);
    this.name = "RowLimitError";
    this.rowCount = rowCount;
  }
}
