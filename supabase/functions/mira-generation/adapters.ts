import {
  type PlanIdeaProvider,
  resolvePlanIdeaProviders,
} from "../generate-plan-ideas/plan-ideas.ts";

type Env = { get(name: string): string | undefined };

type JsonGenerationRequest = {
  system: string;
  input: unknown;
  schema: Record<string, unknown>;
  signal: AbortSignal;
};

export interface MiraGenerationAdapter {
  generateJson(request: JsonGenerationRequest): Promise<unknown>;
}

function completionAdapter(
  provider: PlanIdeaProvider,
  model: string,
  fetchFn: typeof fetch,
): MiraGenerationAdapter {
  return {
    async generateJson({ system, input, schema, signal }) {
      const base = provider.provider === "openai"
        ? "https://api.openai.com/v1"
        : (provider.baseURL ?? "https://api.deepseek.com").replace(/\/$/, "");
      const response = await fetchFn(base + "/chat/completions", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${provider.apiKey}`,
          "Content-Type": "application/json",
        },
        signal,
        body: JSON.stringify({
          model,
          messages: [{ role: "system", content: system }, {
            role: "user",
            content: JSON.stringify(input),
          }],
          response_format: provider.provider === "openai"
            ? {
              type: "json_schema",
              json_schema: { name: "mira_artifact", strict: false, schema },
            }
            : { type: "json_object" },
          ...(provider.provider === "openai" && /^(gpt-[5-9]|o\d)/.test(model)
            ? { max_completion_tokens: 7000, reasoning_effort: "low" }
            : { max_tokens: 7000 }),
        }),
      });
      if (!response.ok) {
        if (response.status === 429 || response.status >= 500) {
          throw Error("transient_provider_error");
        }
        const detail = await response.json().catch(() => null);
        const reason = [detail?.error?.code, detail?.error?.param]
          .filter((part) => typeof part === "string" && part.length > 0)
          .map((part) => String(part).replace(/[^a-zA-Z0-9_.-]/g, "").slice(0, 60))
          .join(" ");
        throw Error(
          `provider_request_rejected ${response.status}${reason ? ` ${reason}` : ""}`,
        );
      }
      const body = await response.json();
      const content = body.choices?.[0]?.message?.content;
      if (typeof content !== "string") throw Error("invalid_provider_response");
      return JSON.parse(content);
    },
  };
}

function geminiAdapter(
  apiKey: string,
  model: string,
  fetchFn: typeof fetch,
): MiraGenerationAdapter {
  return {
    async generateJson({ system, input, signal }) {
      const response = await fetchFn(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
        {
          method: "POST",
          headers: {
            "x-goog-api-key": apiKey,
            "Content-Type": "application/json",
          },
          signal,
          body: JSON.stringify({
            systemInstruction: { parts: [{ text: system }] },
            contents: [{
              role: "user",
              parts: [{ text: JSON.stringify(input) }],
            }],
            generationConfig: {
              responseMimeType: "application/json",
              maxOutputTokens: 7000,
            },
          }),
        },
      );
      if (!response.ok) {
        throw Error(
          response.status === 429 || response.status >= 500
            ? "transient_provider_error"
            : "provider_request_rejected",
        );
      }
      const body = await response.json();
      const parts = body.candidates?.[0]?.content?.parts;
      if (!Array.isArray(parts)) throw Error("invalid_provider_response");
      const content = parts
        .map((part: unknown) => {
          if (!part || typeof part !== "object" || !("text" in part)) return "";
          return typeof part.text === "string" ? part.text : "";
        })
        .join("");
      if (!content) throw Error("invalid_provider_response");
      return JSON.parse(content);
    },
  };
}

export function resolveMiraGenerationAdapter(
  env: Env,
  fetchFn: typeof fetch = fetch,
): MiraGenerationAdapter {
  const selected = env.get("MIRA_AI_PROVIDER")?.trim().toLowerCase();
  if (selected === "gemini") {
    const apiKey = env.get("GEMINI_API_KEY")?.trim();
    const model = env.get("MIRA_GEMINI_MODEL")?.trim() ||
      env.get("MIRA_MODEL")?.trim();
    if (!apiKey || !model || !/^[a-zA-Z0-9._-]+$/.test(model)) {
      throw Error("provider_not_configured");
    }
    return geminiAdapter(apiKey, model, fetchFn);
  }
  if (selected && selected !== "openai" && selected !== "deepseek") {
    throw Error("provider_not_configured");
  }
  const providerEnv = selected
    ? {
      get: (name: string) =>
        name === "MCO_AI_PROVIDER_ORDER" ? selected : env.get(name),
    }
    : env;
  const provider = resolvePlanIdeaProviders(providerEnv)[0];
  if (!provider) throw Error("provider_not_configured");
  const model = env.get("MIRA_MODEL")?.trim() || provider.model;
  return completionAdapter(provider, model, fetchFn);
}
