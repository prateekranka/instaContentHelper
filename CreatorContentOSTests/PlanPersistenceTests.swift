import XCTest
@testable import CreatorContentOS

/// Slice 5 — Plan date persistence and accepted-generation recovery without duplicate POST.
@MainActor
final class PlanPersistenceTests: XCTestCase {
    func testPlanSelectedDateStorePersistsAcrossInstances() {
        let defaults = UserDefaults(suiteName: "PlanPersistenceTests.planDate")!
        defaults.removePersistentDomain(forName: "PlanPersistenceTests.planDate")
        let store = UserDefaultsPlanSelectedDateStore(defaults: defaults)

        XCTAssertNil(store.load())
        store.save("2026-07-21")
        XCTAssertEqual(store.load(), "2026-07-21")

        let reloaded = UserDefaultsPlanSelectedDateStore(defaults: defaults)
        XCTAssertEqual(reloaded.load(), "2026-07-21")
    }

    func testAppStatePreparePlanPersistsSelectedDate() {
        let defaults = UserDefaults(suiteName: "PlanPersistenceTests.appState")!
        defaults.removePersistentDomain(forName: "PlanPersistenceTests.appState")
        let store = UserDefaultsPlanSelectedDateStore(defaults: defaults)
        let state = AppState(
            runtime: .fixtures(),
            authenticationPhase: .live,
            planSelectedDateStore: store
        )

        state.preparePlan(selecting: "2026-07-22")
        XCTAssertEqual(state.planSelectedDate, "2026-07-22")
        XCTAssertEqual(state.persistedPlanSelectedDate(), "2026-07-22")
    }

    func testReturnToPlanRestoresPersistedDateAfterConsume() {
        let defaults = UserDefaults(suiteName: "PlanPersistenceTests.return")!
        defaults.removePersistentDomain(forName: "PlanPersistenceTests.return")
        let store = UserDefaultsPlanSelectedDateStore(defaults: defaults)
        let state = AppState(
            runtime: .fixtures(),
            authenticationPhase: .live,
            planSelectedDateStore: store
        )

        state.preparePlan(selecting: "2026-07-21")
        _ = state.consumePlanSelectedDate()
        XCTAssertNil(state.planSelectedDate)
        XCTAssertEqual(state.persistedPlanSelectedDate(), "2026-07-21")

        state.returnToPlan(fromYouDestination: "2026-07-21")
        XCTAssertEqual(state.pendingCreatorTab, .plan)
        XCTAssertEqual(state.consumePlanSelectedDate(), "2026-07-21")
    }

    func testResumeAcceptedGenerationDoesNotCallGenerateDayPOST() async throws {
        let today = "2026-07-21"
        let generationID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let generation = ResumeOnlyDayGenerationRepository()
        let store = InMemoryAcceptedDayGenerationStore(
            runs: [
                AcceptedDayGenerationRun(
                    scheduledDate: today,
                    generationID: generationID,
                    creatorID: WorkspaceContext.creatorFixture.creatorID,
                    acceptedAt: Date()
                )
            ]
        )
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                dailyGeneration: generation,
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            memberRole: "creator",
            todayDate: { today },
            acceptedGenerationStore: store
        )

        let card = try await services.generateDayCard(
            scheduledDate: today,
            dayBrief: "Should resume, not POST."
        )

