# SwiftUI Build Implementation Spec: Creator Content OS V2

Generated with `build-ios-apps:swiftui-ui-patterns`.

This is the build-facing companion to:

- `docs/swiftui-design-system-and-implementation-spec-creator-content-os-v2.md`
- `docs/canonical-training-folio-boards-creator-content-os-v2.md`
- `docs/layers-conceptual-model-creator-content-os-v2.md`
- `docs/layers-interaction-flow-creator-content-os-v2.md`
- `docs/layers-surface-creator-content-os-v2-full-mvp.md`

Canonical visual boards:

- Training Folio Creator Daily Mode: `$HOME/.codex/generated_images/019e91d6-f797-7072-bc8c-b5db7482e6cf/ig_0b70b2531334d988016a21baf5b41481919325834854242dec.png`
- Training Folio Manager Weekly Control: `$HOME/.codex/generated_images/019e91d6-f797-7072-bc8c-b5db7482e6cf/ig_0b70b2531334d988016a21bbdccef48191b828f54a07d944bd.png`
- Training Folio Intelligence System: `$HOME/.codex/generated_images/019e91d6-f797-7072-bc8c-b5db7482e6cf/ig_0b70b2531334d988016a21be44255c81918f32f4e8dd2ab875.png`

Superseded boards:

- Earlier Creator/Weekly/Intelligence boards remain in the generated image folder as history only. Do not implement their denser row layouts, package previews on Today, count-first Intelligence rows, or data-heavy admin treatments.

Purpose:

- Give the first SwiftUI implementation pass concrete file boundaries, route contracts, component APIs, feature state, repository protocols, fixture strategy, and acceptance checks.
- Keep the first build native, iPhone-only, fixture-friendly, and ready to swap in Supabase without rewriting the UI.
- Treat the regenerated Training Folio boards as the visual contract for the first SwiftUI implementation.

## Implementation Posture

Build as a native iOS 26.0+ SwiftUI app.

Use:

- `NavigationStack` with enum routes.
- One navigation stack per tab.
- `@Observable` for root-owned app/session/router state.
- Local `@State` for transient screen UI.
- `@Environment` for shared services.
- `sheet(item:)` for all modal flows.
- Native iOS 26 Liquid Glass APIs where they support navigation, toolbars, bottom action bars, and tappable control clusters.
- Deterministic fixtures and previews before live Supabase.
- Training Folio density rules: one dominant first-viewport block, folio rows, readiness strips, and disclosure for secondary detail.

Avoid:

- A view model per row.
- Boolean sheet flags.
- Passing whole service containers into every subview.
- Live network calls in previews.
- Storing model objects directly in navigation paths.
- Custom blur/glass effects that duplicate iOS 26 system materials.
- Older iOS fallback architecture in the app target.
- Implementing the superseded data-heavy board layouts.

Deployment assumptions:

- Minimum deployment target: iOS 26.0.
- Platform: iPhone only for V1.
- Xcode should use the latest available iOS 26+ simulator runtime.
- Liquid Glass can be used directly in the app target. If a shared package later supports older OS versions, gate iOS 26-only APIs in that package.

## First Build Milestone

The first milestone should prove this complete loop with fixture data:

`Reference -> approved Pattern/Trend/Audio Option -> Weekly Plan -> Published Daily Card -> Creator Today decision -> Archive entry`

Screens needed for that milestone:

- Creator Today.
- Package Detail.
- Decision Sheet.
- Archive.
- Admin Weekly Plan.
- Daily Card Review.
- References Inbox.
- Reference Review.
- Intelligence Home.
- Pattern Detail.
- Trend Detail.
- Audio Option Detail.

Screens that can be skeletal in the first milestone:

- Collabs & Events.
- Creator Profile.
- Watchlist Import.
- Learning Summary.
- Settings.

## App State

Create `App/AppState.swift`.

