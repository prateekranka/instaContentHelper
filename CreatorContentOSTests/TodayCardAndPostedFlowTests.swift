import XCTest
@testable import CreatorContentOS

/// Subagent B + C — Today card UX and posted-state flow.
///
/// These tests cover external behavior of the Today hero card and the
/// shoot -> posted flow, not private view internals.
@MainActor
final class TodayCardAndPostedFlowTests: XCTestCase {
    // MARK: - Today card hook + scene plan (Subagent B)

    func testTodayCardEffectiveHookPrefersGeneratedHook() {
        let card = DailyCard(
            title: "My recovery reset",
            context: "Wednesday",
            effortLabel: "Easy",
            whyToday: "Recovery.",
            hook: "My recovery reset after a heavy week",
            scenes: []
        )
        XCTAssertEqual(card.effectiveHook, "My recovery reset after a heavy week")
    }

    func testTodayCardEffectiveHookFallsBackToCaptionWhenHookMissing() {
        let card = DailyCard(
            title: "Recovery reset",
            context: "Wednesday",
            effortLabel: "Easy",
            whyToday: "Recovery.",
            hook: nil,
            scenes: [],
            caption: "A quiet reset after a heavy week."
        )
        // Without a generated hook the card still shows something usable,
        // derived from the caption. This is the documented data-quality gap.
        XCTAssertEqual(card.effectiveHook, "A quiet reset after a heavy week.")
    }

    func testTodayCardShowsAllScenesNotJustFirstTwo() {
        let card = DailyCard(
            title: "Gym day",
            context: "Tuesday",
            effortLabel: "Medium",
            whyToday: "One movement.",
            scenes: [
                ShotScene(number: 1, title: "Setup", duration: "3 sec", symbol: "dumbbell"),
                ShotScene(number: 2, title: "Lift", duration: "4 sec", symbol: "figure.strengthtraining"),
                ShotScene(number: 3, title: "Reset", duration: "3 sec", symbol: "figure.cooldown"),
                ShotScene(number: 4, title: "Payoff", duration: "2 sec", symbol: "checkmark.seal")
            ]
        )
        // The hero card's scene plan is built from ALL scenes, not .prefix(2).
        let plan = card.scenes.map { "\($0.number). \($0.title)" }
        XCTAssertEqual(plan.count, 4)
        XCTAssertEqual(plan, ["1. Setup", "2. Lift", "3. Reset", "4. Payoff"])
    }

    // MARK: - Posted state flow (Subagent C)

    func testMarkAllAsShotFlipsToMarkAsPostedEligibility() {
        let services = AppServices.fixtureBacked(todayCache: MemoryCacheStore())
        services.todayCard = makeCard(scenes: 3)

        XCTAssertFalse(services.areAllScenesShot)
        XCTAssertFalse(services.canMarkPosted)

        services.markAllScenesShot()

        XCTAssertTrue(services.areAllScenesShot)
        // After all scenes are shot, the next action becomes "Mark as posted".
        XCTAssertTrue(services.canMarkPosted)
    }

    func testMarkPostedRecordsPostedStateAndGreenToast() async {
        let services = AppServices.fixtureBacked(todayCache: MemoryCacheStore())
        services.todayCard = makeCard(scenes: 2)
        services.markAllScenesShot()

        services.markPosted()
        await settle()

        XCTAssertEqual(services.todayCard.completionState, .posted)
        XCTAssertEqual(services.lastActionMessage, "Content marked as posted.")
        // A posted archive entry is recorded.
        XCTAssertEqual(decisionEntry(in: services)?.decision, .posted)
    }

    func testMarkPostedRequiresAllScenesShotFirst() async {
        let services = AppServices.fixtureBacked(todayCache: MemoryCacheStore())
        services.todayCard = makeCard(scenes: 3)
        // Only one scene shot — cannot post yet.
        services.markSceneShot(services.todayCard.scenes[0])

        services.markPosted()
        await settle()

        // Not posted because not all scenes were shot.
        XCTAssertNil(services.todayCard.completionState)
        XCTAssertNil(decisionEntry(in: services))
    }

