import XCTest
@testable import CreatorContentOS

@MainActor
final class ManagerAdminUsageTests: XCTestCase {
    func testManagerSelectsIdeaForNextOpenDay() async throws {
        let weeklyRepository = RecordingWeeklyPlanRepository()
        let services = makeServices(weeklyPlans: weeklyRepository)

        let targetDay = try XCTUnwrap(services.nextOpenWeeklyDay)
        let idea = try XCTUnwrap(services.weeklyIdeas.first { $0.selectedDay == nil })

        await services.selectIdeaForNextOpenDayImmediately(idea)

        let requests = await weeklyRepository.recordedSelectionRequests()
        XCTAssertEqual(requests.map(\.ideaID), [idea.id])
        XCTAssertEqual(requests.map(\.weeklyPlanID), [services.weeklyPlan.id])

        let updatedDay = try XCTUnwrap(
            services.weeklyPlan.days.first { $0.weekday == targetDay.weekday }
        )
        XCTAssertEqual(updatedDay.title, idea.title)
        XCTAssertEqual(updatedDay.reason, idea.reason)
        XCTAssertEqual(updatedDay.source, idea.source)
        XCTAssertEqual(updatedDay.state, .planned)
        XCTAssertNil(services.nextOpenWeeklyDay)
        XCTAssertEqual(
            services.weeklyIdeas.first { $0.id == idea.id }?.selectedDay,
            targetDay.weekday
        )
        XCTAssertEqual(services.lastActionMessage, "Idea added to the next open day.")
        XCTAssertNil(services.lastRepositoryError)
    }

    func testWeeklyReadinessLineReflectsCurrentPlanState() async throws {
        let services = makeServices()

        XCTAssertEqual(services.weeklyPlan.computedReadinessLine, "4 ready, 2 backup, 1 open")

        let idea = try XCTUnwrap(services.weeklyIdeas.first { $0.selectedDay == nil })
        await services.selectIdeaForNextOpenDayImmediately(idea)

        XCTAssertEqual(services.weeklyPlan.computedReadinessLine, "5 ready, 2 backup, 0 open")
    }

    func testManagerSeesErrorWhenIdeaSelectionFails() async throws {
        let weeklyRepository = RecordingWeeklyPlanRepository(
            selectionError: RepositoryError.notConfigured("Selection failed.")
        )
        let services = makeServices(weeklyPlans: weeklyRepository)
        let originalPlan = services.weeklyPlan
        let idea = try XCTUnwrap(services.weeklyIdeas.first { $0.selectedDay == nil })

        await services.selectIdeaForNextOpenDayImmediately(idea)

        XCTAssertEqual(services.weeklyPlan, originalPlan)
        XCTAssertEqual(services.lastRepositoryError, "Selection failed.")
    }

    func testManagerUpdatesWeeklySetupSections() async throws {
        let weeklyRepository = RecordingWeeklyPlanRepository()
        let services = makeServices(weeklyPlans: weeklyRepository)
        var updatedSections = services.weeklyPlan.setupSections
        updatedSections[0].summary = "Jersey City, early mornings."
        updatedSections[0].state = "Ready"

        let didSave = await services.updateWeeklySetupSectionsImmediately(updatedSections)

        XCTAssertTrue(didSave)
        XCTAssertEqual(services.weeklyPlan.setupSections, updatedSections)
        XCTAssertFalse(services.isSavingWeeklyBrief)
        XCTAssertNil(services.weeklyBriefEditError)
        XCTAssertNil(services.lastRepositoryError)
        XCTAssertEqual(services.lastActionMessage, "Weekly brief saved.")

        let requests = await weeklyRepository.recordedSetupRequests()
        XCTAssertEqual(requests, [updatedSections])
    }

