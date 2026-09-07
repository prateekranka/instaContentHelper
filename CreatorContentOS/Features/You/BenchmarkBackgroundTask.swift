import Foundation
import BackgroundTasks

/// Persisted benchmark state so a backgrounded or relaunched app can resume
/// the run loop where it stopped.
struct BenchmarkProgress: Codable, Equatable {
    var runCount: Int
    var currentRun: Int
    var durations: [Double]
    var failures: [String]
    var isRunning: Bool
    var benchmarkDate: String
    var brief: String
}

/// File-backed progress store (Application Support by default; injectable for tests).
struct BenchmarkProgressStore {
    let fileURL: URL

    init(fileManager: FileManager = .default) {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = directory.appendingPathComponent("day-generation-benchmark.json")
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() -> BenchmarkProgress? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(BenchmarkProgress.self, from: data)
    }

    func save(_ progress: BenchmarkProgress) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// The benchmark's background task identifier.
enum BenchmarkBackgroundTask {
    static let identifier = "com.prateekranka.creatorcontenthelper.benchmark"

    /// BGTask is not Sendable; this box carries it across the MainActor hop.
    /// `setTaskCompleted` is safe to call once the work settles.
    private final class TaskBox: @unchecked Sendable {
        let task: BGTask
        init(_ task: BGTask) { self.task = task }
        func complete(_ success: Bool) { task.setTaskCompleted(success: success) }
    }

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handle(task)
        }
    }

    /// Continues the running benchmark inside the granted background window.
    private static func handle(_ task: BGTask) {
        let box = TaskBox(task)
        task.expirationHandler = {
            Task { @MainActor in
                BenchmarkRuntime.coordinator?.suspendForBackground()
            }
            box.complete(false)
        }
        Task { @MainActor in
            guard let coordinator = BenchmarkRuntime.coordinator else {
                box.complete(true)
                return
            }
            coordinator.resumeIfNeeded()
            await coordinator.awaitCompletion()
            box.complete(true)
        }
    }
}

/// Main-actor singleton so the background task handler can reach the active
/// coordinator without holding the view hierarchy.
@MainActor
enum BenchmarkRuntime {
    static var coordinator: DayGenerationBenchmarkCoordinator?

    static func scheduleIfNeeded() {
        guard coordinator?.isRunning == true else { return }
        let request = BGProcessingTaskRequest(identifier: BenchmarkBackgroundTask.identifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 1)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func foregrounded() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BenchmarkBackgroundTask.identifier)
        coordinator?.resumeIfNeeded()
    }
}
