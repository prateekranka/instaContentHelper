import { createClient } from "jsr:@supabase/supabase-js@2";
import { sha256Hex } from "../_shared/device-auth.ts";

const ids = {
  workspace: "11111111-1111-4111-8111-111111111111",
  otherWorkspace: "22222222-2222-4222-8222-222222222222",
  creator: "33333333-3333-4333-8333-333333333333",
  otherCreator: "44444444-4444-4444-8444-444444444444",
  profile: "55555555-5555-4555-8555-555555555551",
  setup: "66666666-6666-4666-8666-666666666661",
  reference: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
  replacementReference: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2",
  idea: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
  ownerInvite: "cccccccc-cccc-4ccc-8ccc-ccccccccccc1",
  editorInvite: "cccccccc-cccc-4ccc-8ccc-ccccccccccc2",
  creatorInvite: "cccccccc-cccc-4ccc-8ccc-ccccccccccc3",
};

const inviteCodes = {
  owner: "AIWEEKOWNER",
  editor: "AIWEEKEDITOR",
  creator: "AIWEEKCREATOR",
};

const weekStartDate = "2026-06-08";

const supabaseURL = Deno.env.get("SUPABASE_URL") ??
  Deno.env.get("API_URL") ??
  "http://127.0.0.1:54321";
const functionsURL = Deno.env.get("FUNCTIONS_URL") ??
  `${supabaseURL}/functions/v1`;
const publishableKey = Deno.env.get("MCO_SUPABASE_PUBLISHABLE_KEY") ??
  Deno.env.get("PUBLISHABLE_KEY") ??
  Deno.env.get("SUPABASE_ANON_KEY") ??
  Deno.env.get("ANON_KEY");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  Deno.env.get("SERVICE_ROLE_KEY");

if (!publishableKey) {
  throw new Error("Missing local publishable key.");
}
if (!serviceRoleKey) {
  throw new Error("Missing local service role key.");
}

const admin = createClient(supabaseURL, serviceRoleKey, {
  auth: { persistSession: false },
});

await seedData();
const ownerSession = await pair("owner", inviteCodes.owner);
const editorSession = await pair("editor", inviteCodes.editor);
const creatorSession = await pair("creator", inviteCodes.creator);
assertEquals(ownerSession.member_role, "owner", "owner pairing role");
assertEquals(editorSession.member_role, "editor", "editor pairing role");
assertEquals(creatorSession.member_role, "creator", "creator pairing role");
console.log("PASS pair-device created owner/editor/creator device tokens");

const generation = await callFunction(
  "generate-week",
  ownerSession.device_token,
  {
    creator_id: ids.creator,
    week_start_date: weekStartDate,
    weekly_setup_id: ids.setup,
    mode: "generate_draft",
  },
);
if (generation.status !== 200) {
  console.log("generate-week response", generation.status, generation.json);
}
assertEquals(generation.status, 200, "generate-week status");
assertEquals(generation.json.status, "draft", "generation response status");
assertEquals(generation.json.daily_cards.length, 7, "generation card count");
assert(
  generation.json.daily_cards.every((card: Record<string, unknown>) =>
    typeof card.script === "string" &&
    typeof card.caption === "string" &&
    typeof card.backup_story === "string"
  ),
  "generated rich fields present",
);
console.log("PASS generate-week mock created a rich seven-card draft");

const weeklyPlanID = generation.json.weekly_plan_id as string;
const draftPlans = await rows(
  admin.from("weekly_plans")
    .select("id,status")
    .eq("workspace_id", ids.workspace)
    .eq("creator_id", ids.creator)
    .eq("week_start_date", weekStartDate)
    .eq("status", "draft"),
  "draft weekly plans",
);
assertEquals(draftPlans.length, 1, "one draft weekly plan");
assertEquals(draftPlans[0].id, weeklyPlanID, "draft plan id");

