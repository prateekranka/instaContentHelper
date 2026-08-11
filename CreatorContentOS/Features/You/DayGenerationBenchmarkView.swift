import SwiftUI

/// Dev-only benchmark: runs N real day generations through the live runtime and
/// reports p50/p95/max so generation latency stays under the 60s p95 gate.
///
/// Uses a far-future benchmark date (today + 90 days) with `confirmOverwrite: true`,
/// so runs never touch real content. Progress persists after every run, so the
/// benchmark survives backgrounding (BGProcessingTask) and relaunches. Reached
/// from You > Dev (DEBUG builds only).
struct DayGenerationBenchmarkView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var coordinator: DayGenerationBenchmarkCoordinator?
    @State private var runCount = 100
    @State private var summaryCopied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
                    if let coordinator {
                        if !coordinator.isLive {
                            Text("Benchmark needs the paired live runtime. Sign in and pair a device first.")
                                .font(PocketSheetType.rowSubtitle)
                                .foregroundStyle(PocketSheetTheme.Color.validationAttention)
                        } else {
                            runControls(coordinator)
                            progressBlock(coordinator)
                            summaryBlock(coordinator)
                        }
                    }
                }
                .padding(PocketSheetSpace.l)
            }
            .background(PocketSheetTheme.Color.paper.ignoresSafeArea())
            .navigationTitle("Generation benchmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if coordinator == nil {
                    let newCoordinator = DayGenerationBenchmarkCoordinator(services: services)
                    coordinator = newCoordinator
                    BenchmarkRuntime.coordinator = newCoordinator
                }
                coordinator?.resumeIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    BenchmarkRuntime.scheduleIfNeeded()
                case .active:
                    BenchmarkRuntime.foregrounded()
                default:
                    break
                }
            }
        }
    }

    private func runControls(_ coordinator: DayGenerationBenchmarkCoordinator) -> some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
            HStack {
                Text("Runs")
                    .font(PocketSheetType.rowTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                Spacer()
                Stepper("\(runCount)", value: $runCount, in: 1...200)
                    .disabled(coordinator.isRunning)
            }
            Text("Target date: \(coordinator.benchmarkDate) (far future — real content untouched)")
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            PocketSheetPrimaryAction(
                title: coordinator.isRunning
                    ? "Running \(coordinator.currentRun)/\(coordinator.runCount)…"
                    : "Run benchmark"
            ) {
                coordinator.start(runCount: runCount)
            }
            .disabled(coordinator.isRunning)
            if coordinator.isRunning {
                PocketSheetSecondaryAction(title: "Cancel") {
                    coordinator.cancel()
                }
            }
        }
    }

    private func progressBlock(_ coordinator: DayGenerationBenchmarkCoordinator) -> some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
            if let last = coordinator.durations.last {
                Text("Last run: \(String(format: "%.1f", last))s")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }
            if coordinator.isRunning {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            if !coordinator.failures.isEmpty {
                Text("Failures: \(coordinator.failures.count)")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.validationAttention)
            }
        }
    }

    private func summaryBlock(_ coordinator: DayGenerationBenchmarkCoordinator) -> some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
            Text("Summary")
                .font(PocketSheetType.sectionLabel)
                .foregroundStyle(PocketSheetTheme.Color.ink)
            Text(summaryText(coordinator))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !coordinator.durations.isEmpty {
                PocketSheetSecondaryAction(title: summaryCopied ? "Copied" : "Copy summary") {
                    UIPasteboard.general.string = summaryText(coordinator)
                    summaryCopied = true
                }
                .disabled(summaryCopied)
            }
            if !coordinator.failures.isEmpty {
                VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                    Text("Failure detail")
                        .font(PocketSheetType.sectionLabel)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                    ForEach(coordinator.failures, id: \.self) { failure in
                        Text(failure)
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.validationAttention)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func summaryText(_ coordinator: DayGenerationBenchmarkCoordinator) -> String {
        guard !coordinator.durations.isEmpty else {
            return "No completed runs yet."
        }
        let sorted = coordinator.durations.sorted()
        let count = sorted.count
        let p50 = percentile(sorted, 0.50)
        let p95 = percentile(sorted, 0.95)
        let mean = coordinator.durations.reduce(0, +) / Double(count)
        return """
        Benchmark: \(count) real generations (live runtime)
        p50: \(String(format: "%.1f", p50))s
        p95: \(String(format: "%.1f", p95))s
        min: \(String(format: "%.1f", sorted.first!))s
        max: \(String(format: "%.1f", sorted.last!))s
        mean: \(String(format: "%.1f", mean))s
        failures: \(coordinator.failures.count)
        gate p95 < 60s: \(p95 < 60 ? "PASS" : "FAIL")
        """
    }

    private func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        let index = Int((Double(sorted.count) * fraction).rounded(.up)) - 1
        return sorted[max(0, index)]
    }
}
