import XCTest
@testable import CreatorContentOS

/// Plan hub behavior: calendar state meanings, generate overwrite gate,
/// Available → Today signal, Unpublish demotion for calendar dots.
@MainActor
final class PlanHubTests: XCTestCase {
    func testCalendarStateMeaningsForPackageStatuses() {
        XCTAssertEqual(PlanCalendarDayState.from(packageStatus: nil), .empty)
        XCTAssertEqual(PlanCalendarDayState.from(packageStatus: ""), .empty)
        XCTAssertEqual(PlanCalendarDayState.from(packageStatus: "draft"), .draft)
        XCTAssertEqual(PlanCalendarDayState.from(packageStatus: "open"), .draft)
        XCTAssertEqual(PlanCalendarDayState.from(packageStatus: "ready"), .draft)
        XCTAssertEqual(PlanCalendarDayState.from(packageStatus: "backup"), .draft)
        XCTAssertEqual(PlanCalendarDayState.from(packageStatus: "published"), .ready)
        XCTAssertEqual(PlanCalendarDayState.from(packageStatus: "posted"), .ready)
        XCTAssertEqual(PlanCalendarDayState.from(packageStatus: "in_decision"), .ready)
        XCTAssertEqual(PlanCalendarDayState.from(packageStatus: "shot"), .ready)
        XCTAssertEqual(PlanCalendarDayState.from(packageStatus: "used_backup"), .ready)
        XCTAssertEqual(PlanCalendarDayState.from(packageStatus: "saved_for_tomorrow"), .ready)
        XCTAssertEqual(PlanCalendarDayState.from(packageStatus: "skipped_intentionally"), .ready)
        XCTAssertEqual(PlanCalendarDayState.from(packageStatus: "unknown"), .empty)
    }

    func testDayPackagePrefersSessionCardThenDraftSummary() {
        let today = "2026-07-21"
        let sessionDraft = makePlanCard(scheduledDate: today, title: "Session", status: "draft")
        let summaryReady = makePlanCard(scheduledDate: today, title: "Summary", status: "published")
        let otherDate = makePlanCard(scheduledDate: "2026-07-22", title: "Other", status: "published")

        let services = AppServices.fixtureBacked(memberRole: "creator", todayDate: { today })
        services.dayBriefGeneratedCards[today] = sessionDraft
        services.latestGenerationSummary = GeneratedWeekDraft(
            id: UUID(),
            weeklyPlanID: UUID(),
            strategySummary: "Plan hub",
            warnings: [],
            assumptions: [],
            dailyCards: [summaryReady, otherDate],
            ideaBank: [],
            sourceSummary: "Fixture",
            generatedAt: "2026-07-21T00:00:00Z"
        )

        XCTAssertEqual(services.dayPackage(for: today)?.title, "Session")
        XCTAssertEqual(
            PlanCalendarDayState.from(packageStatus: services.dayPackage(for: today)?.status),
            .draft
        )

        services.dayBriefGeneratedCards.removeValue(forKey: today)
        XCTAssertEqual(services.dayPackage(for: today)?.title, "Summary")
        XCTAssertEqual(
            PlanCalendarDayState.from(packageStatus: services.dayPackage(for: today)?.status),
            .ready
        )
        XCTAssertEqual(
            PlanCalendarDayState.from(packageStatus: services.dayPackage(for: "2026-07-22")?.status),
            .ready
        )
        XCTAssertNil(services.dayPackage(for: "2026-07-23"))
        XCTAssertEqual(
            PlanCalendarDayState.from(packageStatus: services.dayPackage(for: "2026-07-23")?.status),
            .empty
        )
    }

