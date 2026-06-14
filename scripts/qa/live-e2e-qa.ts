import { createClient } from "jsr:@supabase/supabase-js@2";

type JsonObject = Record<string, unknown>;

const config = {
  supabaseURL: requiredEnv("MCO_SUPABASE_URL").replace(/\/+$/, ""),
  publishableKey: requiredEnv("MCO_SUPABASE_PUBLISHABLE_KEY"),
  serviceRoleKey: requiredEnv("MCO_SUPABASE_SERVICE_ROLE_KEY"),
  weekStartDate: env("MCO_QA_WEEK_START_DATE") ?? "2026-07-06",
  useMockAI: env("MCO_QA_GENERATE_MOCK") === "1",
  responseMode: env("MCO_QA_GENERATION_RESPONSE_MODE") ?? "sync",
  cleanupOnly: env("MCO_QA_CLEANUP_ONLY") === "1",
};

const ids = {
  workspace: "7a111111-1111-4111-8111-1111111111e2",
  creator: "7a222222-2222-4222-8222-2222222222e2",
  profile: "7a333333-3333-4333-8333-3333333333e2",
  setup: "7a444444-4444-4444-8444-4444444444e2",
  ownerMember: "7a555555-5555-4555-8555-5555555555e2",
  editorMember: "7a666666-6666-4666-8666-6666666666e2",
  creatorMember: "7a777777-7777-4777-8777-7777777777e2",
  ownerDevice: "7a888888-8888-4888-8888-8888888888e2",
  editorDevice: "7a999999-9999-4999-8999-9999999999e2",
  creatorDevice: "7aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaae2",
  idea: "7abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbe2",
  otherWorkspace: "7acccccc-cccc-4ccc-8ccc-cccccccccce2",
  otherCreator: "7adddddd-dddd-4ddd-8ddd-dddddddddde2",
};

const tokens = {
  owner: "qa-owner-device-token-live-e2e",
  editor: "qa-editor-device-token-live-e2e",
  creator: "qa-creator-device-token-live-e2e",
};

const functionsURL = `${config.supabaseURL}/functions/v1`;
const admin = createClient(config.supabaseURL, config.serviceRoleKey, {
  auth: { persistSession: false },
});

if (!isDateString(config.weekStartDate)) {
  fail("MCO_QA_WEEK_START_DATE must be YYYY-MM-DD");
}
if (config.responseMode !== "sync" && config.responseMode !== "async") {
  fail("MCO_QA_GENERATION_RESPONSE_MODE must be sync or async");
}

await resetQAWorkspace();
if (config.cleanupOnly) {
  console.log("PASS cleaned live QA workspace");
  Deno.exit(0);
}

await seedQAWorkspace();
await runAdminE2E();
await runCreatorE2E();
await runRoleAndBoundaryChecks();
console.log("PASS live Supabase QA E2E suite");

async function resetQAWorkspace() {
  await must(
    "clean QA workspaces",
    admin.from("workspaces").delete().in("id", [
      ids.workspace,
      ids.otherWorkspace,
    ]),
  );
}

