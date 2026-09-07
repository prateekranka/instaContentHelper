import Foundation
import Observation

/// Drives the day-generation benchmark: sequential real runs through the live
/// runtime, progress persisted after every run so backgrounding or relaunch can
/// resume instead of restarting. Cancellation (e.g. background-window expiry)
/// never records a false failure for the in-flight run.
@MainActor
@Observable
final class DayGenerationBenchmarkCoordinator {
    let brief = "Back in Bombay, restarting gym routine, keep it honest and low effort."
    let benchmarkDaysAhead = 90

    private let services: AppServices
    private let store: BenchmarkProgressStore
    private var runTask: Task<Void, Never>?

    private(set) var runCount = 100
    private(set) var currentRun = 0
    private(set) var durations: [Double] = []
    private(set) var failures: [String] = []
    private(set) var isRunning = false

    init(services: AppServices, store: BenchmarkProgressStore = BenchmarkProgressStore()) {
        self.services = services
        self.store = store
    }

    var benchmarkDate: String {
        SupabaseDateFormatting.dateString(daysAfterToday: benchmarkDaysAhead)
    }

    var isLive: Bool {
        services.isLiveSupabaseRuntime
    }

    // MARK: - Controls

    func start(runCount: Int) {
        guard !isRunning else { return }
        self.runCount = runCount
        currentRun = 0
        durations = []
        failures = []
        isRunning = true
        persist()
        runLoop(from: 1)
    }

    func cancel() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
        currentRun = 0
        durations = []
        failures = []
        store.clear()
    }

    /// Continues a persisted run after foregrounding or a background launch.
    func resumeIfNeeded() {
        guard !isRunning else { return }
        guard let saved = store.load(),
              saved.isRunning,
              saved.benchmarkDate == benchmarkDate
        else {
            return
        }
        runCount = saved.runCount
        durations = saved.durations
        failures = saved.failures
        currentRun = saved.currentRun
        guard currentRun < runCount else {
            isRunning = false
            return
        }
        isRunning = true
        runLoop(from: currentRun + 1)
    }

    /// Persists current progress so the next launch resumes it.
    func suspendForBackground() {
        persist()
    }

    func awaitCompletion() async {
        while isRunning {
            try? await Task.sleep(for: .milliseconds(1000))
        }
    }

    // MARK: - Run loop

    private func runLoop(from startIndex: Int) {
        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for index in startIndex...self.runCount {
                if Task.isCancelled { break }
                self.currentRun = index
                let start = Date()
                do {
                    _ = try await self.services.generateDayCard(
                        scheduledDate: self.benchmarkDate,
                        dayBrief: self.brief,
                        confirmOverwrite: true
                    )
                    self.durations.append(Date().timeIntervalSince(start))
                } catch is CancellationError {
                    // Interrupted by background expiry; the run restarts on resume.
                    break
                } catch {
                    self.failures.append("\(index): \(error.localizedDescription)")
                }
                self.persist()
                if index < self.runCount {
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            self.isRunning = false
            if !Task.isCancelled {
                // A cancelled loop (cancel() / background expiry) must not
                // overwrite the cleared or suspended state.
                self.persist()
            }
        }
    }

    private func persist() {
        store.save(
            BenchmarkProgress(
                runCount: runCount,
                currentRun: currentRun,
                durations: durations,
                failures: failures,
                isRunning: isRunning,
                benchmarkDate: benchmarkDate,
                brief: brief
            )
        )
    }
}
