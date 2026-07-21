import XCTest
@testable import CreatorContentOS

/// Day package lifecycle: draft → ready package via Available on Today,
/// and Today visibility for device-local today only.
@MainActor
final class DayAvailabilityTests: XCTestCase {
    func testMakeDayAvailablePromotesDraftForLocalTodayWithoutSoftLockingWeek() async throws {
        let today = "2026-07-21"
        let draft = makeDraftCard(scheduledDate: today, title: "Today ready package")
        let store = FixturePublishedContentStore()
        let weekly = DayAvailabilityWeeklyPlanRepository(
            publishedStore: store,
            localToday: today,
            weekIsSoftLockedAfterAvailable: false
        )
        let todayRepo = DayAvailabilityTodayCardRepository(store: store, localToday: today)
        let repositories = AppRepositories(
            context: .creatorFixture,
            today: todayRepo,
            weeklyPlans: weekly,
            references: FixtureReferenceRepository(),
            intelligence: FixtureIntelligenceRepository(),
            creatorProfile: FixtureCreatorProfileRepository(),
            archive: FixtureArchiveRepository()
        )
        let services = AppServices.fixtureBacked(
            repositories: repositories,
            todayCache: DayAvailabilityMemoryCacheStore(),
            todayDate: { today }
        )
        services.todayContentState = .missingPublishedCard(date: today)
        services.dayBriefGeneratedCards[today] = draft

        let shouldOpenToday = try await services.makeDayAvailable(scheduledDate: today)

        XCTAssertTrue(shouldOpenToday)
        XCTAssertEqual(services.todayCard.title, "Today ready package")
        XCTAssertEqual(services.todayContentState, .ready)
        XCTAssertEqual(services.dayBriefGeneratedCards[today]?.status, "published")
        XCTAssertFalse(services.weeklyPlan.isSoftLocked)
        XCTAssertNil(services.lastMakeDayAvailableError)
        let weekSoftLocked = await weekly.weekWasSoftLocked()
        XCTAssertEqual(weekSoftLocked, false)
    }

    func testMakeDayAvailableForFutureDateDoesNotBecomeTodayCard() async throws {
        let today = "2026-07-21"
        let tomorrow = "2026-07-22"
        let draft = makeDraftCard(scheduledDate: tomorrow, title: "Tomorrow ready package")
        let store = FixturePublishedContentStore()
        let weekly = DayAvailabilityWeeklyPlanRepository(
            publishedStore: store,
            localToday: today
        )
        let todayRepo = DayAvailabilityTodayCardRepository(store: store, localToday: today)
        let repositories = AppRepositories(
            context: .creatorFixture,
            today: todayRepo,
            weeklyPlans: weekly,
            references: FixtureReferenceRepository(),
            intelligence: FixtureIntelligenceRepository(),
            creatorProfile: FixtureCreatorProfileRepository(),
            archive: FixtureArchiveRepository()
        )
        let services = AppServices.fixtureBacked(
            repositories: repositories,
            todayCache: DayAvailabilityMemoryCacheStore(),
            todayDate: { today }
        )
        services.todayContentState = .missingPublishedCard(date: today)
        let placeholderToday = services.todayCard
        services.dayBriefGeneratedCards[tomorrow] = draft

        let shouldOpenToday = try await services.makeDayAvailable(scheduledDate: tomorrow)

        XCTAssertFalse(shouldOpenToday)
        XCTAssertEqual(services.todayCard.id, placeholderToday.id)
        XCTAssertEqual(services.todayContentState, .missingPublishedCard(date: today))
        XCTAssertEqual(services.dayBriefGeneratedCards[tomorrow]?.status, "published")

        // Today repository still has no local-today ready package.
        do {
            _ = try await todayRepo.todayCard(for: .creatorFixture)
            XCTFail("Expected no published today card for a future-only ready package")
        } catch RepositoryError.noPublishedTodayCard(let date) {
            XCTAssertEqual(date, today)
        }
    }

