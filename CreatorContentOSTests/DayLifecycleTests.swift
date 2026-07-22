import XCTest
@testable import CreatorContentOS

/// Day package lifecycle matrix: Unpublish, overwrite-generate, edit-keeps-ready,
/// Decision + Unpublish / overwrite (live Decision cleared, Archive retained).
@MainActor
final class DayLifecycleTests: XCTestCase {
    func testUnpublishReadyDayReturnsDraftAndClearsLocalToday() async throws {
        let today = "2026-07-21"
        let ready = makeLifecycleCard(scheduledDate: today, title: "Ready to unpublish", status: "published")
        let store = FixturePublishedContentStore()
        let weekly = DayLifecycleWeeklyPlanRepository(publishedStore: store, localToday: today)
        await weekly.seedReadyCard(ready.dailyCard(completionState: nil))
        let archive = MutableFixtureArchiveRepository()
        let repositories = AppRepositories(
            context: .creatorFixture,
            today: DayLifecycleTodayCardRepository(store: store, localToday: today),
            weeklyPlans: weekly,
            references: FixtureReferenceRepository(),
            intelligence: FixtureIntelligenceRepository(),
            creatorProfile: FixtureCreatorProfileRepository(),
            archive: archive
        )
        let services = AppServices.fixtureBacked(
            repositories: repositories,
            todayCache: DayLifecycleMemoryCacheStore(),
            todayDate: { today }
        )
        services.dayBriefGeneratedCards[today] = ready
        services.todayCard = ready.dailyCard(completionState: nil)
        services.todayContentState = .ready

        let result = try await services.unpublishDay(scheduledDate: today)

        XCTAssertEqual(result.status, "draft")
        XCTAssertEqual(services.dayBriefGeneratedCards[today]?.status, "draft")
        XCTAssertEqual(services.todayContentState, .missingPublishedCard(date: today))
        XCTAssertNil(services.lastUnpublishDayError)
    }

    func testUnpublishAfterDecisionClearsLiveDecisionAndRetainsArchive() async throws {
        let today = "2026-07-21"
        let posted = makeLifecycleCard(scheduledDate: today, title: "Posted package", status: "posted")
        let store = FixturePublishedContentStore()
        let weekly = DayLifecycleWeeklyPlanRepository(
            publishedStore: store,
            localToday: today,
            previousStatusOnUnpublish: "posted",
            clearedLiveDecision: true
        )
        await weekly.seedReadyCard(posted.dailyCard(completionState: .posted))
        let archive = MutableFixtureArchiveRepository()
        let entry = ArchiveEntry(
            dailyCardID: posted.id,
            day: "TUE",
            date: "Jul 21",
            cardTitle: posted.title,
            decision: .posted,
            outputLine: "Posted.",
            hasPostThumbnail: true
        )
        await archive.seed([entry])
        let repositories = AppRepositories(
            context: .creatorFixture,
            today: DayLifecycleTodayCardRepository(store: store, localToday: today),
            weeklyPlans: weekly,
            references: FixtureReferenceRepository(),
            intelligence: FixtureIntelligenceRepository(),
            creatorProfile: FixtureCreatorProfileRepository(),
            archive: archive
        )
        let services = AppServices.fixtureBacked(
            repositories: repositories,
            todayCache: DayLifecycleMemoryCacheStore(),
            todayDate: { today }
        )
        services.dayBriefGeneratedCards[today] = posted
        services.archiveEntries = [entry]

        let result = try await services.unpublishDay(scheduledDate: today)

        XCTAssertEqual(result.status, "draft")
        XCTAssertEqual(result.previousStatus, "posted")
        XCTAssertTrue(result.clearedLiveDecision)
        XCTAssertTrue(result.archiveRetained)
        XCTAssertEqual(services.dayBriefGeneratedCards[today]?.status, "draft")
        let retained = try await archive.entries(for: .creatorFixture)
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(retained.first?.dailyCardID, posted.id)
        XCTAssertEqual(retained.first?.decision, .posted)
    }

