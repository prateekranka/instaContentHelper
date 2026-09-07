import XCTest
@testable import CreatorContentOS

/// Plan day generation dispatch: one POST per selection, duplicate protection, Other validation.
@MainActor
final class PlanDayGenerationDispatchTests: XCTestCase {
    func testIdeaSelectionDispatchesOneGenerationWithExactBrief() async throws {
        let today = "2026-07-21"
        let generation = CountingPlanDayGenerationRepository()
        let services = makeServices(today: today, generation: generation)
        let setup = PlanDaySetupSummary(
            contentPillars: ["gym"],
            voiceIsConfigured: true,
            confirmedReferenceCount: 1,
            totalReferenceCount: 1
        )
        let idea = PlanDayIdeaBuilder.buildIdeas(scheduledDate: today, setup: setup)[0]

        _ = try await services.generateDayCard(
            scheduledDate: today,
            dayBrief: idea.dayBrief
        )

        XCTAssertEqual(generation.callCount, 1)
        XCTAssertEqual(generation.lastBrief, idea.dayBrief)
        XCTAssertEqual(generation.lastScheduledDate, today)
    }

    func testOtherTextMustBeNonEmptyBeforeDispatch() async {
        let today = "2026-07-21"
        let generation = CountingPlanDayGenerationRepository()
        let services = makeServices(today: today, generation: generation)

        do {
            _ = try await services.generateDayCard(
                scheduledDate: today,
                dayBrief: "   "
            )
            XCTFail("Expected empty brief rejection")
        } catch {
            XCTAssertEqual(generation.callCount, 0)
            XCTAssertEqual(
                services.dayBriefGenerationErrors[today],
                "day_brief_required"
            )
        }
    }

    func testDuplicateDispatchRejectedWhileGenerationInFlight() async {
        let today = "2026-07-21"
        let generation = CountingPlanDayGenerationRepository()
        let services = makeServices(today: today, generation: generation)
        services.generatingDayBriefDates.insert(today)

        do {
            _ = try await services.generateDayCard(
                scheduledDate: today,
                dayBrief: "Second overlapping request."
            )
            XCTFail("Expected generation_already_running rejection")
        } catch {
            XCTAssertEqual(generation.callCount, 0)
        }
    }

    func testReadyPackageRequiresOverwriteBeforeSecondDispatch() async throws {
        let today = "2026-07-21"
        let ready = makeDispatchPlanCard(scheduledDate: today, title: "Ready", status: "published")
        let generation = CountingPlanDayGenerationRepository()
        let services = await makeServicesWithPublishedReadyCard(
            today: today,
            ready: ready,
            generation: generation
        )
        let setup = PlanDaySetupSummary(
            contentPillars: [],
            voiceIsConfigured: true,
            confirmedReferenceCount: 0,
            totalReferenceCount: 0
        )
        let idea = PlanDayIdeaBuilder.buildIdeas(scheduledDate: today, setup: setup)[1]

        do {
            _ = try await services.generateDayCard(
                scheduledDate: today,
                dayBrief: idea.dayBrief
            )
            XCTFail("Expected overwrite confirmation requirement")
        } catch {
            XCTAssertEqual(generation.callCount, 0)
            XCTAssertEqual(services.pendingOverwriteGenerateDate, today)
        }

        _ = try await services.generateDayCard(
            scheduledDate: today,
            dayBrief: idea.dayBrief,
            confirmOverwrite: true
        )

        XCTAssertEqual(generation.callCount, 1)
        XCTAssertEqual(generation.lastBrief, idea.dayBrief)
    }

    func testDraftPackageRequiresOverwriteConfirmation() async throws {
        let today = "2026-07-21"
        let draft = makeDispatchPlanCard(scheduledDate: today, title: "Draft", status: "draft")
        let generation = CountingPlanDayGenerationRepository()
        let services = makeServices(today: today, generation: generation)
        services.dayBriefGeneratedCards[today] = draft
        let brief = "Behind the routine. Fresh angle for today."

        // A draft must not be silently replaced — confirm first.
        do {
            _ = try await services.generateDayCard(
                scheduledDate: today,
                dayBrief: brief
            )
            XCTFail("Expected overwrite confirmation requirement for an existing draft")
        } catch {
            XCTAssertEqual(generation.callCount, 0)
            XCTAssertEqual(services.pendingOverwriteGenerateDate, today)
            XCTAssertEqual(services.dayBriefGeneratedCards[today]?.title, "Draft",
                           "The draft must not be replaced without confirmation")
        }

        _ = try await services.generateDayCard(
            scheduledDate: today,
            dayBrief: brief,
            confirmOverwrite: true
        )

        XCTAssertEqual(generation.callCount, 1)
        XCTAssertEqual(generation.lastBrief, brief)
        XCTAssertNil(services.pendingOverwriteGenerateDate)
    }