    func testMakeDayAvailableFailureSurfacesErrorAndLeavesTodayUnchanged() async {
        let today = "2026-07-21"
        let draft = makeDraftCard(scheduledDate: today, title: "Draft that will fail")
        let weekly = FailingMakeDayAvailableWeeklyPlanRepository()
        let repositories = AppRepositories(
            context: .creatorFixture,
            today: FixtureTodayCardRepository(),
            weeklyPlans: weekly,
            references: FixtureReferenceRepository(),
            intelligence: FixtureIntelligenceRepository(),
            creatorProfile: FixtureCreatorProfileRepository(),
            archive: FixtureArchiveRepository()
        )
        let services = AppServices.fixtureBacked(
            repositories: repositories,
            todayCache: DayAvailabilityMemoryCacheStore(),
            todayDate: { today }
        )
        let beforeCard = services.todayCard
        services.dayBriefGeneratedCards[today] = draft

        do {
            _ = try await services.makeDayAvailable(scheduledDate: today)
            XCTFail("Expected makeDayAvailable to throw")
        } catch {
            XCTAssertEqual(
                services.lastMakeDayAvailableError,
                "No draft was found for that day. Generate a draft first."
            )
            XCTAssertEqual(services.todayCard.id, beforeCard.id)
            XCTAssertEqual(services.dayBriefGeneratedCards[today]?.status, "draft")
        }
    }
}

// MARK: - Helpers

private func makeDraftCard(scheduledDate: String, title: String) -> GeneratedDailyCardDraft {
    GeneratedDailyCardDraft(
        id: UUID(),
        scheduledDate: scheduledDate,
        status: "draft",
        title: title,
        whyToday: "Ready package path test.",
        growthJob: "Build consistency.",
        contentPillar: "lifestyle",
        shootability: "easy",
        estimatedShootMinutes: 12,
        energyRequired: "medium",
        languageMode: "English",
        sceneList: [
            ShotScene(number: 1, title: "Opening", duration: "3 sec", symbol: "sparkles")
        ],
        script: "One steady line.",
        noVoiceoverVersion: "Quiet clips.",
        onScreenText: ["Simple"],
        caption: "Keeping it simple.",
        cta: "Save this.",
        hashtags: ["test"],
        coverText: "Cover",
        postInstructions: "Calm audio.",
        brandEventNotes: "",
        backupStory: "Backup story.",
        backupCaptionOnly: "Caption only.",
        audioOptionNotes: "Calm audio.",
        creatorFitScore: 90,
        riskNotes: [],
        assumptions: [],
        sourceNote: "Day availability test"
    )
}

private actor DayAvailabilityWeeklyPlanRepository: WeeklyPlanRepository {
    private let publishedStore: FixturePublishedContentStore
    private let localToday: String
    private var lastWeekIsSoftLocked: Bool?
    private let weekIsSoftLockedAfterAvailable: Bool
    private var plan: WeeklyPlan

    init(
        publishedStore: FixturePublishedContentStore,
        localToday: String,
        weekIsSoftLockedAfterAvailable: Bool = false,
        plan: WeeklyPlan = .raceWeek
    ) {
        self.publishedStore = publishedStore
        self.localToday = localToday
        self.weekIsSoftLockedAfterAvailable = weekIsSoftLockedAfterAvailable
        self.plan = plan
    }

    func weekWasSoftLocked() -> Bool? {
        lastWeekIsSoftLocked
    }

    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan {
        plan
    }

    func currentGeneratedDraft(for context: WorkspaceContext) async throws -> GeneratedWeekDraft? {
        nil
    }

    func ideaBank(for context: WorkspaceContext) async throws -> [WeeklyIdea] {
        []
    }

    func currentWeeklyContent(for context: WorkspaceContext) async throws -> WeeklyRepositoryContent {
        WeeklyRepositoryContent(publishedPlan: plan, generatedDraft: nil, ideaBank: [])
    }

    func publishWeek(
        _ plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        generatedDraft: GeneratedWeekDraft?,
        context: WorkspaceContext
    ) async throws -> WeeklyPublishResult {
        throw RepositoryError.notConfigured("publish_week_not_used")
    }

    func selectIdeaForNextOpenDay(
        _ idea: WeeklyIdea,
        in plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        context: WorkspaceContext
    ) async throws -> WeeklySelectionUpdate {
        WeeklySelectionUpdate(weeklyPlan: plan, ideaBank: ideaBank)
    }

    func updateWeeklySetupSections(
        _ sections: [WeeklySetupSection],
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        plan
    }

    func updateWeeklyBrief(
        _ text: String,
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        plan
    }

    func makeDayAvailable(
        scheduledDate: String,
        dailyCardID: UUID?,
        context: WorkspaceContext
    ) async throws -> DayAvailabilityResult {
        let cardID = dailyCardID ?? UUID()
        let readyCard = DailyCard(
            id: cardID,
            title: scheduledDate == localToday ? "Today ready package" : "Tomorrow ready package",
            context: SupabaseDateFormatting.contextLine(for: scheduledDate),
            effortLabel: "Easy - 12 min",
            whyToday: "Available on Today from draft.",
            scheduledDate: scheduledDate,
            scenes: [
                ShotScene(number: 1, title: "Opening", duration: "3 sec", symbol: "sparkles")
            ]
        )

        var cards = await publishedStore.readWeekCards()
        cards.removeAll { $0.scheduledDate == scheduledDate }
        cards.append(readyCard)
        let todayCard = cards.first { $0.scheduledDate == localToday }
        await publishedStore.savePublishedContent(cards: cards, todayCard: todayCard)

        lastWeekIsSoftLocked = weekIsSoftLockedAfterAvailable
        return DayAvailabilityResult(
            dailyCardID: cardID,
            scheduledDate: scheduledDate,
            status: "published",
            weeklyPlanID: plan.id,
            weekIsSoftLocked: weekIsSoftLockedAfterAvailable
        )
    }
}