    func testDraftRegenerateDoesNotRequireOverwriteConfirmation() async throws {
        let today = "2026-07-21"
        let draft = makeLifecycleCard(scheduledDate: today, title: "Draft only", status: "draft")
        let generation = DayLifecycleDayGenerationRepository(
            cardFactory: { date, brief in
                makeLifecycleCard(scheduledDate: date, title: "Regenerated \(brief)", status: "draft")
            }
        )
        let weekly = DayLifecycleWeeklyPlanRepository(
            publishedStore: FixturePublishedContentStore(),
            localToday: today
        )
        let repositories = AppRepositories(
            context: .creatorFixture,
            today: FixtureTodayCardRepository(),
            weeklyPlans: weekly,
            references: FixtureReferenceRepository(),
            dailyGeneration: generation,
            intelligence: FixtureIntelligenceRepository(),
            creatorProfile: FixtureCreatorProfileRepository(),
            archive: FixtureArchiveRepository()
        )
        let services = AppServices.fixtureBacked(
            repositories: repositories,
            todayCache: DayLifecycleMemoryCacheStore(),
            todayDate: { today }
        )
        services.dayBriefGeneratedCards[today] = draft

        let card = try await services.generateDayCard(
            scheduledDate: today,
            dayBrief: "Fresh draft brief",
            confirmOverwrite: false
        )

        XCTAssertEqual(card.status, "draft")
        XCTAssertEqual(card.title, "Regenerated Fresh draft brief")
        let unpublishCount = await weekly.unpublishCallCount()
        XCTAssertEqual(unpublishCount, 0)
    }

    func testOverwriteGenerateOnReadyRequiresConfirmationThenYieldsDraft() async throws {
        let today = "2026-07-21"
        let ready = makeLifecycleCard(scheduledDate: today, title: "Ready package", status: "published")
        let store = FixturePublishedContentStore()
        let weekly = DayLifecycleWeeklyPlanRepository(publishedStore: store, localToday: today)
        await weekly.seedReadyCard(ready.dailyCard(completionState: nil))
        let generation = DayLifecycleDayGenerationRepository(
            cardFactory: { date, _ in
                makeLifecycleCard(scheduledDate: date, title: "New draft after overwrite", status: "draft")
            }
        )
        let repositories = AppRepositories(
            context: .creatorFixture,
            today: DayLifecycleTodayCardRepository(store: store, localToday: today),
            weeklyPlans: weekly,
            references: FixtureReferenceRepository(),
            dailyGeneration: generation,
            intelligence: FixtureIntelligenceRepository(),
            creatorProfile: FixtureCreatorProfileRepository(),
            archive: FixtureArchiveRepository()
        )
        let services = AppServices.fixtureBacked(
            repositories: repositories,
            todayCache: DayLifecycleMemoryCacheStore(),
            todayDate: { today }
        )
        services.dayBriefGeneratedCards[today] = ready
        services.todayCard = ready.dailyCard(completionState: nil)
        services.todayContentState = .ready

        do {
            _ = try await services.generateDayCard(
                scheduledDate: today,
                dayBrief: "Should warn first",
                confirmOverwrite: false
            )
            XCTFail("Expected overwrite confirmation requirement")
        } catch {
            XCTAssertEqual(services.pendingOverwriteGenerateDate, today)
            XCTAssertTrue(
                services.dayBriefGenerationErrors[today]?.contains("Overwrite") == true
                    || services.dayBriefGenerationErrors[today]?.contains("ready package") == true
            )
            XCTAssertEqual(services.dayBriefGeneratedCards[today]?.status, "published")
        }

        let card = try await services.generateDayCard(
            scheduledDate: today,
            dayBrief: "Confirmed overwrite",
            confirmOverwrite: true
        )

        XCTAssertEqual(card.status, "draft")
        XCTAssertEqual(card.title, "New draft after overwrite")
        XCTAssertEqual(services.dayBriefGeneratedCards[today]?.status, "draft")
        let unpublishCount = await weekly.unpublishCallCount()
        XCTAssertEqual(unpublishCount, 1)
        XCTAssertNil(services.pendingOverwriteGenerateDate)
    }

