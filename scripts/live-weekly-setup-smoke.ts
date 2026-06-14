import { createClient } from "jsr:@supabase/supabase-js@2";

type JsonObject = Record<string, unknown>;

const supabaseURL = requiredEnv("MCO_SUPABASE_URL").replace(/\/+$/, "");
const publishableKey = requiredEnv("MCO_SUPABASE_PUBLISHABLE_KEY");
const serviceRoleKey = requiredEnv("MCO_SUPABASE_SERVICE_ROLE_KEY");
const creatorID = requiredEnv("MCO_LIVE_CREATOR_ID");
const providedDeviceToken = env("MCO_LIVE_DEVICE_TOKEN");
const weeklyPlanID = env("MCO_LIVE_WEEKLY_PLAN_ID");
const smokeValue = `Live smoke place ${new Date().toISOString()}`;

const admin = createClient(supabaseURL, serviceRoleKey, {
  auth: { persistSession: false },
});

const creator = await requireSingle(
  "creator",
  admin.from("creators")
    .select("id,workspace_id,status")
    .eq("id", creatorID)
    .eq("status", "active")
    .maybeSingle(),
);
const workspaceID = stringValue(creator.workspace_id);
if (!workspaceID) {
  fail("creator is missing workspace_id");
}

const tempSession = providedDeviceToken
  ? null
  : await createTemporaryDeviceSession(workspaceID);
const deviceToken = providedDeviceToken ?? tempSession!.deviceToken;

try {
  const weeklyPlan = await selectWeeklyPlan(
    workspaceID,
    creatorID,
    weeklyPlanID,
  );
  const weeklySetupID = stringValue(weeklyPlan.weekly_setup_id);
  if (!weeklySetupID) {
    fail("selected weekly plan has no weekly_setup_id");
  }

  const originalSetup = await requireSingle(
    "weekly setup",
    admin.from("weekly_setups")
      .select("id,location")
      .eq("workspace_id", workspaceID)
      .eq("creator_id", creatorID)
      .eq("id", weeklySetupID)
      .maybeSingle(),
  );
  const originalLocation = stringValue(originalSetup.location);

  await invoke("write-content", {
    action: "update_weekly_setup",
    creator_id: creatorID,
    weekly_plan_id: weeklyPlan.id,
    setup_sections: [{ title: "Place", summary: smokeValue }],
  }, deviceToken);
  console.log("PASS write-content update_weekly_setup smoke edit");

  const editedWeekly = await invoke("read-content", {
    action: "weekly",
    creator_id: creatorID,
  }, deviceToken);
  const editedSetup = objectValue(editedWeekly.weekly_setup);
  assertEquals(
    stringValue(editedSetup?.location),
    smokeValue,
    "read-content weekly smoke location",
  );
  console.log("PASS read-content weekly saw smoke edit");

  await invoke("write-content", {
    action: "update_weekly_setup",
    creator_id: creatorID,
    weekly_setup_id: weeklySetupID,
    setup_sections: [{ title: "Place", summary: originalLocation ?? "" }],
  }, deviceToken);
  console.log("PASS write-content restored weekly setup");

  const restoredWeekly = await invoke("read-content", {
    action: "weekly",
    creator_id: creatorID,
  }, deviceToken);
  const restoredSetup = objectValue(restoredWeekly.weekly_setup);
  assertEquals(
    stringValue(restoredSetup?.location),
    originalLocation,
    "read-content weekly restored location",
  );
  console.log("PASS read-content weekly saw restored value");
  console.log("PASS live weekly setup smoke");
} finally {
  if (tempSession) {
    await admin
      .from("device_installations")
      .delete()
      .eq("id", tempSession.deviceInstallationID);
    console.log("PASS removed temporary smoke device installation");
  }
}

async function createTemporaryDeviceSession(workspaceID: string) {
  const member = await requireSingle(
    "owner/editor member",
    admin.from("members")
      .select("id,role,status")
      .eq("workspace_id", workspaceID)
      .eq("status", "active")
      .in("role", ["owner", "editor"])
      .order("role", { ascending: false })
      .limit(1)
      .maybeSingle(),
  );
  const memberID = stringValue(member.id);
  if (!memberID) {
    fail("no active owner/editor member found");
  }

  const deviceToken = randomToken();
  const deviceInstallationID = crypto.randomUUID();
  await requireSuccess(
    "insert temporary device installation",
    admin.from("device_installations").insert({
      id: deviceInstallationID,
      workspace_id: workspaceID,
      member_id: memberID,
      device_name: "Live weekly setup smoke",
      platform: "ios",
      token_hash: await sha256Hex(deviceToken),
    }),
  );
  console.log("PASS created temporary owner/editor smoke device");
  return { deviceInstallationID, deviceToken };
}

async function selectWeeklyPlan(
  workspaceID: string,
  creatorID: string,
  preferredWeeklyPlanID?: string,
) {
  let query = admin.from("weekly_plans")
    .select("id,weekly_setup_id,week_start_date,status,updated_at")
    .eq("workspace_id", workspaceID)
    .eq("creator_id", creatorID)
    .not("weekly_setup_id", "is", null);

  if (preferredWeeklyPlanID) {
    query = query.eq("id", preferredWeeklyPlanID);
  } else {
    query = query
      .in("status", ["draft", "reviewed", "published"])
      .order("updated_at", { ascending: false })
      .limit(1);
  }

  return await requireSingle("weekly plan", query.maybeSingle());
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

async function requireSingle(label: string, promise: PromiseLike<unknown>) {
  const value = await promise as {
    data?: unknown;
    error?: { message?: string };
  };
  if (value.error) {
    fail(`${label} lookup failed: ${value.error.message ?? "unknown error"}`);
  }
  const row = objectValue(value.data);
  if (!row) {
    fail(`${label} not found`);
  }
  return row;
}

async function requireSuccess(label: string, promise: PromiseLike<unknown>) {
  const value = await promise as { error?: { message?: string } };
  if (value.error) {
    fail(`${label} failed: ${value.error.message ?? "unknown error"}`);
  }
}

function randomToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
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

function stringValue(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function assertEquals(actual: unknown, expected: unknown, label: string) {
  if (actual !== expected) {
    fail(
      `${label}: expected ${JSON.stringify(expected)}, got ${
        JSON.stringify(actual)
      }`,
    );
  }
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
