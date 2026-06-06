import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  corsHeaders,
  jsonResponse,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";
import {
  classifyURL,
  displayHandle,
  normalizeInstagramHandle,
  normalizeURL,
} from "../import-references/normalization.ts";

type ReviewReferenceRequest = {
  creator_id?: string;
  item?: {
    kind?: "benchmark_creator" | "source_reference";
    id?: string;
  };
  action?: "approve" | "dismiss" | "edit";
  edit?: {
    target_type?: "account" | "reel" | "audio" | "unknown";
    handle?: string | null;
    url?: string | null;
    notes?: string | null;
  };
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

  let body: ReviewReferenceRequest;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const creatorID = body.creator_id?.trim();
  const itemKind = body.item?.kind;
  const itemID = body.item?.id?.trim();
  const action = body.action;

  if (!creatorID || !itemKind || !itemID || !action) {
    return jsonResponse({ error: "invalid_review_payload" }, 400);
  }

  if (!["approve", "dismiss", "edit"].includes(action)) {
    return jsonResponse({ error: "invalid_review_action" }, 400);
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

  try {
    if (itemKind === "benchmark_creator") {
      return await reviewBenchmarkCreator(
        admin,
        session.workspaceID,
        creatorID,
        session.memberID,
        itemID,
        action,
      );
    }

    return await reviewSourceReference(
      admin,
      session.workspaceID,
      creatorID,
      session.memberID,
      itemID,
      action,
      body.edit,
    );
  } catch (error) {
    return jsonResponse({
      error: "review_reference_failed",
      details: error instanceof Error ? error.message : String(error),
    }, 500);
  }
});

async function reviewBenchmarkCreator(
  admin: any,
  workspaceID: string,
  creatorID: string,
  memberID: string,
  itemID: string,
  action: "approve" | "dismiss" | "edit",
): Promise<Response> {
  if (action === "edit") {
    return jsonResponse({ error: "benchmark_creator_edit_not_supported" }, 400);
  }

  const resultStatus = action === "approve" ? "active" : "poor_fit";
  const { data, error } = await admin
    .from("benchmark_creators")
    .update({
      status: resultStatus,
      relevance_notes: reviewNote(action, memberID),
      updated_at: new Date().toISOString(),
    })
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("id", itemID)
    .select("id,status")
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    return jsonResponse({ error: "review_item_not_found" }, 404);
  }

  return jsonResponse({
    item_id: itemID,
    kind: "benchmark_creator",
    action,
    result_status: resultStatus,
    toast: action === "approve"
      ? "Reference creator approved."
      : "Reference creator marked poor fit.",
  });
}

async function reviewSourceReference(
  admin: any,
  workspaceID: string,
  creatorID: string,
  memberID: string,
  itemID: string,
  action: "approve" | "dismiss" | "edit",
  edit?: ReviewReferenceRequest["edit"],
): Promise<Response> {
  const { data: source, error: sourceError } = await admin
    .from("source_references")
    .select(
      "id,source_type,source_url,manual_notes,provenance,status,canonical_source_key",
    )
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("id", itemID)
    .maybeSingle();

  if (sourceError) {
    throw sourceError;
  }

  if (!source) {
    return jsonResponse({ error: "review_item_not_found" }, 404);
  }

  if (action === "approve") {
    return await updateSourceReview(admin, source, memberID, "approve", {
      status: "confirmed",
      source_type: source.source_type,
      source_url: source.source_url,
      manual_notes: source.manual_notes,
      canonical_source_key: source.canonical_source_key,
    }, "Reference confirmed.");
  }

  if (action === "dismiss") {
    return await updateSourceReview(admin, source, memberID, "dismiss", {
      status: "dismissed",
      source_type: source.source_type,
      source_url: source.source_url,
      manual_notes: source.manual_notes,
      canonical_source_key: source.canonical_source_key,
    }, "Reference dismissed.");
  }

  if (!edit?.target_type) {
    return jsonResponse({ error: "missing_review_edit" }, 400);
  }

  if (edit.target_type === "account") {
    return await resolveUnknownAsAccount(
      admin,
      workspaceID,
      creatorID,
      memberID,
      source,
      edit,
    );
  }

  if (edit.target_type === "reel" || edit.target_type === "audio") {
    return await resolveUnknownAsSource(admin, memberID, source, edit);
  }

  return await updateSourceReview(admin, source, memberID, "edit", {
    status: "needs_review",
    source_type: "import_row",
    source_url: edit.url?.trim() || source.source_url,
    manual_notes: edit.notes?.trim() || source.manual_notes,
    canonical_source_key: normalizeURL(edit.url ?? "") ??
      source.canonical_source_key,
  }, "Reference updated.");
}

