export type PlanIdeaInput = {
  scheduledDate: string;
  contentPillars: string[];
  voiceConfigured: boolean;
  referenceCount: number;
  positioning?: string;
  voiceRules?: string;
  captionStyle?: string;
  noGoTopics?: string;
  referenceLabels?: string[];
};

export type PlanIdeaDTO = {
  title: string;
  day_brief: string;
};

export type PlanIdeaProviderName = "deepseek" | "openai";

export type PlanIdeaProvider = {
  provider: PlanIdeaProviderName;
  model: string;
  apiKey: string;
  baseURL?: string;
};

type EnvLike = { get: (name: string) => string | undefined };

/** Flash-first for plan-idea latency (same default as day generation). */
const DEFAULT_DEEPSEEK_MODEL = "deepseek-v4-flash";
const DEFAULT_OPENAI_MODEL = "gpt-4.1-mini";
const DEFAULT_DEEPSEEK_BASE_URL = "https://api.deepseek.com";
const IDEA_COUNT = 5;

/** Tight output budget: 5 short one-liners + day_brief cues. */
export const PLAN_IDEAS_MAX_TOKENS = 500;

/**
 * Provider request timeout. Keep well under the 60s p95 UX budget so cold start
 * + network + fallback still fit. Override with MCO_AI_PLAN_IDEAS_TIMEOUT_MS.
 */
export const DEFAULT_PLAN_IDEAS_TIMEOUT_MS = 40_000;
const MIN_PLAN_IDEAS_TIMEOUT_MS = 5_000;
const MAX_PLAN_IDEAS_TIMEOUT_MS = 55_000;

/** Input truncation caps — keep prompts small for latency. */
export const PLAN_IDEA_INPUT_LIMITS = {
  positioningChars: 400,
  voiceRulesChars: 400,
  captionStyleChars: 200,
  noGoTopicsChars: 200,
  maxReferenceLabels: 10,
  referenceLabelChars: 80,
  maxPillars: 12,
  pillarChars: 60,
} as const;

const FORMAT_HINTS = [
  "POV Reel",
  "GRWM Reel",
  "Listicle Reel",
  "Myth vs reality",
  "Hot take Reel",
  "Day in the life",
  "Before / after",
  "Soft life Reel",
  "Ranking Reel",
  "Wish I knew",
];

export function resolvePlanIdeaProviders(env: EnvLike): PlanIdeaProvider[] {
  const deepSeekKey = env.get("DEEPSEEK_API_KEY")?.trim();
  const openAIKey = env.get("OPENAI_API_KEY")?.trim();
  const deepSeekModel = env.get("MCO_DEEPSEEK_MODEL")?.trim() ||
    DEFAULT_DEEPSEEK_MODEL;
  const openAIModel = env.get("MCO_OPENAI_MODEL")?.trim() ||
    DEFAULT_OPENAI_MODEL;
  const deepSeekBaseURL = env.get("MCO_DEEPSEEK_BASE_URL")?.trim() ||
    DEFAULT_DEEPSEEK_BASE_URL;

  const byName: Record<string, PlanIdeaProvider | undefined> = {
    deepseek: deepSeekKey
      ? {
        provider: "deepseek",
        model: deepSeekModel,
        apiKey: deepSeekKey,
        baseURL: deepSeekBaseURL,
      }
      : undefined,
    openai: openAIKey
      ? { provider: "openai", model: openAIModel, apiKey: openAIKey }
      : undefined,
  };

  const order = (env.get("MCO_AI_PROVIDER_ORDER") ?? "deepseek,openai")
    .split(",")
    .map((value) => value.trim().toLowerCase())
    .filter(Boolean);

  const providers: PlanIdeaProvider[] = [];
  for (const name of order) {
    const provider = byName[name];
    if (provider && !providers.some((item) => item.provider === provider.provider)) {
      providers.push(provider);
    }
  }
  return providers;
}

export function resolvePlanIdeasTimeoutMs(
  configured: string | undefined,
): number {
  if (!configured) return DEFAULT_PLAN_IDEAS_TIMEOUT_MS;
  const parsed = Number(configured);
  if (!Number.isFinite(parsed) || parsed < MIN_PLAN_IDEAS_TIMEOUT_MS) {
    return DEFAULT_PLAN_IDEAS_TIMEOUT_MS;
  }
  return Math.min(parsed, MAX_PLAN_IDEAS_TIMEOUT_MS);
}

