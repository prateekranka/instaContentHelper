# SwiftUI Design System And Implementation Spec: Creator Content OS V2 Full MVP

Generated with `build-ios-apps:swiftui-ui-patterns`.

Inputs:

- `docs/layers-conceptual-model-creator-content-os-v2.md`
- `docs/layers-interaction-flow-creator-content-os-v2.md`
- `docs/layers-surface-creator-content-os-v2-full-mvp.md`
- Canonical Training Folio Creator Daily Mode board: `$HOME/.codex/generated_images/019e91d6-f797-7072-bc8c-b5db7482e6cf/ig_0b70b2531334d988016a21baf5b41481919325834854242dec.png`
- Canonical Training Folio Manager Weekly Control board: `$HOME/.codex/generated_images/019e91d6-f797-7072-bc8c-b5db7482e6cf/ig_0b70b2531334d988016a21bbdccef48191b828f54a07d944bd.png`
- Canonical Training Folio Intelligence System board: `$HOME/.codex/generated_images/019e91d6-f797-7072-bc8c-b5db7482e6cf/ig_0b70b2531334d988016a21be44255c81918f32f4e8dd2ab875.png`

Superseded visual boards:

- Earlier Creator Daily Mode board: `$HOME/.codex/generated_images/019e91d6-f797-7072-bc8c-b5db7482e6cf/ig_0b70b2531334d988016a21af17bf7881919860e24aa72a9200.png`
- Earlier Manager Weekly Control board: `$HOME/.codex/generated_images/019e91d6-f797-7072-bc8c-b5db7482e6cf/ig_0b70b2531334d988016a21af9a792881918ddeece7f9c76aa5.png`
- Earlier Intelligence System board: `$HOME/.codex/generated_images/019e91d6-f797-7072-bc8c-b5db7482e6cf/ig_0b70b2531334d988016a21b02438f88191b438814a07d5f43c.png`

Implementation must follow the canonical Training Folio boards. The superseded boards are retained only as history and should not drive layout, density, or component decisions.

External API references checked:

- Apple SwiftUI `NavigationStack`: https://developer.apple.com/documentation/SwiftUI/NavigationStack
- Apple Observation: https://developer.apple.com/documentation/Observation
- Apple Liquid Glass overview: https://developer.apple.com/documentation/technologyoverviews/liquid-glass
- Apple SwiftUI `glassEffect(_:in:)`: https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
- Apple local notifications: https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app
- Supabase Swift client: https://supabase.com/docs/reference/swift/introduction
- Supabase Row Level Security: https://supabase.com/docs/guides/database/postgres/row-level-security
- Supabase Edge Functions: https://supabase.com/docs/guides/functions

## Product Frame

Creator Content OS is a native iPhone app that turns Manager's weekly setup and curated source intelligence into one prepared, shootable Daily Card for Creator.

The app has two visible personalities:

- Creator Mode: a quiet daily decision product. It should feel like opening a premium fitness journal and seeing exactly what to shoot today.
- Manager/Admin Mode: an editorial operating surface. It should help Manager prepare, review, publish, and improve the week without feeling like SaaS analytics.

The Intelligence system is part of the MVP, but it exists to feed Daily Cards. It must not become the emotional center of the product.

## Non-Negotiable Vocabulary

Use these terms exactly in code, UI labels, and comments where applicable:

- `Reference`: raw source material.
- `Confirm extraction`: the system read a Reference correctly.
- `Approve`: an extracted Pattern, Trend, Audio Option, or Idea fits Creator.
- `Publish`: Creator can now see the Weekly Plan or update.
- `Daily Card`: the scheduled daily package.
- `Today`: the Creator-facing placement of the current Daily Card.
- `Weekly Setup`: Manager's weekly input packet.
- `Weekly Plan`: the 7-day plan generated from setup and reviewed by Manager.
- `Card Alternative`: a non-destructive proposed variation.
- `Brand Brief`: an obligation.
- `Collab Lead`: a possible future brand.
- `Key Moment`: real-world context.
- `Archive`: preserved decision/output history.

Avoid:

- `Campaign calendar`, `content dashboard`, `AI chat`, `prompt`, `asset pipeline`, `trend feed`, `analytics`.

## Design System

### Visual Direction

The app should read as a premium editorial fitness journal:

- Warm, calm, precise.
- Typographic first.
- Tactile and printable.
- Quiet confidence instead of AI enthusiasm.
- Structured but not corporate.
- Screenshot-worthy on every primary screen.
- Folio-like rather than dashboard-like: large editorial anchors, thin-rule rows, sparse metadata, and one clear decision per first viewport.
- iOS 26-native without becoming a Liquid Glass demo.

Do not use:

- Purple-blue AI gradients.
- Chat bubbles as the primary interaction.
- Dense KPI cards.
- Nested cards inside cards.
- Marketing hero layouts inside the app.
- Decorative orb/bokeh backgrounds.

### Density And Folio Direction

The revised visual direction is `Training Folio`: a private editorial folio for Creator's week, not a data console.

Every screen should operate in one density mode:

