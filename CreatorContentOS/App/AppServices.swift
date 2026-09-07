import Foundation
import Observation

typealias TodayDateProvider = @Sendable () -> String

enum TodayContentState: Equatable, Hashable, Sendable {
    case loading
    case ready
    case missingPublishedCard(date: String)
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

    var todayCard: DailyCard
    var shotSceneIDs: Set<UUID>
    var archiveEntries: [ArchiveEntry]
    var weeklyPlan: WeeklyPlan
    var weeklyBriefDraftText: String
    var weeklyIdeas: [WeeklyIdea]
    var intelligenceHome: IntelligenceHome
    var creatorProfileSummary: CreatorProfileSummary
    var creatorOnboardingPresentation: CreatorOnboardingPresentation = .new
    var weekCards: [DailyCard]
    var lastRepositoryError: String?
    var lastTodayDecisionSyncError: String?
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
    var todayContentState: TodayContentState
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
    var dayBriefGeneratedCards: [String: GeneratedDailyCardDraft] = [:]
    /// Cached Plan empty-day idea one-liners keyed by `yyyy-MM-dd` (fingerprint inside entry).
    var planDayIdeasByDate: [String: PlanDayIdeasCacheEntry] = [:]
    var loadingPlanDayIdeaDates: Set<String> = []
    var generatingStoryboardThumbnailCardIDs: Set<UUID> = []
    var storyboardThumbnailErrors: [UUID: String] = [:]
    var generationError: String?
    var latestGenerationSummary: GeneratedWeekDraft?
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
    private let acceptedGenerationStore: any AcceptedDayGenerationStoring
    let aiConsentStore: any AIConsentStoring
    var isAIConsentSheetPresented = false
    var aiConsentAllowsOutbound = false
    var aiConsentEpoch = 0
    private var recoveringAcceptedGenerationDates: Set<String> = []

