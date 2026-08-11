import XCTest
@testable import CreatorContentOS

/// Benchmark progress store round-trip + coordinator resume behavior.
@MainActor
final class BenchmarkProgressStoreTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("benchmark-progress-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    func testProgressRoundTrip() throws {
        let store = BenchmarkProgressStore(fileURL: tempURL)
        let progress = BenchmarkProgress(
            runCount: 100,
            currentRun: 42,
            durations: [21.5, 22.1, 19.8],
            failures: ["7: boom"],
            isRunning: true,
            benchmarkDate: "2026-11-09",
            brief: "Bench brief"
        )

        store.save(progress)
        let loaded = store.load()

        XCTAssertEqual(loaded, progress)
    }

    func testClearRemovesProgress() throws {
        let store = BenchmarkProgressStore(fileURL: tempURL)
        store.save(
            BenchmarkProgress(
                runCount: 1, currentRun: 1, durations: [1.0], failures: [],
                isRunning: false, benchmarkDate: "2026-11-09", brief: "b"
            )
        )
        store.clear()
        XCTAssertNil(store.load())
    }

    func testCoordinatorRunsAndPersistsWithFixtureServices() async throws {
        let services = AppServices.fixtureBacked()
        let store = BenchmarkProgressStore(fileURL: tempURL)
        let coordinator = DayGenerationBenchmarkCoordinator(services: services, store: store)

        coordinator.start(runCount: 3)
        await coordinator.awaitCompletion()

        XCTAssertEqual(coordinator.durations.count, 3)
        XCTAssertEqual(coordinator.failures.count, 0)
        XCTAssertFalse(coordinator.isRunning)
        // Persisted state marks the run complete.
        XCTAssertEqual(store.load()?.currentRun, 3)
    }

    func testCoordinatorResumesFromPersistedProgress() async throws {
        let services = AppServices.fixtureBacked()
        let store = BenchmarkProgressStore(fileURL: tempURL)
        let date = SupabaseDateFormatting.dateString(daysAfterToday: 90)
        store.save(
            BenchmarkProgress(
                runCount: 5,
                currentRun: 2,
                durations: [20.0, 21.0],
                failures: [],
                isRunning: true,
                benchmarkDate: date,
                brief: "Back in Bombay, restarting gym routine, keep it honest and low effort."
            )
        )
        let coordinator = DayGenerationBenchmarkCoordinator(services: services, store: store)

        coordinator.resumeIfNeeded()
        await coordinator.awaitCompletion()

        XCTAssertEqual(coordinator.durations.count, 5)
        XCTAssertEqual(coordinator.currentRun, 5)
        XCTAssertFalse(coordinator.isRunning)
    }

    func testCoordinatorCancelClearsState() async throws {
        let services = AppServices.fixtureBacked()
        let store = BenchmarkProgressStore(fileURL: tempURL)
        let coordinator = DayGenerationBenchmarkCoordinator(services: services, store: store)
        coordinator.start(runCount: 50)

        coordinator.cancel()

        XCTAssertFalse(coordinator.isRunning)
        XCTAssertTrue(coordinator.durations.isEmpty)
        XCTAssertNil(store.load())
    }
}