- `Glance`: one decision or one next action. Use for Creator Today, Publish Confirmation, and Archive summaries.
- `Plan`: a sequence with limited metadata. Use for Weekly Setup, Weekly Plan, and Collabs & Events.
- `Review`: compare source, extracted meaning, warnings, and approval. Use for Daily Card Review and Reference Review.
- `Library`: browse prepared material. Use for Intelligence Home, Patterns, Trends, Audio Options, and Ideas.

Rules:

- Do not mix all density modes on one screen.
- First viewport gets one dominant block, not several equal cards.
- Creator screens show one hero idea, maximum two metadata chips, maximum two visible actions, and one source sentence at most.
- Admin rows show one title, one reason line, maximum two chips, and one trailing state/action.
- Counts, provenance, confidence, edit history, and secondary warnings move behind disclosure unless they block the current task.
- Weekly Plan and Archive should feel like folio timelines, not tables.
- References and Intelligence are editorial shelves/queues, not database lists.

### Palette

Create a `MCOTheme.Color` namespace.

Core:

- `paper`: `#F7F1E8`
- `paperRaised`: `#FBF7EF`
- `ink`: `#221F1B`
- `inkMuted`: `#5D5750`
- `hairline`: `#D8CDBD`
- `hairlineStrong`: `#BFAF9B`

Accent:

- `oxblood`: `#8E2D2C`
- `oxbloodDark`: `#6F1F1E`
- `sage`: `#7F8A6B`
- `sageDeep`: `#5E6A50`
- `brass`: `#B89A61`
- `clay`: `#A96E4D`

Status:

- `ready`: `sageDeep`
- `needsReview`: `brass`
- `warning`: `clay`
- `blocked`: `oxblood`
- `quiet`: `inkMuted`
- `offline`: `#6A6F74`

Background rule:

- The default screen background is `paper`.
- Detail blocks can use `paperRaised`.
- Oxblood is reserved for decisive actions, selected state, and high-importance labels.
- Do not let red dominate admin screens; admin should feel precise, not alarmed.

### Typography

Create `MCOType`.

Use system fonts first:

- Editorial titles: `.system(size: ..., weight: ..., design: .serif)`
- Body/UI: `.system(size: ..., weight: ..., design: .default)`
- Monospaced only for dates, codes, or structured import previews.

Scale:

- `display`: 42, serif, regular. Use only for Today hero titles and major empty states.
- `screenTitle`: 34, serif, regular.
- `sectionTitle`: 13, default, semibold, uppercase only in admin/source labels.
- `cardTitle`: 24, serif, regular.
- `headline`: 18, default, semibold.
- `body`: 16, default, regular.
- `bodySmall`: 14, default, regular.
- `caption`: 12, default, regular.
- `tinyLabel`: 11, default, semibold.

Rules:

- Letter spacing is `0`.
- Do not scale type with viewport width.
- Support Dynamic Type through at least large accessibility sizes for Today, Package Detail, Decision Sheet, Archive, and text-heavy admin review screens.
- Long captions/scripts must wrap naturally and have nearby copy buttons.

### Spacing And Layout

Create `MCOSpace`.

- `xxs`: 4
- `xs`: 8
- `s`: 12
- `m`: 16
- `l`: 24
- `xl`: 32
- `xxl`: 48

Screen rules:

- Root horizontal padding: 20.
- Admin list row vertical padding: 14 to 16.
- Creator decision blocks: minimum 56 point tap height.
- Bottom primary action area: pinned where useful, but avoid hiding scroll content.
- Use thin divider rules instead of heavy card shadows.

### Shape And Materials

Create `MCOShape`.

- `blockRadius`: 8
- `controlRadius`: 8
- `pillRadius`: 999
- `imageRadius`: 6

Use:

- Flat blocks with 1 point hairline stroke.
- Slight raised background only for hero Today card and important previews.
- Native iOS 26 Liquid Glass for system navigation, toolbars, bottom action bars, compact floating controls, and tappable command clusters where it improves hierarchy.

Liquid Glass rules:

- Deployment target is iOS 26.0+, so SwiftUI iOS 26 APIs can be used directly in the app target.
- Prefer native APIs such as `glassEffect(_:in:)`, `GlassEffectContainer`, `.buttonStyle(.glass)`, and `.buttonStyle(.glassProminent)` over custom blur/glass effects.
- Keep the core reading surfaces editorial and paper-like. Do not turn Daily Cards, scripts, captions, Reference summaries, or Archive entries into translucent panels.
- Use interactive glass only for tappable/focusable elements.
- If a shared package or preview target ever supports older iOS versions, gate Liquid Glass with `#available(iOS 26, *)` in that target.

### Icons

Use SF Symbols, styled consistently with `.symbolRenderingMode(.monochrome)` unless a status color is needed.

Suggested symbols:

- Today: `house`
- Week/Weekly Plan: `calendar`
- References: `tray`
- Intelligence: `sparkle.magnifyingglass` or `lightbulb`
- Collabs & Events: `briefcase`
- Creator Profile: `person.text.rectangle`
- Archive: `archivebox`
- Settings: `gearshape`
- Scene/shot list: `movieclapper`
- Script: `pencil.line`
- Caption: `text.quote`
- Audio: `music.note`
- Post: `paperplane`
- Brand warning: `exclamationmark.triangle`
- Verified: `checkmark.seal`
- Unavailable: `slash.circle`
- Save for tomorrow: `bookmark`

