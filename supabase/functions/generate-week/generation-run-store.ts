import { SupabaseAdminClient } from "../_shared/device-auth.ts";

export const GENERATION_RUN_STATUS_SELECT =
  "id,workspace_id,creator_id,weekly_setup_id,requested_by_member_id,status,weekly_plan_id,output_snapshot,input_snapshot,error_code,completed_at,model,generation_scope,target_daily_card_id,target_scheduled_date";

export const GENERATION_RUN_CANCELLATION_SELECT = "status,error_code";

export async function readGenerationRunStatus(
  admin: SupabaseAdminClient,
  generationID: string,
  workspaceID: string,
): Promise<{ data: Record<string, unknown> | null; error: unknown }> {
  const { data, error } = await admin
    .from("weekly_generation_runs")
    .select(GENERATION_RUN_STATUS_SELECT)
    .eq("id", generationID)
    .eq("workspace_id", workspaceID)
    .maybeSingle();

  return {
    data: isRecord(data) ? data : null,
    error,
  };
}

export async function readGenerationRunCancellationState(
  admin: SupabaseAdminClient,
  generationID: string,
): Promise<{ data: Record<string, unknown> | null; error: unknown }> {
  const { data, error } = await admin
    .from("weekly_generation_runs")
    .select(GENERATION_RUN_CANCELLATION_SELECT)
    .eq("id", generationID)
    .maybeSingle();

  return {
    data: isRecord(data) ? data : null,
    error,
  };
}

export async function insertWeekGenerationRun(
  admin: SupabaseAdminClient,
  row: Record<string, unknown>,
): Promise<{ data: { id: string } | null; error: unknown }> {
  const { data, error } = await admin
    .from("weekly_generation_runs")
    .insert(row)
    .select("id")
    .single();

  return {
    data: isRunIDRecord(data) ? data : null,
    error,
  };
}

export async function insertDayGenerationRun(
  admin: SupabaseAdminClient,
  row: Record<string, unknown>,
): Promise<{ data: { id: string } | null; error: unknown }> {
  const { data, error } = await admin
    .from("weekly_generation_runs")
    .insert(row)
    .select("id")
    .single();

  return {
    data: isRunIDRecord(data) ? data : null,
    error,
  };
}

export async function linkGenerationRunWeeklyPlan(
  admin: SupabaseAdminClient,
  generationID: string,
  weeklyPlanID: string,
): Promise<{ error: unknown | null }> {
  const { error } = await admin
    .from("weekly_generation_runs")
    .update({ weekly_plan_id: weeklyPlanID })
    .eq("id", generationID)
    .eq("status", "running");

  return { error: error ?? null };
}

export async function updateGenerationRunProgress(
  admin: SupabaseAdminClient,
  generationID: string,
  progress: unknown,
): Promise<{ error: unknown | null }> {
  const { error } = await admin
    .from("weekly_generation_runs")
    .update({ output_snapshot: progress })
    .eq("id", generationID)
    .eq("status", "running");

  return { error: error ?? null };
}

export async function completeFullWeekGenerationRun(
  admin: SupabaseAdminClient,
  generationID: string,
  payload: {
    weekly_plan_id: string;
    output_snapshot: unknown;
    warnings: unknown;
    assumptions: unknown;
    completed_at: string;
  },
): Promise<{ error: unknown | null }> {
  const { error } = await admin
    .from("weekly_generation_runs")
    .update({
      weekly_plan_id: payload.weekly_plan_id,
      status: "completed",
      output_snapshot: payload.output_snapshot,
      warnings: payload.warnings,
      assumptions: payload.assumptions,
      completed_at: payload.completed_at,
      error_code: null,
    })
    .eq("id", generationID);

  return { error: error ?? null };
}

export async function completePartialGenerationRun(
  admin: SupabaseAdminClient,
  generationID: string,
  payload: {
    weekly_plan_id: string;
    output_snapshot: unknown;
    completed_at: string;
  },
): Promise<{ error: unknown | null }> {
  const { error } = await admin
    .from("weekly_generation_runs")
    .update({
      weekly_plan_id: payload.weekly_plan_id,
      status: "completed",
      output_snapshot: payload.output_snapshot,
      error_code: "partial_generation",
      completed_at: payload.completed_at,
    })
    .eq("id", generationID);

  return { error: error ?? null };
}

export async function completeDayGenerationRun(
  admin: SupabaseAdminClient,
  generationID: string,
  payload: {
    output_snapshot: unknown;
    warnings: unknown;
    assumptions: unknown;
    completed_at: string;
  },
): Promise<{ error: unknown | null }> {
  const { error } = await admin
    .from("weekly_generation_runs")
    .update({
      status: "completed",
      output_snapshot: payload.output_snapshot,
      warnings: payload.warnings,
      assumptions: payload.assumptions,
      completed_at: payload.completed_at,
      error_code: null,
    })
    .eq("id", generationID);

  return { error: error ?? null };
}

export async function completeGenerationRunMinimal(
  admin: SupabaseAdminClient,
  generationID: string,
  update: Record<string, unknown>,
): Promise<{ error: unknown | null }> {
  const { error } = await admin
    .from("weekly_generation_runs")
    .update(update)
    .eq("id", generationID);

  return { error: error ?? null };
}

export async function markGenerationRunFailed(
  admin: SupabaseAdminClient,
  generationID: string,
  errorCode: string,
): Promise<void> {
  await admin
    .from("weekly_generation_runs")
    .update({
      status: "failed",
      error_code: errorCode,
      completed_at: new Date().toISOString(),
    })
    .eq("id", generationID);
}

function isRunIDRecord(value: unknown): value is { id: string } {
  return isRecord(value) && typeof value.id === "string";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
