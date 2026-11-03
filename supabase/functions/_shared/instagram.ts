// Instagram API with Facebook Login for Business ("Unified login") — OAuth +
// account insights. Newer Meta apps can't use Instagram Login, so the creator
// signs in with Facebook and we read the Instagram professional account that is
// linked to one of their Facebook Pages.
//
// This module isolates all Instagram I/O behind thin fetch wrappers and keeps the
// display/aggregation logic as pure functions (formatting, deltas, nudge, state
// mapping) so it can be unit-tested without network or a database.

// MARK: - Types

export type InstagramTokens = {
  igUserID: string;
  accessToken: string;
  expiresAt: string | null; // ISO
  username: string | null;
  accountType: InstagramAccountType;
};

export type InstagramAccountType =
  | "business"
  | "media_creator"
  | "personal"
  | "unknown";

export type AccountSnapshot = {
  followersCount: number | null;
  reach7d: number | null;
  saves7d: number | null;
};

export type InsightMetricDTO = {
  id: string;
  label: string;
  value: string;
  delta: string | null;
};

export type InsightsState =
  | "not_connected"
  | "connected_personal"
  | "permission_needed"
  | "no_data"
  | "ready";

export type InsightsReportDTO = {
  connected: boolean;
  account_type: InstagramAccountType | null;
  source: "api" | "sample" | "manual";
  state: InsightsState;
  username: string | null;
  metrics: InsightMetricDTO[] | null;
  detail: InsightMetricDTO[] | null;
  nudge: string | null;
  fetched_at: string | null;
  data_quality: string | null;
};

// MARK: - Pure helpers (unit-tested)

/** Professional (business/creator) accounts can return insights; personal cannot. */
export function isProfessional(accountType: InstagramAccountType): boolean {
  return accountType === "business" || accountType === "media_creator";
}

export function formatCount(value: number | null): string | null {
  if (value === null || !Number.isFinite(value)) return null;
  return new Intl.NumberFormat("en-US").format(Math.round(value));
}

/**
 * Week-over-week delta copy. Followers reads as an absolute change
 * ("+38 this week"); rate metrics read as a percentage ("up 22%").
 * Returns null when there is no prior snapshot to compare against.
 */
export function formatDelta(
  current: number | null,
  previous: number | null,
  kind: "absolute" | "percent",
): string | null {
  if (current === null || previous === null) return null;
  if (!Number.isFinite(current) || !Number.isFinite(previous)) return null;

  if (kind === "absolute") {
    const diff = Math.round(current - previous);
    if (diff === 0) return "no change this week";
    const sign = diff > 0 ? "+" : "−";
    return `${sign}${Math.abs(diff)} this week`;
  }

  if (previous === 0) return null;
  const pct = Math.round(((current - previous) / previous) * 100);
  if (pct === 0) return "no change";
  return pct > 0 ? `up ${pct}%` : `down ${Math.abs(pct)}%`;
}

/** One rule-based "what's working" nudge from the latest vs previous snapshot. */
export function deriveNudge(
  current: AccountSnapshot,
  previous: AccountSnapshot | null,
): string | null {
  if (!previous) return null;
  const candidates: Array<{ label: string; pct: number }> = [];
  const rate = (c: number | null, p: number | null) =>
    c !== null && p !== null && p > 0 ? ((c - p) / p) * 100 : null;

  const reachPct = rate(current.reach7d, previous.reach7d);
  const savesPct = rate(current.saves7d, previous.saves7d);
  if (reachPct !== null) candidates.push({ label: "reach", pct: reachPct });
  if (savesPct !== null) candidates.push({ label: "saves", pct: savesPct });

  const best = candidates.sort((a, b) => b.pct - a.pct)[0];
  if (!best || best.pct < 5) return null;

  if (best.label === "saves") {
    return `Saves are up ${Math.round(best.pct)}% — your audience is bookmarking this to come back to. Make more like it.`;
  }
  return `Reach is up ${Math.round(best.pct)}% this week — whatever you changed is working. Keep it going.`;
}

