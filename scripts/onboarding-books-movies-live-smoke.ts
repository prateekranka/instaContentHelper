/**
 * Local staging smoke: books/movies onboarding profile → generate-week generate_day.
 * Requires local Supabase + functions serve with a real provider key (OpenAI or DeepSeek).
 * Does not print secrets or personal notes.
 */
import { createClient } from "jsr:@supabase/supabase-js@2";
import { sha256Hex } from "../supabase/functions/_shared/device-auth.ts";

const ids = {
  workspace: "77777777-7777-4777-8777-777777777771",
  creator: "88888888-8888-4888-8888-888888888881",
  profile: "99999999-9999-4999-8999-999999999991",
  ownerInvite: "dddddddd-dddd-4ddd-8ddd-dddddddddd01",
};

const inviteCode = "BOOKSMOVIES";
const scheduledDate = new Date().toISOString().slice(0, 10);

const dayBrief =
  "First idea after onboarding. Interests: Books, Movies & TV. Starting point: just starting. " +
  "Formats: talking to camera, voiceover b-roll. Time: ten to thirty minutes. Language: English. " +
  "Show face: yes. Use voice: yes. Style: warm honest takes on stories worth finishing.";

const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
const functionsURL = Deno.env.get("FUNCTIONS_URL") ??
  `${supabaseURL}/functions/v1`;
const publishableKey = Deno.env.get("MCO_SUPABASE_PUBLISHABLE_KEY") ??
  Deno.env.get("ANON_KEY") ??
  Deno.env.get("PUBLISHABLE_KEY");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  Deno.env.get("SERVICE_ROLE_KEY");

if (!publishableKey || !serviceRoleKey) {
  throw new Error("Missing local Supabase keys.");
}

const admin = createClient(supabaseURL, serviceRoleKey, {
  auth: { persistSession: false },
});

async function must(query: PromiseLike<{ error: { message: string } | null }>, label: string) {
  const { error } = await query;
  if (error) throw new Error(`${label}: ${error.message}`);
}

async function callFunction(
  name: string,
  body: Record<string, unknown>,
  deviceToken?: string,
) {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    apikey: publishableKey!,
    Authorization: `Bearer ${publishableKey}`,
  };
  if (deviceToken) headers["x-mco-device-token"] = deviceToken;

  const response = await fetch(`${functionsURL}/${name}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
  const json = await response.json().catch(() => ({}));
  return { status: response.status, json };
}

async function seed() {
  await must(
    admin.from("workspaces").delete().eq("id", ids.workspace),
    "clean workspace",
  );
  await must(
    admin.from("workspaces").insert({
      id: ids.workspace,
      name: "Onboarding Live Smoke",
      status: "active",
    }),
    "workspace",
  );

  await must(
    admin.from("creators").delete().eq("id", ids.creator),
    "clean creator",
  );
  await must(
    admin.from("creators").insert({
      id: ids.creator,
      workspace_id: ids.workspace,
      display_name: "Casey",
      handle: "casey-books",
      default_timezone: "Asia/Kolkata",
      status: "active",
    }),
    "creator",
  );

  await must(
    admin.from("creator_profiles").delete().eq("id", ids.profile),
    "clean profile",
  );
  await must(
    admin.from("creator_profiles").insert({
      id: ids.profile,
      workspace_id: ids.workspace,
      creator_id: ids.creator,
      status: "active",
      version: 1,
      onboarding_state: "established",
      onboarding_completed_at: new Date().toISOString(),
      starting_point: "just_starting",
      positioning:
        "A creator sharing book and movie picks with warm, honest takes.",
      voice_rules: ["Specific", "No hype", "First-person"],
      content_pillars: ["books", "movies-tv"],
      production_formats: ["talking_to_camera", "voiceover_broll"],
      time_to_create: "ten_to_thirty",
      on_camera_restrictions: { show_face: true, use_voice: true },
      caption_style: "Short and clear.",
      never_say: ["spoilers without warning"],
      language_preferences: { primary: "English" },
      custom_subjects: [],
      taste_example_ids: ["books-01", "movies-01"],
    }),
    "creator profile",
  );

  const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
  await must(
    admin.from("device_invites").delete().eq("id", ids.ownerInvite),
    "clean invite",
  );
  await must(
    admin.from("device_invites").insert({
      id: ids.ownerInvite,
      workspace_id: ids.workspace,
      code_hash: await sha256Hex(inviteCode),
      role_granted: "owner",
      expires_at: expiresAt,
      use_limit: 1,
      used_count: 0,
    }),
    "device invite",
  );
}

async function pollStatus(
  deviceToken: string,
  generationID: string,
): Promise<Record<string, unknown>> {
  for (let attempt = 0; attempt < 24; attempt++) {
    const status = await callFunction("generate-week", {
      action: "status",
      generation_id: generationID,
      creator_id: ids.creator,
    }, deviceToken);
    if (status.status !== 200) {
      throw new Error(`status poll failed: ${status.status} ${JSON.stringify(status.json)}`);
    }
    const state = String(status.json.status ?? "");
    if (["draft", "completed", "failed", "cancelled"].includes(state)) {
      return status.json as Record<string, unknown>;
    }
    const waitMs = (Number(status.json.poll_after_seconds) || 3) * 1000;
    await new Promise((r) => setTimeout(r, waitMs));
  }
  throw new Error("status poll timed out");
}

const result: Record<string, unknown> = {
  environment: "local-supabase",
  endpoint: `${functionsURL}/generate-week`,
  scheduled_date: scheduledDate,
  profile_pillars: ["books", "movies-tv"],
  hyrox_in_positioning: false,
};

await seed();

const paired = await callFunction("pair-device", {
  invite_code: inviteCode,
  device_name: "onboarding smoke phone",
  platform: "ios",
});
if (paired.status !== 200) {
  throw new Error(`pair-device failed: ${paired.status} ${JSON.stringify(paired.json)}`);
}
const deviceToken = String((paired.json as { device_token: string }).device_token);

const generate = await callFunction("generate-week", {
  action: "generate_day",
  creator_id: ids.creator,
  scheduled_date: scheduledDate,
  day_brief: dayBrief,
  response_mode: "sync",
}, deviceToken);

result.generate_status = generate.status;
if (generate.status !== 200) {
  result.error = generate.json;
  console.log(JSON.stringify(result, null, 2));
  Deno.exit(1);
}

let payload = generate.json as Record<string, unknown>;
if (payload.status === "running" && payload.generation_id) {
  payload = await pollStatus(deviceToken, String(payload.generation_id));
}

const card = (payload.daily_card ?? {}) as Record<string, unknown>;
const cardText = [
  card.title,
  card.content_pillar,
  card.hook,
  card.script,
  card.caption,
].filter(Boolean).join(" ").toLowerCase();

result.generation_status = payload.status;
result.content_pillar = card.content_pillar;
result.title_snippet = String(card.title ?? "").slice(0, 120);
result.card_mentions_books_or_movies = /\b(book|movie|film|story|tv)\b/.test(cardText);
result.card_mentions_hyrox = /\bhyrox\b/.test(cardText);
result.card_mentions_gym_pillar = card.content_pillar === "gym";
result.prompt_identity_check = "see deno test generate_day prompt uses profile identity";

console.log(JSON.stringify(result, null, 2));

if (result.card_mentions_hyrox) {
  Deno.exit(2);
}
if (!result.card_mentions_books_or_movies && card.content_pillar !== "books" && card.content_pillar !== "movies-tv") {
  Deno.exit(3);
}
