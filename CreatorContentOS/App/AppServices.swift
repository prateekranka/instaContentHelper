import Foundation
import Observation
import Network

typealias TodayDateProvider = @Sendable () -> String

enum TodayContentState: Equatable, Hashable, Sendable {
    case loading
    case ready
    case missingPublishedCard(date: String)
    case unavailable
}

@MainActor
@Observable
final class AppServices {
    let context: WorkspaceContext
    let isLiveSupabaseRuntime: Bool
    let memberRole: String
    private let repositories: AppRepositories
    private let todayCache: any TodayCacheStoring
    private let notifications: any TodayNotificationScheduling

    let dayStore: DayStore
    private var isLoadingToday = false
    private var weeklyPlanLayout: WeeklyPlan
    private var generationSummaryMetadata: GeneratedWeekDraft?
    private var generationSummaryDates: Set<String> = []

    var todayCard: DailyCard {
        get {
            if let day = dayStore.day(for: currentTodayDateString), day.lifecycle.exposesReadyPackage,
               let revision = day.revision { return revision.dailyCard }
            return DailyCard(
                id: context.creatorID,
                title: "No ready package",
                context: SupabaseDateFormatting.contextLine(for: currentTodayDateString),
                effortLabel: "",
                whyToday: "Generate or make a draft available.",
                scheduledDate: currentTodayDateString,
                scenes: []
            )
        }
        set {
            do { try dayStore.receivePublished(newValue) }
            catch { lastRepositoryError = error.localizedDescription }
        }
    }

    var shotSceneIDs: Set<UUID> {
        get { dayStore.day(for: currentTodayDateString)?.revision?.filmingProgress.shotSceneIDs ?? [] }
        set {
            do { try dayStore.transition(.markShots(newValue), on: currentTodayDateString) }
            catch { lastRepositoryError = error.localizedDescription }
        }
    }

    var archiveEntries: [ArchiveEntry] {
        get { dayStore.archiveEntries }
        set { dayStore.mergeArchive(newValue, authoritative: true) }
    }

    var weeklyPlan: WeeklyPlan {
        get {
            var plan = weeklyPlanLayout
            plan.days = plan.days.map { day in
                guard let date = day.scheduledDate, let package = dayStore.packages[date] else { return day }
                return package.weeklyDay
            }
            return plan
        }
        set { weeklyPlanLayout = newValue }
    }
    var weeklyBriefDraftText: String
    var weeklyIdeas: [WeeklyIdea]
    var intelligenceHome: IntelligenceHome
    var creatorProfileSummary: CreatorProfileSummary
    var creatorOnboardingPresentation: CreatorOnboardingPresentation = .loading
    var weekCards: [DailyCard] {
        get { dayStore.readyCards }
        set {
            for card in newValue {
                do { try dayStore.receivePublished(card) }
                catch { lastRepositoryError = error.localizedDescription }
            }
        }
    }
    var lastRepositoryError: String?
    var lastTodayDecisionSyncError: String?
    var hasPendingTodayDecision: Bool {
        dayStore.outbox.contains { $0.kind == .decide && $0.revisionID == todayCard.id }
    }
    var lastRepositoryRefreshAttemptAt: Date?
    var lastRepositoryRefreshAt: Date?
    var isRefreshingRepository = false
    var lastRepositoryRefreshError: String?
    var lastRepositoryRefreshSucceededAt: Date?
    var supabaseHealthStatus: RuntimeHealthStatus = .unknown
    var geminiHealthStatus: RuntimeHealthStatus = .unknown
    var isCheckingRuntimeHealth = false
    var lastRuntimeHealthCheckedAt: Date?
    var lastRuntimeHealthError: String?
    var todayContentState: TodayContentState {
        get {
            guard let day = dayStore.day(for: currentTodayDateString) else {
                return isLoadingToday ? .loading : .unavailable
            }
            switch day.lifecycle {
            case .ready, .filming, .decided: return .ready
            case .empty, .draft: return .missingPublishedCard(date: currentTodayDateString)
            case .generating: return .loading
            case .unavailable: return isLoadingToday ? .loading : .unavailable
            }
        }
        set {
            isLoadingToday = newValue == .loading
            switch newValue {
            case .missingPublishedCard(let date):
                try? dayStore.transition(.missingReady, on: date)
            case .unavailable:
                if dayStore.day(for: currentTodayDateString) == nil {
                    try? dayStore.transition(.unavailable, on: currentTodayDateString)
                }
            case .ready, .loading: break
            }
        }
    }
    var lastNotificationSchedule: TodayNotificationSchedule?
    var lastNotificationError: String?
    var isPublishingWeek = false
    var isSavingWeeklyBrief = false
    var weeklyBriefEditError: String?
    var isSavingCreatorProfile = false
    var creatorProfileEditError: String?
    var lastPublishSummary: String?
    var lastPublishError: String?
    var isMakingDayAvailable = false
    var lastMakeDayAvailableError: String?
    var isUnpublishingDay = false
    var lastUnpublishDayError: String?
    var isUpdatingReadyDayPackage = false
    var lastReadyDayPackageEditError: String?
    var pendingOverwriteGenerateDate: String?
    var regeneratingDayDates: Set<String> = []
    var regenerationDayErrors: [String: String] = [:]
    var generatingDayBriefDates: Set<String> = []
    var dayBriefGenerationErrors: [String: String] = [:]
    var dayBriefGeneratedCards: [String: GeneratedDailyCardDraft] { dayStore.packages }
    /// Cached Plan empty-day idea one-liners keyed by `yyyy-MM-dd` (fingerprint inside entry).
    var planDayIdeasByDate: [String: PlanDayIdeasCacheEntry] {
        get { dayStore.ideaSuggestions }
        set { dayStore.ideaSuggestions = newValue }
    }
    var loadingPlanDayIdeaDates: Set<String> = []
    var generatingStoryboardThumbnailCardIDs: Set<UUID> = []
    var storyboardThumbnailErrors: [UUID: String] = [:]
    var generationError: String?
    var latestGenerationSummary: GeneratedWeekDraft? {
        get {
            guard var summary = generationSummaryMetadata else { return nil }
            summary.dailyCards = generationSummaryDates.sorted().compactMap { dayStore.packages[$0] }
            return summary
        }
        set { setGenerationSummary(newValue) }
    }

    private func setGenerationSummary(_ summary: GeneratedWeekDraft?, importingCards: Bool = true, readVersion: Int? = nil) {
        generationSummaryDates = Set(summary?.dailyCards.map(\.scheduledDate) ?? [])
        generationSummaryMetadata = summary
        generationSummaryMetadata?.dailyCards = []
        if importingCards {
            for package in summary?.dailyCards ?? [] {
                do { try dayStore.receive(package, readVersion: readVersion) }
                catch { lastRepositoryError = error.localizedDescription }
            }
        }
    }

    var referenceImportPreview: ReferenceImportPreview?
    var referenceImportConfirmResult: ReferenceImportConfirmResult?
    var referenceReviewResult: ReferenceReviewResult?
    var referenceImportToast: String?
    var lastReferenceImportError: String?
    var isPreviewingReferenceImport = false
    var isConfirmingReferenceImport = false
    var isReviewingReference = false
    var testers: [TesterAccessRecord] = []
    var isLoadingTesters = false
    var testerAccessError: String?
    var testerAccessMessage: String?
    var lastActionMessage: String?
    private let todayDate: TodayDateProvider
    let aiConsentStore: any AIConsentStoring
    var isAIConsentSheetPresented = false
    var aiConsentAllowsOutbound = false
    var aiConsentEpoch = 0

    /// Resolves the Plan package for a date from session cards or the latest draft summary.
    func dayPackage(for scheduledDate: String) -> GeneratedDailyCardDraft? {
        dayStore.day(for: scheduledDate)?.revision?.content
    }

    /// Today Shoot Folio card with Gemini storyboard thumbnails from Plan when Today is missing them.
    var todayShootFolioCard: DailyCard {
        var card = todayCard
        let assets = resolvedStoryboardThumbnailAssets(for: card)
        if !assets.isEmpty {
            card.storyboardThumbnailAssets = assets
        }
        if card.voiceoverTimeline?.isEmpty != false,
           let package = dayPackage(for: card.scheduledDate ?? currentTodayDateString),
           !package.voiceoverTimeline.isEmpty {
            card.voiceoverTimeline = package.voiceoverTimeline
        }
        if card.shotTimeline?.isEmpty != false,
           let package = dayPackage(for: card.scheduledDate ?? currentTodayDateString),
           !package.shotTimeline.isEmpty {
            card.shotTimeline = package.shotTimeline
        }
        return card
    }

    /// Prefer Plan/session Gemini storyboard assets when the published Today card lacks them.
    func resolvedStoryboardThumbnailAssets(for card: DailyCard) -> [StoryboardThumbnailAsset] {
        if Self.hasUsableStoryboardThumbnails(card.storyboardThumbnailAssets) {
            return card.storyboardThumbnailAssets ?? []
        }

        return dayStore.card(revisionID: card.id)?.storyboardThumbnailAssets ?? card.storyboardThumbnailAssets ?? []
    }

    /// Copies Plan Gemini thumbnails onto `todayCard` so Shoot Folio can render them.
    @discardableResult
    func hydrateTodayStoryboardThumbnailsFromPlanPackage() -> Bool {
        let assets = resolvedStoryboardThumbnailAssets(for: todayCard)
        guard Self.hasUsableStoryboardThumbnails(assets) else { return false }
        let existing = todayCard.storyboardThumbnailAssets ?? []
        guard existing != assets else { return false }
        todayCard.storyboardThumbnailAssets = assets
        if let package = dayPackage(for: todayCard.scheduledDate ?? currentTodayDateString) {
            if todayCard.voiceoverTimeline?.isEmpty != false, !package.voiceoverTimeline.isEmpty {
                todayCard.voiceoverTimeline = package.voiceoverTimeline
            }
            if todayCard.shotTimeline?.isEmpty != false, !package.shotTimeline.isEmpty {
                todayCard.shotTimeline = package.shotTimeline
            }
        }
        saveTodaySnapshot(source: "storyboard-thumbnail-hydrate")
        return true
    }

    private static func hasUsableStoryboardThumbnails(_ assets: [StoryboardThumbnailAsset]?) -> Bool {
        guard let assets, !assets.isEmpty else { return false }
        return assets.contains { $0.publicURL?.nilIfBlank != nil }
    }

    private var outboxReplayTask: Task<Void, Never>?
    private var outboxNeedsReplay = false
    private var outboxResults: [String: OutboxReplayResult] = [:]
    private var outboxErrors: [String: Error] = [:]
    private let networkMonitor = NWPathMonitor()
    private var networkWasAvailable: Bool?

