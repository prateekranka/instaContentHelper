import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  CONTENT_CREATOR_ROLES,
  corsHeaders,
  jsonResponse,
  SupabaseAdminClient,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";

type HandlerDependencies = {
  createAdminClient?: (
    supabaseURL: string,
    serviceRoleKey: string,
  ) => SupabaseAdminClient;
  env?: { get: (name: string) => string | undefined };
};

type PieceRow = {
  id: string;
  scheduled_date: string;
  document: Record<string, unknown>;
  revision: number;
  sync_sequence: number;
  updated_at: string;
};

type PushedPiece = {
  id: string;
  scheduled_date: string;
  document: Record<string, unknown>;
  base_revision: number | null;
  client_updated_at: string | null;
};

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_PUSH_PIECES = 50;
const MAX_PULL_PIECES = 500;
const MAX_DOCUMENT_BYTES = 512 * 1024;
const ROW_COLUMNS = "id, scheduled_date, document, revision, sync_sequence, updated_at";

export async function handleSyncPiecesRequest(
  request: Request,
  dependencies: HandlerDependencies = {},
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const env = dependencies.env ?? Deno.env;
  const supabaseURL = env.get("SUPABASE_URL");
  const serviceRoleKey = env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) {
    return jsonResponse({ error: "missing_function_secrets" }, 500);
  }

  const admin = dependencies.createAdminClient
    ? dependencies.createAdminClient(supabaseURL, serviceRoleKey)
    : createClient(supabaseURL, serviceRoleKey, {
      auth: { persistSession: false },
    }) as unknown as SupabaseAdminClient;

  const authResult = await verifyDeviceSession(request, admin, [
    ...CONTENT_CREATOR_ROLES,
  ]);
  if ("response" in authResult) {
    return authResult.response;
  }
  const { session } = authResult;

  let body: Record<string, unknown>;
  try {
    const parsed = await request.json();
    if (!isRecord(parsed)) throw new Error("not_object");
    body = parsed;
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const creatorID = stringValue(body.creator_id);
  if (!creatorID || !UUID_PATTERN.test(creatorID)) {
    return jsonResponse({ error: "invalid_sync_pieces_payload" }, 400);
  }
  const creatorResponse = await assertCreator(
    admin,
    session.workspaceID,
    creatorID,
  );
  if (creatorResponse) {
    return creatorResponse;
  }

  switch (body.action) {
    case "pull":
      return await pull(admin, session.workspaceID, creatorID, body);
    case "push":
      return await push(
        admin,
        session.workspaceID,
        creatorID,
        session.memberID,
        body,
      );
    default:
      return jsonResponse({ error: "invalid_sync_pieces_payload" }, 400);
  }
}

async function pull(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  body: Record<string, unknown>,
): Promise<Response> {
  const since = typeof body.since_sequence === "number" &&
      Number.isInteger(body.since_sequence) && body.since_sequence >= 0
    ? body.since_sequence
    : 0;

  const { data, error } = await admin
    .from("content_pieces")
    .select(ROW_COLUMNS)
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .gt("sync_sequence", since)
    .order("sync_sequence", { ascending: true })
    .limit(MAX_PULL_PIECES);
  if (error) {
    return jsonResponse({ error: "sync_pieces_read_failed" }, 500);
  }

  const rows = (data ?? []) as PieceRow[];
  const cursor = rows.reduce(
    (max, row) => Math.max(max, Number(row.sync_sequence) || 0),
    since,
  );
  return jsonResponse({
    pieces: rows.map(remotePiece),
    cursor,
    has_more: rows.length === MAX_PULL_PIECES,
  });
}

