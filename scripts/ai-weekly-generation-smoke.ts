type JsonObject = Record<string, unknown>;

const supabaseURL = requiredEnv("MCO_SUPABASE_URL").replace(/\/+$/, "");
const publishableKey = requiredEnv("MCO_SUPABASE_PUBLISHABLE_KEY");
const creatorID = requiredEnv("MCO_LIVE_CREATOR_ID");
const ownerEditorToken = requiredEnv("MCO_LIVE_DEVICE_TOKEN");
const weekStartDate = requiredEnv("MCO_LIVE_AI_WEEK_START_DATE");
const weeklySetupID = env("MCO_LIVE_AI_WEEKLY_SETUP_ID");
const allowDraftMutation = env("MCO_LIVE_AI_DRAFT_SMOKE") === "1";
const allowPublishMutation = env("MCO_LIVE_AI_PUBLISH_SMOKE") === "1";

if (!isUUID(creatorID)) {
  fail("MCO_LIVE_CREATOR_ID must be a UUID");
}
if (!isDateString(weekStartDate)) {
  fail("MCO_LIVE_AI_WEEK_START_DATE must be YYYY-MM-DD");
}
if (weeklySetupID && !isUUID(weeklySetupID)) {
  fail("MCO_LIVE_AI_WEEKLY_SETUP_ID must be a UUID");
}
if (!allowDraftMutation) {
  fail(
    "AI smoke creates a draft weekly plan. Set MCO_LIVE_AI_DRAFT_SMOKE=1 after choosing a safe future/test week.",
  );
}

await expectError(
  "generate-week rejects invalid token",
  "generate-week",
  generateBody(),
  "definitely-invalid-device-token",
  "invalid_device_token",
);

const creatorRoleToken = env("MCO_LIVE_CREATOR_ROLE_DEVICE_TOKEN");
if (creatorRoleToken) {
  await expectError(
    "creator role rejected for generate-week",
    "generate-week",
    generateBody(),
    creatorRoleToken,
    "role_not_allowed",
  );
} else {
  console.log(
    "SKIP creator-role rejection. Set MCO_LIVE_CREATOR_ROLE_DEVICE_TOKEN to test it.",
  );
}

const generation = await invoke(
  "generate-week",
  generateBody(),
  ownerEditorToken,
);

const weeklyPlanID = requiredString(
  generation.weekly_plan_id,
  "generation weekly_plan_id",
);
assertEquals(requiredString(generation.status, "generation status"), "draft");
assertArrayLength(generation.daily_cards, 7, "generation daily_cards");
assertTruthy(
  requiredString(generation.strategy_summary, "generation strategy_summary"),
  "generation strategy_summary",
);

const cards = generation.daily_cards as unknown[];
for (const [index, cardValue] of cards.entries()) {
  const card = requireObject(cardValue, `daily_cards[${index}]`);
  assertEquals(
    requiredString(card.scheduled_date, `daily_cards[${index}].scheduled_date`),
    weekDates(weekStartDate)[index],
    `daily_cards[${index}].scheduled_date`,
  );
  requiredString(card.title, `daily_cards[${index}].title`);
  requiredString(card.why_today, `daily_cards[${index}].why_today`);
  requiredString(card.growth_job, `daily_cards[${index}].growth_job`);
  requiredString(card.content_pillar, `daily_cards[${index}].content_pillar`);
  requiredString(card.shootability, `daily_cards[${index}].shootability`);
  assertNumber(
    card.estimated_shoot_minutes,
    `daily_cards[${index}].estimated_shoot_minutes`,
  );
  requiredString(card.energy_required, `daily_cards[${index}].energy_required`);
  requiredString(card.language_mode, `daily_cards[${index}].language_mode`);
  assertNonEmptyArray(card.scene_list, `daily_cards[${index}].scene_list`);
  requiredString(card.script, `daily_cards[${index}].script`);
  requiredString(
    card.no_voiceover_version,
    `daily_cards[${index}].no_voiceover_version`,
  );
  assertNonEmptyArray(
    card.on_screen_text,
    `daily_cards[${index}].on_screen_text`,
  );
  requiredString(card.caption, `daily_cards[${index}].caption`);
  requiredString(card.cta, `daily_cards[${index}].cta`);
  assertNonEmptyArray(card.hashtags, `daily_cards[${index}].hashtags`);
  requiredString(card.cover_text, `daily_cards[${index}].cover_text`);
  requiredString(
    card.post_instructions,
    `daily_cards[${index}].post_instructions`,
  );
  requiredString(card.backup_story, `daily_cards[${index}].backup_story`);
  requiredString(
    card.backup_caption_only,
    `daily_cards[${index}].backup_caption_only`,
  );
  requiredString(
    card.audio_option_notes,
    `daily_cards[${index}].audio_option_notes`,
  );
  assertNumber(card.mamta_fit_score, `daily_cards[${index}].mamta_fit_score`);
  assertArray(card.risk_notes, `daily_cards[${index}].risk_notes`);
  assertArray(card.assumptions, `daily_cards[${index}].assumptions`);
  requiredString(card.source_note, `daily_cards[${index}].source_note`);
}
console.log(`PASS generate-week created draft ${weeklyPlanID}`);

