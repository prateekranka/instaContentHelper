import { jsonResponse, SupabaseAdminClient } from "../_shared/device-auth.ts";
import type {
  GeneratedDailyCard,
  GeneratedWeekOutput,
  GenerateWeekRequest,
  GenerationInputSnapshot,
} from "./generation.ts";
import { preserveManualDailyCardEdits } from "./generation.ts";
import { isRecord, isUUID, weekDates } from "./generation-validation.ts";

type PlanIdentityRecord = {
  id: string;
  status?: string;
  is_soft_locked?: boolean;
};

type CardIdentityRecord = {
  id: string;
  scheduled_date: string;
} & Record<string, unknown>;

export function generationPersistFailure(
  step: string,
  error?: unknown,
): { response: Response } {
  console.error(
    "generate-week persist failed",
    step,
    postgrestErrorMessage(error),
  );
  const detail = postgrestErrorMessage(error);
  return {
    response: jsonResponse(
      {
        error: "generation_persist_failed",
        step,
        detail: detail.slice(0, 500),
      },
      500,
    ),
  };
}

export function postgrestErrorMessage(error: unknown): string {
  if (isRecord(error)) {
    return stringValue(error.message) ??
      stringValue(error.details) ??
      stringValue(error.hint) ??
      stringValue(error.code) ??
      "unknown_error";
  }
  if (error instanceof Error) {
    return error.message;
  }
  return typeof error === "string" ? error : "unknown_error";
}

export async function clearExistingDraftDailyCardsForFullGeneration(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  weeklyPlanID: string,
): Promise<{ ok: true } | { response: Response }> {
  const { error } = await admin
    .from("daily_cards")
    .delete()
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("weekly_plan_id", weeklyPlanID);

  if (error) {
    return generationPersistFailure("daily_cards_clear_existing", error);
  }

  return { ok: true };
}

export function generatedDailyCardValues(
  card: GeneratedDailyCard,
): Record<string, unknown> {
  return {
    status: "draft",
    title: card.title,
    why_today: card.why_today,
    growth_job: card.growth_job,
    content_pillar: card.content_pillar,
    shootability: card.shootability,
    estimated_shoot_minutes: card.estimated_shoot_minutes,
    energy_required: card.energy_required,
    language_mode: card.language_mode,
    scene_list: card.scene_list,
    script: card.script,
    no_voiceover_version: card.no_voiceover_version,
    on_screen_text: card.on_screen_text,
    caption: card.caption,
    cta: card.cta,
    hashtags: card.hashtags,
    cover_text: card.cover_text,
    post_instructions: {
      instructions: card.post_instructions,
      audio_option_notes: card.audio_option_notes,
      format: card.format,
      primary_surface: card.primary_surface,
      duration_seconds: card.duration_seconds,
      hook: card.hook,
      weekly_brief_anchor: card.weekly_brief_anchor,
      brief_alignment: card.brief_alignment,
      brief_context_tags: card.brief_context_tags,
      save_share_reason: card.save_share_reason,
      shot_timeline: card.shot_timeline,
      voiceover_timeline: card.voiceover_timeline,
      silent_version_timeline: card.silent_version_timeline,
      on_screen_text_timeline: card.on_screen_text_timeline,
      caption_backup_detail: card.caption_backup_detail,
      creator_fit_score: card.creator_fit_score,
    },
    brand_event_notes: card.brand_event_notes || null,
    backup_story: { line: card.backup_story, detail: card.backup_story_detail },
    backup_caption_only: {
      line: card.backup_caption_only,
      detail: card.caption_backup_detail,
    },
    risk_notes: card.risk_notes,
    assumptions: card.assumptions,
    source_note: card.source_note,
    storyboard_thumbnail_assets: [],
  };
}

export const DAY_PLAN_CONTAINER_SELECT = "id,status,is_soft_locked";
export const DRAFT_DAILY_CARD_UPDATE_SELECT = "id,scheduled_date";

export type ThinDraftDayPlanContainerRow = {
  id: string;
  workspace_id: string;
  creator_id: string;
  weekly_setup_id: null;
  creator_profile_id: null;
  week_start_date: string;
  status: "draft";
  strategy_summary: string;
  warnings: unknown[];
  assumptions: string[];
  is_soft_locked: false;
  created_by_member_id: string;
};