    func testGenerateOnReadyRequiresOverwriteThenYieldsDraftCalendarState() async throws {
        let today = "2026-07-21"
        let ready = makePlanCard(scheduledDate: today, title: "Ready", status: "published")
        let store = FixturePublishedContentStore()
        let weekly = PlanHubWeeklyPlanRepository(publishedStore: store, localToday: today)
        await weekly.seedReadyCard(ready.dailyCard(completionState: nil))
        let generation = PlanHubDayGenerationStub()
        let repositories = AppRepositories(
            context: .creatorFixture,
            today: PlanHubTodayCardRepository(store: store, localToday: today),
            weeklyPlans: weekly,
            references: FixtureReferenceRepository(),
            dailyGeneration: generation,
            intelligence: FixtureIntelligenceRepository(),
            creatorProfile: FixtureCreatorProfileRepository(),
            archive: FixtureArchiveRepository()
        )
        let services = AppServices.fixtureBacked(
            repositories: repositories,
            memberRole: "creator",
            todayCache: PlanHubMemoryCacheStore(),
            todayDate: { today }
        )
        services.dayBriefGeneratedCards[today] = ready

        do {
            _ = try await services.generateDayCard(
                scheduledDate: today,
                dayBrief: "Overwrite attempt without confirmation."
            )
            XCTFail("Expected overwrite confirmation requirement")
        } catch {
            XCTAssertEqual(services.pendingOverwriteGenerateDate, today)
            XCTAssertEqual(
                PlanCalendarDayState.from(packageStatus: services.dayBriefGeneratedCards[today]?.status),
                .ready
            )
        }

        let overwritten = try await services.generateDayCard(
            scheduledDate: today,
            dayBrief: "Confirmed overwrite.",
            confirmOverwrite: true
        )
        XCTAssertEqual(overwritten.status, "draft")
        XCTAssertEqual(
            PlanCalendarDayState.from(packageStatus: services.dayBriefGeneratedCards[today]?.status),
            .draft
        )
    }

    func testAvailableOnTodayForLocalTodayReturnsNavigateSignalAndReadyDot() async throws {
        let today = "2026-07-21"
        let draft = makePlanCard(scheduledDate: today, title: "Draft ready to publish", status: "draft")
        let store = FixturePublishedContentStore()
        let weekly = PlanHubWeeklyPlanRepository(publishedStore: store, localToday: today)
        let repositories = AppRepositories(
            context: .creatorFixture,
            today: PlanHubTodayCardRepository(store: store, localToday: today),
            weeklyPlans: weekly,
            references: FixtureReferenceRepository(),
            intelligence: FixtureIntelligenceRepository(),
            creatorProfile: FixtureCreatorProfileRepository(),
            archive: FixtureArchiveRepository()
        )
        let services = AppServices.fixtureBacked(
            repositories: repositories,
            memberRole: "creator",
            todayCache: PlanHubMemoryCacheStore(),
            todayDate: { today }
        )
        services.dayBriefGeneratedCards[today] = draft

        let shouldOpenToday = try await services.makeDayAvailable(scheduledDate: today)

        XCTAssertTrue(shouldOpenToday)
        XCTAssertEqual(services.dayBriefGeneratedCards[today]?.status, "published")
        XCTAssertEqual(
            PlanCalendarDayState.from(packageStatus: services.dayBriefGeneratedCards[today]?.status),
            .ready
        )

        let appState = AppState(runtime: .fixtures(), authenticationPhase: .live)
        appState.requestCreatorTab(.today)
        XCTAssertEqual(appState.pendingCreatorTab, .today)
    }

    func testUnpublishReadyDayReturnsDraftCalendarState() async throws {
        let today = "2026-07-21"
        let ready = makePlanCard(scheduledDate: today, title: "Ready", status: "published")
        let store = FixturePublishedContentStore()
        let weekly = PlanHubWeeklyPlanRepository(publishedStore: store, localToday: today)
        await weekly.seedReadyCard(ready.dailyCard(completionState: nil))
        let repositories = AppRepositories(
            context: .creatorFixture,
            today: PlanHubTodayCardRepository(store: store, localToday: today),
            weeklyPlans: weekly,
            references: FixtureReferenceRepository(),
            intelligence: FixtureIntelligenceRepository(),
            creatorProfile: FixtureCreatorProfileRepository(),
            archive: FixtureArchiveRepository()
        )
        let services = AppServices.fixtureBacked(
            repositories: repositories,
            memberRole: "creator",
            todayCache: PlanHubMemoryCacheStore(),
            todayDate: { today }
        )
        services.dayBriefGeneratedCards[today] = ready
        services.todayCard = ready.dailyCard(completionState: nil)
        services.todayContentState = TodayContentState.ready

        _ = try await services.unpublishDay(scheduledDate: today)

        XCTAssertEqual(services.dayBriefGeneratedCards[today]?.status, "draft")
        XCTAssertEqual(
            PlanCalendarDayState.from(packageStatus: services.dayBriefGeneratedCards[today]?.status),
            .draft
        )
    }
}