```swift
import Observation

@MainActor
@Observable
final class AppState {
  var activeMode: AppMode
  var currentWorkspaceID: Workspace.ID
  var currentCreatorID: Creator.ID
  var currentMember: Member
  var syncBanner: SyncBanner?

  init(
    activeMode: AppMode = .creator,
    currentWorkspaceID: Workspace.ID = .fixture,
    currentCreatorID: Creator.ID = .fixtureCreator,
    currentMember: Member = .fixtureCreator
  ) {
    self.activeMode = activeMode
    self.currentWorkspaceID = currentWorkspaceID
    self.currentCreatorID = currentCreatorID
    self.currentMember = currentMember
  }
}

enum AppMode: String, Codable, CaseIterable {
  case creator
  case admin
}
```

Rules:

- `AppState` owns app context only.
- Feature data lives in repositories or local feature state.
- Mode switching is allowed, but Creator-facing UI defaults to Creator Mode.

## App Services

Create `App/AppServices.swift`.

```swift
import Observation

@MainActor
@Observable
final class AppServices {
  let dailyCards: DailyCardRepository
  let weeklyPlans: WeeklyPlanRepository
  let references: ReferenceRepository
  let intelligence: IntelligenceRepository
  let collabs: CollabsRepository
  let creatorProfile: CreatorProfileRepository
  let archive: ArchiveRepository
  let generation: GenerationService
  let completionQueue: CompletionQueue
  let notifications: NotificationScheduler
  let externalLinks: ExternalLinkService

  init(
    dailyCards: DailyCardRepository,
    weeklyPlans: WeeklyPlanRepository,
    references: ReferenceRepository,
    intelligence: IntelligenceRepository,
    collabs: CollabsRepository,
    creatorProfile: CreatorProfileRepository,
    archive: ArchiveRepository,
    generation: GenerationService,
    completionQueue: CompletionQueue,
    notifications: NotificationScheduler,
    externalLinks: ExternalLinkService
  ) {
    self.dailyCards = dailyCards
    self.weeklyPlans = weeklyPlans
    self.references = references
    self.intelligence = intelligence
    self.collabs = collabs
    self.creatorProfile = creatorProfile
    self.archive = archive
    self.generation = generation
    self.completionQueue = completionQueue
    self.notifications = notifications
    self.externalLinks = externalLinks
  }
}
```

Preview factory:

```swift
extension AppServices {
  @MainActor
  static let preview = AppServices(
    dailyCards: PreviewDailyCardRepository(),
    weeklyPlans: PreviewWeeklyPlanRepository(),
    references: PreviewReferenceRepository(),
    intelligence: PreviewIntelligenceRepository(),
    collabs: PreviewCollabsRepository(),
    creatorProfile: PreviewCreatorProfileRepository(),
    archive: PreviewArchiveRepository(),
    generation: PreviewGenerationService(),
    completionQueue: PreviewCompletionQueue(),
    notifications: PreviewNotificationScheduler(),
    externalLinks: PreviewExternalLinkService()
  )
}
```

Rules:

- Put services in `@Environment(AppServices.self)`.
- Feature-local derived state stays in feature structs or private `@State`.
- Live Supabase services should conform to the same protocols as preview services.

## Root App Wiring

Create `App/CreatorContentOSAppView.swift`.

```swift
import SwiftUI

@MainActor
struct CreatorContentOSAppView: View {
  @State private var appState = AppState()
  @State private var services = AppServices.preview

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
    .environment(services)
  }
}
```

Production later:

- Replace `.preview` services with live dependencies created by `AppServices.live(...)`.
- Device pairing should decide the default `AppMode` and `Member` role.

## Router Contract

Create `Navigation/RouterPath.swift`.

```swift
import Observation

@MainActor
@Observable
final class RouterPath<Route: Hashable, Sheet: Identifiable> {
  var path: [Route] = []
  var presentedSheet: Sheet?

  func navigate(to route: Route) {
    path.append(route)
  }

  func present(_ sheet: Sheet) {
    presentedSheet = sheet
  }

  func reset() {
    path = []
    presentedSheet = nil
  }
}
```

