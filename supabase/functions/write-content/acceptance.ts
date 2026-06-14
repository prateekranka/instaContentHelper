import { createClient } from "jsr:@supabase/supabase-js@2";
import { sha256Hex } from "../_shared/device-auth.ts";

const ids = {
  workspaceA: "11111111-1111-4111-8111-111111111111",
  workspaceB: "22222222-2222-4222-8222-222222222222",
  creatorA: "33333333-3333-4333-8333-333333333333",
  creatorB: "44444444-4444-4444-8444-444444444444",
  ownerMember: "55555555-5555-4555-8555-555555555551",
  editorMember: "55555555-5555-4555-8555-555555555552",
  creatorMember: "55555555-5555-4555-8555-555555555553",
  ownerDevice: "66666666-6666-4666-8666-666666666661",
  editorDevice: "66666666-6666-4666-8666-666666666662",
  creatorDevice: "66666666-6666-4666-8666-666666666663",
  weeklySetupA: "88888888-8888-4888-8888-888888888881",
  weeklySetupB: "88888888-8888-4888-8888-888888888882",
  weeklyPlanA: "77777777-7777-4777-8777-777777777771",
  weeklyPlanB: "77777777-7777-4777-8777-777777777772",
  ownerCard: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
  editorCard: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2",
  creatorCard: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3",
  crossWorkspaceCard: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4",
  ownerOpenCard: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5",
  editorOpenCard: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa6",
  ownerIdea: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
  editorIdea: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2",
  creatorIdea: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3",
  crossWorkspaceIdea: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4",
};

const tokens = {
  owner: "mco-owner-write-token",
  editor: "mco-editor-write-token",
  creator: "mco-creator-write-token",
};

const statusEnv = await readSupabaseStatusEnv();
const supabaseURL = Deno.env.get("SUPABASE_URL") ??
  Deno.env.get("MCO_SUPABASE_URL") ??
  statusEnv.SUPABASE_URL ??
  statusEnv.API_URL ??
  "http://127.0.0.1:54321";
const publishableKey = Deno.env.get("MCO_SUPABASE_PUBLISHABLE_KEY") ??
  Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
  Deno.env.get("SUPABASE_ANON_KEY") ??
  statusEnv.SUPABASE_PUBLISHABLE_KEY ??
  statusEnv.PUBLISHABLE_KEY ??
  statusEnv.SUPABASE_ANON_KEY ??
  statusEnv.ANON_KEY;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  Deno.env.get("SERVICE_ROLE_KEY") ??
  statusEnv.SUPABASE_SERVICE_ROLE_KEY ??
  statusEnv.SERVICE_ROLE_KEY;

if (!publishableKey) {
  throw new Error(
    "Missing local publishable key. Set MCO_SUPABASE_PUBLISHABLE_KEY or SUPABASE_ANON_KEY.",
  );
}

if (!serviceRoleKey) {
  throw new Error(
    "Missing local service role key. Set SUPABASE_SERVICE_ROLE_KEY.",
  );
}

const admin = createClient(supabaseURL, serviceRoleKey, {
  auth: { persistSession: false },
});

await seedAcceptanceData();
await assertTokenRejections();
await assertWorkspaceRejection();
await assertOwnerCanWriteAllActions();
await assertEditorCanWriteAllActions();
await assertCreatorWriteBoundary();
await assertCrossWorkspaceIdeaRejection();
await assertWeeklySetupUpdateBoundary();

console.log("PASS write-content acceptance");

