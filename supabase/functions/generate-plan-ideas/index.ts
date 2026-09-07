// deno-lint-ignore-file no-explicit-any
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  CONTENT_CREATOR_ROLES,
  corsHeaders,
  jsonResponse,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";
import {
  buildPlanIdeasPrompt,
  callDeepSeekPlanIdeas,
  callOpenAIPlanIdeas,
  mockPlanIdeas,
  normalizePlanIdeaInput,
  normalizePlanIdeas,
  resolvePlanIdeaProviders,
  resolvePlanIdeasTimeoutMs,
  type PlanIdeaInput,
  type PlanIdeaProvider,
} from "./plan-ideas.ts";

type GeneratePlanIdeasRequest = {
  creator_id?: string;
  scheduled_date?: string;
  content_pillars?: string[];
  voice_configured?: boolean;
  reference_count?: number;
  positioning?: string;
  voice_rules?: string | string[];
  caption_style?: string;
  no_go_topics?: string | string[];
  reference_labels?: string[];
  mock?: boolean;
};

type EnvLike = { get: (name: string) => string | undefined };

type Dependencies = {
  env?: EnvLike;
  createAdminClient?: (url: string, key: string) => any;
  verifySession?: typeof verifyDeviceSession;
  fetchFn?: typeof fetch;
  callProviders?: (
    input: PlanIdeaInput,
    providers: PlanIdeaProvider[],
    fetchFn: typeof fetch,
    timeoutMS: number,
  ) => Promise<{ ideas: ReturnType<typeof normalizePlanIdeas>; model: string }>;
};

export async function handleGeneratePlanIdeasRequest(
  request: Request,
  dependencies: Dependencies = {},
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const env = dependencies.env ?? Deno.env;
  const supabaseURL = env.get("SUPABASE_URL");
  const serviceRoleKey = env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) {
    return jsonResponse({ error: "missing_function_secrets" }, 500);
  }

  const createAdminClient = dependencies.createAdminClient ??
    ((url, key) =>
      createClient(url, key, {
        auth: { persistSession: false, autoRefreshToken: false },
      }));
  const admin = createAdminClient(supabaseURL, serviceRoleKey);
  const authResult = await (dependencies.verifySession ?? verifyDeviceSession)(
    request,
    admin,
    [...CONTENT_CREATOR_ROLES],
  );
  if ("response" in authResult) {
    return authResult.response;
  }

  let body: GeneratePlanIdeasRequest;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const scheduledDate = body.scheduled_date?.trim() ?? "";
  if (!/^\d{4}-\d{2}-\d{2}$/.test(scheduledDate)) {
    return jsonResponse({ error: "invalid_scheduled_date" }, 400);
  }

  const creatorID = body.creator_id?.trim();
  if (creatorID) {
    const { data: creator, error: creatorError } = await admin
      .from("creators")
      .select("id")
      .eq("id", creatorID)
      .eq("workspace_id", authResult.session.workspaceID)
      .eq("status", "active")
      .maybeSingle();
    if (creatorError) {
      return jsonResponse({ error: "creator_lookup_failed" }, 500);
    }
    if (!creator) {
      return jsonResponse({ error: "creator_not_found" }, 404);
    }
  }

  const input = normalizePlanIdeaInput({
    scheduledDate,
    contentPillars: body.content_pillars,
    voiceConfigured: body.voice_configured,
    referenceCount: body.reference_count,
    positioning: body.positioning,
    voiceRules: body.voice_rules,
    captionStyle: body.caption_style,
    noGoTopics: body.no_go_topics,
    referenceLabels: body.reference_labels,
  });

  const allowMock = env.get("MCO_AI_MOCK") === "1" ||
    (body.mock === true && env.get("MCO_ALLOW_AI_MOCK_REQUEST") === "1");
  if (allowMock) {
    return jsonResponse({
      scheduled_date: scheduledDate,
      source: "mock",
      ideas: mockPlanIdeas(input),
    });
  }

  const providers = resolvePlanIdeaProviders(env);
  if (providers.length === 0) {
    return jsonResponse({ error: "missing_openai_api_key" }, 500);
  }

  const fetchFn = dependencies.fetchFn ?? fetch;
  const callProviders = dependencies.callProviders ?? defaultCallProviders;
  const timeoutMS = resolvePlanIdeasTimeoutMs(
    env.get("MCO_AI_PLAN_IDEAS_TIMEOUT_MS")?.trim(),
  );

  try {
    const result = await callProviders(input, providers, fetchFn, timeoutMS);
    return jsonResponse({
      scheduled_date: scheduledDate,
      source: "llm",
      model: result.model,
      ideas: result.ideas,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const status = message.startsWith("deepseek_request_failed") ||
        message.startsWith("openai_request_failed") ||
        message.startsWith("ai_provider_request_failed")
      ? 502
      : 400;
    return jsonResponse({
      error: message.startsWith("deepseek_request_failed") ||
          message.startsWith("openai_request_failed") ||
          message.startsWith("ai_provider_request_failed")
        ? "openai_request_failed"
        : message.startsWith("invalid_ai_json")
        ? "invalid_ai_json"
        : "plan_ideas_generation_failed",
      details: message,
    }, status);
  }
}

async function defaultCallProviders(
  input: PlanIdeaInput,
  providers: PlanIdeaProvider[],
  fetchFn: typeof fetch,
  timeoutMS: number,
): Promise<{ ideas: ReturnType<typeof normalizePlanIdeas>; model: string }> {
  let lastError: unknown;
  for (const provider of providers) {
    try {
      const raw = provider.provider === "deepseek"
        ? await callDeepSeekPlanIdeas(input, provider, fetchFn, timeoutMS)
        : await callOpenAIPlanIdeas(input, provider, fetchFn, timeoutMS);
      const ideas = normalizePlanIdeas(raw, input);
      if (ideas.length < 5) {
        throw new Error("invalid_ai_json:expected_five_ideas");
      }
      return {
        ideas,
        model: `${provider.provider}:${provider.model}`,
      };
    } catch (error) {
      lastError = error;
      // Do not chain a second full timeout after a provider timeout — that would
      // blow the <60s p95 budget. Quick failures (auth/4xx) may still fall through.
      const message = error instanceof Error ? error.message : String(error);
      if (message.includes(":timeout:")) {
        break;
      }
    }
  }
  throw lastError instanceof Error
    ? lastError
    : new Error("plan_ideas_generation_failed");
}

// Re-export for tests that import the prompt builder alongside the handler.
export { buildPlanIdeasPrompt };

if (import.meta.main) {
  Deno.serve((request) => handleGeneratePlanIdeasRequest(request));
}