async function seedQAWorkspace() {
  await must(
    "seed QA workspaces",
    admin.from("workspaces").insert([
      {
        id: ids.workspace,
        name: "Creator Content OS Live QA",
        status: "active",
      },
      {
        id: ids.otherWorkspace,
        name: "Creator Content OS Cross Workspace QA",
        status: "active",
      },
    ]),
  );

  await must(
    "seed QA creators",
    admin.from("creators").insert([
      {
        id: ids.creator,
        workspace_id: ids.workspace,
        display_name: "QA Creator",
        handle: "qa_creator",
        default_timezone: "America/New_York",
        status: "active",
      },
      {
        id: ids.otherCreator,
        workspace_id: ids.otherWorkspace,
        display_name: "Cross Workspace QA Creator",
        handle: "cross_workspace_qa_creator",
        default_timezone: "America/New_York",
        status: "active",
      },
    ]),
  );

  await must(
    "seed QA members",
    admin.from("members").insert([
      {
        id: ids.ownerMember,
        workspace_id: ids.workspace,
        display_name: "QA Owner",
        email: "qa-owner@example.invalid",
        role: "owner",
        status: "active",
      },
      {
        id: ids.editorMember,
        workspace_id: ids.workspace,
        display_name: "QA Editor",
        email: "qa-editor@example.invalid",
        role: "editor",
        status: "active",
      },
      {
        id: ids.creatorMember,
        workspace_id: ids.workspace,
        display_name: "QA Creator Tester",
        email: "qa-creator@example.invalid",
        role: "creator",
        status: "active",
      },
    ]),
  );

  await must(
    "seed QA device sessions",
    admin.from("device_installations").insert([
      {
        id: ids.ownerDevice,
        workspace_id: ids.workspace,
        member_id: ids.ownerMember,
        device_name: "QA Owner Simulator",
        platform: "ios",
        token_hash: await sha256Hex(tokens.owner),
      },
      {
        id: ids.editorDevice,
        workspace_id: ids.workspace,
        member_id: ids.editorMember,
        device_name: "QA Editor Simulator",
        platform: "ios",
        token_hash: await sha256Hex(tokens.editor),
      },
      {
        id: ids.creatorDevice,
        workspace_id: ids.workspace,
        member_id: ids.creatorMember,
        device_name: "QA Creator Simulator",
        platform: "ios",
        token_hash: await sha256Hex(tokens.creator),
      },
    ]),
  );

  await must(
    "seed QA creator profile",
    admin.from("creator_profiles").insert({
      id: ids.profile,
      workspace_id: ids.workspace,
      creator_id: ids.creator,
      status: "active",
      version: 1,
      positioning:
        "Practical wellness creator for women balancing family, travel, training, and recovery.",
      voice_rules: ["specific", "warm", "no medical claims"],
      content_pillars: ["routine", "recovery", "family", "travel"],
      preferred_hooks: [
        "Start with the real constraint",
        "Show the simplest useful detail",
      ],
      caption_style: "Short, useful, and human.",
      never_say: ["guaranteed results", "diagnosis", "weight loss promise"],
      weekly_routine: {
        planning_day: "Monday",
        preferred_shoot_time: "morning",
      },
      family_race_travel_context: {
        location: "New Jersey",
        theme: "recovery week",
      },
      brand_tone: "calm and practical",
      language_preferences: {
        primary: "English",
        secondary: "Hindi when natural",
      },
      recurring_formats: ["one practical detail", "caption-only backup"],
      trend_filter_rules: { avoid: "high effort trend chasing" },
      influencer_adaptation_rules: { use: "adapt structure, not personality" },
      created_by_member_id: ids.ownerMember,
    }),
  );

  await must(
    "seed QA weekly setup",
    admin.from("weekly_setups").insert({
      id: ids.setup,
      workspace_id: ids.workspace,
      creator_id: ids.creator,
      creator_profile_id: ids.profile,
      week_start_date: config.weekStartDate,
      status: "ready_to_generate",
      location: "New Jersey, USA",
      workout_race_schedule: [
        { day: "Monday", note: "Recovery walk only" },
        { day: "Wednesday", note: "Mobility and light strength" },
      ],
      family_travel_moments: [
        {
          day: "Week",
          note: "Staying near younger son; use simple family details",
        },
      ],
      energy_constraints: [
        {
          note: "Recovery week; keep physical effort low and no medical advice",
        },
      ],
      shooting_constraints: [
        {
          note:
            "Phone-only, natural light, can shoot indoors if weather is poor",
        },
      ],
      no_go_topics: [
        "medical diagnosis",
        "weight loss claims",
        "race result claims",
      ],
      selected_sources: [{ source: "Inspiration references" }],
      notes:
        "QA setup: prioritize recovery, family, New Jersey, and low-effort shootability.",
      created_by_member_id: ids.ownerMember,
    }),
  );

  await must(
    "seed QA confirmed reference",
    admin.from("source_references").insert({
      workspace_id: ids.workspace,
      creator_id: ids.creator,
      source_type: "reel_link",
      source_url: "https://www.instagram.com/reel/QASeedRef001/",
      manual_notes:
        "Seed QA reference: shoes by the door, recovery walk, quiet practical tone.",
      status: "confirmed",
      analysis_confidence: 92,
    }),
  );

  await must(
    "seed QA idea",
    admin.from("ideas").insert({
      id: ids.idea,
      workspace_id: ids.workspace,
      creator_id: ids.creator,
      title: "Recovery walk after a travel morning",
      summary:
        "A low-effort reel about keeping routine realistic while away from home.",
      tags: ["recovery", "travel", "routine"],
      suggested_use: "Use when energy is low but consistency matters.",
      shootability: "easy",
      fit_score: 88,
      status: "saved",
    }),
  );

  console.log("PASS seeded live QA workspace");
}

