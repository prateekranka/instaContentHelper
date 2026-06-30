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
    var weekCards: [DailyCard]
    var lastRepositoryError: String?
    var lastRepositoryRefreshAttemptAt: Date?
    var lastRepositoryRefreshAt: Date?
    var isRefreshingRepository = false
    var lastRepositoryRefreshError: String?
    var lastRepositoryRefreshSucceededAt: Date?
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
    var isGeneratingWeek = false
    var regeneratingDayDates: Set<String> = []
    var regenerationDayErrors: [String: String] = [:]
    var generationError: String?
    var weeklyGenerationProgress: WeeklyGenerationProgress?
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
        todayContentState: TodayContentState = .ready
    ) {
        self.context = repositories.context
        self.isLiveSupabaseRuntime = isLiveSupabaseRuntime
        self.memberRole = memberRole
        self.repositories = repositories
        self.todayCache = todayCache
        self.notifications = notifications
        self.todayDate = todayDate
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
    }

    var canManageTesterAccess: Bool {
        isLiveSupabaseRuntime && memberRole == "owner"
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
        todayDate: @escaping TodayDateProvider = { SupabaseDateFormatting.todayDateString() }
    ) -> AppServices {
        AppServices(
            repositories: repositories,
            isLiveSupabaseRuntime: isLiveSupabaseRuntime,
            memberRole: memberRole,
            todayCache: todayCache,
            notifications: notifications,
            todayDate: todayDate,
            todayCard: .raceWeekToday,
            archiveEntries: ArchiveEntry.fixtures,
            weeklyPlan: .raceWeek,
            weeklyIdeas: WeeklyIdea.raceWeekBank,
            intelligenceHome: .raceWeekLibrary,
            creatorProfileSummary: .creatorFixture,
            weekCards: DailyCard.weekFixtures
        )
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
            creatorProfileSummary: CreatorProfileSummary(
                displayName: "Creator",
                positioning: "Loading live profile",
                voiceLine: "",
                noGoTopics: []
            ),
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
            archiveEntries = try await repositories.archive.upsertDecision(
                entry,
                for: pendingSync.card,
                context: context
            )
            guard isCurrentTodayDecisionSync(pendingSync) else {
                return pendingSync.localEntry
            }
            saveTodaySnapshot(source: "decision-synced")
            lastRepositoryError = nil
            return entry
        } catch {
            guard isCurrentTodayDecisionSync(pendingSync) else {
                return pendingSync.localEntry
            }
            lastRepositoryError = error.localizedDescription
            return pendingSync.localEntry
        }
    }

    var nextOpenWeeklyDay: WeeklyDay? {
        weeklyPlan.days.first { $0.state == .open }
    }

    var canGenerateWeek: Bool {
        (memberRole == "owner" || memberRole == "editor") &&
            !weeklyPlan.isSoftLocked &&
            !isSavingWeeklyBrief &&
            !isGeneratingWeek
    }

    var canPublishCurrentWeek: Bool {
        guard memberRole == "owner" || memberRole == "editor",
              !isPublishingWeek,
              !isGeneratingWeek,
              !weeklyPlan.isSoftLocked,
              weeklyPlan.days.count == 7,
              weeklyPlan.openDayCount == 0
        else {
            return false
        }

        if let progress = weeklyGenerationProgress,
           !progress.dayStatuses.isEmpty,
           !progress.dayStatuses.allSatisfy(\.isCompleted) {
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
        weeklyGenerationProgress = nil
        generationError = nil
    }

    func updateWeeklyStartDate(_ startDate: String) {
        guard !weeklyPlan.isSoftLocked else { return }

        guard !SupabaseDateFormatting.isDatePast(startDate, todayString: todayDate()) else {
            generationError = "past_generation_date_not_allowed"
            return
        }

        let constrainedEndDate = SupabaseDateFormatting.weekEndDate(starting: startDate)
        let openDays = Self.emptyWeekDays(starting: startDate)
        weeklyPlan.weekStartDate = startDate
        weeklyPlan.weekEndDate = constrainedEndDate
        weeklyPlan.weekRange = SupabaseDateFormatting.dateRange(
            starting: startDate,
            ending: constrainedEndDate
        )
        weeklyPlan.days = openDays
        weeklyPlan.readinessLine = weeklyPlan.computedReadinessLine
        latestGenerationSummary = nil
        generationError = nil
        weeklyGenerationProgress = nil
        lastPublishError = nil
    }

    func generateCurrentWeek() {
        Task {
            await generateCurrentWeekImmediately()
        }
    }

    @discardableResult
    func generateCurrentWeekImmediately() async -> GeneratedWeekDraft? {
        guard !isGeneratingWeek else {
            return latestGenerationSummary
        }

        guard memberRole == "owner" || memberRole == "editor" else {
            generationError = "role_not_allowed"
            return nil
        }

        guard !weeklyPlan.isSoftLocked else {
            generationError = "existing_published_week_locked"
            return nil
        }

        let weekStartDate = weeklyPlan.weekStartDate
            ?? weeklyPlan.days.compactMap(\.scheduledDate).first
            ?? todayDate()

        guard !SupabaseDateFormatting.isDatePast(weekStartDate, todayString: todayDate()) else {
            generationError = "past_generation_date_not_allowed"
            return nil
        }

        if isWeeklyBriefDirty {
            weeklyGenerationProgress = .savingWeeklyBrief
            let didSave = await updateWeeklyBriefImmediately(weeklyBriefDraftText)
            guard didSave else {
                generationError = weeklyBriefEditError ?? "weekly_setup_update_failed"
                weeklyGenerationProgress = .failed(generationError ?? "weekly_setup_update_failed")
                return nil
            }
        }

        isGeneratingWeek = true
        generationError = nil
        weeklyGenerationProgress = .loadingContext
        defer { isGeneratingWeek = false }

        let mode: GenerateWeekMode = latestGenerationSummary == nil ? .generateDraft : .regenerateDraft
        let previousDraft = latestGenerationSummary
        let previousPlan = weeklyPlan

        do {
            if mode == .regenerateDraft {
                latestGenerationSummary = nil
                weeklyPlan.days = Self.emptyWeekDays(starting: weekStartDate)
                weeklyPlan.readinessLine = weeklyPlan.computedReadinessLine
            }
            let draft = try await repositories.weeklyGeneration.generateWeek(
                creatorID: context.creatorID,
                weekStartDate: weekStartDate,
                weeklySetupID: nil,
                mode: mode,
                context: context,
                progress: { [weak self] progress in
                    self?.weeklyGenerationProgress = progress
                }
            )
            guard !draft.dailyCards.isEmpty else {
                if mode == .regenerateDraft {
                    latestGenerationSummary = previousDraft
                    weeklyPlan = previousPlan
                }
                throw RepositoryError.edgeFunction("invalid_generated_week")
            }

            applyGeneratedDraft(draft)
            if !draft.isCompleteWeekDraft {
                let message = "Some days were saved and some days failed. Retry the failed days before publishing."
                let terminalProgress = weeklyGenerationProgress
                generationError = nil
                weeklyGenerationProgress = WeeklyGenerationProgress.partialFailure(
                    from: draft,
                    message: message,
                    preserving: terminalProgress,
                    expectedScheduledDates: Self.expectedGenerationScheduledDates(
                        weekStartDate: weekStartDate,
                        weeklyPlan: weeklyPlan
                    )
                )
                lastRepositoryError = nil
                return draft
            }

            weeklyGenerationProgress = .savingDraftWeek(from: draft)
            weeklyGenerationProgress = .readyForReview(from: draft)
            generationError = nil
            lastRepositoryError = nil
            return draft
        } catch {
            if latestGenerationSummary == nil,
               let previousDraft = previousDraft,
               mode == .regenerateDraft {
                latestGenerationSummary = previousDraft
                weeklyPlan = previousPlan
            }
            generationError = WeeklyGenerationErrorDisplay.message(for: error)
            let message = generationError ?? error.localizedDescription
            weeklyGenerationProgress = weeklyGenerationProgress?.failed(message) ?? .failed(message)
            return nil
        }
    }

    func applyGeneratedDraft(_ draft: GeneratedWeekDraft) {
        guard !draft.dailyCards.isEmpty else {
            generationError = WeeklyGenerationErrorDisplay.message(forCode: "invalid_generated_week")
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
        let dateParser = DateFormatter()
        dateParser.locale = Locale(identifier: "en_US_POSIX")
        dateParser.dateFormat = "yyyy-MM-dd"

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
        weekdayFormatter.dateFormat = "EEE"

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "d"

        return SupabaseDateFormatting.weekDates(starting: startDate).map { dateString in
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

    private static func expectedGenerationScheduledDates(
        weekStartDate: String?,
        weeklyPlan: WeeklyPlan
    ) -> [String] {
        if let weekStartDate {
            return SupabaseDateFormatting.weekDates(starting: weekStartDate)
        }

        if let firstScheduledDate = weeklyPlan.days.compactMap(\.scheduledDate).first {
            return SupabaseDateFormatting.weekDates(starting: firstScheduledDate)
        }

        return weeklyPlan.days.compactMap(\.scheduledDate)
    }

    func generatedDailyCard(for dayID: UUID) -> GeneratedDailyCardDraft? {
        latestGenerationSummary?.dailyCards.first { $0.id == dayID }
    }

    func generatedDailyCard(for day: WeeklyDay) -> GeneratedDailyCardDraft? {
        latestGenerationSummary?.dailyCards.first {
            $0.id == day.id || $0.scheduledDate == day.scheduledDate
        }
    }

    func regeneratedDailyCard(
        scheduledDate: String,
        preserveManualEdits: Bool
    ) async throws -> GeneratedDailyCardDraft {
        guard !SupabaseDateFormatting.isDatePast(scheduledDate, todayString: todayDate()) ||
            isRetryableFailedGenerationDate(scheduledDate) else {
            let error = "past_generation_date_not_allowed"
            regenerationDayErrors[scheduledDate] = error
            throw RepositoryError.edgeFunction(error)
        }

        guard memberRole == "owner" || memberRole == "editor" else {
            let error = "role_not_allowed"
            regenerationDayErrors[scheduledDate] = error
            throw RepositoryError.edgeFunction(error)
        }

        guard !weeklyPlan.isSoftLocked else {
            let error = "published_week_locked"
            regenerationDayErrors[scheduledDate] = error
            throw RepositoryError.edgeFunction(error)
        }

        guard !regeneratingDayDates.contains(scheduledDate) else {
            if let existing = latestGenerationSummary?.dailyCards.first(where: { $0.scheduledDate == scheduledDate }) {
                return existing
            }
            let error = "generation_already_running"
            regenerationDayErrors[scheduledDate] = error
            throw RepositoryError.edgeFunction(error)
        }

        regeneratingDayDates.insert(scheduledDate)
        regenerationDayErrors[scheduledDate] = nil
        defer { regeneratingDayDates.remove(scheduledDate) }

        do {
            let result = try await repositories.weeklyGeneration.regenerateDay(
                creatorID: context.creatorID,
                weeklyPlanID: weeklyPlan.id,
                scheduledDate: scheduledDate,
                preserveManualEdits: preserveManualEdits,
                context: context
            )
            applyRegeneratedDay(result.dailyCard)
            markRegeneratedDayCompleted(result.dailyCard)
            generationError = nil
            lastRepositoryError = nil
            return result.dailyCard
        } catch {
            let message = WeeklyGenerationErrorDisplay.message(for: error)
            regenerationDayErrors[scheduledDate] = message
            generationError = message
            throw RepositoryError.edgeFunction(message)
        }
    }

    func retryQueuedGenerationDay(scheduledDate: String) async throws {
        guard !SupabaseDateFormatting.isDatePast(scheduledDate, todayString: todayDate()) ||
            isRetryableFailedGenerationDate(scheduledDate) else {
            let error = "past_generation_date_not_allowed"
            regenerationDayErrors[scheduledDate] = error
            throw RepositoryError.edgeFunction(error)
        }

        guard memberRole == "owner" || memberRole == "editor" else {
            let error = "role_not_allowed"
            regenerationDayErrors[scheduledDate] = error
            throw RepositoryError.edgeFunction(error)
        }

        guard !weeklyPlan.isSoftLocked else {
            let error = "published_week_locked"
            regenerationDayErrors[scheduledDate] = error
            throw RepositoryError.edgeFunction(error)
        }

        guard let generationID = weeklyGenerationProgress?.generationID else {
            let error = "generation_not_found"
            regenerationDayErrors[scheduledDate] = error
            throw RepositoryError.edgeFunction(error)
        }

        // Past failed dates in the active draft week must use regenerate_day,
        // not the durable retry_day path which rejects past dates.
        if SupabaseDateFormatting.isDatePast(scheduledDate, todayString: todayDate()),
           isRetryableFailedGenerationDate(scheduledDate) {
            markQueuedDayRetrying(scheduledDate: scheduledDate)
            _ = try await regeneratedDailyCard(
                scheduledDate: scheduledDate,
                preserveManualEdits: false
            )
            return
        }

        let canFallbackToRegenerateDay = isRetryableFailedGenerationDate(scheduledDate)
        regeneratingDayDates.insert(scheduledDate)
        regenerationDayErrors[scheduledDate] = nil
        defer { regeneratingDayDates.remove(scheduledDate) }

        do {
            let preservedDayStates = reviewedDayStatesByDate()
            let expectedScheduledDates = Self.expectedGenerationScheduledDates(
                weekStartDate: weeklyPlan.weekStartDate,
                weeklyPlan: weeklyPlan
            )
            markQueuedDayRetrying(scheduledDate: scheduledDate)
            let draft = try await repositories.weeklyGeneration.retryQueuedDay(
                generationID: generationID,
                scheduledDate: scheduledDate,
                context: context,
                progress: { [weak self] progress in
                    self?.weeklyGenerationProgress = progress
                }
            )
            applyGeneratedDraft(draft)
            restoreReviewedDayStates(preservedDayStates)
            if !draft.isCompleteWeekDraft {
                let message = "Some days were saved and some days failed. Retry the failed days before publishing."
                weeklyGenerationProgress = WeeklyGenerationProgress.partialFailure(
                    from: draft,
                    message: message,
                    preserving: weeklyGenerationProgress,
                    expectedScheduledDates: expectedScheduledDates
                )
                generationError = nil
                lastRepositoryError = nil
                return
            }

            weeklyGenerationProgress = .readyForReview(from: draft)
            generationError = nil
            lastRepositoryError = nil
        } catch {
            if shouldFallbackToRegenerateDayAfterQueuedRetryFailure(
                error,
                canFallback: canFallbackToRegenerateDay
            ) {
                regeneratingDayDates.remove(scheduledDate)
                regenerationDayErrors[scheduledDate] = nil
                markQueuedDayRetrying(scheduledDate: scheduledDate)
                _ = try await regeneratedDailyCard(
                    scheduledDate: scheduledDate,
                    preserveManualEdits: false
                )
                return
            }
            let message = WeeklyGenerationErrorDisplay.message(for: error)
            regenerationDayErrors[scheduledDate] = message
            generationError = message
            throw RepositoryError.edgeFunction(message)
        }
    }

    func cancelGeneration() {
        let generationID = weeklyGenerationProgress?.generationID
        isGeneratingWeek = false
        weeklyGenerationProgress = nil
        generationError = nil

        guard let generationID else { return }

        let context = self.context
        Task { [weak self] in
            do {
                try await self?.repositories.weeklyGeneration.cancelGeneration(
                    generationID: generationID,
                    context: context
                )
            } catch {
                self?.lastRepositoryError = error.localizedDescription
            }
        }
    }

    func applyRegeneratedDay(_ card: GeneratedDailyCardDraft) {
        if var draft = latestGenerationSummary {
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

    private func markRegeneratedDayCompleted(_ card: GeneratedDailyCardDraft) {
        guard var progress = weeklyGenerationProgress,
              let index = progress.dayStatuses.firstIndex(where: { $0.scheduledDate == card.scheduledDate })
        else { return }

        progress.dayStatuses[index].status = "completed"
        progress.dayStatuses[index].dailyCardID = card.id
        progress.dayStatuses[index].errorCode = nil
        progress.dayStatuses[index].message = nil
        let savedCount = progress.dayStatuses.filter(\.isCompleted).count
        let failedCount = progress.dayStatuses.filter(\.isFailed).count
        progress.savedDayCount = max(progress.savedDayCount ?? 0, savedCount)
        progress.failedDayCount = failedCount
        progress.checkedDayCount = progress.savedDayCount ?? progress.checkedDayCount
        progress.draftedDayCount = min(progress.totalDayCount, savedCount)
        if failedCount == 0, let draft = latestGenerationSummary, draft.dailyCards.count >= progress.totalDayCount {
            progress = .readyForReview(from: draft)
        }
        weeklyGenerationProgress = progress
    }

    private func markQueuedDayRetrying(scheduledDate: String) {
        guard var progress = weeklyGenerationProgress,
              let index = progress.dayStatuses.firstIndex(where: { $0.scheduledDate == scheduledDate })
        else { return }

        progress.dayStatuses[index].status = "retrying"
        progress.dayStatuses[index].errorCode = nil
        progress.dayStatuses[index].message = nil
        progress.failedDayCount = progress.dayStatuses.filter(\.isFailed).count
        progress.currentDay = scheduledDate
        weeklyGenerationProgress = progress
    }

    private func reviewedDayStatesByDate() -> [String: WeeklyDayState] {
        weeklyPlan.days.reduce(into: [String: WeeklyDayState]()) { result, day in
            guard let scheduledDate = day.scheduledDate,
                  day.state != .open
            else { return }

            result[scheduledDate] = day.state
        }
    }

    private func restoreReviewedDayStates(_ statesByDate: [String: WeeklyDayState]) {
        guard !statesByDate.isEmpty else { return }

        for index in weeklyPlan.days.indices {
            guard let scheduledDate = weeklyPlan.days[index].scheduledDate,
                  let state = statesByDate[scheduledDate]
            else { continue }

            weeklyPlan.days[index].state = state
        }
        weeklyPlan.readinessLine = weeklyPlan.computedReadinessLine

        guard var draft = latestGenerationSummary else { return }
        for index in draft.dailyCards.indices {
            guard let state = statesByDate[draft.dailyCards[index].scheduledDate] else {
                continue
            }
            draft.dailyCards[index].status = state.generatedDraftStatus
        }
        latestGenerationSummary = draft
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

    func reconcileGeneratedDayCardFromCurrentWeeklyContent(scheduledDate: String) async {
        do {
            let content = try await repositories.weeklyPlans.currentWeeklyContent(for: context)
            guard let draft = content.generatedDraft,
                  draft.weeklyPlanID == weeklyPlan.id,
                  let canonicalCard = draft.dailyCards.first(where: { $0.scheduledDate == scheduledDate })
            else {
                return
            }

            if var localDraft = latestGenerationSummary,
               localDraft.weeklyPlanID == draft.weeklyPlanID {
                localDraft.replaceDailyCard(canonicalCard)
                latestGenerationSummary = localDraft
            }

            if let dayIndex = weeklyPlan.days.firstIndex(where: {
                $0.id == canonicalCard.id || $0.scheduledDate == canonicalCard.scheduledDate
            }) {
                weeklyPlan.days[dayIndex] = canonicalCard.weeklyDay
                weeklyPlan.readinessLine = weeklyPlan.computedReadinessLine
            }

            lastRepositoryError = nil
        } catch {
            lastRepositoryError = error.localizedDescription
        }
    }

    func refreshFromRepositories() {
        Task {
            await refreshFromRepositoriesImmediately()
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
        } catch {
            lastReferenceImportError = ReferenceImportErrorDisplay.message(for: error)
            referenceImportToast = nil
            return nil
        }
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
        defer { isRefreshingRepository = false }

        do {
            todayCard = try await repositories.today.todayCard(for: context)
            todayContentState = .ready
            saveTodaySnapshot(source: "repository-refresh")
            await scheduleTodayNotificationIfNeededImmediately()
        } catch RepositoryError.noPublishedTodayCard(let date) {
            refreshError = RepositoryError.noPublishedTodayCard(date: date)
            todayContentState = .missingPublishedCard(date: date)
            lastNotificationSchedule = nil
            lastNotificationError = nil
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
            weeklyIdeas = weeklyContent.ideaBank
            reconcileGenerationProgressAfterDraftRefresh()
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
        } catch {
            refreshError = refreshError ?? error
        }

        lastRepositoryError = refreshError?.localizedDescription
        if refreshError == nil {
            lastRepositoryRefreshAt = Date()
            lastRepositoryRefreshSucceededAt = Date()
            lastRepositoryRefreshError = nil
            todayContentState = .ready
        } else {
            lastRepositoryRefreshError = refreshError?.localizedDescription
        }

#if DEBUG
        applyDebugWeekStartOverrideIfNeeded()
#endif

        normalizeManagerWeekStartIfStale()
    }

    /// Re-fetches canonical published content immediately after publish so the
    /// manager week state and creator Today state come from the same source of truth.
    /// This prevents local reviewed-draft state from diverging from published rows.
    func refreshPublishedContentAfterPublishImmediately() async {
        var refreshError: Error?

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

        lastRepositoryError = refreshError?.localizedDescription
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
            weeklyIdeas = weeklyContent.ideaBank
            reconcileGenerationProgressAfterDraftRefresh()
        } catch {
            refreshError = error
        }

        if let refreshError {
            lastRepositoryError = refreshError.localizedDescription
        } else {
            lastRepositoryError = nil
            normalizeManagerWeekStartIfStale()
        }
    }

    private func reconcileGenerationProgressAfterDraftRefresh() {
        guard let draft = latestGenerationSummary, draft.weeklyPlanID == weeklyPlan.id else {
            if weeklyGenerationProgress?.phase == .failed {
                weeklyGenerationProgress = nil
            }
            return
        }

        if draft.isCompleteWeekDraft {
            if weeklyGenerationProgress?.phase == .failed {
                weeklyGenerationProgress = nil
            }
            return
        }

        weeklyGenerationProgress = WeeklyGenerationProgress.partialFailure(
            from: draft,
            message: "Some days were saved and some days failed. Retry the failed days before publishing.",
            preserving: weeklyGenerationProgress,
            expectedScheduledDates: Self.expectedGenerationScheduledDates(
                weekStartDate: weeklyPlan.weekStartDate,
                weeklyPlan: weeklyPlan
            )
        )
        generationError = nil
    }

    private func isRetryableFailedGenerationDate(_ scheduledDate: String) -> Bool {
        guard latestGenerationSummary?.weeklyPlanID == weeklyPlan.id else { return false }

        return weeklyGenerationProgress?.dayStatuses.contains {
            $0.scheduledDate == scheduledDate &&
                ($0.isFailed || $0.isRetrying) &&
                ($0.retryAction == "retry_day" || $0.retryAction == "regenerate_day")
        } ?? false
    }

    private func shouldFallbackToRegenerateDayAfterQueuedRetryFailure(
        _ error: Error,
        canFallback: Bool
    ) -> Bool {
        guard canFallback else { return false }

        let description = error.localizedDescription
        return [
            "past_generation_date_not_allowed",
            "day_job_not_retryable"
        ].contains { description.contains($0) }
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

private enum WeeklyGenerationErrorDisplay {
    private static let userFacingMessages = [
        "invalid_ai_json": "The AI returned an incomplete draft. Try Generate again.",
        "invalid_generated_week": "The AI draft did not pass validation. Try Generate again.",
        "openai_request_failed": "The AI service failed. Try Generate again.",
        "missing_openai_api_key": "AI generation is not configured in Supabase.",
        "invalid_generation_payload": "The generation request could not be accepted. Refresh and try again.",
        "generation_persist_failed": "The draft could not be saved. Try Generate again.",
        "weekly_setup_not_found": "The weekly brief could not be found. Save the brief and try again.",
        "existing_published_week_locked": "This week is already published and locked.",
        "past_generation_date_not_allowed": "You cannot generate content for a past date. Select today or a future date."
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
        "generation_persist_failed",
        "weekly_setup_not_found",
        "existing_published_week_locked",
        "past_generation_date_not_allowed"
    ]

    static func message(for error: Error) -> String {
        let description = error.localizedDescription
        if description.contains("generation_persist_failed:") {
            return "The draft could not be saved (\(description))."
        }
        if let message = userFacingMessages[description] {
            return message
        }

        if let code = stableCodes.first(where: { description.contains($0) }) {
            return userFacingMessages[code] ?? code
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
        "role_not_allowed": "Only owners and editors can manage references.",
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
