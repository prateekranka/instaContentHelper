import { jsonResponse, SupabaseAdminClient } from "../_shared/device-auth.ts";
import {
  GenerateWeekValidationError,
  isUUID,
  normalizeGenerateDayRequest,
  normalizeRegenerateDayRequest,
} from "./generation.ts";
import {
  markGenerationRunFailed,
  readGenerationRunStatus,
} from "./generation-run-store.ts";

export type GenerationIntent = {
  idempotencyKey: string;
  identity: Record<string, unknown>;
  replace: boolean;
  expectedRevisionID?: string;
  pieceID?: string;
};

export function generationIntent(
  body: Record<string, unknown>,
): GenerationIntent {
  if (
    body.idempotency_key !== undefined &&
    (typeof body.idempotency_key !== "string" ||
      body.idempotency_key.trim().length === 0 ||
      body.idempotency_key.trim().length > 200)
  ) {
    throw new Error("invalid_idempotency_key");
  }
  if (
    body.daily_card_id !== undefined &&
    (typeof body.daily_card_id !== "string" || !isUUID(body.daily_card_id))
  ) {
    throw new GenerateWeekValidationError(
      "invalid_generation_payload",
      "daily_card_id must be a UUID.",
    );
  }
  if (
    body.piece_id !== undefined &&
    (typeof body.piece_id !== "string" || !isUUID(body.piece_id))
  ) {
    throw new GenerateWeekValidationError(
      "invalid_generation_payload",
      "piece_id must be a UUID.",
    );
  }
  const replace = body.action === "replace_day";
  const normalized = body.action === "regenerate_day"
    ? normalizeRegenerateDayRequest(body)
    : normalizeGenerateDayRequest({ ...body, action: "generate_day" });
  const { response_mode: _responseMode, ...identity } = normalized;
  return {
    idempotencyKey: typeof body.idempotency_key === "string"
      ? body.idempotency_key.trim()
      : crypto.randomUUID(),
    identity: JSON.parse(
      canonicalJSON({
        ...identity,
        action: body.action,
        daily_card_id: body.daily_card_id ?? null,
      }),
    ),
    replace,
    ...(typeof body.piece_id === "string"
      ? { pieceID: body.piece_id.toLowerCase() }
      : {}),
    expectedRevisionID: typeof body.daily_card_id === "string"
      ? body.daily_card_id
      : undefined,
  };
}

export function canonicalJSON(value: unknown): string {
  if (Array.isArray(value)) {
    return JSON.stringify(value.map((item) => JSON.parse(canonicalJSON(item))));
  }
  if (value && typeof value === "object") {
    return JSON.stringify(
      Object.fromEntries(
        Object.entries(value).filter(([, v]) => v !== undefined)
          .sort(([a], [b]) => a.localeCompare(b)).map((
            [k, v],
          ) => [k, JSON.parse(canonicalJSON(v))]),
      ),
    );
  }
  return JSON.stringify(value);
}

export async function readGenerationReplay(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  intent: GenerationIntent,
): Promise<Response | null> {
  const { data, error } = await admin.from("weekly_generation_runs")
    .select("*").eq("workspace_id", workspaceID).eq("creator_id", creatorID)
    .eq("idempotency_key", intent.idempotencyKey).maybeSingle();
  if (error) return jsonResponse({ error: "generation_lookup_failed" }, 500);
  if (!data) return null;
  return await generationReplayResponse(
    admin,
    data as Record<string, unknown>,
    intent,
  );
}

export async function generationReplayResponse(
  admin: SupabaseAdminClient,
  run: Record<string, unknown>,
  intent: GenerationIntent,
): Promise<Response> {
  if (canonicalJSON(run.request_identity) !== canonicalJSON(intent.identity)) {
    return jsonResponse({ error: "idempotency_key_conflict" }, 409);
  }
  if (
    run.status === "running" && typeof run.updated_at === "string" &&
    Date.parse(run.updated_at) < Date.now() - 600_000
  ) {
    await markGenerationRunFailed(admin, String(run.id), "generation_stale");
    const latest = await readGenerationRunStatus(
      admin,
      String(run.id),
      String(run.workspace_id),
    );
    if (latest.error || !latest.data) {
      return jsonResponse({ error: "generation_lookup_failed" }, 500);
    }
    run = { ...run, ...latest.data };
  }
  if (run.status === "completed") {
    return jsonResponse({
      ...(run.output_snapshot as Record<string, unknown>),
      piece_id: run.piece_id,
      replaced_daily_card_id: run.replaced_daily_card_id,
      idempotency_key: intent.idempotencyKey,
      replayed: true,
    });
  }
  return jsonResponse({
    generation_id: run.id,
    piece_id: run.piece_id,
    weekly_plan_id: run.weekly_plan_id,
    target_scheduled_date: run.target_scheduled_date,
    status: run.status,
    error: run.status === "failed" ? run.error_code : undefined,
    idempotency_key: intent.idempotencyKey,
    replayed: true,
    poll_after_seconds: run.status === "running" ? 2 : null,
  }, run.status === "running" ? 202 : 200);
}
