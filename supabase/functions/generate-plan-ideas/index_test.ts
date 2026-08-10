import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildPlanIdeasPrompt,
  DEFAULT_PLAN_IDEAS_TIMEOUT_MS,
  mockPlanIdeas,
  normalizePlanIdeaInput,
  normalizePlanIdeas,
  PLAN_IDEA_INPUT_LIMITS,
  PLAN_IDEAS_MAX_TOKENS,
  resolvePlanIdeaProviders,
  resolvePlanIdeasTimeoutMs,
  truncateText,
  weekdayName,
} from "./plan-ideas.ts";
import { handleGeneratePlanIdeasRequest } from "./index.ts";

Deno.test("weekdayName uses UTC calendar date", () => {
  assertEquals(weekdayName("2026-08-12"), "Wednesday");
});

Deno.test("buildPlanIdeasPrompt personalizes pillars and date", () => {
  const prompt = buildPlanIdeasPrompt({
    scheduledDate: "2026-08-12",
    contentPillars: ["gym", "recovery"],
    voiceConfigured: true,
    referenceCount: 2,
  });
  assertStringIncludes(prompt.user, "2026-08-12");
  assertStringIncludes(prompt.user, "Wednesday");
  assertStringIncludes(prompt.user, "gym, recovery");
  assertStringIncludes(prompt.system, "exactly 5 ideas");
});

Deno.test("buildPlanIdeasPrompt includes voice text and reference labels", () => {
  const prompt = buildPlanIdeasPrompt({
    scheduledDate: "2026-08-12",
    contentPillars: ["gym"],
    voiceConfigured: true,
    referenceCount: 2,
    positioning: "Warm fitness creator for busy parents",
    voiceRules: "Conversational; Warm; Self-aware",
    captionStyle: "Short sharp lines",
    noGoTopics: "Politics; Weight talk",
    referenceLabels: ["Calm Drive", "Gym mirror format"],
  });
  assertStringIncludes(prompt.user, "Positioning: Warm fitness creator");
  assertStringIncludes(prompt.user, "Voice rules: Conversational");
  assertStringIncludes(prompt.user, "Caption style: Short sharp lines");
  assertStringIncludes(prompt.user, "No-go topics: Politics");
  assertStringIncludes(prompt.user, "Calm Drive");
  assertStringIncludes(prompt.user, "Gym mirror format");
  assertStringIncludes(prompt.system, "Respect no-go topics");
});

Deno.test("normalizePlanIdeaInput truncates voice and reference labels", () => {
  const long = "x".repeat(800);
  const labels = Array.from({ length: 20 }, (_, i) => `Label ${i} ${"y".repeat(100)}`);
  const input = normalizePlanIdeaInput({
    scheduledDate: "2026-08-12",
    contentPillars: ["gym"],
    voiceConfigured: true,
    referenceCount: 20,
    positioning: long,
    voiceRules: long,
    captionStyle: long,
    noGoTopics: ["Politics", long],
    referenceLabels: labels,
  });
  assertEquals(
    input.positioning?.length,
    PLAN_IDEA_INPUT_LIMITS.positioningChars,
  );
  assertEquals(
    input.voiceRules?.length,
    PLAN_IDEA_INPUT_LIMITS.voiceRulesChars,
  );
  assertEquals(
    input.captionStyle?.length,
    PLAN_IDEA_INPUT_LIMITS.captionStyleChars,
  );
  assertEquals(
    (input.noGoTopics?.length ?? 0) <= PLAN_IDEA_INPUT_LIMITS.noGoTopicsChars,
    true,
  );
  assertEquals(
    input.referenceLabels?.length,
    PLAN_IDEA_INPUT_LIMITS.maxReferenceLabels,
  );
  assertEquals(
    input.referenceLabels?.every((label) =>
      label.length <= PLAN_IDEA_INPUT_LIMITS.referenceLabelChars
    ),
    true,
  );
});

Deno.test("truncateText collapses whitespace and caps length", () => {
  assertEquals(truncateText("  hello   world  ", 20), "hello world");
  assertEquals(truncateText("abcdef", 3), "abc");
});

Deno.test("resolvePlanIdeasTimeoutMs defaults and caps for p95 budget", () => {
  assertEquals(resolvePlanIdeasTimeoutMs(undefined), DEFAULT_PLAN_IDEAS_TIMEOUT_MS);
  assertEquals(resolvePlanIdeasTimeoutMs("2000"), DEFAULT_PLAN_IDEAS_TIMEOUT_MS);
  assertEquals(resolvePlanIdeasTimeoutMs("45000"), 45_000);
  assertEquals(resolvePlanIdeasTimeoutMs("120000"), 55_000);
  assertEquals(PLAN_IDEAS_MAX_TOKENS, 500);
  assertEquals(DEFAULT_PLAN_IDEAS_TIMEOUT_MS <= 55_000, true);
});

