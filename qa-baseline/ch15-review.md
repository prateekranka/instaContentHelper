# CH-15 independent review

Recorded: 7 September 2026.
Reviewer did not implement the slice. Implementer narrative was read only after the git diff.
Repo: `/Users/prateekranka/Cowork/contenthelper` · branch `cursor/today-ui-prototype-cea4`
Simulator: ContentHelper QA · iPhone · `FAE1FD16-D185-433C-AC85-544FF45F2C82`

## Verdict

**PASS.** Scope matches CH-15. No code fix in this review.

## Scope

| Check | Result |
| --- | --- |
| Copy on Today inline Script / Caption | **ok** |
| Same pasteboard rules as Shoot Folio (`PackageCopyText`) | **ok** |
| CTA / hashtags / cover / post instructions **not** in caption paste | **ok** (shown when non-blank; omitted from copy) |
| Reduce Motion on folder-tab animation | **ok** |
| Storyboard resize + VoiceOver handle kept | **ok** (AX label `Resize scene column`; drag clamp still in `sceneResizeHandle`) |
| Folio entry overflow-only “Edit scenes & script”, starts editing, existing `CreatorShellView` destination | **ok** |
| No production Folio primary launcher / no Folio chrome on Today | **ok** |
| No `AppServices.swift` / `AppState.swift` / DTO / onboarding edits | **ok** |
| Tests only in existing file | **ok** (`GeneratedStoryboardBreakdownTests.swift`) |
| Posted is not treated as shared | **ok** (Today still “Mark all as shot”; Folio “Mark as posted” unchanged and unused in this run) |
| `prototypes/today-ui/index.html` dirty state preserved | **ok** (still modified; not reverted) |

## Native files (this slice)

Unstaged only. No other native files in the CH-15 diff.

| File | Role |
| --- | --- |
| `CreatorContentOS/Models/GeneratedStoryboardBreakdown.swift` | Shared `PackageCopyText` (script blob else VO lines; caption else fallback) |
| `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift` | `PackageCopyButton` on Script + Caption; Reduce Motion on folder tabs |
| `CreatorContentOS/Features/Today/ShootFolioView.swift` | Caption + script copy now call `PackageCopyText` (no Folio layout rewrite) |
| `CreatorContentOS/Features/Today/TodayView.swift` | Overflow `NavigationLink` → `CreatorRoute.shootFolio(editing: true)` |
| `CreatorContentOSTests/GeneratedStoryboardBreakdownTests.swift` | Three `PackageCopyText` tests |

**Confirmed clean:** `CreatorContentOS/App/AppServices.swift`, `CreatorContentOS/App/AppState.swift`, all `CreatorContentOS/Data/*DTO*.swift`, onboarding sources.

**Untracked / dirty, not this slice:** `prototypes/today-ui/index.html` remains dirty (`318` hunks). Implementer record said it was unchanged; git still shows it modified. Left as-is.

No new test **file**. UIT-7 skip body was not replaced (see leftover risks).

## Copy-text rules (source, both call sites)

`PackageCopyText` is the single formatter.

**Script** (`Copy full script` on Today; Shoot Folio `ScriptTimelineCopyBlock` uses the same helper):

1. Non-blank `card.script` → copy that blob.
2. Else → `GeneratedStoryboardBreakdown.rows` `audioDialogue` joined with `\n`.

**Caption** (`Copy caption` on Today; Shoot Folio caption `CopyBlock` body):

1. Non-blank `card.caption` → caption only.
2. Else → `"No caption recorded for today."`

CTA, cover text, post instructions, and hashtags are extra **display** fields on Today Caption. They are **not** appended to the paste. Matches Folio `CopyBlock`, which never copied those fields.

Feedback: Today uses new `PackageCopyButton` (`PocketSheetSecondaryAction` title flips to **Copied**, `UIPasteboard.general.string`). Folio Script/Caption still use the same secondary-action **Copied** pattern. Not a Folio chrome copy.

## Pasteboard evidence

Fixture launch: `SIMCTL_CHILD_MCO_FORCE_FIXTURE_UI=1`, card **Race week has entered the house**. Review build: `/tmp/ch15-review-derived`. Host clipboard seeded with unique sentinels **before** each tap so a Mac race would keep the sentinel.

### Unit tests (not the 359-suite)