private struct DayAvailabilityTodayCardRepository: TodayCardRepository {
    let store: FixturePublishedContentStore
    let localToday: String

    func todayCard(for context: WorkspaceContext) async throws -> DailyCard {
        if let card = await store.readTodayCard(), card.scheduledDate == localToday {
            return card
        }
        throw RepositoryError.noPublishedTodayCard(date: localToday)
    }

    func weekCards(for context: WorkspaceContext) async throws -> [DailyCard] {
        await store.readWeekCards()
    }

    func completeToday(
        card: DailyCard,
        decision: DailyDecision,
        context: WorkspaceContext
    ) async throws -> ArchiveEntry {
        ArchiveEntry(
            dailyCardID: card.id,
            day: "TODAY",
            date: card.scheduledDate ?? "",
            cardTitle: card.title,
            decision: decision.completionState,
            outputLine: decision.outputLine,
            hasPostThumbnail: decision.hasPostThumbnail
        )
    }
}

private actor FailingMakeDayAvailableWeeklyPlanRepository: WeeklyPlanRepository {
    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan {
        .raceWeek
    }

    func currentGeneratedDraft(for context: WorkspaceContext) async throws -> GeneratedWeekDraft? {
        nil
    }

    func ideaBank(for context: WorkspaceContext) async throws -> [WeeklyIdea] {
        []
    }

    func currentWeeklyContent(for context: WorkspaceContext) async throws -> WeeklyRepositoryContent {
        WeeklyRepositoryContent(publishedPlan: .raceWeek, generatedDraft: nil, ideaBank: [])
    }

    func publishWeek(
        _ plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        generatedDraft: GeneratedWeekDraft?,
        context: WorkspaceContext
    ) async throws -> WeeklyPublishResult {
        throw RepositoryError.notConfigured("publish_week_not_used")
    }

    func selectIdeaForNextOpenDay(
        _ idea: WeeklyIdea,
        in plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        context: WorkspaceContext
    ) async throws -> WeeklySelectionUpdate {
        WeeklySelectionUpdate(weeklyPlan: plan, ideaBank: ideaBank)
    }

    func updateWeeklySetupSections(
        _ sections: [WeeklySetupSection],
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        plan
    }

    func updateWeeklyBrief(
        _ text: String,
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        plan
    }

    func makeDayAvailable(
        scheduledDate: String,
        dailyCardID: UUID?,
        context: WorkspaceContext
    ) async throws -> DayAvailabilityResult {
        throw RepositoryError.edgeFunction("daily_card_not_found")
    }
}

private final class DayAvailabilityMemoryCacheStore: TodayCacheStoring {
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