    init(
        repositories: AppRepositories,
        isLiveSupabaseRuntime: Bool = false,
        memberRole: String = "owner",
        todayCache: any TodayCacheStoring = FileTodayCacheStore(),
        notifications: any TodayNotificationScheduling = NoopTodayNotificationScheduler(),
        todayDate: @escaping TodayDateProvider = { SupabaseDateFormatting.todayDateString() },
        todayCard: DailyCard,
        archiveEntries: [ArchiveEntry],
        weeklyPlan: WeeklyPlan,
        weeklyIdeas: [WeeklyIdea],
        intelligenceHome: IntelligenceHome,
        creatorProfileSummary: CreatorProfileSummary,
        weekCards: [DailyCard],
        todayContentState: TodayContentState = .ready,
        aiConsentStore: (any AIConsentStoring)? = nil
    ) {
        self.context = repositories.context
        self.isLiveSupabaseRuntime = isLiveSupabaseRuntime
        self.memberRole = memberRole
        self.repositories = repositories
        self.todayCache = todayCache
        self.notifications = notifications
        self.todayDate = todayDate
        self.aiConsentStore = aiConsentStore ?? UserDefaultsAIConsentStore(
            workspaceID: repositories.context.workspaceID,
            creatorID: repositories.context.creatorID
        )
        self.aiConsentAllowsOutbound = AIConsentPolicy.allowsOutbound(self.aiConsentStore.load())
        self.dayStore = DayStore(context: repositories.context)
        self.weeklyPlanLayout = weeklyPlan
        weeklyBriefDraftText = weeklyPlan.weeklyBriefText
        self.weeklyIdeas = weeklyIdeas
        self.intelligenceHome = intelligenceHome
        self.creatorProfileSummary = creatorProfileSummary
        isLoadingToday = todayContentState == .loading
        if case .missingPublishedCard(let date) = todayContentState {
            try? dayStore.transition(.missingReady, on: date)
        }
        for card in weekCards { try? dayStore.receivePublished(card) }
        if todayContentState == .ready { try? dayStore.receivePublished(todayCard) }
        dayStore.mergeArchive(archiveEntries)
        if isLiveSupabaseRuntime {
            _ = loadTodayFromCache()
            supabaseHealthStatus = .unknown
            geminiHealthStatus = .unknown
        } else {
            supabaseHealthStatus = .sample
            geminiHealthStatus = .sample
        }
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let returned = available && self.networkWasAvailable == false
                self.networkWasAvailable = available
                if returned { await self.replayOutboxImmediately() }
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "contenthelper.outbox.network"))
    }

    deinit { networkMonitor.cancel() }

    var canManageTesterAccess: Bool {
        isLiveSupabaseRuntime && memberRole == "owner"
    }

    /// Creator voice is configured when positioning and voice rules are both set.
    var voiceIsConfigured: Bool {
        let positioning = creatorProfileSummary.positioning.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasRules = !creatorProfileSummary.voiceRules.isEmpty
            || !creatorProfileSummary.voiceLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !positioning.isEmpty && hasRules
    }

    /// Plan / global generation still ignores Launch-A deferral (VG-6).
    /// First-idea skip/continue passes `allowDeferredVoice` on `generateDayCard` instead.
    /// A global `established && !voiceIsConfigured` getter was rejected: it would open Plan generate_day.
    var voiceDeferred: Bool {
        false
    }

    /// Honest Launch-A deferral after persist: established profile, empty voice, no fabricated rules.
    private var isHonestDeferredVoice: Bool {
        creatorProfileSummary.onboardingState == .established && !voiceIsConfigured
    }

    /// True while the post-onboarding Creator Voice prefill draft is active.
    /// UI-only — cleared on the creator's first voice save.
    var voicePrefilled: Bool {
        UserDefaultsOnboardingStore().loadCompletedData()?.voicePrefilled == true
    }

    /// Voice gate: generation is blocked only when voice is neither configured nor deferred.
    var voiceGateOpen: Bool {
        !voiceIsConfigured && !voiceDeferred
    }

    /// Plan generation requires configured voice (VG-6). First-idea may pass `allowDeferredVoice`.
    /// The app is creator-only — no role check applies anymore.
    var canGenerateContent: Bool {
        !voiceGateOpen
    }

    var currentTodayDateString: String {
        todayDate()
    }

    static var preview: AppServices {
        fixtureBacked(repositories: .fixture)
    }

    static func fixtureBacked(
        repositories: AppRepositories = .fixture,
        isLiveSupabaseRuntime: Bool = false,
        memberRole: String = "owner",
        todayCache: any TodayCacheStoring = FileTodayCacheStore(),
        notifications: any TodayNotificationScheduling = NoopTodayNotificationScheduler(),
        todayDate: @escaping TodayDateProvider = { SupabaseDateFormatting.todayDateString() },
        aiConsentStore: (any AIConsentStoring)? = nil
    ) -> AppServices {
        let services = AppServices(
            repositories: repositories,
            isLiveSupabaseRuntime: isLiveSupabaseRuntime,
            memberRole: memberRole,
            todayCache: todayCache,
            notifications: notifications,
            todayDate: todayDate,
            todayCard: DebugLaunchFlags.forceEmptyToday ? .emptyTodayPlaceholder : .raceWeekToday,
            archiveEntries: FakeServer.shared.initialArchiveEntries,
            weeklyPlan: .raceWeek,
            weeklyIdeas: WeeklyIdea.raceWeekBank,
            intelligenceHome: .raceWeekLibrary,
            creatorProfileSummary: .creatorFixture,
            weekCards: DailyCard.weekFixtures,
            aiConsentStore: aiConsentStore
        )
        return services
    }

    static func liveBacked(
        repositories: AppRepositories,
        memberRole: String,
        todayCache: any TodayCacheStoring = FileTodayCacheStore(),
        notifications: any TodayNotificationScheduling = NoopTodayNotificationScheduler()
    ) -> AppServices {
        AppServices(
            repositories: repositories,
            isLiveSupabaseRuntime: true,
            memberRole: memberRole,
            todayCache: todayCache,
            notifications: notifications,
            todayCard: DailyCard(
                title: "Checking today's plan",
                context: "Live Supabase",
                effortLabel: "Loading",
                whyToday: "Your latest published card will appear after the live refresh completes.",
                scenes: []
            ),
            archiveEntries: [],
            weeklyPlan: WeeklyPlan(
                title: "Generate a Week",
                eyebrow: "LIVE WORKSPACE",
                weekRange: "Checking schedule",
                readinessLine: "Loading live plan",
                isSoftLocked: false,
                days: [],
                weeklyBriefText: "",
                setupSections: []
            ),
            weeklyIdeas: [],
            intelligenceHome: IntelligenceHome(
                sourcePulse: SourcePulseSummary(
                    title: "Checking sources",
                    subtitle: "Loading live Supabase context",
                    references: []
                ),
                readyForThisWeek: [],
                needsReview: [],
                ideaCandidates: [],
                recentlyUsed: [],
                librarySections: []
            ),
            creatorProfileSummary: CreatorProfileSummary.emptyLiveFallback(displayName: "Loading"),
            weekCards: [],
            todayContentState: .loading
        )
    }

    func completeToday(with completionState: CompletionState) {
        completeToday(with: DailyDecision(completionState: completionState))
    }

    var shotSceneCount: Int {
        todayCard.scenes.count { shotSceneIDs.contains($0.id) }
    }

    var unshotSceneCount: Int {
        max(todayCard.scenes.count - shotSceneCount, 0)
    }

    var areAllScenesShot: Bool {
        !todayCard.scenes.isEmpty && unshotSceneCount == 0
    }

    func isSceneShot(_ scene: ShotScene) -> Bool {
        shotSceneIDs.contains(scene.id)
    }

    func markSceneShot(_ scene: ShotScene) {
        guard todayCard.scenes.contains(where: { $0.id == scene.id }),
              !shotSceneIDs.contains(scene.id) else { return }
        shotSceneIDs.insert(scene.id)
        lastActionMessage = "Scene \(scene.number) marked shot."
        if areAllScenesShot, dayStore.day(for: currentTodayDateString)?.revision?.decision == nil {
            completeToday(with: DailyDecision.shot)
        } else {
            saveTodaySnapshot(source: "shot-progress")
        }
    }

    func markAllScenesShot() {
        shotSceneIDs.formUnion(todayCard.scenes.map(\.id))
        lastActionMessage = "All scenes marked shot."
        if dayStore.day(for: currentTodayDateString)?.revision?.decision == nil {
            completeToday(with: DailyDecision.shot)
        } else {
            saveTodaySnapshot(source: "shot-progress")
        }
    }

    /// Records the card as posted once all scenes are shot. Produces the green
    /// success toast the creator sees after shipping. The Shoot Folio only
    /// reveals this action after every scene is marked shot.
    func markPosted() {
        guard canMarkPosted else { return }
        lastActionMessage = "Content marked as posted."
        completeToday(with: DailyDecision.posted)
    }

    /// Replaces a posted decision with the existing shot decision while keeping
    /// every completed scene. The archive upsert uses the daily card ID, so this
    /// updates the current decision instead of creating a second archive row.
    func undoPosted() {
        guard todayCard.completionState == .posted else { return }
        lastActionMessage = todayCard.isNonFilmingPost
            ? "Posted status removed."
            : "Posted status removed. Scenes stay marked shot."
        completeToday(with: DailyDecision.shot)
    }

    var canMarkPosted: Bool {
        guard case .ready = todayContentState else { return false }
        return (areAllScenesShot || todayCard.isNonFilmingPost) && todayCard.completionState != .posted
    }

    var canChooseEasierOption: Bool {
        todayCard.completionState != .shot && todayCard.completionState != .posted
    }

    func completeToday(with decision: DailyDecision) {
        let isFilmingDecision = decision.completionState == .shot || decision.completionState == .posted
        guard isFilmingDecision || canChooseEasierOption else { return }
        guard canApplyTodayDecision(decision) else { return }
        guard prepareTodayDecision(decision) != nil else { return }
        Task { await replayOutboxImmediately() }
    }

    @discardableResult
    func completeTodayImmediately(with decision: DailyDecision) async -> ArchiveEntry {
        let fallback = makeArchiveEntry(for: todayCard, decision: decision)
        guard canApplyTodayDecision(decision), let intent = prepareTodayDecision(decision) else { return fallback }
        await replayOutboxImmediately()
        if case .decision(let entry) = outboxResults[intent.id] { return entry }
        return intent.archiveSnapshot ?? fallback
    }

    private func canApplyTodayDecision(_ decision: DailyDecision) -> Bool {
        guard var day = dayStore.day(for: currentTodayDateString) else { return false }
        do { try day.transition(.decide(decision)); return true }
        catch { return false }
    }

    private func prepareTodayDecision(_ decision: DailyDecision) -> ContentIntent? {
        let card = todayCard
        var decidedCard = card
        decidedCard.completionState = decision.completionState
        var intent = ContentIntent(kind: .decide, context: context, scheduledDate: card.scheduledDate ?? currentTodayDateString, revisionID: card.id)
        intent.decision = decision
        intent.undoPosted = card.completionState == .posted && decision.completionState == .shot
        intent.cardSnapshot = decidedCard
        intent.archiveSnapshot = makeArchiveEntry(for: card, decision: decision)
        do {
            try enqueueIntent(intent)
            try dayStore.transition(.decide(decision), on: intent.scheduledDate)
            if let entry = intent.archiveSnapshot { dayStore.mergeArchive([entry]) }
            try persistDaySnapshot(source: "decision")
            lastTodayDecisionSyncError = nil
            Task { await cancelTodayNotification() }
            return intent
        } catch {
            lastTodayDecisionSyncError = error.localizedDescription
            return nil
        }
    }

    var canPublishCurrentWeek: Bool {
        guard canGenerateContent,
              !isPublishingWeek,
              !weeklyPlan.isSoftLocked,
              weeklyPlan.days.count == 7,
              weeklyPlan.openDayCount == 0
        else {
            return false
        }

        guard let draft = latestGenerationSummary else {
            return weeklyPlan.days.allSatisfy { $0.state != .open }
        }

        guard draft.weeklyPlanID == weeklyPlan.id,
              draft.isCompleteWeekDraft,
              weeklyPlan.openDayCount == 0
        else {
            return false
        }

        let planDates = Set(weeklyPlan.days.compactMap(\.scheduledDate))
        let draftDates = Set(draft.dailyCards.map(\.scheduledDate))
        return planDates.count == 7 && planDates == draftDates
    }

#if DEBUG
    func applyDebugWeekStartOverrideIfNeeded(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        let argumentValue = arguments
            .first { $0.hasPrefix("MCO_DEBUG_WEEK_START=") }?
            .split(separator: "=", maxSplits: 1)
            .last
            .map(String.init)

        guard let startDate = (environment["MCO_DEBUG_WEEK_START"] ?? argumentValue)?.nilIfBlank,
              SupabaseDateFormatting.weekEndDate(starting: startDate) != startDate
        else {
            return
        }

        let currentStartDate = weeklyPlan.weekStartDate
            ?? weeklyPlan.days.compactMap(\.scheduledDate).first
        guard currentStartDate != startDate else {
            return
        }

        updateWeeklyStartDate(startDate)
    }