const draftCards = await rows(
  admin.from("daily_cards")
    .select(
      "id,scheduled_date,status,script,caption,backup_story,backup_caption_only",
    )
    .eq("weekly_plan_id", weeklyPlanID)
    .order("scheduled_date", { ascending: true }),
  "draft daily cards",
);
assertEquals(draftCards.length, 7, "draft daily card count");
assert(
  draftCards.every((card: Record<string, unknown>) => card.status === "draft"),
  "all draft",
);
assert(
  draftCards.every((card: Record<string, unknown>) =>
    card.script && card.caption && card.backup_story
  ),
  "draft card rich fields persisted",
);
console.log("PASS persisted exactly one draft plan and seven rich draft cards");

const draftCardReferences = await rows(
  admin.from("daily_card_references")
    .select("daily_card_id,source_reference_id,reason")
    .eq("workspace_id", ids.workspace)
    .eq("creator_id", ids.creator),
  "draft daily card references",
);
assertEquals(
  draftCardReferences.length,
  7,
  "draft source reference link count",
);
assert(
  draftCardReferences.every((reference: Record<string, unknown>) =>
    reference.source_reference_id === ids.reference &&
    typeof reference.reason === "string" &&
    reference.reason.includes("Confirmed towel transition")
  ),
  "draft source references persisted",
);
console.log("PASS generated draft cards preserve source reference links");

await must(
  admin.from("daily_cards")
    .update({
      title: "Edited acceptance title",
      why_today: "Edited acceptance why today.",
      shootability: "medium",
      estimated_shoot_minutes: 23,
      scene_list: [{
        number: 1,
        title: "Edited acceptance scene",
        duration: "5 sec",
        symbol: "pencil",
      }],
      caption: "Edited acceptance caption.",
      backup_story: { line: "Edited acceptance backup story." },
      backup_caption_only: {
        line: "Edited acceptance caption-only backup.",
      },
    })
    .eq("id", draftCards[0].id),
  "edit generated draft card",
);

await must(
  admin.from("source_references").update({ status: "archived" }).eq(
    "id",
    ids.reference,
  ),
  "archive first confirmed source reference",
);
await must(
  admin.from("source_references").insert({
    id: ids.replacementReference,
    workspace_id: ids.workspace,
    creator_id: ids.creator,
    source_type: "reel_link",
    source_url: "https://www.instagram.com/reel/replacement/",
    manual_notes: "Replacement confirmed shoe transition",
    status: "confirmed",
    analysis_confidence: 91,
  }),
  "seed replacement confirmed reference",
);

const regeneration = await callFunction(
  "generate-week",
  ownerSession.device_token,
  {
    creator_id: ids.creator,
    week_start_date: weekStartDate,
    weekly_setup_id: ids.setup,
    mode: "regenerate_draft",
    preserve_manual_edits: true,
  },
);
assertEquals(regeneration.status, 200, "regenerate draft status");
assertEquals(
  regeneration.json.weekly_plan_id,
  weeklyPlanID,
  "regenerate reuses draft plan",
);
const regeneratedFirstCard = regeneration.json.daily_cards.find(
  (card: Record<string, unknown>) => card.scheduled_date === weekStartDate,
);
assertEquals(
  regeneratedFirstCard?.caption,
  "Edited acceptance caption.",
  "regenerate response preserved caption",
);
assertEquals(
  regeneratedFirstCard?.backup_story,
  "Edited acceptance backup story.",
  "regenerate response preserved backup story",
);
const regeneratedFirstCardSourceIDs = regeneratedFirstCard
  ?.source_reference_ids;
assert(
  Array.isArray(regeneratedFirstCardSourceIDs) &&
    regeneratedFirstCardSourceIDs.includes(ids.replacementReference),
  "regenerate response used replacement source reference",
);

