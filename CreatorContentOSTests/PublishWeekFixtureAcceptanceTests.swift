import XCTest
@testable import CreatorContentOS

@MainActor
final class PublishWeekFixtureAcceptanceTests: XCTestCase {
    func testManagerPublishesFixtureWeekAndCreatorTodayReadsPublishedCard() async throws {
        let cache = MemoryTodayCacheStore()
        let services = AppServices.fixtureBacked(todayCache: cache)

        XCTAssertFalse(services.weeklyPlan.isSoftLocked)
        XCTAssertEqual(services.weeklyPlan.days.count, 7)
        XCTAssertEqual(services.weekCards.count, 7)
        XCTAssertNil(services.lastRepositoryError)

        await markAllFixtureDaysPlanned(in: services)
        await services.publishCurrentWeekImmediately()

        XCTAssertTrue(services.weeklyPlan.isSoftLocked)
        XCTAssertTrue(services.weeklyPlan.days.allSatisfy(\.isSoftLocked))
        XCTAssertEqual(services.weekCards.count, 7)
        let expectedTodayCard = try expectedPublishedFixtureTodayCard()
        XCTAssertEqual(services.todayCard.title, expectedTodayCard.title)
        XCTAssertEqual(services.todayCard.scheduledDate, expectedTodayCard.scheduledDate)
        XCTAssertEqual(services.lastPublishSummary, "Published 7 cards to Creator Today.")
        XCTAssertEqual(services.lastActionMessage, "Week published. Creator Today is updated.")
        XCTAssertNil(services.lastRepositoryError)
    }

    func testPublishingWeekStoresPublishedCardForOfflineToday() async throws {
        let cache = MemoryTodayCacheStore()
        let services = AppServices.fixtureBacked(todayCache: cache)

        await markAllFixtureDaysPlanned(in: services)
        await services.publishCurrentWeekImmediately()

        let snapshot = try XCTUnwrap(cache.loadSnapshot(for: .creatorFixture))
        let expectedTodayCard = try expectedPublishedFixtureTodayCard()
        XCTAssertEqual(snapshot.todayCard.title, expectedTodayCard.title)
        XCTAssertEqual(snapshot.todayCard.scheduledDate, expectedTodayCard.scheduledDate)
        XCTAssertEqual(snapshot.weekCards.count, 7)
        XCTAssertEqual(snapshot.source, "week-publish")
    }