export type ExistingDraftDailyCardIdentity = {
  id: string;
  workspace_id: string;
  creator_id: string;
  weekly_plan_id: string;
  scheduled_date: string;
};

/** Latest draft weekly_plans container for single-day generation. */
export async function findLatestDraftDayPlanContainer(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  weekStartDate: string,
): Promise<{ data: Record<string, unknown>[] | null; error: unknown }> {
  const { data, error } = await admin
    .from("weekly_plans")
    .select(DAY_PLAN_CONTAINER_SELECT)
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("week_start_date", weekStartDate)
    .in("status", ["draft"])
    .order("updated_at", { ascending: false })
    .limit(1);

  return {
    data: Array.isArray(data) ? data.filter(isRecord) : null,
    error,
  };
}

/** Thin draft weekly_plans insert used when no day container exists. */
export async function insertThinDraftDayPlanContainer(
  admin: SupabaseAdminClient,
  row: ThinDraftDayPlanContainerRow,
): Promise<{ data: { id: string } | null; error: unknown }> {
  const { data, error } = await admin
    .from("weekly_plans")
    .insert(row)
    .select("id")
    .single();

  return {
    data: isPlanIDRecord(data) ? data : null,
    error,
  };
}

/** Update an existing draft daily_cards row during regenerate_day. */
export async function updateExistingDraftDailyCard(
  admin: SupabaseAdminClient,
  values: Record<string, unknown>,
  identity: ExistingDraftDailyCardIdentity,
): Promise<{ data: Record<string, unknown> | null; error: unknown }> {
  const { data, error } = await admin
    .from("daily_cards")
    .update(values)
    .eq("id", identity.id)
    .eq("workspace_id", identity.workspace_id)
    .eq("creator_id", identity.creator_id)
    .eq("weekly_plan_id", identity.weekly_plan_id)
    .eq("scheduled_date", identity.scheduled_date)
    .eq("status", "draft")
    .select(DRAFT_DAILY_CARD_UPDATE_SELECT)
    .maybeSingle();

  return {
    data: isRecord(data) ? data : null,
    error,
  };
}

export async function replaceDailyCardReferences(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  dailyCardID: string,
  card: GeneratedDailyCard,
): Promise<{ ok: true } | { response: Response }> {
  const { error: clearError } = await admin
    .from("daily_card_references")
    .delete()
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("daily_card_id", dailyCardID);
  if (clearError) {
    console.warn("generate-week day reference clear failed; continuing", {
      step: "replace_day_references_clear",
      error: clearError,
    });
  }
  const references = (card.source_reference_ids ?? []).filter(isUUID).map(
    (sourceReferenceID) => ({
      workspace_id: workspaceID,
      creator_id: creatorID,
      daily_card_id: dailyCardID,
      source_reference_id: sourceReferenceID,
      reason: card.source_note,
    }),
  );
  if (references.length > 0) {
    const { error } = await admin
      .from("daily_card_references")
      .insert(references);
    if (error) {
      console.warn("generate-week day reference insert failed; continuing", {
        step: "replace_day_references_insert",
        error,
      });
    }
  }
  return { ok: true };
}

export async function upsertDraftWeeklyPlan(
  admin: SupabaseAdminClient,
  workspaceID: string,
  request: GenerateWeekRequest,
  memberID: string,
  weeklySetup: Record<string, unknown> | null,
  inputSnapshot: GenerationInputSnapshot,
  generated: GeneratedWeekOutput,
): Promise<{ weeklyPlanID: string } | { response: Response }> {
  const existingResult = await admin
    .from("weekly_plans")
    .select("id,status,is_soft_locked")
    .eq("workspace_id", workspaceID)
    .eq("creator_id", request.creator_id)
    .eq("week_start_date", request.week_start_date)
    .in("status", ["draft", "reviewed"])
    .order("updated_at", { ascending: false })
    .limit(1);

  if (existingResult.error) {
    return generationPersistFailure(
      "weekly_plan_lookup",
      existingResult.error,
    );
  }

  const existing = (existingResult.data?.[0] ?? null) as
    | PlanIdentityRecord
    | null;
  if (existing?.is_soft_locked) {
    return {
      response: jsonResponse({ error: "existing_published_week_locked" }, 409),
    };
  }

  const recoveredPlanID = existing?.id
    ? undefined
    : await recoverWeeklyPlanIDFromExistingCards(
      admin,
      workspaceID,
      request.creator_id,
      request.week_start_date,
    );
  const weeklyPlanID = existing?.id ?? recoveredPlanID ?? crypto.randomUUID();
  const planValues = {
    id: weeklyPlanID,
    workspace_id: workspaceID,
    creator_id: request.creator_id,
    weekly_setup_id: weeklySetup?.id ?? null,
    creator_profile_id: stringValue(weeklySetup?.creator_profile_id) ??
      stringValue(inputSnapshot.creator_profile?.id) ??
      null,
    week_start_date: request.week_start_date,
    status: "draft",
    strategy_summary: generated.strategy_summary,
    warnings: generated.warnings,
    assumptions: generated.assumptions,
    is_soft_locked: false,
    created_by_member_id: memberID,
  };

  const write = existing || recoveredPlanID
    ? admin.from("weekly_plans").update(planValues).eq("id", weeklyPlanID)
      .select("id").single()
    : admin.from("weekly_plans").insert(planValues).select("id").single();

  const { data, error } = await write;
  if (error || !data) {
    return generationPersistFailure("weekly_plan_write", error);
  }

  return { weeklyPlanID };
}