async function runAdminE2E() {
  const profile = await invoke("read-content", tokens.owner, {
    action: "creator_profile",
    creator_id: ids.creator,
  });
  assertTruthy(objectValue(profile.profile), "creator profile is available");
  console.log("PASS admin read-content creator_profile");

  const intelligence = await invoke("read-content", tokens.owner, {
    action: "intelligence",
    creator_id: ids.creator,
  });
  assertArray(intelligence.confirmed_source_references, "confirmed references");
  assertArray(intelligence.review_source_references, "review references");
  assertArray(intelligence.ideas, "ideas");
  console.log("PASS admin read-content intelligence");

  const generation = await generateWeek();
  const weeklyPlanID = requiredString(
    generation.weekly_plan_id,
    "generated weekly_plan_id",
  );
  const generatedCards = requiredArray(
    generation.daily_cards,
    "generated cards",
  );
  assertEquals(generatedCards.length, 7, "generated card count");
  assertGeneratedCards(generatedCards, weekDates(config.weekStartDate));
  console.log(`PASS admin generated draft week ${weeklyPlanID}`);

  const weeklyAfterGenerate = await invoke("read-content", tokens.owner, {
    action: "weekly",
    creator_id: ids.creator,
  });
  assertEquals(
    stringValue(objectValue(weeklyAfterGenerate.weekly_plan)?.id),
    weeklyPlanID,
    "weekly read generated plan id",
  );
  assertEquals(
    stringValue(objectValue(weeklyAfterGenerate.weekly_plan)?.status),
    "draft",
    "weekly read generated plan status",
  );
  assertEquals(
    requiredArray(weeklyAfterGenerate.daily_cards, "weekly generated cards")
      .length,
    7,
    "weekly generated card count",
  );
  console.log("PASS admin weekly read shows generated draft");

  const editedPlace = `QA edited New Jersey location ${Date.now()}`;
  const editedNotes = `QA setup note ${new Date().toISOString()}`;
  const setupEdit = await invoke("write-content", tokens.editor, {
    action: "update_weekly_setup",
    creator_id: ids.creator,
    weekly_plan_id: weeklyPlanID,
    setup_sections: [
      { title: "Place", summary: editedPlace },
      { title: "Notes", summary: editedNotes },
    ],
  });
  assertEquals(
    stringValue(objectValue(setupEdit.weekly_setup)?.location),
    editedPlace,
    "weekly setup edited location",
  );
  console.log("PASS admin edited Weekly Brief through write-content");

  const importedReferenceID = await importAndApproveReference();
  console.log(
    `PASS admin imported/approved QA reference ${importedReferenceID}`,
  );

  const dayTarget = weekDates(config.weekStartDate)[2];
  const dayRegeneration = await regenerateDay(weeklyPlanID, dayTarget);
  assertEquals(
    stringValue(dayRegeneration.target_scheduled_date),
    dayTarget,
    "regenerated target date",
  );
  assertEquals(
    stringValue(objectValue(dayRegeneration.daily_card)?.scheduled_date),
    dayTarget,
    "regenerated card date",
  );
  requiredString(
    objectValue(dayRegeneration.daily_card)?.caption,
    "regenerated caption",
  );
  console.log("PASS admin regenerated one day");

  const weeklyBeforePublish = await invoke("read-content", tokens.owner, {
    action: "weekly",
    creator_id: ids.creator,
  });
  const cardsForPublish = requiredArray(
    weeklyBeforePublish.daily_cards,
    "cards before publish",
  ).map((value, index) => {
    const card = requireObject(value, `publish card ${index}`);
    return index === 0
      ? {
        ...card,
        title: "QA edited Monday recovery title",
        caption: "QA edited caption persisted through publish.",
        scene_list: [
          {
            number: 1,
            title: "QA edited scene",
            duration: "4 sec",
            symbol: "figure.walk",
          },
          ...(Array.isArray(card.scene_list) ? card.scene_list.slice(1) : []),
        ],
        backup_story: { line: "QA edited backup story." },
        backup_caption_only: { line: "QA edited caption-only backup." },
      }
      : card;
  });

  const publish = await invoke("publish-week", tokens.owner, {
    creator_id: ids.creator,
    weekly_plan_id: weeklyPlanID,
    strategy_summary: "QA published generated week with edited first card.",
    draft_daily_cards: cardsForPublish,
  });
  assertEquals(numberValue(publish.daily_card_count), 7, "publish card count");
  assertEquals(publish.is_soft_locked, true, "publish lock flag");
  assertTruthy(stringValue(publish.published_at), "publish timestamp");
  console.log("PASS admin confirmed/published generated week");

  const idempotentPublish = await invoke("publish-week", tokens.owner, {
    creator_id: ids.creator,
    weekly_plan_id: weeklyPlanID,
  });
  assertEquals(
    numberValue(idempotentPublish.daily_card_count),
    7,
    "idempotent publish card count",
  );
  console.log("PASS admin publish is idempotent");

  const weeklyAfterPublish = await invoke("read-content", tokens.owner, {
    action: "weekly",
    creator_id: ids.creator,
  });
  assertEquals(
    stringValue(objectValue(weeklyAfterPublish.weekly_plan)?.status),
    "published",
    "weekly plan published status",
  );
  const publishedCards = requiredArray(
    weeklyAfterPublish.daily_cards,
    "published weekly cards",
  );
  assertEquals(publishedCards.length, 7, "published weekly card count");
  const firstCard = requireObject(publishedCards[0], "first published card");
  assertEquals(
    stringValue(firstCard.title),
    "QA edited Monday recovery title",
    "published edited title",
  );
  assertEquals(
    stringValue(firstCard.caption),
    "QA edited caption persisted through publish.",
    "published edited caption",
  );
  assertEquals(
    stringValue(objectValue(weeklyAfterPublish.weekly_setup)?.location),
    editedPlace,
    "weekly setup edit persisted",
  );
  console.log("PASS admin published data persisted in read-content");

  const intelligenceAfterReference = await invoke(
    "read-content",
    tokens.owner,
    {
      action: "intelligence",
      creator_id: ids.creator,
    },
  );
  const confirmedReferences = requiredArray(
    intelligenceAfterReference.confirmed_source_references,
    "confirmed references after import",
  );
  assert(
    confirmedReferences.some((value) =>
      stringValue(requireObject(value, "confirmed reference").id) ===
        importedReferenceID
    ),
    "approved QA reference appears in confirmed references",
  );
  console.log("PASS admin reference persists in intelligence");
}