Use one router per tab.

Create `Navigation/TabRouter.swift`.

```swift
import SwiftUI

@MainActor
@Observable
final class TabRouter<Tab: Hashable, Route: Hashable, Sheet: Identifiable> {
  private var routers: [Tab: RouterPath<Route, Sheet>] = [:]

  func router(for tab: Tab) -> RouterPath<Route, Sheet> {
    if let router = routers[tab] { return router }
    let router = RouterPath<Route, Sheet>()
    routers[tab] = router
    return router
  }

  func binding(for tab: Tab) -> Binding<[Route]> {
    let router = router(for: tab)
    return Binding(
      get: { router.path },
      set: { router.path = $0 }
    )
  }
}
```

## Creator Navigation

Create `Navigation/CreatorNavigation.swift`.

```swift
import SwiftUI

enum CreatorTab: String, CaseIterable, Identifiable, Hashable {
  case today
  case week
  case archive
  case settings

  var id: String { rawValue }

  @ViewBuilder
  var label: some View {
    switch self {
    case .today: Label("Today", systemImage: "house")
    case .week: Label("Week", systemImage: "calendar")
    case .archive: Label("Archive", systemImage: "archivebox")
    case .settings: Label("Settings", systemImage: "gearshape")
    }
  }
}

enum CreatorRoute: Hashable {
  case packageDetail(cardID: DailyCard.ID, initialSection: PackageSection)
  case weekDay(cardID: DailyCard.ID)
  case archiveEntry(cardID: DailyCard.ID)
}

enum CreatorSheetDestination: Identifiable, Hashable {
  case decision(cardID: DailyCard.ID)
  case completion(cardID: DailyCard.ID, decision: CompletionState)
  case postResult(cardID: DailyCard.ID)
  case alternativeRequest(cardID: DailyCard.ID, action: AlternativeAction)
  case feedback(cardID: DailyCard.ID)

  var id: String {
    switch self {
    case .decision(let cardID): "decision-\(cardID.rawValue)"
    case .completion(let cardID, let decision): "completion-\(cardID.rawValue)-\(decision.rawValue)"
    case .postResult(let cardID): "post-result-\(cardID.rawValue)"
    case .alternativeRequest(let cardID, let action): "alternative-\(cardID.rawValue)-\(action.rawValue)"
    case .feedback(let cardID): "feedback-\(cardID.rawValue)"
    }
  }
}
```

`CreatorShellView` contract:

- `TabView(selection:)`.
- `NavigationStack(path:)` per tab.
- `navigationDestination(for: CreatorRoute.self)`.
- `.sheet(item:)` per tab router.
- Inject tab router into children.

## Admin Navigation

Create `Navigation/AdminNavigation.swift`.

```swift
import SwiftUI

enum AdminTab: String, CaseIterable, Identifiable, Hashable {
  case todayPreview
  case weeklyPlan
  case references
  case intelligence
  case more

  var id: String { rawValue }

  @ViewBuilder
  var label: some View {
    switch self {
    case .todayPreview: Label("Today", systemImage: "house")
    case .weeklyPlan: Label("Week", systemImage: "calendar")
    case .references: Label("References", systemImage: "tray")
    case .intelligence: Label("Intel", systemImage: "lightbulb")
    case .more: Label("More", systemImage: "ellipsis")
    }
  }
}

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

enum AdminSheetDestination: Identifiable, Hashable {
  case addReference
  case extractionResults(referenceID: Reference.ID)
  case sourcePicker(context: SourcePickerContext)
  case generationCheck(setupID: WeeklySetup.ID)
  case alternativePreview(cardID: DailyCard.ID, alternativeID: CardAlternative.ID)
  case changeType(planID: WeeklyPlan.ID)
  case impactPreview(changeID: MidweekChange.ID)
  case editField(EditFieldContext)

  var id: String {
    switch self {
    case .addReference: "add-reference"
    case .extractionResults(let referenceID): "extraction-\(referenceID.rawValue)"
    case .sourcePicker(let context): "source-picker-\(context.id)"
    case .generationCheck(let setupID): "generation-\(setupID.rawValue)"
    case .alternativePreview(let cardID, let alternativeID): "alternative-\(cardID.rawValue)-\(alternativeID.rawValue)"
    case .changeType(let planID): "change-type-\(planID.rawValue)"
    case .impactPreview(let changeID): "impact-\(changeID.rawValue)"
    case .editField(let context): "edit-\(context.id)"
    }
  }
}
```