```
xcodebuild test -project CreatorContentOS.xcodeproj -scheme CreatorContentOS \
  -destination 'platform=iOS Simulator,id=FAE1FD16-D185-433C-AC85-544FF45F2C82' \
  -derivedDataPath /tmp/ch15-review-derived \
  -only-testing:CreatorContentOSTests/GeneratedStoryboardBreakdownTests/testPackageCopyTextPrefersStoredScriptBlob \
  -only-testing:CreatorContentOSTests/GeneratedStoryboardBreakdownTests/testPackageCopyTextFallsBackToVoiceoverLinesWhenScriptMissing \
  -only-testing:CreatorContentOSTests/GeneratedStoryboardBreakdownTests/testPackageCopyTextUsesCaptionFallbackWhenBlank
```

**3/3 passed.** xcresult: `/tmp/ch15-review-derived/Logs/Test/Test-CreatorContentOS-2026.09.07_18-54-50-+0530.xcresult`

### In-sim Script

1. Today → Script → scroll → **Copy full script**.
2. Button became **Copied** (`AXButton "Copied"`).
3. Sentinel was replaced. `simctl pbpaste` (same string as host this run, 172 chars):

```
Race week starts with the shoes by the door.
Then I open the journal and write one honest line.
Bottle, timer, breath. Keep it small.
One steady stride is enough for today.
```

Matches stored race-week `script` blob (unit test equality path). Not VO-join, not caption, not CTA/hashtags.

### In-sim Caption

1. Today → Caption → **Copy caption**.
2. Button became **Copied**.
3. Race-week caption is blank, so fields for Caption/CTA/hashtags are hidden (`GeneratedReadOnlyField` skips blanks). Only the copy control showed.
4. Sentinel was replaced. `simctl pbpaste`:

```
No caption recorded for today.
```

Matches Folio missing-caption fallback. Not a composed post block.

Host `pbpaste` matched `simctl pbpaste` on this machine after both taps. Sentinels were overwritten, so this was not leftover Mac clipboard. Still treat unit tests + **Copied** as the durable proof; host pasteboard can race on other runs.

## Folio / resize / motion

- Overflow menu items: **Edit scenes & script** (`today.editScenesScript`), **Plan**. No Today primary “Open Shoot Folio”.
- Tap opened existing `ShootFolioView`: title Shoot Folio, subtitle **Editing scenes & script**, Cancel, disabled **Save edits**, Scenes list. `CreatorShellView` already maps `.shootFolio(editing:)` → `startsInEditingMode`.
- Storyboard tab AX: `AXGroup "Resize scene column"`. Source still has `sceneResizeHandle` (now ~342–374 after Reduce Motion env var shifted lines; ledger `:288` / `:338-370` are the pre-patch numbers).
- Folder tabs: `.animation(reduceMotion ? nil : .snappy(duration: 0.22), value: selectedFolderTab)`. Runtime VoiceOver increment/decrement on the handle was **not** re-run.

## Leftover risks (not CH-15 fails)

- Empty Script on Today copies `PackageCopyText.script` (often `""`). Folio empty path still uses `CopyBlock` body `"No script recorded for today."` and does not go through the helper. Ready packages with rows are unaffected.
- If a Plan `dayPackage` exists for the Today card’s scheduled date, inline Today copies that draft while Folio copies `todayCard`. Pre-existing resolver; not introduced here. Fixture race-week date `2026-06-05` did not hit the Plan seed keyed to calendar today.
- UIT-7 skip (`testCreatorTodayAndShootFolioAreReachableInInstalledApp`) not replaced with a current-path copy/edit UITest. CH-15 asked for existing-file tests; unit tests cover formatter only.
- TPE-3 / TPE-5 `.shootFolio` names not reconciled (CH-10).
- Narrow edit still presents full Folio chrome (header, Scenes/Script/Caption/Audio). Entry is narrow; destination is the existing editor. Spec allowed this.
- **Copy full script** sits under Today’s command bar until the package is scrolled. Reachable; easy to miss.
- AX reports copy buttons under panel ids (`plan.package.panel.script` / `.caption`), not `plan.package.copyScript` / `copyCaption`. Parent identifier likely wins.
- Caption copy of a blank caption pastes the fallback sentence. Intentional Folio parity; not a composed Instagram caption.

## Fixes made in this review

None.