const weeklyRead = await invoke(
  "read-content",
  { action: "weekly", creator_id: creatorID },
  ownerEditorToken,
);
const weeklyPlan = requireObject(weeklyRead.weekly_plan, "weekly weekly_plan");
assertEquals(
  requiredString(weeklyPlan.id, "weekly_plan.id"),
  weeklyPlanID,
  "weekly read draft plan id",
);
assertArrayLength(weeklyRead.daily_cards, 7, "weekly daily_cards");
console.log("PASS read-content weekly returns generated draft");

if (allowPublishMutation) {
  const publish = await invoke(
    "publish-week",
    {
      creator_id: creatorID,
      weekly_plan_id: weeklyPlanID,
    },
    ownerEditorToken,
  );
  assertEquals(
    String(publish.daily_card_count),
    "7",
    "publish daily_card_count",
  );
  console.log("PASS publish-week published generated draft");

  const today = await invoke(
    "read-content",
    {
      action: "today",
      creator_id: creatorID,
      today_date: weekStartDate,
    },
    ownerEditorToken,
  );
  const todayCard = requireObject(today.today_card, "today today_card");
  assertEquals(
    requiredString(todayCard.weekly_plan_id, "today_card.weekly_plan_id"),
    weeklyPlanID,
    "today generated weekly plan id",
  );
  requiredString(todayCard.script, "today_card.script");
  requiredString(todayCard.caption, "today_card.caption");
  console.log("PASS read-content today returns generated published card");
} else {
  console.log(
    "SKIP publish smoke. Set MCO_LIVE_AI_PUBLISH_SMOKE=1 only for a safe future/test week.",
  );
}

function generateBody(): JsonObject {
  return {
    creator_id: creatorID,
    week_start_date: weekStartDate,
    weekly_setup_id: weeklySetupID,
    mode: "generate_draft",
    preserve_manual_edits: true,
  };
}

async function invoke(
  functionName: string,
  body: JsonObject,
  token: string,
): Promise<JsonObject> {
  const response = await fetch(`${supabaseURL}/functions/v1/${functionName}`, {
    method: "POST",
    headers: headers(token),
    body: JSON.stringify(body),
  });
  const data = await response.json().catch(() => null);
  if (!response.ok) {
    fail(
      `${functionName} failed with ${response.status}: ${JSON.stringify(data)}`,
    );
  }
  return requireObject(data, functionName);
}

async function expectError(
  label: string,
  functionName: string,
  body: JsonObject,
  token: string,
  expectedError: string,
) {
  const response = await fetch(`${supabaseURL}/functions/v1/${functionName}`, {
    method: "POST",
    headers: headers(token),
    body: JSON.stringify(body),
  });
  const data = await response.json().catch(() => null);
  const actualError = objectValue(data) ? stringValue(data.error) : undefined;
  if (response.ok || actualError !== expectedError) {
    fail(
      `${label}: expected ${expectedError}, got status ${response.status} body ${
        JSON.stringify(data)
      }`,
    );
  }
  console.log(`PASS ${label}`);
}

function headers(token: string): HeadersInit {
  return {
    Authorization: `Bearer ${publishableKey}`,
    apikey: publishableKey,
    "Content-Type": "application/json",
    "x-mco-device-token": token,
  };
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

function objectValue(value: unknown): JsonObject | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonObject
    : null;
}

function requireObject(value: unknown, label: string): JsonObject {
  const object = objectValue(value);
  if (!object) {
    fail(`${label} was not an object`);
  }
  return object;
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function requiredString(value: unknown, label: string): string {
  const string = stringValue(value)?.trim();
  if (!string) {
    fail(`${label} was missing`);
  }
  return string;
}

function assertEquals(actual: string, expected: string, label = "value") {
  if (actual !== expected) {
    fail(`${label}: expected ${expected}, got ${actual}`);
  }
}

function assertTruthy(value: unknown, label: string) {
  if (!value) {
    fail(`${label} was empty`);
  }
}

function assertNumber(value: unknown, label: string) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    fail(`${label}: expected number, got ${JSON.stringify(value)}`);
  }
}

function assertArray(value: unknown, label: string) {
  if (!Array.isArray(value)) {
    fail(`${label}: expected array, got ${JSON.stringify(value)}`);
  }
}

function assertNonEmptyArray(value: unknown, label: string) {
  assertArray(value, label);
  if ((value as unknown[]).length === 0) {
    fail(`${label}: expected at least one item`);
  }
}

function assertArrayLength(value: unknown, length: number, label: string) {
  if (!Array.isArray(value) || value.length !== length) {
    fail(`${label}: expected ${length} rows, got ${JSON.stringify(value)}`);
  }
}

function isUUID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{12}$/i
    .test(value);
}

function isDateString(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(value);
}

function weekDates(startDate: string): string[] {
  const start = new Date(`${startDate}T00:00:00Z`);
  return Array.from({ length: 7 }, (_, index) => {
    const date = new Date(start);
    date.setUTCDate(start.getUTCDate() + index);
    return date.toISOString().slice(0, 10);
  });
}

function fail(message: string): never {
  throw new Error(message);
}
