import SwiftUI

/// Plan hub: selected date → five ideas or Other → one day-only generation → draft / Approve.
struct PlanHubView: View {
    private enum LightEditField: Hashable { case script, caption }
    @FocusState private var focusedLightEditField: LightEditField?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @Environment(\.pocketReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedDate = Date()
    @State private var visibleMonth = Date()
    @State private var generationStartTime: Date?
    @State private var showCalendarSheet = false
    @State private var isAddingPiece = false
    @State private var packageScrollRequest = 0
    @State private var showDayReview = DebugLaunchFlags.forceFixtureUI && DebugLaunchConfiguration.isEnabled("MCO_START_DAY_REVIEW")
    @State private var showMoveSheet = false
    @State private var moveError: String?
    @State private var showUnpublishConfirmation = false
    @State private var showOverwriteConfirmation = false
    @State private var pendingGenerationBrief: String?
    @State private var hasDispatchedGeneration = false
    @State private var isOtherIdeaOpen = false
    @State private var otherIdeaText = ""
    @State private var lightEditSessionID = UUID()
    @State private var lightEditCaption = ""
    @State private var lightEditScript = ""
    @State private var lightEditScenes: [ShotScene] = []
    @State private var didApplyInitialSelectedDate = false
    /// Reveals the idea launcher when a package already exists (overwrite / replace).
    @State private var showReplaceIdeaLauncher = false
    /// When true (DEBUG Admin Daily), show Admin “Creator mode” chrome. Creator Plan passes false.
    var showsModeSwitch: Bool = false
    /// Back chevron when Plan is pushed (e.g. from Today). Omit on the Plan tab root.
    var showsBackButton: Bool = true
    /// Optional `yyyy-MM-dd` preselection from Today Edit / ⋯ / empty CTA.
    var initialSelectedDate: String? = nil

    var body: some View {
        ScrollViewReader { proxy in
            planScreen
                .onChange(of: packageScrollRequest) { _, _ in
                    proxy.scrollTo("plan.package.top", anchor: .top)
                }
        }
    }

    private var planScreen: some View {
        PocketSheetScreen(
            topContentPadding: PocketSheetSpace.xxs,
            bottomContentPadding: 120,
            showsBottomBar: false
        ) {
            VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
                header
                selectedDateHeader
                sevenDaySelector
                pieceChoices
                if let otherLabel = otherDayGeneratingLabel {
                    Text("Still drafting \(otherLabel) in the background — you can keep planning other days.")
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        .accessibilityIdentifier("plan.generation.backgroundHint")
                }
                if isSelectedDayUnavailable {
                    PocketSheetFeedbackBanner(message: "This day is unavailable. Try again to load its saved state.", kind: .issue)
                    PocketSheetSecondaryAction(title: "Try again") {
                        services.refreshFromRepositories()
                    }
                    .disabled(services.isRefreshingRepository)
                }
                if shouldShowIdeaLauncher {
                    if services.voiceGateOpen {
                        Text("Set up Creator voice before generating more ideas.")
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("plan.voiceGate.hint")
                        PocketSheetSecondaryAction(title: "Set up Creator voice") {
                            appState.requestYouDestination(.creatorVoice, from: .plan(selectedDate: scheduledDateString))
                        }
                        .accessibilityIdentifier("plan.voiceGate.setup")
                    }
                    PlanDayIdeaLauncher(
                        ideas: dayIdeas,
                        isBusy: isGeneratingSelectedDay || hasDispatchedGeneration,
                        isInteractionDisabled: !canGenerate,
                        isOtherOpen: $isOtherIdeaOpen,
                        otherText: $otherIdeaText,
                        onSelectIdea: { requestGeneration(brief: $0.dayBrief) },
                        onSubmitOther: submitOtherIdea
                    )
                    if services.isLiveSupabaseRuntime && !services.aiConsentAllowsOutbound {
                        Text(AIConsentCopy.blockedMessage)
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("plan.aiConsent.hint")
                    }
                }
                if isGeneratingSelectedDay || (hasDispatchedGeneration && displayedCard == nil) {
                    generationProgressBlock
                }
                if let error = surfacedGenerationError {
                    if hasPendingGeneration {
                        PocketSheetPrimaryAction(title: "Try again", systemImage: "arrow.clockwise") {
                            Task { await services.replayOutboxImmediately() }
                        }
                        .accessibilityIdentifier("plan.piece.retry")
                    }
                    let cancelled = Self.isCancellationMessage(error)
                    AdminSignalBlock(
                        title: "",
                        value: error,
                        systemImage: cancelled ? "xmark.circle" : "exclamationmark.triangle",
                        tone: .warning
                    )
                }
                if let error = services.lastMakeDayAvailableError?.nilIfBlank {
                    AdminSignalBlock(
                        title: "",
                        value: error,
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                }
                if let error = services.lastUnpublishDayError?.nilIfBlank {
                    AdminSignalBlock(
                        title: "",
                        value: error,
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                }
                if let error = services.lastReadyDayPackageEditError?.nilIfBlank {
                    AdminSignalBlock(
                        title: "",
                        value: error,
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                }
                resultBlock
                    .id("plan.package.top")
                if let moveError {
                    PocketSheetFeedbackBanner(message: moveError, kind: .issue)
                        .accessibilityIdentifier("plan.piece.move.error")
                }
                if selectedPieces.contains(where: { !$0.requiresServerBinding || $0.revision != nil }), isSelectedDayEligible, !shouldShowIdeaLauncher, !isGeneratingSelectedDay {
                    PocketSheetSecondaryAction(title: "Add a piece") {
                        resetIdeaLauncherState()
                        isAddingPiece = true
                        refreshDayIdeasIfNeeded()
                    }
                    .accessibilityIdentifier("plan.piece.add")
                }
                if isAddingPiece || showReplaceIdeaLauncher {
                    PocketSheetSecondaryAction(title: "Cancel") {
                        resetIdeaLauncherState()
                        packageScrollRequest += 1
                    }
                        .accessibilityIdentifier("plan.piece.cancel")
                }
                PlanGenerationInputsSummary(setup: setupSummary, selectedDate: scheduledDateString)
                if !selectedPieces.isEmpty, !isAddingPiece {
                    VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                        Text(services.dayStore.reviewSummary(on: scheduledDateString))
                            .font(PocketSheetType.rowSubtitle)
                            .accessibilityIdentifier("plan.day.summary")
                        Text(services.weekPieceSummary)
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                            .accessibilityIdentifier("plan.week.summary")
                        PocketSheetSecondaryAction(title: "Review day") { showDayReview = true }
                            .accessibilityIdentifier("plan.day.review")
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isGeneratingSelectedDay)
        } bottomBar: {
            EmptyView()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if canMakeAvailable {
                approveDock
            } else if canLightEditReadyPackage {
                lightEditDock
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
        .sheet(isPresented: $showDayReview) {
            PlanDayReviewSheet(scheduledDate: DebugLaunchFlags.forceFixtureUI && DebugLaunchConfiguration.isEnabled("MCO_START_DAY_REVIEW")
                ? services.currentTodayDateString : scheduledDateString)
        }
        .sheet(isPresented: $showMoveSheet) {
            PlanPieceMoveSheet(sourceDate: scheduledDateString, today: planTodayDate) { date in
                moveSelectedPiece(to: date)
            }
        }
        .alert("Unpublish this day?", isPresented: $showUnpublishConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Unpublish", role: .destructive) {
                unpublishSelectedDay()
            }
        } message: {
            Text("Returns this ready package to draft. If there was a Decision, the live Decision clears and Archive history stays.")
        }
        .alert("Overwrite current draft?", isPresented: $showOverwriteConfirmation) {
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
            Text("This replaces this piece with a new draft. Any live Decision clears; Archive history stays. You will need to approve again.")
        }
        .onChange(of: selectedPieceID) { _, _ in
            resetLightEdit(displayedCard)
        }
        .onChange(of: displayedCard?.id) { _, _ in
            resetLightEdit(displayedCard)
        }
        .onChange(of: selectedDate) { _, newDate in
            visibleMonth = newDate
            resetIdeaLauncherState()
            resetLightEdit(displayedCard)
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
            resetLightEdit(displayedCard)
            if isGeneratingSelectedDay {
                hasDispatchedGeneration = true
            }
            applyFirstDayHandoffIfNeeded()
            refreshDayIdeasIfNeeded()
        }
        .onChange(of: appState.planSelectedDate) { _, _ in
            applyPendingPlanDateSelection()
        }
        .onChange(of: services.aiConsentEpoch) { _, _ in
            refreshDayIdeasIfNeeded()
        }
    }

    private func applyPendingPlanDateSelection() {
        let candidate: String?
        if DebugLaunchFlags.forceFixtureUI && DebugLaunchConfiguration.isEnabled("MCO_START_DAY_REVIEW") {
            candidate = services.currentTodayDateString
        } else if !didApplyInitialSelectedDate, let initial = initialSelectedDate?.nilIfBlank {
            didApplyInitialSelectedDate = true
            appState.preparePlan(selecting: initial)
            candidate = initial
        } else if let pending = appState.consumePlanSelectedDate() {
            candidate = pending
        } else if let persisted = appState.persistedPlanSelectedDate(),
                  !SupabaseDateFormatting.isDatePast(persisted, todayString: services.currentTodayDateString) {
            candidate = persisted
        } else {
            candidate = services.currentTodayDateString
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
        generationStartTime = nil
        isOtherIdeaOpen = false
        otherIdeaText = ""
        pendingGenerationBrief = nil
        showReplaceIdeaLauncher = false
        isAddingPiece = false
        moveError = nil
    }

    /// Empty eligible day: idea launcher. After idea select / while generating / with a package: hide it.
    private var shouldShowIdeaLauncher: Bool {
        guard isSelectedDayEligible, !isSelectedDayUnavailable else { return false }
        if isGeneratingSelectedDay || hasDispatchedGeneration || hasPendingGeneration {
            return false
        }
        if isAddingPiece { return true }
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

    private var isSelectedDayUnavailable: Bool {
        guard !isAddingPiece, let day = selectedPiece else { return false }
        return day.lifecycle == .unavailable && day.revision?.content.status != "archived"
    }

    private var isGeneratingSelectedDay: Bool {
        guard !isAddingPiece, surfacedGenerationError == nil else { return false }
        if case .generating = selectedPiece?.lifecycle { return true }
        return services.dayStore.outbox.contains { $0.isGeneration && $0.pieceID == selectedPieceID }
    }

    private var hasPendingGeneration: Bool {
        !isAddingPiece && services.dayStore.outbox.contains { $0.isGeneration && $0.pieceID == selectedPieceID }
    }

    private var isRunningSelectedGeneration: Bool {
        if hasDispatchedGeneration, generationStartTime != nil { return true }
        guard isGeneratingSelectedDay, let intentID = services.activeGenerationIntentID else { return false }
        return services.dayStore.outbox.contains { $0.id == intentID && $0.pieceID == selectedPieceID }
    }

    private var otherDayGeneratingLabel: String? {
        let others = services.generatingDayBriefDates.filter { $0 != scheduledDateString }.sorted()
        guard let first = others.first else { return nil }
        return shortLabel(for: first)
    }

    private var canMakeAvailable: Bool {
        canGenerate
            && !shouldShowIdeaLauncher
            && !isGeneratingSelectedDay
            && !services.isMakingDayAvailable
            && !services.isApprovingPieces
            && displayedCard != nil
            && DayPackageLifecycleStatus.isDraftPackage(displayedCard?.status)
    }

    private var canUnpublish: Bool {
        canGenerate
            && !shouldShowIdeaLauncher
            && !isGeneratingSelectedDay
            && !services.isUnpublishingDay
            && DayPackageLifecycleStatus.requiresOverwriteConfirmation(displayedCard?.status)
    }

    private var canLightEditReadyPackage: Bool {
        canGenerate
            && !shouldShowIdeaLauncher
            && !isGeneratingSelectedDay
            && DayPackageLifecycleStatus.requiresOverwriteConfirmation(displayedCard?.status)
    }

    private var scheduledDateString: String {
        Self.dateString(from: selectedDate)
    }

    private var surfacedGenerationError: String? {
        guard !isAddingPiece else { return nil }
        return selectedPieceID.flatMap { services.pieceGenerationErrors[$0] }
    }

    private var displayedCard: GeneratedDailyCardDraft? {
        guard !isAddingPiece, !isSelectedDayUnavailable else { return nil }
        guard let package = services.dayPackage(for: scheduledDateString, pieceID: selectedPieceID), package.status != "archived" else { return nil }
        return package
    }

    private var selectedPieces: [Piece] { services.dayStore.orderedPieces(on: scheduledDateString) }

    private var selectedPieceID: UUID? {
        if let saved = appState.planSelectedPiece(on: scheduledDateString, context: services.context),
           selectedPieces.contains(where: { $0.identity.pieceID == saved }) { return saved }
        return selectedPieces.first?.identity.pieceID
    }

    private var selectedPiece: Piece? { selectedPieceID.flatMap { services.dayStore.piece(for: $0) } }

    @ViewBuilder
    private var pieceChoices: some View {
        if selectedPieces.count > 1 {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                Text("Pieces for this day")
                    .font(PocketSheetType.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                ForEach(selectedPieces) { piece in
                    Button {
                        resetIdeaLauncherState()
                        appState.selectPlanPiece(piece.identity.pieceID, on: scheduledDateString, context: services.context)
                        resetLightEdit(displayedCard)
                    } label: {
                        HStack(alignment: .top, spacing: PocketSheetSpace.s) {
                            Text("\(piece.position + 1). \(piece.revision?.content.title ?? "New piece")")
                                .font(PocketSheetType.rowTitle)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: PocketSheetSpace.xs)
                            if !isAddingPiece, piece.identity.pieceID == selectedPieceID {
                                Image(systemName: "checkmark").font(PocketSheetType.bodyText)
                            }
                        }
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .padding(.vertical, PocketSheetSpace.s)
                        .padding(.horizontal, PocketSheetSpace.l)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(PocketSheetTheme.Color.fillMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(!isAddingPiece && piece.identity.pieceID == selectedPieceID ? [.isSelected] : [])
                    .accessibilityIdentifier("plan.piece.\(piece.position)")
                }
            }
        }
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
                Text("Plan the next seven days, then make a ready package for Today.")
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
                dateHeaderLayout {
                    if let formatted = PlanDayDateFormatting.formattedDate(for: scheduledDateString) {
                        Text(formatted.weekday)
                            .font(PocketSheetType.sectionLabel)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
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

    private var sevenDaySelector: some View {
        PlanSevenDaySelector(
            selectedDate: selectedDate,
            today: planTodayDate,
            packageStatusForDate: { services.dayPackage(for: $0)?.status },
            onSelectDate: { selectedDate = $0 }
        )
    }

    private var dateHeaderLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PocketSheetSpace.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: PocketSheetSpace.xs))
    }

    private var planTodayDate: Date {
        Self.parseLocalDate(services.currentTodayDateString) ?? Self.startOfToday()
    }

    private var generationProgressBlock: some View {
        PocketSheetCard {
            HStack(spacing: PocketSheetSpace.s) {
                if isRunningSelectedGeneration {
                    ProgressView()
                        .controlSize(.small)
                }
                VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                    Text(isRunningSelectedGeneration
                         ? "Drafting \(shortLabel(for: scheduledDateString))"
                         : "Waiting to draft \(shortLabel(for: scheduledDateString))")
                        .font(PocketSheetType.rowTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                    Text(isRunningSelectedGeneration ? "Preparing your idea…" : "Your request is saved.")
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                }
                Spacer()
                if isRunningSelectedGeneration, let startTime = generationStartTime {
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
                Text(card.title)
                    .font(PocketSheetType.screenTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("plan.package.title")
                GeneratedDayPlannedContent(card: card) { assets in
                    services.applyStoryboardThumbnailAssets(assets, toDailyCardID: card.id)
                }

                if canLightEditReadyPackage {
                    lightEditBlock
                        .id(lightEditSessionID)
                        .disabled(services.isUpdatingReadyDayPackage)
                }
                unpublishActionBlock
                if let progress = selectedPiece?.revision?.filmingProgress, !progress.shotSceneIDs.isEmpty {
                    Text("\(progress.shotSceneIDs.count) of \(card.sceneList.count) shots filmed")
                        .font(PocketSheetType.rowSubtitle)
                        .accessibilityIdentifier("plan.piece.filming")
                }
                PocketSheetSecondaryAction(title: "Move to another date") {
                    showMoveSheet = true
                }
                .accessibilityIdentifier("plan.piece.move")

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
                if hasEditableScript {
                    Text("Script")
                        .font(PocketSheetType.sectionLabel)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                    Text(ShotScript.editorGuidance)
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    TextEditor(text: lightEditBinding($lightEditScript))
                        .focused($focusedLightEditField, equals: .script)
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 150)
                        .accessibilityIdentifier("plan.package.script.editor")
                    if lightEditScript.nilIfBlank == nil {
                        Text("Enter a script before saving.")
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Caption")
                    .font(PocketSheetType.sectionLabel)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                TextEditor(text: lightEditBinding($lightEditCaption))
                    .focused($focusedLightEditField, equals: .caption)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 72)
                    .accessibilityIdentifier("daily.ready.edit.caption")
                if lightEditCaption.nilIfBlank == nil {
                    Text("Enter a caption before saving.")
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var lightEditDock: some View {
        PocketSheetSecondaryAction(
            title: services.isUpdatingReadyDayPackage ? "Saving…" : (hasScriptEdit ? "Save edits" : "Save caption")
        ) {
            saveLightEdit()
        }
        .disabled(!canSaveLightEdit)
        .opacity(canSaveLightEdit ? 1 : 0.48)
        .accessibilityIdentifier("daily.ready.edit.save")
        .padding(.horizontal, PocketSheetSpace.l)
        .padding(.top, PocketSheetSpace.s)
        .padding(.bottom, PocketSheetSpace.xs)
        .background(PocketSheetTheme.Color.paper)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PocketSheetTheme.Color.hairline)
                .frame(height: 1)
        }
    }

    private var canSaveLightEdit: Bool {
        canLightEditReadyPackage
            && !services.isUpdatingReadyDayPackage
            && lightEditCaption.nilIfBlank != nil
            && (!hasEditableScript || lightEditScript.nilIfBlank != nil)
            && (lightEditCaption != (displayedCard?.caption ?? "")
                || hasScriptEdit)
    }

    private var hasScriptEdit: Bool {
        lightEditScript != (displayedCard.map { PackageCopyText.script(for: $0) } ?? "")
    }

    private var hasEditableScript: Bool {
        !lightEditScenes.isEmpty || displayedCard?.script.nilIfBlank != nil
    }

    private var approveDock: some View {
        VStack(alignment: .center, spacing: PocketSheetSpace.xs) {
            PocketSheetPrimaryAction(
                title: services.isMakingDayAvailable ? "Saving…" : readyActionTitle,
                systemImage: "checkmark.circle"
            ) {
                makeAvailableOnToday()
            }
            .disabled(!canMakeAvailable)
            .opacity(canMakeAvailable ? 1 : 0.48)
            .accessibilityIdentifier("daily.availableOnToday")

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

    private var readyActionTitle: String {
        if scheduledDateString == services.currentTodayDateString {
            return "Make ready for Today"
        }
        if let formatted = PlanDayDateFormatting.formattedDate(for: scheduledDateString) {
            return "Save for \(formatted.weekday)"
        }
        return "Save for this day"
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
        guard services.canGenerateContent else {
            // The inline voice-gate hint explains why generation is paused.
            return
        }

        // Any existing package — draft or live — needs explicit confirmation before replacement.
        if displayedCard != nil {
            pendingGenerationBrief = trimmed
            showOverwriteConfirmation = true
            return
        }
        generate(brief: trimmed, confirmOverwrite: false)
    }

    private func generate(brief: String, confirmOverwrite: Bool) {
        guard !hasDispatchedGeneration || confirmOverwrite else { return }
        let dateString = scheduledDateString
        let pieceID = selectedPieceID
        let adding = isAddingPiece
        let startTime = Date()
        hasDispatchedGeneration = true
        generationStartTime = startTime
        showReplaceIdeaLauncher = false
        Task { @MainActor in
            defer {
                if generationStartTime == startTime {
                    generationStartTime = nil
                    hasDispatchedGeneration = false
                }
            }
            do {
                _ = try await services.generateDayCard(
                    scheduledDate: dateString,
                    dayBrief: brief,
                    confirmOverwrite: confirmOverwrite,
                    pieceID: pieceID,
                    addingPiece: adding,
                    onPieceSaved: { id in
                        appState.selectPlanPiece(id, on: dateString, context: services.context)
                        if scheduledDateString == dateString { isAddingPiece = false }
                    }
                )
                guard scheduledDateString == dateString else { return }
                isOtherIdeaOpen = false
                otherIdeaText = ""
                resetLightEdit(displayedCard)
            } catch {
                if generationStartTime == startTime, !isGeneratingSelectedDay {
                    hasDispatchedGeneration = false
                }
            }
        }
    }

    private func makeAvailableOnToday() {
        let dateString = scheduledDateString
        let pieceID = selectedPieceID
        Task { @MainActor in
            do {
                let shouldOpenToday = try await services.makeDayAvailable(scheduledDate: dateString, pieceID: pieceID)
                if shouldOpenToday {
                    navigateToTodayAfterAvailable()
                }
                guard scheduledDateString == dateString else { return }
                resetLightEdit(displayedCard)
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
        let pieceID = selectedPieceID
        Task { @MainActor in
            do {
                _ = try await services.unpublishDay(scheduledDate: dateString, pieceID: pieceID)
                guard scheduledDateString == dateString else { return }
                resetLightEdit(displayedCard)
            } catch {
                // Surfaced via services.lastUnpublishDayError.
            }
        }
    }

    private func saveLightEdit() {
        guard canSaveLightEdit else { return }
        focusedLightEditField = nil
        let dateString = scheduledDateString
        let pieceID = selectedPieceID
        let sessionID = lightEditSessionID
        let caption = lightEditCaption
        let scenes = ShotScript.editing(lightEditScript, scenes: lightEditScenes)
        let script = scenes.isEmpty ? lightEditScript : ShotScript.text(for: scenes)
        Task { @MainActor in
            do {
                _ = try await services.updateReadyDayPackage(
                    scheduledDate: dateString,
                    package: ReadyDayPackageUpdate(
                        caption: caption,
                        script: script.nilIfBlank == nil ? nil : script,
                        sceneList: scenes.isEmpty ? nil : scenes
                    ),
                    pieceID: pieceID
                )
                guard scheduledDateString == dateString, selectedPieceID == pieceID, lightEditSessionID == sessionID else { return }
                resetLightEdit(displayedCard)
            } catch {
                // Surfaced via services.lastReadyDayPackageEditError.
            }
        }
    }

    private func moveSelectedPiece(to date: String) {
        guard let pieceID = selectedPieceID else { return }
        moveError = nil
        showMoveSheet = false
        Task { @MainActor in
            do {
                let moved = try await services.movePiece(pieceID, to: date)
                appState.selectPlanPiece(moved.pieceID, on: moved.scheduledDate, context: services.context)
                if let movedDate = Self.parseLocalDate(moved.scheduledDate) { selectedDate = movedDate }
            } catch {
                let isQueued = services.dayStore.outbox.contains { $0.kind == .movePiece && $0.pieceID == pieceID }
                moveError = PieceMoveErrorDisplay.message(for: error, isQueued: isQueued)
            }
        }
    }

    private func lightEditBinding(_ draft: Binding<String>) -> Binding<String> {
        let sessionID = lightEditSessionID
        return Binding(
            get: { draft.wrappedValue },
            set: { value in
                guard lightEditSessionID == sessionID else { return }
                draft.wrappedValue = value
            }
        )
    }

    private func resetLightEdit(_ card: GeneratedDailyCardDraft?) {
        lightEditSessionID = UUID()
        focusedLightEditField = nil
        lightEditCaption = card?.caption ?? ""
        lightEditScenes = card?.sceneList ?? []
        lightEditScript = card.map { PackageCopyText.script(for: $0) } ?? ""
    }

    // MARK: - Date helpers

    private func shortLabel(for dateString: String) -> String {
        if dateString == services.currentTodayDateString {
            return "today"
        }
        guard let date = Self.parseLocalDate(dateString) else {
            return dateString
        }
        return SupabaseDateFormatting.calendarText(from: date, format: "EEE d MMM")
    }

    private static func startOfToday() -> Date {
        PlanDayDateFormatting.startOfToday
    }

    private static func dateString(from date: Date) -> String {
        SupabaseDateFormatting.dateString(from: date)
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

/// Compact seven-day view for the common Plan path. The calendar remains available
/// from the date header for dates outside this short planning window.
private struct PlanSevenDaySelector: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let selectedDate: Date
    let today: Date
    let packageStatusForDate: (String) -> String?
    let onSelectDate: (Date) -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                LazyVStack(spacing: PocketSheetSpace.xs) {
                    ForEach(sevenDayDates, id: \.self) { date in
                        accessibilityDayButton(for: date)
                    }
                }
            } else if dynamicTypeSize >= .xxLarge {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PocketSheetSpace.xs) {
                        ForEach(sevenDayDates, id: \.self) { date in
                            compactDayButton(for: date)
                                .frame(width: 64)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollClipDisabled()
            } else {
                GeometryReader { proxy in
                    let spacing = PocketSheetSpace.xs
                    let tileWidth = max(44, (proxy.size.width - spacing * 6) / 7)
                    HStack(spacing: PocketSheetSpace.xs) {
                        ForEach(sevenDayDates, id: \.self) { date in
                            compactDayButton(for: date)
                                .frame(width: tileWidth)
                        }
                    }
                }
                .frame(height: 72)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.sevenDaySelector")
    }

    private var sevenDayDates: [Date] {
        let calendar = PlanDayDateFormatting.calendar
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    private func compactDayButton(for date: Date) -> some View {
        let dateString = Self.dateString(from: date)
        let state = PlanCalendarDayState.from(packageStatus: packageStatusForDate(dateString))
        let isSelected = dateString == Self.dateString(from: selectedDate)
        let isToday = dateString == Self.dateString(from: today)
        let calendar = PlanDayDateFormatting.calendar
        let dayNumber = calendar.component(.day, from: date)
        let month = monthLabel(for: date)
        let weekday = weekdayLabel(for: date)

        return Button {
            onSelectDate(date)
        } label: {
            VStack(spacing: 2) {
                Text(isToday ? "Today" : weekday)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isSelected ? PocketSheetTheme.Color.ink : PocketSheetTheme.Color.inkMuted)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(dayNumber)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                Text(month)
                    .font(.caption2)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                statusIcon(state)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .padding(.horizontal, 2)
            .background(isSelected ? PocketSheetTheme.Color.fillMuted : PocketSheetTheme.Color.paperRaised)
            .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                    .stroke(isSelected ? PocketSheetTheme.Color.ink : PocketSheetTheme.Color.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: dateString, weekday: weekday, dayNumber: dayNumber, month: month, state: state))
        .accessibilityIdentifier("plan.sevenDaySelector.day.\(dateString)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func accessibilityDayButton(for date: Date) -> some View {
        let dateString = Self.dateString(from: date)
        let state = PlanCalendarDayState.from(packageStatus: packageStatusForDate(dateString))
        let isSelected = dateString == Self.dateString(from: selectedDate)
        let isToday = dateString == Self.dateString(from: today)
        let calendar = PlanDayDateFormatting.calendar
        let dayNumber = calendar.component(.day, from: date)
        let month = monthLabel(for: date)
        let weekday = weekdayLabel(for: date)

        return Button {
            onSelectDate(date)
        } label: {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                    Text(isToday ? "Today" : weekday)
                        .font(.body.weight(.semibold))
                    Text("\(dayNumber) \(month)")
                        .font(.body)
                }
                .foregroundStyle(PocketSheetTheme.Color.ink)
                statusView(state)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .padding(.horizontal, PocketSheetSpace.m)
            .padding(.vertical, PocketSheetSpace.s)
            .background(isSelected ? PocketSheetTheme.Color.fillMuted : PocketSheetTheme.Color.paperRaised)
            .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                    .stroke(isSelected ? PocketSheetTheme.Color.ink : PocketSheetTheme.Color.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: dateString, weekday: weekday, dayNumber: dayNumber, month: month, state: state))
        .accessibilityIdentifier("plan.sevenDaySelector.day.\(dateString)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func statusIcon(_ state: PlanCalendarDayState) -> some View {
        let label: String
        let symbol: String
        switch state {
        case .ready:
            label = "Ready"
            symbol = "checkmark.circle.fill"
        case .draft:
            label = "Draft"
            symbol = "doc.text"
        case .empty:
            label = "Open"
            symbol = "circle"
        }

        return Image(systemName: symbol)
            .font(.caption.weight(.semibold))
            .frame(minWidth: 20, minHeight: 20)
            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            .accessibilityLabel(label)
    }

    private func statusView(_ state: PlanCalendarDayState) -> some View {
        let label: String
        let symbol: String
        switch state {
        case .ready:
            label = "Ready"
            symbol = "checkmark.circle.fill"
        case .draft:
            label = "Draft"
            symbol = "doc.text"
        case .empty:
            label = "Open"
            symbol = "circle"
        }

        return HStack(spacing: PocketSheetSpace.xs) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
            Text(label)
                .font(.body.weight(.semibold))
        }
        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    private func accessibilityLabel(
        for dateString: String,
        weekday: String,
        dayNumber: Int,
        month: String,
        state: PlanCalendarDayState
    ) -> String {
        let status: String
        switch state {
        case .ready: status = "ready"
        case .draft: status = "draft"
        case .empty: status = "open"
        }
        return "\(weekday) \(dayNumber) \(month), \(status), \(dateString)"
    }

    private func weekdayLabel(for date: Date) -> String {
        SupabaseDateFormatting.calendarText(from: date, format: "EEE", localeIdentifier: "en_GB")
    }

    private func monthLabel(for date: Date) -> String {
        SupabaseDateFormatting.calendarText(from: date, format: "MMM", localeIdentifier: "en_GB")
    }

    private static func dateString(from date: Date) -> String {
        SupabaseDateFormatting.dateString(from: date)
    }
}

private struct PlanPieceMoveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var weekOffset = 0
    let sourceDate: String
    let today: Date
    let onMove: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSheetSpace.section) {
                    Text("Choose a date for this piece. Your edits and filmed shots stay with it.")
                        .font(PocketSheetType.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: PocketSheetSpace.s) {
                        ForEach(dates, id: \.self) { date in
                            let value = SupabaseDateFormatting.dateString(from: date)
                            PocketSheetSecondaryAction(title: SupabaseDateFormatting.displayDate(for: value)) {
                                onMove(value)
                            }
                            .disabled(value == sourceDate)
                            .accessibilityIdentifier("plan.move.date.\(value)")
                        }
                    }
                    PocketSheetSecondaryAction(title: "Next week") { weekOffset += 1 }
                        .accessibilityIdentifier("plan.move.next")
                    if weekOffset > 0 {
                        PocketSheetSecondaryAction(title: "Previous week") { weekOffset -= 1 }
                            .accessibilityIdentifier("plan.move.previous")
                    }
                }
                .padding(PocketSheetSpace.l)
            }
            .background(PocketSheetTheme.Color.paper)
            .navigationTitle("Move to another date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(PocketSheetType.actionSecondary)
                        .accessibilityIdentifier("plan.move.cancel")
                }
            }
        }
        .tint(PocketSheetTheme.Color.ink)
    }

    private var dates: [Date] {
        let start = PlanDayDateFormatting.calendar.startOfDay(for: today)
        return (0..<7).compactMap { PlanDayDateFormatting.calendar.date(byAdding: .day, value: max(0, weekOffset) * 7 + $0, to: start) }
    }
}

struct PlanDayReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    let scheduledDate: String
    @State private var selectedRevisions: [UUID: UUID] = [:]
    @State private var reviewingPieceID: UUID?
    @State private var reviewingRevisionID: UUID?
    @State private var didApplyFixtureSelection = false

    private var pieces: [Piece] { services.dayStore.reviewPieces(on: scheduledDate) }

    private var eligibleSelection: [UUID: UUID] {
        selectedRevisions.filter { pieceID, revisionID in
            guard let piece = pieces.first(where: { $0.identity.pieceID == pieceID }) else { return false }
            return piece.canApproveReviewedDraft && piece.revision?.id == revisionID
        }
    }

    var body: some View {
        Group {
            if let pieceID = reviewingPieceID, let revisionID = reviewingRevisionID {
                PlanPieceReviewContent(pieceID: pieceID, revisionID: revisionID) {
                    reviewingPieceID = nil
                    reviewingRevisionID = nil
                } onReviewed: {
                    selectedRevisions[pieceID] = revisionID
                    reviewingPieceID = nil
                    reviewingRevisionID = nil
                }
                .id(revisionID)
            } else {
                reviewList
                    .id(scheduledDate)
            }
        }
        .pocketSheetChromePalette()
        .interactiveDismissDisabled(services.isApprovingPieces)
        .onAppear {
            guard !didApplyFixtureSelection, DebugLaunchFlags.forceFixtureUI,
                  DebugLaunchConfiguration.isEnabled("MCO_REVIEW_SELECT_ALL") else { return }
            didApplyFixtureSelection = true
            selectedRevisions = Dictionary(uniqueKeysWithValues: pieces.compactMap { piece in
                guard piece.canApproveReviewedDraft, let revisionID = piece.revision?.id else { return nil }
                return (piece.identity.pieceID, revisionID)
            })
        }
    }

    private var reviewList: some View {
        PocketSheetScreen(bottomContentPadding: PocketSheetSpace.section) {
            VStack(alignment: .leading, spacing: PocketSheetSpace.section) {
                PocketSheetSecondaryAction(title: "Close") { dismiss() }
                    .accessibilityIdentifier("review.day.close")
                Text("Review day")
                    .font(PocketSheetType.screenTitle)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("review.day.title")
                Text(PlanDayDateFormatting.formattedDate(for: scheduledDate)?.label ?? scheduledDate)
                    .font(PocketSheetType.bodyText)
                    .accessibilityIdentifier("review.day.date")
                Text(services.dayStore.reviewSummary(on: scheduledDate))
                    .font(PocketSheetType.rowSubtitle)
                    .accessibilityIdentifier("review.day.summary")
                ForEach(pieces) { piece in
                    pieceRow(piece)
                }
            }
        } bottomBar: {
            PocketSheetPrimaryAction(
                title: services.isApprovingPieces ? "Saving…" : "Approve \(eligibleSelection.count) \(eligibleSelection.count == 1 ? "piece" : "pieces")",
                systemImage: "checkmark.circle"
            ) {
                let selection = eligibleSelection
                Task { await services.approveReviewedPieces(selection) }
            }
            .disabled(eligibleSelection.isEmpty || services.isApprovingPieces || services.isMakingDayAvailable || !services.canGenerateContent)
            .accessibilityIdentifier("review.day.approve")
        }
    }

    private func pieceRow(_ piece: Piece) -> some View {
        let pieceID = piece.identity.pieceID
        let rowID = "review.piece.\(scheduledDate).\(piece.position)"
        return PocketSheetCard {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                Text(services.dayStore.projection(pieceID: pieceID)?.package.title ?? "Piece \(piece.position + 1)")
                    .font(PocketSheetType.rowTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(rowID).title")
                Text(piece.reviewStateLabel)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .accessibilityIdentifier("\(rowID).state")
                if piece.canReviewDraft, let revisionID = piece.revision?.id {
                    if piece.canApproveReviewedDraft {
                        Toggle("Select for approval", isOn: Binding(
                            get: { eligibleSelection[pieceID] == revisionID },
                            set: { selectedRevisions[pieceID] = $0 ? revisionID : nil }
                        ))
                        .font(PocketSheetType.bodyText)
                        .tint(PocketSheetTheme.Color.ink)
                        .disabled(services.isApprovingPieces)
                        .accessibilityIdentifier("\(rowID).select")
                    }
                    PocketSheetSecondaryAction(title: piece.canApproveReviewedDraft ? "Review again" : "Review") {
                        reviewingRevisionID = revisionID
                        reviewingPieceID = pieceID
                    }
                    .disabled(services.isApprovingPieces)
                    .accessibilityIdentifier("\(rowID).open")
                }
                if let error = services.pieceApprovalError(for: pieceID) {
                    Text(error)
                        .font(PocketSheetType.rowSubtitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("\(rowID).error")
                    if piece.canApproveReviewedDraft, let revisionID = piece.revision?.id {
                        PocketSheetSecondaryAction(title: "Try again") {
                            Task { await services.approveReviewedPieces([pieceID: revisionID]) }
                        }
                        .disabled(services.isApprovingPieces || services.isMakingDayAvailable)
                        .accessibilityIdentifier("\(rowID).retry")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(rowID)
    }
}

private struct PlanPieceReviewContent: View {
    private enum Section: String, CaseIterable { case script = "Script", shots = "Shots", caption = "Caption" }
    @Environment(AppServices.self) private var services
    let pieceID: UUID
    let revisionID: UUID
    let onBack: () -> Void
    let onReviewed: () -> Void
    @State private var section: Section = .script
    @State private var saveError: String?
    @State private var isSaving = false

    private var card: GeneratedDailyCardDraft? {
        guard services.dayStore.piece(for: pieceID)?.revision?.id == revisionID else { return nil }
        return services.dayStore.projection(pieceID: pieceID, revisionID: revisionID)?.package
    }

    var body: some View {
        PocketSheetScreen(bottomContentPadding: PocketSheetSpace.section) {
            VStack(alignment: .leading, spacing: PocketSheetSpace.section) {
                PocketSheetSecondaryAction(title: "Back to review day", action: onBack)
                    .accessibilityIdentifier("review.content.back")
                if let card {
                    Text(card.title)
                        .font(PocketSheetType.screenTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("review.content.title")
                    ForEach(Section.allCases, id: \.self) { choice in
                        PocketSheetSecondaryAction(title: choice.rawValue) { section = choice }
                            .accessibilityAddTraits(section == choice ? [.isSelected] : [])
                            .accessibilityIdentifier("review.content.tab.\(choice.rawValue.lowercased())")
                    }
                    content(card)
                } else {
                    Text("This piece changed. Return to review day and open it again.")
                        .font(PocketSheetType.bodyText)
                }
                if let saveError {
                    Text(saveError)
                        .font(PocketSheetType.rowSubtitle)
                        .accessibilityIdentifier("review.content.error")
                }
            }
        } bottomBar: {
            PocketSheetPrimaryAction(title: isSaving ? "Saving…" : "Reviewed", systemImage: "checkmark") {
                isSaving = true
                Task { @MainActor in
                    defer { isSaving = false }
                    do {
                        try await services.markPieceReviewed(pieceID: pieceID, revisionID: revisionID)
                        onReviewed()
                    } catch { saveError = error.localizedDescription }
                }
            }
            .disabled(card == nil || isSaving || services.dayStore.piece(for: pieceID)?.canReviewDraft != true)
            .accessibilityIdentifier("review.content.done")
        }
    }

    @ViewBuilder
    private func content(_ card: GeneratedDailyCardDraft) -> some View {
        switch section {
        case .script:
            Text(PackageCopyText.script(for: card))
                .font(PocketSheetType.bodyText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("review.content.script")
        case .caption:
            Text(card.caption)
                .font(PocketSheetType.bodyText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("review.content.caption")
        case .shots:
            ForEach(card.sceneList) { scene in
                VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                    Text("Shot \(scene.number): \(scene.title)")
                        .font(PocketSheetType.rowTitle)
                    Text(scene.duration)
                        .font(PocketSheetType.rowSubtitle)
                    if let dialogue = scene.dialogue?.nilIfBlank {
                        Text(dialogue).font(PocketSheetType.bodyText)
                    }
                }
            }
        }
    }
}
