import { normalizedMaxRows } from "./index.ts";

Deno.test("normalizedMaxRows clamps week thumbnail batches", () => {
  assertEquals(normalizedMaxRows(undefined), 6);
  assertEquals(normalizedMaxRows(0), 1);
  assertEquals(normalizedMaxRows(3.8), 3);
  assertEquals(normalizedMaxRows(99), 12);
});

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Assertion failed:\nactual: ${JSON.stringify(actual)}\nexpected: ${
        JSON.stringify(expected)
      }`,
    );
  }
}