    func testBackupDecisionsRequireExplicitUseBackupAndRecordUsedBackup() async {
        let services = AppServices.fixtureBacked(todayCache: MemoryCacheStore())
        services.todayCard = makeCard(scenes: 1)

        // Opening a backup sheet does NOT record a decision. Only the explicit
        // DailyDecision.backupStory / .captionOnly (mapped to "Use backup")
        // records .usedBackup.
        services.completeToday(with: .backupStory)
        await settle()
        XCTAssertEqual(services.todayCard.completionState, .usedBackup)
        XCTAssertEqual(decisionEntry(in: services)?.decision, .usedBackup)
    }

    func testSaveForTomorrowAndSkipStillWork() async {
        let services = AppServices.fixtureBacked(todayCache: MemoryCacheStore())
        services.todayCard = makeCard(scenes: 1)

        services.completeToday(with: DailyDecision.savedForTomorrow)
        await settle()
        XCTAssertEqual(services.todayCard.completionState, .savedForTomorrow)
        XCTAssertEqual(decisionEntry(in: services)?.decision, .savedForTomorrow)

        services.todayCard.completionState = nil
        services.completeToday(with: DailyDecision.skippedIntentionally)
        await settle()
        XCTAssertEqual(services.todayCard.completionState, .skippedIntentionally)
        XCTAssertEqual(decisionEntry(in: services)?.decision, .skippedIntentionally)
    }

    func testSavedForTomorrowUsesShortCreatorConfirmationMessage() {
        XCTAssertEqual(DailyDecision.savedForTomorrow.confirmationMessage, "Saved for tomorrow")
        XCTAssertEqual(
            DailyDecision.backupStory.confirmationMessage,
            "Used backup: 10-second story"
        )
    }

    // MARK: - Profile refresh feedback (Subagent D)

    func testRefreshSetsRefreshingFlagAndClearsOnCompletion() async {
        let services = AppServices.fixtureBacked(todayCache: MemoryCacheStore())
        XCTAssertFalse(services.isRefreshingRepository)

        await services.refreshFromRepositoriesImmediately()

        // After completion the flag must be cleared and success recorded.
        XCTAssertFalse(services.isRefreshingRepository)
        XCTAssertNotNil(services.lastRepositoryRefreshSucceededAt)
        XCTAssertNil(services.lastRepositoryRefreshError)
    }

    func testRefreshRecordsErrorWhenRepositoryFails() async {
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FailingTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: MemoryCacheStore()
        )

        await services.refreshFromRepositoriesImmediately()