export function truncateText(
  value: string | undefined | null,
  maxChars: number,
): string {
  if (!value) return "";
  const collapsed = value.replace(/\s+/g, " ").trim();
  if (!collapsed) return "";
  if (collapsed.length <= maxChars) return collapsed;
  return collapsed.slice(0, maxChars).trimEnd();
}

export function truncateLabelList(
  labels: unknown,
  maxCount: number,
  maxChars: number,
): string[] {
  if (!Array.isArray(labels)) return [];
  const out: string[] = [];
  const seen = new Set<string>();
  for (const raw of labels) {
    const label = truncateText(String(raw ?? ""), maxChars);
    if (!label) continue;
    const key = label.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(label);
    if (out.length >= maxCount) break;
  }
  return out;
}

/** Normalize + truncate client payload before prompting. */
export function normalizePlanIdeaInput(raw: {
  scheduledDate: string;
  contentPillars?: unknown;
  voiceConfigured?: unknown;
  referenceCount?: unknown;
  positioning?: unknown;
  voiceRules?: unknown;
  captionStyle?: unknown;
  noGoTopics?: unknown;
  referenceLabels?: unknown;
}): PlanIdeaInput {
  const limits = PLAN_IDEA_INPUT_LIMITS;
  const pillars = Array.isArray(raw.contentPillars)
    ? raw.contentPillars
      .map((value) => truncateText(String(value), limits.pillarChars))
      .filter(Boolean)
      .slice(0, limits.maxPillars)
    : [];

  const voiceRules = typeof raw.voiceRules === "string"
    ? truncateText(raw.voiceRules, limits.voiceRulesChars)
    : Array.isArray(raw.voiceRules)
    ? truncateText(
      raw.voiceRules.map((v) => String(v).trim()).filter(Boolean).join("; "),
      limits.voiceRulesChars,
    )
    : "";

  const noGoTopics = typeof raw.noGoTopics === "string"
    ? truncateText(raw.noGoTopics, limits.noGoTopicsChars)
    : Array.isArray(raw.noGoTopics)
    ? truncateText(
      raw.noGoTopics.map((v) => String(v).trim()).filter(Boolean).join("; "),
      limits.noGoTopicsChars,
    )
    : "";

  const referenceLabels = truncateLabelList(
    raw.referenceLabels,
    limits.maxReferenceLabels,
    limits.referenceLabelChars,
  );

  return {
    scheduledDate: raw.scheduledDate,
    contentPillars: pillars,
    voiceConfigured: Boolean(raw.voiceConfigured),
    referenceCount: Math.max(
      0,
      Number(raw.referenceCount ?? referenceLabels.length) || 0,
    ),
    positioning: truncateText(
      typeof raw.positioning === "string" ? raw.positioning : "",
      limits.positioningChars,
    ),
    voiceRules,
    captionStyle: truncateText(
      typeof raw.captionStyle === "string" ? raw.captionStyle : "",
      limits.captionStyleChars,
    ),
    noGoTopics,
    referenceLabels,
  };
}

export function weekdayName(scheduledDate: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(scheduledDate);
  if (!match) return "today";
  const date = new Date(
    Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])),
  );
  return new Intl.DateTimeFormat("en-GB", {
    weekday: "long",
    timeZone: "UTC",
  }).format(date);
}