    /// Resolves the Plan package for a date from session cards or the latest draft summary.
    func dayPackage(for scheduledDate: String) -> GeneratedDailyCardDraft? {
        if let card = dayBriefGeneratedCards[scheduledDate] {
            return card
        }
        return latestGenerationSummary?.dailyCards.first { $0.scheduledDate == scheduledDate }
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

        let scheduledDate = card.scheduledDate ?? currentTodayDateString
        if let package = dayPackage(for: scheduledDate),
           Self.hasUsableStoryboardThumbnails(package.storyboardThumbnailAssets) {
            return package.storyboardThumbnailAssets
        }

        if let summaryCard = latestGenerationSummary?.dailyCards.first(where: {
            $0.id == card.id || $0.scheduledDate == scheduledDate
        }), Self.hasUsableStoryboardThumbnails(summaryCard.storyboardThumbnailAssets) {
            return summaryCard.storyboardThumbnailAssets
        }

        if let weekCard = weekCards.first(where: {
            $0.id == card.id || $0.scheduledDate == scheduledDate
        }), Self.hasUsableStoryboardThumbnails(weekCard.storyboardThumbnailAssets) {
            return weekCard.storyboardThumbnailAssets ?? []
        }

        return card.storyboardThumbnailAssets ?? []
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

    private var latestTodayDecisionSyncID = 0
    private var todayDecisionSyncTask: Task<Void, Never>?

    private struct PendingTodayDecisionSync {
        let id: Int
        let card: DailyCard
        let decision: DailyDecision
        let localEntry: ArchiveEntry
    }

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
        acceptedGenerationStore: any AcceptedDayGenerationStoring = UserDefaultsAcceptedDayGenerationStore.shared,
        aiConsentStore: (any AIConsentStoring)? = nil
    ) {
        self.context = repositories.context
        self.isLiveSupabaseRuntime = isLiveSupabaseRuntime
        self.memberRole = memberRole
        self.repositories = repositories
        self.todayCache = todayCache
        self.notifications = notifications
        self.todayDate = todayDate
        self.acceptedGenerationStore = acceptedGenerationStore
        self.aiConsentStore = aiConsentStore ?? UserDefaultsAIConsentStore(
            workspaceID: repositories.context.workspaceID,
            creatorID: repositories.context.creatorID
        )
        self.aiConsentAllowsOutbound = AIConsentPolicy.allowsOutbound(self.aiConsentStore.load())
        self.todayCard = todayCard
        shotSceneIDs = todayCard.completionState == .shot || todayCard.completionState == .posted
            ? Set(todayCard.scenes.map(\.id))
            : []
        self.archiveEntries = archiveEntries
        self.weeklyPlan = weeklyPlan
        weeklyBriefDraftText = weeklyPlan.weeklyBriefText
        self.weeklyIdeas = weeklyIdeas
        self.intelligenceHome = intelligenceHome
        self.creatorProfileSummary = creatorProfileSummary
        self.weekCards = weekCards
        self.todayContentState = todayContentState
        if isLiveSupabaseRuntime {
            supabaseHealthStatus = .unknown
            geminiHealthStatus = .unknown
        } else {
            supabaseHealthStatus = .sample
            geminiHealthStatus = .sample
        }
    }

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
        acceptedGenerationStore: any AcceptedDayGenerationStoring = UserDefaultsAcceptedDayGenerationStore.shared,
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
            archiveEntries: ArchiveEntry.fixtures,
            weeklyPlan: .raceWeek,
            weeklyIdeas: WeeklyIdea.raceWeekBank,
            intelligenceHome: .raceWeekLibrary,
            creatorProfileSummary: .creatorFixture,
            weekCards: DailyCard.weekFixtures,
            acceptedGenerationStore: acceptedGenerationStore,
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
        shotSceneIDs.insert(scene.id)
        lastActionMessage = "Scene \(scene.number) marked shot."
        if areAllScenesShot, todayCard.completionState == nil {
            completeToday(with: DailyDecision.shot)
        }
    }

    func markAllScenesShot() {
        shotSceneIDs.formUnion(todayCard.scenes.map(\.id))
        lastActionMessage = "All scenes marked shot."
        if todayCard.completionState == nil {
            completeToday(with: DailyDecision.shot)
        }
    }

    /// Records the card as posted once all scenes are shot. Produces the green
    /// success toast the creator sees after shipping. The Shoot Folio only
    /// reveals this action after every scene is marked shot.
    func markPosted() {
        guard areAllScenesShot else { return }
        lastActionMessage = "Content marked as posted."
        completeToday(with: DailyDecision.posted)
    }

    var canMarkPosted: Bool {
        areAllScenesShot && todayCard.completionState != .posted
    }

    func completeToday(with decision: DailyDecision) {
        let pendingSync = prepareTodayDecisionSync(decision)
        todayDecisionSyncTask?.cancel()
        todayDecisionSyncTask = Task { [weak self, pendingSync] in
            guard let self else { return }
            _ = await self.syncTodayDecision(pendingSync)
        }
    }

    @discardableResult
    func completeTodayImmediately(with decision: DailyDecision) async -> ArchiveEntry {
        let pendingSync = prepareTodayDecisionSync(decision)
        todayDecisionSyncTask?.cancel()
        return await syncTodayDecision(pendingSync)
    }

    @discardableResult
    private func applyLocalTodayDecision(_ decision: DailyDecision) -> (card: DailyCard, entry: ArchiveEntry) {
        todayCard.completionState = decision.completionState
        let localEntry = makeArchiveEntry(for: todayCard, decision: decision)
        upsertLocalArchiveEntry(localEntry, for: todayCard)
        saveTodaySnapshot(source: "decision")
        Task {
            await cancelTodayNotification()
        }
        return (todayCard, localEntry)
    }

    private func prepareTodayDecisionSync(_ decision: DailyDecision) -> PendingTodayDecisionSync {
        let localDecision = applyLocalTodayDecision(decision)
        lastTodayDecisionSyncError = nil
        latestTodayDecisionSyncID += 1
        return PendingTodayDecisionSync(
            id: latestTodayDecisionSyncID,
            card: localDecision.card,
            decision: decision,
            localEntry: localDecision.entry
        )
    }

    private func isCurrentTodayDecisionSync(_ pendingSync: PendingTodayDecisionSync) -> Bool {
        pendingSync.id == latestTodayDecisionSyncID && !Task.isCancelled
    }

    @discardableResult
    private func syncTodayDecision(_ pendingSync: PendingTodayDecisionSync) async -> ArchiveEntry {
        guard isCurrentTodayDecisionSync(pendingSync) else {
            return pendingSync.localEntry
        }

        do {
            let entry = try await repositories.today.completeToday(
                card: pendingSync.card,
                decision: pendingSync.decision,
                context: context
            )
            guard isCurrentTodayDecisionSync(pendingSync) else {
                return pendingSync.localEntry
            }
            try await repositories.archive.persistDecision(
                entry,
                for: pendingSync.card,
                context: context
            )
            guard isCurrentTodayDecisionSync(pendingSync) else {
                return pendingSync.localEntry
            }
            if let refreshedEntries = try? await repositories.archive.entries(for: context) {
                archiveEntries = refreshedEntries
            }
            // Fixture archives ignore persist; keep the synced entry visible locally.
            upsertLocalArchiveEntry(entry, for: pendingSync.card)
            guard isCurrentTodayDecisionSync(pendingSync) else {
                return pendingSync.localEntry
            }
            saveTodaySnapshot(source: "decision-synced")
            lastRepositoryError = nil
            lastTodayDecisionSyncError = nil
            return entry
        } catch RepositoryError.noPublishedTodayCard(let date) {
            guard isCurrentTodayDecisionSync(pendingSync) else {
                return pendingSync.localEntry
            }
            applyMissingPublishedTodayCardState(date: date)
            lastRepositoryError = nil
            lastTodayDecisionSyncError = nil
            return pendingSync.localEntry
        } catch {
            guard isCurrentTodayDecisionSync(pendingSync) else {
                return pendingSync.localEntry
            }
            if error is CancellationError {
                return pendingSync.localEntry
            }
            if (error as NSError).domain == NSURLErrorDomain,
               (error as NSError).code == NSURLErrorCancelled {
                return pendingSync.localEntry
            }
            lastTodayDecisionSyncError = TodayDecisionErrorDisplay.message(for: error)
            return pendingSync.localEntry
        }
    }

    var nextOpenWeeklyDay: WeeklyDay? {
        weeklyPlan.days.first { $0.state == .open }
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

    var isWeeklyBriefDirty: Bool {
        weeklyBriefDraftText.trimmingCharacters(in: .whitespacesAndNewlines) !=
            weeklyPlan.weeklyBriefText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func updateWeeklyDateWindow(startDate: String, endDate: String) {
        updateWeeklyStartDate(startDate)
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
        dateParser.dateFormat = "yyyy-MM-dd"

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
        weekdayFormatter.dateFormat = "EEE"

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
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

        regeneratingDayDates.insert(scheduledDate)
        regenerationDayErrors[scheduledDate] = nil
        defer { regeneratingDayDates.remove(scheduledDate) }

        do {
            logGeneration(
                "regenerate_day started scheduled_date=\(scheduledDate) preserve_manual_edits=\(preserveManualEdits) guidance_chars=\(dayGuidance?.count ?? 0)"
            )
            let result = try await repositories.dailyGeneration.regenerateDay(
                creatorID: context.creatorID,
                weeklyPlanID: weeklyPlan.id,
                scheduledDate: scheduledDate,
                preserveManualEdits: preserveManualEdits,
                dayGuidance: dayGuidance,
                context: context
            )
            applyRegeneratedDay(result.dailyCard)
            generationError = nil
            lastRepositoryError = nil
            logGeneration("regenerate_day completed scheduled_date=\(scheduledDate) daily_card_id=\(result.dailyCard.id)")
            return result.dailyCard
        } catch {
            let message = DayGenerationErrorDisplay.message(for: error)
            regenerationDayErrors[scheduledDate] = message
            generationError = message
            logGeneration("regenerate_day failed scheduled_date=\(scheduledDate) error=\(message)")
            throw RepositoryError.edgeFunction(message)
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

    /// Day-at-a-time generation: one storyboard + caption card for an explicit
    /// target date, driven entirely by the supplied day brief (which can also
    /// carry one-off asks like brand deliverables). The server sends the
    /// creator profile, references, and this brief to the AI provider.
    ///
    /// When the date already has a ready package or Decision, pass
    /// `confirmOverwrite: true` after an explicit Overwrite confirmation.
    /// That unpublishes first (clearing live Decision, keeping Archive), then
    /// regenerates as a new draft.
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

        let existingStatus = dayBriefGeneratedCards[scheduledDate]?.status
            ?? latestGenerationSummary?.dailyCards.first(where: { $0.scheduledDate == scheduledDate })?.status
        // Any existing package — draft or live — must be explicitly confirmed before it is replaced.
        if existingStatus != nil {
            guard confirmOverwrite else {
                let error = "ready_package_overwrite_required"
                dayBriefGenerationErrors[scheduledDate] = DayLifecycleErrorDisplay.message(forCode: error)
                pendingOverwriteGenerateDate = scheduledDate
                throw RepositoryError.edgeFunction(error)
            }
            // Only live packages (published / decision) need unpublishing;
            // a draft has nothing live to unpublish.
            if DayPackageLifecycleStatus.requiresOverwriteConfirmation(existingStatus) {
                do {
                    _ = try await unpublishDay(scheduledDate: scheduledDate)
                } catch {
                    let message = DayLifecycleErrorDisplay.message(for: error)
                    dayBriefGenerationErrors[scheduledDate] = message
                    throw RepositoryError.edgeFunction(message)
                }
            }
        }
        pendingOverwriteGenerateDate = nil

        guard !generatingDayBriefDates.contains(scheduledDate) else {
            let message = DayGenerationErrorDisplay.message(forCode: "generation_already_running")
            dayBriefGenerationErrors[scheduledDate] = message
            throw RepositoryError.edgeFunction(message)
        }

        if let acceptedRun = acceptedGenerationStore.load(scheduledDate: scheduledDate) {
            return try await resumeAcceptedDayGeneration(acceptedRun)
        }

        generatingDayBriefDates.insert(scheduledDate)
        dayBriefGenerationErrors[scheduledDate] = nil
        defer { generatingDayBriefDates.remove(scheduledDate) }

        do {
            logGeneration("generate_day started scheduled_date=\(scheduledDate) brief_chars=\(brief.count)")
            let result = try await repositories.dailyGeneration.generateDay(
                creatorID: context.creatorID,
                scheduledDate: scheduledDate,
                dayBrief: brief,
                context: context
            )
            return try applyDayGenerationResult(result, scheduledDate: scheduledDate)
        } catch {
            let message = DayGenerationErrorDisplay.message(for: error)
            dayBriefGenerationErrors[scheduledDate] = message
            logGeneration(
                "generate_day failed scheduled_date=\(scheduledDate) user_message=\(message) error_type=\(String(describing: type(of: error))) localized=\(error.localizedDescription) dump=\(String(describing: error))"
            )
            throw RepositoryError.edgeFunction(message)
        }
    }

    /// Rehydrates persisted accepted runs after relaunch and resumes status polling — no new POST.
    func restoreAcceptedDayGenerationsIfNeeded() {
        for run in acceptedGenerationStore.loadAll() {
            guard !recoveringAcceptedGenerationDates.contains(run.scheduledDate) else { continue }
            recoveringAcceptedGenerationDates.insert(run.scheduledDate)
            generatingDayBriefDates.insert(run.scheduledDate)
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer {
                    self.recoveringAcceptedGenerationDates.remove(run.scheduledDate)
                    self.generatingDayBriefDates.remove(run.scheduledDate)
                }
                _ = try? await self.resumeAcceptedDayGeneration(run, fromRecovery: true)
            }
        }
    }

    private func resumeAcceptedDayGeneration(
        _ run: AcceptedDayGenerationRun,
        fromRecovery: Bool = false
    ) async throws -> GeneratedDailyCardDraft {
        if !fromRecovery {
            guard !generatingDayBriefDates.contains(run.scheduledDate) else {
                let message = DayGenerationErrorDisplay.message(forCode: "generation_already_running")
                dayBriefGenerationErrors[run.scheduledDate] = message
                throw RepositoryError.edgeFunction(message)
            }
        }

        let manageGeneratingFlag = !fromRecovery && !generatingDayBriefDates.contains(run.scheduledDate)
        if manageGeneratingFlag {
            generatingDayBriefDates.insert(run.scheduledDate)
        }
        dayBriefGenerationErrors[run.scheduledDate] = nil
        defer {
            if manageGeneratingFlag {
                generatingDayBriefDates.remove(run.scheduledDate)
            }
        }

        do {
            logGeneration("generate_day resume scheduled_date=\(run.scheduledDate) generation_id=\(run.generationID)")
            let result = try await repositories.dailyGeneration.resumeAcceptedDayGeneration(
                generationID: run.generationID,
                creatorID: run.creatorID,
                context: context
            )
            acceptedGenerationStore.remove(scheduledDate: run.scheduledDate)
            return try applyDayGenerationResult(result, scheduledDate: run.scheduledDate)
        } catch {
            let message = DayGenerationErrorDisplay.message(for: error)
            dayBriefGenerationErrors[run.scheduledDate] = message
            throw RepositoryError.edgeFunction(message)
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
            dayBriefGeneratedCards[scheduledDate] = result.dailyCard
            let integratesWithCurrentWeeklyReview = result.weeklyPlanID == weeklyPlan.id
                && weeklyPlan.days.contains(where: { $0.scheduledDate == scheduledDate })
            if integratesWithCurrentWeeklyReview {
                applyRegeneratedDay(result.dailyCard)
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

    func applyRegeneratedDay(_ card: GeneratedDailyCardDraft) {
        if var draft = latestGenerationSummary,
           draft.weeklyPlanID == weeklyPlan.id {
            if draft.replaceDailyCard(card) {
                latestGenerationSummary = draft
            }
        }

        if let dayIndex = weeklyPlan.days.firstIndex(where: {
            $0.id == card.id || $0.scheduledDate == card.scheduledDate
        }) {
            weeklyPlan.days[dayIndex] = card.weeklyDay
            weeklyPlan.readinessLine = weeklyPlan.computedReadinessLine
        }
    }

    func applyStoryboardThumbnailAssets(
        _ assets: [StoryboardThumbnailAsset],
        toDailyCardID dailyCardID: UUID
    ) {
        let matchingScheduledDates = dayBriefGeneratedCards.compactMap { scheduledDate, card in
            card.id == dailyCardID ? scheduledDate : nil
        }
        for scheduledDate in matchingScheduledDates {
            guard var updatedCard = dayBriefGeneratedCards[scheduledDate] else { continue }
            updatedCard.storyboardThumbnailAssets = assets
            dayBriefGeneratedCards[scheduledDate] = updatedCard
        }

        if var draft = latestGenerationSummary,
           let index = draft.dailyCards.firstIndex(where: { $0.id == dailyCardID }) {
            draft.dailyCards[index].storyboardThumbnailAssets = assets
            latestGenerationSummary = draft
        }

        if todayCard.id == dailyCardID
            || matchingScheduledDates.contains(todayCard.scheduledDate ?? "")
            || matchingScheduledDates.contains(currentTodayDateString) {
            todayCard.storyboardThumbnailAssets = assets
            saveTodaySnapshot(source: "storyboard-thumbnail-apply")
        }

        if let weekIndex = weekCards.firstIndex(where: { $0.id == dailyCardID }) {
            weekCards[weekIndex].storyboardThumbnailAssets = assets
        }
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

    func updateWeeklyDayState(dayID: UUID, state: WeeklyDayState) {
        Task {
            _ = await updateWeeklyDayStateImmediately(dayID: dayID, state: state)
        }
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

        if var draft = latestGenerationSummary,
           draft.weeklyPlanID == weeklyPlan.id,
           let cardIndex = draft.dailyCards.firstIndex(where: {
               $0.id == dailyCardID || $0.scheduledDate == day.scheduledDate
           }) {
            draft.dailyCards[cardIndex].status = state.generatedDraftStatus
            latestGenerationSummary = draft
        }

        generationError = nil

        do {
            try await repositories.weeklyPlans.updateDailyCardReviewState(
                dailyCardID: dailyCardID,
                reviewState: state.generatedDraftStatus,
                context: context
            )
            lastRepositoryError = nil
            return true
        } catch {
            guard weeklyPlan.days[dayIndex].state == state else {
                return false
            }
            weeklyPlan.days[dayIndex].state = previousState
            weeklyPlan.readinessLine = weeklyPlan.computedReadinessLine
            if var draft = latestGenerationSummary,
               draft.weeklyPlanID == weeklyPlan.id,
               let cardIndex = draft.dailyCards.firstIndex(where: {
                   $0.id == dailyCardID || $0.scheduledDate == day.scheduledDate
               }) {
                draft.dailyCards[cardIndex].status = previousState.generatedDraftStatus
                latestGenerationSummary = draft
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
        let record = OnboardingRecord(completedData: completedData)
        let completedAt = SupabaseDateFormatting.isoTimestampString()
        let existingPackage = firstIdeaPackage(for: scheduledDate)
        let plan = OnboardingFirstIdeaHandoffPlanner.plan(
            scheduledDate: scheduledDate,
            record: record,
            existingPackageStatus: existingPackage?.status,
            hasUserEditedPackage: hasUserEditedFirstIdeaPackage(for: scheduledDate),
            firstIdeaHandoffStatus: creatorProfileSummary.firstIdeaHandoff["status"],
            existingDraftIsComplete: isFirstIdeaDraftComplete(existingPackage)
        )

        let preparingHandoff = OnboardingFirstIdeaHandoffPlanner.firstIdeaHandoffPayload(
            scheduledDate: scheduledDate,
            status: .preparing,
            briefFingerprint: plan.briefFingerprint
        )
        var establishedUpdate = OnboardingProfileMapper.profileUpdate(
            from: record,
            onboardingState: .established,
            onboardingStep: nil,
            onboardingCompletedAt: completedAt,
            firstIdeaHandoff: preparingHandoff
        )

        guard await updateCreatorProfileImmediately(establishedUpdate) else {
            var partialUpdate = establishedUpdate
            partialUpdate.onboardingState = .partial
            partialUpdate.onboardingCompletedAt = nil
            _ = await updateCreatorProfileImmediately(partialUpdate)
            return .persistFailed
        }

        if !plan.shouldGenerate {
            if plan.makeAvailableOnly {
                do {
                    let navigatedToday = try await makeDayAvailable(scheduledDate: scheduledDate)
                    return await completeFirstIdeaHandoff(
                        record: record,
                        scheduledDate: scheduledDate,
                        completedAt: completedAt,
                        briefFingerprint: plan.briefFingerprint,
                        navigatedToday: navigatedToday
                    )
                } catch {
                    return await failFirstIdeaHandoff(
                        record: record,
                        scheduledDate: scheduledDate,
                        completedAt: completedAt,
                        briefFingerprint: plan.briefFingerprint,
                        error: error
                    )
                }
            }

            return await skipFirstIdeaHandoffForExistingReady(
                record: record,
                scheduledDate: scheduledDate,
                completedAt: completedAt,
                briefFingerprint: plan.briefFingerprint,
                skipReason: plan.skipReason
            )
        }

        if hasUsableReadyTodayPackage(for: scheduledDate) {
            return await skipFirstIdeaHandoffForExistingReady(
                record: record,
                scheduledDate: scheduledDate,
                completedAt: completedAt,
                briefFingerprint: plan.briefFingerprint,
                skipReason: .skippedExistingReady
            )
        }

        do {
            _ = try await generateDayCard(
                scheduledDate: scheduledDate,
                dayBrief: plan.dayBrief,
                confirmOverwrite: plan.confirmOverwrite,
                allowDeferredVoice: completedData.voiceDeferred
            )
            let navigatedToday = try await makeDayAvailable(scheduledDate: scheduledDate)
            return await completeFirstIdeaHandoff(
                record: record,
                scheduledDate: scheduledDate,
                completedAt: completedAt,
                briefFingerprint: plan.briefFingerprint,
                navigatedToday: navigatedToday
            )
        } catch {
            if Self.isReadyPackageOverwriteRequired(error) {
                return await skipFirstIdeaHandoffForExistingReady(
                    record: record,
                    scheduledDate: scheduledDate,
                    completedAt: completedAt,
                    briefFingerprint: plan.briefFingerprint,
                    skipReason: .skippedExistingReady
                )
            }
            return await failFirstIdeaHandoff(
                record: record,
                scheduledDate: scheduledDate,
                completedAt: completedAt,
                briefFingerprint: plan.briefFingerprint,
                error: error
            )
        }
    }

    private func skipFirstIdeaHandoffForExistingReady(
        record: OnboardingRecord,
        scheduledDate: String,
        completedAt: String,
        briefFingerprint: String,
        skipReason: OnboardingFirstIdeaHandoffStatus?
    ) async -> OnboardingFirstIdeaHandoffResult {
        let skippedHandoff = OnboardingFirstIdeaHandoffPlanner.firstIdeaHandoffPayload(
            scheduledDate: scheduledDate,
            status: skipReason ?? .skippedExistingReady,
            briefFingerprint: briefFingerprint
        )
        var skippedUpdate = OnboardingProfileMapper.profileUpdate(
            from: record,
            onboardingState: .established,
            onboardingCompletedAt: completedAt,
            firstIdeaHandoff: skippedHandoff
        )
        _ = await updateCreatorProfileImmediately(skippedUpdate)
        return .skippedExistingReady
    }

    private func completeFirstIdeaHandoff(
        record: OnboardingRecord,
        scheduledDate: String,
        completedAt: String,
        briefFingerprint: String,
        navigatedToday: Bool
    ) async -> OnboardingFirstIdeaHandoffResult {
        let completedHandoff = OnboardingFirstIdeaHandoffPlanner.firstIdeaHandoffPayload(
            scheduledDate: scheduledDate,
            status: .completed,
            briefFingerprint: briefFingerprint
        )
        var completedUpdate = OnboardingProfileMapper.profileUpdate(
            from: record,
            onboardingState: .established,
            onboardingCompletedAt: completedAt,
            firstIdeaHandoff: completedHandoff
        )
        _ = await updateCreatorProfileImmediately(completedUpdate)
        return .completed(navigatedToday: navigatedToday)
    }

    private func failFirstIdeaHandoff(
        record: OnboardingRecord,
        scheduledDate: String,
        completedAt: String,
        briefFingerprint: String,
        error: Error
    ) async -> OnboardingFirstIdeaHandoffResult {
        let failedHandoff = OnboardingFirstIdeaHandoffPlanner.firstIdeaHandoffPayload(
            scheduledDate: scheduledDate,
            status: .failed,
            briefFingerprint: briefFingerprint
        )
        var failedUpdate = OnboardingProfileMapper.profileUpdate(
            from: record,
            onboardingState: .established,
            onboardingCompletedAt: completedAt,
            firstIdeaHandoff: failedHandoff
        )
        _ = await updateCreatorProfileImmediately(failedUpdate)
        return .generationFailed(message: Self.firstIdeaHandoffErrorMessage(for: error))
    }

    private static let todayCardLoadingTitles: Set<String> = [
        "Checking today's plan"
    ]

    private func hasUsableReadyTodayPackage(for scheduledDate: String) -> Bool {
        guard scheduledDate == currentTodayDateString else { return false }
        let title = todayCard.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !Self.todayCardLoadingTitles.contains(title) else { return false }
        return !todayCard.scenes.isEmpty
    }

    private static func isReadyPackageOverwriteRequired(_ error: Error) -> Bool {
        if case RepositoryError.edgeFunction(let code) = error {
            return code == "ready_package_overwrite_required"
        }
        return error.localizedDescription.contains("ready_package_overwrite_required")
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

    private func existingFirstIdeaPackageStatus(for scheduledDate: String) -> String? {
        firstIdeaPackage(for: scheduledDate)?.status
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

    func publishCurrentWeek() {
        Task {
            await publishCurrentWeekImmediately()
        }
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
                hydrateDayBriefGeneratedCardsFromLatestDraft()
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

    /// Promotes one draft day to a ready package. Returns `true` when the date is
    /// device-local today and Today was refreshed with that card (caller should
    /// navigate to Creator Today). On failure, throws after setting
    /// `lastMakeDayAvailableError` and does not navigate.
    @discardableResult
    func makeDayAvailable(scheduledDate: String) async throws -> Bool {
        guard !isMakingDayAvailable else {
            throw RepositoryError.edgeFunction("make_day_available_already_running")
        }

        isMakingDayAvailable = true
        lastMakeDayAvailableError = nil
        defer { isMakingDayAvailable = false }

        let draftCard = dayBriefGeneratedCards[scheduledDate]
            ?? latestGenerationSummary?.dailyCards.first(where: { $0.scheduledDate == scheduledDate })

        do {
            let result = try await repositories.weeklyPlans.makeDayAvailable(
                scheduledDate: scheduledDate,
                dailyCardID: draftCard?.id,
                context: context
            )

            if var localDraft = dayBriefGeneratedCards[scheduledDate] {
                localDraft.status = "published"
                dayBriefGeneratedCards[scheduledDate] = localDraft
            }
            if var summary = latestGenerationSummary,
               let index = summary.dailyCards.firstIndex(where: { $0.scheduledDate == scheduledDate }) {
                var card = summary.dailyCards[index]
                card.status = "published"
                summary.dailyCards[index] = card
                latestGenerationSummary = summary
            }

            let isLocalToday = scheduledDate == currentTodayDateString
            if isLocalToday {
                let preservedAssets = draftCard?.storyboardThumbnailAssets ?? []
                if let draftCard {
                    todayCard = draftCard.dailyCard(completionState: nil)
                    todayContentState = .ready
                }
                await refreshPublishedContentAfterPublishImmediately(skipTodayCard: draftCard != nil)
                if !Self.hasUsableStoryboardThumbnails(todayCard.storyboardThumbnailAssets),
                   Self.hasUsableStoryboardThumbnails(preservedAssets) {
                    todayCard.storyboardThumbnailAssets = preservedAssets
                }
                hydrateTodayStoryboardThumbnailsFromPlanPackage()
                saveTodaySnapshot(source: "day-available")
                await scheduleTodayNotificationIfNeededImmediately()
            }

            lastActionMessage = isLocalToday
                ? "Ready for Today."
                : "Ready package saved for \(SupabaseDateFormatting.displayDate(for: scheduledDate))."
            lastRepositoryError = nil
            _ = result
            return isLocalToday
        } catch {
            let message = DayAvailabilityErrorDisplay.message(for: error)
            lastMakeDayAvailableError = message
            throw RepositoryError.edgeFunction(message)
        }
    }

    /// Demotes a ready/decision package to draft. Clears live Decision state locally
    /// and empties Today when the date is device-local today. Archive entries stay.
    @discardableResult
    func unpublishDay(scheduledDate: String) async throws -> DayUnpublishResult {
        guard !isUnpublishingDay else {
            throw RepositoryError.edgeFunction("unpublish_day_already_running")
        }

        isUnpublishingDay = true
        lastUnpublishDayError = nil
        defer { isUnpublishingDay = false }

        let card = dayBriefGeneratedCards[scheduledDate]
            ?? latestGenerationSummary?.dailyCards.first(where: { $0.scheduledDate == scheduledDate })

        do {
            let result = try await repositories.weeklyPlans.unpublishDay(
                scheduledDate: scheduledDate,
                dailyCardID: card?.id,
                context: context
            )

            if var localCard = dayBriefGeneratedCards[scheduledDate] {
                localCard.status = "draft"
                dayBriefGeneratedCards[scheduledDate] = localCard
            }
            if var summary = latestGenerationSummary,
               let index = summary.dailyCards.firstIndex(where: { $0.scheduledDate == scheduledDate }) {
                var draftCard = summary.dailyCards[index]
                draftCard.status = "draft"
                summary.dailyCards[index] = draftCard
                latestGenerationSummary = summary
            }

            let isLocalToday = scheduledDate == currentTodayDateString
            if isLocalToday {
                todayContentState = .missingPublishedCard(date: scheduledDate)
                weekCards.removeAll { $0.scheduledDate == scheduledDate }
                if todayCard.scheduledDate == scheduledDate {
                    todayCard = DailyCard(
                        id: UUID(),
                        title: "No ready package",
                        context: SupabaseDateFormatting.contextLine(for: scheduledDate),
                        effortLabel: "",
                        whyToday: "Unpublished. Generate or make a draft available again.",
                        scheduledDate: scheduledDate,
                        scenes: []
                    )
                }
                await refreshPublishedContentAfterPublishImmediately()
                saveTodaySnapshot(source: "day-unpublish")
            }

            lastActionMessage = "Unpublished — back to draft."
            lastRepositoryError = nil
            return result
        } catch {
            let message = DayLifecycleErrorDisplay.message(for: error)
            lastUnpublishDayError = message
            throw RepositoryError.edgeFunction(message)
        }
    }

    /// Light-edits a ready package in place (status stays ready). Refreshes Today when local today.
    @discardableResult
    func updateReadyDayPackage(
        scheduledDate: String,
        package: ReadyDayPackageUpdate
    ) async throws -> DayPackageUpdateResult {
        guard !isUpdatingReadyDayPackage else {
            throw RepositoryError.edgeFunction("update_ready_day_package_already_running")
        }

        isUpdatingReadyDayPackage = true
        lastReadyDayPackageEditError = nil
        defer { isUpdatingReadyDayPackage = false }

        let card = dayBriefGeneratedCards[scheduledDate]
            ?? latestGenerationSummary?.dailyCards.first(where: { $0.scheduledDate == scheduledDate })

        let resolvedCardID = card?.id
            ?? weekCards.first(where: { $0.scheduledDate == scheduledDate })?.id
            ?? (scheduledDate == currentTodayDateString ? todayCard.id : nil)

        do {
            let result = try await repositories.weeklyPlans.updateReadyDayPackage(
                scheduledDate: scheduledDate,
                dailyCardID: resolvedCardID,
                package: package,
                context: context
            )

            if var localCard = dayBriefGeneratedCards[scheduledDate] {
                if let title = package.title?.nilIfBlank { localCard.title = title }
                if let whyToday = package.whyToday?.nilIfBlank { localCard.whyToday = whyToday }
                if let caption = package.caption { localCard.caption = caption }
                if let script = package.script { localCard.script = script }
                if let backupStory = package.backupStory { localCard.backupStory = backupStory }
                if let backupCaptionOnly = package.backupCaptionOnly {
                    localCard.backupCaptionOnly = backupCaptionOnly
                }
                if let shootability = package.shootability { localCard.shootability = shootability }
                if let minutes = package.estimatedShootMinutes {
                    localCard.estimatedShootMinutes = minutes
                }
                if let sceneList = package.sceneList {
                    localCard.sceneList = sceneList
                }
                // Keep ready status — light edit must not demote.
                dayBriefGeneratedCards[scheduledDate] = localCard
            }

            let isLocalToday = scheduledDate == currentTodayDateString
            if isLocalToday {
                if let title = package.title?.nilIfBlank {
                    todayCard.title = title
                }
                if let whyToday = package.whyToday?.nilIfBlank {
                    todayCard.whyToday = whyToday
                }
                if let caption = package.caption {
                    todayCard.caption = caption
                }
                if let script = package.script {
                    todayCard.script = script
                }
                if let sceneList = package.sceneList {
                    todayCard.scenes = sceneList
                }
                if var localCard = dayBriefGeneratedCards[scheduledDate] {
                    todayCard = localCard.dailyCard(completionState: todayCard.completionState)
                }
                todayContentState = .ready
                if let index = weekCards.firstIndex(where: { $0.scheduledDate == scheduledDate }) {
                    weekCards[index] = todayCard
                }
                await refreshPublishedContentAfterPublishImmediately()
                saveTodaySnapshot(source: "ready-day-edit")
            }

            lastActionMessage = "Ready package updated."
            lastRepositoryError = nil
            return result
        } catch {
            let message = DayLifecycleErrorDisplay.message(for: error)
            lastReadyDayPackageEditError = message
            throw RepositoryError.edgeFunction(message)
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
        do {
            let content = try await repositories.weeklyPlans.currentWeeklyContent(for: context)
            guard let draft = content.generatedDraft,
                  draft.weeklyPlanID == weeklyPlan.id,
                  let canonicalCard = draft.dailyCards.first(where: { $0.scheduledDate == scheduledDate })
            else {
                return
            }

            if var localDraft = latestGenerationSummary {
                if localDraft.weeklyPlanID == draft.weeklyPlanID {
                    localDraft.replaceDailyCard(canonicalCard)
                    latestGenerationSummary = localDraft
                }
            } else {
                latestGenerationSummary = draft
            }

            if let dayIndex = weeklyPlan.days.firstIndex(where: {
                $0.id == canonicalCard.id || $0.scheduledDate == canonicalCard.scheduledDate
            }) {
                weeklyPlan.days[dayIndex] = canonicalCard.weeklyDay
                weeklyPlan.readinessLine = weeklyPlan.computedReadinessLine
            }

            dayBriefGeneratedCards[scheduledDate] = canonicalCard
            lastRepositoryError = nil
        } catch {
            if suppressRepositoryErrorOnFailure {
                logGeneration(
                    "reconcile_generated_day_card_failed scheduled_date=\(scheduledDate) error=\(error.localizedDescription)"
                )
            } else {
                lastRepositoryError = error.localizedDescription
            }
        }
    }

    func refreshFromRepositories() {
        Task {
            await refreshFromRepositoriesImmediately()
        }
    }

    func checkRuntimeHealth() {
        Task {
            await checkRuntimeHealthImmediately()
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

    func refreshWeeklyData() {
        Task {
            await refreshWeeklyDataFromRepositories()
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
            return true
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
            todayCard = try await repositories.today.todayCard(for: context)
            todayContentState = .ready
            saveTodaySnapshot(source: "repository-refresh")
            await scheduleTodayNotificationIfNeededImmediately()
        } catch RepositoryError.noPublishedTodayCard(let date) {
            isMissingPublishedTodayCard = true
            applyMissingPublishedTodayCardState(date: date)
        } catch {
            refreshError = error
            if loadTodayFromCache() {
                todayContentState = .ready
                await scheduleTodayNotificationIfNeededImmediately()
            } else {
                lastRepositoryError = error.localizedDescription
            }
        }

        do {
            weekCards = try await repositories.today.weekCards(for: context)
        } catch {
            refreshError = refreshError ?? error
        }

        do {
            archiveEntries = try await repositories.archive.entries(for: context)
        } catch {
            refreshError = refreshError ?? error
        }

        do {
            let weeklyContent = try await repositories.weeklyPlans.currentWeeklyContent(for: context)
            weeklyPlan = weeklyContent.workingPlan ?? weeklyContent.publishedPlan
            weeklyBriefDraftText = weeklyPlan.weeklyBriefText
            latestGenerationSummary = weeklyContent.generatedDraft
            hydrateDayBriefGeneratedCardsFromLatestDraft()
            weeklyIdeas = weeklyContent.ideaBank
        } catch {
            refreshError = refreshError ?? error
        }

        do {
            intelligenceHome = try await repositories.intelligence.home(for: context)
        } catch {
            refreshError = refreshError ?? error
        }

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
        restoreAcceptedDayGenerationsIfNeeded()
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
        var refreshError: Error?

        if !skipTodayCard {
            do {
                todayCard = try await repositories.today.todayCard(for: context)
                todayContentState = .ready
            } catch RepositoryError.noPublishedTodayCard(let date) {
                todayContentState = .missingPublishedCard(date: date)
                lastNotificationSchedule = nil
                lastNotificationError = nil
            } catch {
                refreshError = error
            }
        }

        do {
            weekCards = try await repositories.today.weekCards(for: context)
        } catch {
            refreshError = refreshError ?? error
        }

        do {
            weeklyPlan = try await repositories.weeklyPlans.currentPublishedPlan(for: context)
            weeklyBriefDraftText = weeklyPlan.weeklyBriefText
        } catch {
            refreshError = refreshError ?? error
        }

        lastRepositoryRefreshError = refreshError?.localizedDescription
    }

    func refreshIntelligenceHomeImmediately() async {
        do {
            intelligenceHome = try await repositories.intelligence.home(for: context)
            lastRepositoryError = nil
        } catch {
            lastRepositoryError = error.localizedDescription
        }
    }

    private func refreshWeeklyDataFromRepositories() async {
        var refreshError: Error?

        do {
            let weeklyContent = try await repositories.weeklyPlans.currentWeeklyContent(for: context)
            weeklyPlan = weeklyContent.workingPlan ?? weeklyContent.publishedPlan
            weeklyBriefDraftText = weeklyPlan.weeklyBriefText
            latestGenerationSummary = weeklyContent.generatedDraft
            hydrateDayBriefGeneratedCardsFromLatestDraft()
            weeklyIdeas = weeklyContent.ideaBank
        } catch {
            refreshError = error
        }

        if let refreshError {
            lastRepositoryRefreshError = refreshError.localizedDescription
        } else {
            lastRepositoryRefreshError = nil
            normalizeManagerWeekStartIfStale()
        }
    }

    private func hydrateDayBriefGeneratedCardsFromLatestDraft() {
        var hydratedCards = dayBriefGeneratedCards.filter { generatingDayBriefDates.contains($0.key) }

        guard let draft = latestGenerationSummary else {
            return
        }

        for card in draft.dailyCards where card.status.lowercased() != "published" {
            guard !generatingDayBriefDates.contains(card.scheduledDate) else { continue }
            hydratedCards[card.scheduledDate] = card
        }

        dayBriefGeneratedCards = hydratedCards
    }

    func scheduleTodayNotificationIfNeeded() {
        Task {
            await scheduleTodayNotificationIfNeededImmediately()
        }
    }

    func scheduleTodayNotificationIfNeededImmediately() async {
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
        todayCard = snapshot.todayCard
        weekCards = snapshot.weekCards
    }

    private func saveTodaySnapshot(source: String) {
        let snapshot = CachedTodaySnapshot(
            todayCard: todayCard,
            weekCards: weekCards,
            cachedAt: Date(),
            source: source
        )

        do {
            try todayCache.saveSnapshot(snapshot, for: context)
        } catch {
            lastRepositoryError = error.localizedDescription
        }
    }

    private func makeArchiveEntry(
        for card: DailyCard,
        decision: DailyDecision
    ) -> ArchiveEntry {
        let archiveDate = card.scheduledDate ?? SupabaseDateFormatting.todayDateString()
        return ArchiveEntry(
            dailyCardID: card.id,
            day: SupabaseDateFormatting.weekdayAbbreviation(for: archiveDate),
            date: SupabaseDateFormatting.shortDate(for: archiveDate),
            cardTitle: card.title,
            decision: decision.completionState,
            outputLine: decision.outputLine,
            hasPostThumbnail: decision.hasPostThumbnail
        )
    }

    private func upsertLocalArchiveEntry(_ entry: ArchiveEntry, for card: DailyCard) {
        if let index = archiveEntries.firstIndex(where: { archiveEntry in
            archiveEntry.dailyCardID == card.id || archiveEntry.cardTitle == card.title
        }) {
            archiveEntries[index] = entry
        } else {
            archiveEntries.insert(entry, at: 0)
        }
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
