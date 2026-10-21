import { jsonResponse, SupabaseAdminClient } from "../_shared/device-auth.ts";
import { generationPersistFailure } from "./generation-persistence.ts";
import type { GenerationInputSnapshot } from "./generation.ts";
import type { GenerationIntent } from "./generation-idempotency.ts";

export type GenerationRunRecord = {
  id: string;
  replayed?: boolean;
  [key: string]: unknown;
};

export type DayGenerationRunStartPrepared = {
  generationIntent?: GenerationIntent;
  session: { workspaceID: string };
  request: {
    creator_id: string;
    weekly_plan_id: string;
    scheduled_date: string;
  };
  plan: { weekly_setup_id?: string | null };
  targetCard?: { id: string } | null;
  model: string;
  inputSnapshot: GenerationInputSnapshot;
};

export async function createDayGenerationRun(
  admin: SupabaseAdminClient,
  prepared: DayGenerationRunStartPrepared,
  memberID: string,
): Promise<{ run: GenerationRunRecord } | { response: Response }> {
  const intent = prepared.generationIntent;
  const { data, error } = await (admin as SupabaseAdminClient & {
    rpc: (
      name: string,
      args: Record<string, unknown>,
    ) => Promise<{ data: Record<string, unknown> | null; error: unknown }>;
  }).rpc(intent?.replace ? "replace_day" : "start_day_generation", {
    payload: {
      workspace_id: prepared.session.workspaceID,
      creator_id: prepared.request.creator_id,
      weekly_plan_id: prepared.request.weekly_plan_id,
      scheduled_date: prepared.request.scheduled_date,
      member_id: memberID,
      model: prepared.model,
      input_snapshot: prepared.inputSnapshot,
      idempotency_key: intent?.idempotencyKey ?? crypto.randomUUID(),
      request_identity: intent?.identity ?? prepared.request,
      daily_card_id: intent?.expectedRevisionID,
      piece_id: intent?.pieceID,
      preserve_manual_edits:
        (prepared.request as Record<string, unknown>).preserve_manual_edits,
    },
  });
  if (typeof data?.error === "string") {
    return {
      response: jsonResponse(
        { error: data.error },
        typeof data.status === "number" ? data.status : 500,
      ),
    };
  }
  if (error || !data || typeof data.id !== "string") {
    return generationPersistFailure("create_day_generation_run", error);
  }
  return { run: data as GenerationRunRecord };
}