export async function recoverWeeklyPlanIDFromExistingCards(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  weekStartDate: string,
): Promise<string | undefined> {
  const dates = new Set(weekDates(weekStartDate));
  const { data, error } = await admin
    .from("daily_cards")
    .select("weekly_plan_id,scheduled_date")
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .in("scheduled_date", [...dates]);
  if (error) {
    console.warn("generate-week existing card plan recovery failed", {
      step: "recover_weekly_plan_from_cards",
      error,
    });
    return undefined;
  }
  const rows = ((data ?? []) as Record<string, unknown>[]).filter((row) =>
    dates.has(stringValue(row.scheduled_date) ?? "")
  );
  const planIDs = new Set(
    rows.map((row) => stringValue(row.weekly_plan_id)).filter((
      value,
    ): value is string => isUUID(value)),
  );
  if (rows.length === dates.size && planIDs.size === 1) {
    return [...planIDs][0];
  }
  return undefined;
}

export async function insertGeneratedIdeas(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  generated: GeneratedWeekOutput,
): Promise<{ ideaBank: Record<string, unknown>[] } | { response: Response }> {
  if (generated.idea_bank.length === 0) {
    return { ideaBank: [] };
  }

  const rows = generated.idea_bank.map((idea) => ({
    workspace_id: workspaceID,
    creator_id: creatorID,
    title: idea.title,
    summary: idea.summary,
    tags: idea.tags,
    suggested_use: idea.suggested_use,
    shootability: idea.shootability,
    fit_score: idea.fit_score,
    notes: idea.source_note,
    status: idea.status,
  }));

  const { data, error } = await admin
    .from("ideas")
    .insert(rows)
    .select("id,title,summary,suggested_use,shootability,status");

  if (error) {
    console.warn("generate-week idea bank insert failed; continuing", {
      step: "ideas_insert",
      error,
    });
    return { ideaBank: [] };
  }

  return { ideaBank: (data ?? []) as Record<string, unknown>[] };
}