Avoid cute or playful symbols. These icons are functional labels, not decoration.

### Core Components

Implement these as small SwiftUI views under `DesignSystem/Components`.

#### `EditorialScreen`

Reusable root wrapper:

- Sets paper background.
- Applies safe area treatment.
- Provides default horizontal padding.
- Optional bottom action bar slot.

#### `ScreenHeader`

Variants:

- Creator: quiet avatar/monogram, title, date/context line, small settings control.
- Admin: back control or mode marker, title, subtitle, overflow menu.

#### `JournalBlock`

Purpose:

- Full-width content block with paperRaised fill, hairline stroke, radius 8.
- Use for Today hero, package preview, admin sections, warnings, extracted candidates.

Rules:

- A `JournalBlock` cannot contain another `JournalBlock`.
- Use `Divider()` or custom `Hairline()` inside a block for related rows.
- `JournalBlock` must not use `.glassEffect`. It is the app's paper content surface, not system chrome.

#### `GlassCommandBar`

Purpose:

- iOS 26 bottom command container for pinned action groups.

Use for:

- Today actions when pinned.
- Package Detail ready action.
- Decision Sheet confirmation.
- Weekly Plan `Rebalance` / `Publish`.
- Daily Card Review `Create alternative` / `Approve card`.
- Reference Review confirmation/approval actions.
- Intelligence detail `Use this week`.

Rules:

- Wrap grouped glass actions in `GlassEffectContainer`.
- Apply `.glassEffect(...)` after frame, padding, and appearance modifiers.
- Keep long text and reading content out of this component.
- Use native Liquid Glass APIs, not custom blur effects.

#### `FloatingIconButton`

Purpose:

- iOS 26 glass-backed icon-only controls that sit above content or in compact toolbar-like positions.

Use for:

- Settings/control icon.
- Filters.
- Overflow.
- Bookmark/save.
- Media overlay controls.

Rules:

- Use `.glassEffect(.regular.interactive(), in: .circle)` for tappable controls.
- Use stable 36 to 44 point frames.
- Do not use interactive glass on non-interactive status indicators.

#### `StatusChip`

Fields:

- `label`
- `tone`: ready, candidate, warning, blocked, quiet, sourceReason
- optional `systemImage`

Use for:

- `Candidate`, `Approved`, `Stale`, `Verified`, `Unavailable`, `Used`
- `Routine`, `Brand`, `Moment`, `Trend`, `Pattern`, `Evergreen`
- `Easy`, `Medium`, `Hard`

Fit scores cannot rely on color only. Always include text such as `High fit` or `80%`.

#### `SourceReasonChip`

Dedicated chip for why a Daily Card exists:

- `Routine`
- `Brand`
- `Moment`
- `Trend`
- `Pattern`
- `Evergreen`

Use on Weekly Plan rows and admin Daily Card Review. On Creator Today, collapse this to a small sentence such as `Inspired by a fitness-after-60 pattern`.

#### `PrimaryActionButton`

Oxblood filled button.

Use for:

- `See what to shoot`
- `Use backup`
- `Publish week`
- `Approve card`
- `Confirm extraction`
- `Use this week`

Do not use for low-commitment actions like filters or tabs.

iOS 26 rule:

- Preserve oxblood as the primary action identity.
- Inside `GlassCommandBar`, use the glass container for system material; do not automatically replace every primary action with `.buttonStyle(.glassProminent)`.

#### `SecondaryActionButton`

Paper button with hairline stroke.

Use for:

- `Need easier option`
- `Rebalance`
- `Create alternative`
- `Open source`
- `View older`

iOS 26 rule:

- Use paper/hairline by default.
- Use `.buttonStyle(.glass)` only when the secondary action lives inside a floating or pinned `GlassCommandBar`.

#### `EditorialTabs`

Segmented tab control for package/detail sections.

Enums:

- `PackageSection`: scenes, script, caption, audio, post, brand.
- `IntelligenceSection`: watchlists, benchmarkCreators, patterns, trends, audioOptions, ideas.
- `ArchiveSection`: all, posted, backupUsed, saved, skipped, learnings.

#### `WarningRow`

Use for blocking and non-blocking warnings:

- Icon.
- Short title.
- One-line reason.
- Optional action.

Warnings should expand into readable text. Do not only show counts.

#### `FitScoreBadge`

Shows:

- Percent or categorical score.
- Text label: `High fit`, `Medium fit`, `Low fit`.
- Optional reason line in details.

Use lightly on admin/intelligence screens. Do not show fit score prominently on Creator Today.

#### `FolioRow`

Purpose:

- Quiet row primitive for Weekly Plan, Archive, References, and Intelligence shelves.

Structure:

- Leading slot: date numeral, day abbreviation, icon, or thumbnail.
- Title.
- One secondary reason line.
- Maximum two chips.
- Optional trailing state or action.

Rules:

- Do not show raw provenance, confidence, exact timestamps, and counts together in a row.
- If more detail is needed, navigate or disclose.
- Use thin separators and typography, not heavy card framing.

#### `ReadinessStrip`

Purpose:

- Admin-only summary strip for readiness and blockers.

Use for:

- Weekly Plan readiness.
- Weekly Setup state.
- Publish Confirmation.
- Reference/Intelligence review queues when needed.

