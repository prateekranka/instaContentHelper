import XCTest
@testable import CreatorContentOS

/// Subagent F — Published Week Persistence.
///
/// Published content must survive refresh/restart and must NOT depend on
/// transient generation state. These tests prove the creator Today reads
/// published `daily_cards` (not a generated draft), that the cache stores the
/// published card, and that a missing generated draft does not block the
/// published Today card from loading.
@MainActor
final class PublishedWeekPersistenceTests: XCTestCase {
    func testPublishThenClearInMemoryThenRefreshStillLoadsPublishedTodayCard() async throws {
        let cache = PersistenceMemoryTodayCacheStore()
        let services = AppServices.fixtureBacked(
            repositories: makeGeneratingFixtureRepositories(),
            todayCache: cache,
            todayDate: { "2026-06-01" }
        )

        // Generate + publish a week so a canonical published card exists.
        let draft = await services.generateCurrentWeekImmediately()
        XCTAssertNotNil(draft)
        for day in services.weeklyPlan.days {
            await services.updateWeeklyDayStateImmediately(dayID: day.id, state: .planned)
        }
        await services.publishCurrentWeekImmediately()
        let publishedTodayTitle = services.todayCard.title
        XCTAssertFalse(publishedTodayTitle.isEmpty)

        // Simulate restart: wipe in-memory state, then refresh from repositories.
        services.latestGenerationSummary = nil
        services.weeklyGenerationProgress = nil
        services.todayCard = DailyCard(
            title: "Cleared",
            context: "Restart",
            effortLabel: "—",
            whyToday: "—",
            scenes: []
        )
        services.todayContentState = .loading

        await services.refreshFromRepositoriesImmediately()

        // The published Today card must reload from the canonical published
        // source, independent of the (now absent) generated draft.
        XCTAssertEqual(services.todayContentState, .ready)
        XCTAssertEqual(services.todayCard.title, publishedTodayTitle)
        XCTAssertNil(services.latestGenerationSummary,
                     "Generated draft can be absent while the published card still loads.")
    }

    func testCacheStoresPublishedTodayCard() async throws {
        let cache = PersistenceMemoryTodayCacheStore()
        let services = AppServices.fixtureBacked(
            repositories: makeGeneratingFixtureRepositories(),
            todayCache: cache,
            todayDate: { "2026-06-01" }
        )

        // Generate + publish drives saveTodaySnapshot(source: "week-publish")
        // through the production path, persisting the published card to cache.
        let draft = await services.generateCurrentWeekImmediately()
        XCTAssertNotNil(draft)
        for day in services.weeklyPlan.days {
            await services.updateWeeklyDayStateImmediately(dayID: day.id, state: .planned)
        }
        await services.publishCurrentWeekImmediately()

        let snapshot = try XCTUnwrap(cache.loadSnapshot(for: services.context))
        XCTAssertEqual(snapshot.todayCard.title, services.todayCard.title,
                       "Cache must store the published Today card from the publish path.")
        XCTAssertEqual(snapshot.source, "week-publish",
                       "Snapshot must originate from the publish flow, not a transient draft.")
    }