    func testOverwriteGenerateAfterDecisionClearsLiveDecisionAndRetainsArchive() async throws {
        let today = "2026-07-21"
        let posted = makeLifecycleCard(scheduledDate: today, title: "Decision day", status: "posted")
        let store = FixturePublishedContentStore()
        let weekly = DayLifecycleWeeklyPlanRepository(
            publishedStore: store,
            localToday: today,
            previousStatusOnUnpublish: "posted",
            clearedLiveDecision: true
        )
        await weekly.seedReadyCard(posted.dailyCard(completionState: .posted))
        let archive = MutableFixtureArchiveRepository()
        let entry = ArchiveEntry(
            dailyCardID: posted.id,
            day: "TUE",
            date: "Jul 21",
            cardTitle: posted.title,
            decision: .posted,
            outputLine: "Posted.",
            hasPostThumbnail: true
        )
        await archive.seed([entry])
        let generation = DayLifecycleDayGenerationRepository(
            cardFactory: { date, _ in
                makeLifecycleCard(scheduledDate: date, title: "Draft after decision overwrite", status: "draft")
            }
        )
        let repositories = AppRepositories(
            context: .creatorFixture,
            today: DayLifecycleTodayCardRepository(store: store, localToday: today),
            weeklyPlans: weekly,
            references: FixtureReferenceRepository(),
            dailyGeneration: generation,
            intelligence: FixtureIntelligenceRepository(),
            creatorProfile: FixtureCreatorProfileRepository(),
            archive: archive
        )
        let services = AppServices.fixtureBacked(
            repositories: repositories,
            todayCache: DayLifecycleMemoryCacheStore(),
            todayDate: { today }
        )
        services.dayBriefGeneratedCards[today] = posted
        services.archiveEntries = [entry]

        let card = try await services.generateDayCard(
            scheduledDate: today,
            dayBrief: "Overwrite after decision",
            confirmOverwrite: true
        )

        XCTAssertEqual(card.status, "draft")
        let unpublish = await weekly.lastUnpublishResult()
        XCTAssertEqual(unpublish?.previousStatus, "posted")
        XCTAssertEqual(unpublish?.clearedLiveDecision, true)
        XCTAssertEqual(unpublish?.archiveRetained, true)
        let retained = try await archive.entries(for: .creatorFixture)
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(retained.first?.decision, .posted)
    }

    func testLightEditKeepsReadyAndRefreshesToday() async throws {
        let today = "2026-07-21"
        let ready = makeLifecycleCard(scheduledDate: today, title: "Ready edit me", status: "published")
        let store = FixturePublishedContentStore()
        let weekly = DayLifecycleWeeklyPlanRepository(publishedStore: store, localToday: today)
        await weekly.seedReadyCard(ready.dailyCard(completionState: nil))
        let repositories = AppRepositories(
            context: .creatorFixture,
            today: DayLifecycleTodayCardRepository(store: store, localToday: today),
            weeklyPlans: weekly,
            references: FixtureReferenceRepository(),
            intelligence: FixtureIntelligenceRepository(),
            creatorProfile: FixtureCreatorProfileRepository(),
            archive: FixtureArchiveRepository()
        )
        let services = AppServices.fixtureBacked(
            repositories: repositories,
            todayCache: DayLifecycleMemoryCacheStore(),
            todayDate: { today }
        )
        services.dayBriefGeneratedCards[today] = ready
        services.todayCard = ready.dailyCard(completionState: nil)
        services.todayContentState = .ready

        let result = try await services.updateReadyDayPackage(
            scheduledDate: today,
            package: ReadyDayPackageUpdate(caption: "Edited caption stays ready.")
        )

        XCTAssertEqual(result.status, "published")
        XCTAssertEqual(services.dayBriefGeneratedCards[today]?.status, "published")
        XCTAssertEqual(services.dayBriefGeneratedCards[today]?.caption, "Edited caption stays ready.")
        XCTAssertEqual(services.todayCard.caption, "Edited caption stays ready.")
        XCTAssertEqual(services.todayContentState, .ready)
        XCTAssertFalse(services.weeklyPlan.isSoftLocked)
        let editCount = await weekly.updatePackageCallCount()
        XCTAssertEqual(editCount, 1)
    }

