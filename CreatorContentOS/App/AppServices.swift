import Foundation
import Observation

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
    var weeklyIdeas: [WeeklyIdea]
    var intelligenceHome: IntelligenceHome
    var creatorProfileSummary: CreatorProfileSummary
    var weekCards: [DailyCard]
    var lastRepositoryError: String?
    var lastRepositoryRefreshAttemptAt: Date?
    var lastRepositoryRefreshAt: Date?
    var lastNotificationSchedule: TodayNotificationSchedule?
    var lastNotificationError: String?
    var isPublishingWeek = false
    var lastPublishSummary: String?
    var isGeneratingWeek = false
    var regeneratingDayDates: Set<String> = []
    var regenerationDayErrors: [String: String] = [:]
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

    init(
        repositories: AppRepositories,
        isLiveSupabaseRuntime: Bool = false,
        memberRole: String = "owner",
        todayCache: any TodayCacheStoring = FileTodayCacheStore(),
        notifications: any TodayNotificationScheduling = NoopTodayNotificationScheduler(),
        todayCard: DailyCard,
        archiveEntries: [ArchiveEntry],
        weeklyPlan: WeeklyPlan,
        weeklyIdeas: [WeeklyIdea],
        intelligenceHome: IntelligenceHome,
        creatorProfileSummary: CreatorProfileSummary,
        weekCards: [DailyCard]
    ) {
        self.context = repositories.context
        self.isLiveSupabaseRuntime = isLiveSupabaseRuntime
        self.memberRole = memberRole
        self.repositories = repositories
        self.todayCache = todayCache
        self.notifications = notifications
        self.todayCard = todayCard
        shotSceneIDs = todayCard.completionState == .shot || todayCard.completionState == .posted
            ? Set(todayCard.scenes.map(\.id))
            : []
        self.archiveEntries = archiveEntries
        self.weeklyPlan = weeklyPlan
        self.weeklyIdeas = weeklyIdeas
        self.intelligenceHome = intelligenceHome
        self.creatorProfileSummary = creatorProfileSummary
        self.weekCards = weekCards
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
        notifications: any TodayNotificationScheduling = NoopTodayNotificationScheduler()
    ) -> AppServices {
        AppServices(
            repositories: repositories,
            isLiveSupabaseRuntime: isLiveSupabaseRuntime,
            memberRole: memberRole,
            todayCache: todayCache,
            notifications: notifications,
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
            weekCards: []
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
        if areAllScenesShot, todayCard.completionState == nil {
            completeToday(with: DailyDecision.shot)
        }
    }

    func markAllScenesShot() {
        shotSceneIDs.formUnion(todayCard.scenes.map(\.id))
        if todayCard.completionState == nil {
            completeToday(with: DailyDecision.shot)
        }
    }

    func completeToday(with decision: DailyDecision) {
        Task {
            await completeTodayImmediately(with: decision)
        }
    }

    @discardableResult
    func completeTodayImmediately(with decision: DailyDecision) async -> ArchiveEntry {
        todayCard.completionState = decision.completionState
        let localEntry = makeArchiveEntry(for: todayCard, decision: decision)
        upsertLocalArchiveEntry(localEntry, for: todayCard)
        saveTodaySnapshot(source: "decision")
        await cancelTodayNotification()

        do {
            let entry = try await repositories.today.completeToday(
                card: todayCard,
                decision: decision,
                context: context
            )
            archiveEntries = try await repositories.archive.upsertDecision(
                entry,
                for: todayCard,
                context: context
            )
            saveTodaySnapshot(source: "decision-synced")
            lastRepositoryError = nil
            return entry
        } catch {
            lastRepositoryError = error.localizedDescription
            return localEntry
        }
    }

    var nextOpenWeeklyDay: WeeklyDay? {
        weeklyPlan.days.first { $0.state == .open }
    }

    var canGenerateWeek: Bool {
        (memberRole == "owner" || memberRole == "editor") &&
            !weeklyPlan.isSoftLocked &&
            !isGeneratingWeek
    }

    func updateWeeklyDateWindow(startDate: String, endDate: String) {
        guard !weeklyPlan.isSoftLocked else { return }

        let constrainedEndDate = SupabaseDateFormatting.constrainedWeekEndDate(
            starting: startDate,
            requestedEndDate: endDate
        )
        weeklyPlan.weekStartDate = startDate
        weeklyPlan.weekEndDate = constrainedEndDate
        weeklyPlan.weekRange = SupabaseDateFormatting.dateRange(
            starting: startDate,
            ending: constrainedEndDate
        )
        generationError = nil
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

        isGeneratingWeek = true
        defer { isGeneratingWeek = false }

        do {
            let weekStartDate = weeklyPlan.weekStartDate
                ?? weeklyPlan.days.compactMap(\.scheduledDate).first
                ?? SupabaseDateFormatting.todayDateString()
            let mode: GenerateWeekMode = latestGenerationSummary == nil ? .generateDraft : .regenerateDraft
            let draft = try await repositories.weeklyGeneration.generateWeek(
                creatorID: context.creatorID,
                weekStartDate: weekStartDate,
                weeklySetupID: nil,
                mode: mode,
                context: context
            )
            applyGeneratedDraft(draft)
            generationError = nil
            lastRepositoryError = nil
            return draft
        } catch {
            generationError = WeeklyGenerationErrorDisplay.message(for: error)
            return nil
        }
    }

    func applyGeneratedDraft(_ draft: GeneratedWeekDraft) {
        latestGenerationSummary = draft
        weeklyPlan = draft.weeklyPlan(setupSections: weeklyPlan.setupSections)
        weeklyIdeas = draft.ideaBank.isEmpty ? weeklyIdeas : draft.ideaBank
    }

    func generatedDailyCard(for dayID: UUID) -> GeneratedDailyCardDraft? {
        latestGenerationSummary?.dailyCards.first { $0.id == dayID }
    }

    func regeneratedDailyCard(
        scheduledDate: String,
        preserveManualEdits: Bool
    ) async throws -> GeneratedDailyCardDraft {
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

    func updateWeeklyDayState(dayID: UUID, state: WeeklyDayState) {
        guard !weeklyPlan.isSoftLocked,
              let dayIndex = weeklyPlan.days.firstIndex(where: { $0.id == dayID }),
              !weeklyPlan.days[dayIndex].isSoftLocked
        else {
            return
        }

        weeklyPlan.days[dayIndex].state = state
        weeklyPlan.readinessLine = weeklyPlan.computedReadinessLine

        if var draft = latestGenerationSummary,
           draft.weeklyPlanID == weeklyPlan.id,
           let cardIndex = draft.dailyCards.firstIndex(where: { $0.id == dayID }) {
            draft.dailyCards[cardIndex].status = state.generatedDraftStatus
            latestGenerationSummary = draft
        }

        generationError = nil
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
            lastRepositoryError = nil
        } catch {
            lastRepositoryError = error.localizedDescription
        }
    }

    func publishCurrentWeek() {
        Task {
            await publishCurrentWeekImmediately()
        }
    }

    func publishCurrentWeekImmediately() async {
        guard !isPublishingWeek else { return }

        isPublishingWeek = true
        defer { isPublishingWeek = false }

        do {
            let result = try await repositories.weeklyPlans.publishWeek(
                weeklyPlan,
                ideaBank: weeklyIdeas,
                generatedDraft: latestGenerationSummary?.weeklyPlanID == weeklyPlan.id ? latestGenerationSummary : nil,
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
            saveTodaySnapshot(source: "week-publish")
            await scheduleTodayNotificationIfNeededImmediately()
            lastPublishSummary = result.summary
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
            lastReferenceImportError = error.localizedDescription
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
            lastReferenceImportError = nil
            await refreshIntelligenceHomeImmediately()
            return result
        } catch {
            lastReferenceImportError = error.localizedDescription
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
            lastReferenceImportError = nil
            await refreshIntelligenceHomeImmediately()
            return result
        } catch {
            lastReferenceImportError = error.localizedDescription
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
        lastRepositoryRefreshAttemptAt = Date()
        var refreshError: Error?

        do {
            async let loadedTodayCard = repositories.today.todayCard(for: context)
            async let loadedWeekCards = repositories.today.weekCards(for: context)

            todayCard = try await loadedTodayCard
            weekCards = try await loadedWeekCards
            saveTodaySnapshot(source: "repository-refresh")
            await scheduleTodayNotificationIfNeededImmediately()
        } catch {
            refreshError = error
            if loadTodayFromCache() {
                await scheduleTodayNotificationIfNeededImmediately()
            } else {
                lastRepositoryError = error.localizedDescription
            }
        }

        do {
            archiveEntries = try await repositories.archive.entries(for: context)
        } catch {
            refreshError = refreshError ?? error
        }

        do {
            weeklyPlan = try await repositories.weeklyPlans.currentPublishedPlan(for: context)
        } catch {
            refreshError = refreshError ?? error
        }

        do {
            weeklyIdeas = try await repositories.weeklyPlans.ideaBank(for: context)
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
        }
    }

    func refreshIntelligenceHomeImmediately() async {
        do {
            intelligenceHome = try await repositories.intelligence.home(for: context)
            lastRepositoryError = nil
        } catch {
            lastRepositoryError = error.localizedDescription
        }
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
        "existing_published_week_locked"
    ]

    static func message(for error: Error) -> String {
        let description = error.localizedDescription
        if stableCodes.contains(description) {
            return description
        }

        return stableCodes.first { description.contains($0) } ?? description
    }
}