Rules:

- Maximum three labels.
- No charts.
- No oversized KPI numbers.
- If one item blocks publishing, show the blocker instead of a count.

#### `EditorialDisclosure`

Purpose:

- Hide secondary detail without losing access.

Use for:

- Source provenance.
- Analysis confidence.
- Edit history.
- Full brand requirements.
- Related references.
- Learning detail.

Rules:

- Default closed unless the detail is needed for the current decision.
- Disclosure labels should be specific: `Source details`, `Brand requirements`, `Why this fits`, not generic `More`.

#### `EmptyState`

Tone:

- Useful and specific, not motivational.

Examples:

- `No card has been published for today.`
- `Prepare next week.`
- `Add screenshot or link.`
- `Import a creator list to learn formats, hooks, and patterns.`

## Navigation Model

### Minimum OS

Target iOS 26.0+.

Implications:

- Use SwiftUI, Observation, `NavigationStack`, and iOS 26 Liquid Glass APIs directly in the app target.
- Do not add iOS 16/17 fallback architecture.
- Keep the UI iPhone-only for V1.
- Use native iOS 26 system behavior where it supports the product, but preserve the warm editorial fitness journal direction instead of making the app feel like a generic glass demo.

### App Shell

Use one `TabView` per mode and one `NavigationStack` per tab. Store routes as small `Hashable` enum values, not model objects or views.

Root:

```swift
@MainActor
struct CreatorContentOSAppView: View {
  @State private var appState = AppState()

  var body: some View {
    Group {
      switch appState.activeMode {
      case .creator:
        CreatorShellView()
      case .admin:
        AdminShellView()
      }
    }
    .environment(appState)
    .withAppServices()
  }
}
```

`AppMode`:

```swift
enum AppMode: String, Codable, CaseIterable {
  case creator
  case admin
}
```

Mode switching:

- Creator's device should default to Creator Mode.
- Manager's device should default to Admin Mode.
- A small Settings/Control icon can expose mode switching for Manager.
- Creator can edit if needed, but advanced controls are tucked behind settings and deliberate confirmation.

### Creator Mode Tabs

Use bottom tabs:

- `Today`
- `Week`
- `Archive`
- `Settings`

`CreatorRoute`:

```swift
enum CreatorRoute: Hashable {
  case packageDetail(cardID: DailyCard.ID, initialSection: PackageSection)
  case weekDay(cardID: DailyCard.ID)
  case archiveEntry(cardID: DailyCard.ID)
  case feedback(cardID: DailyCard.ID)
}
```

`CreatorSheetDestination`:

```swift
enum CreatorSheetDestination: Identifiable, Hashable {
  case decision(cardID: DailyCard.ID)
  case backupOptions(cardID: DailyCard.ID)
  case postResult(cardID: DailyCard.ID)
  case completion(cardID: DailyCard.ID, decision: CompletionState)
  case alternativeRequest(cardID: DailyCard.ID, action: AlternativeAction)
}
```

### Admin Mode Navigation

The surface docs define eight admin destinations, but iPhone bottom navigation should not expose eight equal tabs.

Use bottom tabs:

- `Today Preview`
- `Weekly Plan`
- `References`
- `Intelligence`
- `More`

`More` contains:

- `Collabs & Events`
- `Creator Profile`
- `Archive & Learnings`
- `Settings`

This preserves the full information architecture without creating an overloaded tab bar.

`AdminRoute`:

```swift
enum AdminRoute: Hashable {
  case weeklySetup(weekStart: Date)
  case weeklyPlan(planID: WeeklyPlan.ID)
  case dailyCardReview(cardID: DailyCard.ID)
  case publishConfirmation(planID: WeeklyPlan.ID)
  case referenceReview(referenceID: Reference.ID)
  case watchlistImport
  case benchmarkCreator(id: BenchmarkCreator.ID)
  case patternDetail(id: Pattern.ID)
  case trendDetail(id: Trend.ID)
  case audioOptionDetail(id: AudioOption.ID)
  case ideaDetail(id: Idea.ID)
  case brandBriefDetail(id: BrandBrief.ID)
  case collabLeadDetail(id: CollabLead.ID)
  case keyMomentDetail(id: KeyMoment.ID)
  case creatorProfileSection(CreatorProfileSection)
  case archiveEntry(cardID: DailyCard.ID)
  case learningSummary(id: LearningSummary.ID)
}
```

`AdminSheetDestination`:

```swift
enum AdminSheetDestination: Identifiable, Hashable {
  case addReference
  case extractionResults(referenceID: Reference.ID)
  case sourcePicker(context: SourcePickerContext)
  case generationCheck(setupID: WeeklySetup.ID)
  case alternativePreview(cardID: DailyCard.ID, alternativeID: CardAlternative.ID)
  case changeType(planID: WeeklyPlan.ID)
  case impactPreview(changeID: MidweekChange.ID)
  case publishConfirmation(planID: WeeklyPlan.ID)
  case editField(EditFieldContext)
}
```

Use `.sheet(item:)` for sheet presentation. Avoid multiple boolean sheet flags.

## Screen-By-Screen Implementation Spec

### 1. Today

Primary user: Creator.

Root view:

- `TodayView`
- Feature state: `TodayFeatureState`
- Service dependencies: `DailyCardRepository`, `CompletionQueue`, `NotificationScheduler`

Purpose:

- Show one current Published Daily Card and let Creator decide what happens today.

Primary hierarchy:

1. Date/context line.
2. Daily Card title.
3. One `Easy • 12 min` style effort chip.
4. One why-today sentence.
5. Primary action: `See what to shoot`.
6. Secondary action: `Not today`.
7. Completion state if already decided.

States:

- `loadingFromCache`
- `ready(card)`
- `offlineWithCachedCard(card, pendingSyncCount)`
- `noPublishedCard`
- `noCacheOffline`
- `completed(card, decision)`

Interactions:

- `See what to shoot` pushes `PackageDetailView`.
- `Need easier option` presents `AlternativeRequestSheet` if online and generation is available; if offline, show stored backup options.
- `Can shoot today?` appears in `DecisionSheet`.
- Completion decisions are optimistic locally and queued if offline.

Surface rules:

- Source intelligence remains a single small sentence.
- No fit score as a primary Creator element.
- Completion means decision made, not necessarily posted.
- If there is a Brand Brief, show a quiet brand/disclosure note before copy actions.
- Do not show a package preview on Today home. Package content begins on Package Detail.
- Do not show more than two chips on Today.

### 2. Package Detail

Root view:

- `PackageDetailView`

Purpose:

- Show the prepared content package for the Daily Card.

Sections:

- `Scenes`
- `Script`
- `Caption`
- `Audio`
- `Post`
- `Brand` only when applicable.

Components:

- `PackageSectionTabs`
- `SceneListView`
- `CopyableTextBlock`
- `AudioOptionBlock`
- `PostChecklistView`
- `BrandRequirementBlock`

Interactions:

- Copy script.
- Copy caption.
- Copy audio notes.
- Open Instagram/audio link externally.
- Return to Today with the same card state.

Failure states:

- Audio link fails externally: keep user on Audio section and show fallback audio note.
- Brand requirement incomplete: hide post-ready language and show required disclosure warning.

### 3. Decision Sheet

Root view:

- `DecisionSheet`

Purpose:

- Let Creator make a decision quickly, including lower-effort backups.

Layout:

- Title: `Can shoot today?`
- Segmented intent: `Yes, I can` / `Not today`
- If `Not today`, immediately show:
  - `10-second story`
  - `Caption-only post`
  - `Save this for tomorrow`
  - `Skip intentionally`
- Primary action: context-specific, e.g. `Use backup`.

Rules:

- Do not ask Creator to explain before presenting backups.
- Do not persist `Can shoot today` as completion.
- Persist only final states: shot, posted, used backup, saved for tomorrow, skipped intentionally.

### 4. Alternative Flow

Root views:

- `AlternativeRequestSheet`
- `AlternativePreviewView`

Actions:

- `Make easier`
- `Shorter caption`
- `More Hinglish`
- `New audio/trend version`

Rules:

- Generate an alternative first.
- Original card is never mutated until Creator/admin chooses `Use this`.
- Show changed fields, preserved requirements, and lost requirements.
- If a Brand Brief exists, alternatives must preserve disclosure and required talking points.
- If a new audio option is unverified, show fallback and verification note.

Offline:

- Disable live AI alternatives.
- Keep stored backups available.

### 5. Weekly Plan

Primary user: Manager. Secondary: Creator view-only.

Root views:

- `WeeklyPlanView`
- `WeeklySetupDraftView`
- `WeeklyPlanReviewView`
- `DailyCardReviewView`
- `PublishConfirmationView`

Purpose:

- Prepare, review, edit, publish, and monitor a 7-day plan.

Weekly Setup Draft sections:

- This week's location.
- Workout/race schedule.
- Family/travel moments.
- Brand/collab obligations.
- 5 to 10 trend/audio options.
- No-go topics.
- Selected Patterns, Trends, Audio Options, Ideas.
- Recent Learning Summary.

Weekly Plan Review row hierarchy:

1. Day/date.
2. Daily Card title.
3. One reason line.
4. Source reason chip: Routine, Brand, Moment, Trend, Pattern, Evergreen.
5. Shootability state.
6. Warning marker only if needed.

Admin actions:

- Generate week.
- Open day.
- Swap days.
- Rebalance.
- Inject Brand Brief.
- Inject Key Moment.
- Inject Trend/Pattern/Audio Option.
- Publish.

Publish rules:

- Publish is disabled if Brand Brief required disclosure/tags are missing.
- Unverified audio can publish only with visible fallback and verification note.
- Published days are soft-locked.
- Completed days cannot be overwritten by midweek replanning.

Visual density rules:

- First viewport shows a `ReadinessStrip` plus the seven-day rhythm.
- Day rows use `FolioRow`, not dense table rows.
- Workout context, audio confidence, brand/event details, and provenance belong in day detail, not the weekly row.

### 6. Daily Card Review

Primary user: Manager.

Purpose:

- Review and edit the full package before publishing or updating.

Hierarchy:

1. `CreatorPreviewCard`: exactly what Creator will see.
2. Package sections: Scenes, Script, Caption, Audio, Post, Backup, Brand if relevant.
3. Source explanation.
4. Warning list.
5. Edit history marker.
6. Actions: `Create alternative`, `Approve card`.

