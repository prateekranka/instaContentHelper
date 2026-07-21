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
    @State private var showUnpublishConfirmation = false
    @State private var showOverwriteConfirmation = false
    @State private var lightEditCaption = ""
    /// When false (Plan from Creator Profile), hide Admin-mode switch chrome.
    var showsModeSwitch: Bool = true

    var body: some View {
        EditorialScreen {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                header
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
                if let error = services.lastMakeDayAvailableError?.nilIfBlank {
                    AdminSignalBlock(
                        title: "Available on Today",
                        value: error,
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                }
                if let error = services.lastUnpublishDayError?.nilIfBlank {
                    AdminSignalBlock(
                        title: "Unpublish",
                        value: error,
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                }
                if let error = services.lastReadyDayPackageEditError?.nilIfBlank {
                    AdminSignalBlock(
                        title: "Save edits",
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
                if canUnpublish {
                    SecondaryActionButton(
                        title: services.isUnpublishingDay ? "Unpublishing…" : "Unpublish"
                    ) {
                        showUnpublishConfirmation = true
                    }
                    .disabled(services.isUnpublishingDay || isGenerating)
                    .opacity(services.isUnpublishingDay || isGenerating ? 0.48 : 1)
                    .accessibilityIdentifier("daily.unpublish")
                }
                if canMakeAvailable {
                    SecondaryActionButton(
                        title: services.isMakingDayAvailable ? "Making available…" : "Available on Today"
                    ) {
                        makeAvailableOnToday()
                    }
                    .disabled(!canMakeAvailable)
                    .opacity(canMakeAvailable ? 1 : 0.48)
                    .accessibilityIdentifier("daily.availableOnToday")
                }
                PrimaryActionButton(
                    title: generateButtonTitle,
                    systemImage: isGenerating ? "hourglass" : "sparkles"
                ) {
                    requestGenerate()
                }
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.48)
                .accessibilityIdentifier("daily.generate.submit")
            }
        }
        .navigationBarHidden(true)
        .alert("Unpublish this day?", isPresented: $showUnpublishConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Unpublish", role: .destructive) {
                unpublishSelectedDay()
            }
        } message: {
            Text("Returns this ready package to draft. If there was a Decision, the live Decision clears and Archive history stays.")
        }
        .alert("Overwrite ready package?", isPresented: $showOverwriteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Overwrite", role: .destructive) {
                generate(confirmOverwrite: true)
            }
        } message: {
            Text("This replaces the ready package with a new draft. Any live Decision clears; Archive history stays. You will need Available on Today again.")
        }
        .onChange(of: displayedCard?.id) { _, _ in
            lightEditCaption = displayedCard?.caption ?? ""
        }
        .onAppear {
            lightEditCaption = displayedCard?.caption ?? ""
        }
    }

    // MARK: - State helpers

    /// Creator-only product: generation is not gated on owner/editor.
    private var canGenerate: Bool {
        services.canGenerateContent
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

    private var canMakeAvailable: Bool {
        canGenerate
            && !isGenerating
            && !services.isMakingDayAvailable
            && displayedCard != nil
            && displayedCard?.status == "draft"
    }

    private var canUnpublish: Bool {
        canGenerate
            && !isGenerating
            && !services.isUnpublishingDay
            && DayPackageLifecycleStatus.requiresOverwriteConfirmation(displayedCard?.status)
    }

    private var canLightEditReadyPackage: Bool {
        canGenerate
            && !isGenerating
            && !services.isUpdatingReadyDayPackage
            && DayPackageLifecycleStatus.requiresOverwriteConfirmation(displayedCard?.status)
    }

    private var generateButtonTitle: String {
        let labelDate = activeGenerationDate ?? scheduledDateString
        if isGenerating {
            return "Generating \(shortLabel(for: labelDate))"
        }
        if DayPackageLifecycleStatus.requiresOverwriteConfirmation(displayedCard?.status) {
            return "Overwrite \(shortLabel(for: scheduledDateString))"
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

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            if showsModeSwitch {
                HStack {
                    Spacer()
                    FloatingIconButton(systemImage: "ellipsis", label: "Back to Creator Mode") {
                        appState.activeMode = .creator
                    }
                }
            }
            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                Text("Plan")
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
                    subtitle: "Days with a card from this session."
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
                                    text: shortLabel(for: date),
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
                    subtitle: readyPackageSubtitle(for: card)
                )
                GeneratedDayPlannedContent(card: card) { assets in
                    services.dayBriefGeneratedCards[card.scheduledDate]?.storyboardThumbnailAssets = assets
                }
                if canLightEditReadyPackage {
                    lightEditBlock
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

    private var lightEditBlock: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                Text("Light edit")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                Text("Edits keep this day ready — no Unpublish required.")
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                TextEditor(text: $lightEditCaption)
                    .font(MCOType.bodySmall)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 72)
                    .accessibilityIdentifier("daily.ready.edit.caption")
                SecondaryActionButton(
                    title: services.isUpdatingReadyDayPackage ? "Saving…" : "Save caption"
                ) {
                    saveLightEdit()
                }
                .disabled(!canSaveLightEdit)
                .opacity(canSaveLightEdit ? 1 : 0.48)
                .accessibilityIdentifier("daily.ready.edit.save")
            }
        }
    }

    private var canSaveLightEdit: Bool {
        canLightEditReadyPackage
            && lightEditCaption != (displayedCard?.caption ?? "")
    }

    private func readyPackageSubtitle(for card: GeneratedDailyCardDraft) -> String {
        if DayPackageLifecycleStatus.requiresOverwriteConfirmation(card.status) {
            return "\(shortLabel(for: card.scheduledDate)) — ready package. Light edit keeps it ready; Overwrite yields a new draft."
        }
        return "\(shortLabel(for: card.scheduledDate)) — review, then Available on Today."
    }

    // MARK: - Actions

    private func requestGenerate() {
        if DayPackageLifecycleStatus.requiresOverwriteConfirmation(displayedCard?.status) {
            showOverwriteConfirmation = true
            return
        }
        generate(confirmOverwrite: false)
    }

    private func generate(confirmOverwrite: Bool) {
        let dateString = scheduledDateString
        generationStartTime = Date()
        Task { @MainActor in
            defer { generationStartTime = nil }
            do {
                _ = try await services.generateDayCard(
                    scheduledDate: dateString,
                    dayBrief: dayBrief,
                    confirmOverwrite: confirmOverwrite
                )
                dayBrief = ""
                lightEditCaption = services.dayBriefGeneratedCards[dateString]?.caption ?? ""
            } catch {
                // The error is surfaced via services.dayBriefGenerationErrors.
            }
        }
    }

    private func makeAvailableOnToday() {
        let dateString = scheduledDateString
        Task { @MainActor in
            do {
                let shouldOpenToday = try await services.makeDayAvailable(scheduledDate: dateString)
                if shouldOpenToday {
                    appState.activeMode = .creator
                }
                lightEditCaption = services.dayBriefGeneratedCards[dateString]?.caption ?? ""
            } catch {
                // Surfaced via services.lastMakeDayAvailableError; stay on Daily.
            }
        }
    }

    private func unpublishSelectedDay() {
        let dateString = scheduledDateString
        Task { @MainActor in
            do {
                _ = try await services.unpublishDay(scheduledDate: dateString)
                lightEditCaption = services.dayBriefGeneratedCards[dateString]?.caption ?? ""
            } catch {
                // Surfaced via services.lastUnpublishDayError.
            }
        }
    }

    private func saveLightEdit() {
        let dateString = scheduledDateString
        let caption = lightEditCaption
        Task { @MainActor in
            do {
                _ = try await services.updateReadyDayPackage(
                    scheduledDate: dateString,
                    package: ReadyDayPackageUpdate(caption: caption)
                )
            } catch {
                // Surfaced via services.lastReadyDayPackageEditError.
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
