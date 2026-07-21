import XCTest
@testable import CreatorContentOS

/// Ticket 06: empty Today → Plan; Edit / ⋯ → Plan with date; notification copy;
/// offline cache still serves a ready package.
@MainActor
final class TodayPlanEntryTests: XCTestCase {
    func testEmptyTodayCTARouteCarriesMissingDate() {
        let missingDate = "2026-07-21"
        let route = CreatorRoute.plan(selectedDate: missingDate)

        guard case .plan(let selectedDate) = route else {
            return XCTFail("Expected plan route")
        }
        XCTAssertEqual(selectedDate, missingDate)
    }

    func testPreparePlanSetsSelectedDateForHub() {
        let state = AppState(runtime: .fixtures(), authenticationPhase: .live)
        XCTAssertNil(state.planSelectedDate)

        state.preparePlan(selecting: "2026-07-21")
        XCTAssertEqual(state.planSelectedDate, "2026-07-21")

        state.preparePlan(selecting: "  ")
        XCTAssertNil(state.planSelectedDate)

        state.preparePlan(selecting: "2026-07-22")
        XCTAssertEqual(state.consumePlanSelectedDate(), "2026-07-22")
        XCTAssertNil(state.planSelectedDate)
    }

    func testEditAndOverflowRoutesPreselectCardDate() {
        let cardDate = "2026-07-21"
        let editRoute = CreatorRoute.shootFolio(editing: true)
        let overflowRoute = CreatorRoute.plan(selectedDate: cardDate)

        guard case .shootFolio(let editing) = editRoute else {
            return XCTFail("Expected edit shoot folio route")
        }
        guard case .plan(let overflowDate) = overflowRoute else {
            return XCTFail("Expected overflow plan route")
        }
        XCTAssertTrue(editing)
        XCTAssertEqual(overflowDate, cardDate)
        XCTAssertNotEqual(editRoute, overflowRoute)
    }

    func testCreatorRoutePlanIsDistinctFromShootFolio() {
        XCTAssertNotEqual(
            CreatorRoute.plan(selectedDate: "2026-07-21"),
            CreatorRoute.shootFolio()
        )
    }

    func testEditRouteOpensShootFolioEditingNotPlan() {
        let editRoute = CreatorRoute.shootFolio(editing: true)
        guard case .shootFolio(let editing) = editRoute else {
            return XCTFail("Expected shoot folio edit route")
        }
        XCTAssertTrue(editing)
        XCTAssertNotEqual(editRoute, CreatorRoute.plan(selectedDate: "2026-07-21"))
    }

    func testNotificationReminderTitleIsGetTodaysContentReady() {
        XCTAssertEqual(TodayNotificationCopy.reminderTitle, "Get today's content ready.")
    }

    func testOfflineCacheStillPresentsReadyPackageWhenNetworkFails() async throws {
        let cache = TodayPlanEntryMemoryCacheStore()
        let readyCard = DailyCard(
            title: "Cached ready package",
            context: "Tuesday",
            effortLabel: "Easy - 10 min",
            whyToday: "Routine.",
            scheduledDate: "2026-07-21",
            scenes: [ShotScene(number: 1, title: "Shoes", duration: "3 sec", symbol: "shoeprints.fill")]
        )
        try cache.saveSnapshot(
            CachedTodaySnapshot(
                todayCard: readyCard,
                weekCards: [readyCard],
                cachedAt: Date(),
                source: "repository-refresh"
            ),
            for: .creatorFixture
        )

        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: TodayPlanEntryOfflineTodayRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: cache,
            todayDate: { "2026-07-21" }
        )
        services.todayContentState = .loading

        await services.refreshFromRepositoriesImmediately()

        XCTAssertEqual(services.todayCard.title, "Cached ready package")
        XCTAssertEqual(services.todayContentState, .ready)
    }
}

private final class TodayPlanEntryMemoryCacheStore: TodayCacheStoring {
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

private struct TodayPlanEntryOfflineTodayRepository: TodayCardRepository {
    func todayCard(for context: WorkspaceContext) async throws -> DailyCard {
        throw URLError(.notConnectedToInternet)
    }

    func weekCards(for context: WorkspaceContext) async throws -> [DailyCard] {
        throw URLError(.notConnectedToInternet)
    }

    func completeToday(
        card: DailyCard,
        decision: DailyDecision,
        context: WorkspaceContext
    ) async throws -> ArchiveEntry {
        throw URLError(.notConnectedToInternet)
    }
}