async function seedAcceptanceData() {
  await must(
    admin.from("workspaces").delete().in("id", [
      ids.workspaceA,
      ids.workspaceB,
    ]),
    "clean workspaces",
  );

  await must(
    admin.from("workspaces").insert([
      { id: ids.workspaceA, name: "Write Content Workspace", status: "active" },
      { id: ids.workspaceB, name: "Other Workspace", status: "active" },
    ]),
    "seed workspaces",
  );

  await must(
    admin.from("creators").insert([
      {
        id: ids.creatorA,
        workspace_id: ids.workspaceA,
        display_name: "Creator",
        handle: "creator",
        status: "active",
      },
      {
        id: ids.creatorB,
        workspace_id: ids.workspaceB,
        display_name: "Other Creator",
        handle: "other",
        status: "active",
      },
    ]),
    "seed creators",
  );

  await must(
    admin.from("members").insert([
      {
        id: ids.ownerMember,
        workspace_id: ids.workspaceA,
        display_name: "Owner Phone",
        role: "owner",
        status: "active",
      },
      {
        id: ids.editorMember,
        workspace_id: ids.workspaceA,
        display_name: "Editor Phone",
        role: "editor",
        status: "active",
      },
      {
        id: ids.creatorMember,
        workspace_id: ids.workspaceA,
        display_name: "Creator Phone",
        role: "creator",
        status: "active",
      },
    ]),
    "seed members",
  );

  await must(
    admin.from("device_installations").insert([
      {
        id: ids.ownerDevice,
        workspace_id: ids.workspaceA,
        member_id: ids.ownerMember,
        device_name: "Owner iPhone",
        platform: "ios",
        token_hash: await sha256Hex(tokens.owner),
      },
      {
        id: ids.editorDevice,
        workspace_id: ids.workspaceA,
        member_id: ids.editorMember,
        device_name: "Editor iPhone",
        platform: "ios",
        token_hash: await sha256Hex(tokens.editor),
      },
      {
        id: ids.creatorDevice,
        workspace_id: ids.workspaceA,
        member_id: ids.creatorMember,
        device_name: "Creator iPhone",
        platform: "ios",
        token_hash: await sha256Hex(tokens.creator),
      },
    ]),
    "seed device installations",
  );

  await must(
    admin.from("weekly_setups").insert([
      {
        id: ids.weeklySetupA,
        workspace_id: ids.workspaceA,
        creator_id: ids.creatorA,
        week_start_date: "2026-06-01",
        status: "ready_to_generate",
        location: "Original local place",
        workout_race_schedule: ["Original body note"],
        family_travel_moments: ["Original family note"],
        energy_constraints: ["Original energy constraint"],
        shooting_constraints: ["Original shooting constraint"],
        no_go_topics: ["Original boundary"],
        selected_sources: ["Original source pulse"],
        notes: "Original notes",
        created_by_member_id: ids.ownerMember,
      },
      {
        id: ids.weeklySetupB,
        workspace_id: ids.workspaceB,
        creator_id: ids.creatorB,
        week_start_date: "2026-06-01",
        status: "ready_to_generate",
        location: "Other workspace place",
        workout_race_schedule: [],
        family_travel_moments: [],
        energy_constraints: [],
        shooting_constraints: [],
        no_go_topics: [],
        selected_sources: [],
      },
    ]),
    "seed weekly setups",
  );

  await must(
    admin.from("weekly_plans").insert([
      {
        id: ids.weeklyPlanA,
        workspace_id: ids.workspaceA,
        creator_id: ids.creatorA,
        weekly_setup_id: ids.weeklySetupA,
        week_start_date: "2026-06-01",
        status: "published",
        strategy_summary: "Acceptance weekly plan",
        warnings: [],
        assumptions: [],
        is_soft_locked: true,
        created_by_member_id: ids.ownerMember,
      },
      {
        id: ids.weeklyPlanB,
        workspace_id: ids.workspaceB,
        creator_id: ids.creatorB,
        weekly_setup_id: ids.weeklySetupB,
        week_start_date: "2026-06-01",
        status: "published",
        strategy_summary: "Other weekly plan",
        warnings: [],
        assumptions: [],
        is_soft_locked: true,
      },
    ]),
    "seed weekly plans",
  );

  await must(
    admin.from("daily_cards").insert([
      dailyCard(
        ids.ownerCard,
        ids.workspaceA,
        ids.creatorA,
        ids.weeklyPlanA,
        "2026-06-05",
        "Owner Friday card",
      ),
      dailyCard(
        ids.editorCard,
        ids.workspaceA,
        ids.creatorA,
        ids.weeklyPlanA,
        "2026-06-06",
        "Editor Saturday card",
      ),
      dailyCard(
        ids.creatorCard,
        ids.workspaceA,
        ids.creatorA,
        ids.weeklyPlanA,
        "2026-06-07",
        "Creator Sunday card",
      ),
      dailyCard(
        ids.crossWorkspaceCard,
        ids.workspaceB,
        ids.creatorB,
        ids.weeklyPlanB,
        "2026-06-05",
        "Cross workspace card",
      ),
      dailyCard(
        ids.ownerOpenCard,
        ids.workspaceA,
        ids.creatorA,
        ids.weeklyPlanA,
        "2026-06-08",
        "Owner open slot",
        "draft",
      ),
      dailyCard(
        ids.editorOpenCard,
        ids.workspaceA,
        ids.creatorA,
        ids.weeklyPlanA,
        "2026-06-09",
        "Editor open slot",
        "draft",
      ),
    ]),
    "seed daily cards",
  );

  await must(
    admin.from("ideas").insert([
      idea(ids.ownerIdea, ids.workspaceA, ids.creatorA, "Owner idea"),
      idea(ids.editorIdea, ids.workspaceA, ids.creatorA, "Editor idea"),
      idea(ids.creatorIdea, ids.workspaceA, ids.creatorA, "Creator idea"),
      idea(
        ids.crossWorkspaceIdea,
        ids.workspaceB,
        ids.creatorB,
        "Other workspace idea",
      ),
    ]),
    "seed ideas",
  );

  console.log("PASS seeded write-content data");
}