async function runCreatorE2E() {
  const today = await invoke("read-content", tokens.creator, {
    action: "today",
    creator_id: ids.creator,
    today_date: config.weekStartDate,
  });
  const todayCard = requireObject(today.today_card, "creator today card");
  assert(
    [
      "published",
      "in_decision",
      "shot",
      "posted",
      "used_backup",
      "saved_for_tomorrow",
      "skipped_intentionally",
    ]
      .includes(requiredString(todayCard.status, "creator today status")),
    "creator today card has published-family status",
  );
  const todayCardID = requiredString(todayCard.id, "creator today card id");
  requiredString(todayCard.script, "creator today script");
  requiredString(todayCard.caption, "creator today caption");
  assertArray(todayCard.scene_list, "creator today scenes");
  console.log("PASS creator sees published generated Today card");

  const decision = await invoke("write-content", tokens.creator, {
    action: "complete_today",
    creator_id: ids.creator,
    daily_card_id: todayCardID,
    decision: {
      status: "used_backup",
      output_line: "QA creator used backup path after reviewing Shoot Folio.",
      has_post_thumbnail: false,
    },
    decision_at: new Date().toISOString(),
  });
  assertEquals(
    stringValue(objectValue(decision.daily_card)?.status),
    "used_backup",
    "creator complete_today status",
  );
  console.log("PASS creator decision write works");

  await invoke("write-content", tokens.creator, {
    action: "upsert_archive_decision",
    creator_id: ids.creator,
    daily_card_id: todayCardID,
    archive_date: config.weekStartDate,
    decision: "used_backup",
    output_line: "QA creator used backup path after reviewing Shoot Folio.",
    has_post_thumbnail: false,
  });
  console.log("PASS creator archive upsert works");

  const archive = await invoke("read-content", tokens.creator, {
    action: "archive",
    creator_id: ids.creator,
  });
  const archiveEntries = requiredArray(
    archive.entries,
    "creator archive entries",
  );
  assert(
    archiveEntries.some((value) => {
      const entry = requireObject(value, "archive entry");
      return stringValue(entry.daily_card_id) === todayCardID &&
        stringValue(entry.decision) === "used_backup";
    }),
    "creator archive contains decision",
  );
  console.log("PASS creator Profile/Archive data persists");
}