    func testManagerKeepsWeeklySetupSectionsWhenSaveFails() async throws {
        let weeklyRepository = RecordingWeeklyPlanRepository(
            setupError: RepositoryError.edgeFunction("weekly_setup_update_failed")
        )
        let services = makeServices(weeklyPlans: weeklyRepository)
        let originalSections = services.weeklyPlan.setupSections
        var updatedSections = originalSections
        updatedSections[0].summary = "Jersey City, early mornings."

        let didSave = await services.updateWeeklySetupSectionsImmediately(updatedSections)

        XCTAssertFalse(didSave)
        XCTAssertEqual(services.weeklyPlan.setupSections, originalSections)
        XCTAssertFalse(services.isSavingWeeklyBrief)
        XCTAssertEqual(services.weeklyBriefEditError, "weekly_setup_update_failed")
        XCTAssertEqual(services.lastRepositoryError, "weekly_setup_update_failed")
    }

    func testWeeklyStartDateSetsSevenDayWindow() async throws {
        let services = makeServices()

        services.updateWeeklyStartDate("2026-07-13")

        XCTAssertEqual(services.weeklyPlan.weekStartDate, "2026-07-13")
        XCTAssertEqual(services.weeklyPlan.weekEndDate, "2026-07-19")
        XCTAssertEqual(services.weeklyPlan.weekRange, "13 Jul - 19 Jul")
    }

    func testWorkflowStatusIsPublishedOnlyForSelectedPublishedWeek() async throws {
        let status = WeeklyWorkflowWindowStatus(
            plan: WeeklyPlan.raceWeek.softLockedForPublish,
            startDate: "2026-06-01",
            endDate: "2026-06-07"
        )

        XCTAssertEqual(status, .published)
        XCTAssertEqual(status.tone, .ready)
    }

    func testWorkflowStatusIsPlannedWhenSelectedWeekHasPlannedContent() async throws {
        let status = WeeklyWorkflowWindowStatus(
            plan: WeeklyPlan.raceWeek,
            startDate: "2026-06-01",
            endDate: "2026-06-07"
        )

        XCTAssertEqual(status, .planned)
        XCTAssertEqual(status.tone, .warning)
    }

    func testWorkflowStatusDoesNotPublishDifferentSelectedWeek() async throws {
        let status = WeeklyWorkflowWindowStatus(
            plan: WeeklyPlan.raceWeek.softLockedForPublish,
            startDate: "2026-07-13",
            endDate: "2026-07-19"
        )

        XCTAssertEqual(status, .draft)
        XCTAssertEqual(status.tone, .info)
    }

    func testGenerateSavesDirtyWeeklyBriefBeforeGenerating() async throws {
        let weeklyRepository = RecordingWeeklyPlanRepository()
        let services = makeServices(weeklyPlans: weeklyRepository)
        let brief = """
        Weekly routine: Pilates Monday, strength Wednesday.
        Brand/collab: Puma pickup on Saturday.
        Family/travel: Sunday lunch.
        """

        services.weeklyBriefDraftText = brief
        let draft = await services.generateCurrentWeekImmediately()

        XCTAssertNotNil(draft)
        XCTAssertEqual(services.weeklyPlan.weeklyBriefText, brief)
        XCTAssertEqual(services.weeklyBriefDraftText, brief)
        XCTAssertNil(services.weeklyBriefEditError)
        XCTAssertNil(services.generationError)

        let briefRequests = await weeklyRepository.recordedBriefRequests()
        XCTAssertEqual(briefRequests, [brief])
    }

    func testGenerateStopsWhenDirtyWeeklyBriefSaveFails() async throws {
        let weeklyRepository = RecordingWeeklyPlanRepository(
            briefError: RepositoryError.edgeFunction("weekly_setup_update_failed")
        )
        let services = makeServices(weeklyPlans: weeklyRepository)
        let originalPlan = services.weeklyPlan

        services.weeklyBriefDraftText = "Weekly routine: save should fail."
        let draft = await services.generateCurrentWeekImmediately()

        XCTAssertNil(draft)
        XCTAssertEqual(services.weeklyPlan, originalPlan)
        XCTAssertEqual(services.weeklyBriefEditError, "weekly_setup_update_failed")
        XCTAssertEqual(services.generationError, "weekly_setup_update_failed")
        XCTAssertNil(services.latestGenerationSummary)

        let briefRequests = await weeklyRepository.recordedBriefRequests()
        XCTAssertEqual(briefRequests, ["Weekly routine: save should fail."])
    }

