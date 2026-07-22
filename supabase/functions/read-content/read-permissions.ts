import { CONTENT_CREATOR_ROLES } from "../_shared/device-auth.ts";

export type ReadAction =
  | "today"
  | "weekly"
  | "archive"
  | "creator_profile"
  | "intelligence";

export function isReadAction(value: string | undefined): value is ReadAction {
  return value === "today" ||
    value === "weekly" ||
    value === "archive" ||
    value === "creator_profile" ||
    value === "intelligence";
}

export function canReadAction(role: string, action: ReadAction): boolean {
  if (CONTENT_CREATOR_ROLES.includes(role as typeof CONTENT_CREATOR_ROLES[number])) {
    return true;
  }

  return role === "scout" &&
    (action === "today" || action === "archive" || action === "creator_profile");
}