async function runRoleAndBoundaryChecks() {
  const invalidToken = await invokeExpectError(
    "read-content",
    "definitely-invalid-qa-token",
    { action: "weekly", creator_id: ids.creator },
    "invalid_device_token",
  );
  assertEquals(invalidToken.status, 401, "invalid token status");

  const creatorGenerate = await invokeExpectError(
    "generate-week",
    tokens.creator,
    {
      creator_id: ids.creator,
      week_start_date: nextWeek(config.weekStartDate),
      weekly_setup_id: ids.setup,
    },
    "role_not_allowed",
  );
  assertEquals(creatorGenerate.status, 403, "creator generate status");

  const crossWorkspace = await invokeExpectError(
    "read-content",
    tokens.owner,
    { action: "weekly", creator_id: ids.otherCreator },
    "creator_not_found",
  );
  assertEquals(crossWorkspace.status, 404, "cross workspace status");

  const locked = await invokeExpectError(
    "generate-week",
    tokens.owner,
    {
      creator_id: ids.creator,
      week_start_date: config.weekStartDate,
      weekly_setup_id: ids.setup,
    },
    "existing_published_week_locked",
  );
  assertEquals(locked.status, 409, "published week locked status");
  console.log("PASS live QA role and boundary checks");
}

async function generateWeek(): Promise<JsonObject> {
  const response = await invoke("generate-week", tokens.owner, {
    creator_id: ids.creator,
    week_start_date: config.weekStartDate,
    weekly_setup_id: ids.setup,
    mode: "generate_draft",
    preserve_manual_edits: true,
    response_mode: config.responseMode,
    ...(config.useMockAI ? { mock: true } : {}),
  }, { allowAccepted: true });
  return await resolveGenerationResponse(response);
}