Deno.test("normalizePlanIdeas accepts title/day_brief objects", () => {
  const ideas = normalizePlanIdeas({
    ideas: [
      { title: "POV: gym mornings", day_brief: "POV: gym mornings. POV Reel" },
      { title: "GRWM recovery", day_brief: "GRWM recovery" },
      { title: "3 gym mistakes", day_brief: "3 gym mistakes" },
      { title: "Myth vs reality recovery", day_brief: "Myth vs reality recovery" },
      { title: "Hot take on gym rest", day_brief: "Hot take on gym rest" },
    ],
  }, {
    scheduledDate: "2026-08-12",
    contentPillars: ["gym"],
    voiceConfigured: false,
    referenceCount: 0,
  });
  assertEquals(ideas.length, 5);
  assertEquals(ideas[0].title, "POV: gym mornings");
  assertStringIncludes(ideas[0].day_brief, "POV: gym mornings");
});

Deno.test("normalizePlanIdeas fills missing slots from mock fallback", () => {
  const ideas = normalizePlanIdeas({
    ideas: [{ title: "Only one idea" }],
  }, {
    scheduledDate: "2026-08-12",
    contentPillars: ["food"],
    voiceConfigured: false,
    referenceCount: 0,
  });
  assertEquals(ideas.length, 5);
  assertEquals(ideas[0].title, "Only one idea");
  assertEquals(ideas.every((idea) => idea.title.trim().length > 0), true);
});

Deno.test("resolvePlanIdeaProviders prefers DeepSeek then OpenAI", () => {
  const providers = resolvePlanIdeaProviders({
    get(name) {
      const values: Record<string, string> = {
        DEEPSEEK_API_KEY: "deepseek-key",
        OPENAI_API_KEY: "openai-key",
      };
      return values[name];
    },
  });
  assertEquals(providers.map((item) => item.provider), ["deepseek", "openai"]);
});

Deno.test("mockPlanIdeas returns five deterministic one-liners", () => {
  const ideas = mockPlanIdeas({
    scheduledDate: "2026-08-12",
    contentPillars: ["lifestyle"],
    voiceConfigured: true,
    referenceCount: 1,
  });
  assertEquals(ideas.length, 5);
  assertEquals(new Set(ideas.map((idea) => idea.title)).size, 5);
});

Deno.test("handleGeneratePlanIdeasRequest returns mock ideas when MCO_AI_MOCK=1", async () => {
  const response = await handleGeneratePlanIdeasRequest(
    new Request("http://localhost/functions/v1/generate-plan-ideas", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        scheduled_date: "2026-08-12",
        content_pillars: ["gym"],
        voice_configured: true,
        reference_count: 1,
        positioning: "Warm gym creator",
        voice_rules: "Conversational",
        caption_style: "Short",
        no_go_topics: "Politics",
        reference_labels: ["Calm Drive"],
      }),
    }),
    {
      env: {
        get(name) {
          const values: Record<string, string> = {
            SUPABASE_URL: "http://localhost:54321",
            SUPABASE_SERVICE_ROLE_KEY: "service-role",
            MCO_AI_MOCK: "1",
          };
          return values[name];
        },
      },
      createAdminClient: () => ({}),
      verifySession: async () => ({
        session: {
          deviceInstallationID: "device",
          workspaceID: "workspace",
          memberID: "member",
          role: "creator",
        },
      }),
    },
  );

  assertEquals(response.status, 200);
  const json = await response.json();
  assertEquals(json.source, "mock");
  assertEquals(json.ideas.length, 5);
  assertEquals(json.scheduled_date, "2026-08-12");
});

Deno.test("handleGeneratePlanIdeasRequest rejects invalid date", async () => {
  const response = await handleGeneratePlanIdeasRequest(
    new Request("http://localhost/functions/v1/generate-plan-ideas", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ scheduled_date: "not-a-date" }),
    }),
    {
      env: {
        get(name) {
          const values: Record<string, string> = {
            SUPABASE_URL: "http://localhost:54321",
            SUPABASE_SERVICE_ROLE_KEY: "service-role",
          };
          return values[name];
        },
      },
      createAdminClient: () => ({}),
      verifySession: async () => ({
        session: {
          deviceInstallationID: "device",
          workspaceID: "workspace",
          memberID: "member",
          role: "creator",
        },
      }),
    },
  );
  assertEquals(response.status, 400);
  const json = await response.json();
  assertEquals(json.error, "invalid_scheduled_date");
});