Rule:

- Use `More` to contain Collabs & Events, Creator Profile, Archive & Learnings, and Settings. Do not overload the iPhone tab bar with eight admin destinations.

## Model ID Pattern

Create stable typed IDs to prevent route confusion.

```swift
struct EntityID<Tag>: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
  let rawValue: String
  var id: String { rawValue }

  init(rawValue: String) {
    self.rawValue = rawValue
  }
}

enum DailyCardTag {}
enum WeeklyPlanTag {}
enum ReferenceTag {}
```

Usage:

```swift
struct DailyCard: Identifiable, Codable, Hashable {
  typealias ID = EntityID<DailyCardTag>
  let id: ID
  var date: Date
  var title: String
  var whyToday: String
  var shootability: Shootability
  var estimatedShootMinutes: Int
  var package: DailyCardPackage
  var sourceNote: String?
  var brandNote: BrandNote?
  var completionState: CompletionState?
}
```

If this generic ID adds too much friction early, use `typealias ID = String` for the first fixture build, but keep route enums specific.

## Core Enums

Create `Models/CommonEnums.swift`.

```swift
enum Shootability: String, Codable, CaseIterable, Hashable {
  case easy = "Easy"
  case medium = "Medium"
  case hard = "Hard"
}

enum CompletionState: String, Codable, CaseIterable, Hashable {
  case shot
  case posted
  case usedBackup
  case savedForTomorrow
  case skippedIntentionally
}

enum PackageSection: String, Codable, CaseIterable, Identifiable, Hashable {
  case scenes = "Scenes"
  case script = "Script"
  case caption = "Caption"
  case audio = "Audio"
  case post = "Post"
  case brand = "Brand"

  var id: String { rawValue }
}

enum SourceReason: String, Codable, CaseIterable, Hashable {
  case routine = "Routine"
  case brand = "Brand"
  case moment = "Moment"
  case trend = "Trend"
  case pattern = "Pattern"
  case evergreen = "Evergreen"
}

enum AlternativeAction: String, Codable, CaseIterable, Hashable {
  case makeEasier
  case shorterCaption
  case moreHinglish
  case newAudioTrendVersion
}

enum ReferenceStatus: String, Codable, CaseIterable, Hashable {
  case needsAnalysis
  case analyzing
  case needsConfirmation
  case confirmed
  case dismissed
}

enum ApprovalStatus: String, Codable, CaseIterable, Hashable {
  case candidate
  case approved
  case rejected
  case used
  case archived
}

enum AudioAvailability: String, Codable, CaseIterable, Hashable {
  case candidate
  case verified
  case unavailable
  case used
}

enum DensityMode: String, Codable, CaseIterable, Hashable {
  case glance
  case plan
  case review
  case library
}
```

## Repository Protocols

Create `Services/Repositories.swift`.