    func testUnpublishFailureSurfacesErrorWithoutAmbiguousState() async {
        let today = "2026-07-21"
        let ready = makeLifecycleCard(scheduledDate: today, title: "Will fail", status: "published")
        let weekly = FailingUnpublishWeeklyPlanRepository()
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
            todayCache: DayLifecycleMemoryCacheStore(),
            todayDate: { today }
        )
        services.dayBriefGeneratedCards[today] = ready
        services.todayContentState = .ready

        do {
            _ = try await services.unpublishDay(scheduledDate: today)
            XCTFail("Expected unpublish to throw")
        } catch {
            XCTAssertEqual(services.dayBriefGeneratedCards[today]?.status, "published")
            XCTAssertEqual(services.todayContentState, .ready)
            XCTAssertNotNil(services.lastUnpublishDayError)
        }
    }
}

// MARK: - Helpers

private func makeLifecycleCard(
    scheduledDate: String,
    title: String,
    status: String
) -> GeneratedDailyCardDraft {
    GeneratedDailyCardDraft(
        id: UUID(),
        scheduledDate: scheduledDate,
        status: status,
        title: title,
        whyToday: "Lifecycle matrix.",
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
        sourceNote: "Day lifecycle test"
    )
}

private actor DayLifecycleWeeklyPlanRepository: WeeklyPlanRepository {
    private let publishedStore: FixturePublishedContentStore
    private let localToday: String
    private let previousStatusOnUnpublish: String
    private let clearedLiveDecision: Bool
    private var plan: WeeklyPlan
    private var unpublishCalls = 0
    private var updatePackageCalls = 0
    private var lastUnpublish: DayUnpublishResult?

    init(
        publishedStore: FixturePublishedContentStore,
        localToday: String,
        previousStatusOnUnpublish: String = "published",
        clearedLiveDecision: Bool = false,
        plan: WeeklyPlan = .raceWeek
    ) {
        self.publishedStore = publishedStore
        self.localToday = localToday
        self.previousStatusOnUnpublish = previousStatusOnUnpublish
        self.clearedLiveDecision = clearedLiveDecision
        self.plan = plan
    }

    func seedReadyCard(_ card: DailyCard) async {
        var cards = await publishedStore.readWeekCards()
        cards.removeAll { $0.scheduledDate == card.scheduledDate }
        cards.append(card)
        let todayCard = cards.first { $0.scheduledDate == localToday }
        await publishedStore.savePublishedContent(cards: cards, todayCard: todayCard)
    }

    func unpublishCallCount() -> Int { unpublishCalls }
    func updatePackageCallCount() -> Int { updatePackageCalls }
    func lastUnpublishResult() -> DayUnpublishResult? { lastUnpublish }

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
        throw RepositoryError.notConfigured("make_day_available_not_used")
    }

    func unpublishDay(
        scheduledDate: String,
        dailyCardID: UUID?,
        context: WorkspaceContext
    ) async throws -> DayUnpublishResult {
        unpublishCalls += 1
        var cards = await publishedStore.readWeekCards()
        let existing = cards.first { card in
            if let dailyCardID { return card.id == dailyCardID }
            return card.scheduledDate == scheduledDate
        }
        let cardID = existing?.id ?? dailyCardID ?? UUID()
        cards.removeAll { $0.id == cardID || $0.scheduledDate == scheduledDate }
        let todayCard = cards.first { $0.scheduledDate == localToday }
        await publishedStore.savePublishedContent(cards: cards, todayCard: todayCard)

        let result = DayUnpublishResult(
            dailyCardID: cardID,
            scheduledDate: scheduledDate,
            status: "draft",
            previousStatus: previousStatusOnUnpublish,
            clearedLiveDecision: clearedLiveDecision,
            archiveRetained: true,
            weeklyPlanID: plan.id
        )
        lastUnpublish = result
        return result
    }

    func updateReadyDayPackage(
        scheduledDate: String,
        dailyCardID: UUID?,
        package: ReadyDayPackageUpdate,
        context: WorkspaceContext
    ) async throws -> DayPackageUpdateResult {
        updatePackageCalls += 1
        var cards = await publishedStore.readWeekCards()
        guard let index = cards.firstIndex(where: { card in
            if let dailyCardID { return card.id == dailyCardID }
            return card.scheduledDate == scheduledDate
        }) else {
            throw RepositoryError.edgeFunction("daily_card_not_found")
        }
        var card = cards[index]
        if let title = package.title { card.title = title }
        if let whyToday = package.whyToday { card.whyToday = whyToday }
        if let caption = package.caption { card.caption = caption }
        if let script = package.script { card.script = script }
        cards[index] = card
        let todayCard = cards.first { $0.scheduledDate == localToday }
        await publishedStore.savePublishedContent(cards: cards, todayCard: todayCard)
        return DayPackageUpdateResult(
            dailyCardID: card.id,
            scheduledDate: scheduledDate,
            status: "published",
            weeklyPlanID: plan.id,
            title: card.title,
            caption: card.caption
        )
    }
}