export async function upsertGeneratedDailyCards(
  admin: SupabaseAdminClient,
  workspaceID: string,
  creatorID: string,
  weeklyPlanID: string,
  cards: GeneratedDailyCard[],
  preserveManualEdits: boolean,
): Promise<{ dailyCards: GeneratedDailyCard[] } | { response: Response }> {
  const existingCardsResult = await admin
    .from("daily_cards")
    .select(
      [
        "id",
        "scheduled_date",
        "title",
        "why_today",
        "shootability",
        "estimated_shoot_minutes",
        "scene_list",
        "caption",
        "backup_story",
        "backup_caption_only",
      ].join(","),
    )
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("weekly_plan_id", weeklyPlanID);

  if (existingCardsResult.error) {
    return generationPersistFailure(
      "daily_cards_lookup",
      existingCardsResult.error,
    );
  }

  const existingIDs = new Map<string, string>(
    ((existingCardsResult.data ?? []) as CardIdentityRecord[]).map((row) => [
      row.scheduled_date,
      row.id,
    ]),
  );
  const existingCards = new Map<string, CardIdentityRecord>(
    ((existingCardsResult.data ?? []) as CardIdentityRecord[]).map((row) => [
      row.scheduled_date,
      row,
    ]),
  );
  const cardsToWrite = preserveManualEdits
    ? cards.map((card) =>
      preserveManualDailyCardEdits(card, existingCards.get(card.scheduled_date))
    )
    : cards;

  const rows = cardsToWrite.map((card) => ({
    id: existingIDs.get(card.scheduled_date) ?? crypto.randomUUID(),
    workspace_id: workspaceID,
    creator_id: creatorID,
    weekly_plan_id: weeklyPlanID,
    scheduled_date: card.scheduled_date,
    status: "draft",
    title: card.title,
    why_today: card.why_today,
    growth_job: card.growth_job,
    content_pillar: card.content_pillar,
    shootability: card.shootability,
    estimated_shoot_minutes: card.estimated_shoot_minutes,
    energy_required: card.energy_required,
    language_mode: card.language_mode,
    scene_list: card.scene_list,
    script: card.script,
    no_voiceover_version: card.no_voiceover_version,
    on_screen_text: card.on_screen_text,
    caption: card.caption,
    cta: card.cta,
    hashtags: card.hashtags,
    cover_text: card.cover_text,
    post_instructions: {
      instructions: card.post_instructions,
      audio_option_notes: card.audio_option_notes,
      format: card.format,
      primary_surface: card.primary_surface,
      duration_seconds: card.duration_seconds,
      hook: card.hook,
      weekly_brief_anchor: card.weekly_brief_anchor,
      brief_alignment: card.brief_alignment,
      brief_context_tags: card.brief_context_tags,
      save_share_reason: card.save_share_reason,
      shot_timeline: card.shot_timeline,
      voiceover_timeline: card.voiceover_timeline,
      silent_version_timeline: card.silent_version_timeline,
      on_screen_text_timeline: card.on_screen_text_timeline,
      caption_backup_detail: card.caption_backup_detail,
      creator_fit_score: card.creator_fit_score,
    },
    brand_event_notes: card.brand_event_notes || null,
    backup_story: { line: card.backup_story, detail: card.backup_story_detail },
    backup_caption_only: {
      line: card.backup_caption_only,
      detail: card.caption_backup_detail,
    },
    risk_notes: card.risk_notes,
    assumptions: card.assumptions,
    source_note: card.source_note,
    storyboard_thumbnail_assets: [],
  }));

  const writtenIDs = new Map<string, string>();
  for (const row of rows) {
    if (existingIDs.has(row.scheduled_date)) {
      const {
        id,
        workspace_id: _workspaceID,
        creator_id: _creatorID,
        weekly_plan_id: _weeklyPlanID,
        scheduled_date: _scheduledDate,
        ...updateValues
      } = row;
      const { data, error } = await admin
        .from("daily_cards")
        .update(updateValues)
        .eq("id", id)
        .eq("workspace_id", workspaceID)
        .eq("creator_id", creatorID)
        .eq("weekly_plan_id", weeklyPlanID)
        .eq("scheduled_date", row.scheduled_date)
        .select("id,scheduled_date")
        .maybeSingle();

      if (error) {
        return generationPersistFailure("daily_card_update", error);
      }
      if (!isRecord(data)) {
        const fallback = await upsertDailyCardRow(admin, row);
        if ("response" in fallback) {
          return fallback;
        }
        writtenIDs.set(fallback.scheduledDate, fallback.id);
        continue;
      }
      writtenIDs.set(
        stringValue(data.scheduled_date) ?? row.scheduled_date,
        stringValue(data.id) ?? id,
      );
      continue;
    }

    const insertResult = await upsertDailyCardRow(admin, row);
    if ("response" in insertResult) {
      return insertResult;
    }
    writtenIDs.set(insertResult.scheduledDate, insertResult.id);
  }

  const dailyCards = cardsToWrite.map((card) => ({
    ...card,
    id: writtenIDs.get(card.scheduled_date) ??
      rows.find((row) => row.scheduled_date === card.scheduled_date)?.id,
  }));

  const dailyCardIDs = dailyCards
    .map((card) => card.id)
    .filter((id): id is string => isUUID(id));
  if (dailyCardIDs.length > 0) {
    const { error: clearReferenceError } = await admin
      .from("daily_card_references")
      .delete()
      .eq("workspace_id", workspaceID)
      .eq("creator_id", creatorID)
      .in("daily_card_id", dailyCardIDs);
    if (clearReferenceError) {
      console.warn(
        "generate-week daily card reference clear failed; continuing",
        {
          step: "daily_card_references_clear",
          error: clearReferenceError,
        },
      );
    }
  }

  const references = dailyCards.flatMap((card) =>
    (card.source_reference_ids ?? []).filter(isUUID).map((
      sourceReferenceID,
    ) => ({
      workspace_id: workspaceID,
      creator_id: creatorID,
      daily_card_id: card.id,
      source_reference_id: sourceReferenceID,
      reason: card.source_note,
    }))
  ).filter((row) => row.daily_card_id);

  if (references.length > 0) {
    const { error: referenceError } = await admin
      .from("daily_card_references")
      .insert(references);
    if (referenceError) {
      console.warn(
        "generate-week daily card reference insert failed; continuing",
        {
          step: "daily_card_references_insert",
          error: referenceError,
        },
      );
    }
  }

  return { dailyCards };
}