// MARK: - Helpers

private func makePlanCard(
    scheduledDate: String,
    title: String,
    status: String
) -> GeneratedDailyCardDraft {
    GeneratedDailyCardDraft(
        id: UUID(),
        scheduledDate: scheduledDate,
        status: status,
        title: title,
        whyToday: "Plan hub test.",
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
        sourceNote: "Plan hub fixture."
    )
}

private struct PlanHubDayGenerationStub: DayGenerationRepository {
    func generateDay(
        creatorID: UUID,
        scheduledDate: String,
        dayBrief: String,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        DailyGenerationResult(
            generationID: UUID(),
            weeklyPlanID: WeeklyPlan.raceWeek.id,
            status: "draft",
            targetScheduledDate: scheduledDate,
            dailyCard: makePlanCard(
                scheduledDate: scheduledDate,
                title: "Generated: \(dayBrief)",
                status: "draft"
            ),
            warnings: [],
            assumptions: [],
            sourceSummary: "Plan hub stub",
            generatedAt: "2026-07-21T00:00:00Z"
        )
    }
}

private actor PlanHubWeeklyPlanRepository: WeeklyPlanRepository {
    private let publishedStore: FixturePublishedContentStore
    private let localToday: String
    private var plan: WeeklyPlan

    init(
        publishedStore: FixturePublishedContentStore,
        localToday: String,
        plan: WeeklyPlan = .raceWeek
    ) {
        self.publishedStore = publishedStore
        self.localToday = localToday
        self.plan = plan
    }

    func seedReadyCard(_ card: DailyCard) async {
        var cards = await publishedStore.readWeekCards()
        cards.removeAll { $0.scheduledDate == card.scheduledDate }
        cards.append(card)
        let todayCard = cards.first { $0.scheduledDate == localToday }
        await publishedStore.savePublishedContent(cards: cards, todayCard: todayCard)
    }

    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan { plan }
    func currentGeneratedDraft(for context: WorkspaceContext) async throws -> GeneratedWeekDraft? { nil }
    func ideaBank(for context: WorkspaceContext) async throws -> [WeeklyIdea] { [] }
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
    ) async throws -> WeeklyPlan { plan }

    func updateWeeklyBrief(
        _ text: String,
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan { plan }

    func makeDayAvailable(
        scheduledDate: String,
        dailyCardID: UUID?,
        context: WorkspaceContext
    ) async throws -> DayAvailabilityResult {
        let cardID = dailyCardID ?? UUID()
        let readyCard = DailyCard(
            id: cardID,
            title: "Ready package",
            context: SupabaseDateFormatting.contextLine(for: scheduledDate),
            effortLabel: "Easy - 10 min",
            whyToday: "Available on Today from Plan.",
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
        return DayAvailabilityResult(
            dailyCardID: cardID,
            scheduledDate: scheduledDate,
            status: "published",
            weeklyPlanID: plan.id,
            weekIsSoftLocked: false
        )
    }

    func unpublishDay(
        scheduledDate: String,
        dailyCardID: UUID?,
        context: WorkspaceContext
    ) async throws -> DayUnpublishResult {
        var cards = await publishedStore.readWeekCards()
        let existing = cards.first { card in
            if let dailyCardID { return card.id == dailyCardID }
            return card.scheduledDate == scheduledDate
        }
        let cardID = existing?.id ?? dailyCardID ?? UUID()
        cards.removeAll { $0.id == cardID || $0.scheduledDate == scheduledDate }
        let todayCard = cards.first { $0.scheduledDate == localToday }
        await publishedStore.savePublishedContent(cards: cards, todayCard: todayCard)
        return DayUnpublishResult(
            dailyCardID: cardID,
            scheduledDate: scheduledDate,
            status: "draft",
            previousStatus: "published",
            clearedLiveDecision: false,
            archiveRetained: true,
            weeklyPlanID: plan.id
        )
    }
}

private struct PlanHubTodayCardRepository: TodayCardRepository {
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

private final class PlanHubMemoryCacheStore: TodayCacheStoring {
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