export function buildReadyReport(
  current: AccountSnapshot,
  previous: AccountSnapshot | null,
  options: {
    username: string | null;
    accountType: InstagramAccountType;
    source: "api" | "sample" | "manual";
    fetchedAt: string;
    dataQuality: string;
  },
): InsightsReportDTO {
  const headline: InsightMetricDTO[] = [];
  const followers = formatCount(current.followersCount);
  if (followers !== null) {
    headline.push({
      id: "followers",
      label: "Followers",
      value: followers,
      delta: formatDelta(current.followersCount, previous?.followersCount ?? null, "absolute"),
    });
  }
  const reach = formatCount(current.reach7d);
  if (reach !== null) {
    headline.push({
      id: "reach",
      label: "Reach",
      value: reach,
      delta: formatDelta(current.reach7d, previous?.reach7d ?? null, "percent"),
    });
  }
  const saves = formatCount(current.saves7d);
  if (saves !== null) {
    headline.push({
      id: "saves",
      label: "Saves",
      value: saves,
      delta: formatDelta(current.saves7d, previous?.saves7d ?? null, "percent"),
    });
  }

  return {
    connected: true,
    account_type: options.accountType,
    source: options.source,
    state: "ready",
    username: options.username,
    metrics: headline,
    detail: [],
    nudge: deriveNudge(current, previous),
    fetched_at: options.fetchedAt,
    data_quality: options.dataQuality,
  };
}

export function hasAnyMetric(snapshot: AccountSnapshot): boolean {
  return snapshot.followersCount !== null ||
    snapshot.reach7d !== null ||
    snapshot.saves7d !== null;
}

/** Picks the first Facebook Page that has a linked Instagram professional account. */
export function pickInstagramAccount(
  pages: Array<{ instagram_business_account?: { id?: string; username?: string } }>,
): { igUserID: string; username: string | null } | null {
  for (const page of pages) {
    const account = page.instagram_business_account;
    if (account?.id) return { igUserID: account.id, username: account.username ?? null };
  }
  return null;
}

// MARK: - Graph API I/O (thin wrappers; not unit-tested)

const GRAPH = `https://graph.facebook.com/${Deno.env.get("INSTAGRAM_GRAPH_VERSION") ?? "v24.0"}`;

export class InstagramPermissionError extends Error {}

/** The Facebook user has no Page with a linked Instagram professional account. */
export class InstagramAccountNotLinkedError extends Error {}

export async function exchangeCodeForTokens(args: {
  code: string;
  appID: string;
  appSecret: string;
  redirectURI: string;
}): Promise<InstagramTokens> {
  const shortURL = new URL(`${GRAPH}/oauth/access_token`);
  shortURL.searchParams.set("client_id", args.appID);
  shortURL.searchParams.set("client_secret", args.appSecret);
  shortURL.searchParams.set("redirect_uri", args.redirectURI);
  shortURL.searchParams.set("code", args.code);
  const shortRes = await fetch(shortURL);
  if (!shortRes.ok) {
    throw new Error(`facebook_code_exchange_failed:${shortRes.status}`);
  }
  const shortJSON = await shortRes.json() as { access_token?: string };
  if (!shortJSON.access_token) {
    throw new Error("facebook_code_exchange_missing_token");
  }

  // Exchange the short-lived user token for a long-lived (~60d) one. Facebook
  // user tokens can't be refreshed server-side; when one lapses, Graph returns
  // an OAuthException and the app asks the creator to reconnect.
  const longURL = new URL(`${GRAPH}/oauth/access_token`);
  longURL.searchParams.set("grant_type", "fb_exchange_token");
  longURL.searchParams.set("client_id", args.appID);
  longURL.searchParams.set("client_secret", args.appSecret);
  longURL.searchParams.set("fb_exchange_token", shortJSON.access_token);
  const longRes = await fetch(longURL);
  if (!longRes.ok) throw new Error(`facebook_long_token_failed:${longRes.status}`);
  const longJSON = await longRes.json() as { access_token?: string; expires_in?: number };
  const accessToken = longJSON.access_token ?? shortJSON.access_token;
  const expiresAt = longJSON.expires_in
    ? new Date(Date.now() + longJSON.expires_in * 1000).toISOString()
    : null;

  const account = await fetchLinkedInstagramAccount(accessToken);
  if (!account) throw new InstagramAccountNotLinkedError();

  return {
    igUserID: account.igUserID,
    accessToken,
    expiresAt,
    username: account.username,
    // Only professional (Business or Creator) accounts can be linked to a Page,
    // and Graph doesn't say which, so record the generic professional type.
    accountType: "business",
  };
}

