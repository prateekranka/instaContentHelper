const INSTAGRAM_HOSTS = new Set([
  "instagram.com",
  "www.instagram.com",
  "m.instagram.com",
]);
const RESERVED_PROFILE_SEGMENTS = new Set([
  "about",
  "accounts",
  "audio",
  "developer",
  "direct",
  "explore",
  "p",
  "reel",
  "reels",
  "stories",
  "tv",
]);

const TRACKING_QUERY_PREFIXES = ["utm_"];
const TRACKING_QUERY_KEYS = new Set([
  "igshid",
  "fbclid",
  "gclid",
  "mc_cid",
  "mc_eid",
]);

export type InstagramURLClassification =
  | {
    kind: "story";
    url: string;
    reason: string;
  }
  | {
    kind: "profile";
    url: string;
    handle: string;
    normalizedHandle: string;
    privateLike: boolean;
  }
  | {
    kind: "reel" | "post";
    url: string;
    shortcode: string;
    canonicalKey: string;
    inferredHandle?: string | null;
  }
  | {
    kind: "audio";
    url: string;
    canonicalKey: string;
  }
  | {
    kind: "malformed_instagram";
    url: string;
  }
  | {
    kind: "non_instagram";
    url: string;
    canonicalKey: string;
  };

export function extractURLs(value: string): string[] {
  const matches = value.match(
    /(?:https?:\/\/|www\.)[^\s,;]+|(?:instagram\.com|www\.instagram\.com)\/[^\s,;]+/gi,
  );
  return (matches ?? []).map((match) => match.replace(/[)\].,]+$/g, ""));
}

export function parseURL(value: string): URL | null {
  const trimmed = value.trim();
  if (!trimmed) return null;

  const urlish = /^https?:\/\//i.test(trimmed)
    ? trimmed
    : `https://${trimmed.replace(/^\/+/, "")}`;

  try {
    return new URL(urlish);
  } catch {
    return null;
  }
}

export function normalizeURL(value: string): string | null {
  const url = parseURL(value);
  if (!url) return null;

  url.hostname = url.hostname.toLowerCase();
  url.hash = "";

  for (const key of [...url.searchParams.keys()]) {
    if (
      TRACKING_QUERY_KEYS.has(key.toLowerCase()) ||
      TRACKING_QUERY_PREFIXES.some((prefix) =>
        key.toLowerCase().startsWith(prefix)
      )
    ) {
      url.searchParams.delete(key);
    }
  }

  url.pathname = url.pathname.replace(/\/+$/g, "");
  return url.toString().replace(/\/$/g, "");
}

export function normalizeInstagramHandle(value: string): string | null {
  const trimmed = value.trim();
  if (!trimmed) return null;

  const url = parseURL(trimmed);
  if (url && isInstagramHost(url.hostname)) {
    const segments = pathSegments(url);
    if (
      segments.length === 1 &&
      !RESERVED_PROFILE_SEGMENTS.has(segments[0].toLowerCase())
    ) {
      return normalizePlainHandle(segments[0]);
    }
    return null;
  }

  return normalizePlainHandle(trimmed);
}

export function normalizePlainHandle(value: string): string | null {
  const handle = value
    .trim()
    .replace(/^@+/, "")
    .replace(/\/+$/g, "")
    .toLowerCase();

  if (!/^[a-z0-9._]{2,30}$/.test(handle)) {
    return null;
  }

  if (!/[a-z]/.test(handle)) {
    return null;
  }

  if (RESERVED_PROFILE_SEGMENTS.has(handle)) {
    return null;
  }

  return handle;
}

export function extractHandleTokens(value: string): string[] {
  const handles = new Set<string>();

  for (const match of value.matchAll(/(^|[\s,(])@([A-Za-z0-9._]{2,30})\b/g)) {
    const normalized = normalizePlainHandle(match[2]);
    if (normalized) {
      handles.add(normalized);
    }
  }

  return [...handles];
}

export function classifyURL(value: string): InstagramURLClassification {
  const normalized = normalizeURL(value) ?? value.trim();
  const url = parseURL(normalized);

  if (!url) {
    return { kind: "malformed_instagram", url: value.trim() };
  }

  if (!isInstagramHost(url.hostname)) {
    return { kind: "non_instagram", url: normalized, canonicalKey: normalized };
  }

  const segments = pathSegments(url);
  if (segments.length === 0) {
    return { kind: "malformed_instagram", url: normalized };
  }

  if (segments[0].toLowerCase() === "stories") {
    return {
      kind: "story",
      url: normalized,
      reason: "Story URLs can't be used as references.",
    };
  }

  const audioIndex = segments.findIndex((segment) =>
    segment.toLowerCase() === "audio"
  );
  if (
    audioIndex >= 0 ||
    segments.some((segment) => segment.toLowerCase() === "music")
  ) {
    return {
      kind: "audio",
      url: normalized,
      canonicalKey: normalized,
    };
  }

  for (let index = 0; index < segments.length - 1; index += 1) {
    const segment = segments[index].toLowerCase();
    if (segment === "reel" || segment === "reels" || segment === "p") {
      const shortcode = segments[index + 1];
      if (
        !shortcode || RESERVED_PROFILE_SEGMENTS.has(shortcode.toLowerCase())
      ) {
        return { kind: "malformed_instagram", url: normalized };
      }

      const kind = segment === "p" ? "post" : "reel";
      const maybeHandle = index > 0
        ? normalizePlainHandle(segments[index - 1])
        : null;
      return {
        kind,
        url: normalized,
        shortcode,
        canonicalKey: `instagram:${kind}:${shortcode}`,
        inferredHandle: maybeHandle,
      };
    }
  }

  if (segments.length === 1) {
    const handle = normalizePlainHandle(segments[0]);
    if (handle) {
      return {
        kind: "profile",
        url: normalized,
        handle: `@${handle}`,
        normalizedHandle: handle,
        privateLike: true,
      };
    }
  }

  return { kind: "malformed_instagram", url: normalized };
}

export function displayHandle(normalizedHandle: string): string {
  return `@${normalizedHandle}`;
}

function isInstagramHost(hostname: string): boolean {
  return INSTAGRAM_HOSTS.has(hostname.toLowerCase());
}

function pathSegments(url: URL): string[] {
  return url.pathname
    .split("/")
    .map((segment) => segment.trim())
    .filter(Boolean)
    .map((segment) => decodeURIComponent(segment));
}