#endif

    /// When no working draft exists and the loaded week start is in the past,
    /// reset the manager view to a seven-day unlocked window starting today.
    /// Replaces the old published/historical plan with a new manager-local
    /// WeeklyPlan carrying a fresh ID and isSoftLocked == false, preserving
    /// brief/setup context. This avoids leaving the manager on a stale date
    /// pointing at a published backend plan.
    func normalizeManagerWeekStartIfStale() {
        guard latestGenerationSummary == nil else { return }

        let today = todayDate()
        guard let weekStartDate = weeklyPlan.weekStartDate,
              SupabaseDateFormatting.isDatePast(weekStartDate, todayString: today)
        else {
            return
        }

        let constrainedEndDate = SupabaseDateFormatting.weekEndDate(starting: today)
        let openDays = Self.emptyWeekDays(starting: today)
        let range = SupabaseDateFormatting.dateRange(
            starting: today,
            ending: constrainedEndDate
        )
        weeklyPlan = WeeklyPlan(
            id: UUID(),
            title: weeklyPlan.title,
            eyebrow: weeklyPlan.eyebrow,
            weekRange: range,
            weekStartDate: today,
            weekEndDate: constrainedEndDate,
            readinessLine: "",
            isSoftLocked: false,
            days: openDays,
            weeklyBriefText: weeklyPlan.weeklyBriefText,
            setupSections: weeklyPlan.setupSections
        )
        weeklyPlan.readinessLine = weeklyPlan.computedReadinessLine
        generationError = nil
    }

    func updateWeeklyStartDate(_ startDate: String) {
        guard !weeklyPlan.isSoftLocked else { return }

        guard !SupabaseDateFormatting.isDatePast(startDate, todayString: todayDate()) else {
            generationError = "past_generation_date_not_allowed"
            return
        }

        let constrainedEndDate = SupabaseDateFormatting.weekEndDate(starting: startDate)
        let projectedDraft = Self.projectedGeneratedDraft(latestGenerationSummary, starting: startDate)
        let days = Self.weekDays(starting: startDate, preserving: projectedDraft?.dailyCards ?? [])
        weeklyPlan.weekStartDate = startDate
        weeklyPlan.weekEndDate = constrainedEndDate
        weeklyPlan.weekRange = SupabaseDateFormatting.dateRange(
            starting: startDate,
            ending: constrainedEndDate
        )
        weeklyPlan.days = days
        weeklyPlan.readinessLine = weeklyPlan.computedReadinessLine
        latestGenerationSummary = projectedDraft
        generationError = nil
        lastPublishError = nil
    }

    func applyGeneratedDraft(_ draft: GeneratedWeekDraft) {
        guard !draft.dailyCards.isEmpty else {
            generationError = DayGenerationErrorDisplay.message(forCode: "invalid_generated_week")
            return
        }

        latestGenerationSummary = draft
        weeklyPlan = draft.weeklyPlan(
            setupSections: weeklyPlan.setupSections,
            weeklyBriefText: weeklyPlan.weeklyBriefText
        )
        weeklyIdeas = draft.ideaBank.isEmpty ? weeklyIdeas : draft.ideaBank
    }

    private static func emptyWeekDays(starting startDate: String) -> [WeeklyDay] {
        weekDays(starting: startDate, preserving: [])
    }

    private static func projectedGeneratedDraft(
        _ draft: GeneratedWeekDraft?,
        starting startDate: String
    ) -> GeneratedWeekDraft? {
        guard var draft else { return nil }

        let cardsByDate = draft.dailyCards.reduce(into: [String: GeneratedDailyCardDraft]()) { result, card in
            result[card.scheduledDate] = card
        }
        let projectedCards = SupabaseDateFormatting.weekDates(starting: startDate).compactMap { cardsByDate[$0] }
        guard !projectedCards.isEmpty else { return nil }

        draft.dailyCards = projectedCards
        return draft
    }

    private static func weekDays(
        starting startDate: String,
        preserving cards: [GeneratedDailyCardDraft]
    ) -> [WeeklyDay] {
        let dateParser = DateFormatter()
        dateParser.locale = Locale(identifier: "en_US_POSIX")
        dateParser.timeZone = TimeZone(secondsFromGMT: 0)
        dateParser.dateFormat = "yyyy-MM-dd"

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
        weekdayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        weekdayFormatter.dateFormat = "EEE"

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dayFormatter.dateFormat = "d"

        let cardsByDate = cards.reduce(into: [String: GeneratedDailyCardDraft]()) { result, card in
            result[card.scheduledDate] = card
        }

        return SupabaseDateFormatting.weekDates(starting: startDate).map { dateString in
            if let card = cardsByDate[dateString] {
                return card.weeklyDay
            }

            let date = dateParser.date(from: dateString)
            return WeeklyDay(
                weekday: date.map { weekdayFormatter.string(from: $0).uppercased() } ?? "",
                date: date.map { dayFormatter.string(from: $0) } ?? "",
                scheduledDate: dateString,
                title: "Open",
                reason: "",
                source: .open,
                state: .open,
                isSoftLocked: false
            )
        }
    }

    func generatedDailyCard(for dayID: UUID) -> GeneratedDailyCardDraft? {
        if let card = dayBriefGeneratedCards.values.first(where: { $0.id == dayID }) {
            return card
        }
        return latestGenerationSummary?.dailyCards.first { $0.id == dayID }
    }

    func generatedDailyCard(for day: WeeklyDay) -> GeneratedDailyCardDraft? {
        if let scheduledDate = day.scheduledDate,
           let card = dayBriefGeneratedCards[scheduledDate] {
            return card
        }
        if let card = dayBriefGeneratedCards.values.first(where: { $0.id == day.id }) {
            return card
        }
        return latestGenerationSummary?.dailyCards.first {
            $0.id == day.id || $0.scheduledDate == day.scheduledDate
        }
    }

    func regeneratedDailyCard(
        scheduledDate: String,
        preserveManualEdits: Bool,
        dayGuidance: String? = nil
    ) async throws -> GeneratedDailyCardDraft {
        guard !SupabaseDateFormatting.isDatePast(scheduledDate, todayString: todayDate()) else {
            let error = "past_generation_date_not_allowed"
            regenerationDayErrors[scheduledDate] = error
            logGeneration("regenerate_day rejected past_generation_date scheduled_date=\(scheduledDate)")
            throw RepositoryError.edgeFunction(error)
        }

        guard canGenerateContent else {
            let error = "creator_voice_required"
            regenerationDayErrors[scheduledDate] = error
            logGeneration("regenerate_day rejected creator_voice_required scheduled_date=\(scheduledDate)")
            throw RepositoryError.edgeFunction(error)
        }

        try requireAIConsent(for: .regenerateDay(scheduledDate: scheduledDate))

        guard !weeklyPlan.isSoftLocked else {
            let error = "published_week_locked"
            regenerationDayErrors[scheduledDate] = error
            logGeneration("regenerate_day rejected published_week_locked scheduled_date=\(scheduledDate)")
            throw RepositoryError.edgeFunction(error)
        }

        guard !regeneratingDayDates.contains(scheduledDate) else {
            let message = DayGenerationErrorDisplay.message(forCode: "generation_already_running")
            regenerationDayErrors[scheduledDate] = message
            logGeneration("regenerate_day rejected generation_already_running scheduled_date=\(scheduledDate)")
            throw RepositoryError.edgeFunction(message)
        }

        if let pending = dayStore.outbox.first(where: { $0.isGeneration && $0.scheduledDate == scheduledDate }) {
            guard pending.weeklyPlanID == weeklyPlan.id, pending.preserveManualEdits == preserveManualEdits, pending.dayGuidance == dayGuidance else { throw RepositoryError.edgeFunction("generation_already_running") }
            await replayOutboxImmediately()
            return try generatedResult(for: pending)
        }
        var intent = ContentIntent(kind: .generate, context: context, scheduledDate: scheduledDate, revisionID: dayPackage(for: scheduledDate)?.id ?? UUID())
        intent.requestedRevisionID = UUID()
        intent.weeklyPlanID = weeklyPlan.id
        intent.preserveManualEdits = preserveManualEdits
        intent.dayGuidance = dayGuidance
        do {
            try enqueueGeneration(intent)
            await replayOutboxImmediately()
            return try generatedResult(for: intent)
        } catch {
            regenerationDayErrors[scheduledDate] = DayGenerationErrorDisplay.message(for: error)
            throw error
        }
    }

    /// Resolves Plan idea one-liners for a date. Returns cached DeepSeek/live ideas when
    /// present for the same setup fingerprint; otherwise the deterministic on-device builder
    /// so Plan is never blank.
    func planDayIdeas(
        for scheduledDate: String,
        setup: PlanDaySetupSummary
    ) -> [PlanDayIdeaCandidate] {
        if let cached = planDayIdeasByDate[scheduledDate],
           cached.setupFingerprint == setup.cacheFingerprint,
           !cached.ideas.isEmpty {
            return cached.ideas
        }
        return PlanDayIdeaBuilder.buildIdeas(scheduledDate: scheduledDate, setup: setup)
    }

    /// Loads Plan ideas for an empty day. Fixture / non-live runtimes use the on-device
    /// builder. Live runtimes call `generate-plan-ideas` (DeepSeek primary) and fall back
    /// to the builder on any failure / client timeout so the launcher never hangs past ~60s.
    func refreshPlanDayIdeas(
        scheduledDate: String,
        setup: PlanDaySetupSummary
    ) async {
        if let cached = planDayIdeasByDate[scheduledDate],
           cached.setupFingerprint == setup.cacheFingerprint,
           !cached.ideas.isEmpty {
            return
        }

        guard !loadingPlanDayIdeaDates.contains(scheduledDate) else { return }

        if !isLiveSupabaseRuntime {
            planDayIdeasByDate[scheduledDate] = PlanDayIdeasCacheEntry(
                setupFingerprint: setup.cacheFingerprint,
                ideas: PlanDayIdeaBuilder.buildIdeas(scheduledDate: scheduledDate, setup: setup)
            )
            return
        }

        loadingPlanDayIdeaDates.insert(scheduledDate)
        defer { loadingPlanDayIdeaDates.remove(scheduledDate) }

        do {
            try requireAIConsent(for: .planIdeas)
        } catch {
            if planDayIdeasByDate[scheduledDate]?.setupFingerprint != setup.cacheFingerprint {
                planDayIdeasByDate[scheduledDate] = PlanDayIdeasCacheEntry(
                    setupFingerprint: setup.cacheFingerprint,
                    ideas: PlanDayIdeaBuilder.buildIdeas(scheduledDate: scheduledDate, setup: setup)
                )
            }
            return
        }

        do {
            let ideas = try await fetchPlanDayIdeasWithTimeout(
                scheduledDate: scheduledDate,
                setup: setup
            )
            if ideas.count == PlanDayIdeaBuilder.ideaCount {
                planDayIdeasByDate[scheduledDate] = PlanDayIdeasCacheEntry(
                    setupFingerprint: setup.cacheFingerprint,
                    ideas: ideas
                )
                return
            }
        } catch {
            logGeneration(
                "plan_ideas failed scheduled_date=\(scheduledDate) error=\(error.localizedDescription)"
            )
        }

        if planDayIdeasByDate[scheduledDate]?.setupFingerprint != setup.cacheFingerprint {
            planDayIdeasByDate[scheduledDate] = PlanDayIdeasCacheEntry(
                setupFingerprint: setup.cacheFingerprint,
                ideas: PlanDayIdeaBuilder.buildIdeas(scheduledDate: scheduledDate, setup: setup)
            )
        }
    }

    private func fetchPlanDayIdeasWithTimeout(
        scheduledDate: String,
        setup: PlanDaySetupSummary
    ) async throws -> [PlanDayIdeaCandidate] {
        let timeoutNanoseconds = UInt64(
            PlanDayIdeaPayloadLimits.clientTimeoutSeconds * 1_000_000_000
        )
        return try await withThrowingTaskGroup(of: [PlanDayIdeaCandidate].self) { group in
            group.addTask {
                try await self.repositories.planDayIdeas.generatePlanDayIdeas(
                    creatorID: self.context.creatorID,
                    scheduledDate: scheduledDate,
                    setup: setup,
                    context: self.context
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw RepositoryError.edgeFunction("plan_ideas_timeout")
            }
            guard let result = try await group.next() else {
                throw RepositoryError.edgeFunction("plan_ideas_timeout")
            }
            group.cancelAll()
            return result
        }
    }

    @discardableResult
    func generateDayCard(
        scheduledDate: String,
        dayBrief: String,
        confirmOverwrite: Bool = false,
        allowDeferredVoice: Bool = false
    ) async throws -> GeneratedDailyCardDraft {
        let brief = dayBrief.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brief.isEmpty else {
            let error = "day_brief_required"
            dayBriefGenerationErrors[scheduledDate] = error
            throw RepositoryError.edgeFunction(error)
        }

        guard !SupabaseDateFormatting.isDatePast(scheduledDate, todayString: todayDate()) else {
            let error = "past_generation_date_not_allowed"
            dayBriefGenerationErrors[scheduledDate] = error
            logGeneration("generate_day rejected past_generation_date scheduled_date=\(scheduledDate)")
            throw RepositoryError.edgeFunction(error)
        }

        let firstIdeaDeferredVoiceAllowed = allowDeferredVoice && isHonestDeferredVoice
        guard canGenerateContent || firstIdeaDeferredVoiceAllowed else {
            let error = "creator_voice_required"
            dayBriefGenerationErrors[scheduledDate] = error
            logGeneration("generate_day rejected creator_voice_required scheduled_date=\(scheduledDate)")
            throw RepositoryError.edgeFunction(error)
        }

        try requireAIConsent(for: .generateDay(scheduledDate: scheduledDate))

        if let pending = dayStore.outbox.first(where: { $0.isGeneration && $0.scheduledDate == scheduledDate }) {
            guard pending.dayBrief == brief else { throw RepositoryError.edgeFunction("generation_already_running") }
            await replayOutboxImmediately()
            return try generatedResult(for: pending)
        }
        let existing = dayPackage(for: scheduledDate)
        if existing != nil && !confirmOverwrite {
            pendingOverwriteGenerateDate = scheduledDate
            throw RepositoryError.edgeFunction("ready_package_overwrite_required")
        }
        pendingOverwriteGenerateDate = nil
        var intent = ContentIntent(kind: existing == nil ? .generate : .replaceDay, context: context, scheduledDate: scheduledDate, revisionID: existing?.id ?? UUID())
        intent.dayBrief = brief
        do {
            try enqueueGeneration(intent)
            await replayOutboxImmediately()
            return try generatedResult(for: intent)
        } catch {
            dayBriefGenerationErrors[scheduledDate] = DayGenerationErrorDisplay.message(for: error)
            throw error
        }
    }

    @discardableResult
    private func applyDayGenerationResult(
        _ result: DailyGenerationResult,
        scheduledDate: String
    ) throws -> GeneratedDailyCardDraft {
            guard result.targetScheduledDate == scheduledDate,
                  result.dailyCard.scheduledDate == scheduledDate
            else {
                logGeneration(
                    "generate_day rejected invalid_generated_day scheduled_date=\(scheduledDate) target=\(result.targetScheduledDate) card_date=\(result.dailyCard.scheduledDate)"
                )
                throw RepositoryError.edgeFunction("invalid_generated_day")
            }
            if case .generating(let run) = dayStore.day(for: scheduledDate)?.lifecycle {
                guard run.generationID == nil || run.generationID == result.generationID else {
                    throw DayTransitionError.staleAnswer
                }
                try dayStore.transition(.generated(result.dailyCard), on: scheduledDate)
            } else {
                try dayStore.receive(result.dailyCard)
            }
            saveTodaySnapshot(source: "generated-day")
            let integratesWithCurrentWeeklyReview = result.weeklyPlanID == weeklyPlan.id
                && weeklyPlan.days.contains(where: { $0.scheduledDate == scheduledDate })
            if integratesWithCurrentWeeklyReview {
                Task { @MainActor in
                    await reconcileGeneratedDayCardFromCurrentWeeklyContent(
                        scheduledDate: scheduledDate,
                        suppressRepositoryErrorOnFailure: true
                    )
                }
            }
            lastRepositoryError = nil
            logGeneration("generate_day completed scheduled_date=\(scheduledDate) daily_card_id=\(result.dailyCard.id)")
            return result.dailyCard
    }

    func generateStoryboardThumbnails(
        for card: GeneratedDailyCardDraft,
        rowIndexes: [Int]? = nil,
        force: Bool = false,
        revisionInstructions: String? = nil
    ) async throws -> [StoryboardThumbnailAsset] {
        guard canGenerateContent else {
            let error = "role_not_allowed"
            storyboardThumbnailErrors[card.id] = error
            throw RepositoryError.edgeFunction(error)
        }

        try requireAIConsent(for: .storyboardThumbnails(cardID: card.id, promptIfDeclined: true))

        if generatingStoryboardThumbnailCardIDs.contains(card.id) {
            return card.storyboardThumbnailAssets
        }

        generatingStoryboardThumbnailCardIDs.insert(card.id)
        storyboardThumbnailErrors[card.id] = nil
        defer { generatingStoryboardThumbnailCardIDs.remove(card.id) }

        do {
            let assets = try await repositories.storyboardThumbnails.generateStoryboardThumbnails(
                creatorID: context.creatorID,
                dailyCardID: card.id,
                rowIndexes: rowIndexes,
                force: force,
                revisionInstructions: revisionInstructions,
                context: context
            )
            applyStoryboardThumbnailAssets(assets, toDailyCardID: card.id)
            generationError = nil
            lastRepositoryError = nil
            return assets
        } catch {
            let message = DayGenerationErrorDisplay.message(for: error)
            storyboardThumbnailErrors[card.id] = message
            throw RepositoryError.edgeFunction(message)
        }
    }

    func prepareStoryboardThumbnailsForVisibleCard(dailyCardID: UUID) async {
        guard let card = resolvedDailyCardForStoryboardThumbnail(dailyCardID: dailyCardID),
              !generatingStoryboardThumbnailCardIDs.contains(card.id)
        else { return }

        if !Self.hasMissingStoryboardThumbnails(for: card) {
            if let summaryCard = latestGenerationSummary?.dailyCards.first(where: { $0.id == dailyCardID }),
               Self.hasMissingStoryboardThumbnails(for: summaryCard) {
                applyStoryboardThumbnailAssets(card.storyboardThumbnailAssets, toDailyCardID: dailyCardID)
            }
            return
        }

        do {
            try requireAIConsent(for: .storyboardThumbnails(cardID: card.id, promptIfDeclined: false))
        } catch {
            return
        }

        _ = try? await generateStoryboardThumbnails(for: card)
    }

    private func resolvedDailyCardForStoryboardThumbnail(dailyCardID: UUID) -> GeneratedDailyCardDraft? {
        if let dailyCard = dayBriefGeneratedCards.values.first(where: { $0.id == dailyCardID }) {
            return dailyCard
        }
        return latestGenerationSummary?.dailyCards.first(where: { $0.id == dailyCardID })
    }

    func applyStoryboardThumbnailAssets(
        _ assets: [StoryboardThumbnailAsset],
        toDailyCardID dailyCardID: UUID
    ) {
        do {
            try dayStore.updateThumbnails(assets, revisionID: dailyCardID)
            saveTodaySnapshot(source: "storyboard-thumbnail-apply")
        } catch { lastRepositoryError = error.localizedDescription }
    }

    private func logGeneration(_ message: String) {
        let line = "[ContentHelperGeneration] \(ISO8601DateFormatter().string(from: Date())) \(message)"
        print(line)
        GenerationLogFile.append(line)
    }

    private static func hasMissingStoryboardThumbnails(for card: GeneratedDailyCardDraft) -> Bool {
        let rows = GeneratedStoryboardBreakdown.rows(for: card)
        return rows.contains { $0.thumbnailURL == nil }
    }

    @discardableResult
    func updateWeeklyDayStateImmediately(dayID: UUID, state: WeeklyDayState) async -> Bool {
        guard !weeklyPlan.isSoftLocked,
              let dayIndex = weeklyPlan.days.firstIndex(where: { $0.id == dayID }),
              !weeklyPlan.days[dayIndex].isSoftLocked
        else {
            return false
        }

        let day = weeklyPlan.days[dayIndex]
        guard let dailyCardID = resolvedDailyCardID(for: day) else {
            lastRepositoryError = "Review state could not be saved for this day."
            return false
        }

        let previousState = weeklyPlan.days[dayIndex].state
        weeklyPlan.days[dayIndex].state = state
        weeklyPlan.readinessLine = weeklyPlan.computedReadinessLine

        let previousPackage = day.scheduledDate.flatMap { dayPackage(for: $0) }
        if var package = previousPackage {
            package.status = state.generatedDraftStatus
            do { try dayStore.transition(.edit(package), on: package.scheduledDate) }
            catch { lastRepositoryError = error.localizedDescription; return false }
        }

        generationError = nil

        do {
            try await repositories.weeklyPlans.updateDailyCardReviewState(
                dailyCardID: dailyCardID,
                reviewState: state.generatedDraftStatus,
                context: context
            )
            saveTodaySnapshot(source: "day-review-state")
            lastRepositoryError = nil
            return true
        } catch {
            guard weeklyPlan.days[dayIndex].state == state else {
                return false
            }
            weeklyPlan.days[dayIndex].state = previousState
            weeklyPlan.readinessLine = weeklyPlan.computedReadinessLine
            if let previousPackage {
                try? dayStore.transition(.edit(previousPackage), on: previousPackage.scheduledDate)
            }
            lastRepositoryError = error.localizedDescription
            return false
        }
    }

    private func resolvedDailyCardID(for day: WeeklyDay) -> UUID? {
        if let scheduledDate = day.scheduledDate?.nilIfBlank,
           let draft = latestGenerationSummary,
           draft.weeklyPlanID == weeklyPlan.id,
           let card = draft.dailyCards.first(where: { $0.scheduledDate == scheduledDate }) {
            return card.id
        }

        return day.id
    }

    func selectIdeaForNextOpenDay(_ idea: WeeklyIdea) {
        Task {
            await selectIdeaForNextOpenDayImmediately(idea)
        }
    }

    func selectIdeaForNextOpenDayImmediately(_ idea: WeeklyIdea) async {
        do {
            let update = try await repositories.weeklyPlans.selectIdeaForNextOpenDay(
                idea,
                in: weeklyPlan,
                ideaBank: weeklyIdeas,
                context: context
            )
            weeklyPlan = update.weeklyPlan
            weeklyIdeas = update.ideaBank
            lastActionMessage = "Idea added to the next open day."
            lastRepositoryError = nil
        } catch {
            lastRepositoryError = error.localizedDescription
        }
    }

    func updateWeeklySetupSections(_ sections: [WeeklySetupSection]) {
        Task {
            await updateWeeklySetupSectionsImmediately(sections)
        }
    }

    func updateWeeklyBrief(_ text: String) {
        Task {
            await updateWeeklyBriefImmediately(text)
        }
    }

    @discardableResult
    func updateWeeklySetupSectionsImmediately(_ sections: [WeeklySetupSection]) async -> Bool {
        guard !isSavingWeeklyBrief else { return false }

        isSavingWeeklyBrief = true
        defer { isSavingWeeklyBrief = false }

        do {
            weeklyPlan = try await repositories.weeklyPlans.updateWeeklySetupSections(
                sections,
                in: weeklyPlan,
                context: context
            )
            weeklyBriefEditError = nil
            lastRepositoryError = nil
            lastActionMessage = "Weekly brief saved."

            return true
        } catch {
            weeklyBriefEditError = error.localizedDescription
            lastRepositoryError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateWeeklyBriefImmediately(_ text: String) async -> Bool {
        guard !isSavingWeeklyBrief else { return false }

        isSavingWeeklyBrief = true
        defer { isSavingWeeklyBrief = false }

        do {
            weeklyPlan = try await repositories.weeklyPlans.updateWeeklyBrief(
                text,
                in: weeklyPlan,
                context: context
            )
            weeklyBriefDraftText = weeklyPlan.weeklyBriefText
            weeklyBriefEditError = nil
            lastRepositoryError = nil
            lastActionMessage = "Weekly brief saved."

            return true
        } catch {
            weeklyBriefEditError = error.localizedDescription
            lastRepositoryError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateCreatorProfileImmediately(_ update: CreatorProfileUpdate) async -> Bool {
        guard !isSavingCreatorProfile else { return false }

        isSavingCreatorProfile = true
        defer { isSavingCreatorProfile = false }

        do {
            creatorProfileSummary = try await repositories.creatorProfile.updateProfile(
                update,
                context: context
            )
            creatorProfileEditError = nil
            lastRepositoryError = nil
            lastActionMessage = "Creator profile saved."
            return true
        } catch {
            creatorProfileEditError = error.localizedDescription
            lastRepositoryError = error.localizedDescription
            return false
        }
    }

    func confirmOnboardingAndPrepareFirstIdea(
        completedData: OnboardingCompletedData,
        scheduledDate: String
    ) async -> OnboardingFirstIdeaHandoffResult {
        var intent: ContentIntent
        if let pending = dayStore.outbox.first(where: { $0.kind == .firstIdea && $0.scheduledDate == scheduledDate }) {
            intent = pending
        } else {
            let record = OnboardingRecord(completedData: completedData)
            let existing = firstIdeaPackage(for: scheduledDate)
            let plan = OnboardingFirstIdeaHandoffPlanner.plan(
                scheduledDate: scheduledDate,
                record: record,
                existingPackageStatus: existing?.status,
                hasUserEditedPackage: hasUserEditedFirstIdeaPackage(for: scheduledDate),
                firstIdeaHandoffStatus: creatorProfileSummary.firstIdeaHandoff["status"],
                existingDraftIsComplete: isFirstIdeaDraftComplete(existing)
            )
            intent = ContentIntent(kind: .firstIdea, context: context, scheduledDate: scheduledDate, revisionID: plan.makeAvailableOnly ? existing?.id ?? UUID() : UUID())
            intent.completedData = completedData
            intent.priorRevisionID = existing?.id
            intent.dayBrief = plan.dayBrief
            intent.firstIdeaSkipped = !plan.shouldGenerate && !plan.makeAvailableOnly
            if plan.makeAvailableOnly { intent.generatedRevisionID = existing?.id }
            do { try enqueueIntent(intent) }
            catch { return .persistFailed }
        }
        await replayOutboxImmediately()
        if case .firstIdea(let result) = outboxResults[intent.id] { return result }
        if dayStore.outbox.first(where: { $0.id == intent.id })?.profileSaved == false { return .persistFailed }
        return .generationFailed(message: Self.firstIdeaHandoffErrorMessage(for: outboxErrors[intent.id] ?? RepositoryError.edgeFunction("generation_pending")))
    }

    private static func firstIdeaHandoffErrorMessage(for error: Error) -> String {
        if case RepositoryError.edgeFunction(let code) = error {
            if code == "ready_package_overwrite_required" {
                return "We saved your preferences, but Today already has an idea, so we left it."
            }
            let mapped = DayLifecycleErrorDisplay.message(forCode: code)
            if mapped != code, let message = mapped.nilIfBlank {
                return message
            }
        }
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if description.contains("ready_package_overwrite_required") {
            return "We saved your preferences, but Today already has an idea, so we left it."
        }
        if description.contains("_") && !description.contains(" ") {
            return "We saved your preferences but couldn't prepare your first idea."
        }
        return description.nilIfBlank ?? "We saved your preferences but couldn't prepare your first idea."
    }

    private func firstIdeaPackage(for scheduledDate: String) -> GeneratedDailyCardDraft? {
        dayBriefGeneratedCards[scheduledDate]
            ?? latestGenerationSummary?.dailyCards.first(where: { $0.scheduledDate == scheduledDate })
    }

    private func hasUserEditedFirstIdeaPackage(for scheduledDate: String) -> Bool {
        guard let package = firstIdeaPackage(for: scheduledDate) else {
            return false
        }
        return OnboardingFirstIdeaPackageEditDetector.hasUserEditedPackage(
            packageStatus: package.status,
            packageTitle: package.title,
            packageScript: package.script,
            packageCaption: package.caption,
            lastGeneratedSnapshot: nil
        )
    }

    private func isFirstIdeaDraftComplete(_ package: GeneratedDailyCardDraft?) -> Bool {
        guard let package else { return false }
        return OnboardingFirstIdeaPackageEditDetector.isCompleteGeneratedDraft(
            packageTitle: package.title,
            packageScript: package.script,
            packageCaption: package.caption
        )
    }

    func publishCurrentWeekImmediately() async {
        guard !isPublishingWeek else { return }
        guard canPublishCurrentWeek else {
            lastPublishError = "Review all seven generated days before publishing."
            return
        }

        isPublishingWeek = true
        defer { isPublishingWeek = false }

        do {
            let result = try await publishWeekWithOneTransientRetry(
                weeklyPlan,
                ideaBank: weeklyIdeas,
                generatedDraft: latestGenerationSummary,
                context: context
            )
            weeklyPlan = result.weeklyPlan
            weekCards = result.weekCards
            if let draft = latestGenerationSummary, draft.weeklyPlanID == result.weeklyPlan.id {
                latestGenerationSummary = draft.markedPublished
                }
            if let todayCard = result.todayCard {
                self.todayCard = todayCard
            }
            lastPublishSummary = result.summary
            lastActionMessage = "Week published. Creator Today is updated."
            lastRepositoryError = nil
            lastPublishError = nil
            await refreshPublishedContentAfterPublishImmediately()
            saveTodaySnapshot(source: "week-publish")
            await scheduleTodayNotificationIfNeededImmediately()
        } catch {
            lastPublishError = error.localizedDescription
        }
    }

    @discardableResult
    func makeDayAvailable(scheduledDate: String) async throws -> Bool {
        guard !isMakingDayAvailable else { throw RepositoryError.edgeFunction("make_day_available_already_running") }
        isMakingDayAvailable = true
        lastMakeDayAvailableError = nil
        defer { isMakingDayAvailable = false }
        do {
            let intent = try packageIntent(on: scheduledDate, action: .makeReady)
            try enqueueIntent(intent)
            await replayOutboxImmediately()
            guard case .available = outboxResults[intent.id] else { throw replayError(for: intent) }
            lastActionMessage = scheduledDate == currentTodayDateString ? "Ready for Today." : "Ready package saved for \(SupabaseDateFormatting.displayDate(for: scheduledDate))."
            return scheduledDate == currentTodayDateString
        } catch {
            lastMakeDayAvailableError = DayAvailabilityErrorDisplay.message(for: error)
            throw error
        }
    }

    @discardableResult
    func unpublishDay(scheduledDate: String) async throws -> DayUnpublishResult {
        guard !isUnpublishingDay else { throw RepositoryError.edgeFunction("unpublish_day_already_running") }
        isUnpublishingDay = true
        lastUnpublishDayError = nil
        defer { isUnpublishingDay = false }
        do {
            let intent = try packageIntent(on: scheduledDate, action: .returnToDraft)
            try enqueueIntent(intent)
            await replayOutboxImmediately()
            guard case .unpublished(let result) = outboxResults[intent.id] else { throw replayError(for: intent) }
            lastActionMessage = "Unpublished — back to draft."
            return result
        } catch {
            lastUnpublishDayError = DayLifecycleErrorDisplay.message(for: error)
            throw error
        }
    }

    @discardableResult
    func updateReadyDayPackage(scheduledDate: String, package: ReadyDayPackageUpdate) async throws -> DayPackageUpdateResult {
        guard !isUpdatingReadyDayPackage else { throw RepositoryError.edgeFunction("update_ready_day_package_already_running") }
        isUpdatingReadyDayPackage = true
        lastReadyDayPackageEditError = nil
        defer { isUpdatingReadyDayPackage = false }
        do {
            try package.validate()
            var intent = try packageIntent(on: scheduledDate, action: .update)
            intent.package = package.owningShotLines(in: dayStore.day(for: scheduledDate)?.revision?.content)
            try enqueueIntent(intent)
            await replayOutboxImmediately()
            guard case .package(let result) = outboxResults[intent.id] else { throw replayError(for: intent) }
            lastActionMessage = "Ready package updated."
            return result
        } catch {
            lastReadyDayPackageEditError = DayLifecycleErrorDisplay.message(for: error)
            throw error
        }
    }

    private func publishWeekWithOneTransientRetry(
        _ plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        generatedDraft: GeneratedWeekDraft?,
        context: WorkspaceContext
    ) async throws -> WeeklyPublishResult {
        let effectiveDraft = generatedDraft?.weeklyPlanID == plan.id ? generatedDraft : nil
        do {
            return try await repositories.weeklyPlans.publishWeek(
                plan,
                ideaBank: ideaBank,
                generatedDraft: effectiveDraft,
                context: context
            )
        } catch {
            guard SupabaseGenerationRetryPolicy.isTransientPollingError(error) else {
                throw error
            }
            return try await repositories.weeklyPlans.publishWeek(
                plan,
                ideaBank: ideaBank,
                generatedDraft: effectiveDraft,
                context: context
            )
        }
    }

    func reconcileGeneratedDayCardFromCurrentWeeklyContent(
        scheduledDate: String,
        suppressRepositoryErrorOnFailure: Bool = false
    ) async {
        let version = dayStore.changeVersion
        do {
            let content = try await repositories.weeklyPlans.currentWeeklyContent(for: context)
            guard let card = content.generatedDraft?.dailyCards.first(where: { $0.scheduledDate == scheduledDate }) else { return }
            try dayStore.receive(card, readVersion: version)
            saveTodaySnapshot(source: "generation-reconciled")
        } catch {
            if !suppressRepositoryErrorOnFailure { lastRepositoryError = error.localizedDescription }
        }
    }

    func refreshFromRepositories() {
        Task {
            await refreshFromRepositoriesImmediately()
        }
    }

    func checkRuntimeHealthImmediately() async {
        guard isLiveSupabaseRuntime else {
            supabaseHealthStatus = .sample
            geminiHealthStatus = .sample
            lastRuntimeHealthError = nil
            lastRuntimeHealthCheckedAt = Date()
            return
        }

        isCheckingRuntimeHealth = true
        supabaseHealthStatus = .checking
        geminiHealthStatus = .checking
        defer { isCheckingRuntimeHealth = false }

        do {
            let report = try await repositories.runtimeHealth.checkHealth(for: context)
            supabaseHealthStatus = report.supabaseOK ? .live : .down(report.supabaseDetail)
            geminiHealthStatus = report.geminiOK ? .live : .down(report.geminiDetail)
            lastRuntimeHealthCheckedAt = report.checkedAt
            lastRuntimeHealthError = nil
        } catch {
            supabaseHealthStatus = .down(error.localizedDescription)
            geminiHealthStatus = .down(error.localizedDescription)
            lastRuntimeHealthCheckedAt = Date()
            lastRuntimeHealthError = error.localizedDescription
        }
    }

    func previewReferenceImport(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String? = nil
    ) {
        Task {
            await previewReferenceImportImmediately(
                rawText: rawText,
                inputType: inputType,
                filename: filename
            )
        }
    }

    @discardableResult
    func previewReferenceImportImmediately(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String? = nil
    ) async -> ReferenceImportPreview? {
        guard !isPreviewingReferenceImport else {
            return referenceImportPreview
        }

        isPreviewingReferenceImport = true
        defer { isPreviewingReferenceImport = false }

        do {
            // Timeout bound lives inside SupabaseReferenceImportRepository so an
            // unreachable/slow Instagram probe never hangs either flow.
            let preview = try await repositories.referenceImport.previewImport(
                rawText: rawText,
                inputType: inputType,
                filename: filename,
                context: context
            )
            referenceImportPreview = preview
            referenceImportConfirmResult = nil
            referenceImportToast = nil
            lastReferenceImportError = nil
            return preview
        } catch is PreviewImportTimeoutError {
            lastReferenceImportError = "Couldn't verify — add it anyway."
            referenceImportToast = nil
            return nil
        } catch {
            lastReferenceImportError = ReferenceImportErrorDisplay.message(for: error)
            referenceImportToast = nil
            return nil
        }
    }

    func verifyInstagramProfileImmediately(_ rawHandle: String) async -> OnboardingProfileVerificationResult {
        await AppServicesOnboardingProfileVerifier(services: self).verify(handle: rawHandle)
    }

    func confirmReferenceImport(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String? = nil,
        previewChecksum: String
    ) {
        Task {
            await confirmReferenceImportImmediately(
                rawText: rawText,
                inputType: inputType,
                filename: filename,
                previewChecksum: previewChecksum
            )
        }
    }

    @discardableResult
    func confirmReferenceImportImmediately(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String? = nil,
        previewChecksum: String
    ) async -> ReferenceImportConfirmResult? {
        guard !isConfirmingReferenceImport else {
            return referenceImportConfirmResult
        }

        isConfirmingReferenceImport = true
        defer { isConfirmingReferenceImport = false }

        do {
            let result = try await repositories.referenceImport.confirmImport(
                rawText: rawText,
                inputType: inputType,
                filename: filename,
                previewChecksum: previewChecksum,
                context: context
            )
            referenceImportConfirmResult = result
            referenceImportToast = result.toast
            lastActionMessage = result.toast
            lastReferenceImportError = nil
            await refreshIntelligenceHomeImmediately()
            return result
        } catch {
            lastReferenceImportError = ReferenceImportErrorDisplay.message(for: error)
            referenceImportToast = nil
            return nil
        }
    }

    func reviewReferenceItem(_ request: ReferenceReviewRequest) {
        Task {
            await reviewReferenceItemImmediately(request)
        }
    }

    @discardableResult
    func reviewReferenceItemImmediately(_ request: ReferenceReviewRequest) async -> ReferenceReviewResult? {
        guard !isReviewingReference else {
            return referenceReviewResult
        }

        isReviewingReference = true
        defer { isReviewingReference = false }

        do {
            let result = try await repositories.referenceImport.reviewItem(
                request,
                context: context
            )
            referenceReviewResult = result
            referenceImportToast = result.toast
            lastActionMessage = result.toast
            lastReferenceImportError = nil
            await refreshIntelligenceHomeImmediately()
            return result
        } catch {
            lastReferenceImportError = ReferenceImportErrorDisplay.message(for: error)
            referenceImportToast = nil
            return nil
        }
    }

    @discardableResult
    func loadTodayFromCache() -> Bool {
        do {
            guard let snapshot = try todayCache.loadSnapshot(for: context) else {
                return false
            }
            apply(snapshot: snapshot)
            guard let day = dayStore.day(for: currentTodayDateString) else { return false }
            return day.lifecycle != .unavailable
        } catch {
            lastRepositoryError = error.localizedDescription
            return false
        }
    }

    func refreshFromRepositoriesImmediately() async {
        isRefreshingRepository = true
        lastRepositoryRefreshAttemptAt = Date()
        var refreshError: Error?
        var isMissingPublishedTodayCard = false
        defer { isRefreshingRepository = false }

        do {
            creatorProfileSummary = try await repositories.creatorProfile.activeProfileSummary(for: context)
            creatorOnboardingPresentation = CreatorOnboardingPresentationMapper.presentation(
                from: creatorProfileSummary,
                loadFailed: false,
                previousPresentation: creatorOnboardingPresentation
            )
        } catch {
            refreshError = refreshError ?? error
            creatorOnboardingPresentation = CreatorOnboardingPresentationMapper.presentation(
                from: creatorProfileSummary,
                loadFailed: true,
                previousPresentation: creatorOnboardingPresentation
            )
        }

        let dayReadVersion = dayStore.changeVersion
        var usedDaySnapshot = false
        do {
            if let rows = try await repositories.today.creatorDays(for: context) {
                try dayStore.reconcile(rows, today: currentTodayDateString, readVersion: dayReadVersion)
                usedDaySnapshot = true
            } else {
                do {
                    let card = try await repositories.today.todayCard(for: context)
                    try dayStore.receivePublished(card, readVersion: dayReadVersion)
                } catch RepositoryError.noPublishedTodayCard(let date) {
                    isMissingPublishedTodayCard = true
                    if !dayStore.changed(date, since: dayReadVersion) { applyMissingPublishedTodayCardState(date: date) }
                }
                let weekReadVersion = dayStore.changeVersion
                let cards = try await repositories.today.weekCards(for: context)
                for card in cards { try dayStore.receivePublished(card, readVersion: weekReadVersion) }
            }
            isLoadingToday = false
            saveTodaySnapshot(source: "repository-refresh")
            await scheduleTodayNotificationIfNeededImmediately()
        } catch {
            refreshError = error
            if dayStore.day(for: currentTodayDateString) == nil { _ = loadTodayFromCache() }
            todayContentState = .unavailable
            lastRepositoryError = error.localizedDescription
        }

        do {
            archiveEntries = try await repositories.archive.entries(for: context)
        } catch {
            refreshError = refreshError ?? error
        }

        let weeklyReadVersion = dayStore.changeVersion
        do {
            let weeklyContent = try await repositories.weeklyPlans.currentWeeklyContent(for: context)
            weeklyPlan = weeklyContent.workingPlan ?? weeklyContent.publishedPlan
            weeklyBriefDraftText = weeklyPlan.weeklyBriefText
            setGenerationSummary(weeklyContent.generatedDraft, importingCards: !usedDaySnapshot, readVersion: weeklyReadVersion)
            weeklyIdeas = weeklyContent.ideaBank
        } catch {
            refreshError = refreshError ?? error
        }

        for package in await repositories.dailyGeneration.persistedDayPackages(context: context)
        where dayBriefGeneratedCards[package.scheduledDate] == nil {
            try? dayStore.receive(package)
        }

        do {
            intelligenceHome = try await repositories.intelligence.home(for: context)
        } catch {
            refreshError = refreshError ?? error
        }

        await replayOutboxImmediately()

        if refreshError == nil {
            lastRepositoryRefreshAt = Date()
            lastRepositoryRefreshSucceededAt = Date()
            lastRepositoryRefreshError = nil
            if !isMissingPublishedTodayCard {
                todayContentState = .ready
            }
            hydrateTodayStoryboardThumbnailsFromPlanPackage()
        } else {
            lastRepositoryRefreshError = refreshError?.localizedDescription
        }

#if DEBUG
        applyDebugWeekStartOverrideIfNeeded()
#endif

        normalizeManagerWeekStartIfStale()
        saveTodaySnapshot(source: "repository-refresh-complete")
        await checkRuntimeHealthImmediately()
    }

    private func applyMissingPublishedTodayCardState(date: String) {
        todayContentState = .missingPublishedCard(date: date)
        lastNotificationSchedule = nil
        lastNotificationError = nil
    }

    /// Re-fetches canonical published content immediately after publish so the
    /// manager week state and creator Today state come from the same source of truth.
    /// This prevents local reviewed-draft state from diverging from published rows.
    func refreshPublishedContentAfterPublishImmediately(skipTodayCard: Bool = false) async {
        let version = dayStore.changeVersion
        do {
            if let rows = try await repositories.today.creatorDays(for: context) {
                try dayStore.reconcile(rows, today: currentTodayDateString, readVersion: version)
            } else {
                if !skipTodayCard {
                    do {
                        let card = try await repositories.today.todayCard(for: context)
                        try dayStore.receivePublished(card, readVersion: version)
                    } catch RepositoryError.noPublishedTodayCard(let date) {
                        if !dayStore.changed(date, since: version) { applyMissingPublishedTodayCardState(date: date) }
                    }
                }
                for card in try await repositories.today.weekCards(for: context) {
                    try dayStore.receivePublished(card, readVersion: version)
                }
            }
            weeklyPlan = try await repositories.weeklyPlans.currentPublishedPlan(for: context)
            weeklyBriefDraftText = weeklyPlan.weeklyBriefText
            lastRepositoryRefreshError = nil
            saveTodaySnapshot(source: "published-refresh")
        } catch { lastRepositoryRefreshError = error.localizedDescription }
    }

    func refreshIntelligenceHomeImmediately() async {
        do {
            intelligenceHome = try await repositories.intelligence.home(for: context)
            lastRepositoryError = nil
        } catch {
            lastRepositoryError = error.localizedDescription
        }
    }

    func scheduleTodayNotificationIfNeededImmediately() async {
        guard case .ready = todayContentState else {
            await cancelTodayNotification()
            return
        }
        do {
            lastNotificationSchedule = try await notifications.scheduleTodayReminder(
                for: todayCard,
                context: context
            )
            lastNotificationError = nil
        } catch {
            lastNotificationSchedule = nil
            lastNotificationError = error.localizedDescription
        }
    }

    func loadTesterAccess() {
        Task {
            await loadTesterAccessImmediately()
        }
    }

    func loadTesterAccessImmediately() async {
        guard canManageTesterAccess else {
            testers = []
            testerAccessError = nil
            return
        }

        isLoadingTesters = true
        defer { isLoadingTesters = false }

        do {
            testers = try await repositories.testerAccess.listTesters(context: context)
            testerAccessError = nil
        } catch {
            testerAccessError = error.localizedDescription
        }
    }

    func inviteTester(email: String, displayName: String?) {
        Task {
            await inviteTesterImmediately(email: email, displayName: displayName)
        }
    }

    func inviteTesterImmediately(email: String, displayName: String?) async {
        guard canManageTesterAccess else {
            testerAccessError = "owner_role_required"
            return
        }

        isLoadingTesters = true
        defer { isLoadingTesters = false }

        do {
            let tester = try await repositories.testerAccess.inviteTester(
                email: email,
                displayName: displayName,
                context: context
            )
            testers.removeAll { $0.id == tester.id || $0.email == tester.email }
            testers.append(tester)
            testers.sort { $0.email < $1.email }
            testerAccessMessage = "Invite sent to (tester.email)."
            testerAccessError = nil
        } catch {
            testerAccessError = error.localizedDescription
        }
    }

    func resendTesterOTP(email: String) {
        Task {
            await resendTesterOTPImmediately(email: email)
        }
    }

    func resendTesterOTPImmediately(email: String) async {
        guard canManageTesterAccess else {
            testerAccessError = "owner_role_required"
            return
        }

        isLoadingTesters = true
        defer { isLoadingTesters = false }

        do {
            let tester = try await repositories.testerAccess.resendTesterOTP(email: email, context: context)
            testerAccessMessage = "New code sent to \(tester.email)."
            testerAccessError = nil
        } catch {
            testerAccessError = error.localizedDescription
        }
    }

    func revokeTester(memberID: UUID) {
        Task {
            await revokeTesterImmediately(memberID: memberID)
        }
    }

    func revokeTesterImmediately(memberID: UUID) async {
        guard canManageTesterAccess else {
            testerAccessError = "owner_role_required"
            return
        }

        isLoadingTesters = true
        defer { isLoadingTesters = false }

        do {
            let tester = try await repositories.testerAccess.revokeTester(
                memberID: memberID,
                context: context
            )
            testers.removeAll { $0.id == memberID }
            testers.append(tester)
            testers.sort { $0.email < $1.email }
            testerAccessMessage = "Access revoked for (tester.email)."
            testerAccessError = nil
        } catch {
            testerAccessError = error.localizedDescription
        }
    }

    private func apply(snapshot: CachedTodaySnapshot) {
        dayStore.restore(snapshot.migratedStore(for: context))
        for intent in dayStore.outbox {
            if let card = intent.cardSnapshot { try? dayStore.retainPendingCard(card) }
        }
    }

    private func saveTodaySnapshot(source: String) {
        do { try persistDaySnapshot(source: source) }
        catch { lastRepositoryError = error.localizedDescription }
    }

    private func persistDaySnapshot(source: String) throws {
        try todayCache.saveSnapshot(CachedTodaySnapshot(dayStore: dayStore.snapshot, cachedAt: Date(), source: source), for: context)
    }

    private func migrateLegacyOutbox() {
        let defaults = isLiveSupabaseRuntime ? UserDefaults.standard : DebugLaunchConfiguration.fixtureDefaults
        let firstKey = "ch-pending-first-idea"
        let generationKey = "ch-accepted-day-generations"
        var changed = false
        if let data = defaults.data(forKey: firstKey),
           let legacy = try? JSONDecoder().decode(LegacyFirstIdeaMigration.self, from: data), legacy.creatorID == context.creatorID {
            if !dayStore.outbox.contains(where: { $0.kind == .firstIdea && $0.scheduledDate == legacy.scheduledDate }) {
                var intent = ContentIntent(kind: .firstIdea, context: context, scheduledDate: legacy.scheduledDate)
                intent.completedData = legacy.completedData
                intent.dayBrief = OnboardingFirstIdeaBriefBuilder.buildDayBrief(from: OnboardingRecord(completedData: legacy.completedData))
                if let existing = dayPackage(for: legacy.scheduledDate), isFirstIdeaDraftComplete(existing) {
                    intent.generatedRevisionID = existing.id
                    intent.firstIdeaSkipped = DayPackageLifecycleStatus.requiresOverwriteConfirmation(existing.status)
                }
                dayStore.enqueue(intent)
            }
            changed = true
        }
        let runs = defaults.data(forKey: generationKey).flatMap { try? JSONDecoder().decode([LegacyGenerationMigration].self, from: $0) } ?? []
        for run in runs where run.creatorID == context.creatorID {
            if let pending = dayStore.outbox.first(where: { $0.isGeneration && $0.scheduledDate == run.scheduledDate }) {
                if pending.generationID == nil {
                    var pending = pending
                    pending.generationID = run.generationID
                    dayStore.updateIntent(pending)
                }
            } else {
                var intent = ContentIntent(kind: .generate, context: context, scheduledDate: run.scheduledDate)
                intent.generationID = run.generationID
                intent.createdAt = run.acceptedAt
                dayStore.enqueue(intent)
            }
            changed = true
        }
        guard changed else { return }
        do {
            try persistDaySnapshot(source: "outbox-migrated")
            if let data = defaults.data(forKey: firstKey), let legacy = try? JSONDecoder().decode(LegacyFirstIdeaMigration.self, from: data), legacy.creatorID == context.creatorID {
                defaults.removeObject(forKey: firstKey)
            }
            if !runs.isEmpty, runs.allSatisfy({ $0.creatorID == context.creatorID }) { defaults.removeObject(forKey: generationKey) }
        } catch { lastRepositoryError = error.localizedDescription }
    }

    private func enqueueIntent(_ intent: ContentIntent) throws {
        if dayStore.outbox.contains(where: { $0.id == intent.id }) { return }
        dayStore.enqueue(intent)
        do { try persistDaySnapshot(source: "outbox-enqueued") }
        catch { dayStore.finishIntent(intent.id); throw error }
    }

    private func enqueueGeneration(_ requested: ContentIntent) throws {
        var intent = requested
        intent.priorRevisionID = dayPackage(for: intent.scheduledDate)?.id
        guard !dayStore.outbox.contains(where: { $0.isGeneration && $0.scheduledDate == intent.scheduledDate }) else {
            throw RepositoryError.edgeFunction("generation_already_running")
        }
        if case .generating = dayStore.day(for: intent.scheduledDate)?.lifecycle { throw RepositoryError.edgeFunction("generation_already_running") }
        try enqueueIntent(intent)
        try dayStore.transition(.generate(DayGenerationRun(requestID: intent.requestedRevisionID, generationID: nil), replacing: dayPackage(for: intent.scheduledDate) != nil), on: intent.scheduledDate)
        try persistDaySnapshot(source: "outbox-generation")
    }

    private func packageIntent(on date: String, action: PackageIntentAction) throws -> ContentIntent {
        guard let day = dayStore.day(for: date), let revision = day.revision else { throw DayTransitionError.mismatchedRevision }
        if let existing = dayStore.outbox.first(where: { $0.kind == .editPackage && $0.revisionID == revision.id && $0.packageAction == action && action != .update }) { return existing }
        var intent = ContentIntent(kind: .editPackage, context: context, scheduledDate: date, revisionID: revision.id)
        intent.packageAction = action
        intent.expectedVersion = day.serverUpdatedAt
        return intent
    }

    private func replayError(for intent: ContentIntent) -> Error {
        outboxErrors[intent.id] ?? RepositoryError.edgeFunction("Your request is saved. It will retry when the connection returns.")
    }

    private func generatedResult(for intent: ContentIntent) throws -> GeneratedDailyCardDraft {
        if case .generated(let card) = outboxResults[intent.id] { return card }
        throw replayError(for: intent)
    }

    func replayOutboxImmediately() async {
        migrateLegacyOutbox()
        if let task = outboxReplayTask {
            outboxNeedsReplay = true
            await task.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                self.outboxNeedsReplay = false
                await self.drainOutbox()
            } while self.outboxNeedsReplay
        }
        outboxReplayTask = task
        await task.value
        outboxReplayTask = nil
    }

    private func drainOutbox() async {
        var attempted: Set<String> = []
        var blocked: Set<UUID> = []
        while let intent = dayStore.outbox.first(where: { candidate in
            !attempted.contains(candidate.id) && !blocked.contains(candidate.revisionID)
                && (candidate.isGeneration || !dayStore.outbox.contains { $0.isGeneration && $0.requestedRevisionID == candidate.revisionID && $0.generatedRevisionID == nil })
        }) {
            if Task.isCancelled { return }
            attempted.insert(intent.id)
            outboxErrors[intent.id] = nil
            if intent.isGeneration { generatingDayBriefDates.insert(intent.scheduledDate) }
            do {
                let result = try await replayIntent(intent)
                let pending = dayStore.outbox
                dayStore.finishIntent(intent.id)
                do { try persistDaySnapshot(source: "outbox-done") }
                catch { dayStore.restoreOutbox(pending); throw error }
                outboxResults[intent.id] = result
                if intent.kind == .decide { lastTodayDecisionSyncError = nil }
                lastRepositoryError = nil
            } catch {
                outboxErrors[intent.id] = error
                let code = SupabaseFunctionErrorMapper.errorCode(from: error) ?? error.localizedDescription
                if code == "daily_card_not_found" {
                    let pending = dayStore.outbox
                    do {
                        if intent.kind == .firstIdea { try await saveFirstIdeaProfile(intent, status: .failed) }
                        dayStore.finishIntent(intent.id)
                        try persistDaySnapshot(source: "outbox-revision-removed")
                    } catch { dayStore.restoreOutbox(pending) }
                } else if case OutboxTerminalFailure.server = error {
                    let pending = dayStore.outbox
                    do {
                        if intent.kind == .firstIdea { try await saveFirstIdeaProfile(intent, status: .failed) }
                        dayStore.finishIntent(intent.id)
                        try persistDaySnapshot(source: "outbox-terminal-failure")
                    } catch { dayStore.restoreOutbox(pending) }
                } else {
                    blocked.insert(intent.revisionID)
                    if intent.isGeneration { await reconcileInterruptedGeneration(intent) }
                }
                if intent.kind == .decide { lastTodayDecisionSyncError = TodayDecisionErrorDisplay.message(for: error) }
                if intent.isGeneration { dayBriefGenerationErrors[intent.scheduledDate] = DayGenerationErrorDisplay.message(for: error) }
                if intent.kind == .firstIdea, let current = dayStore.outbox.first(where: { $0.id == intent.id }), current.profileSaved {
                    try? await saveFirstIdeaProfile(current, status: .failed)
                }
            }
            if intent.isGeneration { generatingDayBriefDates.remove(intent.scheduledDate) }
        }
    }

    private func reconcileInterruptedGeneration(_ intent: ContentIntent) async {
        let version = dayStore.changeVersion
        do {
            if let rows = try await repositories.today.creatorDays(for: context) {
                let matches = rows.filter { $0.scheduledDate == intent.scheduledDate }
                if !matches.isEmpty { try dayStore.reconcile(matches, today: intent.scheduledDate, readVersion: version) }
            } else if let card = try await repositories.today.weekCards(for: context).first(where: { $0.scheduledDate == intent.scheduledDate }) {
                try dayStore.receivePublished(card, readVersion: version)
            }
            try persistDaySnapshot(source: "outbox-generation-reconciled")
        } catch { lastRepositoryError = error.localizedDescription }
    }

    private func replayIntent(_ original: ContentIntent) async throws -> OutboxReplayResult {
        switch original.kind {
        case .decide:
            let entry = try await repositories.today.replayDecision(original, context: context)
            guard entry.dailyCardID == original.revisionID else { throw DayTransitionError.mismatchedRevision }
            dayStore.mergeArchive([entry], authoritative: true)
            return .decision(entry)
        case .editPackage:
            let result = try await repositories.weeklyPlans.replayPackage(original, context: context)
            try await applyPackageReply(result, intent: original)
            return result
        case .generate, .replaceDay:
            return .generated(try await replayGeneration(original))
        case .firstIdea:
            var intent = original
            if let code = intent.terminalFailureCode {
                try await saveFirstIdeaProfile(intent, status: .failed)
                throw OutboxTerminalFailure.server(code)
            }
            try await saveFirstIdeaProfile(intent, status: .preparing)
            if !intent.profileSaved {
                intent.profileSaved = true
                dayStore.updateIntent(intent)
                try persistDaySnapshot(source: "outbox-first-idea-profile")
            }
            if intent.firstIdeaSkipped {
                try await saveFirstIdeaProfile(intent, status: .skippedExistingReady)
                return .firstIdea(.skippedExistingReady)
            }
            if intent.generatedRevisionID == nil {
                let card = try await replayGeneration(intent)
                intent = dayStore.outbox.first { $0.id == intent.id } ?? intent
                intent.generatedRevisionID = card.id
                dayStore.updateIntent(intent)
                try persistDaySnapshot(source: "outbox-first-idea-draft")
            }
            guard let revisionID = intent.generatedRevisionID else { throw DayTransitionError.mismatchedRevision }
            var approval = intent
            approval.kind = .editPackage
            approval.revisionID = revisionID
            approval.packageAction = .makeReady
            approval.idempotencyKey = intent.id + ":ready"
            let result = try await repositories.weeklyPlans.replayPackage(approval, context: context)
            try await applyPackageReply(result, intent: approval)
            try persistDaySnapshot(source: "outbox-first-idea-ready")
            try await saveFirstIdeaProfile(intent, status: .completed)
            return .firstIdea(.completed(navigatedToday: intent.scheduledDate == currentTodayDateString))
        }
    }

    private func replayGeneration(_ original: ContentIntent) async throws -> GeneratedDailyCardDraft {
        var intent = original
        if intent.generatedRevisionID == nil && intent.supersededByServer != true {
            try dayStore.transition(.generate(DayGenerationRun(requestID: intent.requestedRevisionID, generationID: intent.generationID), replacing: dayPackage(for: intent.scheduledDate) != nil), on: intent.scheduledDate)
            try persistDaySnapshot(source: "outbox-generating")
        }
        while !Task.isCancelled {
            try requireAIConsent(for: .generateDay(scheduledDate: intent.scheduledDate))
            let response = try await repositories.dailyGeneration.replayGeneration(intent, context: context)
            intent = dayStore.outbox.first { $0.id == intent.id } ?? intent
            switch response {
            case .running(let generationID, let delay):
                intent.generationID = generationID
                dayStore.updateIntent(intent)
                if intent.supersededByServer != true {
                    try dayStore.transition(.generate(DayGenerationRun(requestID: intent.requestedRevisionID, generationID: generationID), replacing: true), on: intent.scheduledDate)
                }
                try persistDaySnapshot(source: "outbox-generation-accepted")
                try await Task.sleep(nanoseconds: UInt64(max(1, min(delay, 15))) * 1_000_000_000)
            case .completed(let result):
                guard result.targetScheduledDate == intent.scheduledDate, result.dailyCard.scheduledDate == intent.scheduledDate else { throw DayTransitionError.mismatchedRevision }
                let card: GeneratedDailyCardDraft
                if intent.supersededByServer == true {
                    if dayStore.day(for: intent.scheduledDate)?.revision?.id != result.dailyCard.id {
                        try dayStore.transition(.retain(result.dailyCard, nil), on: intent.scheduledDate)
                    }
                    card = result.dailyCard
                } else if let existing = dayStore.day(for: intent.scheduledDate)?.revision, existing.id == result.dailyCard.id {
                    try dayStore.receive(existing.content, completion: existing.decision?.completionState, authoritativeDecision: true)
                    card = existing.content
                } else {
                    card = try applyDayGenerationResult(result, scheduledDate: intent.scheduledDate)
                }
                intent.generatedRevisionID = card.id
                dayStore.updateIntent(intent)
                dayStore.bindRevision(requestedID: intent.requestedRevisionID, to: card.id)
                try persistDaySnapshot(source: "outbox-generation-completed")
                return card
            case .failed(let code):
                intent.terminalFailureCode = code
                dayStore.updateIntent(intent)
                if intent.supersededByServer != true, case .generating(let run) = dayStore.day(for: intent.scheduledDate)?.lifecycle,
                   run.requestID == intent.requestedRevisionID || run.generationID == intent.generationID && intent.generationID != nil {
                    try dayStore.transition(.generationFailed, on: intent.scheduledDate)
                }
                try persistDaySnapshot(source: "outbox-generation-failed")
                throw OutboxTerminalFailure.server(code)
            }
        }
        throw CancellationError()
    }

    private func applyPackageReply(_ result: OutboxReplayResult, intent: ContentIntent) async throws {
        let current = dayStore.day(for: intent.scheduledDate)?.revision?.id == intent.revisionID
        switch result {
        case .available(let reply):
            guard reply.dailyCardID == intent.revisionID, reply.scheduledDate == intent.scheduledDate else { throw DayTransitionError.mismatchedRevision }
            if current, var content = dayStore.day(for: intent.scheduledDate)?.revision?.content {
                content.status = reply.status
                try dayStore.receive(content, completion: CompletionState(supabaseStatus: reply.status), authoritativeDecision: true)
            }
            if current, intent.scheduledDate == currentTodayDateString { await scheduleTodayNotificationIfNeededImmediately() }
        case .unpublished(let reply):
            guard reply.dailyCardID == intent.revisionID, reply.scheduledDate == intent.scheduledDate else { throw DayTransitionError.mismatchedRevision }
            if current, dayStore.day(for: intent.scheduledDate)?.lifecycle.exposesReadyPackage == true { try dayStore.transition(.returnToDraft, on: intent.scheduledDate) }
            if current, intent.scheduledDate == currentTodayDateString { await cancelTodayNotification() }
        case .package(let reply):
            guard reply.dailyCardID == intent.revisionID, reply.scheduledDate == intent.scheduledDate else { throw DayTransitionError.mismatchedRevision }
            if current, let patch = intent.package { try dayStore.updatePackage(on: intent.scheduledDate, revisionID: reply.dailyCardID, patch: patch, title: reply.title, caption: reply.caption) }
        default: throw DayTransitionError.mismatchedRevision
        }
    }

    private func saveFirstIdeaProfile(_ intent: ContentIntent, status: OnboardingFirstIdeaHandoffStatus) async throws {
        guard let data = intent.completedData else { throw DayTransitionError.incompletePackage }
        let brief = intent.dayBrief ?? ""
        var update = OnboardingProfileMapper.profileUpdate(
            from: OnboardingRecord(completedData: data),
            onboardingState: .established,
            onboardingCompletedAt: ISO8601DateFormatter().string(from: intent.createdAt),
            firstIdeaHandoff: OnboardingFirstIdeaHandoffPlanner.firstIdeaHandoffPayload(
                scheduledDate: intent.scheduledDate,
                status: status,
                briefFingerprint: OnboardingFirstIdeaBriefBuilder.fingerprint(for: brief)
            )
        )
        if intent.profileSaved {
            update = CreatorProfileUpdate(firstIdeaHandoff: update.firstIdeaHandoff)
        }
        guard await updateCreatorProfileImmediately(update) else {
            throw RepositoryError.edgeFunction(creatorProfileEditError ?? "creator_profile_save_failed")
        }
    }

    private func makeArchiveEntry(
        for card: DailyCard,
        decision: DailyDecision
    ) -> ArchiveEntry {
        let archiveDate = card.scheduledDate ?? SupabaseDateFormatting.todayDateString()
        var entry = ArchiveEntry(
            dailyCardID: card.id,
            day: SupabaseDateFormatting.weekdayAbbreviation(for: archiveDate),
            date: SupabaseDateFormatting.shortDate(for: archiveDate),
            cardTitle: card.title,
            decision: decision.completionState,
            outputLine: decision.outputLine,
            hasPostThumbnail: decision.hasPostThumbnail
        )
        entry.captionSnapshot = card.caption
        entry.scheduledDate = archiveDate
        entry.decisionAt = ISO8601DateFormatter().string(from: Date())
        return entry
    }

    private func cancelTodayNotification() async {
        await notifications.cancelTodayReminder(for: context)
        lastNotificationSchedule = nil
    }
}

private enum TodayDecisionErrorDisplay {
    private static let userFacingMessages = [
        "daily_card_not_found": "Today's package could not be found. Refresh Plan, then try again.",
        "complete_today_failed": "Could not save today's decision. Try again.",
        "archive_upsert_failed": "Could not save today's archive entry. Try again.",
        "missing_device_token": "This device session is missing. Sign in again.",
        "invalid_device_token": "This device session has expired. Sign in again.",
        "role_not_allowed": "This session cannot save today's decision."
    ]

    static func message(for error: Error) -> String {
        let description = error.localizedDescription
        if let message = userFacingMessages[description] {
            return message
        }
        if let code = userFacingMessages.keys.first(where: { description.contains($0) }) {
            return userFacingMessages[code] ?? description
        }

        let lowered = description.lowercased()
        if lowered.contains("network connection was lost")
            || lowered.contains("timed out")
            || lowered.contains("internet connection appears to be offline")
            || lowered.contains("could not connect to the server")
        {
            return "Connection dropped briefly while saving. Your choice is kept on this device — try again."
        }

        return description
    }
}

private enum DayAvailabilityErrorDisplay {
    private static let userFacingMessages = [
        "daily_card_not_found": "No draft was found for that day. Generate a draft first.",
        "daily_card_not_draft": "That day is already a ready package.",
        "daily_card_incomplete": "That draft is incomplete. Generate again, then approve.",
        "invalid_make_day_available_payload": "Make ready could not accept that request. Refresh and try again.",
        "make_day_available_failed": "Could not approve this day. Try again.",
        "make_day_available_already_running": "Approve is already running. Wait a moment.",
        "role_not_allowed": "This session cannot make a day available.",
        "creator_not_found": "This creator workspace is no longer available. Refresh and try again.",
        "missing_device_token": "This device session is missing. Sign in again.",
        "invalid_device_token": "This device session has expired. Sign in again.",
        "make_day_available_not_configured": "Approve is not configured for this runtime."
    ]

    static func message(for error: Error) -> String {
        let description = error.localizedDescription
        if let message = userFacingMessages[description] {
            return message
        }
        if let code = userFacingMessages.keys.first(where: { description.contains($0) }) {
            return userFacingMessages[code] ?? description
        }
        let lowered = description.lowercased()
        if lowered.contains("network connection was lost")
            || lowered.contains("timed out")
            || lowered.contains("internet connection appears to be offline")
            || lowered.contains("could not connect to the server")
        {
            return "Connection dropped briefly. Tap Approve again."
        }
        return description
    }
}

private enum DayLifecycleErrorDisplay {
    private static let userFacingMessages = [
        "daily_card_not_found": "No package was found for that day.",
        "daily_card_not_ready": "That day is not a ready package.",
        "daily_card_already_draft": "That day is already a draft.",
        "unpublish_day_conflict": "Could not unpublish — the day changed. Refresh and try again.",
        "invalid_unpublish_day_payload": "Unpublish could not accept that request. Refresh and try again.",
        "unpublish_day_failed": "Could not unpublish this day. Try again.",
        "unpublish_day_already_running": "Unpublish is already running. Wait a moment.",
        "unpublish_day_not_configured": "Unpublish is not configured for this runtime.",
        "invalid_update_ready_day_package_payload": "Could not save those edits. Refresh and try again.",
        "update_ready_day_package_failed": "Could not save package edits. Try again.",
        "update_ready_day_package_already_running": "Package save is already running. Wait a moment.",
        "update_ready_day_package_not_configured": "Package editing is not configured for this runtime.",
        "update_ready_day_package_conflict": "Could not save edits — the day changed. Refresh and try again.",
        "ready_package_overwrite_required": "This day already has a draft or package. Confirm Overwrite to replace it with a new draft.",
        "role_not_allowed": "This session cannot change that day package.",
        "creator_not_found": "This creator workspace is no longer available. Refresh and try again.",
        "missing_device_token": "This device session is missing. Sign in again.",
        "invalid_device_token": "This device session has expired. Sign in again."
    ]

    static func message(forCode code: String) -> String {
        userFacingMessages[code] ?? code
    }

    static func message(for error: Error) -> String {
        let description = error.localizedDescription
        if let message = userFacingMessages[description] {
            return message
        }
        if let code = userFacingMessages.keys.first(where: { description.contains($0) }) {
            return userFacingMessages[code] ?? description
        }
        return description
    }
}

/// Thrown when a reference-import call (live Instagram probe) exceeds its bound.
struct PreviewImportTimeoutError: Error, LocalizedError {
    var errorDescription: String? {
        "Couldn't reach Instagram — try again."
    }
}

private enum DayGenerationErrorDisplay {
    private static let userFacingMessages = [
        "invalid_ai_json": "The AI returned an incomplete draft. Try Generate again.",
        "invalid_generated_week": "The AI draft did not pass validation. Try Generate again.",
        "invalid_generated_day": "The generated card did not match the requested date. Try Generate again.",
        "openai_request_failed": "The AI service failed. Try Generate again.",
        "missing_openai_api_key": "AI generation is not configured in Supabase.",
        "invalid_generation_payload": "The generation request could not be accepted. Refresh and try again.",
        "generation_persist_failed": "The draft could not be saved. Try Generate again.",
        "weekly_setup_not_found": "The weekly brief could not be found. Save the brief and try again.",
        "existing_published_week_locked": "This week is already published and locked.",
        "past_generation_date_not_allowed": "You cannot generate content for a past date. Select today or a future date.",
        "generation_timeout": "Generation timed out. Wait a moment, then try Generate again.",
        "generation_cancelled": "This day’s draft stopped before it finished. You can try Generate again.",
        "generation_already_running": "A generation is already in progress for this day. Wait for it to finish, then try again.",
        "creator_voice_required": "Set up your creator voice first — or defer voice in You.",
        "ai_consent_required": AIConsentCopy.blockedMessage,
        "accepted_run_not_found": "Generation status is still syncing. Refresh and try Generate again.",
        "cancelled": "This day’s draft stopped before it finished. You can try Generate again."
    ]

    private static let stableCodes = [
        "missing_device_token",
        "invalid_device_token",
        "role_not_allowed",
        "creator_not_found",
        "invalid_generation_payload",
        "missing_openai_api_key",
        "openai_request_failed",
        "invalid_ai_json",
        "invalid_generated_week",
        "invalid_generated_day",
        "generation_persist_failed",
        "weekly_setup_not_found",
        "existing_published_week_locked",
        "past_generation_date_not_allowed",
        "generation_timeout",
        "generation_cancelled",
        "generation_already_running",
        "creator_voice_required",
        "ai_consent_required",
        "accepted_run_not_found",
        "cancelled"
    ]

    static func message(for error: Error) -> String {
        if error is CancellationError {
            return message(forCode: "generation_cancelled")
        }
        let description = error.localizedDescription
        if description.contains("generation_persist_failed:") {
            return "The draft could not be saved (\(description))."
        }
        if let message = userFacingMessages[description] {
            return message
        }

        if let code = stableCodes.first(where: { description.localizedCaseInsensitiveContains($0) }) {
            return userFacingMessages[code] ?? code
        }

        let lowered = description.lowercased()
        if lowered.contains("cancel") {
            return message(forCode: "generation_cancelled")
        }

        return description
    }

    static func message(forCode code: String) -> String {
        userFacingMessages[code] ?? code
    }
}

private enum ReferenceImportErrorDisplay {
    private static let userFacingMessages = [
        "missing_raw_text": "Paste at least one handle, reel link, audio link, or CSV row before previewing.",
        "row_limit_exceeded": "This import is too large. Split it into smaller batches and try again.",
        "checksum_mismatch": "The import changed. Preview it again before saving.",
        "story_urls_not_allowed": "Story URLs cannot be used as references. Add a reel, post, audio link, or account instead.",
        "missing_reference_url": "Add a reference URL before saving this review item.",
        "invalid_account_handle": "Enter a valid Instagram handle for this account reference.",
        "invalid_review_payload": "This review item is missing required details. Refresh and try again.",
        "invalid_review_action": "This review action is not supported. Refresh and try again.",
        "review_item_not_found": "This review item is no longer available. Refresh References.",
        "creator_not_found": "This creator workspace is no longer available. Refresh and try again.",
        "role_not_allowed": "This action is not available for your account role.",
        "missing_device_token": "This device session is missing. Sign in again.",
        "invalid_device_token": "This device session has expired. Sign in again.",
        "import_failed_nothing_saved": "The import could not be saved. Try previewing again.",
        "duplicate_lookup_failed": "Duplicate checking failed. Try previewing again.",
        "import_parse_failed": "The import could not be parsed. Check the pasted rows or CSV format.",
        "invalid_input_type": "Choose paste or CSV import and try again.",
        "invalid_mode": "Choose preview or import and try again."
    ]

    private static let stableCodes = Array(userFacingMessages.keys)

    static func message(for error: Error) -> String {
        let description = error.localizedDescription
        if let message = userFacingMessages[description] {
            return message
        }

        if let code = stableCodes.first(where: { description.contains($0) }) {
            return userFacingMessages[code] ?? code
        }

        return description
    }
}
