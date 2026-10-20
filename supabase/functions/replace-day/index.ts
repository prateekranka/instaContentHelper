import {
  type GenerateWeekDependencies,
  handleGenerateWeekRequest,
} from "../generate-week/index.ts";
import { jsonResponse } from "../_shared/device-auth.ts";

export async function handleReplaceDayRequest(
  request: Request,
  dependencies: GenerateWeekDependencies = {},
): Promise<Response> {
  if (request.method !== "POST") {
    return await handleGenerateWeekRequest(request, dependencies);
  }
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_generation_payload" }, 400);
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return jsonResponse({ error: "invalid_generation_payload" }, 400);
  }
  return await handleGenerateWeekRequest(
    new Request(request.url, {
      method: "POST",
      headers: request.headers,
      body: JSON.stringify({ ...body, action: "replace_day" }),
    }),
    dependencies,
  );
}

if (import.meta.main) Deno.serve((request) => handleReplaceDayRequest(request));