```swift
protocol DailyCardRepository {
  func todayCard(for creatorID: Creator.ID) async throws -> DailyCard?
  func card(id: DailyCard.ID) async throws -> DailyCard
  func cachedTodayCard(for creatorID: Creator.ID) async -> DailyCard?
}

protocol WeeklyPlanRepository {
  func currentPublishedPlan(for creatorID: Creator.ID) async throws -> WeeklyPlan?
  func draftPlan(for creatorID: Creator.ID, weekStart: Date) async throws -> WeeklyPlan?
  func approveCard(id: DailyCard.ID) async throws
  func publishPlan(id: WeeklyPlan.ID) async throws
}

protocol ReferenceRepository {
  func inbox(for creatorID: Creator.ID) async throws -> ReferenceInbox
  func reference(id: Reference.ID) async throws -> Reference
  func addReference(_ draft: ReferenceDraft) async throws -> Reference
  func analyzeReference(id: Reference.ID) async throws
  func confirmExtraction(referenceID: Reference.ID) async throws -> ReferenceExtraction
}

protocol IntelligenceRepository {
  func home(for creatorID: Creator.ID) async throws -> IntelligenceHome
  func pattern(id: Pattern.ID) async throws -> Pattern
  func trend(id: Trend.ID) async throws -> Trend
  func audioOption(id: AudioOption.ID) async throws -> AudioOption
  func approvePattern(id: Pattern.ID) async throws
  func approveTrend(id: Trend.ID) async throws
  func approveAudioOption(id: AudioOption.ID) async throws
}

protocol ArchiveRepository {
  func archive(for creatorID: Creator.ID) async throws -> [ArchiveEntry]
  func recordCompletion(_ completion: DailyCardCompletion) async throws
}
```

Rule:

- Protocols should express product actions, not table access.
- Supabase table names belong in live repository implementations, not views.

## Local Completion Queue

Create `Services/CompletionQueue.swift`.

```swift
protocol CompletionQueue {
  func complete(_ completion: DailyCardCompletion) async
  func pendingCompletions() async -> [DailyCardCompletion]
  func flushPending() async
}

struct DailyCardCompletion: Codable, Hashable, Identifiable {
  var id: String
  var cardID: DailyCard.ID
  var creatorID: Creator.ID
  var decision: CompletionState
  var decidedAt: Date
  var feedbackTags: [FeedbackTag]
  var note: String?
  var postURL: URL?
}
```

Rules:

- Creator completion writes local state immediately.
- If offline, queue the mutation.
- A sync failure is admin-visible, not a Creator-blocking error.

## Feature State Contracts

### Today

Create `Features/Today/TodayFeatureState.swift`.

```swift
enum TodayFeatureState: Equatable {
  case loading
  case ready(DailyCard)
  case offline(DailyCard, pendingCount: Int)
  case empty
  case unavailableOffline
  case failed(message: String)
}
```

`TodayView`:

- Owns `@State private var state: TodayFeatureState = .loading`.
- Reads `AppState` and `AppServices` from environment.
- Loads cached card first, then refreshes.
- Presents `CreatorSheetDestination.decision`.
- Pushes `CreatorRoute.packageDetail`.

### Weekly Plan

Create `Features/Week/WeeklyPlanFeatureState.swift`.

```swift
enum WeeklyPlanFeatureState {
  case loading
  case noSetup
  case setupDraft(WeeklySetup)
  case draftPlan(WeeklyPlan)
  case published(WeeklyPlan)
  case failed(message: String)
}
```

Rules:

- Publish actions use pessimistic completion.
- No generated Weekly Plan becomes visible until server validation succeeds.

### References

Create `Features/References/ReferencesFeatureState.swift`.

```swift
struct ReferenceInbox: Codable, Hashable {
  var needsAnalysis: [Reference]
  var needsConfirmation: [Reference]
  var confirmed: [Reference]
  var dismissed: [Reference]
}

enum ReferencesFeatureState {
  case loading
  case ready(ReferenceInbox)
  case empty
  case failed(message: String)
}
```

Rules:

- `Analyze` can be available to Manager/admin.
- Scout can add References and see status, but not approve derived objects.

### Intelligence

Create `Features/Intelligence/IntelligenceFeatureState.swift`.

```swift
struct IntelligenceHome: Codable, Hashable {
  var readyForThisWeek: [IntelligenceItem]
  var needsReview: [IntelligenceItem]
  var recentlyUsed: [IntelligenceItem]
  var sectionCounts: IntelligenceSectionCounts
}
```

Rules:

- Home screen groups by action need, not object database order.
- Detail screens foreground Creator adaptation.

## Component API Contracts

Create these before feature views.