    func testPublishReplacesOptimisticWeekCardsWithCanonicalPublishedRows() async throws {
        let cache = PersistenceMemoryTodayCacheStore()
        let optimisticCard = DailyCard(
            title: "Optimistic reviewed draft",
            context: "Wednesday",
            effortLabel: "Easy - 8 min",
            whyToday: "Local review edit.",
            scheduledDate: "2026-06-25",
            scenes: [ShotScene(number: 1, title: "Local scene", duration: "3 sec", symbol: "pencil")]
        )
        let canonicalCard = DailyCard(
            title: "Canonical published June 25",
            context: "Wednesday",
            effortLabel: "Easy - 8 min",
            whyToday: "Published row.",
            scheduledDate: "2026-06-25",
            scenes: [
                ShotScene(number: 1, title: "Published scene 1", duration: "3 sec", symbol: "sparkles"),
                ShotScene(number: 2, title: "Published scene 2", duration: "4 sec", symbol: "camera")
            ]
        )

        let repositories = AppRepositories(
            context: .creatorFixture,
            today: CanonicalPublishedTodayRepository(
                today: canonicalCard,
                weekCards: [canonicalCard]
            ),
            weeklyPlans: CanonicalPublishedWeeklyPlanRepository(
                optimisticToday: optimisticCard,
                canonicalPlan: WeeklyPlan.raceWeek.softLockedForPublish
            ),
            references: FixtureReferenceRepository(),
            referenceImport: FixtureReferenceImportRepository(),
            weeklyGeneration: TestWeeklyGenerationRepository(),
            intelligence: FixtureIntelligenceRepository(),
            creatorProfile: FixtureCreatorProfileRepository(),
            archive: FixtureArchiveRepository()
        )
        let services = AppServices.fixtureBacked(
            repositories: repositories,
            todayCache: cache
        )

        for day in services.weeklyPlan.days {
            await services.updateWeeklyDayStateImmediately(dayID: day.id, state: .planned)
        }

        await services.publishCurrentWeekImmediately()

        XCTAssertEqual(services.todayCard.title, "Canonical published June 25")
        XCTAssertEqual(services.weekCards.map(\.title), ["Canonical published June 25"],
                       "Week cards must be reloaded from canonical published rows after publish, not left on the optimistic draft state.")

        let snapshot = try XCTUnwrap(cache.loadSnapshot(for: services.context))
        XCTAssertEqual(snapshot.todayCard.title, "Canonical published June 25")
        XCTAssertEqual(snapshot.weekCards.map(\.title), ["Canonical published June 25"])
    }

    func testRefreshFallsBackToCachedPublishedCardWhenRepositoryFails() async throws {
        let cache = PersistenceMemoryTodayCacheStore()
        // Pre-seed the cache with a published card.
        let cachedCard = DailyCard(
            title: "Cached published card",
            context: "Tuesday",
            effortLabel: "Easy - 10 min",
            whyToday: "Routine.",
            scheduledDate: "2026-06-23",
            scenes: [ShotScene(number: 1, title: "Shoes", duration: "3 sec", symbol: "shoeprints.fill")]
        )
        try cache.saveSnapshot(
            CachedTodaySnapshot(
                todayCard: cachedCard,
                weekCards: [],
                cachedAt: Date(),
                source: "repository-refresh"
            ),
            for: .creatorFixture
        )

        // A repository that throws on every read simulates an offline/failed refresh.
        let services = AppServices.fixtureBacked(
            repositories: makeFailingRepositories(),
            todayCache: cache
        )
        services.todayCard = DailyCard(
            title: "Placeholder",
            context: "—",
            effortLabel: "—",
            whyToday: "—",
            scenes: []
        )
        services.todayContentState = .loading

        await services.refreshFromRepositoriesImmediately()

        // Offline fallback must use the cached PUBLISHED card, not stay on the
        // placeholder or fail outright.
        XCTAssertEqual(services.todayCard.title, "Cached published card")
        XCTAssertEqual(services.todayContentState, .ready)
    }

    // MARK: - Helpers

    private func makeGeneratingFixtureRepositories() -> AppRepositories {
        let store = FixturePublishedContentStore()
        return AppRepositories(
            context: .creatorFixture,
            today: FixtureTodayCardRepository(publishedStore: store),
            weeklyPlans: FixtureWeeklyPlanRepository(publishedStore: store),
            references: FixtureReferenceRepository(),
            referenceImport: FixtureReferenceImportRepository(),
            weeklyGeneration: TestWeeklyGenerationRepository(),
            intelligence: FixtureIntelligenceRepository(),
            creatorProfile: FixtureCreatorProfileRepository(),
            archive: FixtureArchiveRepository()
        )
    }

    private func makeFailingRepositories() -> AppRepositories {
        AppRepositories(
            context: .creatorFixture,
            today: FailingTodayCardRepository(),
            weeklyPlans: FailingWeeklyPlanRepository(),
            references: FixtureReferenceRepository(),
            referenceImport: FixtureReferenceImportRepository(),
            weeklyGeneration: TestWeeklyGenerationRepository(),
            intelligence: FixtureIntelligenceRepository(),
            creatorProfile: FixtureCreatorProfileRepository(),
            archive: FixtureArchiveRepository()
        )
    }
}