const regeneratedDraftCards = await rows(
  admin.from("daily_cards")
    .select("id,title,scene_list,caption,backup_story,backup_caption_only")
    .eq("weekly_plan_id", weeklyPlanID)
    .order("scheduled_date", { ascending: true }),
  "regenerated draft daily cards",
);
assertEquals(
  regeneratedDraftCards[0].title,
  "Edited acceptance title",
  "regenerate persisted edited title",
);
assertEquals(
  regeneratedDraftCards[0].scene_list?.[0]?.title,
  "Edited acceptance scene",
  "regenerate persisted edited scene",
);
assertEquals(
  regeneratedDraftCards[0].caption,
  "Edited acceptance caption.",
  "regenerate persisted edited caption",
);
console.log("PASS regenerate draft preserves manual review edits");

const regeneratedCardReferences = await rows(
  admin.from("daily_card_references")
    .select("daily_card_id,source_reference_id,reason")
    .eq("workspace_id", ids.workspace)
    .eq("creator_id", ids.creator),
  "regenerated daily card references",
);
assertEquals(
  regeneratedCardReferences.length,
  7,
  "regenerated source reference link count",
);
assert(
  regeneratedCardReferences.every((reference: Record<string, unknown>) =>
    reference.source_reference_id === ids.replacementReference &&
    typeof reference.reason === "string" &&
    reference.reason.includes("Replacement confirmed shoe transition")
  ),
  "regenerate replaced stale source references",
);
console.log("PASS regenerate replaces stale source reference links");

const weeklyRead = await callFunction(
  "read-content",
  ownerSession.device_token,
  { action: "weekly", creator_id: ids.creator },
);
assertEquals(weeklyRead.status, 200, "read weekly status");
assertEquals(weeklyRead.json.weekly_plan.id, weeklyPlanID, "weekly draft id");
assertEquals(weeklyRead.json.daily_cards.length, 7, "weekly read card count");
console.log("PASS read-content weekly returns draft review data");

const profileRead = await callFunction(
  "read-content",
  ownerSession.device_token,
  { action: "creator_profile", creator_id: ids.creator },
);
assertEquals(profileRead.status, 200, "read creator profile status");
assertEquals(
  profileRead.json.profile.positioning,
  "Premium fitness after 60, warm and practical.",
  "creator profile positioning",
);
assertEquals(
  profileRead.json.profile.voice_rules.length,
  3,
  "creator profile voice rules",
);
console.log("PASS read-content creator profile returns live profile data");

const publish = await callFunction(
  "publish-week",
  ownerSession.device_token,
  {
    creator_id: ids.creator,
    weekly_plan_id: weeklyPlanID,
  },
);
assertEquals(publish.status, 200, "publish existing draft status");
assertEquals(publish.json.daily_card_count, 7, "published card count");

const publishedCards = await rows(
  admin.from("daily_cards")
    .select("id,status,script,caption,backup_story")
    .eq("weekly_plan_id", weeklyPlanID)
    .order("scheduled_date", { ascending: true }),
  "published daily cards",
);
assert(
  publishedCards.every((card: Record<string, unknown>) =>
    card.status === "published"
  ),
  "all published",
);
assert(
  publishedCards.every((card: Record<string, unknown>) =>
    card.script && card.caption && card.backup_story
  ),
  "published rich fields preserved",
);
console.log(
  "PASS publish-week published existing draft and preserved rich fields",
);

const todayRead = await callFunction(
  "read-content",
  creatorSession.device_token,
  {
    action: "today",
    creator_id: ids.creator,
    today_date: weekStartDate,
  },
);
assertEquals(todayRead.status, 200, "read today status");
assertEquals(
  todayRead.json.today_card.weekly_plan_id,
  weeklyPlanID,
  "today plan id",
);
assert(todayRead.json.today_card.script, "today rich script present");
console.log(
  "PASS Creator creator read-content today returns generated published card",
);

