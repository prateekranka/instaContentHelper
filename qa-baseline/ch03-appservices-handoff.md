# CH-03 AppServices handoff (Grok)

Repo: `/Users/prateekranka/Cowork/contenthelper`  
Scope: copy-only rows in `AppServices.swift` — **do not edit in CH-03 slice** (Grok owns `AppServices.swift`).

## Rewrite rows deferred to Grok

| ID | File:line (ledger) | Existing | Proposed | Notes |
| --- | --- | --- | --- | --- |
| COPY-0025 | `CreatorContentOS/App/AppServices.swift:2532` | Approve could not accept that request. Refresh and try again. | Make ready could not accept that request. Refresh and try again. | Key: `invalid_make_day_available_payload` in `DayAvailabilityErrorDisplay.userFacingMessages`. |

**Status at CH-03 verify (7 Sep 2026):** line 2532 already reads `Make ready could not accept that request. Refresh and try again.` — no further Grok action unless other Approve-aligned **keep** rows are promoted later (e.g. `Tap Approve again` at ~2556).

## Not in CH-03 AppServices scope

- No other copy-ledger **rewrite** or **cut** rows target `AppServices.swift`.
- **557 keep** rows in AppServices remain unchanged by CH-03.

## Related C1 alignment (informational — keep rows today)

These stay **keep** in the ledger but may read odd next to Make ready until a future pass:

- `make_day_available_already_running`: "Approve is already running. Wait a moment."
- `make_day_available_not_configured`: "Approve is not configured for this runtime."
- Connection retry helper (~2556): "Tap Approve again."

Not CH-03 scope unless parent expands beyond the locked 15 rewrite rows.
