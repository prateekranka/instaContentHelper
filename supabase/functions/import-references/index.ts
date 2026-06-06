import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  corsHeaders,
  jsonResponse,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";
import { countsForRows, parseReferenceImport } from "./parser.ts";
import {
  ReferenceImportInputType,
  ReferenceImportMode,
  ReferenceImportPreview,
  ReferenceImportRow,
  RowLimitError,
} from "./types.ts";

type ImportReferencesRequest = {
  mode?: ReferenceImportMode;
  creator_id?: string;
  input_type?: ReferenceImportInputType;
  raw_text?: string;
  filename?: string | null;
  preview_checksum?: string | null;
};

Deno.serve(async (request) => {
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
  });

  const authResult = await verifyDeviceSession(request, admin, [
    "owner",
    "editor",
  ]);
  if ("response" in authResult) {
    return authResult.response;
  }

  let body: ImportReferencesRequest;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const mode = body.mode;
  const creatorID = body.creator_id?.trim();
  const inputType = body.input_type;
  const rawText = body.raw_text ?? "";
  const filename = body.filename ?? null;

  if (mode !== "preview" && mode !== "confirm") {
    return jsonResponse({ error: "invalid_mode" }, 400);
  }

  if (inputType !== "paste" && inputType !== "csv") {
    return jsonResponse({ error: "invalid_input_type" }, 400);
  }

  if (!creatorID || !rawText.trim()) {
    return jsonResponse({ error: "missing_raw_text" }, 400);
  }

  const { session } = authResult;
  const { data: creator, error: creatorError } = await admin
    .from("creators")
    .select("id")
    .eq("id", creatorID)
    .eq("workspace_id", session.workspaceID)
    .eq("status", "active")
    .maybeSingle();

  if (creatorError) {
    return jsonResponse({ error: "creator_lookup_failed" }, 500);
  }

  if (!creator) {
    return jsonResponse({ error: "creator_not_found" }, 404);
  }

  let preview: ReferenceImportPreview;
  try {
    preview = await parseReferenceImport(rawText, inputType, filename);
  } catch (error) {
    if (error instanceof RowLimitError) {
      return jsonResponse({
        error: "row_limit_exceeded",
        row_count: error.rowCount,
      }, 400);
    }
    return jsonResponse({ error: "import_parse_failed" }, 400);
  }

  let enrichedPreview: ReferenceImportPreview;
  try {
    enrichedPreview = await withDuplicateInformation(
      preview,
      admin,
      session.workspaceID,
      creatorID,
    );
  } catch (error) {
    return jsonResponse({
      error: "duplicate_lookup_failed",
      details: error instanceof Error ? error.message : String(error),
    }, 500);
  }

  if (mode === "preview") {
    return jsonResponse(enrichedPreview);
  }

  if (
    body.preview_checksum &&
    body.preview_checksum !== enrichedPreview.preview_checksum
  ) {
    return jsonResponse({
      error: "checksum_mismatch",
      message: "Import changed. Preview again before confirming.",
    }, 409);
  }

  const { data, error } = await admin.rpc("confirm_reference_import", {
    payload: {
      workspace_id: session.workspaceID,
      creator_id: creatorID,
      member_id: session.memberID,
      input_type: inputType,
      filename,
      preview_checksum: enrichedPreview.preview_checksum,
      parser_version: enrichedPreview.parser_version,
      rows: enrichedPreview.rows,
    },
  });

  if (error) {
    return jsonResponse({
      error: "import_failed_nothing_saved",
      details: error.message,
    }, 500);
  }

  return jsonResponse(data as Record<string, unknown>);
});

async function withDuplicateInformation(
  preview: ReferenceImportPreview,
  admin: any,
  workspaceID: string,
  creatorID: string,
): Promise<ReferenceImportPreview> {
  const accountKeys = [
    ...new Set(
      preview.rows
        .map((row) => row.normalized_handle)
        .filter((value): value is string => Boolean(value)),
    ),
  ];
  const sourceRows = preview.rows.filter((row) =>
    row.canonical_source_key && row.source_type
  );
  const sourceKeys = [
    ...new Set(sourceRows.map((row) => row.canonical_source_key as string)),
  ];

  const accountStatusByKey = new Map<string, string>();
  const sourceStatusByKey = new Map<string, string>();

  if (accountKeys.length > 0) {
    const { data, error } = await admin
      .from("benchmark_creators")
      .select("normalized_handle,status")
      .eq("workspace_id", workspaceID)
      .eq("creator_id", creatorID)
      .eq("platform", "instagram")
      .in("normalized_handle", accountKeys);

    if (error) {
      throw error;
    }

    for (const row of data ?? []) {
      accountStatusByKey.set(row.normalized_handle, row.status);
    }
  }

  if (sourceKeys.length > 0) {
    const { data, error } = await admin
      .from("source_references")
      .select("source_type,canonical_source_key,status")
      .eq("workspace_id", workspaceID)
      .eq("creator_id", creatorID)
      .in("canonical_source_key", sourceKeys);

    if (error) {
      throw error;
    }

    for (const row of data ?? []) {
      sourceStatusByKey.set(
        `${row.source_type}:${row.canonical_source_key}`,
        row.status,
      );
    }
  }

  const seenAccountKeys = new Set<string>();
  const seenSourceKeys = new Set<string>();
  const rows = preview.rows.map((row) => {
    const marked = { ...row };

    if (marked.preview_state === "invalid") {
      return marked;
    }

    if (marked.classification === "account" && marked.normalized_handle) {
      const existingStatus = accountStatusByKey.get(marked.normalized_handle);
      if (existingStatus) {
        return duplicateRow(marked, duplicateReasonForAccount(existingStatus));
      }
      if (seenAccountKeys.has(marked.normalized_handle)) {
        return duplicateRow(marked, "Duplicate in this import");
      }
      seenAccountKeys.add(marked.normalized_handle);
      return marked;
    }

    if (marked.canonical_source_key && marked.source_type) {
      const sourceKey = `${marked.source_type}:${marked.canonical_source_key}`;
      const existingStatus = sourceStatusByKey.get(sourceKey);
      if (existingStatus) {
        return duplicateRow(marked, duplicateReasonForSource(existingStatus));
      }
      if (seenSourceKeys.has(sourceKey)) {
        return duplicateRow(marked, "Duplicate in this import");
      }
      seenSourceKeys.add(sourceKey);
    }

    return marked;
  });

  return {
    ...preview,
    counts: countsForRows(rows),
    rows,
  };
}

function duplicateRow(
  row: ReferenceImportRow,
  reason: string,
): ReferenceImportRow {
  return {
    ...row,
    preview_state: "duplicate",
    duplicate_reason: reason,
    provenance: {
      ...row.provenance,
      duplicate_reason: reason,
    },
  };
}

function duplicateReasonForAccount(status: string): string {
  switch (status) {
    case "active":
      return "Already active";
    case "candidate":
      return "Already candidate";
    case "poor_fit":
      return "Previously marked poor fit";
    case "archived":
      return "Previously archived";
    default:
      return "Already imported";
  }
}

function duplicateReasonForSource(status: string): string {
  switch (status) {
    case "confirmed":
      return "Already confirmed";
    case "dismissed":
      return "Previously dismissed";
    case "needs_review":
      return "Already needs review";
    case "archived":
      return "Previously archived";
    default:
      return "Already imported";
  }
}