Rules:

- The Creator preview comes before admin controls.
- Warnings must show readable text, not just icon counts.
- Use `Create alternative` for non-destructive AI changes.

### 7. Midweek Change

Root views:

- `MidweekChangeTypeSheet`
- `MidweekChangeDraftView`
- `ImpactPreviewView`
- `AffectedCardReviewView`
- `UpdateReviewView`

Purpose:

- Change only affected future cards without destabilizing Creator's week.

Change types:

- Brand Brief.
- Key Moment.
- Strong Trend.
- Schedule/location update.

Rules:

- Completed days are locked by default.
- Tomorrow's card requires explicit confirmation before replacement.
- Brand Briefs due soon outrank generic trends.
- Show what would be lost if a card is replaced.
- If Creator currently has the card cached, update non-disruptively and show a revision marker next open.

### 8. References

Primary user: Manager/scout.

Root views:

- `ReferencesInboxView`
- `AddReferenceSheet`
- `ReferenceReviewView`

Purpose:

- Add raw source material, analyze it, and confirm extraction.

Groups:

- `Needs analysis`
- `Needs confirmation`
- `Confirmed`
- `Dismissed` behind filter.

Reference row shows:

- Source type: screenshot, reel link, audio link, note, import.
- Preview or URL.
- Added by.
- Analysis status.
- One candidate/status label.

Actions:

- Add screenshot/link.
- Analyze.
- Confirm extraction.
- Dismiss.
- Open source externally.

Rules:

- `Reference` means raw source material.
- `Confirm extraction` means the system read it correctly.
- Do not use `Approve` on raw References.
- A single Reference can yield multiple derived objects.
- Hide full URL, exact timestamp, detailed provenance, and confidence in the row. Put them in Reference Review.

### 9. Reference Review

Primary user: Manager.

Root view:

- `ReferenceReviewView`

Purpose:

- Inspect raw source and decide what it produced.

Layout:

1. Raw source preview and source details.
2. Extraction summary:
   - Extracted hook.
   - Visual pattern.
   - Caption pattern.
   - Extracted audio.
3. Derived candidates:
   - Suggested Pattern.
   - Suggested Trend.
   - Suggested Audio Option.
   - Suggested Idea.
4. Creator fit notes.
5. Avoid/copying warning.
6. Confidence.
7. Actions.

Actions:

- Confirm extraction.
- Approve as Pattern.
- Approve as Trend.
- Approve Audio Option.
- Save as Idea.
- Dismiss extraction item.

Rules:

- Visually separate each derived object.
- Confirmation and approval are separate steps.
- Warning copy: `Use the structure, not the script.`

### 10. Intelligence

Primary user: Manager.

Root views:

- `IntelligenceHomeView`
- `WatchlistsView`
- `WatchlistImportView`
- `BenchmarkCreatorDetailView`
- `PatternsView`
- `PatternDetailView`
- `TrendsView`
- `TrendDetailView`
- `AudioOptionsView`
- `AudioOptionDetailView`
- `IdeasView`
- `IdeaDetailView`

Purpose:

- Manage the preparation library that feeds Weekly Setup and Daily Cards.

Intelligence Home sections:

- Ready for this week.
- Needs your call.
- Recently used.
- Library navigation: Watchlists, Benchmark Creators, Patterns, Trends, Audio Options, Ideas.

Hierarchy:

1. Ready for this week.
2. Needs review.
3. Recently used.
4. Archived/dismissed behind filters.

Rules:

- Do not present this as analytics.
- Do not foreground external creators over Creator adaptation.
- Trend freshness is visible but secondary to Creator fit.
- Watchlists are for learning formats, not copying scripts.
- Counts are quiet trailing details, never the main visual hierarchy.
- Intelligence Home uses shelves, not metric cards or count-first rows.

Detail requirements:

- Pattern: title, type, summary, Creator adaptation, complexity, fit, source references, used count.
- Trend: summary, first/last seen, timing recommendation, region/niche, hook/visual/caption pattern, Creator adaptation, saturation note, fit, audio options.
- Audio Option: name, source link, usage notes, region seen, availability confidence, verification status, fallback.
- Idea: title, summary, suggested use, shootability, fit score, source object.

### 11. Collabs & Events

Primary user: Manager.

Root views:

- `CollabsEventsView`
- `BrandBriefDetailView`
- `CollabLeadDetailView`
- `KeyMomentDetailView`

Purpose:

- Manage obligations, possible brands, and real-world context.

Sections:

- Brand Briefs.
- Collab Leads.
- Key Moments.

Rules:

- Brand Brief is an obligation and can block publishing.
- Collab Lead is future possibility and does not constrain generation unless selected as inspiration.
- Key Moment is real-world context and can drive a Daily Card or angle.

Brand Brief Detail shows:

- Brand, campaign, deliverable.
- Due/post/review dates.
- Required talking points.
- Must avoid.
- Required tags.
- Disclosure.
- Approval state.
- Usage rights.
- Payment/barter status if present.
- Linked Daily Cards.

Blocking warning:

- `This brief is missing disclosure or required tags. Cards using it cannot be published yet.`

### 12. Creator Profile

Primary user: Manager. Creator advanced access.

Root views:

- `CreatorProfileView`
- `CreatorProfileSectionEditor`

Purpose:

- Edit the living product memory.

Sections:

- Positioning.
- Voice rules.
- Content pillars.
- Preferred hooks.
- Caption style.
- Things Creator would never say.
- Weekly routine.
- Brand tone.
- No-go topics.
- Language preferences.
- Recurring formats.
- Trend filter rules.
- Influencer adaptation rules.

Rules:

- This must feel like editing a brief, not code/config.
- Show active profile version.
- Save creates a new version.
- Restore old versions only after confirmation.

### 13. Archive & Learnings

Primary users: Creator and Manager.

Root views:

- `ArchiveView`
- `ArchiveEntryDetailView`
- `LearningSummaryView`

Purpose:

- Show decisions and outputs, not analytics.

Archive entry shows:

- Date.
- Daily Card title.
- Completion state.
- Caption/script used.
- Feedback tags.
- Trend/Pattern/Audio used.
- Brand/Moment attached.
- Optional final Instagram post link.
- Optional manual performance notes.

Learning Summary shows:

- Worked well.
- Did not work.
- Voice learnings.
- Shootability learnings.
- Brand learnings.
- Trend learnings.
- Next week recommendations.

Rules:

- Keep learning qualitative first.
- Performance numbers are optional and secondary.
- Creator sees personal history; Manager sees history plus learning actions.

## Suggested Swift File And Module Structure

Assuming a single iOS app target:

```text
CreatorContentOS/
  App/
    CreatorContentOSApp.swift
    CreatorContentOSAppView.swift
    AppState.swift
    AppMode.swift
    AppServices.swift
    AppEnvironment.swift
  DesignSystem/
    MCOTheme.swift
    MCOType.swift
    MCOSpace.swift
    MCOShape.swift
    MCOGlass.swift
    Components/
      EditorialScreen.swift
      ScreenHeader.swift
      JournalBlock.swift
      GlassCommandBar.swift
      FloatingIconButton.swift
      Hairline.swift
      StatusChip.swift
      SourceReasonChip.swift
      FitScoreBadge.swift
      FolioRow.swift
      ReadinessStrip.swift
      EditorialDisclosure.swift
      WarningRow.swift
      EditorialTabs.swift
      PrimaryActionButton.swift
      SecondaryActionButton.swift
      CopyableTextBlock.swift
      EmptyState.swift
  Navigation/
    CreatorShellView.swift
    AdminShellView.swift
    AppTab.swift
    RouterPath.swift
    Routes.swift
    SheetDestinations.swift
    SheetRouterModifier.swift
  Models/
    Workspace.swift
    Creator.swift
    Member.swift
    CreatorProfile.swift
    WeeklySetup.swift
    WeeklyPlan.swift
    DailyCard.swift
    CardAlternative.swift
    Reference.swift
    Watchlist.swift
    BenchmarkCreator.swift
    Pattern.swift
    Trend.swift
    AudioOption.swift
    Idea.swift
    BrandBrief.swift
    CollabLead.swift
    KeyMoment.swift
    Feedback.swift
    LearningSummary.swift
    PostResult.swift
    CommonEnums.swift
  Services/
    SupabaseClientFactory.swift
    WorkspaceSessionService.swift
    DailyCardRepository.swift
    WeeklyPlanRepository.swift
    ReferenceRepository.swift
    IntelligenceRepository.swift
    CollabsRepository.swift
    CreatorProfileRepository.swift
    ArchiveRepository.swift
    GenerationService.swift
    ReferenceAnalysisService.swift
    CompletionQueue.swift
    NotificationScheduler.swift
    ExternalLinkService.swift
  Persistence/
    LocalStore.swift
    CachedTodayCard.swift
    CachedWeeklyPlan.swift
    PendingMutation.swift
    SyncState.swift
  Features/
    Today/
      TodayView.swift
      TodayFeatureState.swift
      PackageDetailView.swift
      DecisionSheet.swift
      AlternativeRequestSheet.swift
      AlternativePreviewView.swift
      FeedbackPromptView.swift
    Week/
      CreatorWeekView.swift
      WeeklyPlanView.swift
      WeeklySetupDraftView.swift
      WeeklyPlanReviewView.swift
      DailyCardReviewView.swift
      PublishConfirmationView.swift
      MidweekChangeViews.swift
    References/
      ReferencesInboxView.swift
      AddReferenceSheet.swift
      ReferenceReviewView.swift
      ExtractionResultsView.swift
    Intelligence/
      IntelligenceHomeView.swift
      WatchlistsView.swift
      WatchlistImportView.swift
      BenchmarkCreatorDetailView.swift
      PatternsView.swift
      PatternDetailView.swift
      TrendsView.swift
      TrendDetailView.swift
      AudioOptionsView.swift
      AudioOptionDetailView.swift
      IdeasView.swift
      IdeaDetailView.swift
    CollabsEvents/
      CollabsEventsView.swift
      BrandBriefDetailView.swift
      CollabLeadDetailView.swift
      KeyMomentDetailView.swift
    CreatorProfile/
      CreatorProfileView.swift
      CreatorProfileSectionEditor.swift
    Archive/
      ArchiveView.swift
      ArchiveEntryDetailView.swift
      LearningSummaryView.swift
    Settings/
      SettingsView.swift
      PairingView.swift
  Fixtures/
    PreviewFixtures.swift
    SampleDailyCards.swift
    SampleWeeklyPlan.swift
    SampleReferences.swift
  Resources/
    Assets.xcassets
```