const todayCardID = todayRead.json.today_card.id as string;
const decision = await callFunction(
  "write-content",
  creatorSession.device_token,
  {
    action: "complete_today",
    creator_id: ids.creator,
    daily_card_id: todayCardID,
    decision: {
      status: "used_backup",
      output_line: "Used backup from generated card",
      has_post_thumbnail: false,
    },
    decision_at: "2026-06-08T08:00:00Z",
  },
);
assertEquals(decision.status, 200, "creator write decision status");
console.log("PASS Creator decision write still works through write-content");

const creatorRejected = await callFunction(
  "generate-week",
  creatorSession.device_token,
  {
    creator_id: ids.creator,
    week_start_date: "2026-06-15",
  },
);
assertEquals(
  creatorRejected.status,
  403,
  "creator generation rejection status",
);
assertEquals(
  creatorRejected.json.error,
  "role_not_allowed",
  "creator rejection error",
);
console.log("PASS creator role is rejected for generate-week");

const crossWorkspace = await callFunction(
  "generate-week",
  ownerSession.device_token,
  {
    creator_id: ids.otherCreator,
    week_start_date: "2026-06-15",
  },
);
assertEquals(crossWorkspace.status, 404, "cross workspace creator status");
assertEquals(
  crossWorkspace.json.error,
  "creator_not_found",
  "cross workspace error",
);
console.log("PASS cross-workspace creator id is rejected");

const locked = await callFunction(
  "generate-week",
  ownerSession.device_token,
  {
    creator_id: ids.creator,
    week_start_date: weekStartDate,
  },
);
assertEquals(locked.status, 409, "published week lock status");
assertEquals(
  locked.json.error,
  "existing_published_week_locked",
  "published week lock error",
);
console.log(
  "PASS published week lock prevents accidental regeneration overwrite",
);

console.log("PASS ai-weekly local acceptance");

async function seedData() {
  await must(
    admin.from("workspaces").delete().in("id", [
      ids.workspace,
      ids.otherWorkspace,
    ]),
    "clean workspaces",
  );

  await must(
    admin.from("workspaces").insert([
      { id: ids.workspace, name: "AI Weekly Acceptance", status: "active" },
      { id: ids.otherWorkspace, name: "Other Workspace", status: "active" },
    ]),
    "seed workspaces",
  );

  await must(
    admin.from("creators").insert([
      {
        id: ids.creator,
        workspace_id: ids.workspace,
        display_name: "Creator",
        handle: "creator",
        default_timezone: "Asia/Kolkata",
        status: "active",
      },
      {
        id: ids.otherCreator,
        workspace_id: ids.otherWorkspace,
        display_name: "Other Creator",
        handle: "other",
        default_timezone: "Asia/Kolkata",
        status: "active",
      },
    ]),
    "seed creators",
  );

  await must(
    admin.from("creator_profiles").insert({
      id: ids.profile,
      workspace_id: ids.workspace,
      creator_id: ids.creator,
      status: "active",
      version: 1,
      positioning: "Premium fitness after 60, warm and practical.",
      voice_rules: ["warm", "steady", "no hype"],
      content_pillars: ["routine", "fitness", "family"],
      never_say: ["weight talk", "politics"],
      caption_style: "Short and human.",
      language_preferences: { primary: "English", allow_hinglish: true },
    }),
    "seed creator profile",
  );

  await must(
    admin.from("weekly_setups").insert({
      id: ids.setup,
      workspace_id: ids.workspace,
      creator_id: ids.creator,
      creator_profile_id: ids.profile,
      week_start_date: weekStartDate,
      status: "ready_to_generate",
      location: "Mumbai",
      workout_race_schedule: [{ day: "Monday", note: "Easy run" }],
      family_travel_moments: [{ day: "Saturday", note: "Family walk" }],
      energy_constraints: [{ note: "Keep shoots low effort" }],
      shooting_constraints: [{ note: "Phone-only, natural light" }],
      no_go_topics: ["weight talk", "politics"],
      selected_sources: [{ source: "Inspiration references" }],
      notes: "Use calm practical content.",
    }),
    "seed weekly setup",
  );

  await must(
    admin.from("source_references").insert({
      id: ids.reference,
      workspace_id: ids.workspace,
      creator_id: ids.creator,
      source_type: "reel_link",
      source_url: "https://www.instagram.com/reel/acceptance/",
      manual_notes: "Confirmed towel transition",
      status: "confirmed",
      analysis_confidence: 88,
    }),
    "seed confirmed reference",
  );

  await must(
    admin.from("ideas").insert({
      id: ids.idea,
      workspace_id: ids.workspace,
      creator_id: ids.creator,
      title: "Quiet Sunday family walk",
      summary: "Low effort family moment.",
      tags: ["family", "routine"],
      suggested_use: "Use as a backup day.",
      shootability: "easy",
      fit_score: 86,
      status: "saved",
    }),
    "seed idea",
  );

  const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
  await must(
    admin.from("device_invites").insert([
      {
        id: ids.ownerInvite,
        workspace_id: ids.workspace,
        code_hash: await sha256Hex(inviteCodes.owner),
        role_granted: "owner",
        expires_at: expiresAt,
        use_limit: 1,
        used_count: 0,
      },
      {
        id: ids.editorInvite,
        workspace_id: ids.workspace,
        code_hash: await sha256Hex(inviteCodes.editor),
        role_granted: "editor",
        expires_at: expiresAt,
        use_limit: 1,
        used_count: 0,
      },
      {
        id: ids.creatorInvite,
        workspace_id: ids.workspace,
        code_hash: await sha256Hex(inviteCodes.creator),
        role_granted: "creator",
        expires_at: expiresAt,
        use_limit: 1,
        used_count: 0,
      },
    ]),
    "seed device invites",
  );

  console.log("PASS seeded ai-weekly acceptance data");
}