private struct FailingTodayCardRepository: TodayCardRepository {
    func todayCard(for context: WorkspaceContext) async throws -> DailyCard {
        throw RepositoryError.notConfigured("offline")
    }
    func weekCards(for context: WorkspaceContext) async throws -> [DailyCard] {
        throw RepositoryError.notConfigured("offline")
    }
    func completeToday(
        card: DailyCard,
        decision: DailyDecision,
        context: WorkspaceContext
    ) async throws -> ArchiveEntry {
        throw RepositoryError.notConfigured("offline")
    }
}

private actor FailingWeeklyPlanRepository: WeeklyPlanRepository {
    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan {
        throw RepositoryError.notConfigured("offline")
    }
    func currentGeneratedDraft(for context: WorkspaceContext) async throws -> GeneratedWeekDraft? {
        throw RepositoryError.notConfigured("offline")
    }
    func ideaBank(for context: WorkspaceContext) async throws -> [WeeklyIdea] {
        throw RepositoryError.notConfigured("offline")
    }
    func currentWeeklyContent(for context: WorkspaceContext) async throws -> WeeklyRepositoryContent {
        throw RepositoryError.notConfigured("offline")
    }
    func publishWeek(
        _ plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        generatedDraft: GeneratedWeekDraft?,
        context: WorkspaceContext
    ) async throws -> WeeklyPublishResult {
        throw RepositoryError.notConfigured("offline")
    }
    func selectIdeaForNextOpenDay(
        _ idea: WeeklyIdea,
        in plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        context: WorkspaceContext
    ) async throws -> WeeklySelectionUpdate {
        throw RepositoryError.notConfigured("offline")
    }
    func updateWeeklySetupSections(
        _ sections: [WeeklySetupSection],
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        throw RepositoryError.notConfigured("offline")
    }
    func updateWeeklyBrief(
        _ text: String,
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        throw RepositoryError.notConfigured("offline")
    }
}

private struct CanonicalPublishedTodayRepository: TodayCardRepository {
    let today: DailyCard
    let weekCards: [DailyCard]

    func todayCard(for context: WorkspaceContext) async throws -> DailyCard {
        today
    }

    func weekCards(for context: WorkspaceContext) async throws -> [DailyCard] {
        weekCards
    }

    func completeToday(
        card: DailyCard,
        decision: DailyDecision,
        context: WorkspaceContext
    ) async throws -> ArchiveEntry {
        ArchiveEntry(
            dailyCardID: card.id,
            day: "WED",
            date: "25 JUN",
            cardTitle: card.title,
            decision: decision.completionState,
            outputLine: decision.outputLine,
            hasPostThumbnail: decision.hasPostThumbnail
        )
    }
}

private actor CanonicalPublishedWeeklyPlanRepository: WeeklyPlanRepository {
    let optimisticToday: DailyCard
    let canonicalPlan: WeeklyPlan

    init(optimisticToday: DailyCard, canonicalPlan: WeeklyPlan) {
        self.optimisticToday = optimisticToday
        self.canonicalPlan = canonicalPlan
    }

    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan {
        canonicalPlan
    }

    func currentGeneratedDraft(for context: WorkspaceContext) async throws -> GeneratedWeekDraft? {
        nil
    }

    func ideaBank(for context: WorkspaceContext) async throws -> [WeeklyIdea] {
        []
    }

    func currentWeeklyContent(for context: WorkspaceContext) async throws -> WeeklyRepositoryContent {
        WeeklyRepositoryContent(
            publishedPlan: canonicalPlan,
            generatedDraft: nil,
            ideaBank: []
        )
    }

    func publishWeek(
        _ plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        generatedDraft: GeneratedWeekDraft?,
        context: WorkspaceContext
    ) async throws -> WeeklyPublishResult {
        WeeklyPublishResult(
            weeklyPlan: plan.softLockedForPublish,
            weekCards: [optimisticToday],
            todayCard: optimisticToday,
            summary: "Published 1 cards to Creator Today."
        )
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
}

private final class PersistenceMemoryTodayCacheStore: TodayCacheStoring {
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