async function fetchLinkedInstagramAccount(
  accessToken: string,
): Promise<{ igUserID: string; username: string | null } | null> {
  const url = new URL(`${GRAPH}/me/accounts`);
  url.searchParams.set("fields", "id,instagram_business_account{id,username}");
  url.searchParams.set("limit", "100");
  url.searchParams.set("access_token", accessToken);
  const res = await fetch(url);
  await throwIfPermission(res);
  if (!res.ok) throw new Error(`facebook_pages_lookup_failed:${res.status}`);
  const json = await res.json() as {
    data?: Array<{ instagram_business_account?: { id?: string; username?: string } }>;
  };
  return pickInstagramAccount(json.data ?? []);
}

/** Fetch followers + 7-day reach (+ best-effort 7-day saves). */
export async function fetchAccountSnapshot(
  igUserID: string,
  accessToken: string,
): Promise<AccountSnapshot> {
  const followersCount = await fetchFollowers(igUserID, accessToken);
  const reach7d = await fetchReach7d(igUserID, accessToken);
  const saves7d = await fetchSaves7d(igUserID, accessToken).catch(() => null);
  return { followersCount, reach7d, saves7d };
}

async function fetchFollowers(igUserID: string, accessToken: string): Promise<number | null> {
  const url = new URL(`${GRAPH}/${igUserID}`);
  url.searchParams.set("fields", "followers_count");
  url.searchParams.set("access_token", accessToken);
  const res = await fetch(url);
  await throwIfPermission(res);
  if (!res.ok) return null;
  const json = await res.json() as { followers_count?: number };
  return json.followers_count ?? null;
}

async function fetchReach7d(igUserID: string, accessToken: string): Promise<number | null> {
  const url = new URL(`${GRAPH}/${igUserID}/insights`);
  url.searchParams.set("metric", "reach");
  url.searchParams.set("period", "day");
  url.searchParams.set("metric_type", "total_value");
  const now = Math.floor(Date.now() / 1000);
  url.searchParams.set("since", String(now - 7 * 24 * 60 * 60));
  url.searchParams.set("until", String(now));
  url.searchParams.set("access_token", accessToken);
  const res = await fetch(url);
  await throwIfPermission(res);
  if (!res.ok) return null;
  const json = await res.json() as {
    data?: Array<{ total_value?: { value?: number }; values?: Array<{ value?: number }> }>;
  };
  const entry = json.data?.[0];
  if (entry?.total_value?.value !== undefined) return entry.total_value.value;
  if (entry?.values) return entry.values.reduce((sum, v) => sum + (v.value ?? 0), 0);
  return null;
}

/** Account-level "saves" does not exist; sum per-media `saved` over the last 7 days. */
async function fetchSaves7d(igUserID: string, accessToken: string): Promise<number | null> {
  const since = Math.floor(Date.now() / 1000) - 7 * 24 * 60 * 60;
  const url = new URL(`${GRAPH}/${igUserID}/media`);
  url.searchParams.set("fields", "timestamp,insights.metric(saved)");
  url.searchParams.set("since", String(since));
  url.searchParams.set("access_token", accessToken);
  const res = await fetch(url);
  if (!res.ok) return null;
  const json = await res.json() as {
    data?: Array<{ insights?: { data?: Array<{ values?: Array<{ value?: number }> }> } }>;
  };
  if (!json.data) return null;
  let total = 0;
  let sawAny = false;
  for (const media of json.data) {
    const values = media.insights?.data?.[0]?.values;
    if (values) {
      sawAny = true;
      total += values.reduce((sum, v) => sum + (v.value ?? 0), 0);
    }
  }
  return sawAny ? total : null;
}

async function throwIfPermission(res: Response): Promise<void> {
  if (res.status === 403 || res.status === 400) {
    const text = await res.clone().text();
    if (/permission|OAuthException|insufficient/i.test(text)) {
      throw new InstagramPermissionError(text.slice(0, 200));
    }
  }
}