Rule:

- Keep feature state close to the feature.
- Use repositories/services in the environment.
- Pass models explicitly to subviews.
- Do not introduce a view model for every row.

## Data And State Assumptions

### Backend Shape

Use Supabase for:

- Postgres source of truth.
- Storage for uploaded screenshots/screen recordings/context visuals.
- Edge Functions for AI calls, generation, reference analysis, and privileged writes.
- Optional Realtime for admin sync/status after the basic polling path works.

Tables should include `workspace_id` and `creator_id` even though the V1 UI only exposes Creator.

Core tables:

- `workspaces`
- `creators`
- `members`
- `device_installations`
- `creator_profiles`
- `weekly_setups`
- `weekly_plans`
- `daily_cards`
- `card_alternatives`
- `references`
- `reference_extractions`
- `watchlists`
- `benchmark_creators`
- `patterns`
- `trends`
- `audio_options`
- `ideas`
- `brand_briefs`
- `collab_leads`
- `key_moments`
- `feedback`
- `learning_summaries`
- `post_results`
- `sync_events`

### No Login In V1

The UI should not expose login/authentication.

Recommended internal approach:

- Pair each installed app with a Workspace and Member role using a device invite.
- Store device credentials in Keychain.
- Send mutations through Edge Functions that verify the device token and role.
- Keep table RLS enabled before exposing direct table access.
- If direct Supabase Swift reads are used, scope them through safe read views or role-aware policies.

This keeps V1 easy while preserving the path to multiple creators/workspaces later.

### Local Cache

Use a small local store for offline Today mode.

Cache:

- Current Published Daily Card.
- Current Weekly Plan summary.
- Recent Package Detail content.
- Recent Archive entries.
- Pending completion decisions.
- Pending feedback.

Do not cache:

- AI generation drafts as usable product data.
- Failed AI outputs except as admin diagnostics if needed.
- Full watchlist imports unless required for offline admin review.

### Sync Model

Creator Today:

- Cache first.
- Network refresh in the background.
- Completion decisions update locally immediately.
- Pending decisions sync later if offline.
- Failed completion sync should create an admin-visible sync warning, not a scary Creator error.

Admin generation/analysis:

- Pessimistic completion.
- Weekly Plan appears only after server validation succeeds.
- Reference analysis becomes useful only after extraction is confirmed.
- Alternatives never mutate the original until `Use this`.

### Notifications

Use local notifications on Creator's phone.

Flow:

1. Manager publishes a Weekly Plan.
2. Creator's phone syncs the published plan.
3. Creator's phone schedules gentle daily local notifications.

Notification copy:

- `Today's reel is ready: Race week has entered the house.`
- `A lighter option is ready if today is packed.`
- `Today's card is ready for race week.`

Rules:

- Notification should include the actual Daily Card title when possible.
- Do not schedule from the backend in V1.
- If the published plan changes midweek, reschedule only affected future notifications.

### AI Boundaries

AI actions:

- Analyze Reference.
- Generate Weekly Plan.
- Generate Card Alternative.
- Generate Learning Summary.
- Adapt Trend/Pattern/Audio into a Daily Card.

AI cannot:

- Publish directly to Creator.
- Mark a Reference approved.
- Overwrite completed days.
- Silently use unavailable audio.
- Skip Brand Brief disclosure/tags.

All AI output should be strict structured JSON and validated server-side before entering the product model.

## Build Order

Even though the MVP includes the full V2 intelligence system, build in vertical slices:

1. App shell, role mode, design system primitives, fixture data.
2. Creator Today, Package Detail, Decision Sheet, Archive with local fixtures.
3. Admin Weekly Setup and Weekly Plan Review with fixtures.
4. References Inbox and Reference Review with placeholder analysis.
5. Intelligence Home plus Pattern/Trend/Audio/Idea detail screens.
6. Collabs & Events and Creator Profile editors.
7. Local cache and pending completion queue.
8. Supabase schema and repositories.
9. Edge Functions for weekly generation and reference analysis.
10. Notification scheduling on Creator's device.
11. Learning Summary and Archive feedback loop.
12. End-to-end TestFlight proof: one Reference -> approved Pattern/Trend/Audio -> Weekly Plan -> Daily Card -> Creator decision -> Archive/Learning.

## Acceptance Checks For First SwiftUI Pass

- Creator launches into Today without seeing admin machinery.
- Manager launches into Weekly/Admin mode without losing access to Today Preview.
- Today can be used offline from cache.
- A completed day means a decision was made, not necessarily that Creator posted.
- `Not today` immediately offers lower-effort backups.
- Weekly Plan rows always show why each card exists.
- Reference Review clearly separates raw Reference, confirmed extraction, and approved derived objects.
- Intelligence Home feels like a preparation library, not analytics.
- Brand Brief warnings block publishing when disclosure/tags are missing.
- Card Alternatives are previewed before use and never overwrite silently.
- Archive is clean history and qualitative learning, not a KPI dashboard.
