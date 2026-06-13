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
        isLiveSupabaseRuntime: Bool = false
    ) -> AppServices {
        let repositories = AppRepositories(
            context: .creatorFixture,
            today: FixtureTodayCardRepository(),
            weeklyPlans: weeklyPlans,
            references: FixtureReferenceRepository(),
            referenceImport: referenceImport,
            intelligence: intelligence,
            creatorProfile: FixtureCreatorProfileRepository(),
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
    private let selectionError: Error?

    init(
        plan: WeeklyPlan = .raceWeek,
        ideas: [WeeklyIdea] = WeeklyIdea.raceWeekBank,
        selectionError: Error? = nil
    ) {
        self.plan = plan
        self.ideas = ideas
        self.selectionError = selectionError
    }

    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan {
        plan
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