    func testManagerUpdatesCreatorProfileOutsideWeeklySetup() async throws {
        let profileRepository = RecordingCreatorProfileRepository()
        let services = makeServices(creatorProfile: profileRepository)
        let update = CreatorProfileUpdate(
            positioning: "Premium fitness-after-60 voice for busy weeks.",
            voiceRules: ["Warm", "Direct", "Light Hinglish when natural"],
            contentPillars: ["routine", "recovery", "family"],
            captionStyle: "Short and useful.",
            noGoTopics: ["Politics", "Weight talk"],
            recurringFormats: ["one practical detail", "caption-only backup"]
        )

        let didSave = await services.updateCreatorProfileImmediately(update)

        XCTAssertTrue(didSave)
        XCTAssertEqual(services.creatorProfileSummary.positioning, update.positioning)
        XCTAssertEqual(services.creatorProfileSummary.voiceRules, update.voiceRules)
        XCTAssertEqual(services.creatorProfileSummary.contentPillars, update.contentPillars)
        XCTAssertEqual(services.creatorProfileSummary.captionStyle, update.captionStyle)
        XCTAssertEqual(services.creatorProfileSummary.noGoTopics, update.noGoTopics)
        XCTAssertEqual(services.creatorProfileSummary.recurringFormats, update.recurringFormats)
        XCTAssertEqual(services.lastActionMessage, "Creator profile saved.")
        XCTAssertNil(services.creatorProfileEditError)

        let updates = await profileRepository.recordedUpdates()
        XCTAssertEqual(updates, [update])
    }

    func testManagerReferenceImportPreviewAndConfirmRefreshesIntelligence() async throws {
        let refreshedHome = IntelligenceHome.adminUsageReviewCleared
        let importRepository = RecordingReferenceImportRepository()
        let intelligenceRepository = RecordingIntelligenceRepository(home: refreshedHome)
        let services = makeServices(
            referenceImport: importRepository,
            intelligence: intelligenceRepository,
            isLiveSupabaseRuntime: true
        )
        let rawText = """
        @fitover60
        https://www.instagram.com/reel/ABC123/
        post-run family moment
        """

        let preview = await services.previewReferenceImportImmediately(
            rawText: rawText,
            inputType: .paste
        )

        XCTAssertEqual(preview?.previewChecksum, "fixture")
        XCTAssertEqual(services.referenceImportPreview?.counts.importable, 6)
        XCTAssertNil(services.lastReferenceImportError)

        let result = await services.confirmReferenceImportImmediately(
            rawText: rawText,
            inputType: .paste,
            previewChecksum: "fixture"
        )

        XCTAssertEqual(result?.counts.imported, 5)
        XCTAssertEqual(result?.counts.needsReview, 1)
        XCTAssertEqual(services.referenceImportConfirmResult?.toast, "Imported 5. 1 needs review.")
        XCTAssertEqual(services.referenceImportToast, "Imported 5. 1 needs review.")
        XCTAssertEqual(services.lastActionMessage, "Imported 5. 1 needs review.")
        XCTAssertEqual(services.intelligenceHome, refreshedHome)
        XCTAssertNil(services.lastReferenceImportError)

        let previewRequests = await importRepository.recordedPreviewRequests()
        XCTAssertEqual(previewRequests.map(\.rawText), [rawText])
        XCTAssertEqual(previewRequests.map(\.inputType), [.paste])

        let confirmRequests = await importRepository.recordedConfirmRequests()
        XCTAssertEqual(confirmRequests.map(\.previewChecksum), ["fixture"])
        let homeCallCount = await intelligenceRepository.homeCallCount()
        XCTAssertEqual(homeCallCount, 1)
    }

