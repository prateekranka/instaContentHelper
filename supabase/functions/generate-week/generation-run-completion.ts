import { SupabaseAdminClient } from "../_shared/device-auth.ts";
import { generationPersistFailure } from "./generation-persistence.ts";
import type {
  GenerateWeekDraftResponse,
  RegenerateDayDraftResponse,
} from "./generation-run-snapshot.ts";
import {
  completeDayGenerationRun as completeDayGenerationRunStore,
  completeFullWeekGenerationRun,
  completeGenerationRunMinimal,
  markGenerationRunFailed as markGenerationRunFailedStore,
} from "./generation-run-store.ts";

export async function completeDayGenerationRun(
  admin: SupabaseAdminClient,
  generationID: string,
  payload: RegenerateDayDraftResponse,
  completedAt: string,
): Promise<{ ok: true } | { response: Response }> {
  const { error } = await completeDayGenerationRunStore(
    admin,
    generationID,
    {
      output_snapshot: payload,
      warnings: payload.warnings,
      assumptions: payload.assumptions,
      completed_at: completedAt,
    },
  );
  if (error) {
    const fallback = await completeGenerationRunWithoutSnapshot(
      admin,
      generationID,
      undefined,
      completedAt,
      "complete_day_generation_run",
      error,
    );
    if ("response" in fallback) {
      return fallback;
    }
  }
  return { ok: true };
}

export async function completeGenerationRun(
  admin: SupabaseAdminClient,
  generationID: string,
  weeklyPlanID: string,
  payload: GenerateWeekDraftResponse,
  completedAt: string,
): Promise<{ ok: true } | { response: Response }> {
  const { error } = await completeFullWeekGenerationRun(
    admin,
    generationID,
    {
      weekly_plan_id: weeklyPlanID,
      output_snapshot: payload,
      warnings: payload.warnings,
      assumptions: payload.assumptions,
      completed_at: completedAt,
    },
  );

  if (error) {
    const fallback = await completeGenerationRunWithoutSnapshot(
      admin,
      generationID,
      weeklyPlanID,
      completedAt,
      "complete_generation_run",
      error,
    );
    if ("response" in fallback) {
      return fallback;
    }
  }

  return { ok: true };
}

async function completeGenerationRunWithoutSnapshot(
  admin: SupabaseAdminClient,
  generationID: string,
  weeklyPlanID: string | undefined,
  completedAt: string,
  step: string,
  originalError: unknown,
): Promise<{ ok: true } | { response: Response }> {
  console.warn(
    "generate-week completion snapshot write failed; retrying minimal completion",
    {
      step,
      error: originalError,
    },
  );
  const update: Record<string, unknown> = {
    status: "completed",
    completed_at: completedAt,
    error_code: null,
  };
  if (weeklyPlanID) {
    update.weekly_plan_id = weeklyPlanID;
  }

  const { error } = await completeGenerationRunMinimal(
    admin,
    generationID,
    update,
  );

  if (error) {
    return generationPersistFailure(step, error);
  }

  return { ok: true };
}

export async function markGenerationRunFailed(
  admin: SupabaseAdminClient,
  generationID: string,
  errorCode: string,
): Promise<void> {
  await markGenerationRunFailedStore(admin, generationID, errorCode);
}
