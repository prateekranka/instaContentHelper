// deno-lint-ignore-file no-explicit-any
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  corsHeaders,
  jsonResponse,
  verifyDeviceSession,
} from "../_shared/device-auth.ts";

type RuntimeHealthDependencies = {
  env?: { get: (name: string) => string | undefined };
  createAdminClient?: (url: string, key: string) => any;
  verifySession?: typeof verifyDeviceSession;
  fetchFn?: typeof fetch;
  now?: () => Date;
};

type ServiceProbe = {
  ok: boolean;
  latency_ms: number;
  detail?: string;
};

export async function handleRuntimeHealthRequest(
  request: Request,
  dependencies: RuntimeHealthDependencies = {},
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
    ["owner", "editor", "creator", "scout"],
  );
  if ("response" in authResult) {
    return authResult.response;
  }

  const fetchFn = dependencies.fetchFn ?? fetch;
  const checkedAt = (dependencies.now?.() ?? new Date()).toISOString();

  const [supabase, gemini] = await Promise.all([
    probeSupabase(admin),
    probeGemini(env, fetchFn),
  ]);

  return jsonResponse({
    checked_at: checkedAt,
    supabase,
    gemini,
  });
}

async function probeSupabase(admin: any): Promise<ServiceProbe> {
  const started = performance.now();
  try {
    const { error } = await admin
      .from("workspaces")
      .select("id")
      .limit(1);
    const latency = Math.round(performance.now() - started);
    if (error) {
      return {
        ok: false,
        latency_ms: latency,
        detail: error.message ?? "supabase_query_failed",
      };
    }
    return { ok: true, latency_ms: latency };
  } catch (error) {
    return {
      ok: false,
      latency_ms: Math.round(performance.now() - started),
      detail: error instanceof Error ? error.message : "supabase_probe_failed",
    };
  }
}

async function probeGemini(
  env: { get: (name: string) => string | undefined },
  fetchFn: typeof fetch,
): Promise<ServiceProbe> {
  const started = performance.now();
  const geminiAPIKey = env.get("GEMINI_API_KEY")?.trim();
  if (!geminiAPIKey) {
    return {
      ok: false,
      latency_ms: Math.round(performance.now() - started),
      detail: "gemini_api_key_missing",
    };
  }

  try {
    const url =
      `https://generativelanguage.googleapis.com/v1beta/models?pageSize=1&key=${
        encodeURIComponent(geminiAPIKey)
      }`;
    const response = await fetchFn(url, {
      method: "GET",
      headers: { Accept: "application/json" },
    });
    const latency = Math.round(performance.now() - started);
    if (!response.ok) {
      return {
        ok: false,
        latency_ms: latency,
        detail: `gemini_http_${response.status}`,
      };
    }
    return { ok: true, latency_ms: latency };
  } catch (error) {
    return {
      ok: false,
      latency_ms: Math.round(performance.now() - started),
      detail: error instanceof Error ? error.message : "gemini_probe_failed",
    };
  }
}

if (import.meta.main) {
  Deno.serve((request) => handleRuntimeHealthRequest(request));
}