export function buildPlanIdeasPrompt(input: PlanIdeaInput): {
  system: string;
  user: string;
} {
  const pillars = input.contentPillars.length > 0
    ? input.contentPillars.join(", ")
    : "your niche";
  const weekday = weekdayName(input.scheduledDate);
  const positioning = input.positioning?.trim() ?? "";
  const voiceRules = input.voiceRules?.trim() ?? "";
  const captionStyle = input.captionStyle?.trim() ?? "";
  const noGoTopics = input.noGoTopics?.trim() ?? "";
  const labels = input.referenceLabels ?? [];

  const voiceLines: string[] = [];
  if (positioning) voiceLines.push(`Positioning: ${positioning}`);
  if (voiceRules) voiceLines.push(`Voice rules: ${voiceRules}`);
  if (captionStyle) voiceLines.push(`Caption style: ${captionStyle}`);
  if (noGoTopics) voiceLines.push(`No-go topics: ${noGoTopics}`);
  if (voiceLines.length === 0) {
    voiceLines.push(
      input.voiceConfigured
        ? "Voice is configured — keep phrasing conversational and first-person."
        : "Voice is not configured — keep phrasing natural but generic.",
    );
  }

  const refsBit = labels.length > 0
    ? `Confirmed reference labels (echo pacing/format vibes only, do not invent insights): ${
      labels.join("; ")
    }.`
    : input.referenceCount > 0
    ? `Creator has ${input.referenceCount} confirmed Instagram references — echo current Reel pacing without inventing insights data.`
    : "No confirmed references — lean on current Instagram Reel formats.";

  return {
    system: [
      "You invent Instagram Reel day ideas for a creator content planner.",
      "Return JSON only: {\"ideas\":[{\"title\":\"...\",\"day_brief\":\"...\"}]} with exactly 5 ideas.",
      "Each title must be one succinct one-liner (no line breaks, no subheads, under 90 characters).",
      "Vary formats across POV, GRWM, listicle, myth vs reality, hot take, day-in-the-life, before/after, ranking, and similar current Reel patterns.",
      "Personalize with the creator's content pillars and voice text when provided. Do not invent biography, brands, or metrics.",
      "Respect no-go topics: never pitch those themes.",
      "day_brief should be the generation brief for that idea: usually the title plus a short format cue.",
      "No hashtags, no emojis, no markdown.",
    ].join(" "),
    user: [
      `Scheduled date: ${input.scheduledDate} (${weekday}).`,
      `Content pillars: ${pillars}.`,
      ...voiceLines,
      refsBit,
      "Produce 5 fresh, trend-informed idea one-liners for this day only.",
    ].join("\n"),
  };
}

export function mockPlanIdeas(input: PlanIdeaInput): PlanIdeaDTO[] {
  const pillars = input.contentPillars.length > 0
    ? input.contentPillars
    : ["your niche"];
  const weekday = weekdayName(input.scheduledDate);
  return Array.from({ length: IDEA_COUNT }, (_, index) => {
    const pillar = pillars[index % pillars.length];
    const format = FORMAT_HINTS[index % FORMAT_HINTS.length];
    const title = `${format}: ${pillar} on ${weekday}`;
    return {
      title,
      day_brief: `${title}. ${format}`,
    };
  });
}

export function normalizePlanIdeas(
  raw: unknown,
  input: PlanIdeaInput,
): PlanIdeaDTO[] {
  const ideas = extractIdeasArray(raw)
    .map((item) => normalizeOneIdea(item))
    .filter((item): item is PlanIdeaDTO => item !== null);

  const unique: PlanIdeaDTO[] = [];
  const seen = new Set<string>();
  for (const idea of ideas) {
    const key = idea.title.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(idea);
    if (unique.length === IDEA_COUNT) break;
  }

  if (unique.length === IDEA_COUNT) {
    return unique;
  }

  const fallback = mockPlanIdeas(input);
  for (const idea of fallback) {
    const key = idea.title.toLowerCase();
    if (seen.has(key)) continue;
    unique.push(idea);
    seen.add(key);
    if (unique.length === IDEA_COUNT) break;
  }
  return unique.slice(0, IDEA_COUNT);
}

function extractIdeasArray(raw: unknown): unknown[] {
  if (Array.isArray(raw)) return raw;
  if (!isRecord(raw)) return [];
  if (Array.isArray(raw.ideas)) return raw.ideas;
  if (isRecord(raw.ideas) && Array.isArray(raw.ideas.items)) {
    return raw.ideas.items;
  }
  return [];
}

function normalizeOneIdea(raw: unknown): PlanIdeaDTO | null {
  if (typeof raw === "string") {
    const title = collapseOneLiner(raw);
    if (!title) return null;
    return { title, day_brief: title };
  }
  if (!isRecord(raw)) return null;
  const title = collapseOneLiner(
    stringValue(raw.title) ?? stringValue(raw.idea) ?? stringValue(raw.text),
  );
  if (!title) return null;
  const dayBrief = collapseOneLiner(
    stringValue(raw.day_brief) ??
      stringValue(raw.dayBrief) ??
      stringValue(raw.brief),
  ) ?? title;
  return { title, day_brief: dayBrief };
}