async function assertTokenRejections() {
  const body = completeTodayBody(ids.ownerCard, "shot");

  const missing = await callWriteContent(null, body);
  assertEquals(missing.status, 401, "missing token status");
  assertEquals(
    missing.json.error,
    "missing_device_token",
    "missing token error",
  );

  const invalid = await callWriteContent("not-a-valid-token", body);
  assertEquals(invalid.status, 401, "invalid token status");
  assertEquals(
    invalid.json.error,
    "invalid_device_token",
    "invalid token error",
  );

  console.log("PASS rejects missing/invalid device token");
}

async function assertWorkspaceRejection() {
  const response = await callWriteContent(
    tokens.owner,
    {
      ...completeTodayBody(ids.crossWorkspaceCard, "shot"),
      creator_id: ids.creatorB,
    },
  );

  assertEquals(response.status, 404, "outside creator status");
  assertEquals(
    response.json.error,
    "creator_not_found",
    "outside creator error",
  );
  console.log("PASS rejects creator outside paired workspace");
}

async function assertOwnerCanWriteAllActions() {
  const completed = await callWriteContent(
    tokens.owner,
    completeTodayBody(ids.ownerCard, "shot"),
  );
  assertEquals(completed.status, 200, "owner complete_today status");

  const card = await singleRow(
    admin.from("daily_cards")
      .select("status,decision_at,completed_by_member_id")
      .eq("id", ids.ownerCard)
      .single(),
    "owner daily card",
  );
  assertEquals(card.status, "shot", "owner daily card status");
  assert(Boolean(card.decision_at), "owner decision_at set");
  assertEquals(
    card.completed_by_member_id,
    ids.ownerMember,
    "owner completed member",
  );

  await upsertArchiveTwice(tokens.owner, ids.ownerCard, "owner");

  const selected = await callWriteContent(
    tokens.owner,
    selectIdeaBody(ids.ownerIdea),
  );
  assertEquals(selected.status, 200, "owner select idea status");
  await assertIdeaScheduled(ids.ownerIdea, "owner idea scheduled");
  await assertOpenCardFilled(
    ids.ownerOpenCard,
    ids.ownerIdea,
    "Owner idea",
    "owner open card selected",
  );

  console.log("PASS owner can call all write actions");
}