    func testDefaultFixtureRepositoriesGenerateDayDraft() async throws {
        let today = "2026-08-09"
        let brief = "Behind the routine. Fixture path must not throw generate_day_not_configured."
        let generation = FixtureDayGenerationRepository(artificialDelayNanoseconds: 0)
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
            todayDate: { today }
        )

        let card = try await services.generateDayCard(
            scheduledDate: today,
            dayBrief: brief
        )

        XCTAssertEqual(card.scheduledDate, today)
        XCTAssertEqual(card.status, "draft")
        XCTAssertEqual(card.whyToday, brief)
        XCTAssertNil(services.dayBriefGenerationErrors[today])
        XCTAssertEqual(services.dayBriefGeneratedCards[today]?.id, card.id)
    }

    func testFixtureBundleDayGenerationIsConfigured() async throws {
        let repositories = AppRepositories.fixture
        XCTAssertTrue(
            repositories.dailyGeneration is FixtureDayGenerationRepository,
            "AppRepositories.fixture must wire FixtureDayGenerationRepository, not the unavailable stub"
        )

        let result = try await FixtureDayGenerationRepository(artificialDelayNanoseconds: 0).generateDay(
            creatorID: repositories.context.creatorID,
            scheduledDate: "2026-08-09",
            dayBrief: "Bundle wiring smoke brief.",
            context: repositories.context
        )

        XCTAssertEqual(result.targetScheduledDate, "2026-08-09")
        XCTAssertEqual(result.dailyCard.status, "draft")
        XCTAssertEqual(result.dailyCard.sourceNote, "FixtureDayGenerationRepository")
    }

    private func makeServices(
        today: String,
        generation: CountingPlanDayGenerationRepository
    ) -> AppServices {
        AppServices.fixtureBacked(
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
            todayDate: { today }
        )
    }

    private func makeServicesWithPublishedReadyCard(
        today: String,
        ready: GeneratedDailyCardDraft,
        generation: CountingPlanDayGenerationRepository
    ) async -> AppServices {
        let store = FixturePublishedContentStore()
        let dailyCard = ready.dailyCard(completionState: nil)
        let weekly = PlanDispatchWeeklyPlanRepository(publishedStore: store, localToday: today)
        await weekly.seedReadyCard(dailyCard)
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: PlanDispatchTodayCardRepository(store: store, localToday: today),
                weeklyPlans: weekly,
                references: FixtureReferenceRepository(),
                dailyGeneration: generation,
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            memberRole: "creator",
            todayDate: { today }
        )
        services.dayBriefGeneratedCards[today] = ready
        return services
    }
}

// MARK: - Helpers

private final class CountingPlanDayGenerationRepository: DayGenerationRepository, @unchecked Sendable {
    private(set) var callCount = 0
    private(set) var lastBrief: String?
    private(set) var lastScheduledDate: String?

    func generateDay(
        creatorID: UUID,
        scheduledDate: String,
        dayBrief: String,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        callCount += 1
        lastBrief = dayBrief
        lastScheduledDate = scheduledDate
        return DailyGenerationResult(
            generationID: UUID(),
            weeklyPlanID: WeeklyPlan.raceWeek.id,
            status: "draft",
            targetScheduledDate: scheduledDate,
            dailyCard: makeDispatchPlanCard(
                scheduledDate: scheduledDate,
                title: "Generated: \(dayBrief)",
                status: "draft"
            ),
            warnings: [],
            assumptions: [],
            sourceSummary: "Counting stub",
            generatedAt: "2026-07-21T00:00:00Z"
        )
    }
}

private func makeDispatchPlanCard(
    scheduledDate: String,
    title: String,
    status: String
) -> GeneratedDailyCardDraft {
    GeneratedDailyCardDraft(
        id: UUID(),
        scheduledDate: scheduledDate,
        status: status,
        title: title,
        whyToday: "Dispatch test.",
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
        sourceNote: "Dispatch test fixture."
    )
}

private actor PlanDispatchWeeklyPlanRepository: WeeklyPlanRepository {
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
        throw RepositoryError.notConfigured("makeDayAvailable_not_used")
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

private struct PlanDispatchTodayCardRepository: TodayCardRepository {
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