    func testManagerReviewsNeedsYourCallItemAndHomeRefreshes() async throws {
        let reviewItemID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        let importRepository = RecordingReferenceImportRepository()
        let intelligenceRepository = RecordingIntelligenceRepository(home: .adminUsageReviewCleared)
        let services = makeServices(
            referenceImport: importRepository,
            intelligence: intelligenceRepository,
            isLiveSupabaseRuntime: true
        )
        let edit = ReferenceReviewEdit(
            targetType: .reel,
            handle: nil,
            url: "https://www.instagram.com/reel/ABC123/",
            notes: "Good race-week pattern."
        )

        let result = await services.reviewReferenceItemImmediately(
            ReferenceReviewRequest(
                item: ReferenceReviewItem(kind: .sourceReference, id: reviewItemID),
                action: .edit,
                edit: edit
            )
        )

        XCTAssertEqual(result?.itemID, reviewItemID)
        XCTAssertEqual(result?.action, .edit)
        XCTAssertEqual(result?.resultStatus, "confirmed")
        XCTAssertEqual(services.referenceReviewResult?.toast, "Reference confirmed.")
        XCTAssertEqual(services.referenceImportToast, "Reference confirmed.")
        XCTAssertEqual(services.lastActionMessage, "Reference confirmed.")
        XCTAssertEqual(services.intelligenceHome.needsReview, [])
        XCTAssertNil(services.lastReferenceImportError)

        let reviewRequests = await importRepository.recordedReviewRequests()
        XCTAssertEqual(reviewRequests.map(\.item.id), [reviewItemID])
        XCTAssertEqual(reviewRequests.map(\.action), [.edit])
        XCTAssertEqual(reviewRequests.map(\.edit), [edit])
        let homeCallCount = await intelligenceRepository.homeCallCount()
        XCTAssertEqual(homeCallCount, 1)
    }

    private func makeServices(
        weeklyPlans: any WeeklyPlanRepository = RecordingWeeklyPlanRepository(),
        referenceImport: any ReferenceImportRepository = RecordingReferenceImportRepository(),
        intelligence: any IntelligenceRepository = FixtureIntelligenceRepository(),
        creatorProfile: any CreatorProfileRepository = FixtureCreatorProfileRepository(),
        isLiveSupabaseRuntime: Bool = false
    ) -> AppServices {
        let repositories = AppRepositories(
            context: .creatorFixture,
            today: FixtureTodayCardRepository(),
            weeklyPlans: weeklyPlans,
            references: FixtureReferenceRepository(),
            referenceImport: referenceImport,
            intelligence: intelligence,
            creatorProfile: creatorProfile,
            archive: FixtureArchiveRepository()
        )

        return AppServices.fixtureBacked(
            repositories: repositories,
            isLiveSupabaseRuntime: isLiveSupabaseRuntime,
            todayCache: AdminUsageMemoryTodayCacheStore(),
            notifications: NoopTodayNotificationScheduler()
        )
    }
}

private struct SelectionRequest: Hashable, Sendable {
    var ideaID: UUID
    var weeklyPlanID: UUID
}

