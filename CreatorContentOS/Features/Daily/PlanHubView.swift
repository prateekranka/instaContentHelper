import SwiftUI

/// Plan hub: selected date → five ideas or Other → one day-only generation → draft / Approve.
struct PlanHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @State private var selectedDate = Date()
    @State private var visibleMonth = Date()
    @State private var generationStartTime: Date?
    @State private var showCalendarSheet = false
    @State private var showUnpublishConfirmation = false
    @State private var showOverwriteConfirmation = false
    @State private var pendingGenerationBrief: String?
    @State private var hasDispatchedGeneration = false
    @State private var isOtherIdeaOpen = false
    @State private var otherIdeaText = ""
    @State private var lightEditCaption = ""
    /// Reveals the idea launcher when a package already exists (overwrite / replace).
    @State private var showReplaceIdeaLauncher = false
    /// When true (DEBUG Admin Daily), show Admin “Creator mode” chrome. Creator Plan passes false.
    var showsModeSwitch: Bool = false
    /// Back chevron when Plan is pushed (e.g. from Today). Omit on the Plan tab root.
    var showsBackButton: Bool = true
    /// Optional `yyyy-MM-dd` preselection from Today Edit / ⋯ / empty CTA.
    var initialSelectedDate: String? = nil

    var body: some View {
        PocketSheetScreen(
            topContentPadding: PocketSheetSpace.xxs,
            bottomContentPadding: 120,
            showsBottomBar: false
        ) {
            VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
                header
                selectedDateHeader
                if let otherLabel = otherDayGeneratingLabel {
                    Text("Still drafting \(otherLabel) in the background — you can keep planning other days.")
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        .accessibilityIdentifier("plan.generation.backgroundHint")
                }
                if shouldShowIdeaLauncher {
                    PlanDayIdeaLauncher(
                        ideas: dayIdeas,
                        isBusy: isGeneratingSelectedDay || hasDispatchedGeneration,
                        isInteractionDisabled: !canGenerate,
                        isOtherOpen: $isOtherIdeaOpen,
                        otherText: $otherIdeaText,
                        onSelectIdea: { requestGeneration(brief: $0.dayBrief) },
                        onSubmitOther: submitOtherIdea
                    )
                }
                if isGeneratingSelectedDay || (hasDispatchedGeneration && displayedCard == nil) {
                    generationProgressBlock
                }
                if let error = surfacedGenerationError {
                    let cancelled = Self.isCancellationMessage(error)
                    AdminSignalBlock(
                        title: cancelled ? "Generation stopped" : "Generation error",
                        value: error,
                        systemImage: cancelled ? "xmark.circle" : "exclamationmark.triangle",
                        tone: .warning
                    )
                }
                if let error = services.lastMakeDayAvailableError?.nilIfBlank {
                    AdminSignalBlock(
                        title: "Approve",
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
                PlanGenerationInputsSummary(setup: setupSummary, selectedDate: scheduledDateString)
            }
            .animation(.easeInOut(duration: 0.28), value: isGeneratingSelectedDay)
        } bottomBar: {
            EmptyView()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if canMakeAvailable {
                approveDock
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showCalendarSheet) {
            PlanCalendarSheet(
                selectedDate: $selectedDate,
                visibleMonth: $visibleMonth,
                packageStatusForDate: { services.dayPackage(for: $0)?.status },
                onSelectDate: { date in
                    resetIdeaLauncherState()
                    visibleMonth = date
                    refreshDayIdeasIfNeeded(scheduledDate: Self.dateString(from: date))
                }
            )
        }
        .alert("Unpublish this day?", isPresented: $showUnpublishConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Unpublish", role: .destructive) {
                unpublishSelectedDay()
            }
        } message: {
            Text("Returns this ready package to draft. If there was a Decision, the live Decision clears and Archive history stays.")
        }
        .alert("Overwrite ready package?", isPresented: $showOverwriteConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingGenerationBrief = nil
            }
            Button("Overwrite", role: .destructive) {
                if let brief = pendingGenerationBrief {
                    generate(brief: brief, confirmOverwrite: true)
                }
                pendingGenerationBrief = nil
            }
        } message: {
            Text("This replaces the ready package with a new draft. Any live Decision clears; Archive history stays. You will need to approve again.")
        }
        .onChange(of: displayedCard?.id) { _, _ in
            lightEditCaption = displayedCard?.caption ?? ""
        }
        .onChange(of: selectedDate) { _, newDate in
            visibleMonth = newDate
            resetIdeaLauncherState()
            lightEditCaption = displayedCard?.caption ?? ""
            syncPersistedPlanDate()
            refreshDayIdeasIfNeeded()
        }
        .onChange(of: isGeneratingSelectedDay) { wasGenerating, isGenerating in
            if isGenerating && !wasGenerating {
                hasDispatchedGeneration = true
            }
            if wasGenerating && !isGenerating {
                hasDispatchedGeneration = false
            }
        }
        .onAppear {
            applyPendingPlanDateSelection()
            visibleMonth = selectedDate
            lightEditCaption = displayedCard?.caption ?? ""
            if isGeneratingSelectedDay {
                hasDispatchedGeneration = true
            }
            applyFirstDayHandoffIfNeeded()
            refreshDayIdeasIfNeeded()
        }
        .onChange(of: appState.planSelectedDate) { _, _ in
            applyPendingPlanDateSelection()
        }
    }

    private func applyPendingPlanDateSelection() {
        let candidate: String?
        if let initial = initialSelectedDate?.nilIfBlank {
            appState.preparePlan(selecting: initial)
            candidate = initial
        } else if let pending = appState.consumePlanSelectedDate() {
            candidate = pending
        } else if let persisted = appState.persistedPlanSelectedDate() {
            candidate = persisted
        } else {
            candidate = nil
        }
        guard let candidate, let date = Self.parseLocalDate(candidate) else { return }
        selectedDate = date
        visibleMonth = date
    }

    private func syncPersistedPlanDate() {
        appState.preparePlan(selecting: scheduledDateString)
    }

    private func applyFirstDayHandoffIfNeeded() {
        guard let handoff = appState.consumeFirstDayHandoff(),
              handoff.scheduledDate == scheduledDateString
        else {
            return
        }
        guard let brief = handoff.dayBrief?.nilIfBlank else {
            // Onboarding hands off to the five idea options; no auto-generation.
            resetIdeaLauncherState()
            return
        }
        requestGeneration(brief: brief)
    }

    private func resetIdeaLauncherState() {
        hasDispatchedGeneration = false
        isOtherIdeaOpen = false
        otherIdeaText = ""
        pendingGenerationBrief = nil
        showReplaceIdeaLauncher = false
    }

    /// Empty eligible day: idea launcher. After idea select / while generating / with a package: hide it.
    private var shouldShowIdeaLauncher: Bool {
        guard isSelectedDayEligible else { return false }
        if isGeneratingSelectedDay || hasDispatchedGeneration {
            return false
        }
        if displayedCard != nil {
            return showReplaceIdeaLauncher
        }
        return true
    }

    // MARK: - State helpers

    private var setupSummary: PlanDaySetupSummary {
        PlanDaySetupSummary.from(
            profile: services.creatorProfileSummary,
            intelligenceHome: services.intelligenceHome
        )
    }

    private var dayIdeas: [PlanDayIdeaCandidate] {
        services.planDayIdeas(for: scheduledDateString, setup: setupSummary)
    }

    private func refreshDayIdeasIfNeeded(scheduledDate: String? = nil) {
        let dateString = scheduledDate ?? scheduledDateString
        if dateString == scheduledDateString {
            guard shouldShowIdeaLauncher else { return }
        } else {
            guard let date = Self.parseLocalDate(dateString), date >= Self.startOfToday() else { return }
            guard services.dayPackage(for: dateString) == nil else { return }
        }
        let setup = setupSummary
        Task { @MainActor in
            await services.refreshPlanDayIdeas(scheduledDate: dateString, setup: setup)
        }
    }

    private var canGenerate: Bool {
        services.canGenerateContent
    }

    private var isSelectedDayEligible: Bool {
        selectedDate >= Self.startOfToday()
    }

    private var isGeneratingSelectedDay: Bool {
        services.generatingDayBriefDates.contains(scheduledDateString)
    }

    private var otherDayGeneratingLabel: String? {
        let others = services.generatingDayBriefDates.filter { $0 != scheduledDateString }.sorted()
        guard let first = others.first else { return nil }
        return shortLabel(for: first)
    }

    private var canMakeAvailable: Bool {
        canGenerate
            && !isGeneratingSelectedDay
            && !services.isMakingDayAvailable
            && displayedCard != nil
            && DayPackageLifecycleStatus.isDraftPackage(displayedCard?.status)
    }

    private var canUnpublish: Bool {
        canGenerate
            && !isGeneratingSelectedDay
            && !services.isUnpublishingDay
            && DayPackageLifecycleStatus.requiresOverwriteConfirmation(displayedCard?.status)
    }

    private var canLightEditReadyPackage: Bool {
        canGenerate
            && !isGeneratingSelectedDay
            && !services.isUpdatingReadyDayPackage
            && DayPackageLifecycleStatus.requiresOverwriteConfirmation(displayedCard?.status)
    }

    private var scheduledDateString: String {
        Self.dateString(from: selectedDate)
    }

    private var surfacedGenerationError: String? {
        services.dayBriefGenerationErrors[scheduledDateString]
    }

    private var displayedCard: GeneratedDailyCardDraft? {
        services.dayPackage(for: scheduledDateString)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top, spacing: PocketSheetSpace.s) {
            if showsBackButton {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .background(PocketSheetTheme.Color.paperRaised.opacity(0.72), in: Circle())
                        .overlay {
                            Circle().stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("plan.back")
            }

            VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                Text("Plan")
                    .font(PocketSheetType.screenTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .accessibilityIdentifier("plan.title")
                Text("Pick a day, choose an idea, then approve the draft for Today.")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: PocketSheetSpace.s)

            if showsModeSwitch {
                FloatingIconButton(systemImage: "ellipsis", label: "Back to Creator Mode") {
                    appState.activeMode = .creator
                }
            }
        }
    }

    private var selectedDateHeader: some View {
        Button {
            visibleMonth = selectedDate
            showCalendarSheet = true
        } label: {
            HStack(alignment: .center, spacing: PocketSheetSpace.s) {
                HStack(alignment: .firstTextBaseline, spacing: PocketSheetSpace.xs) {
                    if let formatted = PlanDayDateFormatting.formattedDate(for: scheduledDateString) {
                        Text(formatted.weekday)
                            .font(PocketSheetType.sectionLabel)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                            .textCase(.uppercase)
                        Text(formatted.label)
                            .font(PocketSheetType.rowTitle)
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                    } else {
                        Text(scheduledDateString)
                            .font(PocketSheetType.rowTitle)
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                    }
                }
                Spacer(minLength: PocketSheetSpace.s)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }
            .padding(PocketSheetSpace.m)
            .background(PocketSheetTheme.Color.paperRaised.opacity(0.86))
            .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                    .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change selected day")
        .accessibilityIdentifier("plan.date.header")
    }

    private var generationProgressBlock: some View {
        PocketSheetCard {
            HStack(spacing: PocketSheetSpace.s) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                    Text("Drafting \(shortLabel(for: scheduledDateString))")
                        .font(PocketSheetType.rowTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                    Text("Deep reasoning takes a couple of minutes. Validation may retry once or twice.")
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                }
                Spacer()
                if let startTime = generationStartTime {
                    TimelineView(.periodic(from: startTime, by: 1)) { context in
                        Text(Self.elapsedText(context.date.timeIntervalSince(startTime)))
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                            .monospacedDigit()
                    }
                }
            }
        }
        .accessibilityIdentifier("plan.generation.progress")
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var resultBlock: some View {
        if let card = displayedCard, !isGeneratingSelectedDay {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                GeneratedDayPlannedContent(card: card) { assets in
                    services.applyStoryboardThumbnailAssets(assets, toDailyCardID: card.id)
                }

                if canLightEditReadyPackage {
                    lightEditBlock
                }
                unpublishActionBlock

                if isSelectedDayEligible, !showReplaceIdeaLauncher {
                    Button {
                        showReplaceIdeaLauncher = true
                    } label: {
                        Text("Choose another idea")
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("plan.package.replaceIdea")
                }
            }
            .transition(.opacity)
        }
    }

    private var lightEditBlock: some View {
        PocketSheetCard {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                Text("Light edit")
                    .font(PocketSheetType.sectionLabel)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                Text("Edits keep this day ready — no Unpublish required.")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                TextEditor(text: $lightEditCaption)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 72)
                    .accessibilityIdentifier("daily.ready.edit.caption")
                PocketSheetSecondaryAction(
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

    private var approveDock: some View {
        VStack(alignment: .center, spacing: PocketSheetSpace.xs) {
            PocketSheetPrimaryAction(
                title: services.isMakingDayAvailable ? "Approving…" : "Approve",
                systemImage: "checkmark.circle"
            ) {
                makeAvailableOnToday()
            }
            .disabled(!canMakeAvailable)
            .opacity(canMakeAvailable ? 1 : 0.48)
            .accessibilityIdentifier("daily.availableOnToday")

            Text("Clicking this will add the card to the Today page.")
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("daily.approve.hint")
        }
        .padding(.horizontal, PocketSheetSpace.l)
        .padding(.top, PocketSheetSpace.s)
        .padding(.bottom, PocketSheetSpace.xs)
        .frame(maxWidth: .infinity)
        .background(PocketSheetTheme.Color.paper)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PocketSheetTheme.Color.hairline)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var unpublishActionBlock: some View {
        if canUnpublish {
            PocketSheetSecondaryAction(
                title: services.isUnpublishingDay ? "Unpublishing…" : "Unpublish"
            ) {
                showUnpublishConfirmation = true
            }
            .disabled(services.isUnpublishingDay || isGeneratingSelectedDay)
            .opacity(services.isUnpublishingDay || isGeneratingSelectedDay ? 0.48 : 1)
            .accessibilityIdentifier("daily.unpublish")
        }
    }

    // MARK: - Actions

    private func submitOtherIdea() {
        let brief = otherIdeaText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brief.isEmpty else { return }
        requestGeneration(brief: brief)
    }

    private func requestGeneration(brief: String) {
        guard !hasDispatchedGeneration, !isGeneratingSelectedDay else { return }
        let trimmed = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if DayPackageLifecycleStatus.requiresOverwriteConfirmation(displayedCard?.status) {
            pendingGenerationBrief = trimmed
            showOverwriteConfirmation = true
            return
        }
        generate(brief: trimmed, confirmOverwrite: false)
    }

    private func generate(brief: String, confirmOverwrite: Bool) {
        guard !hasDispatchedGeneration || confirmOverwrite else { return }
        let dateString = scheduledDateString
        hasDispatchedGeneration = true
        generationStartTime = Date()
        showReplaceIdeaLauncher = false
        Task { @MainActor in
            defer { generationStartTime = nil }
            do {
                _ = try await services.generateDayCard(
                    scheduledDate: dateString,
                    dayBrief: brief,
                    confirmOverwrite: confirmOverwrite
                )
                isOtherIdeaOpen = false
                otherIdeaText = ""
                lightEditCaption = services.dayPackage(for: dateString)?.caption ?? ""
            } catch {
                if !isGeneratingSelectedDay {
                    hasDispatchedGeneration = false
                }
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

    // MARK: - Date helpers

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
        PlanDayDateFormatting.parseLocalDate(dateString)
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
        if DayPackageLifecycleStatus.isDraftPackage(status) {
            return .draft
        }
        return .empty
    }
}

extension PlanHubView {
    fileprivate static func isCancellationMessage(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("cancel")
            || lowered.contains("stopped before it finished")
    }
}
