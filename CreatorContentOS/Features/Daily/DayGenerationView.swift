import SwiftUI

/// Day-at-a-time generation. Pick the day you want content for, write a brief
/// for that day — including one-off asks like brand deliverables — and
/// generate a single storyboard + caption card for that date.
struct DayGenerationView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @State private var selectedDate = Date()
    @State private var dayBrief = ""
    @State private var generationStartTime: Date?
    @State private var displayedCardDate: String?

    var body: some View {
        EditorialScreen {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                header
                if !canGenerate {
                    AdminSignalBlock(
                        title: "Editor access required",
                        value: "Only owner and editor sessions can generate daily content.",
                        systemImage: "lock",
                        tone: .warning
                    )
                }
                daySelector
                briefComposer
                if isGenerating {
                    generationProgressBlock
                }
                if let error = services.dayBriefGenerationErrors[scheduledDateString] {
                    AdminSignalBlock(
                        title: "Generation error",
                        value: error,
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                }
                generatedDaysStrip
                resultBlock
            }
        } bottomBar: {
            GlassCommandBar {
                PrimaryActionButton(
                    title: generateButtonTitle,
                    systemImage: isGenerating ? "hourglass" : "sparkles"
                ) {
                    generate()
                }
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.48)
                .accessibilityIdentifier("daily.generate.submit")
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - State helpers

    private var canGenerate: Bool {
        services.memberRole == "owner" || services.memberRole == "editor"
    }

    private var isGenerating: Bool {
        services.generatingDayBriefDates.contains(scheduledDateString)
    }

    private var canSubmit: Bool {
        canGenerate && !isGenerating &&
            !dayBrief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var generateButtonTitle: String {
        if isGenerating {
            return "Generating \(shortLabel(for: scheduledDateString))"
        }
        return "Generate \(shortLabel(for: scheduledDateString))"
    }

    private var scheduledDateString: String {
        Self.dateString(from: selectedDate)
    }

    private var displayedCard: GeneratedDailyCardDraft? {
        if let displayedCardDate, let card = services.dayBriefGeneratedCards[displayedCardDate] {
            return card
        }
        return services.dayBriefGeneratedCards[scheduledDateString]
    }

    private var generatedDates: [String] {
        services.dayBriefGeneratedCards.keys.sorted()
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            HStack {
                Spacer()
                FloatingIconButton(systemImage: "ellipsis", label: "Back to Creator Mode") {
                    appState.activeMode = .creator
                }
            }
            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                Text("Daily Content")
                    .font(MCOType.display)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text("One day at a time: pick a date, brief it, and get a storyboard and caption.")
                    .font(MCOType.body)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var daySelector: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            WeeklySectionTitle(
                title: "Day",
                subtitle: "Today, tomorrow, or any day you want to plan ahead."
            )
            JournalBlock {
                VStack(alignment: .leading, spacing: MCOSpace.m) {
                    HStack(spacing: MCOSpace.s) {
                        ForEach(quickDayOptions, id: \.dateString) { option in
                            quickDayChip(option)
                        }
                    }
                    DatePicker(
                        "Another date",
                        selection: $selectedDate,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .font(MCOType.bodySmall)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .tint(MCOTheme.Color.oxblood)
                    .accessibilityIdentifier("daily.generate.datePicker")
                }
            }
        }
    }

    private func quickDayChip(_ option: QuickDayOption) -> some View {
        let isSelected = option.dateString == scheduledDateString
        return Button {
            selectedDate = option.date
        } label: {
            VStack(spacing: MCOSpace.xxs) {
                Text(option.title)
                    .font(MCOType.caption)
                Text(SupabaseDateFormatting.displayDate(for: option.dateString))
                    .font(MCOType.tinyLabel)
            }
            .foregroundStyle(isSelected ? MCOTheme.Color.oxblood : MCOTheme.Color.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                isSelected
                    ? MCOTheme.Color.oxblood.opacity(0.12)
                    : MCOTheme.Color.paperRaised.opacity(0.58)
            )
            .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                    .stroke(
                        isSelected ? MCOTheme.Color.oxblood.opacity(0.62) : MCOTheme.Color.hairline,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("daily.generate.day.\(option.title)")
    }

    private var briefComposer: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            WeeklySectionTitle(
                title: "Brief for the day",
                subtitle: "What is happening, what should the content feel like, and any one-off asks — brand work included."
            )
            JournalBlock {
                ZStack(alignment: .topLeading) {
                    if dayBrief.isEmpty {
                        Text("e.g. Back in Bombay, first gym session after travel. Or: brand deliverable — unbox the recovery drink at home, honest tone, one Reel.")
                            .font(MCOType.bodySmall)
                            .foregroundStyle(MCOTheme.Color.inkMuted)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    TextEditor(text: $dayBrief)
                        .font(MCOType.bodySmall)
                        .foregroundStyle(MCOTheme.Color.ink)
                        .scrollContentBackground(.hidden)
                        .disabled(isGenerating || !canGenerate)
                        .accessibilityIdentifier("daily.generate.brief")
                }
                .padding(MCOSpace.s)
                .frame(minHeight: 128, alignment: .topLeading)
                .background(MCOTheme.Color.paperRaised.opacity(0.86))
                .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                        .stroke(MCOTheme.Color.hairlineStrong.opacity(0.8), lineWidth: 1)
                }
            }
        }
    }

    private var generationProgressBlock: some View {
        JournalBlock {
            HStack(spacing: MCOSpace.s) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                    Text("Drafting \(shortLabel(for: scheduledDateString))")
                        .font(MCOType.headline)
                        .foregroundStyle(MCOTheme.Color.ink)
                    Text("Deep reasoning takes a couple of minutes. Validation may retry once or twice.")
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                }
                Spacer()
                if let startTime = generationStartTime {
                    TimelineView(.periodic(from: startTime, by: 1)) { context in
                        Text(Self.elapsedText(context.date.timeIntervalSince(startTime)))
                            .font(MCOType.caption)
                            .foregroundStyle(MCOTheme.Color.brass)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var generatedDaysStrip: some View {
        if !generatedDates.isEmpty {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                WeeklySectionTitle(
                    title: "Generated days",
                    subtitle: "Days with a card from this session."
                )
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MCOSpace.s) {
                        ForEach(generatedDates, id: \.self) { date in
                            Button {
                                displayedCardDate = date
                            } label: {
                                StatusChip(
                                    text: shortLabel(for: date),
                                    tone: date == (displayedCardDate ?? scheduledDateString) ? .ready : .quiet
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("daily.generated.\(date)")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultBlock: some View {
        if let card = displayedCard {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                WeeklySectionTitle(
                    title: "Storyboard & caption",
                    subtitle: "\(shortLabel(for: card.scheduledDate)) — review, then shoot from the storyboard."
                )
                GeneratedDayPlannedContent(card: card) { assets in
                    services.dayBriefGeneratedCards[card.scheduledDate]?.storyboardThumbnailAssets = assets
                }
            }
        } else {
            AdminSignalBlock(
                title: "No card yet",
                value: "Write the brief for the selected day and generate to see the storyboard and caption here.",
                systemImage: "wand.and.stars",
                tone: .quiet
            )
        }
    }

    // MARK: - Actions

    private func generate() {
        let dateString = scheduledDateString
        generationStartTime = Date()
        displayedCardDate = dateString
        Task { @MainActor in
            defer { generationStartTime = nil }
            do {
                _ = try await services.generateDayCard(
                    scheduledDate: dateString,
                    dayBrief: dayBrief
                )
                dayBrief = ""
            } catch {
                // The error is surfaced via services.dayBriefGenerationErrors.
            }
        }
    }

    // MARK: - Dates

    private struct QuickDayOption {
        let title: String
        let date: Date
        let dateString: String
    }

    private var quickDayOptions: [QuickDayOption] {
        let titles = ["Today", "Tomorrow", "Day after"]
        return titles.enumerated().compactMap { offset, title in
            guard let date = Calendar(identifier: .gregorian)
                .date(byAdding: .day, value: offset, to: Date()) else {
                return nil
            }
            return QuickDayOption(
                title: title,
                date: date,
                dateString: Self.dateString(from: date)
            )
        }
    }

    private func shortLabel(for dateString: String) -> String {
        if dateString == Self.dateString(from: Date()) {
            return "today"
        }
        guard let date = Self.parseLocalDate(dateString) else {
            return dateString
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }

    private static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func parseLocalDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }

    private static func elapsedText(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
