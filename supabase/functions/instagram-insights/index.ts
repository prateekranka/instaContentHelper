import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  assertCreator,
  CONTENT_CREATOR_ROLES,
  corsHeaders,
  jsonResponse,
  SupabaseAdminClient,
  VerifiedDeviceSession,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";
import {
  AccountSnapshot,
  buildReadyReport,
  fetchAccountSnapshot,
  hasAnyMetric,
  InstagramAccountType,
  InstagramPermissionError,
  InsightsReportDTO,
  isProfessional,
  needsRefresh,
  refreshLongLivedToken,
} from "../_shared/instagram.ts";

type InsightsRequest = { creator_id?: string };

type ConnectionRow = {
  id: string;
  ig_user_id: string;
  username: string | null;
  account_type: InstagramAccountType;
  access_token: string;
  token_expires_at: string | null;
};

export async function handleInstagramInsightsRequest(
  request: Request,
): Promise<Response> {
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

  const authResult = await verifyDeviceSession(
    request,
    admin,
    [...CONTENT_CREATOR_ROLES],
  );
  if ("response" in authResult) {
    return authResult.response;
  }

  let body: InsightsRequest;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const creatorID = body.creator_id?.trim();
  if (!creatorID) {
    return jsonResponse({ error: "invalid_insights_payload" }, 400);
  }

  const { session } = authResult;
  const creatorResult = await assertCreator(admin, session, creatorID);
  if (creatorResult) {
    return creatorResult;
  }

  return produceInsights(admin, session, creatorID);
}

if (import.meta.main) Deno.serve(handleInstagramInsightsRequest);

async function produceInsights(
  admin: SupabaseAdminClient,
  session: VerifiedDeviceSession,
  creatorID: string,
): Promise<Response> {
  const { data: connection, error: connError } = await admin
    .from("creator_instagram_connections")
    .select("id, ig_user_id, username, account_type, access_token, token_expires_at")
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", creatorID)
    .is("revoked_at", null)
    .maybeSingle();

  if (connError) {
    return jsonResponse({ error: "connection_lookup_failed" }, 500);
  }
  if (!connection) {
    return jsonResponse(state("not_connected", null));
  }

  const conn = connection as ConnectionRow;
  if (!isProfessional(conn.account_type)) {
    return jsonResponse(state("connected_personal", conn.account_type));
  }

  let accessToken = conn.access_token;
  if (needsRefresh(conn.token_expires_at, new Date())) {
    try {
      const refreshed = await refreshLongLivedToken(accessToken);
      accessToken = refreshed.accessToken;
      await admin
        .from("creator_instagram_connections")
        .update({ access_token: refreshed.accessToken, token_expires_at: refreshed.expiresAt })
        .eq("id", conn.id);
    } catch (_error) {
      // Non-fatal: try the existing token; a hard auth failure surfaces below.
    }
  }

  let snapshot: AccountSnapshot;
  try {
    snapshot = await fetchAccountSnapshot(conn.ig_user_id, accessToken);
  } catch (error) {
    if (error instanceof InstagramPermissionError) {
      return jsonResponse(state("permission_needed", conn.account_type));
    }
    return jsonResponse({ error: "instagram_fetch_failed" }, 502);
  }

  if (!hasAnyMetric(snapshot)) {
    return jsonResponse(state("no_data", conn.account_type, conn.username));
  }

  // Previous snapshot (for deltas) BEFORE inserting the new one.
  const { data: prevRows } = await admin
    .from("creator_account_insight_snapshots")
    .select("followers_count, reach_7d, saves_7d")
    .eq("workspace_id", session.workspaceID)
    .eq("creator_id", creatorID)
    .order("captured_at", { ascending: false })
    .limit(1);

  const previous: AccountSnapshot | null = prevRows && prevRows.length > 0
    ? {
      followersCount: prevRows[0].followers_count ?? null,
      reach7d: prevRows[0].reach_7d ?? null,
      saves7d: prevRows[0].saves_7d ?? null,
    }
    : null;

  await admin.from("creator_account_insight_snapshots").insert({
    workspace_id: session.workspaceID,
    creator_id: creatorID,
    followers_count: snapshot.followersCount,
    reach_7d: snapshot.reach7d,
    saves_7d: snapshot.saves7d,
    metric_source: "api",
    data_quality: snapshot.saves7d === null ? "partial" : "complete",
  });

  const report = buildReadyReport(snapshot, previous, {
    username: conn.username,
    accountType: conn.account_type,
    source: "api",
    fetchedAt: new Date().toISOString(),
    dataQuality: snapshot.saves7d === null ? "partial" : "complete",
  });

  return jsonResponse(report as unknown as Record<string, unknown>);
}

function state(
  s: InsightsReportDTO["state"],
  accountType: InstagramAccountType | null,
  username: string | null = null,
): Record<string, unknown> {
  const report: InsightsReportDTO = {
    connected: s !== "not_connected",
    account_type: accountType,
    source: "api",
    state: s,
    username,
    metrics: null,
    detail: null,
    nudge: null,
    fetched_at: null,
    data_quality: null,
  };
  return report as unknown as Record<string, unknown>;
}