async function resolveUnknownAsAccount(
  admin: any,
  workspaceID: string,
  creatorID: string,
  memberID: string,
  source: any,
  edit: NonNullable<ReviewReferenceRequest["edit"]>,
): Promise<Response> {
  const normalizedHandle = normalizeInstagramHandle(
    edit.handle ?? edit.url ?? "",
  );
  if (!normalizedHandle) {
    return jsonResponse({ error: "invalid_account_handle" }, 400);
  }

  const watchlistID = await inspirationWatchlistID(
    admin,
    workspaceID,
    creatorID,
  );
  let { data: benchmark, error: benchmarkError } = await admin
    .from("benchmark_creators")
    .select("id")
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("platform", "instagram")
    .eq("normalized_handle", normalizedHandle)
    .maybeSingle();

  if (benchmarkError) {
    throw benchmarkError;
  }

  if (!benchmark) {
    const insert = await admin
      .from("benchmark_creators")
      .insert({
        workspace_id: workspaceID,
        creator_id: creatorID,
        handle: displayHandle(normalizedHandle),
        normalized_handle: normalizedHandle,
        display_name: displayHandle(normalizedHandle),
        platform: "instagram",
        relevance_notes: edit.notes?.trim() ||
          "Resolved from imported reference.",
        priority_score: 50,
        status: "active",
      })
      .select("id")
      .single();

    if (insert.error) {
      throw insert.error;
    }
    benchmark = insert.data;
  } else {
    const update = await admin
      .from("benchmark_creators")
      .update({
        status: "active",
        updated_at: new Date().toISOString(),
      })
      .eq("id", benchmark.id);

    if (update.error) {
      throw update.error;
    }
  }

  const link = await admin
    .from("watchlist_benchmark_creators")
    .insert({
      workspace_id: workspaceID,
      creator_id: creatorID,
      watchlist_id: watchlistID,
      benchmark_creator_id: benchmark.id,
    });

  if (link.error && !String(link.error.message).includes("duplicate key")) {
    throw link.error;
  }

  const update = await updateSourceReview(admin, source, memberID, "edit", {
    status: "dismissed",
    source_type: "import_row",
    source_url: source.source_url,
    manual_notes: edit.notes?.trim() || source.manual_notes,
    benchmark_creator_id: benchmark.id,
    canonical_source_key: source.canonical_source_key,
  }, "Reference creator approved.");

  return update;
}

async function resolveUnknownAsSource(
  admin: any,
  memberID: string,
  source: any,
  edit: NonNullable<ReviewReferenceRequest["edit"]>,
): Promise<Response> {
  const url = edit.url?.trim() || source.source_url;
  if (!url) {
    return jsonResponse({ error: "missing_reference_url" }, 400);
  }

  const classified = classifyURL(url);
  if (classified.kind === "story") {
    return jsonResponse({
      error: "story_urls_not_allowed",
      message: "Story URLs can't be used as references.",
    }, 400);
  }

  const sourceType = edit.target_type === "audio" ? "audio_link" : "reel_link";
  const canonicalKey =
    classified.kind === "audio" || classified.kind === "reel" ||
      classified.kind === "post"
      ? classified.canonicalKey
      : normalizeURL(url);

  return await updateSourceReview(admin, source, memberID, "edit", {
    status: "confirmed",
    source_type: sourceType,
    source_url: normalizeURL(url) ?? url,
    manual_notes: edit.notes?.trim() || source.manual_notes,
    canonical_source_key: canonicalKey,
  }, "Reference confirmed.");
}

async function updateSourceReview(
  admin: any,
  source: any,
  memberID: string,
  action: "approve" | "dismiss" | "edit",
  values: Record<string, unknown>,
  toast: string,
): Promise<Response> {
  const provenance = {
    ...(source.provenance ?? {}),
    reviewed_at: new Date().toISOString(),
    review_action: action,
    reviewed_by_member_id: memberID,
  };

  const { data, error } = await admin
    .from("source_references")
    .update({
      ...values,
      provenance,
      updated_at: new Date().toISOString(),
    })
    .eq("id", source.id)
    .select("id,status,source_type")
    .single();

  if (error) {
    throw error;
  }

  return jsonResponse({
    item_id: source.id,
    kind: "source_reference",
    action,
    result_status: data.status,
    toast,
  });
}

async function inspirationWatchlistID(
  admin: any,
  workspaceID: string,
  creatorID: string,
): Promise<string> {
  const existing = await admin
    .from("watchlists")
    .select("id")
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .eq("name", "Inspiration")
    .eq("status", "active")
    .maybeSingle();

  if (existing.error) {
    throw existing.error;
  }

  if (existing.data) {
    return existing.data.id;
  }

  const insert = await admin
    .from("watchlists")
    .insert({
      workspace_id: workspaceID,
      creator_id: creatorID,
      name: "Inspiration",
      kind: "reference_watchlist",
      source_description:
        "Manual import destination for inspiration accounts and links.",
      provenance_notes: "Created by Reference Review.",
      status: "active",
    })
    .select("id")
    .single();

  if (insert.error) {
    throw insert.error;
  }

  return insert.data.id;
}

function reviewNote(action: string, memberID: string): string {
  return `Reference ${action} by ${memberID} at ${new Date().toISOString()}.`;
}
