import type { MiraInput } from "./contracts.ts";

const TEXT_TIMEOUT_MS = 55_000;
const MIN_LEASE_SECONDS = 90;
const LEASE_MARGIN_MS = 20_000;
const CLAIM_BUFFER_MS = 5_000;

export const AI_TIMEOUT_MS = {
  ideas: TEXT_TIMEOUT_MS,
  todayIdea: TEXT_TIMEOUT_MS,
  script: TEXT_TIMEOUT_MS,
  storyboard: TEXT_TIMEOUT_MS,
  reviseScript: TEXT_TIMEOUT_MS,
  reviseShot: TEXT_TIMEOUT_MS,
  reviseStoryboard: TEXT_TIMEOUT_MS,
  requirements: TEXT_TIMEOUT_MS,
  shotPictures: 100_000,
} satisfies Record<MiraInput["operation"] | "shotPictures", number>;

type AIOperation = keyof typeof AI_TIMEOUT_MS;

export function leaseSeconds(operation?: AIOperation): number {
  const timeoutMs = operation ? AI_TIMEOUT_MS[operation] : TEXT_TIMEOUT_MS;
  return Math.max(
    MIN_LEASE_SECONDS,
    Math.ceil((timeoutMs + LEASE_MARGIN_MS + CLAIM_BUFFER_MS) / 1_000),
  );
}

export function providerDeadline(
  operation: AIOperation,
  leaseUntil: string,
): AbortSignal {
  const timeoutMs = AI_TIMEOUT_MS[operation];
  if (!(Date.parse(leaseUntil) - Date.now() >= timeoutMs + LEASE_MARGIN_MS)) {
    throw Error("mira_insufficient_lease_budget");
  }
  return AbortSignal.timeout(timeoutMs);
}
