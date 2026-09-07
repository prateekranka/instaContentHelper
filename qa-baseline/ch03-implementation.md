# CH-03 implementation record

Recorded: 7 September 2026, ~19:05–19:09 IST  
Repo: `/Users/prateekranka/Cowork/contenthelper`  
Audit: `/Users/prateekranka/Documents/Codex/2026-06-19/contenthelper-ui-audit`  
Simulator: ContentHelper QA · iPhone 16 · `FAE1FD16-D185-433C-AC85-544FF45F2C82`

## Summary

| Metric | Count |
| --- | ---: |
| Rewrite rows applied (non-AppServices) | **14** |
| Rewrite rows in AppServices (Grok / already present) | **1** (COPY-0025) |
| Cut rows applied | **16** |
| Cut rows skipped (ledger line drift) | **2** |
| Proposed skip-toast held for CH-02 | **1** (COPY-0431) |

**Applied total (ledger rows with code change this slice):** **30** of 33 locked rows (14 rewrite + 16 cut).  
**Skipped:** COPY-0025 (AppServices — handoff; already on disk), COPY-0431 (C12 / CH-02), COPY-0250 + COPY-0564 (no error tile at cited lines).

## Files changed

| File | Rows |
| --- | --- |
| `CreatorContentOS/Features/Daily/PlanHubView.swift` | COPY-0225, 0231, 0232, 0233; cuts 0202–0212 |
| `CreatorContentOS/Features/Daily/PlanGenerationInputsSummary.swift` | COPY-0198 |
| `CreatorContentOS/Features/Daily/PlanDayIdeaLauncher.swift` | COPY-0196 |
| `CreatorContentOS/Features/Archive/ArchiveView.swift` | COPY-0158 |
| `CreatorContentOS/Features/You/YouView.swift` | COPY-0579 |
| `CreatorContentOS/Features/Today/TodayView.swift` | COPY-0490, 0498 |
| `CreatorContentOS/Features/Today/ShootFolioView.swift` | COPY-0487, 0489 |
| `CreatorContentOS/Features/Today/NotTodaySheet.swift` | cuts 0443–0446 |
| `CreatorContentOS/Features/Intelligence/ReferenceImportPreviewView.swift` | COPY-0273 |
| `CreatorContentOS/Features/Intelligence/ReferenceImportView.swift` | COPY-0285 |
| `CreatorContentOS/Navigation/AdminShellView.swift` | `AdminSignalBlock` empty-title support; cuts 0603, 0637 |

**Not changed:** `AppServices.swift`, `AppState`, DTOs, backend, git identity, build number, HTML prototype, onboarding structure (CH-02), `OnboardingViewModel` skip toast (C12).

## Rewrites applied (14)

| ID | Location | Before → After |
| --- | --- | --- |
| COPY-0158 | `ArchiveView.swift` filter | Completed → **Shot & posted** |
| COPY-0196 | `PlanDayIdeaLauncher.swift` placeholder | pre-race check-in… → **low-key check-in about what I'm working on this week…** |
| COPY-0198 | `PlanGenerationInputsSummary.swift` | Generation inputs → **Idea settings** |
| COPY-0225 | `PlanHubView.swift` progress | Deep reasoning… → **Preparing your idea…** |
| COPY-0231 | `PlanHubView.swift` dock loading | Approving… → **Making ready…** |
| COPY-0232 | `PlanHubView.swift` dock action | Approve → **Make ready** |
| COPY-0233 | `PlanHubView.swift` dock hint | Clicking this will add… → **removed** |
| COPY-0273 | `ReferenceImportPreviewView.swift` | the server re-checks… → **we'll re-check…** |
| COPY-0285 | `ReferenceImportView.swift` | The server decides… → **We'll sort what's usable…** |
| COPY-0487 | `ShootFolioView.swift` fallback | third-person society garden/gym → **You can shoot this at home or wherever…** |
| COPY-0489 | `ShootFolioView.swift` empty | published card → **ready card** |
| COPY-0490 | `TodayView.swift` CTA | Mark posted → **Mark as posted** |
| COPY-0498 | `TodayView.swift` loading | The app is loading the latest published card. → **Getting your latest card…** |
| COPY-0579 | `YouView.swift` block header | Generation inputs → **Idea settings** |

## Cuts applied (16 ledger IDs)

| IDs | Change |
| --- | --- |
| COPY-0202–0212 (11) | `PlanHubView` error tiles: empty `AdminSignalBlock` title — human message only |
| COPY-0443–0446 (4) | `NotTodaySheet` streak/thought slogans removed; subtitle uses backup body or hides when empty |
| COPY-0603, COPY-0637 (2) | DEBUG `AIRunwayView` generation error title dropped |

## Skipped

| ID | Reason |
| --- | --- |
| COPY-0025 | `AppServices.swift` — Grok owns file; see `ch03-appservices-handoff.md` (already present on disk) |
| COPY-0431 | C12 skip-toast — held until CH-02 skippable onboarding |
| COPY-0250 | Ledger cites `IntelligenceHomeView:558` **Approve** review button, not an error tile — cut disposition does not apply |
| COPY-0564 | Ledger cites `YouReferencesView:122` **Approve** review button — same drift as COPY-0250 |

## Keep (explicit)

- COPY-0172 **Resize scene column** — unchanged (CH-16).
- **557 keep** ledger rows — not touched.

## Verification

### Build

```
xcodebuild -scheme CreatorContentOS \
  -destination 'platform=iOS Simulator,id=FAE1FD16-D185-433C-AC85-544FF45F2C82' \
  -derivedDataPath qa-baseline/DerivedData-CH03 build
```

Result: **BUILD SUCCEEDED**

### Simulator spot-check (`SIMCTL_CHILD_MCO_FORCE_FIXTURE_UI=1`)

| Check | Result |
| --- | --- |
| Plan dock **Make ready** (no Clicking hint) | **pass** (screenshot) |
| Today **Mark as posted** after Mark all as shot | **pass** (screenshot) |
| You header **IDEA SETTINGS** | **pass** (screenshot) |
| Full 359-test suite | **not run** (per scope) |

Fixture card: **Race week has entered the house**. Mark as posted tapped path only; post not committed.

## AppServices handoff

See [`ch03-appservices-handoff.md`](ch03-appservices-handoff.md).