async function pair(role: string, inviteCode: string) {
  const response = await callFunctionWithoutDeviceToken("pair-device", {
    invite_code: inviteCode,
    device_name: `${role} acceptance phone`,
    platform: "ios",
  });
  assertEquals(response.status, 200, `${role} pair status`);
  return response.json as {
    member_role: string;
    member_id: string;
    device_installation_id: string;
    device_token: string;
  };
}

async function callFunction(
  functionName: string,
  deviceToken: string,
  body: Record<string, unknown>,
) {
  return callFunctionRaw(functionName, body, {
    "x-mco-device-token": deviceToken,
  });
}

async function callFunctionWithoutDeviceToken(
  functionName: string,
  body: Record<string, unknown>,
) {
  return callFunctionRaw(functionName, body, {});
}

async function callFunctionRaw(
  functionName: string,
  body: Record<string, unknown>,
  extraHeaders: Record<string, string>,
) {
  const response = await fetch(`${functionsURL}/${functionName}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "apikey": publishableKey!,
      "Authorization": `Bearer ${publishableKey}`,
      ...extraHeaders,
    },
    body: JSON.stringify(body),
  });
  let json: any = null;
  try {
    json = await response.json();
  } catch {
    json = {};
  }
  return { status: response.status, json };
}

async function rows(query: PromiseLike<any>, label: string) {
  const { data, error } = await query;
  if (error) {
    throw new Error(`${label} failed: ${error.message}`);
  }
  return data ?? [];
}

async function must(query: PromiseLike<any>, label: string) {
  const { error } = await query;
  if (error) {
    throw new Error(`${label} failed: ${error.message}`);
  }
}

function assert(
  condition: unknown,
  message = "Assertion failed",
): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  if (!Object.is(actual, expected)) {
    throw new Error(
      `${message ?? "Assertion failed"}: expected ${
        JSON.stringify(expected)
      }, got ${JSON.stringify(actual)}`,
    );
  }
}