private actor RecordingWeeklyPlanRepository: WeeklyPlanRepository {
    private var plan: WeeklyPlan
    private var ideas: [WeeklyIdea]
    private var selectionRequests: [SelectionRequest] = []
    private var setupRequests: [[WeeklySetupSection]] = []
    private var briefRequests: [String] = []
    private let selectionError: Error?
    private let setupError: Error?
    private let briefError: Error?

    init(
        plan: WeeklyPlan = .raceWeek,
        ideas: [WeeklyIdea] = WeeklyIdea.raceWeekBank,
        selectionError: Error? = nil,
        setupError: Error? = nil,
        briefError: Error? = nil
    ) {
        self.plan = plan
        self.ideas = ideas
        self.selectionError = selectionError
        self.setupError = setupError
        self.briefError = briefError
    }

    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan {
        plan
    }

    func currentGeneratedDraft(for context: WorkspaceContext) async throws -> GeneratedWeekDraft? {
        nil
    }

    func ideaBank(for context: WorkspaceContext) async throws -> [WeeklyIdea] {
        ideas
    }

    func publishWeek(
        _ plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        generatedDraft: GeneratedWeekDraft?,
        context: WorkspaceContext
    ) async throws -> WeeklyPublishResult {
        let publishedPlan = plan.softLockedForPublish
        let cards = DailyCard.publishedCards(from: publishedPlan)
        self.plan = publishedPlan
        self.ideas = ideaBank

        return WeeklyPublishResult(
            weeklyPlan: publishedPlan,
            weekCards: cards,
            todayCard: DailyCard.bestTodayCard(from: cards),
            summary: "Published \(cards.count) cards to Creator Today."
        )
    }

    func selectIdeaForNextOpenDay(
        _ idea: WeeklyIdea,
        in plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        context: WorkspaceContext
    ) async throws -> WeeklySelectionUpdate {
        selectionRequests.append(
            SelectionRequest(ideaID: idea.id, weeklyPlanID: plan.id)
        )

        if let selectionError {
            throw selectionError
        }

        let update = Self.applySelection(idea, in: plan, ideaBank: ideaBank)
        self.plan = update.weeklyPlan
        self.ideas = update.ideaBank
        return update
    }

    func recordedSelectionRequests() -> [SelectionRequest] {
        selectionRequests
    }

    func updateWeeklySetupSections(
        _ sections: [WeeklySetupSection],
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        setupRequests.append(sections)

        if let setupError {
            throw setupError
        }

        var updatedPlan = plan
        updatedPlan.setupSections = sections
        self.plan = updatedPlan
        return updatedPlan
    }

    func recordedSetupRequests() -> [[WeeklySetupSection]] {
        setupRequests
    }

    func updateWeeklyBrief(
        _ text: String,
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        briefRequests.append(text)

        if let briefError {
            throw briefError
        }

        var updatedPlan = plan
        updatedPlan.weeklyBriefText = text
        self.plan = updatedPlan
        return updatedPlan
    }

    func recordedBriefRequests() -> [String] {
        briefRequests
    }

    private static func applySelection(
        _ idea: WeeklyIdea,
        in plan: WeeklyPlan,
        ideaBank: [WeeklyIdea]
    ) -> WeeklySelectionUpdate {
        var updatedPlan = plan
        var updatedIdeaBank = ideaBank

        guard
            let ideaIndex = updatedIdeaBank.firstIndex(where: { $0.id == idea.id }),
            let dayIndex = updatedPlan.days.firstIndex(where: { $0.state == .open })
        else {
            return WeeklySelectionUpdate(weeklyPlan: updatedPlan, ideaBank: updatedIdeaBank)
        }

        updatedPlan.days[dayIndex].title = idea.title
        updatedPlan.days[dayIndex].reason = idea.reason
        updatedPlan.days[dayIndex].source = idea.source
        updatedPlan.days[dayIndex].state = .planned
        updatedPlan.days[dayIndex].isSoftLocked = false
        updatedIdeaBank[ideaIndex].selectedDay = updatedPlan.days[dayIndex].weekday

        return WeeklySelectionUpdate(weeklyPlan: updatedPlan, ideaBank: updatedIdeaBank)
    }
}

private actor RecordingCreatorProfileRepository: CreatorProfileRepository {
    private var summary: CreatorProfileSummary
    private var updates: [CreatorProfileUpdate] = []
    private let error: Error?

    init(
        summary: CreatorProfileSummary = .creatorFixture,
        error: Error? = nil
    ) {
        self.summary = summary
        self.error = error
    }

    func activeProfileSummary(for context: WorkspaceContext) async throws -> CreatorProfileSummary {
        summary
    }

    func updateProfile(_ update: CreatorProfileUpdate, context: WorkspaceContext) async throws -> CreatorProfileSummary {
        updates.append(update)

        if let error {
            throw error
        }

        summary = CreatorProfileSummary(
            displayName: summary.displayName,
            positioning: update.positioning,
            voiceLine: update.voiceRules.joined(separator: ", "),
            noGoTopics: update.noGoTopics,
            voiceRules: update.voiceRules,
            contentPillars: update.contentPillars,
            captionStyle: update.captionStyle,
            recurringFormats: update.recurringFormats
        )
        return summary
    }

    func recordedUpdates() -> [CreatorProfileUpdate] {
        updates
    }
}

