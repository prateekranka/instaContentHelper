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
                if let error = surfacedGenerationError {
                    AdminSignalBlock(
                        title: "Generation error",
                        value: error,
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                }
                if let error = services.lastPublishError?.nilIfBlank {
                    AdminSignalBlock(
                        title: "Publish error",
                        value: error,
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                }
                ActionFeedbackBanner(message: services.lastActionMessage, tone: .ready)
                generatedDaysStrip
                resultBlock
            }
        } bottomBar: {
            GlassCommandBar {
                if let card = displayedCard {
                    VStack(spacing: MCOSpace.s) {
                        PrimaryActionButton(
                            title: publishButtonTitle(for: card),
                            systemImage: card.status.lowercased() == "published" ? "checkmark.circle.fill" : "paperplane.fill"
                        ) {
                            publish(card)
                        }
                        .disabled(!services.canPublishDay(card))
                        .opacity(services.canPublishDay(card) ? 1 : 0.55)
                        .accessibilityIdentifier("daily.publish.selectedDay")

                        SecondaryActionButton(title: isGenerating ? "Generating…" : "Generate again") {
                            generate()
                        }
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.48)
                        .accessibilityIdentifier("daily.generate.submit")
                    }
                    .frame(maxWidth: .infinity)
                } else {
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
        }
        .navigationBarHidden(true)
    }

    // MARK: - State helpers

    private var canGenerate: Bool {
        services.memberRole == "owner" || services.memberRole == "editor"
    }

    private var activeGenerationDate: String? {
        services.generatingDayBriefDates.sorted().first
    }

    private var isGenerating: Bool {
        activeGenerationDate != nil
    }

    private var canSubmit: Bool {
        canGenerate && !isGenerating &&
            !dayBrief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var generateButtonTitle: String {
        let labelDate = activeGenerationDate ?? scheduledDateString
        if isGenerating {
            return "Generating \(shortLabel(for: labelDate))"
        }
        return "Generate \(shortLabel(for: scheduledDateString))"
    }

    private var scheduledDateString: String {
        Self.dateString(from: selectedDate)
    }

    private var surfacedGenerationError: String? {
        if let activeGenerationDate {
            return services.dayBriefGenerationErrors[activeGenerationDate]
        }
        return services.dayBriefGenerationErrors[scheduledDateString]
    }

    private var displayedCard: GeneratedDailyCardDraft? {
        services.dayBriefGeneratedCards[scheduledDateString]
    }

    private var generatedDates: [String] {
        services.dayBriefGeneratedCards.keys.sorted()
    }

    private func publishButtonTitle(for card: GeneratedDailyCardDraft) -> String {
        if card.status.lowercased() == "published" {
            return "Published"
        }
        if services.publishingDayCardIDs.contains(card.id) {
            return "Publishing…"
        }
        return "Publish selected day"
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
                    .disabled(isGenerating)
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
        .disabled(isGenerating)
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
                    Text("Drafting \(shortLabel(for: activeGenerationDate ?? scheduledDateString))")
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
                    subtitle: "Choose one date to review or publish. Published days stay clearly marked."
                )
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MCOSpace.s) {
                        ForEach(generatedDates, id: \.self) { date in
                            Button {
                                if let parsedDate = Self.parseLocalDate(date) {
                                    selectedDate = parsedDate
                                }
                            } label: {
                                StatusChip(
                                    text: generatedDateLabel(date),
                                    tone: date == scheduledDateString ? .ready : .quiet
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isGenerating)
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
                    subtitle: "\(shortLabel(for: card.scheduledDate)) — \(card.status.lowercased() == "published" ? "published" : "draft"). Gemini shot visuals generate with the day so creators see the same reference on Today."
                )
                GeneratedDayPlannedContent(card: card) { assets in
                    if var updated = services.dayBriefGeneratedCards[card.scheduledDate] {
                        updated.storyboardThumbnailAssets = assets
                        services.dayBriefGeneratedCards[card.scheduledDate] = updated
                    }
                }
                AdminSignalBlock(
                    title: "Draft saved for \(shortLabel(for: card.scheduledDate))",
                    value: "This storyboard stays in Daily under Generated days, so you can return and refine it later. Nothing is published automatically.",
                    systemImage: "checkmark.circle",
                    tone: .ready
                )
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

    private func publish(_ card: GeneratedDailyCardDraft) {
        Task { @MainActor in
            _ = await services.publishDayCard(card)
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

    private func generatedDateLabel(_ dateString: String) -> String {
        let label = shortLabel(for: dateString)
        guard services.dayBriefGeneratedCards[dateString]?.status.lowercased() == "published" else {
            return label
        }
        return "\(label) · Published"
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