private actor FailingUnpublishWeeklyPlanRepository: WeeklyPlanRepository {
    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan { .raceWeek }
    func currentGeneratedDraft(for context: WorkspaceContext) async throws -> GeneratedWeekDraft? { nil }
    func ideaBank(for context: WorkspaceContext) async throws -> [WeeklyIdea] { [] }
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
        throw RepositoryError.notConfigured("make_day_available_not_used")
    }
    func unpublishDay(
        scheduledDate: String,
        dailyCardID: UUID?,
        context: WorkspaceContext
    ) async throws -> DayUnpublishResult {
        throw RepositoryError.edgeFunction("unpublish_day_failed")
    }
}

private struct DayLifecycleTodayCardRepository: TodayCardRepository {
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

private struct DayLifecycleDayGenerationRepository: DayGenerationRepository {
    let cardFactory: @Sendable (String, String) -> GeneratedDailyCardDraft

    func generateDay(
        creatorID: UUID,
        scheduledDate: String,
        dayBrief: String,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        let card = cardFactory(scheduledDate, dayBrief)
        return DailyGenerationResult(
            generationID: UUID(),
            weeklyPlanID: WeeklyPlan.raceWeek.id,
            status: "draft",
            targetScheduledDate: scheduledDate,
            dailyCard: card,
            warnings: [],
            assumptions: [],
            sourceSummary: "Day lifecycle test.",
            generatedAt: "2026-07-21T00:00:00Z"
        )
    }
}

private actor MutableFixtureArchiveRepository: ArchiveRepository {
    private var stored: [ArchiveEntry] = []

    func seed(_ entries: [ArchiveEntry]) {
        stored = entries
    }

    func entries(for context: WorkspaceContext) async throws -> [ArchiveEntry] {
        stored
    }

    func persistDecision(
        _ entry: ArchiveEntry,
        for card: DailyCard,
        context: WorkspaceContext
    ) async throws {
        if let index = stored.firstIndex(where: { $0.dailyCardID == card.id }) {
            stored[index] = entry
        } else {
            stored.insert(entry, at: 0)
        }
    }

    func upsertDecision(
        _ entry: ArchiveEntry,
        for card: DailyCard,
        context: WorkspaceContext
    ) async throws -> [ArchiveEntry] {
        try await persistDecision(entry, for: card, context: context)
        return stored
    }
}

private final class DayLifecycleMemoryCacheStore: TodayCacheStoring {
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