export async function upsertDailyCardRow(
  admin: SupabaseAdminClient,
  row: Record<string, unknown> & { id: string; scheduled_date: string },
): Promise<
  { id: string; scheduledDate: string } | { response: Response }
> {
  const { data, error } = await admin
    .from("daily_cards")
    .insert(row)
    .select("id,scheduled_date")
    .single();

  if (error || !isRecord(data)) {
    const recovered = await recoverInsertedDailyCardRow(admin, row);
    if (recovered) {
      return recovered;
    }
    const recoveredConflict = await recoverConflictingDailyCardRow(admin, row);
    if (recoveredConflict) {
      return recoveredConflict;
    }
    return generationPersistFailure(
      "daily_card_upsert",
      error ?? new Error("daily_card_upsert_no_returned_row"),
    );
  }

  return {
    id: stringValue(data.id) ?? row.id,
    scheduledDate: stringValue(data.scheduled_date) ?? row.scheduled_date,
  };
}

export async function recoverConflictingDailyCardRow(
  admin: SupabaseAdminClient,
  row: Record<string, unknown> & { id: string; scheduled_date: string },
): Promise<{ id: string; scheduledDate: string } | null> {
  const { data: existing, error: lookupError } = await admin
    .from("daily_cards")
    .select("id,scheduled_date")
    .eq("workspace_id", row.workspace_id)
    .eq("creator_id", row.creator_id)
    .eq("weekly_plan_id", row.weekly_plan_id)
    .eq("scheduled_date", row.scheduled_date)
    .maybeSingle();

  if (lookupError || !isRecord(existing)) {
    return null;
  }

  const existingID = stringValue(existing.id);
  if (!existingID) {
    return null;
  }

  const {
    id: _id,
    workspace_id: _workspaceID,
    creator_id: _creatorID,
    weekly_plan_id: _weeklyPlanID,
    scheduled_date: _scheduledDate,
    ...updateValues
  } = row;
  const { data, error } = await admin
    .from("daily_cards")
    .update(updateValues)
    .eq("id", existingID)
    .eq("workspace_id", row.workspace_id)
    .eq("creator_id", row.creator_id)
    .eq("weekly_plan_id", row.weekly_plan_id)
    .eq("scheduled_date", row.scheduled_date)
    .select("id,scheduled_date")
    .maybeSingle();

  if (error || !isRecord(data)) {
    return null;
  }

  return {
    id: stringValue(data.id) ?? existingID,
    scheduledDate: stringValue(data.scheduled_date) ?? row.scheduled_date,
  };
}

export async function recoverInsertedDailyCardRow(
  admin: SupabaseAdminClient,
  row: Record<string, unknown> & { id: string; scheduled_date: string },
): Promise<{ id: string; scheduledDate: string } | null> {
  const { data, error } = await admin
    .from("daily_cards")
    .select("id,scheduled_date")
    .eq("id", row.id)
    .eq("workspace_id", row.workspace_id)
    .eq("creator_id", row.creator_id)
    .eq("weekly_plan_id", row.weekly_plan_id)
    .eq("scheduled_date", row.scheduled_date)
    .maybeSingle();

  if (error || !isRecord(data)) {
    return null;
  }

  return {
    id: stringValue(data.id) ?? row.id,
    scheduledDate: stringValue(data.scheduled_date) ?? row.scheduled_date,
  };
}

function isPlanIDRecord(value: unknown): value is { id: string } {
  return isRecord(value) && typeof value.id === "string";
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0
    ? value
    : undefined;
}