async function assertEditorCanWriteAllActions() {
  const completed = await callWriteContent(
    tokens.editor,
    completeTodayBody(ids.editorCard, "posted"),
  );
  assertEquals(completed.status, 200, "editor complete_today status");

  await upsertArchiveTwice(tokens.editor, ids.editorCard, "editor");

  const selected = await callWriteContent(
    tokens.editor,
    selectIdeaBody(ids.editorIdea),
  );
  assertEquals(selected.status, 200, "editor select idea status");
  await assertIdeaScheduled(ids.editorIdea, "editor idea scheduled");
  await assertOpenCardFilled(
    ids.editorOpenCard,
    ids.editorIdea,
    "Editor idea",
    "editor open card selected",
  );

  console.log("PASS editor can call all write actions");
}

async function assertCreatorWriteBoundary() {
  const completed = await callWriteContent(
    tokens.creator,
    completeTodayBody(ids.creatorCard, "saved_for_tomorrow"),
  );
  assertEquals(completed.status, 200, "creator complete_today status");

  const archive = await callWriteContent(
    tokens.creator,
    archiveBody(ids.creatorCard, "creator archive"),
  );
  assertEquals(archive.status, 200, "creator archive upsert status");

  const select = await callWriteContent(
    tokens.creator,
    selectIdeaBody(ids.creatorIdea),
  );
  assertEquals(select.status, 403, "creator select idea status");
  assertEquals(
    select.json.error,
    "role_not_allowed",
    "creator select idea error",
  );

  console.log("PASS creator can complete/archive but cannot select idea");
}

async function assertCrossWorkspaceIdeaRejection() {
  const response = await callWriteContent(
    tokens.owner,
    selectIdeaBody(ids.crossWorkspaceIdea),
  );
  assertEquals(response.status, 404, "cross workspace idea status");
  assertEquals(
    response.json.error,
    "idea_not_found",
    "cross workspace idea error",
  );

  console.log("PASS rejects cross-workspace idea id");
}

async function assertWeeklySetupUpdateBoundary() {
  const ownerUpdate = await callWriteContent(
    tokens.owner,
    weeklySetupBody("Owner edited New Jersey place", ids.weeklyPlanA),
  );
  assertEquals(ownerUpdate.status, 200, "owner weekly setup update status");
  await assertWeeklySetupSummary("location", "Owner edited New Jersey place");

  const editorUpdate = await callWriteContent(
    tokens.editor,
    {
      action: "update_weekly_setup",
      creator_id: ids.creatorA,
      week_start_date: "2026-06-01",
      setup_sections: [
        {
          title: "Body",
          summary: "Editor edited recovery note",
        },
        {
          title: "Family",
          summary: "Editor edited family note",
        },
      ],
    },
  );
  assertEquals(editorUpdate.status, 200, "editor weekly setup update status");
  await assertWeeklySetupSummary(
    "workout_race_schedule",
    ["Editor edited recovery note"],
  );
  await assertWeeklySetupSummary(
    "family_travel_moments",
    ["Editor edited family note"],
  );

  const creatorUpdate = await callWriteContent(
    tokens.creator,
    weeklySetupBody("Creator should not edit", ids.weeklyPlanA),
  );
  assertEquals(creatorUpdate.status, 403, "creator weekly setup update status");
  assertEquals(
    creatorUpdate.json.error,
    "role_not_allowed",
    "creator weekly setup update error",
  );

  const crossWorkspacePlan = await callWriteContent(
    tokens.owner,
    weeklySetupBody("Cross workspace should fail", ids.weeklyPlanB),
  );
  assertEquals(
    crossWorkspacePlan.status,
    403,
    "cross workspace weekly plan update status",
  );
  assertEquals(
    crossWorkspacePlan.json.error,
    "cross_workspace_forbidden",
    "cross workspace weekly plan update error",
  );

  const crossWorkspaceSetup = await callWriteContent(
    tokens.owner,
    {
      action: "update_weekly_setup",
      creator_id: ids.creatorA,
      weekly_setup_id: ids.weeklySetupB,
      setup_sections: [
        {
          title: "Place",
          summary: "Cross workspace setup should fail",
        },
      ],
    },
  );
  assertEquals(
    crossWorkspaceSetup.status,
    403,
    "cross workspace weekly setup update status",
  );
  assertEquals(
    crossWorkspaceSetup.json.error,
    "cross_workspace_forbidden",
    "cross workspace weekly setup update error",
  );

  const malformed = await callWriteContent(
    tokens.owner,
    {
      action: "update_weekly_setup",
      creator_id: ids.creatorA,
      weekly_plan_id: ids.weeklyPlanA,
      setup_sections: [{ title: "Unknown", summary: "No matching column" }],
    },
  );
  assertEquals(malformed.status, 400, "malformed weekly setup update status");
  assertEquals(
    malformed.json.error,
    "invalid_weekly_setup_payload",
    "malformed weekly setup update error",
  );

  console.log("PASS weekly setup update boundary");
}

