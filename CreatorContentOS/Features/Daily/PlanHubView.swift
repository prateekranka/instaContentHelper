import SwiftUI

/// Buried Plan hub: calendar → brief → Generate → result / Available / Unpublish →
/// collapsed Creator Profile and References.
struct PlanHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @State private var selectedDate = Date()
    @State private var visibleMonth = Date()
    @State private var dayBrief = ""
    @State private var generationStartTime: Date?
    @State private var showUnpublishConfirmation = false
    @State private var showOverwriteConfirmation = false
    @State private var lightEditCaption = ""
    @State private var isCreatorProfileExpanded = false
    @State private var isReferencesExpanded = false
    /// When false (Creator Profile → Plan), hide Admin-mode switch chrome.
    var showsModeSwitch: Bool = true
    /// Optional `yyyy-MM-dd` preselection from Today Edit / ⋯ / empty CTA.
    var initialSelectedDate: String? = nil

    var body: some View {
        EditorialScreen {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                header
                calendarSection
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
                resultBlock
                lifecycleActions
                creatorProfileAccordion
                referencesAccordion
            }
        } bottomBar: {
            GlassCommandBar {
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
        .onChange(of: selectedDate) { _, newDate in
            visibleMonth = newDate
            lightEditCaption = displayedCard?.caption ?? ""
        }
        .onAppear {
            applyPendingPlanDateSelection()
            visibleMonth = selectedDate
            lightEditCaption = displayedCard?.caption ?? ""
        }
    }

    private func applyPendingPlanDateSelection() {
        let candidate: String?
        if let initial = initialSelectedDate?.nilIfBlank {
            appState.preparePlan(selecting: initial)
            candidate = initial
        } else {
            // Profile / Admin Plan opens on local today — drop any leftover Edit date.
            _ = appState.consumePlanSelectedDate()
            candidate = nil
        }
        guard let candidate, let date = Self.parseLocalDate(candidate) else { return }
        selectedDate = date
        visibleMonth = date
    }

    // MARK: - State helpers

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
        services.dayPackage(for: scheduledDateString)
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
                    .accessibilityIdentifier("plan.title")
                Text("Pick a date, brief it, generate a draft, then make it available on Today.")
                    .font(MCOType.body)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            WeeklySectionTitle(
                title: "Calendar",
                subtitle: "Select the day to plan. Dots show package state."
            )
            JournalBlock {
                VStack(alignment: .leading, spacing: MCOSpace.m) {
                    calendarLegend
                    monthHeader
                    weekdayHeader
                    monthGrid
                }
            }
            .accessibilityIdentifier("plan.calendar")
        }
    }

    private var calendarLegend: some View {
        HStack(spacing: MCOSpace.m) {
            legendItem(color: MCOTheme.Color.success, label: "Ready")
            legendItem(color: MCOTheme.Color.warning, label: "Draft")
            HStack(spacing: MCOSpace.xs) {
                Circle()
                    .stroke(MCOTheme.Color.hairlineStrong, lineWidth: 1)
                    .frame(width: 8, height: 8)
                Text("Empty")
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Legend: green ready, yellow draft, none empty")
        .accessibilityIdentifier("plan.calendar.legend")
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: MCOSpace.xs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.inkMuted)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(MCOTheme.Color.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous month")

            Spacer()
            Text(monthTitle(for: visibleMonth))
                .font(MCOType.headline)
                .foregroundStyle(MCOTheme.Color.ink)
            Spacer()

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(MCOTheme.Color.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next month")
        }
    }

    private var weekdayHeader: some View {
        let symbols = Calendar(identifier: .gregorian).veryShortWeekdaySymbols
        return HStack(spacing: 0) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let days = daysInVisibleMonth()
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
            spacing: MCOSpace.xs
        ) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    calendarDayCell(day)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    private func calendarDayCell(_ date: Date) -> some View {
        let dateString = Self.dateString(from: date)
        let state = PlanCalendarDayState.from(packageStatus: services.dayPackage(for: dateString)?.status)
        let isSelected = dateString == scheduledDateString
        let isSelectable = date >= Self.startOfToday()
        let dayNumber = Calendar(identifier: .gregorian).component(.day, from: date)

        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 4) {
                Text("\(dayNumber)")
                    .font(MCOType.bodySmall)
                    .foregroundStyle(
                        isSelected
                            ? MCOTheme.Color.oxblood
                            : (isSelectable ? MCOTheme.Color.ink : MCOTheme.Color.inkMuted.opacity(0.45))
                    )
                Group {
                    switch state {
                    case .ready:
                        Circle()
                            .fill(MCOTheme.Color.success)
                            .frame(width: 6, height: 6)
                    case .draft:
                        Circle()
                            .fill(MCOTheme.Color.warning)
                            .frame(width: 6, height: 6)
                    case .empty:
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                isSelected
                    ? MCOTheme.Color.oxblood.opacity(0.12)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                        .stroke(MCOTheme.Color.oxblood.opacity(0.62), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isGenerating || !isSelectable)
        .accessibilityLabel(calendarAccessibilityLabel(dateString: dateString, dayNumber: dayNumber, state: state))
        .accessibilityIdentifier("plan.calendar.day.\(dateString)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func calendarAccessibilityLabel(
        dateString: String,
        dayNumber: Int,
        state: PlanCalendarDayState
    ) -> String {
        let stateLabel: String
        switch state {
        case .ready: stateLabel = "ready"
        case .draft: stateLabel = "draft"
        case .empty: stateLabel = "empty"
        }
        return "Day \(dayNumber), \(stateLabel), \(dateString)"
    }

    private var briefComposer: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            WeeklySectionTitle(
                title: "Daily generation prompt",
                subtitle: "What is happening, what should the content feel like, and any one-off asks."
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
                value: "Write the prompt for the selected day and generate to see the storyboard and caption here.",
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

    @ViewBuilder
    private var lifecycleActions: some View {
        if canMakeAvailable || canUnpublish {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
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
            }
        }
    }

    private var creatorProfileAccordion: some View {
        DisclosureGroup(isExpanded: $isCreatorProfileExpanded) {
            CreatorProfileAdminView(presentation: .embedded)
                .padding(.top, MCOSpace.s)
        } label: {
            Text("Creator Profile")
                .font(MCOType.headline)
                .foregroundStyle(MCOTheme.Color.ink)
        }
        .tint(MCOTheme.Color.oxblood)
        .accessibilityIdentifier("plan.accordion.creatorProfile")
    }

    private var referencesAccordion: some View {
        DisclosureGroup(isExpanded: $isReferencesExpanded) {
            IntelligenceHomeView(presentation: .embedded)
                .padding(.top, MCOSpace.s)
        } label: {
            Text("References")
                .font(MCOType.headline)
                .foregroundStyle(MCOTheme.Color.ink)
        }
        .tint(MCOTheme.Color.oxblood)
        .accessibilityIdentifier("plan.accordion.references")
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
                lightEditCaption = services.dayPackage(for: dateString)?.caption ?? ""
            } catch {
                // Surfaced via services.dayBriefGenerationErrors.
            }
        }
    }

    private func makeAvailableOnToday() {
        let dateString = scheduledDateString
        Task { @MainActor in
            do {
                let shouldOpenToday = try await services.makeDayAvailable(scheduledDate: dateString)
                if shouldOpenToday {
                    navigateToTodayAfterAvailable()
                }
                lightEditCaption = services.dayPackage(for: dateString)?.caption ?? ""
            } catch {
                // Surfaced via services.lastMakeDayAvailableError; stay on Plan.
            }
        }
    }

    private func navigateToTodayAfterAvailable() {
        appState.activeMode = .creator
        if showsModeSwitch {
            return
        }
        dismiss()
        appState.requestCreatorTab(.today)
    }

    private func unpublishSelectedDay() {
        let dateString = scheduledDateString
        Task { @MainActor in
            do {
                _ = try await services.unpublishDay(scheduledDate: dateString)
                lightEditCaption = services.dayPackage(for: dateString)?.caption ?? ""
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

    // MARK: - Calendar helpers

    private func shiftMonth(by value: Int) {
        guard let next = Calendar(identifier: .gregorian).date(byAdding: .month, value: value, to: visibleMonth) else {
            return
        }
        visibleMonth = next
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func daysInVisibleMonth() -> [Date?] {
        let calendar = Calendar(identifier: .gregorian)
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth),
              let firstWeekdayIndex = calendar.dateComponents([.weekday], from: monthInterval.start).weekday
        else {
            return []
        }

        let leadingBlanks = (firstWeekdayIndex - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: visibleMonth)?.count ?? 0
        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for offset in 0..<dayCount {
            if let date = calendar.date(byAdding: .day, value: offset, to: monthInterval.start) {
                days.append(date)
            }
        }
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
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

    private static func startOfToday() -> Date {
        Calendar(identifier: .gregorian).startOfDay(for: Date())
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

/// Calendar dot meanings for Plan: ready (green), draft (yellow), empty (none).
enum PlanCalendarDayState: Equatable, Sendable {
    case empty
    case draft
    case ready

    static func from(packageStatus: String?) -> PlanCalendarDayState {
        guard let status = packageStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !status.isEmpty
        else {
            return .empty
        }
        if DayPackageLifecycleStatus.requiresOverwriteConfirmation(status) {
            return .ready
        }
        if status == "draft" {
            return .draft
        }
        return .empty
    }
}
