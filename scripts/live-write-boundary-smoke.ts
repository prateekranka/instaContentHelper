type JsonObject = Record<string, unknown>;

const supabaseURL = requiredEnv("MCO_SUPABASE_URL").replace(/\/+$/, "");
const publishableKey = requiredEnv("MCO_SUPABASE_PUBLISHABLE_KEY");
const creatorID = requiredEnv("MCO_LIVE_CREATOR_ID");
const deviceToken = requiredEnv("MCO_LIVE_DEVICE_TOKEN");
const todayDate = env("MCO_LIVE_TODAY_DATE") ?? todayDateString();
const writeSmokeEnabled = env("MCO_LIVE_WRITE_SMOKE") === "1";

await expectError(
  "read-content rejects invalid token",
  "read-content",
  { action: "today", creator_id: creatorID, today_date: todayDate },
  "definitely-invalid-device-token",
  "invalid_device_token",
);

const today = await invoke(
  "read-content",
  { action: "today", creator_id: creatorID, today_date: todayDate },
  deviceToken,
);

const todayCard = objectValue(today.today_card);
if (!todayCard) {
  fail(`read-content today returned no card for ${todayDate}`);
}

const todayCardID = stringValue(todayCard.id) ?? "";
const archiveDate = stringValue(todayCard.scheduled_date) ?? todayDate;
if (!isUUID(todayCardID)) {
  fail("read-content today card is missing a valid id");
}

console.log(
  `PASS read-content today returned ${todayCardID} for ${archiveDate}`,
);

if (writeSmokeEnabled) {
  await runWriteSmoke(todayCardID, archiveDate);
} else {
  console.log(
    "SKIP write smoke. Set MCO_LIVE_WRITE_SMOKE=1 to mutate live data.",
  );
}

async function runWriteSmoke(dailyCardID: string, archiveDate: string) {
  const decisionStatus = env("MCO_LIVE_DECISION_STATUS") ??
    "saved_for_tomorrow";
  const outputLine = env("MCO_LIVE_OUTPUT_LINE") ??
    "Live smoke: write boundary decision";
  const hasPostThumbnail = env("MCO_LIVE_HAS_POST_THUMBNAIL") === "1";

  const completeResponse = await invoke(
    "write-content",
    {
      action: "complete_today",
      creator_id: creatorID,
      daily_card_id: env("MCO_LIVE_DAILY_CARD_ID") ?? dailyCardID,
      decision: {
        status: decisionStatus,
        output_line: outputLine,
        has_post_thumbnail: hasPostThumbnail,
      },
      decision_at: new Date().toISOString(),
    },
    deviceToken,
  );
  const completedCard = requireObject(
    completeResponse.daily_card,
    "complete_today daily_card",
  );
  assertEquals(
    stringValue(completedCard.status),
    decisionStatus,
    "complete_today status",
  );
  assertTruthy(
    stringValue(completedCard.completed_by_member_id),
    "complete_today completed_by_member_id",
  );
  console.log("PASS write-content complete_today");

  const archiveResponse = await invoke(
    "write-content",
    {
      action: "upsert_archive_decision",
      creator_id: creatorID,
      daily_card_id: env("MCO_LIVE_DAILY_CARD_ID") ?? dailyCardID,
      archive_date: env("MCO_LIVE_ARCHIVE_DATE") ?? archiveDate,
      decision: decisionStatus,
      output_line: outputLine,
      has_post_thumbnail: hasPostThumbnail,
    },
    deviceToken,
  );
  const archiveEntry = requireObject(
    archiveResponse.archive_entry,
    "upsert_archive_decision archive_entry",
  );
  assertEquals(
    stringValue(archiveEntry.decision),
    decisionStatus,
    "archive decision",
  );
  console.log("PASS write-content upsert_archive_decision");

  const ideaID = env("MCO_LIVE_IDEA_ID");
  if (ideaID) {
    const selectResponse = await invoke(
      "write-content",
      {
        action: "select_idea_for_next_open_day",
        creator_id: creatorID,
        idea_id: ideaID,
        weekly_plan_id: env("MCO_LIVE_WEEKLY_PLAN_ID") ?? null,
      },
      deviceToken,
    );
    const selectedIdea = requireObject(
      selectResponse.idea,
      "select_idea_for_next_open_day idea",
    );
    assertEquals(stringValue(selectedIdea.status), "scheduled", "idea status");
    console.log("PASS write-content select_idea_for_next_open_day");

    const creatorRoleToken = env("MCO_LIVE_CREATOR_ROLE_DEVICE_TOKEN");
    if (creatorRoleToken) {
      await expectError(
        "creator role rejected for select_idea_for_next_open_day",
        "write-content",
        {
          action: "select_idea_for_next_open_day",
          creator_id: creatorID,
          idea_id: ideaID,
          weekly_plan_id: env("MCO_LIVE_WEEKLY_PLAN_ID") ?? null,
        },
        creatorRoleToken,
        "role_not_allowed",
      );
    }
  } else {
    console.log("SKIP select idea smoke. Set MCO_LIVE_IDEA_ID to test it.");
  }
}

async function invoke(
  functionName: string,
  body: JsonObject,
  token: string,
): Promise<JsonObject> {
  const response = await fetch(`${supabaseURL}/functions/v1/${functionName}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${publishableKey}`,
      apikey: publishableKey,
      "Content-Type": "application/json",
      "x-mco-device-token": token,
    },
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
    headers: {
      Authorization: `Bearer ${publishableKey}`,
      apikey: publishableKey,
      "Content-Type": "application/json",
      "x-mco-device-token": token,
    },
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

function todayDateString(): string {
  return new Date().toISOString().slice(0, 10);
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

function assertEquals(
  actual: string | undefined,
  expected: string,
  label: string,
) {
  if (actual !== expected) {
    fail(`${label}: expected ${expected}, got ${actual ?? "undefined"}`);
  }
}

function assertTruthy(value: unknown, label: string) {
  if (!value) {
    fail(`${label} was empty`);
  }
}

function isUUID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

function fail(message: string): never {
  throw new Error(message);
}