async function upsertArchiveTwice(
  token: string,
  dailyCardID: string,
  label: string,
) {
  const first = await callWriteContent(
    token,
    archiveBody(dailyCardID, `${label} first output`),
  );
  assertEquals(first.status, 200, `${label} first archive status`);

  const second = await callWriteContent(
    token,
    archiveBody(dailyCardID, `${label} updated output`),
  );
  assertEquals(second.status, 200, `${label} second archive status`);

  const { data, count, error } = await admin
    .from("archive_entries")
    .select("id,output_line", { count: "exact" })
    .eq("daily_card_id", dailyCardID);

  if (error) {
    throw new Error(`${label} archive lookup failed: ${error.message}`);
  }

  assertEquals(count, 1, `${label} archive row count`);
  assertEquals(
    data?.[0]?.output_line,
    `${label} updated output`,
    `${label} archive update`,
  );
}

async function assertIdeaScheduled(ideaID: string, label: string) {
  const row = await singleRow(
    admin.from("ideas").select("status").eq("id", ideaID).single(),
    label,
  );
  assertEquals(row.status, "scheduled", label);
}

async function assertOpenCardFilled(
  dailyCardID: string,
  ideaID: string,
  expectedTitle: string,
  label: string,
) {
  const row = await singleRow(
    admin.from("daily_cards")
      .select(
        "origin_idea_id,status,title,why_today,content_pillar,shootability",
      )
      .eq("id", dailyCardID)
      .single(),
    label,
  );

  assertEquals(row.origin_idea_id, ideaID, `${label} origin idea`);
  assertEquals(row.status, "published", `${label} status`);
  assertEquals(row.title, expectedTitle, `${label} title`);
  assertEquals(row.why_today, "Acceptance idea", `${label} why today`);
  assertEquals(row.content_pillar, "idea", `${label} content pillar`);
  assertEquals(row.shootability, "easy", `${label} shootability`);
}

function completeTodayBody(dailyCardID: string, status: string) {
  return {
    action: "complete_today",
    creator_id: ids.creatorA,
    daily_card_id: dailyCardID,
    decision: {
      status,
      output_line: `${status} acceptance output`,
      has_post_thumbnail: status === "shot" || status === "posted",
    },
    decision_at: "2026-06-05T10:00:00.000Z",
  };
}

function archiveBody(dailyCardID: string, outputLine: string) {
  return {
    action: "upsert_archive_decision",
    creator_id: ids.creatorA,
    daily_card_id: dailyCardID,
    archive_date: "2026-06-05",
    decision: "shot",
    output_line: outputLine,
    has_post_thumbnail: true,
  };
}

function selectIdeaBody(ideaID: string) {
  return {
    action: "select_idea_for_next_open_day",
    creator_id: ids.creatorA,
    idea_id: ideaID,
    weekly_plan_id: ids.weeklyPlanA,
  };
}

