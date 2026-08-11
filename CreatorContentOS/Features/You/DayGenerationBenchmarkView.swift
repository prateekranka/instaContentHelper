import SwiftUI

/// Dev-only benchmark: runs N real day generations through the live runtime and
/// reports p50/p95/max so generation latency stays under the 60s p95 gate.
///
/// Uses a far-future benchmark date (today + 90 days) with `confirmOverwrite: true`,
/// so runs never touch real content. Reached from You > Dev (DEBUG builds only).
struct DayGenerationBenchmarkView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var runCount = 100
    @State private var isRunning = false
    @State private var currentRun = 0
    @State private var lastDurationSeconds: Double?
    @State private var durations: [Double] = []
    @State private var failures: [String] = []
    @State private var summaryCopied = false

    private let brief = "Back in Bombay, restarting gym routine, keep it honest and low effort."
    private let benchmarkDaysAhead = 90

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
                    if !services.isLiveSupabaseRuntime {
                        Text("Benchmark needs the paired live runtime. Sign in and pair a device first.")
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.validationAttention)
                    } else {
                        runControls
                        progressBlock
                        summaryBlock
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
        }
    }

    private var runControls: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
            HStack {
                Text("Runs")
                    .font(PocketSheetType.rowTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                Spacer()
                Stepper("\(runCount)", value: $runCount, in: 1...200)
                    .disabled(isRunning)
            }
            Text("Target date: \(SupabaseDateFormatting.dateString(daysAfterToday: benchmarkDaysAhead)) (far future — real content untouched)")
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            PocketSheetPrimaryAction(title: isRunning ? "Running \(currentRun)/\(runCount)…" : "Run benchmark") {
                startBenchmark()
            }
            .disabled(isRunning)
        }
    }

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
            if let last = lastDurationSeconds {
                Text("Last run: \(String(format: "%.1f", last))s")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }
            if isRunning {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            if !failures.isEmpty {
                Text("Failures: \(failures.count)")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.validationAttention)
            }
        }
    }

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
            Text("Summary")
                .font(PocketSheetType.sectionLabel)
                .foregroundStyle(PocketSheetTheme.Color.ink)
            Text(summaryText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !durations.isEmpty {
                PocketSheetSecondaryAction(title: summaryCopied ? "Copied" : "Copy summary") {
                    UIPasteboard.general.string = summaryText
                    summaryCopied = true
                }
                .disabled(summaryCopied)
            }
            if !failures.isEmpty {
                VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                    Text("Failure detail")
                        .font(PocketSheetType.sectionLabel)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                    ForEach(failures, id: \.self) { failure in
                        Text(failure)
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.validationAttention)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var summaryText: String {
        guard !durations.isEmpty else {
            return "No completed runs yet."
        }
        let sorted = durations.sorted()
        let count = sorted.count
        let p50 = percentile(sorted, 0.50)
        let p95 = percentile(sorted, 0.95)
        let mean = durations.reduce(0, +) / Double(count)
        return """
        Benchmark: \(count) real generations (live runtime)
        p50: \(String(format: "%.1f", p50))s
        p95: \(String(format: "%.1f", p95))s
        min: \(String(format: "%.1f", sorted.first!))s
        max: \(String(format: "%.1f", sorted.last!))s
        mean: \(String(format: "%.1f", mean))s
        failures: \(failures.count)
        gate p95 < 60s: \(p95 < 60 ? "PASS" : "FAIL")
        """
    }

    private func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        let index = Int((Double(sorted.count) * fraction).rounded(.up)) - 1
        return sorted[max(0, index)]
    }

    private func startBenchmark() {
        guard !isRunning, services.isLiveSupabaseRuntime else { return }
        isRunning = true
        durations = []
        failures = []
        summaryCopied = false
        currentRun = 0
        let benchmarkDate = SupabaseDateFormatting.dateString(daysAfterToday: benchmarkDaysAhead)
        Task { @MainActor in
            for index in 1...runCount {
                currentRun = index
                let start = Date()
                do {
                    _ = try await services.generateDayCard(
                        scheduledDate: benchmarkDate,
                        dayBrief: brief,
                        confirmOverwrite: true
                    )
                    durations.append(Date().timeIntervalSince(start))
                    lastDurationSeconds = durations.last
                } catch {
                    failures.append("\(index): \(error.localizedDescription)")
                }
                if index < runCount {
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            isRunning = false
        }
    }
}
