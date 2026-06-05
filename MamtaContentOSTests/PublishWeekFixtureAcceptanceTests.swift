import XCTest
@testable import MamtaContentOS

@MainActor
final class PublishWeekFixtureAcceptanceTests: XCTestCase {
    func testPrateekPublishesFixtureWeekAndMamtaTodayReadsPublishedCard() async throws {
        let cache = MemoryTodayCacheStore()
        let services = AppServices.fixtureBacked(todayCache: cache)

        XCTAssertFalse(services.weeklyPlan.isSoftLocked)
        XCTAssertEqual(services.weeklyPlan.days.count, 7)
        XCTAssertEqual(services.weekCards.count, 7)
        XCTAssertNil(services.lastRepositoryError)

        await services.publishCurrentWeekImmediately()

        XCTAssertTrue(services.weeklyPlan.isSoftLocked)
        XCTAssertTrue(services.weeklyPlan.days.allSatisfy(\.isSoftLocked))
        XCTAssertEqual(services.weekCards.count, 7)
        XCTAssertEqual(services.todayCard.title, "Race week has entered the house")
        XCTAssertEqual(services.todayCard.scheduledDate, "2026-06-05")
        XCTAssertEqual(services.lastPublishSummary, "Published 7 cards to Mamta Today.")
        XCTAssertNil(services.lastRepositoryError)
    }

    func testPublishingWeekStoresPublishedCardForOfflineToday() async throws {
        let cache = MemoryTodayCacheStore()
        let services = AppServices.fixtureBacked(todayCache: cache)

        await services.publishCurrentWeekImmediately()

        let snapshot = try XCTUnwrap(cache.loadSnapshot(for: .mamtaFixture))
        XCTAssertEqual(snapshot.todayCard.title, "Race week has entered the house")
        XCTAssertEqual(snapshot.todayCard.scheduledDate, "2026-06-05")
        XCTAssertEqual(snapshot.weekCards.count, 7)
        XCTAssertEqual(snapshot.source, "week-publish")
    }

    func testMamtaTodayUsesCachedPublishedCardWhenRepositoryIsOffline() async throws {
        let cache = MemoryTodayCacheStore()
        var cachedCard = DailyCard.raceWeekToday
        cachedCard.title = "Cached Puma shakeout plan"
        cachedCard.scheduledDate = "2026-06-05"
        let snapshot = CachedTodaySnapshot(
            todayCard: cachedCard,
            weekCards: [cachedCard],
            cachedAt: Date(),
            source: "test"
        )
        try cache.saveSnapshot(snapshot, for: .mamtaFixture)

        let repositories = AppRepositories(
            context: .mamtaFixture,
            today: OfflineTodayCardRepository(),
            weeklyPlans: FixtureWeeklyPlanRepository(),
            references: FixtureReferenceRepository(),
            intelligence: FixtureIntelligenceRepository(),
            creatorProfile: FixtureCreatorProfileRepository(),
            archive: FixtureArchiveRepository()
        )
        let services = AppServices.fixtureBacked(
            repositories: repositories,
            todayCache: cache
        )

        XCTAssertTrue(services.loadTodayFromCache())
        XCTAssertEqual(services.todayCard.title, "Cached Puma shakeout plan")

        await services.refreshFromRepositoriesImmediately()

        XCTAssertEqual(services.todayCard.title, "Cached Puma shakeout plan")
        XCTAssertEqual(services.weekCards.map(\.title), ["Cached Puma shakeout plan"])
        XCTAssertNotNil(services.lastRepositoryError)
    }

    func testMamtaBackupDecisionWritesToArchive() async throws {
        let cache = MemoryTodayCacheStore()
        let services = AppServices.fixtureBacked(todayCache: cache)

        let entry = await services.completeTodayImmediately(with: .backupStory)

        XCTAssertEqual(services.todayCard.completionState, .usedBackup)
        XCTAssertEqual(entry.dailyCardID, services.todayCard.id)
        XCTAssertEqual(entry.day, "FRI")
        XCTAssertEqual(entry.date, "5 JUN")
        XCTAssertEqual(entry.decision, .usedBackup)
        XCTAssertEqual(entry.outputLine, "Used backup: 10-second story")
        XCTAssertFalse(entry.hasPostThumbnail)
        XCTAssertNil(services.lastRepositoryError)

        let archiveEntry = try XCTUnwrap(
            services.archiveEntries.first { $0.dailyCardID == services.todayCard.id }
        )
        XCTAssertEqual(archiveEntry.outputLine, "Used backup: 10-second story")

        let cachedSnapshot = try XCTUnwrap(cache.loadSnapshot(for: .mamtaFixture))
        XCTAssertEqual(cachedSnapshot.todayCard.completionState, .usedBackup)
        XCTAssertEqual(cachedSnapshot.source, "decision-synced")
    }

    func testMamtaShotDecisionWritesToArchive() async throws {
        let services = AppServices.fixtureBacked(todayCache: MemoryTodayCacheStore())

        let entry = await services.completeTodayImmediately(with: .shot)

        XCTAssertEqual(services.todayCard.completionState, .shot)
        XCTAssertEqual(entry.decision, .shot)
        XCTAssertEqual(entry.outputLine, "Shot today, ready to post")
        XCTAssertTrue(entry.hasPostThumbnail)
        XCTAssertNil(services.lastRepositoryError)
    }

