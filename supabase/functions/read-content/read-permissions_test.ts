import { canReadAction } from "./read-permissions.ts";

Deno.test("canReadAction allows creators to read weekly and intelligence", () => {
  assertEquals(canReadAction("creator", "weekly"), true);
  assertEquals(canReadAction("creator", "intelligence"), true);
  assertEquals(canReadAction("owner", "weekly"), true);
  assertEquals(canReadAction("editor", "intelligence"), true);
});

Deno.test("canReadAction keeps scout reads limited to today, archive, and profile", () => {
  assertEquals(canReadAction("scout", "today"), true);
  assertEquals(canReadAction("scout", "archive"), true);
  assertEquals(canReadAction("scout", "creator_profile"), true);
  assertEquals(canReadAction("scout", "weekly"), false);
  assertEquals(canReadAction("scout", "intelligence"), false);
});

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  if (
    actual !== expected && JSON.stringify(actual) !== JSON.stringify(expected)
  ) {
    throw new Error(
      message ??
        `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
