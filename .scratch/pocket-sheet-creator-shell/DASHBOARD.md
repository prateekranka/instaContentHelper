# Pocket-sheet ticket dashboard

Live board: [pocket-sheet-tickets.canvas.tsx](/Users/prateekranka/.cursor/projects/Users-prateekranka-Documents-Codex-2026-06-19-contenthelper-ui-audit/canvases/pocket-sheet-tickets.canvas.tsx)

Machine status: `dashboard-status.json` in this folder.

When you mark a ticket **in_progress** or **done**, update **both**:

1. `dashboard-status.json` — set `status`, optional `notes`, and bump `updatedAt`.
2. The inline `TICKETS` array in the canvas file (same fields). The canvas cannot read JSON at runtime.

MVP implement order is `mvpOrder` in the JSON; hold tickets 11–13 stay after that sequence on the board.