function weeklySetupBody(summary: string, weeklyPlanID: string) {
  return {
    action: "update_weekly_setup",
    creator_id: ids.creatorA,
    weekly_plan_id: weeklyPlanID,
    setup_sections: [
      {
        title: "Place",
        summary,
      },
    ],
  };
}

async function assertWeeklySetupSummary(
  column: string,
  expectedValue: unknown,
) {
  const row = await singleRow(
    admin.from("weekly_setups")
      .select(column)
      .eq("id", ids.weeklySetupA)
      .single(),
    `weekly setup ${column}`,
  );

  const actualValue = row[column];
  if (Array.isArray(expectedValue)) {
    assertEquals(
      JSON.stringify(actualValue),
      JSON.stringify(expectedValue),
      `weekly setup ${column}`,
    );
  } else {
    assertEquals(actualValue, expectedValue, `weekly setup ${column}`);
  }
}

function dailyCard(
  id: string,
  workspaceID: string,
  creatorID: string,
  weeklyPlanID: string,
  scheduledDate: string,
  title: string,
  status = "published",
) {
  return {
    id,
    workspace_id: workspaceID,
    creator_id: creatorID,
    weekly_plan_id: weeklyPlanID,
    scheduled_date: scheduledDate,
    status,
    title,
    why_today: "Acceptance test card.",
    scene_list: [],
    hashtags: [],
  };
}

function idea(
  id: string,
  workspaceID: string,
  creatorID: string,
  title: string,
) {
  return {
    id,
    workspace_id: workspaceID,
    creator_id: creatorID,
    title,
    summary: "Acceptance idea",
    shootability: "easy",
    status: "saved",
  };
}

async function callWriteContent(
  deviceToken: string | null,
  body: Record<string, unknown>,
): Promise<{ status: number; json: Record<string, unknown> }> {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${publishableKey}`,
    apikey: publishableKey,
    "Content-Type": "application/json",
  };

  if (deviceToken !== null) {
    headers["x-mco-device-token"] = deviceToken;
  }

  const response = await fetch(`${supabaseURL}/functions/v1/write-content`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });

  const json = await response.json().catch(() => ({}));
  return { status: response.status, json };
}

async function must<T extends { error: { message: string } | null }>(
  result: PromiseLike<T>,
  label: string,
): Promise<T> {
  const value = await result;
  if (value.error) {
    throw new Error(`${label} failed: ${value.error.message}`);
  }
  return value;
}

async function singleRow<T extends Record<string, unknown>>(
  result: PromiseLike<{ data: T | null; error: { message: string } | null }>,
  label: string,
): Promise<T> {
  const value = await result;
  if (value.error) {
    throw new Error(`${label} failed: ${value.error.message}`);
  }
  if (!value.data) {
    throw new Error(`${label} returned no row`);
  }
  return value.data;
}

function assert(value: boolean, label: string) {
  if (!value) {
    throw new Error(`Assertion failed: ${label}`);
  }
}

function assertEquals(actual: unknown, expected: unknown, label: string) {
  if (actual !== expected) {
    throw new Error(
      `Assertion failed: ${label}; expected ${expected}, got ${actual}`,
    );
  }
}

async function readSupabaseStatusEnv(): Promise<Record<string, string>> {
  try {
    const command = new Deno.Command("supabase", {
      args: ["status", "-o", "env"],
      stdout: "piped",
      stderr: "null",
    });
    const output = await command.output();
    if (!output.success) {
      return {};
    }
    return parseEnvOutput(new TextDecoder().decode(output.stdout));
  } catch {
    return {};
  }
}

function parseEnvOutput(output: string): Record<string, string> {
  const values: Record<string, string> = {};
  for (const line of output.split("\n")) {
    const match = /^([A-Z0-9_]+)=["']?([^"'\n]+)["']?$/.exec(line.trim());
    if (match) {
      values[match[1]] = match[2];
    }
  }
  return values;
}