async function regenerateDay(
  weeklyPlanID: string,
  scheduledDate: string,
): Promise<JsonObject> {
  const response = await invoke("generate-week", tokens.owner, {
    action: "regenerate_day",
    creator_id: ids.creator,
    weekly_plan_id: weeklyPlanID,
    scheduled_date: scheduledDate,
    preserve_manual_edits: true,
    response_mode: config.responseMode,
    ...(config.useMockAI ? { mock: true } : {}),
  }, { allowAccepted: true });
  return await resolveGenerationResponse(response);
}

async function resolveGenerationResponse(
  response: JsonObject,
): Promise<JsonObject> {
  if (response.status !== "running") {
    return response;
  }
  const generationID = requiredString(response.generation_id, "generation_id");
  for (let attempt = 0; attempt < 90; attempt += 1) {
    await delay(5000);
    const status = await invoke("generate-week", tokens.owner, {
      action: "status",
      generation_id: generationID,
      creator_id: ids.creator,
    }, { allowAccepted: true });
    if (status.status === "running") {
      console.log(
        `INFO generation ${generationID} running ${
          numberValue(status.completed_day_count) ?? "?"
        }/${numberValue(status.total_day_count) ?? "?"}`,
      );
      continue;
    }
    if (status.status === "failed") {
      fail(`generation failed: ${JSON.stringify(status)}`);
    }
    return status;
  }
  fail(`generation timed out: ${generationID}`);
}

async function importAndApproveReference(): Promise<string> {
  console.log("INFO admin importing QA reference");
  const stamp = Date.now();
  const rawText = [
    `https://www.instagram.com/reel/QALive${stamp}/`,
    `QA reference note ${stamp}`,
  ].join("\n");
  const preview = await invoke("import-references", tokens.owner, {
    mode: "preview",
    creator_id: ids.creator,
    input_type: "paste",
    raw_text: rawText,
    filename: null,
  });
  const checksum = requiredString(
    preview.preview_checksum,
    "import preview checksum",
  );
  assertTruthy(objectValue(preview.destination), "import destination");
  assertArray(preview.rows, "import preview rows");
  console.log("PASS admin previewed QA reference import");

  await invoke("import-references", tokens.owner, {
    mode: "confirm",
    creator_id: ids.creator,
    input_type: "paste",
    raw_text: rawText,
    filename: null,
    preview_checksum: checksum,
  });
  console.log("PASS admin confirmed QA reference import");

  const source = await requireSingle(
    "imported QA source reference",
    admin.from("source_references")
      .select("id,status")
      .eq("workspace_id", ids.workspace)
      .eq("creator_id", ids.creator)
      .ilike("source_url", `%QALive${stamp}%`)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
  );
  const sourceID = requiredString(source.id, "imported source id");

  console.log("INFO admin approving QA reference");
  const review = await invoke("review-reference", tokens.owner, {
    creator_id: ids.creator,
    item: { kind: "source_reference", id: sourceID },
    action: "edit",
    edit: {
      target_type: "reel",
      url: `https://www.instagram.com/reel/QALiveEdited${stamp}/`,
      notes: "QA approved live E2E reference.",
    },
  });
  assertEquals(review.result_status, "confirmed", "review result status");
  return sourceID;
}

async function invoke(
  functionName: string,
  token: string,
  body: JsonObject,
  options: { allowAccepted?: boolean } = {},
): Promise<JsonObject> {
  const response = await fetch(`${functionsURL}/${functionName}`, {
    method: "POST",
    headers: headers(token),
    body: JSON.stringify(body),
  });
  const data = await response.json().catch(() => null);
  if (!response.ok && !(options.allowAccepted && response.status === 202)) {
    fail(
      `${functionName} failed with ${response.status}: ${JSON.stringify(data)}`,
    );
  }
  if (response.status === 202 && !options.allowAccepted) {
    fail(`${functionName} returned unexpected async response`);
  }
  return requireObject(data, functionName);
}

