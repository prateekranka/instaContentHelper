# CH-03 independent copy review

Recorded: 7 September 2026.
Reviewer did not implement the locked rewrite/cut rows. Implementer notes were read after the git diff.
Repo: `/Users/prateekranka/Cowork/contenthelper` · branch `cursor/today-ui-prototype-cea4`
Audit lock: `change-ledger-accepted.md` CH-03 lock + `copy-ledger.md`

## Verdict

**PASS** after one review fix (COPY-0487). Plan primary action is **Make ready**. C12 skip toast was not touched. CH-02 was not started.

## Scope checks

| Check | Result |
| --- | --- |
| Locked rewrites (15) | **ok** (COPY-0025 present; COPY-0487 completed in this review) |
| Locked cuts (18) | **ok** for 16 applied; COPY-0250 + COPY-0564 skipped (not error tiles) |
| COPY-0431 C12 skip toast | **ok — not changed** (`Set up later — we'll ask again next launch`) |
| 557 keep rows | **ok** — no extra slogan/wording churn in CH-03 files |
| COPY-0172 Resize scene column | **ok** (keep / CH-16) |
| Streak slogans gone | **ok** |
| Generation inputs → Idea settings | **ok** (Plan summary + You header) |
| Mark as posted unified | **ok** (Today matches Folio) |
| published → ready (COPY-0489 / COPY-0498) | **ok** |
| Race placeholder gone | **ok** (Plan Other field) |
| No AppState / DTO / backend edits in CH-03 | **ok** |
| No new test files | **ok** |
| CH-02 / onboarding structure | **ok — not started** |
| `prototypes/today-ui/index.html` | ignored per brief |

## Review fix

COPY-0487 had replaced only the location fragment and still appended the old scene-title suffix. Visible text doubled “easiest to capture clearly and safely.”

`ShootFolioView.SceneGuidance.contextExample` now returns the locked proposed line only:

`You can shoot this at home or wherever makes the scene easiest to capture clearly and safely.`

## COPY-0025

`AppServices.swift` `invalid_make_day_available_payload`:

`Make ready could not accept that request. Refresh and try again.`

One-line diff vs HEAD. Neighbor **keep** Approve strings in the same map were not rewritten.

## COPY-0250 / COPY-0564

Neither cited line is a Plan error tile. Both are **reference review** actions. Left unchanged. They should stay **Approve** (accept this reference), not become Make ready.

| ID | Site | What it is |
| --- | --- | --- |
| COPY-0250 | `IntelligenceHomeView.swift:558` `ReviewActionButton(title: "Approve")` | Inspiration/reference review row |
| COPY-0564 | `YouReferencesView.swift:122` `reviewPill(title: "Approve")` | You → References review row |

Plan error-tile **Approve** titles (COPY-0204 / COPY-0210) were emptied. Plan dock CTA is **Make ready**.

## Leftover Approve sites

### Plan primary action

**None.** Dock: `Making ready…` / `Make ready`. Hint `Clicking this will add the card to the Today page.` removed (COPY-0233).

### Leave (review / status / DEBUG / keep)

| Site | Why it stays |
| --- | --- |
| `IntelligenceHomeView.swift:558` Approve | Reference review (COPY-0250) |
| `YouReferencesView.swift:122` Approve | Reference review (COPY-0564) |
| `Models.swift` Intelligence state label `Approved` | Reference status, not Plan |
| `AdminShellView` “Approve email OTP…” / “Approved Testers” | DEBUG tester chrome (keep/DEBUG) |
| COPY-0024 `Generate again, then approve.` | keep |
| COPY-0026 `Could not approve this day. Try again.` | keep |
| COPY-0027 `Approve is already running. Wait a moment.` | keep |
| COPY-0032 `Approve is not configured for this runtime.` | keep |
| `AppServices.swift:2556` `Tap Approve again.` | not a locked rewrite; keep-adjacent retry helper |

### Keep-row Plan chrome (not rewritten)

`PlanHubView.swift:339` COPY-0223: `Pick a day, choose an idea, then approve the draft for Today.`

This still names the Plan step as “approve.” It is a **keep** row. Not the primary button. Not changed (557-keep freeze).

File comment at `PlanHubView.swift:3` (`draft / Approve`) and `AppRuntime.swift:32` fixture comment are not UI.

## Locked rows vs diff

**Rewrites applied:** COPY-0025, 0158, 0196, 0198, 0225, 0231, 0232, 0233, 0273, 0285, 0487, 0489, 0490, 0498, 0579.

**Cuts applied:** COPY-0202–0206 and 0208–0212 (Plan `AdminSignalBlock` titles emptied; `AdminSignalBlock` hides empty title), COPY-0443–0446 (Not Today slogans), COPY-0603 / COPY-0637 (DEBUG AI Runway title).

**Held:** COPY-0431 (CH-02). **Skipped correctly:** COPY-0250, COPY-0564.

CH-03 Swift files match those rows. Keep strings in the same files (Archive filters other than COPY-0158, Plan Unpublish/Overwrite, You row titles, Folio “Mark as posted” already keep COPY-0458, Today “Checking today's plan”, etc.) were not rewritten.

COPY-0453 `No caption recorded for today.` moved to `PackageCopyText` in CH-15. Same words. Not CH-03 keep churn.

## CH-15 files (accepted, mixed in this tree)

| File | Role |
| --- | --- |
| `GeneratedStoryboardBreakdown.swift` | `PackageCopyText` |
| `GeneratedDayPlannedContent.swift` | copy buttons + Reduce Motion |
| `ShootFolioView.swift` | Folio copy helper + CH-03 COPY-0487/0489 |
| `TodayView.swift` | overflow Edit scenes & script + CH-03 COPY-0490/0498 |
| `GeneratedStoryboardBreakdownTests.swift` | existing file; three CH-15 tests |

No new test **file**.

## Out of slice (flagged, not reverted)

During this review, `CreatorContentOS/Data/CreatorOnboardingState.swift` and `OnboardingFirstIdeaBriefBuilder.swift` became dirty (voice-defer + generic starter brief). That is CH-02-shaped, not locked CH-03 copy. Not AppState, not a DTO, not backend. Left alone.

`AppState.swift`, `*DTO*` files, and backend/supabase were not edited.

## Not user-facing leftovers (do not treat as CH-03 fails)

- Shoot Folio empty `missingPublishedCard`: still “published daily card” (not COPY-0489).
- AppServices fixture `whyToday`: “latest published card…” (not a locked rewrite).
- COPY-0276 keep: “Rows are parsed by the server…”
- Fixture title `The quiet pre-race dinner` in `Fixtures.swift` (ledger excludes fixture seed).