private struct PreviewRequest: Hashable, Sendable {
    var rawText: String
    var inputType: ReferenceImportInputType
    var filename: String?
}

private struct ConfirmRequest: Hashable, Sendable {
    var rawText: String
    var inputType: ReferenceImportInputType
    var filename: String?
    var previewChecksum: String
}

private actor RecordingReferenceImportRepository: ReferenceImportRepository {
    private var previewRequests: [PreviewRequest] = []
    private var confirmRequests: [ConfirmRequest] = []
    private var reviewRequests: [ReferenceReviewRequest] = []

    func previewImport(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String?,
        context: WorkspaceContext
    ) async throws -> ReferenceImportPreview {
        previewRequests.append(
            PreviewRequest(rawText: rawText, inputType: inputType, filename: filename)
        )
        return .referenceImportFixture
    }

    func confirmImport(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String?,
        previewChecksum: String,
        context: WorkspaceContext
    ) async throws -> ReferenceImportConfirmResult {
        confirmRequests.append(
            ConfirmRequest(
                rawText: rawText,
                inputType: inputType,
                filename: filename,
                previewChecksum: previewChecksum
            )
        )
        return ReferenceImportConfirmResult(
            parserVersion: "v1",
            destination: ReferenceImportDestination(watchlistID: nil, watchlistName: "Inspiration"),
            counts: ReferenceImportConfirmCounts(
                imported: 5,
                needsReview: 1,
                duplicatesSkipped: 1,
                invalid: 1
            ),
            toast: "Imported 5. 1 needs review."
        )
    }

    func reviewItem(
        _ request: ReferenceReviewRequest,
        context: WorkspaceContext
    ) async throws -> ReferenceReviewResult {
        reviewRequests.append(request)
        return ReferenceReviewResult(
            itemID: request.item.id,
            kind: request.item.kind,
            action: request.action,
            resultStatus: "confirmed",
            toast: "Reference confirmed."
        )
    }

    func recordedPreviewRequests() -> [PreviewRequest] {
        previewRequests
    }

    func recordedConfirmRequests() -> [ConfirmRequest] {
        confirmRequests
    }

    func recordedReviewRequests() -> [ReferenceReviewRequest] {
        reviewRequests
    }
}

private actor RecordingIntelligenceRepository: IntelligenceRepository {
    private let home: IntelligenceHome
    private var calls = 0

    init(home: IntelligenceHome) {
        self.home = home
    }

    func home(for context: WorkspaceContext) async throws -> IntelligenceHome {
        calls += 1
        return home
    }

    func homeCallCount() -> Int {
        calls
    }
}

private final class AdminUsageMemoryTodayCacheStore: TodayCacheStoring {
    private var snapshots: [WorkspaceContext: CachedTodaySnapshot] = [:]

    func loadSnapshot(for context: WorkspaceContext) throws -> CachedTodaySnapshot? {
        snapshots[context]
    }

    func saveSnapshot(_ snapshot: CachedTodaySnapshot, for context: WorkspaceContext) throws {
        snapshots[context] = snapshot
    }

    func clearSnapshot(for context: WorkspaceContext) throws {
        snapshots[context] = nil
    }
}

private extension IntelligenceHome {
    static var adminUsageReviewCleared: IntelligenceHome {
        IntelligenceHome(
            sourcePulse: SourcePulseSummary(
                title: "Source Pulse",
                subtitle: "1 confirmed reel/audio reference.",
                references: [
                    ReferenceSummary(
                        title: "Race week warmup reel",
                        sourceType: "Reel link",
                        note: "Confirmed",
                        state: .approved,
                        symbol: "link",
                        sourceURL: "https://www.instagram.com/reel/ABC123/"
                    )
                ]
            ),
            readyForThisWeek: IntelligenceHome.raceWeekLibrary.readyForThisWeek,
            needsReview: [],
            ideaCandidates: IntelligenceHome.raceWeekLibrary.ideaCandidates,
            recentlyUsed: IntelligenceHome.raceWeekLibrary.recentlyUsed,
            librarySections: IntelligenceHome.raceWeekLibrary.librarySections
        )
    }
}
