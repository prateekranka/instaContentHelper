import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildReadyReport,
  deriveNudge,
  formatCount,
  formatDelta,
  hasAnyMetric,
  isProfessional,
  needsRefresh,
  normalizeAccountType,
} from "./instagram.ts";

Deno.test("normalizeAccountType maps IG values", () => {
  assertEquals(normalizeAccountType("BUSINESS"), "business");
  assertEquals(normalizeAccountType("MEDIA_CREATOR"), "media_creator");
  assertEquals(normalizeAccountType("CREATOR"), "media_creator");
  assertEquals(normalizeAccountType("PERSONAL"), "personal");
  assertEquals(normalizeAccountType("something-else"), "unknown");
  assertEquals(normalizeAccountType(null), "unknown");
});

Deno.test("isProfessional only for business/creator", () => {
  assertEquals(isProfessional("business"), true);
  assertEquals(isProfessional("media_creator"), true);
  assertEquals(isProfessional("personal"), false);
  assertEquals(isProfessional("unknown"), false);
});

Deno.test("formatCount groups thousands and rejects null/NaN", () => {
  assertEquals(formatCount(12430), "12,430");
  assertEquals(formatCount(0), "0");
  assertEquals(formatCount(null), null);
  assertEquals(formatCount(Number.NaN), null);
});

Deno.test("formatDelta absolute uses count-with-sign", () => {
  assertEquals(formatDelta(12430, 12392, "absolute"), "+38 this week");
  assertEquals(formatDelta(100, 130, "absolute"), "−30 this week");
  assertEquals(formatDelta(100, 100, "absolute"), "no change this week");
  assertEquals(formatDelta(100, null, "absolute"), null);
});

Deno.test("formatDelta percent rounds and guards zero baseline", () => {
  assertEquals(formatDelta(8214, 6733, "percent"), "up 22%");
  assertEquals(formatDelta(90, 100, "percent"), "down 10%");
  assertEquals(formatDelta(100, 100, "percent"), "no change");
  assertEquals(formatDelta(100, 0, "percent"), null);
  assertEquals(formatDelta(null, 100, "percent"), null);
});

Deno.test("deriveNudge picks the strongest riser above threshold", () => {
  const prev = { followersCount: 100, reach7d: 1000, saves7d: 100 };
  const savesUp = deriveNudge({ followersCount: 100, reach7d: 1000, saves7d: 140 }, prev);
  assertEquals(savesUp?.includes("Saves"), true);

  const reachUp = deriveNudge({ followersCount: 100, reach7d: 1300, saves7d: 101 }, prev);
  assertEquals(reachUp?.includes("Reach"), true);

  // Below threshold / no previous → no nudge.
  assertEquals(deriveNudge({ followersCount: 100, reach7d: 1010, saves7d: 101 }, prev), null);
  assertEquals(deriveNudge({ followersCount: 100, reach7d: 2000, saves7d: 200 }, null), null);
});

Deno.test("buildReadyReport includes only present metrics with deltas", () => {
  const current = { followersCount: 12430, reach7d: 8214, saves7d: null };
  const previous = { followersCount: 12392, reach7d: 6733, saves7d: null };
  const report = buildReadyReport(current, previous, {
    username: "mamta",
    accountType: "media_creator",
    source: "api",
    fetchedAt: "2026-11-01T12:00:00Z",
    dataQuality: "partial",
  });
  assertEquals(report.state, "ready");
  assertEquals(report.connected, true);
  assertEquals(report.metrics?.length, 2); // saves omitted (null)
  assertEquals(report.metrics?.[0], {
    id: "followers",
    label: "Followers",
    value: "12,430",
    delta: "+38 this week",
  });
  assertEquals(report.metrics?.[1].delta, "up 22%");
});

Deno.test("hasAnyMetric detects all-null", () => {
  assertEquals(hasAnyMetric({ followersCount: null, reach7d: null, saves7d: null }), false);
  assertEquals(hasAnyMetric({ followersCount: 1, reach7d: null, saves7d: null }), true);
});

Deno.test("needsRefresh true only within the window", () => {
  const now = new Date("2026-11-01T00:00:00Z");
  assertEquals(needsRefresh("2026-11-03T00:00:00Z", now), true); // 2 days out
  assertEquals(needsRefresh("2026-12-15T00:00:00Z", now), false); // far out
  assertEquals(needsRefresh(null, now), false);
});