async function push(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  memberID: string,
  body: Record<string, unknown>,
): Promise<Response> {
  if (!Array.isArray(body.pieces) || body.pieces.length > MAX_PUSH_PIECES) {
    return jsonResponse({ error: "invalid_sync_pieces_payload" }, 400);
  }
  const pieces: PushedPiece[] = [];
  for (const raw of body.pieces) {
    const piece = normalizePushedPiece(raw);
    if (!piece) {
      return jsonResponse({ error: "invalid_sync_pieces_payload" }, 400);
    }
    pieces.push(piece);
  }

  const accepted: Record<string, unknown>[] = [];
  const conflicts: Record<string, unknown>[] = [];

  for (const piece of pieces) {
    const values = {
      scheduled_date: piece.scheduled_date,
      document: piece.document,
      updated_by_member_id: memberID,
      client_updated_at: piece.client_updated_at,
    };

    if (piece.base_revision === null) {
      const { data, error } = await admin
        .from("content_pieces")
        .insert({
          id: piece.id,
          workspace_id: workspaceID,
          creator_id: creatorID,
          revision: 1,
          ...values,
        })
        .select(ROW_COLUMNS)
        .maybeSingle();
      if (!error && data) {
        accepted.push(acceptedPiece(data as PieceRow));
        continue;
      }
      if (error && !isUniqueViolation(error)) {
        return jsonResponse({ error: "sync_pieces_write_failed" }, 500);
      }
    } else {
      const { data, error } = await admin
        .from("content_pieces")
        .update({ ...values, revision: piece.base_revision + 1 })
        .eq("id", piece.id)
        .eq("workspace_id", workspaceID)
        .eq("creator_id", creatorID)
        .eq("revision", piece.base_revision)
        .select(ROW_COLUMNS)
        .maybeSingle();
      if (error) {
        return jsonResponse({ error: "sync_pieces_write_failed" }, 500);
      }
      if (data) {
        accepted.push(acceptedPiece(data as PieceRow));
        continue;
      }
    }

    const { data: current, error: currentError } = await admin
      .from("content_pieces")
      .select(ROW_COLUMNS)
      .eq("id", piece.id)
      .eq("workspace_id", workspaceID)
      .eq("creator_id", creatorID)
      .maybeSingle();
    if (currentError) {
      return jsonResponse({ error: "sync_pieces_read_failed" }, 500);
    }
    if (!current) {
      return jsonResponse({ error: "sync_piece_not_found", id: piece.id }, 404);
    }
    conflicts.push(remotePiece(current as PieceRow));
  }

  return jsonResponse({ accepted, conflicts });
}

function normalizePushedPiece(raw: unknown): PushedPiece | null {
  if (!isRecord(raw)) return null;
  const id = stringValue(raw.id);
  const scheduledDate = stringValue(raw.scheduled_date);
  if (!id || !UUID_PATTERN.test(id)) return null;
  if (!scheduledDate || !DATE_PATTERN.test(scheduledDate)) return null;
  if (!isRecord(raw.document)) return null;
  if (stringValue(raw.document.id)?.toLowerCase() !== id.toLowerCase()) {
    return null;
  }
  if (JSON.stringify(raw.document).length > MAX_DOCUMENT_BYTES) return null;

  const baseRevision = raw.base_revision;
  if (
    baseRevision !== null && baseRevision !== undefined &&
    !(typeof baseRevision === "number" && Number.isInteger(baseRevision) &&
      baseRevision >= 1)
  ) {
    return null;
  }

  const clientUpdatedAt = stringValue(raw.client_updated_at);
  return {
    id,
    scheduled_date: scheduledDate,
    document: raw.document,
    base_revision: typeof baseRevision === "number" ? baseRevision : null,
    client_updated_at: clientUpdatedAt && !Number.isNaN(Date.parse(clientUpdatedAt))
      ? clientUpdatedAt
      : null,
  };
}

function remotePiece(row: PieceRow): Record<string, unknown> {
  return {
    id: row.id,
    scheduled_date: row.scheduled_date,
    document: row.document,
    revision: Number(row.revision),
    sync_sequence: Number(row.sync_sequence),
    updated_at: row.updated_at,
  };
}

function acceptedPiece(row: PieceRow): Record<string, unknown> {
  return {
    id: row.id,
    revision: Number(row.revision),
    sync_sequence: Number(row.sync_sequence),
    updated_at: row.updated_at,
  };
}

function isUniqueViolation(error: unknown): boolean {
  return isRecord(error) && error.code === "23505";
}

async function assertCreator(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
): Promise<Response | null> {
  const { data: creator, error } = await admin
    .from("creators")
    .select("id")
    .eq("id", creatorID)
    .eq("workspace_id", workspaceID)
    .eq("status", "active")
    .maybeSingle();
  if (error) {
    return jsonResponse({ error: "creator_lookup_failed" }, 500);
  }
  if (!creator) {
    return jsonResponse({ error: "creator_not_found" }, 404);
  }
  return null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

if (import.meta.main) {
  Deno.serve((request) => handleSyncPiecesRequest(request));
}