### `EditorialScreen`

```swift
struct EditorialScreen<Content: View, BottomBar: View>: View {
  let content: Content
  let bottomBar: BottomBar?
}
```

Required behavior:

- Paper background.
- Optional bottom safe-area action area.
- Scrollable content supplied by caller.

### `ScreenHeader`

```swift
struct ScreenHeader: View {
  enum Style { case creator, admin }

  let style: Style
  let title: String
  let subtitle: String?
  let leading: HeaderAccessory?
  let trailing: HeaderAccessory?
}
```

### `JournalBlock`

```swift
struct JournalBlock<Content: View>: View {
  let content: Content
}
```

Rule:

- Do not nest `JournalBlock`.
- Do not apply `.glassEffect` inside `JournalBlock`; it is the paper content surface.

### `GlassCommandBar`

```swift
struct GlassCommandBar<Content: View>: View {
  @ViewBuilder var content: Content
}
```

Use for pinned or floating bottom command groups:

- Today actions.
- Package Detail ready action.
- Decision Sheet confirmation.
- Weekly Plan Review actions.
- Daily Card Review actions.
- Reference Review confirmation/approval actions.
- Intelligence detail `Use this week`.

Rules:

- Wrap grouped glass elements in `GlassEffectContainer`.
- Apply `.glassEffect(...)` after layout and visual modifiers.
- Keep long text out of the command bar.
- Use native iOS 26 Liquid Glass APIs only.

### `FloatingIconButton`

```swift
struct FloatingIconButton: View {
  let systemImage: String
  let accessibilityLabel: String
  let action: () -> Void
}
```

Use for compact tappable controls:

- Settings/control.
- Filters.
- Overflow.
- Bookmark/save.
- Media overlay controls.

Rules:

- Use `.glassEffect(.regular.interactive(), in: .circle)`.
- Keep frame size stable between 36 and 44 points.
- Do not use interactive glass for passive status indicators.

### `StatusChip`

```swift
struct StatusChip: View {
  let label: String
  let systemImage: String?
  let tone: StatusTone
}

enum StatusTone {
  case quiet
  case ready
  case warning
  case blocked
  case source(SourceReason)
}
```

### `EditorialTabs`

```swift
struct EditorialTabs<Tab: Identifiable & Hashable>: View where Tab.ID == String {
  let tabs: [Tab]
  @Binding var selection: Tab
  let title: (Tab) -> String
}
```

### `WarningRow`

```swift
struct WarningRow: View {
  let title: String
  let message: String
  let tone: WarningTone
  let actionTitle: String?
  let action: (() -> Void)?
}
```

### `FolioRow`

```swift
struct FolioRow<Leading: View, Trailing: View>: View {
  let title: String
  let subtitle: String?
  let chips: [StatusChipModel]
  @ViewBuilder var leading: Leading
  @ViewBuilder var trailing: Trailing
}
```

Use for:

- Weekly Plan day rows.
- Archive entries.
- Intelligence shelves.
- References rows after simplifying metadata.

Rules:

- One title.
- One subtitle/reason line.
- Maximum two chips.
- One trailing state/action.
- No full provenance, exact timestamps, confidence, and counts together.

### `ReadinessStrip`

```swift
struct ReadinessStrip: View {
  let items: [ReadinessItem]
}
```

Rules:

- Maximum three items.
- No charts.
- No large KPI presentation.
- If a blocker exists, show the blocker instead of a count.

### `EditorialDisclosure`

```swift
struct EditorialDisclosure<Content: View>: View {
  let title: String
  let summary: String?
  @ViewBuilder var content: Content
}
```

Use for:

- Source details.
- Analysis confidence.
- Edit history.
- Full brand requirements.
- Related references.
- Learning details.

## Fixture Strategy

Create `Fixtures/PreviewFixtures.swift`.

Fixture objects required:

- `Workspace.fixture`
- `Creator.fixtureCreator`
- `Member.fixtureCreator`
- `Member.fixtureManager`
- `DailyCard.fixtureTodayRaceWeek`
- `WeeklyPlan.fixtureRaceWeek`
- `Reference.fixtureTrackScreenshot`
- `Reference.fixtureGymPost`
- `Pattern.fixtureDisciplineHardDays`
- `Trend.fixtureRealTrainingHighlight`
- `AudioOption.fixtureCalmDrive`
- `Idea.fixtureWorkoutTruthTenSeconds`
- `BrandBrief.fixturePumaRaceWeek`
- `ArchiveEntry.fixturePosted`

Preview coverage required:

- Today loaded.
- Today offline with cached card.
- Today empty.
- Decision sheet not-today backup state.
- Package Detail Scenes.
- Weekly Plan published.
- Daily Card Review with warnings.
- References Inbox with all groups.
- Reference Review with candidates.
- Intelligence Home.
- Pattern Detail.

Fixtures should be small, readable, and stable. Do not inline huge JSON in previews.

## Screen Build Order

### Slice 1: App Shell And Design System

Files:

- `CreatorContentOSAppView.swift`
- `AppState.swift`
- `AppServices.swift`
- `CreatorShellView.swift`
- `AdminShellView.swift`
- `RouterPath.swift`
- `CreatorNavigation.swift`
- `AdminNavigation.swift`
- all `DesignSystem` primitives.
- `MCOGlass.swift`
- `GlassCommandBar.swift`
- `FloatingIconButton.swift`

Acceptance:

- App builds.
- Creator/Admin mode switch works with fixture services.
- Tabs preserve independent navigation history.
- Sheets present through enum destinations.
- `JournalBlock` renders as paper, not glass.
- Pinned bottom action groups use `GlassCommandBar`.
- Floating icon controls use native Liquid Glass and stable touch targets.

### Slice 2: Creator Daily Loop

Files:

- `TodayView.swift`
- `PackageDetailView.swift`
- `DecisionSheet.swift`
- `AlternativeRequestSheet.swift`
- `ArchiveView.swift`

Acceptance:

- Today shows one best reel idea.
- `See what to shoot` opens package detail.
- `Not today` immediately shows lower-effort backups.
- Completion updates the card and archive fixture state.
- Offline fixture state remains usable.
- Today does not show package preview or more than two metadata chips.
- Archive reads as a decision journal, not a data log.

### Slice 3: Admin Weekly Control

Files:

- `WeeklyPlanView.swift`
- `WeeklySetupDraftView.swift`
- `WeeklyPlanReviewView.swift`
- `DailyCardReviewView.swift`
- `PublishConfirmationView.swift`

Acceptance:

- Weekly Plan shows seven days.
- Each row shows source reason.
- Daily Card Review shows Creator Preview first.
- Publishing confirmation shows notification preview and blockers.
- Weekly Plan uses a readiness strip and folio rows instead of dense table rows.
- Day rows hide workout/audio/brand metadata until detail.

### Slice 4: Reference To Intelligence

Files:

- `ReferencesInboxView.swift`
- `ReferenceReviewView.swift`
- `IntelligenceHomeView.swift`
- `PatternDetailView.swift`
- `TrendDetailView.swift`
- `AudioOptionDetailView.swift`

Acceptance:

- References are grouped by state.
- Reference Review separates extraction confirmation from approval.
- Intelligence reads as a preparation library.
- Pattern/Trend/Audio detail screens foreground Creator adaptation and warnings.
- References rows show only preview, source type, added-by summary, and one status label.
- Intelligence Home is shelf-first and count-secondary.

### Slice 5: Remaining Full MVP Surfaces

Files:

- `CollabsEventsView.swift`
- `BrandBriefDetailView.swift`
- `CreatorProfileView.swift`
- `LearningSummaryView.swift`
- `SettingsView.swift`

Acceptance:

- Brand Briefs can block publish in fixture flow.
- Creator Profile edits feel like a living brief.
- Archive & Learnings remain qualitative.

## Supabase Integration Boundary

Do not wire Supabase into views.

Live implementation classes:

- `SupabaseDailyCardRepository`
- `SupabaseWeeklyPlanRepository`
- `SupabaseReferenceRepository`
- `SupabaseIntelligenceRepository`
- `SupabaseArchiveRepository`
- `SupabaseGenerationService`
- `SupabaseReferenceAnalysisService`

Rules:

- Reads can use Supabase Swift client behind repositories.
- AI calls go through Edge Functions.
- Device pairing token should be stored in Keychain.
- Keep RLS enabled for exposed tables.
- Service role keys never ship in the iOS app.

## Local Cache Boundary

Use a `LocalStore` protocol before choosing the final persistence engine.

```swift
protocol LocalStore {
  func cachedTodayCard(creatorID: Creator.ID) async -> DailyCard?
  func saveTodayCard(_ card: DailyCard, creatorID: Creator.ID) async
  func pendingMutations() async -> [PendingMutation]
  func appendPendingMutation(_ mutation: PendingMutation) async
  func removePendingMutation(id: PendingMutation.ID) async
}
```

Implementation choices:

- First fixture build: in-memory store.
- First offline build: SwiftData or small JSON file store.
- Production: local store plus Supabase repositories.

Do not let local cache objects become separate product objects. They are implementation details.

## Quality Gates

Before moving from one slice to the next:

- App builds without compiler errors.
- Primary previews render.
- At least one loading, empty, or error state preview exists for each new feature.
- Large lists use stable identity.
- Date and status formatting are not repeated inline in many `body` blocks.
- No screen uses a generic `Error: something went wrong` message.
- No Creator screen exposes raw admin vocabulary beyond the approved small source note.
- No dense list uses per-row glass effects.
- No long reading surface uses glass.
- Every custom group with multiple glass children uses `GlassEffectContainer`.
- `.glassEffect(...)` is applied after frame, padding, and appearance modifiers.
- `.interactive()` is only used on tappable or focusable elements.
- `JournalBlock` remains a paper content surface and never applies `.glassEffect`.
- Every primary screen declares one density mode: glance, plan, review, or library.
- Creator Today shows one idea, no package preview, maximum two chips, and maximum two visible actions.
- Admin rows use `FolioRow` or equivalent density: one title, one reason line, maximum two chips.
- Weekly Plan first viewport shows readiness plus seven-day rhythm, not per-day metadata reports.
- References Inbox hides full URLs, exact timestamps, detailed provenance, and confidence until Reference Review.
- Intelligence Home is shelf-first: Ready for this week, Needs your call, Recently used, then library navigation.
- No primary screen has more than one dominant content block in the first viewport.

## Xcode Run And Debug Workflow

When an Xcode project exists and we start creating, running, or visually verifying the app, use `build-ios-apps:ios-debugger-agent`.

Workflow:

1. Discover the booted iOS simulator and prefer a booted iPhone running iOS 26+.
2. Set XcodeBuildMCP session defaults with the project/workspace path, app scheme, simulator ID, `configuration: "Debug"`, and `useLatestOS: true`.
3. Build and run with the XcodeBuildMCP simulator workflow.
4. After launch, verify the app with UI description or screenshot before any interaction.
5. Use debugger-agent UI inspection, screenshots, and logs for simulator validation.

Do not use this workflow until there is a real Xcode project/scheme to run.

## First Build Prompt

Use this prompt when ready to create the Xcode project and first SwiftUI slice:

```text
Use build-ios-apps:swiftui-ui-patterns and build-ios-apps:ios-debugger-agent to scaffold a native iPhone-only SwiftUI app for Creator Content OS V2.

Target iOS 26.0+.

Start with Slice 1 and Slice 2 only:
- App shell
- Creator/Admin mode switch
- Design system primitives
- Fixture models/services
- Creator Today
- Package Detail
- Decision Sheet
- Archive

Use docs/swiftui-build-implementation-spec-creator-content-os-v2.md as the build contract.
Build and run on iOS Simulator, then visually verify the Creator Today flow.
```