    func testCreatorTodayUsesCachedPublishedCardWhenRepositoryIsOffline() async throws {
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
        try cache.saveSnapshot(snapshot, for: .creatorFixture)

        let repositories = AppRepositories(
            context: .creatorFixture,
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

    func testCreatorBackupDecisionWritesToArchive() async throws {
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

        let cachedSnapshot = try XCTUnwrap(cache.loadSnapshot(for: .creatorFixture))
        XCTAssertEqual(cachedSnapshot.todayCard.completionState, .usedBackup)
        XCTAssertEqual(cachedSnapshot.source, "decision-synced")
    }

    func testCreatorShotDecisionWritesToArchive() async throws {
        let services = AppServices.fixtureBacked(todayCache: MemoryTodayCacheStore())

        let entry = await services.completeTodayImmediately(with: .shot)

        XCTAssertEqual(services.todayCard.completionState, .shot)
        XCTAssertEqual(entry.decision, .shot)
        XCTAssertEqual(entry.outputLine, "Shot today, ready to post")
        XCTAssertTrue(entry.hasPostThumbnail)
        XCTAssertNil(services.lastRepositoryError)
    }

    func testCreatorSceneShotActionsExposeFeedback() async throws {
        let services = AppServices.fixtureBacked(todayCache: MemoryTodayCacheStore())
        let firstScene = try XCTUnwrap(services.todayCard.scenes.first)

        services.markSceneShot(firstScene)

        XCTAssertTrue(services.isSceneShot(firstScene))
        XCTAssertEqual(services.lastActionMessage, "Scene \(firstScene.number) marked shot.")

        services.markAllScenesShot()

        XCTAssertTrue(services.areAllScenesShot)
        XCTAssertEqual(services.lastActionMessage, "All scenes marked shot.")
    }

    func testCreatorDecisionStaysInLocalArchiveWhenRepositoryWriteFails() async throws {
        let repositories = AppRepositories(
            context: .creatorFixture,
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
        XCTAssertEqual(schedule.title, TodayNotificationCopy.reminderTitle)
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
            for: .creatorFixture
        )
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
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

    func testCreatorDecisionCancelsPendingTodayNotification() async throws {
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
        let runtime = AppRuntime.makeInitialRuntime(
            store: EmptyRuntimeConfigurationStore(),
            debugEnvironment: [:]
        )

        XCTAssertEqual(runtime.mode, .fixtures)
        XCTAssertEqual(runtime.services.todayCard.title, DailyCard.raceWeekToday.title)
    }

    func testInitialRuntimeUsesStoredLiveSessionWithoutDebugEnvironment() throws {
        let session = try makeLiveSession(memberRole: "editor")

        let runtime = AppRuntime.makeInitialRuntime(
            store: FixedRuntimeConfigurationStore(session: session),
            notifications: NoopTodayNotificationScheduler(),
            debugEnvironment: [:]
        )

        XCTAssertEqual(runtime.mode, .live(session))
        XCTAssertTrue(runtime.services.isLiveSupabaseRuntime)
        XCTAssertEqual(runtime.services.memberRole, "editor")
    }

    func testDebugEnvironmentSessionOverridesStoredSessionFailure() throws {
        let runtime = AppRuntime.makeInitialRuntime(
            store: ThrowingRuntimeConfigurationStore(),
            notifications: NoopTodayNotificationScheduler(),
            debugEnvironment: debugPairedEnvironment(memberRole: "owner")
        )

        guard case .live(let session) = runtime.mode else {
            XCTFail("Expected live runtime from debug environment.")
            return
        }

        XCTAssertTrue(runtime.services.isLiveSupabaseRuntime)
        XCTAssertEqual(session.workspaceName, "Debug Workspace")
        XCTAssertEqual(session.creatorDisplayName, "Creator")
        XCTAssertEqual(session.memberRole, "owner")
        XCTAssertEqual(runtime.services.context.workspaceID, session.workspaceID)
    }

    func testAppStateCanSwapToLiveRuntimeAfterPairing() throws {
        let state = AppState(
            runtime: .fixtures(notifications: NoopTodayNotificationScheduler())
        )
        let session = try makeLiveSession(memberRole: "owner")

        state.replaceRuntime(
            .live(
                session: session,
                notifications: NoopTodayNotificationScheduler()
            )
        )

        XCTAssertEqual(state.runtime.mode, .live(session))
        XCTAssertTrue(state.runtime.services.isLiveSupabaseRuntime)
        XCTAssertEqual(state.runtime.services.context.workspaceID, session.workspaceID)
        XCTAssertEqual(state.runtime.services.context.creatorID, session.creatorID)
        XCTAssertEqual(state.runtime.services.context.memberID, session.memberID)
    }

    private func expectedPublishedFixtureTodayCard() throws -> DailyCard {
        let cards = DailyCard.publishedCards(from: WeeklyPlan.raceWeek.softLockedForPublish)
        return try XCTUnwrap(DailyCard.bestTodayCard(from: cards))
    }

    private func makeLiveSession(memberRole: String) throws -> PairedDeviceSession {
        PairedDeviceSession(
            projectURL: try XCTUnwrap(URL(string: "https://example.supabase.co")),
            publishableKey: "sb_publishable_test_key",
            workspaceID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            creatorID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            memberID: UUID(uuidString: "55555555-5555-4555-8555-555555555551")!,
            deviceInstallationID: UUID(uuidString: "66666666-6666-4666-8666-666666666661")!,
            deviceToken: "test-device-token",
            workspaceName: "Live Workspace",
            creatorDisplayName: "Creator",
            memberRole: memberRole,
            pairedAt: Date()
        )
    }

    private func debugPairedEnvironment(memberRole: String) -> [String: String] {
        [
            "MCO_SUPABASE_URL": "http://127.0.0.1:54321",
            "MCO_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_test_key",
            "MCO_DEBUG_PAIRED_WORKSPACE_ID": "11111111-1111-4111-8111-111111111111",
            "MCO_DEBUG_PAIRED_CREATOR_ID": "33333333-3333-4333-8333-333333333333",
            "MCO_DEBUG_PAIRED_MEMBER_ID": "55555555-5555-4555-8555-555555555551",
            "MCO_DEBUG_PAIRED_DEVICE_INSTALLATION_ID": "66666666-6666-4666-8666-666666666661",
            "MCO_DEBUG_PAIRED_DEVICE_TOKEN": "test-device-token",
            "MCO_DEBUG_PAIRED_WORKSPACE_NAME": "Debug Workspace",
            "MCO_DEBUG_PAIRED_CREATOR_DISPLAY_NAME": "Creator",
            "MCO_DEBUG_PAIRED_MEMBER_ROLE": memberRole
        ]
    }

    private func markAllFixtureDaysPlanned(in services: AppServices) async {
        for day in services.weeklyPlan.days {
            await services.updateWeeklyDayStateImmediately(dayID: day.id, state: .planned)
        }
    }
}

private struct EmptyRuntimeConfigurationStore: RuntimeConfigurationStoring {
    func loadPairedSession() throws -> PairedDeviceSession? {
        nil
    }

    func savePairedSession(_ session: PairedDeviceSession) throws {}

    func clearPairedSession() throws {}
}

private struct FixedRuntimeConfigurationStore: RuntimeConfigurationStoring {
    let session: PairedDeviceSession

    func loadPairedSession() throws -> PairedDeviceSession? {
        session
    }

    func savePairedSession(_ session: PairedDeviceSession) throws {}

    func clearPairedSession() throws {}
}

private struct ThrowingRuntimeConfigurationStore: RuntimeConfigurationStoring {
    func loadPairedSession() throws -> PairedDeviceSession? {
        throw RuntimeConfigurationError.decodingFailed
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
            title: TodayNotificationCopy.reminderTitle,
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