    func testMamtaDecisionStaysInLocalArchiveWhenRepositoryWriteFails() async throws {
        let repositories = AppRepositories(
            context: .mamtaFixture,
            today: OfflineTodayCardRepository(),
            weeklyPlans: FixtureWeeklyPlanRepository(),
            references: FixtureReferenceRepository(),
            intelligence: FixtureIntelligenceRepository(),
            creatorProfile: FixtureCreatorProfileRepository(),
            archive: FixtureArchiveRepository()
        )
        let services = AppServices.fixtureBacked(
            repositories: repositories,
            todayCache: MemoryTodayCacheStore()
        )

        let entry = await services.completeTodayImmediately(with: .savedForTomorrow)

        XCTAssertEqual(entry.decision, .savedForTomorrow)
        XCTAssertEqual(entry.outputLine, "Saved this card for tomorrow")
        XCTAssertEqual(services.todayCard.completionState, .savedForTomorrow)
        XCTAssertNotNil(services.lastRepositoryError)

        let archiveEntry = try XCTUnwrap(
            services.archiveEntries.first { $0.dailyCardID == services.todayCard.id }
        )
        XCTAssertEqual(archiveEntry.decision, .savedForTomorrow)
        XCTAssertEqual(archiveEntry.outputLine, "Saved this card for tomorrow")
    }

    func testRepositoryRefreshSchedulesGentleNotificationFromSyncedTodayCard() async throws {
        let notifications = MemoryTodayNotificationScheduler()
        let services = AppServices.fixtureBacked(
            todayCache: MemoryTodayCacheStore(),
            notifications: notifications
        )

        await services.refreshFromRepositoriesImmediately()

        let schedule = try XCTUnwrap(notifications.pendingSchedule)
        XCTAssertEqual(schedule.cardID, services.todayCard.id)
        XCTAssertEqual(schedule.title, "Today's reel is ready")
        XCTAssertEqual(schedule.body, "Race week has entered the house")
        XCTAssertEqual(schedule.scheduledDate, "2026-06-05")
        XCTAssertEqual(schedule.hour, 8)
        XCTAssertEqual(schedule.minute, 0)
        XCTAssertEqual(services.lastNotificationSchedule, schedule)
        XCTAssertNil(services.lastNotificationError)
    }

    func testCachedTodayCanScheduleNotificationWithoutRepository() async throws {
        let cache = MemoryTodayCacheStore()
        let notifications = MemoryTodayNotificationScheduler()
        var cachedCard = DailyCard.raceWeekToday
        cachedCard.title = "Cached shakeout reminder"
        try cache.saveSnapshot(
            CachedTodaySnapshot(
                todayCard: cachedCard,
                weekCards: [cachedCard],
                cachedAt: Date(),
                source: "test"
            ),
            for: .mamtaFixture
        )
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .mamtaFixture,
                today: OfflineTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: cache,
            notifications: notifications
        )

        XCTAssertTrue(services.loadTodayFromCache())
        await services.scheduleTodayNotificationIfNeededImmediately()

        XCTAssertEqual(notifications.pendingSchedule?.body, "Cached shakeout reminder")
        XCTAssertEqual(services.lastNotificationSchedule?.body, "Cached shakeout reminder")
    }

    func testMamtaDecisionCancelsPendingTodayNotification() async throws {
        let notifications = MemoryTodayNotificationScheduler()
        let services = AppServices.fixtureBacked(
            todayCache: MemoryTodayCacheStore(),
            notifications: notifications
        )

        await services.scheduleTodayNotificationIfNeededImmediately()
        XCTAssertNotNil(notifications.pendingSchedule)

        await services.completeTodayImmediately(with: .backupStory)

        XCTAssertNil(notifications.pendingSchedule)
        XCTAssertEqual(notifications.cancelledIdentifiers.count, 1)
        XCTAssertNil(services.lastNotificationSchedule)
    }

    func testInitialRuntimeFallsBackToFixturesWithoutPairedSession() {
        let runtime = AppRuntime.makeInitialRuntime(store: EmptyRuntimeConfigurationStore())

        XCTAssertEqual(runtime.mode, .fixtures)
        XCTAssertEqual(runtime.services.todayCard.title, DailyCard.raceWeekToday.title)
    }
}

private struct EmptyRuntimeConfigurationStore: RuntimeConfigurationStoring {
    func loadPairedSession() throws -> PairedDeviceSession? {
        nil
    }

    func savePairedSession(_ session: PairedDeviceSession) throws {}

    func clearPairedSession() throws {}
}

private final class MemoryTodayCacheStore: TodayCacheStoring {
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

private final class MemoryTodayNotificationScheduler: TodayNotificationScheduling {
    private(set) var pendingSchedule: TodayNotificationSchedule?
    private(set) var cancelledIdentifiers: [String] = []

    func scheduleTodayReminder(
        for card: DailyCard,
        context: WorkspaceContext
    ) async throws -> TodayNotificationSchedule? {
        let identifier = "test.today.\(context.workspaceID.uuidString).\(context.creatorID.uuidString)"

        guard card.completionState == nil else {
            pendingSchedule = nil
            cancelledIdentifiers.append(identifier)
            return nil
        }

        let schedule = TodayNotificationSchedule(
            identifier: identifier,
            cardID: card.id,
            title: "Today's reel is ready",
            body: card.title,
            scheduledDate: card.scheduledDate ?? SupabaseDateFormatting.todayDateString(),
            hour: 8,
            minute: 0
        )
        pendingSchedule = schedule
        return schedule
    }

    func cancelTodayReminder(for context: WorkspaceContext) async {
        let identifier = "test.today.\(context.workspaceID.uuidString).\(context.creatorID.uuidString)"
        pendingSchedule = nil
        cancelledIdentifiers.append(identifier)
    }
}

private struct OfflineTodayCardRepository: TodayCardRepository {
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
