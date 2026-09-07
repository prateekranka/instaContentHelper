# CH-04 Paper trim

File: `ContentHelper — Launch screens and states — 2026-09-07`  
File ID: `01M1Y4N6TY7JGA07N987FFNJWP`  
Recorded: 7 September 2026  
Method: Paper Desktop UI on this Mac (layers list + Delete). Paper MCP write quota was already exhausted. No Paper Pro purchase. No Buy / Upgrade / Subscribe / Start trial click.

## Deleted

**yes** — all five extra artboards.

| Deleted | Layer name in Paper |
| --- | --- |
| Coverage matrix / index | `AB-INDEX — Coverage matrix` |
| Pocket Sheet component sheet | `AB-CMP — Pocket Sheet component…` |
| A11y equivalence classes | `AB-A11Y — Equivalence classes` |
| Debug AdminShell | `AB-DBG-ADMIN — Debug shell` |
| Five-step onboarding evidence | `AB-CUR-ONB-HIST — Five-step evidence` |

## Remaining

Eight artboards on Page 1. Keep list matches.

| Keep intent | Layer name in Paper |
| --- | --- |
| One-screen onboarding | `AB-CUR-ONB-1 — One skippable s…` |
| AI consent | `AB-CUR-CONSENT — AI consent sl…` |
| Shoot Folio | `AB-CUR-SHOOT — Folio overflow` |
| Today | `AB-CUR-TODAY-ready — Inline pac…` |
| Plan Make ready | `AB-CUR-PLAN-hub — Make ready` |
| Creator tabs | `AB-CUR-SHELL — Creator tabs` |
| Proposed deletion | `AB-PRO-DELETE — Account deletio…` |
| Proposed privacy | `AB-PRO-PRIVACY — Policy URL gap…` |

## Screenshots

Paths under `qa-baseline/screens/paper/`:

- `01-before.png` — 13 artboards before trim
- `02-layers.png` — layers panel crop before trim
- `03-selected.png` — five extras selected
- `04-after-delete.png` — first Delete key did not apply (cliclick)
- `05-after-keycode-delete.png` — five extras gone after System Events Delete
- `06-remaining.png` — remaining eight names
- `07-remaining-focused.png` — `AB-CUR-ONB-1` selected (390×844). Keep names still listed.

## Notes

- Paper MCP `delete_nodes` / reads were blocked: weekly MCP limit.
- Desktop Delete worked on the second try with Mac Delete (key code 51) after Cmd-click in the layers list.
- No paywall showed. Stopped without buying.