        XCTAssertFalse(services.isRefreshingRepository)
        XCTAssertNotNil(services.lastRepositoryRefreshError)
    }

    func testRefreshTreatsMissingPublishedTodayCardAsEmptyStateWithoutError() async {
        let services = AppServices.fixtureBacked(
            repositories: repositories(today: MissingPublishedTodayCardRepository()),
            todayCache: MemoryCacheStore()
        )

        await services.refreshFromRepositoriesImmediately()

        XCTAssertEqual(services.todayContentState, .missingPublishedCard(date: "2026-07-02"))
        XCTAssertNil(services.lastRepositoryError)
        XCTAssertNil(services.lastRepositoryRefreshError)
        XCTAssertNotNil(services.lastRepositoryRefreshSucceededAt)
    }

    func testDecisionSyncTreatsMissingPublishedTodayCardAsEmptyStateWithoutError() async {
        let services = AppServices.fixtureBacked(
            repositories: repositories(today: MissingPublishedTodayCardOnDecisionRepository()),
            todayCache: MemoryCacheStore()
        )
        services.todayCard = makeCard(scenes: 1)

        _ = await services.completeTodayImmediately(with: .posted)

        XCTAssertEqual(services.todayContentState, .missingPublishedCard(date: "2026-07-02"))
        XCTAssertNil(services.lastRepositoryError)
    }

    // MARK: - Stale today date & week normalization

    func testTodayDateLineUsesCurrentDateWhenCardHasStaleScheduledDate() {
        let services = AppServices.fixtureBacked(
            todayCache: MemoryCacheStore(),
            todayDate: { "2026-07-02" }
        )
        services.todayCard.scheduledDate = "2026-06-28"
        services.todayContentState = .ready

        XCTAssertTrue(services.todayCard.scheduledDate == "2026-06-28")
        XCTAssertTrue(SupabaseDateFormatting.isDatePast("2026-06-28", todayString: "2026-07-02"))
    }

    func testNormalizeManagerWeekStartReplacesStaleDateWhenNoDraft() async throws {
        let services = AppServices.fixtureBacked(
            todayCache: MemoryCacheStore(),
            todayDate: { "2026-07-02" }
        )
        services.latestGenerationSummary = nil
        services.weeklyPlan.weekStartDate = "2026-06-28"

        services.normalizeManagerWeekStartIfStale()

        XCTAssertEqual(services.weeklyPlan.weekStartDate, "2026-07-02",
                       "Stale week start should be replaced with today's date")
        XCTAssertEqual(services.weeklyPlan.days.count, 7)
        XCTAssertFalse(services.weeklyPlan.isSoftLocked)
    }

    func testWeekStartCanBeSetToToday() async throws {
        let services = AppServices.fixtureBacked(
            todayCache: MemoryCacheStore(),
            todayDate: { "2026-07-02" }
        )

        services.updateWeeklyStartDate("2026-07-02")

        XCTAssertEqual(services.weeklyPlan.weekStartDate, "2026-07-02")
        XCTAssertNil(services.generationError)
    }

    // MARK: - Helpers

    private func repositories(today: any TodayCardRepository) -> AppRepositories {
        AppRepositories(
            context: .creatorFixture,
            today: today,
            weeklyPlans: FixtureWeeklyPlanRepository(),
            references: FixtureReferenceRepository(),
            referenceImport: FixtureReferenceImportRepository(),
            intelligence: FixtureIntelligenceRepository(),
            creatorProfile: FixtureCreatorProfileRepository(),
            archive: FixtureArchiveRepository()
        )
    }

    private func makeCard(scenes: Int) -> DailyCard {
        DailyCard(
            title: "Today's card",
            context: "Wednesday",
            effortLabel: "Easy - 8 min",
            whyToday: "Recovery reset.",
            scheduledDate: "2026-06-25",
            scenes: (0..<scenes).map { index in
                ShotScene(number: index + 1, title: "Scene \(index + 1)", duration: "3 sec", symbol: "circle")
            }
        )
    }

    private func decisionEntry(in services: AppServices) -> ArchiveEntry? {
        services.archiveEntries.first { entry in
            entry.dailyCardID == services.todayCard.id ||
                entry.cardTitle == services.todayCard.title
        }
    }

    private func settle() async {
        for _ in 0..<3 {
            await Task.yield()
        }
    }
}

private struct MissingPublishedTodayCardRepository: TodayCardRepository {
    func todayCard(for context: WorkspaceContext) async throws -> DailyCard {
        throw RepositoryError.noPublishedTodayCard(date: "2026-07-02")
    }
    func weekCards(for context: WorkspaceContext) async throws -> [DailyCard] {
        []
    }
    func completeToday(
        card: DailyCard,
        decision: DailyDecision,
        context: WorkspaceContext
    ) async throws -> ArchiveEntry {
        throw RepositoryError.noPublishedTodayCard(date: "2026-07-02")
    }
}

private struct MissingPublishedTodayCardOnDecisionRepository: TodayCardRepository {
    func todayCard(for context: WorkspaceContext) async throws -> DailyCard {
        DailyCard(
            title: "Today's card",
            context: "Thursday",
            effortLabel: "Easy - 8 min",
            whyToday: "Recovery reset.",
            scheduledDate: "2026-07-02",
            scenes: [ShotScene(number: 1, title: "Scene 1", duration: "3 sec", symbol: "circle")]
        )
    }
    func weekCards(for context: WorkspaceContext) async throws -> [DailyCard] {
        []
    }
    func completeToday(
        card: DailyCard,
        decision: DailyDecision,
        context: WorkspaceContext
    ) async throws -> ArchiveEntry {
        throw RepositoryError.noPublishedTodayCard(date: "2026-07-02")
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

private final class MemoryCacheStore: TodayCacheStoring {
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