        XCTAssertEqual(generation.generateCallCount, 0)
        XCTAssertEqual(generation.resumeCallCount, 1)
        XCTAssertEqual(generation.lastResumeGenerationID, generationID)
        XCTAssertEqual(card.scheduledDate, today)
        XCTAssertNil(store.load(scheduledDate: today))
    }

    func testRestoreAcceptedGenerationsIfNeededResumesWithoutPOST() async {
        let today = "2026-07-21"
        let generationID = UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!
        let generation = ResumeOnlyDayGenerationRepository()
        let store = InMemoryAcceptedDayGenerationStore(
            runs: [
                AcceptedDayGenerationRun(
                    scheduledDate: today,
                    generationID: generationID,
                    creatorID: WorkspaceContext.creatorFixture.creatorID,
                    acceptedAt: Date()
                )
            ]
        )
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                dailyGeneration: generation,
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            memberRole: "creator",
            todayDate: { today },
            acceptedGenerationStore: store
        )

        services.restoreAcceptedDayGenerationsIfNeeded()
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(generation.generateCallCount, 0)
        XCTAssertEqual(generation.resumeCallCount, 1)
        XCTAssertTrue(services.generatingDayBriefDates.isEmpty)
        XCTAssertNil(store.load(scheduledDate: today))
    }

    func testUnpublishedDraftDoesNotAppearOnTodayAfterRefresh() async {
        let today = "2026-07-21"
        let draft = makePersistencePlanCard(scheduledDate: today, title: "Draft only", status: "draft")
        let services = AppServices.fixtureBacked(
            memberRole: "creator",
            todayDate: { today }
        )
        services.dayBriefGeneratedCards[today] = draft

        await services.refreshFromRepositoriesImmediately()

        if case .missingPublishedCard = services.todayContentState {
            // Expected when fixtures have no published card for today.
        } else if case .ready = services.todayContentState {
            XCTAssertNotEqual(services.todayCard.title, "Draft only")
        }
    }
}

// MARK: - Helpers

private func makePersistencePlanCard(
    scheduledDate: String,
    title: String,
    status: String
) -> GeneratedDailyCardDraft {
    GeneratedDailyCardDraft(
        id: UUID(),
        scheduledDate: scheduledDate,
        status: status,
        title: title,
        whyToday: "Persistence test.",
        growthJob: "Consistency.",
        contentPillar: "lifestyle",
        shootability: "easy",
        estimatedShootMinutes: 10,
        energyRequired: "low",
        languageMode: "English",
        sceneList: [
            ShotScene(number: 1, title: "Scene", duration: "3 sec", symbol: "sparkles")
        ],
        script: "Script.",
        noVoiceoverVersion: "No VO.",
        onScreenText: ["Plan"],
        caption: "Caption.",
        cta: "Save this.",
        hashtags: ["plan"],
        coverText: "Cover",
        postInstructions: "Post.",
        brandEventNotes: "",
        backupStory: "Backup.",
        backupCaptionOnly: "Caption backup.",
        audioOptionNotes: "",
        creatorFitScore: 90,
        riskNotes: [],
        assumptions: [],
        sourceNote: "Persistence fixture."
    )
}

private final class ResumeOnlyDayGenerationRepository: DayGenerationRepository, @unchecked Sendable {
    private(set) var generateCallCount = 0
    private(set) var resumeCallCount = 0
    private(set) var lastResumeGenerationID: UUID?

    func generateDay(
        creatorID: UUID,
        scheduledDate: String,
        dayBrief: String,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        generateCallCount += 1
        XCTFail("generateDay POST must not run during recovery")
        throw RepositoryError.notConfigured("must_not_post")
    }

    func resumeAcceptedDayGeneration(
        generationID: UUID,
        creatorID: UUID,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        resumeCallCount += 1
        lastResumeGenerationID = generationID
        return DailyGenerationResult(
            generationID: generationID,
            weeklyPlanID: WeeklyPlan.raceWeek.id,
            status: "draft",
            targetScheduledDate: "2026-07-21",
            dailyCard: makePersistencePlanCard(
                scheduledDate: "2026-07-21",
                title: "Resumed card",
                status: "draft"
            ),
            warnings: [],
            assumptions: [],
            sourceSummary: "Resume stub",
            generatedAt: "2026-07-21T00:00:00Z"
        )
    }
}

private final class InMemoryAcceptedDayGenerationStore: AcceptedDayGenerationStoring, @unchecked Sendable {
    private var runs: [AcceptedDayGenerationRun]

    init(runs: [AcceptedDayGenerationRun]) {
        self.runs = runs
    }

    func loadAll() -> [AcceptedDayGenerationRun] { runs }
    func load(scheduledDate: String) -> AcceptedDayGenerationRun? {
        runs.first { $0.scheduledDate == scheduledDate }
    }
    func save(_ run: AcceptedDayGenerationRun) {
        runs.removeAll { $0.scheduledDate == run.scheduledDate }
        runs.append(run)
    }
    func remove(scheduledDate: String) {
        runs.removeAll { $0.scheduledDate == scheduledDate }
    }
    func clear() { runs.removeAll() }
}
