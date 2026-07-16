import { SupabaseAdminClient } from "../_shared/device-auth.ts";
import { generationPersistFailure } from "./generation-persistence.ts";
import type { GenerationInputSnapshot } from "./generation.ts";
import { insertDayGenerationRun } from "./generation-run-store.ts";

const PROMPT_VERSION = "creator-weekly-generation-v1";

export type GenerationRunRecord = {
  id: string;
};

export type DayGenerationRunStartPrepared = {
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
  const { data, error } = await insertDayGenerationRun(admin, {
    workspace_id: prepared.session.workspaceID,
    creator_id: prepared.request.creator_id,
    weekly_setup_id: prepared.plan.weekly_setup_id ?? null,
    weekly_plan_id: prepared.request.weekly_plan_id,
    requested_by_member_id: memberID,
    status: "running",
    model: prepared.model,
    prompt_version: PROMPT_VERSION,
    generation_scope: "day",
    target_daily_card_id: prepared.targetCard?.id ?? null,
    target_scheduled_date: prepared.request.scheduled_date,
    input_snapshot: prepared.inputSnapshot,
    warnings: [],
    assumptions: [],
  });
  if (error || !data) {
    return generationPersistFailure("create_day_generation_run", error);
  }
  return { run: data as GenerationRunRecord };
}