function collapseOneLiner(value: string | null | undefined): string | null {
  if (!value) return null;
  const collapsed = value.replace(/\s+/g, " ").trim();
  if (!collapsed) return null;
  return collapsed.slice(0, 120);
}

async function fetchWithTimeout(
  url: string,
  init: RequestInit,
  timeoutMS: number,
  fetchFn: typeof fetch,
): Promise<Response> {
  const controller = new AbortController();
  const timeoutID = setTimeout(() => controller.abort(), timeoutMS);
  try {
    return await fetchFn(url, {
      ...init,
      signal: controller.signal,
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new Error(`ai_provider_request_failed:timeout:${timeoutMS}`);
    }
    throw error;
  } finally {
    clearTimeout(timeoutID);
  }
}

export async function callDeepSeekPlanIdeas(
  input: PlanIdeaInput,
  provider: PlanIdeaProvider,
  fetchFn: typeof fetch = fetch,
  timeoutMS: number = DEFAULT_PLAN_IDEAS_TIMEOUT_MS,
): Promise<unknown> {
  const prompt = buildPlanIdeasPrompt(input);
  const baseURL = (provider.baseURL ?? DEFAULT_DEEPSEEK_BASE_URL).replace(
    /\/+$/,
    "",
  );
  const response = await fetchWithTimeout(
    `${baseURL}/chat/completions`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${provider.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: provider.model,
        messages: [
          { role: "system", content: prompt.system },
          {
            role: "user",
            content: `${prompt.user}\nReturn one valid JSON object only.`,
          },
        ],
        response_format: { type: "json_object" },
        temperature: 0.7,
        max_tokens: PLAN_IDEAS_MAX_TOKENS,
      }),
    },
    timeoutMS,
    fetchFn,
  );
  if (!response.ok) {
    throw new Error(`deepseek_request_failed:${response.status}`);
  }
  const json = await response.json();
  const text = extractChatCompletionOutputText(json);
  if (!text) {
    throw new Error("invalid_ai_json:empty_deepseek_content");
  }
  return parseJSONObject(text);
}

export async function callOpenAIPlanIdeas(
  input: PlanIdeaInput,
  provider: PlanIdeaProvider,
  fetchFn: typeof fetch = fetch,
  timeoutMS: number = DEFAULT_PLAN_IDEAS_TIMEOUT_MS,
): Promise<unknown> {
  const prompt = buildPlanIdeasPrompt(input);
  const response = await fetchWithTimeout(
    "https://api.openai.com/v1/responses",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${provider.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: provider.model,
        input: [
          { role: "system", content: prompt.system },
          {
            role: "user",
            content: `${prompt.user}\nReturn one valid JSON object only.`,
          },
        ],
        text: { format: { type: "json_object" } },
        temperature: 0.7,
        max_output_tokens: PLAN_IDEAS_MAX_TOKENS,
      }),
    },
    timeoutMS,
    fetchFn,
  );
  if (!response.ok) {
    throw new Error(`openai_request_failed:${response.status}`);
  }
  const json = await response.json();
  const text = extractOpenAIOutputText(json);
  if (!text) {
    throw new Error("invalid_ai_json:empty_openai_content");
  }
  return parseJSONObject(text);
}

function parseJSONObject(text: string): unknown {
  const trimmed = text.trim().replace(/^```(?:json)?/i, "").replace(/```$/, "")
    .trim();
  try {
    return JSON.parse(trimmed);
  } catch {
    throw new Error("invalid_ai_json:parse_failed");
  }
}

function extractChatCompletionOutputText(response: unknown): string | null {
  if (!isRecord(response) || !Array.isArray(response.choices)) return null;
  for (const choice of response.choices) {
    if (!isRecord(choice) || !isRecord(choice.message)) continue;
    const content = stringValue(choice.message.content);
    if (content) return content;
  }
  return null;
}

function extractOpenAIOutputText(response: unknown): string | null {
  if (!isRecord(response)) return null;
  const direct = stringValue(response.output_text);
  if (direct) return direct;
  if (!Array.isArray(response.output)) return null;
  const parts: string[] = [];
  for (const item of response.output) {
    if (!isRecord(item) || !Array.isArray(item.content)) continue;
    for (const content of item.content) {
      if (!isRecord(content)) continue;
      const text = stringValue(content.text);
      if (text) parts.push(text);
    }
  }
  return parts.length > 0 ? parts.join("\n") : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}