async function invokeExpectError(
  functionName: string,
  token: string,
  body: JsonObject,
  expectedError: string,
): Promise<{ status: number; body: JsonObject }> {
  const response = await fetch(`${functionsURL}/${functionName}`, {
    method: "POST",
    headers: headers(token),
    body: JSON.stringify(body),
  });
  const data = requireObject(
    await response.json().catch(() => null),
    functionName,
  );
  assertEquals(
    stringValue(data.error),
    expectedError,
    `${functionName} error code`,
  );
  console.log(`PASS ${functionName} rejected with ${expectedError}`);
  return { status: response.status, body: data };
}

function headers(token: string): HeadersInit {
  return {
    Authorization: `Bearer ${config.publishableKey}`,
    apikey: config.publishableKey,
    "Content-Type": "application/json",
    "x-mco-device-token": token,
  };
}

async function requireSingle(label: string, promise: PromiseLike<unknown>) {
  const value = await promise as {
    data?: unknown;
    error?: { message?: string };
  };
  if (value.error) {
    fail(`${label} failed: ${value.error.message ?? "unknown error"}`);
  }
  const row = objectValue(value.data);
  if (!row) {
    fail(`${label} not found`);
  }
  return row;
}

async function must(label: string, promise: PromiseLike<unknown>) {
  const value = await promise as { error?: { message?: string } };
  if (value.error) {
    fail(`${label} failed: ${value.error.message ?? "unknown error"}`);
  }
}

function assertGeneratedCards(cards: unknown[], dates: string[]) {
  for (const [index, value] of cards.entries()) {
    const card = requireObject(value, `generated card ${index}`);
    assertEquals(
      requiredString(card.scheduled_date, `generated card ${index} date`),
      dates[index],
      `generated card ${index} scheduled date`,
    );
    requiredString(card.title, `generated card ${index} title`);
    requiredString(card.why_today, `generated card ${index} why_today`);
    requiredString(card.caption, `generated card ${index} caption`);
    requiredString(card.script, `generated card ${index} script`);
    assertArray(card.scene_list, `generated card ${index} scene_list`);
    assertArray(card.hashtags, `generated card ${index} hashtags`);
    assertTruthy(
      typeof card.estimated_shoot_minutes === "number",
      `generated card ${index} minutes`,
    );
  }
}

function weekDates(weekStartDate: string): string[] {
  const [year, month, day] = weekStartDate.split("-").map(Number);
  const start = new Date(Date.UTC(year, month - 1, day));
  return Array.from({ length: 7 }, (_, index) => {
    const date = new Date(start);
    date.setUTCDate(start.getUTCDate() + index);
    return date.toISOString().slice(0, 10);
  });
}

function nextWeek(dateString: string): string {
  const [year, month, day] = dateString.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day + 7));
  return date.toISOString().slice(0, 10);
}

function isDateString(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(value);
}

async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function objectValue(value: unknown): JsonObject | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonObject
    : null;
}

function requireObject(value: unknown, label: string): JsonObject {
  const object = objectValue(value);
  if (!object) {
    fail(`${label} is not an object`);
  }
  return object;
}

function requiredArray(value: unknown, label: string): unknown[] {
  if (!Array.isArray(value)) {
    fail(`${label} is not an array`);
  }
  return value;
}

function assertArray(value: unknown, label: string) {
  requiredArray(value, label);
}

function requiredString(value: unknown, label: string): string {
  const string = stringValue(value);
  if (!string) {
    fail(`${label} is missing`);
  }
  return string;
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function numberValue(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) {
    fail(message);
  }
}

function assertTruthy(value: unknown, message: string) {
  if (!value) {
    fail(message);
  }
}

function assertEquals(actual: unknown, expected: unknown, message: string) {
  if (actual !== expected) {
    fail(
      `${message}: expected ${JSON.stringify(expected)}, got ${
        JSON.stringify(actual)
      }`,
    );
  }
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function env(name: string): string | undefined {
  return Deno.env.get(name)?.trim() || undefined;
}

function requiredEnv(name: string): string {
  const value = env(name);
  if (!value) {
    fail(`missing ${name}`);
  }
  return value;
}

function fail(message: string): never {
  throw new Error(`FAIL ${message}`);
}
