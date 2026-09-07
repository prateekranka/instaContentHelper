# CH-15 implementation record

Recorded: 7 September 2026, ~18:47–18:50 IST.
Repo: `/Users/prateekranka/Cowork/contenthelper`
Simulator: ContentHelper QA · iPhone 16 · `FAE1FD16-D185-433C-AC85-544FF45F2C82`

## Files changed

| File | Change |
| --- | --- |
| `CreatorContentOS/Models/GeneratedStoryboardBreakdown.swift` | Added shared `PackageCopyText` formatter for script + caption pasteboard strings. |
| `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift` | Added `PackageCopyButton`; copy actions on `GeneratedScriptTimelineContent` and `InstagramCaptionPostContent`; Reduce Motion guard on folder-tab animation. |
| `CreatorContentOS/Features/Today/ShootFolioView.swift` | Reused `PackageCopyText` in `ScriptTimelineCopyBlock` and caption `CopyBlock` (no Folio chrome changes). |
| `CreatorContentOS/Features/Today/TodayView.swift` | Narrow overflow entry `Edit scenes & script` → `CreatorRoute.shootFolio(editing: true)`. |
| `CreatorContentOSTests/GeneratedStoryboardBreakdownTests.swift` | Three tests pinning `PackageCopyText` rules. |

**Not changed:** `AppServices.swift`, onboarding, DTOs, build number, `prototypes/today-ui/index.html`.

## Copied-text rules (exact)

Shared helper: `PackageCopyText`.

**Script (`Copy full script` on Today Script tab; same string as Shoot Folio):**

1. If `card.script` is non-blank after trim → copy that stored script blob verbatim (race-week fixture: four newline-separated beats).
2. Else → join `GeneratedStoryboardBreakdown.rows(for: card).map(\.audioDialogue)` with `\n`.

**Caption (`Copy caption` on Today Caption tab; same string as Shoot Folio caption tab):**

1. If `card.caption` is non-blank after trim → copy caption only.
2. Else → copy `"No caption recorded for today."`

CTA, cover text, post instructions, and hashtags are **not** included in the caption paste (matches existing Shoot Folio `CopyBlock`).

## Shoot Folio launcher

**Not added.** No production Shoot Folio tab/button on Today.

**Narrow editor added:** Today overflow → **Edit scenes & script** pushes existing `ShootFolioView(startsInEditingMode: true)` via `CreatorShellView` `.shootFolio(editing:)` handler. Scene title/script edit is otherwise unreachable from inline Today.

## Verification

### Unit tests (focused, not full suite)

```
xcodebuild … test \
  -only-testing:CreatorContentOSTests/GeneratedStoryboardBreakdownTests/testPackageCopyTextPrefersStoredScriptBlob \
  -only-testing:CreatorContentOSTests/GeneratedStoryboardBreakdownTests/testPackageCopyTextFallsBackToVoiceoverLinesWhenScriptMissing \
  -only-testing:CreatorContentOSTests/GeneratedStoryboardBreakdownTests/testPackageCopyTextUsesCaptionFallbackWhenBlank
```

Result: **3/3 passed**.

### Simulator (ContentHelper QA, `SIMCTL_CHILD_MCO_FORCE_FIXTURE_UI=1`)

| Check | Result |
| --- | --- |
| Build Debug app | **pass** (`/tmp/ch15-derived`) |
| Today Script tab shows **Copy full script** | **pass** (accessibility + screenshot) |
| Tap → **Copied** feedback | **pass** (screenshot after tap at button centre) |
| Today Caption tab shows **Copy caption** | **pass** |
| Race-week fixture caption empty → fallback copy control still present | **pass** |
| Overflow **Edit scenes & script** visible | **pass** (no Shoot Folio primary launcher) |
| CH-16 resize handle still present on Storyboard | **not re-checked this run** (unchanged code path) |
| Host `simctl pbpaste` string match | **not verified** — host pasteboard returned unrelated Mac clipboard text; pasteboard bytes not isolated in this session |

Fixture card: **Race week has entered the house** (0/4 scenes shot). Mark posted / Mark all as shot not tapped.

## Risks

- Caption copy on cards with blank caption copies the fallback sentence, not a composed post block; intentional parity with Shoot Folio.
- Narrow edit still opens full `ShootFolioView` chrome (header, tabs); only entry is narrow, not the sheet layout.
- TPE-3 / TPE-5 `.shootFolio` navigation tests not reconciled in this slice.
- VoiceOver increment/decrement on storyboard resize not re-run (CH-16 retained in source).
