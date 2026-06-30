import SwiftUI

struct WeeklyControlView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @State private var isReviewingInputs = false
    @State private var isReviewingGeneratedDraft = false
    @State private var dayDetailSelection: WeeklyDayDetailSelection?
    @State private var selectedDayFilter: WeeklyDayState?
    @State private var isEditingWeeklyBrief = false
    @State private var isCreatorProfileExpanded = false
    @State private var retryingDayDate: String?

    var body: some View {
        EditorialScreen(bottomContentPadding: 140, showsBottomBar: false) {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                header
                ActionFeedbackBanner(message: services.lastActionMessage, tone: .ready)
                generationStatusPanel
                VStack(spacing: 0) {
                    WeeklyBriefToggleHeader(
                        isSet: isWeeklyBriefSet,
                        isExpanded: isEditingWeeklyBrief
                    ) {
                        withAnimation(.snappy(duration: 0.22)) {
                            isEditingWeeklyBrief.toggle()
                        }
                    }

                    if isEditingWeeklyBrief {
                        WeeklyBriefComposer(
                            text: Binding(
                                get: { services.weeklyBriefDraftText },
                                set: { services.weeklyBriefDraftText = $0 }
                            ),
                            isSaving: services.isSavingWeeklyBrief,
                            isDirty: services.isWeeklyBriefDirty,
                            errorMessage: services.weeklyBriefEditError,
                            onSave: { text in
                                let didSave = await services.updateWeeklyBriefImmediately(text)
                                if didSave {
                                    await MainActor.run {
                                        withAnimation(.snappy(duration: 0.22)) {
                                            isEditingWeeklyBrief = false
                                        }
                                    }
                                }
                                return didSave
                            }
                        )
                        .padding(.bottom, MCOSpace.s)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Hairline()

                    WeeklyContextLinks(
                        profile: services.creatorProfileSummary,
                        isCreatorProfileExpanded: $isCreatorProfileExpanded
                    )
                }
                WeeklyRhythmList(
                    days: visibleWeeklyDays,
                    generatedCard: services.generatedDailyCard,
                    onSelect: { day in
                        dayDetailSelection = makeDayDetailSelection(for: day.id)
                    },
                    dayStatuses: services.weeklyGenerationProgress?.dayStatuses ?? [],
                    retryingDayDate: retryingDayDate,
                    onRetryDay: { [self] scheduledDate in
                        retryDayInline(scheduledDate)
                    }
                )
                publishWeekPageAction
            }
        } bottomBar: {
            EmptyView()
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $isReviewingInputs) {
            WeeklyInputsReviewSheet(
                plan: services.weeklyPlan,
                profile: services.creatorProfileSummary
            )
        }
        .sheet(isPresented: $isReviewingGeneratedDraft) {
            if let draft = services.latestGenerationSummary {
                GeneratedWeekReviewSheet(
                    draft: draft,
                    canRegenerateDay: canRegenerateDay,
                    onSave: services.applyGeneratedDraft,
                    onPublish: { draft in
                        services.applyGeneratedDraft(draft)
                        services.publishCurrentWeek()
                    },
                    onRegenerateDay: services.regeneratedDailyCard
                )
            }
        }
        .sheet(item: $dayDetailSelection) { selection in
            WeeklyDayDetailSheet(
                day: selection.day,
                generatedCard: selection.generatedCard,
                isLocked: services.weeklyPlan.isSoftLocked || selection.day.isSoftLocked,
                canRegenerateDay: canRegenerateDay,
                onSetState: { state in
                    await services.updateWeeklyDayStateImmediately(dayID: selection.id, state: state)
                },
                onRegenerateDay: services.regeneratedDailyCard
            )
        }
    }

    private var canRegenerateDay: Bool {
        (services.memberRole == "owner" || services.memberRole == "editor") &&
            !services.weeklyPlan.isSoftLocked
    }

    private var publishButtonTitle: String {
        if services.isPublishingWeek {
            "Publishing"
        } else if services.weeklyPlan.isSoftLocked {
            "Published"
        } else {
            "Publish week"
        }
    }

    private var generateButtonTitle: String {
        if services.isGeneratingWeek {
            if let progress = services.weeklyGenerationProgress,
               progress.phase == .draftingDays || progress.phase == .savingDraftWeek {
                if progress.draftedDayCount > 0 {
                    "Generating \(progress.draftedDayCount)/\(progress.totalDayCount)"
                } else {
                    "Generating"
                }
            } else {
                "Generating"
            }
        } else if services.latestGenerationSummary != nil {
            "Regenerate"
        } else {
            "Generate"
        }
    }

    private var visibleWeeklyDays: [WeeklyDay] {
        guard let selectedDayFilter else { return services.weeklyPlan.days }
        return services.weeklyPlan.days.filter { $0.state == selectedDayFilter }
    }

    private var isWeeklyBriefSet: Bool {
        !services.weeklyPlan.weeklyBriefText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var publishWeekPageAction: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            if let publishError = publishErrorMessage {
                ActionFeedbackBanner(message: publishError, tone: .danger)
            }
            PrimaryActionButton(
                title: publishButtonTitle,
                systemImage: services.weeklyPlan.isSoftLocked ? "lock.fill" : "paperplane"
            ) {
                services.publishCurrentWeek()
            }
            .disabled(!services.canPublishCurrentWeek)
            .accessibilityIdentifier("weekly.publish")
        }
    }

    private var publishErrorMessage: String? {
        guard !services.isPublishingWeek,
              let error = services.lastPublishError?.nilIfBlank,
              !services.weeklyPlan.isSoftLocked
        else {
            return nil
        }
        return "Publish failed — \(error)"
    }

    private func toggleDayFilter(_ state: WeeklyDayState) {
        selectedDayFilter = selectedDayFilter == state ? nil : state
    }

    private var header: some View {
        HStack(alignment: .top, spacing: MCOSpace.s) {
            Button {
                appState.activeMode = .creator
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .background(MCOTheme.Color.paperRaised.opacity(0.72), in: Circle())
                    .overlay {
                        Circle().stroke(MCOTheme.Color.hairline, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to Creator Mode")

            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                Text(services.weeklyPlan.title)
                    .font(MCOType.screenTitle)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                WeekStartDateSelector(
                    startDate: selectedWeekStartDate,
                    endDate: selectedWeekEndDate,
                    isDisabled: services.weeklyPlan.isSoftLocked,
                    onChange: services.updateWeeklyStartDate
                )
            }
            Spacer(minLength: MCOSpace.s)
            weeklyOptionsMenu
        }
    }

    private var weeklyOptionsMenu: some View {
        Menu {
            Button {
                appState.activeMode = .creator
            } label: {
                Label("Go back to Creator Mode", systemImage: "person.crop.circle")
            }

            Button {
                services.refreshWeeklyData()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 42, height: 42)
                .foregroundStyle(MCOTheme.Color.ink)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Weekly options")
    }

    private var selectedWeekStartDate: String {
        services.weeklyPlan.weekStartDate
            ?? services.weeklyPlan.days.compactMap(\.scheduledDate).first
            ?? SupabaseDateFormatting.todayDateString()
    }

    private var selectedWeekEndDate: String {
        SupabaseDateFormatting.weekEndDate(starting: selectedWeekStartDate)
    }

    private func makeDayDetailSelection(for dayID: UUID) -> WeeklyDayDetailSelection? {
        guard let day = services.weeklyPlan.days.first(where: { $0.id == dayID }) else {
            return nil
        }

        return WeeklyDayDetailSelection(
            day: day,
            generatedCard: services.generatedDailyCard(for: day)
        )
    }

    private func retryDayInline(_ scheduledDate: String) {
        guard retryingDayDate == nil else { return }
        retryingDayDate = scheduledDate
        Task {
            do {
                try await services.retryQueuedGenerationDay(scheduledDate: scheduledDate)
                await services.reconcileGeneratedDayCardFromCurrentWeeklyContent(scheduledDate: scheduledDate)
            } catch {
                _ = error
            }
            retryingDayDate = nil
        }
    }

    private var softLockStrip: some View {
        HStack(spacing: MCOSpace.s) {
            Image(systemName: "lock")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(MCOTheme.Color.brass)
            Text(services.weeklyPlan.isSoftLocked ? "Soft locked week" : "Draft week")
                .font(MCOType.bodySmall)
                .foregroundStyle(MCOTheme.Color.ink)
            Spacer()
            Text("Confirm to change")
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.inkMuted)
        }
        .padding(.horizontal, MCOSpace.m)
        .padding(.vertical, MCOSpace.s)
        .background(MCOTheme.Color.paperRaised.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous)
                .stroke(MCOTheme.Color.hairline, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var generationStatusPanel: some View {
        if let progress = services.weeklyGenerationProgress {
            WeeklyGenerationStatusPanel(
                progress: progress,
                draft: services.latestGenerationSummary,
                weekRange: services.weeklyPlan.weekRange,
                canRegenerateDay: canRegenerateDay,
                onReview: {
                    isReviewingGeneratedDraft = true
                },
                onRegenerate: {
                    services.generateCurrentWeek()
                },
                onRegenerateDay: services.regeneratedDailyCard,
                onRetryQueuedDay: services.retryQueuedGenerationDay,
                onCancel: { services.cancelGeneration() }
            )
        } else if let draft = services.latestGenerationSummary {
            WeeklyGenerationStatusPanel(
                progress: .readyForReview(from: draft),
                draft: draft,
                weekRange: services.weeklyPlan.weekRange,
                canRegenerateDay: canRegenerateDay,
                onReview: {
                    isReviewingGeneratedDraft = true
                },
                onRegenerate: {
                    services.generateCurrentWeek()
                },
                onRegenerateDay: services.regeneratedDailyCard,
                onRetryQueuedDay: services.retryQueuedGenerationDay,
                onCancel: { services.cancelGeneration() }
            )
        } else if let error = services.generationError {
            HStack(spacing: MCOSpace.s) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MCOTheme.Color.clay)
                Text(error)
                    .font(MCOType.bodySmall)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineLimit(2)
                Spacer()
                Button("Inputs") {
                    isReviewingInputs = true
                }
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.oxblood)
            }
            .padding(.horizontal, MCOSpace.m)
            .padding(.vertical, MCOSpace.s)
            .background(MCOTheme.Color.paperRaised.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous)
                    .stroke(MCOTheme.Color.hairline, lineWidth: 1)
            }
        } else if isWeeklyBriefSet {
            PrimaryActionButton(
                title: "Generate",
                systemImage: "paperplane"
            ) {
                services.generateCurrentWeek()
            }
            .disabled(services.isGeneratingWeek)
        }
    }
}

struct WeeklyGenerationStatusPanel: View {
    let progress: WeeklyGenerationProgress
    let draft: GeneratedWeekDraft?
    let weekRange: String
    let canRegenerateDay: Bool
    let onReview: () -> Void
    let onRegenerate: () -> Void
    let onRegenerateDay: RegenerateDayAction?
    let onRetryQueuedDay: RetryQueuedDayAction?
    let onCancel: (() -> Void)?
    @State private var regeneratingFailedDay: String?
    @State private var failedDayRegenerationErrors: [String: String] = [:]

    private var isReady: Bool {
        progress.phase == .readyForReview && draft != nil
    }

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                if isReady, let draft {
                    readyContent(draft)
                } else {
                    runningContent
                }
            }
        }
    }

    private var runningContent: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            HStack {
                Text("Generation Status")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                Spacer()
                if progress.phase == .failed {
                    StatusChip(text: "Failed", tone: .warning)
                } else {
                    StatusChip(text: "Running", tone: .info)
                }
            }

            VStack(spacing: MCOSpace.xs) {
                GenerationStatusRow(
                    title: "Weekly brief saved",
                    detail: nil,
                    state: weeklyBriefRowState
                )
                GenerationStatusRow(
                    title: "Strategy created",
                    detail: nil,
                    state: strategyRowState
                )
                GenerationStatusRow(
                    title: "Drafting days",
                    detail: "\(progress.draftedDayCount) of \(progress.totalDayCount)",
                    state: draftingDaysRowState
                )
                GenerationStatusRow(
                    title: "Saved drafts",
                    detail: "\(progress.effectiveSavedDayCount) of \(progress.totalDayCount)",
                    state: savedDraftsRowState
                )
                if !progress.dayStatuses.isEmpty {
                    WeeklyGenerationDayProgressList(
                        dayStatuses: progress.dayStatuses,
                        draft: draft,
                        canRegenerateDay: canRegenerateDay && onRegenerateDay != nil,
                        regeneratingFailedDay: regeneratingFailedDay,
                        errorMessages: failedDayRegenerationErrors,
                        onReviewGeneratedDay: onReview,
                        onRetryDay: retryFailedDay
                    )
                    .padding(.vertical, MCOSpace.xs)
                }
                GenerationStatusRow(
                    title: "Saving draft week",
                    detail: nil,
                    state: rowState(for: .savingDraftWeek)
                )
                GenerationStatusRow(
                    title: "Ready for review",
                    detail: nil,
                    state: rowState(for: .readyForReview)
                )

            }

            if let error = progress.error {
                VStack(alignment: .leading, spacing: MCOSpace.s) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.oxblood)
                        .fixedSize(horizontal: false, vertical: true)

                    if progress.phase == .failed {
                        Button {
                            onRegenerate()
                        } label: {
                            HStack(spacing: MCOSpace.xs) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(draft == nil ? "Generate" : "Regenerate")
                                    .font(MCOType.bodySmall.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(MCOTheme.Color.paperRaised)
                        .background(MCOTheme.Color.oxblood, in: Capsule())
                        .accessibilityLabel(draft == nil ? "Generate draft week again" : "Regenerate draft week")
                    }
                }
            } else if let currentDay = progress.currentDay {
                Text("Working on \(SupabaseDateFormatting.displayDate(for: currentDay)).")
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }

            if progress.phase == .draftingDays || progress.phase == .loadingContext || progress.phase == .savingDraftWeek {
                if let onCancel {
                    HStack {
                        Spacer()
                        Button(action: onCancel) {
                            HStack(spacing: 6) {
                                Image(systemName: "stop.circle.fill")
                                    .font(.system(size: 16))
                                Text("Stop Generation")
                                    .font(.system(size: 14, weight: .medium, design: .serif))
                            }
                            .foregroundStyle(MCOTheme.Color.oxblood)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(MCOTheme.Color.oxblood.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, MCOSpace.xs)
                }
            }
        }
    }

    private func readyContent(_ draft: GeneratedWeekDraft) -> some View {
        HStack(alignment: .center, spacing: MCOSpace.s) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(MCOTheme.Color.success)
            Text("Draft week generated")
                .font(MCOType.bodySmall.weight(.semibold))
                .foregroundStyle(MCOTheme.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
            Spacer(minLength: MCOSpace.s)
            VStack(spacing: MCOSpace.xs) {
                Button {
                    onReview()
                } label: {
                    Text("Review")
                        .font(MCOType.caption)
                        .frame(width: 78, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(MCOTheme.Color.paperRaised)
                .background(MCOTheme.Color.oxblood, in: Capsule())
                .accessibilityLabel("Review generated day cards")
                .accessibilityIdentifier("weekly.reviewGenerated")

                Button {
                    onRegenerate()
                } label: {
                    Text("Regenerate")
                        .font(MCOType.caption)
                        .frame(width: 78, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(MCOTheme.Color.oxblood)
                .background(MCOTheme.Color.paperRaised.opacity(0.72), in: Capsule())
                .overlay {
                    Capsule().stroke(MCOTheme.Color.hairline, lineWidth: 1)
                }
                .accessibilityLabel("Regenerate draft week")
            }
        }
    }

    private func rowState(for phase: WeeklyGenerationProgress.Phase) -> GenerationStatusRow.State {
        if progress.phase == .failed {
            return phase == .readyForReview ? .pending : .failed
        }

        if progress.phase == phase {
            return .active
        }

        return phaseOrder(progress.phase) > phaseOrder(phase) ? .complete : .pending
    }

    private var weeklyBriefRowState: GenerationStatusRow.State {
        if progress.phase == .savingWeeklyBrief {
            return .active
        }
        if progress.phase == .failed,
           progress.draftedDayCount == 0,
           progress.effectiveSavedDayCount == 0,
           progress.dayStatuses.isEmpty {
            return .failed
        }
        return .complete
    }

    private var strategyRowState: GenerationStatusRow.State {
        if progress.strategyCreated == true {
            return .complete
        }
        if progress.phase == .loadingContext {
            return .active
        }
        if progress.phase == .failed,
           progress.draftedDayCount == 0,
           progress.effectiveSavedDayCount == 0,
           progress.dayStatuses.isEmpty {
            return .failed
        }
        return phaseOrder(progress.phase) > phaseOrder(.loadingContext) ? .complete : .pending
    }

    private var draftingDaysRowState: GenerationStatusRow.State {
        if progress.draftedDayCount >= progress.totalDayCount && progress.totalDayCount > 0 {
            return .complete
        }
        if progress.phase == .failed {
            return .failed
        }
        if progress.phase == .draftingDays {
            return .active
        }
        return phaseOrder(progress.phase) > phaseOrder(.draftingDays) ? .complete : .pending
    }

    private var savedDraftsRowState: GenerationStatusRow.State {
        if progress.phase == .failed {
            return progress.effectiveSavedDayCount > 0 ? .active : .failed
        }
        if progress.effectiveSavedDayCount >= progress.totalDayCount && progress.totalDayCount > 0 {
            return .complete
        }
        if progress.effectiveSavedDayCount > 0 || progress.phase == .draftingDays || progress.phase == .savingDraftWeek {
            return .active
        }
        return .pending
    }

    private func phaseOrder(_ phase: WeeklyGenerationProgress.Phase) -> Int {
        switch phase {
        case .savingWeeklyBrief: 0
        case .loadingContext: 1
        case .draftingDays: 2
        case .savingDraftWeek: 4
        case .readyForReview: 5
        case .failed: -1
        }
    }

    private func retryFailedDay(_ dayStatus: WeeklyDayGenerationStatus) {
        guard let scheduledDate = dayStatus.scheduledDate,
              regeneratingFailedDay == nil
        else { return }

        regeneratingFailedDay = scheduledDate
        failedDayRegenerationErrors[scheduledDate] = nil
        Task {
            do {
                if dayStatus.retryAction == "retry_day", let onRetryQueuedDay {
                    try await onRetryQueuedDay(scheduledDate)
                } else if let onRegenerateDay {
                    _ = try await onRegenerateDay(scheduledDate, false)
                }
            } catch {
                failedDayRegenerationErrors[scheduledDate] = error.localizedDescription
            }
            regeneratingFailedDay = nil
        }
    }
}

struct WeeklyGenerationDayProgressList: View {
    let dayStatuses: [WeeklyDayGenerationStatus]
    let draft: GeneratedWeekDraft?
    let canRegenerateDay: Bool
    let regeneratingFailedDay: String?
    let errorMessages: [String: String]
    let onReviewGeneratedDay: () -> Void
    let onRetryDay: (WeeklyDayGenerationStatus) -> Void

    private var orderedDayStatuses: [WeeklyDayGenerationStatus] {
        dayStatuses.sorted { lhs, rhs in
            if lhs.statusSortKey != rhs.statusSortKey {
                return lhs.statusSortKey < rhs.statusSortKey
            }
            return (lhs.scheduledDate ?? "") < (rhs.scheduledDate ?? "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xs) {
            Text("Day progress")
                .font(MCOType.tinyLabel)
                .foregroundStyle(MCOTheme.Color.inkMuted)

            ForEach(orderedDayStatuses, id: \.self) { dayStatus in
                WeeklyGenerationDayProgressRow(
                    dayStatus: dayStatus,
                    generatedCard: generatedCard(for: dayStatus),
                    isRegenerating: regeneratingFailedDay == dayStatus.scheduledDate,
                    errorMessage: dayStatus.scheduledDate.flatMap { errorMessages[$0] },
                    canRegenerate: canRegenerateDay,
                    onReviewGeneratedDay: onReviewGeneratedDay,
                    onRetryDay: {
                        onRetryDay(dayStatus)
                    }
                )
            }
        }
    }

    private func generatedCard(for dayStatus: WeeklyDayGenerationStatus) -> GeneratedDailyCardDraft? {
        draft?.dailyCards.first {
            $0.id == dayStatus.dailyCardID || $0.scheduledDate == dayStatus.scheduledDate
        }
    }
}

struct WeeklyGenerationDayProgressRow: View {
    let dayStatus: WeeklyDayGenerationStatus
    let generatedCard: GeneratedDailyCardDraft?
    let isRegenerating: Bool
    let errorMessage: String?
    let canRegenerate: Bool
    let onReviewGeneratedDay: () -> Void
    let onRetryDay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xxs) {
            HStack(spacing: MCOSpace.s) {
                statusIcon
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(dayStatus.displayName): \(displayStatusLabel)")
                        .font(MCOType.bodySmall)
                        .foregroundStyle(titleColor)
                    if dayStatus.isFailed, !isRegenerating {
                        Text(dayStatus.failureDetail)
                            .font(MCOType.caption)
                            .foregroundStyle(MCOTheme.Color.inkMuted)
                    } else if let generatedCard {
                        Text(generatedCard.title)
                            .font(MCOType.caption)
                            .foregroundStyle(MCOTheme.Color.inkMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: MCOSpace.s)

                if dayStatus.isCompleted, generatedCard != nil {
                    Button("Review") {
                        onReviewGeneratedDay()
                    }
                    .font(MCOType.caption)
                    .padding(.horizontal, MCOSpace.s)
                    .frame(height: 30)
                    .buttonStyle(.plain)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                    .background(MCOTheme.Color.paperRaised.opacity(0.72), in: Capsule())
                    .overlay {
                        Capsule().stroke(MCOTheme.Color.hairline, lineWidth: 1)
                    }
                    .accessibilityLabel("Review \(dayStatus.displayName) generated card")
                } else if dayStatus.isFailed {
                    Button(action: onRetryDay) {
                        HStack(spacing: MCOSpace.xxs) {
                            if isRegenerating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text(isRegenerating ? "Retrying" : "Retry")
                        }
                        .font(MCOType.caption)
                        .padding(.horizontal, MCOSpace.s)
                        .frame(height: 30)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MCOTheme.Color.paper)
                    .background(MCOTheme.Color.oxblood, in: Capsule())
                    .disabled(!canRegenerate || isRegenerating)
                    .opacity(!canRegenerate || isRegenerating ? 0.55 : 1)
                    .accessibilityLabel("Retry \(dayStatus.displayName) generation")
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.clay)
                    .padding(.leading, 18 + MCOSpace.s)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isRegenerating {
            ProgressView()
                .controlSize(.mini)
                .tint(MCOTheme.Color.oxblood)
        } else if dayStatus.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MCOTheme.Color.success)
        } else if dayStatus.isRunning {
            ProgressView()
                .controlSize(.mini)
                .tint(MCOTheme.Color.oxblood)
        } else if dayStatus.isRetrying {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MCOTheme.Color.warning)
        } else if dayStatus.isFailed {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MCOTheme.Color.clay)
        } else if dayStatus.isCancelled {
            Image(systemName: "minus.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MCOTheme.Color.inkMuted)
        } else {
            Image(systemName: "circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MCOTheme.Color.inkMuted.opacity(0.7))
        }
    }

    private var titleColor: Color {
        if isRegenerating {
            return MCOTheme.Color.oxblood
        }
        if dayStatus.isFailed {
            return MCOTheme.Color.oxblood
        }
        if dayStatus.isQueued || dayStatus.isCancelled {
            return MCOTheme.Color.inkMuted
        }
        return MCOTheme.Color.ink
    }

    private var displayStatusLabel: String {
        isRegenerating ? "Retrying" : dayStatus.displayStatusLabel
    }
}

struct FailedGenerationDayRow: View {
    let dayStatus: WeeklyDayGenerationStatus
    let isRegenerating: Bool
    let errorMessage: String?
    let canRegenerate: Bool
    let onRegenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xxs) {
            HStack(spacing: MCOSpace.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MCOTheme.Color.clay)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(dayStatus.displayName): Failed")
                        .font(MCOType.bodySmall)
                        .foregroundStyle(MCOTheme.Color.oxblood)
                    Text(dayStatus.failureDetail)
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                }
                Spacer(minLength: MCOSpace.s)
                Button(action: onRegenerate) {
                    HStack(spacing: MCOSpace.xxs) {
                        if isRegenerating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(isRegenerating ? "Regenerating" : "Regenerate")
                    }
                    .font(MCOType.caption)
                    .padding(.horizontal, MCOSpace.s)
                    .frame(height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(MCOTheme.Color.paper)
                .background(MCOTheme.Color.oxblood, in: Capsule())
                .disabled(!canRegenerate || isRegenerating)
                .opacity(!canRegenerate || isRegenerating ? 0.55 : 1)
                .accessibilityLabel("Regenerate \(dayStatus.displayName)")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.clay)
                    .padding(.leading, 18 + MCOSpace.s)
            }
        }
        .padding(.vertical, 2)
    }
}

struct GenerationStatusRow: View {
    enum State {
        case pending
        case active
        case complete
        case failed
    }

    let title: String
    let detail: String?
    let state: State

    var body: some View {
        HStack(spacing: MCOSpace.s) {
            icon
                .frame(width: 18)
            Text(title)
                .font(MCOType.bodySmall)
                .foregroundStyle(textColor)
            Spacer(minLength: MCOSpace.s)
            if let detail {
                Text(detail)
                    .font(MCOType.caption)
                    .foregroundStyle(detailColor)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MCOTheme.Color.inkMuted.opacity(0.7))
        case .active:
            ProgressView()
                .controlSize(.mini)
                .tint(MCOTheme.Color.oxblood)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MCOTheme.Color.success)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MCOTheme.Color.clay)
        }
    }

    private var textColor: Color {
        switch state {
        case .pending:
            MCOTheme.Color.inkMuted
        case .active, .complete:
            MCOTheme.Color.ink
        case .failed:
            MCOTheme.Color.oxblood
        }
    }

    private var detailColor: Color {
        switch state {
        case .pending:
            MCOTheme.Color.inkMuted
        case .active:
            MCOTheme.Color.oxblood
        case .complete:
            MCOTheme.Color.sageDeep
        case .failed:
            MCOTheme.Color.oxblood
        }
    }
}

struct WeeklyWorkflowStatusBlock: View {
    let plan: WeeklyPlan
    let draft: GeneratedWeekDraft?
    let startDate: String
    let endDate: String

    private var status: WeeklyWorkflowWindowStatus {
        WeeklyWorkflowWindowStatus(plan: plan, startDate: startDate, endDate: endDate)
    }

    private var isBriefComplete: Bool {
        !plan.weeklyBriefText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isGeneratedComplete: Bool {
        isBriefComplete && draft != nil
    }

    private var isReviewedComplete: Bool {
        isGeneratedComplete && plan.openDayCount == 0
    }

    private var isPublishedComplete: Bool {
        isReviewedComplete && status == .published
    }

    var body: some View {
        HStack(spacing: MCOSpace.s) {
            WorkflowStep(number: 1, title: "Brief", isComplete: isBriefComplete)
            WorkflowStep(number: 2, title: "Generate", isComplete: isGeneratedComplete)
            WorkflowStep(number: 3, title: "Review", isComplete: isReviewedComplete)
            WorkflowStep(number: 4, title: "Publish", isComplete: isPublishedComplete)
        }
        .padding(.horizontal, MCOSpace.s)
        .padding(.vertical, MCOSpace.xs)
        .background(MCOTheme.Color.paperRaised)
        .clipShape(RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous)
                .stroke(MCOTheme.Color.hairline, lineWidth: 1)
        }
    }
}

struct WeeklyBriefToggleHeader: View {
    let isSet: Bool
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: MCOSpace.m) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(MCOTheme.Color.brass)
                    .frame(width: 34)

                Text("Weekly Brief")
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.ink)

                StatusChip(text: isSet ? "Set" : "Not set", tone: isSet ? .ready : .warning)
                Spacer(minLength: MCOSpace.s)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
            .padding(.vertical, MCOSpace.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Close Weekly Brief editor" : "Open Weekly Brief editor")
    }
}

enum WeeklyWorkflowWindowStatus: Equatable {
    case draft
    case planned
    case published

    init(plan: WeeklyPlan, startDate: String, endDate: String) {
        let windowDates = Set(SupabaseDateFormatting.weekDates(starting: startDate))
        let scheduledDays = plan.days.filter { $0.scheduledDate != nil }
        let daysInWindow = scheduledDays.filter { day in
            guard let scheduledDate = day.scheduledDate else { return false }
            return windowDates.contains(scheduledDate)
        }

        let hasScheduledDates = !scheduledDays.isEmpty
        let hasFullSelectedWindow = windowDates.count == 7 && daysInWindow.count == windowDates.count
        let hasPlannedContentInWindow = daysInWindow.contains { $0.state != .open }

        if hasScheduledDates {
            if plan.isSoftLocked && hasFullSelectedWindow {
                self = .published
            } else if hasPlannedContentInWindow {
                self = .planned
            } else {
                self = .draft
            }
        } else if plan.weekStartDate == startDate && plan.weekEndDate == endDate {
            if plan.isSoftLocked {
                self = .published
            } else if plan.plannedDayCount + plan.backupDayCount > 0 {
                self = .planned
            } else {
                self = .draft
            }
        } else {
            self = .draft
        }
    }

    var label: String {
        switch self {
        case .draft: "Draft"
        case .planned: "Planned"
        case .published: "Published"
        }
    }

    var tone: ChipTone {
        switch self {
        case .draft: .info
        case .planned: .warning
        case .published: .ready
        }
    }
}

private struct WorkflowStep: View {
    let number: Int
    let title: String
    let isComplete: Bool

    var body: some View {
        VStack(spacing: MCOSpace.xxs) {
            Text("\(number)")
                .font(MCOType.tinyLabel)
                .foregroundStyle(isComplete ? MCOTheme.Color.paperRaised : MCOTheme.Color.inkMuted)
                .frame(width: 24, height: 24)
                .background(isComplete ? MCOTheme.Color.success : MCOTheme.Color.paperRaised.opacity(0.74), in: Circle())
                .overlay {
                    Circle().stroke(isComplete ? MCOTheme.Color.success : MCOTheme.Color.hairline, lineWidth: 1)
                }
            Text(title)
                .font(MCOType.tinyLabel)
                .foregroundStyle(MCOTheme.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

struct WeekStartDateSelector: View {
    let startDate: String
    let endDate: String
    let isDisabled: Bool
    let onChange: (_ startDate: String) -> Void

    private var startOptions: [String] {
        let today = SupabaseDateFormatting.todayDateString()
        let forwardOptions = SupabaseDateFormatting.dateOptions(
            starting: today,
            dayCount: 84
        )

        if SupabaseDateFormatting.isDatePast(startDate, todayString: today) {
            return forwardOptions
        }

        if forwardOptions.contains(startDate) {
            return forwardOptions
        }

        return (forwardOptions + [startDate]).sorted()
    }

    var body: some View {
        HStack(alignment: .center, spacing: MCOSpace.s) {
            Menu {
                ForEach(startOptions, id: \.self) { date in
                    Button {
                        onChange(date)
                    } label: {
                        dateMenuLabel(
                            date: date,
                            isSelected: date == startDate
                        )
                    }
                }
            } label: {
                dateChip(title: SupabaseDateFormatting.displayDate(for: startDate))
            }
            .disabled(isDisabled)

            Text("through \(SupabaseDateFormatting.displayDate(for: endDate))")
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.inkMuted)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Week starts \(SupabaseDateFormatting.displayDate(for: startDate)) and runs through \(SupabaseDateFormatting.displayDate(for: endDate))")
    }

    private func dateChip(title: String) -> some View {
        HStack(spacing: MCOSpace.xxs) {
            Text(title)
                .font(.system(size: 16, weight: .regular, design: .serif))
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(isDisabled ? MCOTheme.Color.inkMuted : MCOTheme.Color.ink)
        .padding(.horizontal, MCOSpace.xs)
        .padding(.vertical, 6)
        .background(MCOTheme.Color.paperRaised.opacity(0.54))
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(MCOTheme.Color.hairline, lineWidth: 1)
        }
    }

    private func dateMenuLabel(date: String, isSelected: Bool) -> some View {
        Label(
            SupabaseDateFormatting.displayDate(for: date),
            systemImage: isSelected ? "checkmark" : "calendar"
        )
    }
}

private struct WeeklyDayDetailSelection: Identifiable {
    let id: UUID
    let day: WeeklyDay
    let generatedCard: GeneratedDailyCardDraft?

    init(day: WeeklyDay, generatedCard: GeneratedDailyCardDraft?) {
        id = day.id
        self.day = day
        self.generatedCard = generatedCard
    }
}

typealias RetryQueuedDayAction = (_ scheduledDate: String) async throws -> Void
typealias RegenerateDayAction = (_ scheduledDate: String, _ preserveManualEdits: Bool) async throws -> GeneratedDailyCardDraft

struct WeeklyInputsReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let plan: WeeklyPlan
    let profile: CreatorProfileSummary

    var body: some View {
        NavigationStack {
            ZStack {
                MCOTheme.Color.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: MCOSpace.l) {
                        header
                        WeeklySectionTitle(title: "Weekly Brief", subtitle: plan.weekRange)
                        WeeklySetupSummary(sections: plan.setupSections)
                        WeeklySectionTitle(title: "Creator Boundaries", subtitle: profile.voiceLine)
                        boundaryList
                    }
                    .padding(.horizontal, MCOSpace.l)
                    .padding(.top, MCOSpace.l)
                    .padding(.bottom, MCOSpace.xl)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(MCOTheme.Color.oxblood)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xs) {
            Text("MANAGER WEEKLY CONTROL")
                .font(MCOType.tinyLabel)
                .foregroundStyle(MCOTheme.Color.oxblood)
            Text("Review inputs")
                .font(MCOType.screenTitle)
                .foregroundStyle(MCOTheme.Color.ink)
            Text("Confirm the week is grounded before Creator sees the daily cards.")
                .font(MCOType.bodySmall)
                .foregroundStyle(MCOTheme.Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var boundaryList: some View {
        VStack(spacing: 0) {
            FolioRow(
                title: profile.displayName,
                subtitle: profile.positioning,
                leading: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(MCOTheme.Color.brass)
                },
                trailing: {
                    StatusChip(text: "Voice", tone: .ready)
                }
            )
            Hairline()

            ForEach(profile.noGoTopics, id: \.self) { topic in
                FolioRow(
                    title: topic,
                    subtitle: "Do not use as a content angle.",
                    leading: {
                        Image(systemName: "nosign")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(MCOTheme.Color.clay)
                    },
                    trailing: {
                        StatusChip(text: "No-go", tone: .warning)
                    }
                )
                Hairline()
            }
        }
    }
}

struct WeeklyBriefComposer: View {
    @Binding var text: String
    let isSaving: Bool
    let isDirty: Bool
    let errorMessage: String?
    let onSave: (String) async -> Bool

    @FocusState private var isFocused: Bool

    private let suggestions: [WeeklyBriefSuggestion] = [
        WeeklyBriefSuggestion(title: "Weekly routine", insertion: "Weekly routine: "),
        WeeklyBriefSuggestion(title: "Coming up", insertion: "Coming up this week: "),
        WeeklyBriefSuggestion(title: "Brand/collab", insertion: "Brand/collab: "),
        WeeklyBriefSuggestion(title: "Family", insertion: "Family/travel: ")
    ]

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                TextEditor(text: $text)
                    .font(MCOType.bodySmall)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(height: 176)
                    .padding(MCOSpace.s)
                    .background(MCOTheme.Color.paper.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                            .stroke(MCOTheme.Color.hairline, lineWidth: 1)
                    }
                    .overlay(alignment: .topLeading) {
                        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Where is the creator this week? What routine, family, travel, or collab should shape the seven days?")
                                .font(MCOType.bodySmall)
                                .foregroundStyle(MCOTheme.Color.inkMuted)
                                .padding(.horizontal, MCOSpace.m)
                                .padding(.vertical, MCOSpace.m)
                                .allowsHitTesting(false)
                        }
                    }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 118), spacing: MCOSpace.xs)],
                    alignment: .leading,
                    spacing: MCOSpace.xs
                ) {
                    ForEach(suggestions) { suggestion in
                        Button {
                            append(suggestion)
                        } label: {
                            Text(suggestion.title)
                                .font(MCOType.caption)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, MCOSpace.xs)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(MCOTheme.Color.oxblood)
                        .background(MCOTheme.Color.paperRaised.opacity(0.68), in: Capsule())
                        .overlay {
                            Capsule().stroke(MCOTheme.Color.hairline, lineWidth: 1)
                        }
                    }
                }

                HStack(spacing: MCOSpace.s) {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(MCOType.caption)
                            .foregroundStyle(MCOTheme.Color.oxblood)
                            .lineLimit(2)
                    } else if isDirty {
                        Text("Unsaved")
                            .font(MCOType.caption)
                            .foregroundStyle(MCOTheme.Color.brass)
                    } else {
                        EmptyView()
                    }

                    Spacer(minLength: MCOSpace.s)

                    Button {
                        save()
                    } label: {
                        HStack(spacing: MCOSpace.xs) {
                            Image(systemName: isSaving ? "hourglass" : "checkmark")
                            Text(isSaving ? "Saving" : "Save")
                        }
                        .font(MCOType.caption)
                        .padding(.horizontal, MCOSpace.m)
                        .frame(height: 36)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MCOTheme.Color.paperRaised)
                    .background(MCOTheme.Color.oxblood, in: Capsule())
                    .disabled(isSaving || !isDirty)
                    .opacity(isSaving || !isDirty ? 0.48 : 1)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isFocused = false
                }
                Button("Save") {
                    save()
                }
                .disabled(isSaving || !isDirty)
            }
        }
    }

    private func append(_ suggestion: WeeklyBriefSuggestion) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            text = suggestion.insertion
        } else if text.hasSuffix("\n") {
            text += suggestion.insertion
        } else {
            text += "\n\(suggestion.insertion)"
        }
        isFocused = true
    }

    private func save() {
        isFocused = false
        Task {
            _ = await onSave(text)
        }
    }
}

private struct WeeklyBriefSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let insertion: String
}

struct WeeklyContextLinks: View {
    let profile: CreatorProfileSummary
    @Binding var isCreatorProfileExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    isCreatorProfileExpanded.toggle()
                }
            } label: {
                expandableContextRow(
                    systemImage: "person.crop.circle.badge.checkmark",
                    title: "Using Creator Profile",
                    isExpanded: isCreatorProfileExpanded
                )
            }
            .buttonStyle(.plain)

            if isCreatorProfileExpanded {
                VStack(alignment: .leading, spacing: MCOSpace.s) {
                    Text(profile.positioning)
                        .font(MCOType.bodySmall)
                        .foregroundStyle(MCOTheme.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if !profile.contentPillars.isEmpty {
                        Text("Pillars: \(profile.contentPillars.joined(separator: ", "))")
                            .font(MCOType.caption)
                            .foregroundStyle(MCOTheme.Color.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    NavigationLink {
                        CreatorProfileAdminView()
                    } label: {
                        Text("Edit")
                            .font(MCOType.caption)
                            .foregroundStyle(MCOTheme.Color.oxblood)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit")
                }
                .padding(.leading, 34 + MCOSpace.m)
                .padding(.trailing, MCOSpace.m)
                .padding(.bottom, MCOSpace.s)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Hairline()

            NavigationLink {
                IntelligenceHomeView()
            } label: {
                contextRow(
                    systemImage: "bookmark",
                    title: "Idea Bank",
                    subtitle: nil,
                    trailing: "Open"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func expandableContextRow(
        systemImage: String,
        title: String,
        isExpanded: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: MCOSpace.m) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(MCOTheme.Color.brass)
                .frame(width: 34)

            Text(title)
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundStyle(MCOTheme.Color.ink)

            Spacer(minLength: MCOSpace.s)

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MCOTheme.Color.inkMuted)
        }
        .padding(.vertical, MCOSpace.s)
        .contentShape(Rectangle())
    }

    private func contextRow(
        systemImage: String,
        title: String,
        subtitle: String?,
        trailing: String
    ) -> some View {
        HStack(alignment: .center, spacing: MCOSpace.m) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(MCOTheme.Color.brass)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text(title)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: MCOSpace.s)

            Text(trailing)
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.oxblood)
        }
        .padding(.vertical, MCOSpace.s)
        .contentShape(Rectangle())
    }
}

struct WeeklyBriefEditSheet: View {
    let sections: [WeeklySetupSection]
    let isSaving: Bool
    let errorMessage: String?
    let onSave: ([WeeklySetupSection]) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var editableSections: [WeeklySetupSection]

    init(
        sections: [WeeklySetupSection],
        isSaving: Bool,
        errorMessage: String?,
        onSave: @escaping ([WeeklySetupSection]) async -> Bool
    ) {
        self.sections = sections
        self.isSaving = isSaving
        self.errorMessage = errorMessage
        self.onSave = onSave
        _editableSections = State(initialValue: sections)
    }

    var body: some View {
        EditorialScreen {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                header

                if let errorMessage {
                    AdminSignalBlock(
                        title: "Brief not saved",
                        value: errorMessage,
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                }

                VStack(spacing: MCOSpace.m) {
                    ForEach($editableSections) { $section in
                        WeeklyBriefSectionEditor(section: $section)
                    }
                }
                .padding(.bottom, 112)
            }
        } bottomBar: {
            GlassCommandBar {
                SecondaryActionButton(title: "Cancel") {
                    dismiss()
                }
                .frame(maxWidth: 130)
                .disabled(isSaving)

                PrimaryActionButton(
                    title: isSaving ? "Saving" : "Save brief",
                    systemImage: isSaving ? "hourglass" : "checkmark"
                ) {
                    Task {
                        if await onSave(editableSections) {
                            dismiss()
                        }
                    }
                }
                .disabled(isSaving || editableSections == sections)
            }
        }
        .navigationBarHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            HStack {
                Spacer()
                FloatingIconButton(systemImage: "xmark", label: "Close") {
                    dismiss()
                }
            }

            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                Text("Edit Weekly Brief")
                    .font(MCOType.display)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text("Update the inputs used to shape this week.")
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
        }
    }
}

struct WeeklyBriefSectionEditor: View {
    @Binding var section: WeeklySetupSection

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            HStack(spacing: MCOSpace.s) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(MCOTheme.Color.brass)
                    .frame(width: 34)

                Text(section.title)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.ink)

                Spacer(minLength: MCOSpace.s)

                StatusChip(text: section.state, tone: section.state == "Needs detail" ? .warning : .ready)
            }

            TextField("Summary", text: $section.summary, axis: .vertical)
                .font(MCOType.bodySmall)
                .foregroundStyle(MCOTheme.Color.ink)
                .lineLimit(2...5)
                .textFieldStyle(.plain)
        }
        .padding(MCOSpace.m)
        .background(MCOTheme.Color.paperRaised.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous)
                .stroke(MCOTheme.Color.hairline, lineWidth: 1)
        }
    }
}

struct GeneratedWeekReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GeneratedWeekDraft
    let canRegenerateDay: Bool
    let onSave: (GeneratedWeekDraft) -> Void
    let onPublish: (GeneratedWeekDraft) -> Void
    let onRegenerateDay: RegenerateDayAction?

    init(
        draft: GeneratedWeekDraft,
        canRegenerateDay: Bool = false,
        onSave: @escaping (GeneratedWeekDraft) -> Void,
        onPublish: @escaping (GeneratedWeekDraft) -> Void,
        onRegenerateDay: RegenerateDayAction? = nil
    ) {
        _draft = State(initialValue: draft)
        self.canRegenerateDay = canRegenerateDay
        self.onSave = onSave
        self.onPublish = onPublish
        self.onRegenerateDay = onRegenerateDay
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MCOTheme.Color.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: MCOSpace.l) {
                        header
                        GenerationSummaryBlock(
                            title: "Strategy",
                            bodyText: draft.strategySummary
                        )
                        if !draft.warnings.isEmpty {
                            GenerationBulletBlock(title: "Warnings", items: draft.warnings)
                        }
                        if !draft.assumptions.isEmpty {
                            GenerationBulletBlock(title: "Assumptions", items: draft.assumptions)
                        }
                        ForEach($draft.dailyCards) { $card in
                            GeneratedDailyCardEditor(
                                card: $card,
                                canRegenerate: canRegenerateDay,
                                onRegenerate: onRegenerateDay
                            )
                        }
                    }
                    .padding(.horizontal, MCOSpace.l)
                    .padding(.top, MCOSpace.l)
                    .padding(.bottom, 110)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        onSave(draft)
                        dismiss()
                    }
                    .foregroundStyle(MCOTheme.Color.oxblood)
                    .accessibilityIdentifier("weekly.generatedReview.done")
                }
            }
            .safeAreaInset(edge: .bottom) {
                GlassCommandBar {
                    SecondaryActionButton(title: "Save edits") {
                        onSave(draft)
                    }
                    .accessibilityIdentifier("weekly.generatedReview.save")
                    PrimaryActionButton(title: "Publish draft", systemImage: "paperplane") {
                        onPublish(draft)
                        dismiss()
                    }
                    .accessibilityIdentifier("weekly.generatedReview.publishDraft")
                }
                .padding(.horizontal, MCOSpace.m)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xs) {
            Text("MANAGER AI REVIEW")
                .font(MCOType.tinyLabel)
                .foregroundStyle(MCOTheme.Color.oxblood)
            Text("Generated week")
                .font(MCOType.screenTitle)
                .foregroundStyle(MCOTheme.Color.ink)
            Text(draft.sourceSummary)
                .font(MCOType.bodySmall)
                .foregroundStyle(MCOTheme.Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct GenerationSummaryBlock: View {
    let title: String
    let bodyText: String

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                Text(title)
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                Text(bodyText)
                    .font(MCOType.bodySmall)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct GenerationBulletBlock: View {
    let title: String
    let items: [String]

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                Text(title)
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: MCOSpace.s) {
                        Circle()
                            .fill(MCOTheme.Color.brass)
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)
                        Text(item)
                            .font(MCOType.bodySmall)
                            .foregroundStyle(MCOTheme.Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

struct GeneratedDailyCardEditor: View {
    @Binding var card: GeneratedDailyCardDraft
    var canRegenerate = false
    var onRegenerate: RegenerateDayAction?
    @State private var isInspectingGeneratedFields = false
    @State private var preserveManualEdits = true
    @State private var isRegenerating = false
    @State private var regenerationError: String?

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text(card.scheduledDate)
                        .font(MCOType.tinyLabel)
                        .foregroundStyle(MCOTheme.Color.oxblood)
                    Spacer()
                    Text("\(Int(card.creatorFitScore.rounded())) fit")
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.brass)
                }
                GeneratedTextField(title: "Title", text: $card.title)
                GeneratedTextField(title: "Why today", text: $card.whyToday, lineLimit: 3)
                HStack(spacing: MCOSpace.s) {
                    GeneratedTextField(title: "Shootability", text: $card.shootability)
                    Stepper(
                        "\(card.estimatedShootMinutes) min",
                        value: $card.estimatedShootMinutes,
                        in: 0...60,
                        step: 1
                    )
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.ink)
                }
                GeneratedTextEditor(title: "Scene list", text: sceneListBinding, minHeight: 96)
                GeneratedTextEditor(title: "Caption", text: $card.caption, minHeight: 96)
                GeneratedTextEditor(title: "Backup story", text: $card.backupStory, minHeight: 76)
                GeneratedTextEditor(title: "Caption-only backup", text: $card.backupCaptionOnly, minHeight: 76)
                DayRegenerationControls(
                    preserveManualEdits: $preserveManualEdits,
                    isRegenerating: isRegenerating,
                    errorMessage: regenerationError,
                    isDisabled: !canRegenerate || onRegenerate == nil,
                    onRegenerate: regenerate
                )
                GeneratedCardInspectionBlock(
                    card: card,
                    isExpanded: $isInspectingGeneratedFields
                )
            }
        }
    }

    private func regenerate() {
        guard let onRegenerate, !isRegenerating else { return }
        isRegenerating = true
        regenerationError = nil

        Task {
            defer { isRegenerating = false }
            do {
                card = try await onRegenerate(card.scheduledDate, preserveManualEdits)
            } catch {
                regenerationError = error.localizedDescription
            }
        }
    }

    private var sceneListBinding: Binding<String> {
        Binding {
            card.sceneList.map(\.title).joined(separator: "\n")
        } set: { value in
            let titles = value
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            card.sceneList = titles.enumerated().map { index, title in
                let existing = card.sceneList.indices.contains(index) ? card.sceneList[index] : nil
                return ShotScene(
                    number: index + 1,
                    title: title,
                    duration: existing?.duration ?? "4 sec",
                    symbol: existing?.symbol ?? "sparkles"
                )
            }
        }
    }
}

struct GeneratedCardInspectionBlock: View {
    let card: GeneratedDailyCardDraft
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                GeneratedReadOnlyField(title: "Growth job", value: card.growthJob)
                GeneratedReadOnlyField(title: "Pillar", value: card.contentPillar)
                GeneratedReadOnlyField(title: "Energy", value: card.energyRequired)
                GeneratedReadOnlyField(title: "Language", value: card.languageMode)
                GeneratedReadOnlyField(title: "Scenes", value: sceneSummary)
                GeneratedReadOnlyField(title: "Script", value: card.script)
                GeneratedReadOnlyField(title: "No voiceover", value: card.noVoiceoverVersion)
                GeneratedReadOnlyField(title: "On-screen text", value: card.onScreenText.joined(separator: "\n"))
                GeneratedReadOnlyField(title: "CTA", value: card.cta)
                GeneratedReadOnlyField(title: "Hashtags", value: hashtagSummary)
                GeneratedReadOnlyField(title: "Cover", value: card.coverText)
                GeneratedReadOnlyField(title: "Post instructions", value: card.postInstructions)
                GeneratedReadOnlyField(title: "Audio notes", value: card.audioOptionNotes)
                GeneratedReadOnlyField(title: "Brand notes", value: card.brandEventNotes)
                GeneratedReadOnlyField(title: "Risk notes", value: card.riskNotes.joined(separator: "\n"))
                GeneratedReadOnlyField(title: "Assumptions", value: card.assumptions.joined(separator: "\n"))
                GeneratedReadOnlyField(title: "Source", value: card.sourceNote)
            }
            .padding(.top, MCOSpace.s)
        } label: {
            HStack(spacing: MCOSpace.s) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MCOTheme.Color.brass)
                Text("Full generated card")
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.ink)
            }
        }
        .tint(MCOTheme.Color.oxblood)
    }

    private var sceneSummary: String {
        card.sceneList
            .map { "\($0.number). \($0.title) (\($0.duration))" }
            .joined(separator: "\n")
    }

    private var hashtagSummary: String {
        card.hashtags.map { "#\($0.trimmingCharacters(in: CharacterSet(charactersIn: "#")))" }
            .joined(separator: " ")
    }
}

struct GeneratedReadOnlyField: View {
    let title: String
    let value: String

    var body: some View {
        if let normalizedValue = value.nilIfBlank {
            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text(title)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                Text(normalizedValue)
                    .font(MCOType.bodySmall)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct WeeklyDayDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let day: WeeklyDay
    @State private var generatedCard: GeneratedDailyCardDraft?
    let isLocked: Bool
    let canRegenerateDay: Bool
    let onSetState: @MainActor (WeeklyDayState) async -> Bool
    let onRegenerateDay: RegenerateDayAction?
    @State private var preserveManualEdits = true
    @State private var isRegenerating = false
    @State private var regenerationError: String?

    init(
        day: WeeklyDay,
        generatedCard: GeneratedDailyCardDraft?,
        isLocked: Bool,
        canRegenerateDay: Bool = false,
        onSetState: @escaping @MainActor (WeeklyDayState) async -> Bool,
        onRegenerateDay: RegenerateDayAction? = nil
    ) {
        self.day = day
        _generatedCard = State(initialValue: generatedCard)
        self.isLocked = isLocked
        self.canRegenerateDay = canRegenerateDay
        self.onSetState = onSetState
        self.onRegenerateDay = onRegenerateDay
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MCOTheme.Color.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: MCOSpace.l) {
                        header
                        plannedContent
                        stateActions
                        if generatedCard != nil {
                            DayRegenerationControls(
                                preserveManualEdits: $preserveManualEdits,
                                isRegenerating: isRegenerating,
                                errorMessage: regenerationError,
                                isDisabled: isLocked || !canRegenerateDay || onRegenerateDay == nil,
                                onRegenerate: regenerate
                            )
                        }
                    }
                    .padding(.horizontal, MCOSpace.l)
                    .padding(.top, MCOSpace.l)
                    .padding(.bottom, MCOSpace.xl)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(MCOTheme.Color.oxblood)
                    .accessibilityIdentifier("weekly.day.detail.close")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func regenerate() {
        guard
            let scheduledDate = generatedCard?.scheduledDate ?? day.scheduledDate,
            let onRegenerateDay,
            !isRegenerating
        else {
            return
        }

        isRegenerating = true
        regenerationError = nil
        Task {
            defer { isRegenerating = false }
            do {
                generatedCard = try await onRegenerateDay(scheduledDate, preserveManualEdits)
            } catch {
                regenerationError = error.localizedDescription
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xs) {
            Text("\(day.weekday) \(day.date)")
                .font(MCOType.tinyLabel)
                .foregroundStyle(day.state.accent)
            Text(day.title)
                .font(MCOType.screenTitle)
                .foregroundStyle(MCOTheme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(day.reason)
                .font(MCOType.bodySmall)
                .foregroundStyle(MCOTheme.Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stateActions: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                HStack {
                    Text(isLocked ? "Published status" : "Confirm status")
                        .font(MCOType.tinyLabel)
                        .foregroundStyle(MCOTheme.Color.oxblood)
                    Spacer()
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MCOTheme.Color.brass)
                    }
                }

                HStack(spacing: MCOSpace.s) {
                    WeeklyDayStateActionButton(
                        state: .planned,
                        selectedState: day.state,
                        isDisabled: isLocked,
                        identifier: "weekly.day.\(day.weekday).ready"
                    ) {
                        Task {
                            if await onSetState(.planned) {
                                dismiss()
                            }
                        }
                    }
                    WeeklyDayStateActionButton(
                        state: .backup,
                        selectedState: day.state,
                        isDisabled: isLocked,
                        identifier: "weekly.day.\(day.weekday).backup"
                    ) {
                        Task {
                            if await onSetState(.backup) {
                                dismiss()
                            }
                        }
                    }
                    WeeklyDayStateActionButton(
                        state: .open,
                        selectedState: day.state,
                        isDisabled: isLocked,
                        identifier: "weekly.day.\(day.weekday).open"
                    ) {
                        Task {
                            if await onSetState(.open) {
                                dismiss()
                            }
                        }
                    }
                }

                if isLocked {
                    Text("Published weeks are locked.")
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                }
            }
        }
    }

    @ViewBuilder
    private var plannedContent: some View {
        if let generatedCard {
            GeneratedDayPlannedContent(card: generatedCard)
        } else {
            GenerationSummaryBlock(title: "Planned content", bodyText: day.reason)
            GenerationSummaryBlock(title: "Source", bodyText: day.source.rawValue)
        }
    }
}

struct DayRegenerationControls: View {
    @Binding var preserveManualEdits: Bool
    let isRegenerating: Bool
    let errorMessage: String?
    let isDisabled: Bool
    let onRegenerate: () -> Void

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                HStack(alignment: .center, spacing: MCOSpace.s) {
                    VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                        Text("Regenerate this day")
                            .font(MCOType.tinyLabel)
                            .foregroundStyle(MCOTheme.Color.oxblood)
                        Text(preserveManualEdits ? "Keep edited fields where possible." : "Replace the entire generated card.")
                            .font(MCOType.caption)
                            .foregroundStyle(MCOTheme.Color.inkMuted)
                    }
                    Spacer()
                    Toggle("Keep my edits", isOn: $preserveManualEdits)
                        .labelsHidden()
                        .tint(MCOTheme.Color.oxblood)
                        .disabled(isRegenerating || isDisabled)
                        .accessibilityLabel("Keep my edits")
                }

                Button(action: onRegenerate) {
                    HStack(spacing: MCOSpace.s) {
                        if isRegenerating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(isRegenerating ? "Regenerating day" : "Regenerate day")
                    }
                    .font(MCOType.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(.plain)
                .foregroundStyle(MCOTheme.Color.paper)
                .background(MCOTheme.Color.oxblood, in: RoundedRectangle(cornerRadius: MCOShape.controlRadius))
                .disabled(isRegenerating || isDisabled)
                .opacity(isRegenerating || isDisabled ? 0.5 : 1)

                if let errorMessage {
                    Text(errorMessage)
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.oxblood)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct WeeklyDayStateActionButton: View {
    let state: WeeklyDayState
    let selectedState: WeeklyDayState
    let isDisabled: Bool
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: MCOSpace.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(state.label)
                    .font(MCOType.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? state.accent : MCOTheme.Color.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(isSelected ? state.accent.opacity(0.14) : MCOTheme.Color.paperRaised.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                    .stroke(isSelected ? state.accent.opacity(0.62) : MCOTheme.Color.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityIdentifier(identifier ?? "")
    }

    private var isSelected: Bool {
        selectedState == state
    }

    private var systemImage: String {
        switch state {
        case .planned:
            "checkmark.circle.fill"
        case .backup:
            "exclamationmark.triangle.fill"
        case .open:
            "circle.dashed"
        }
    }
}

struct GeneratedDayPlannedContent: View {
    let card: GeneratedDailyCardDraft

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.m) {
            InstagramExecutionSummary(card: card)
            if !card.sceneList.isEmpty {
                InstagramSceneChecklist(scenes: card.sceneList, shotTimeline: card.shotTimeline)
            }
            VoiceoverTimelineBlock(card: card)
            OnScreenTextTimelineBlock(card: card)
            InstagramCaptionPostBlock(card: card)
            DayDecisionBlock(card: card)
        }
    }
}

struct DayDecisionBlock: View {
    let card: GeneratedDailyCardDraft

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                Text("Why this day")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                ExecutionSummaryLine(title: "Reason", value: card.whyToday)
                if let saveShareReason = card.saveShareReason?.nilIfBlank {
                    ExecutionSummaryLine(title: "Why followers save/share it", value: saveShareReason)
                }
                if let sourceNote = card.sourceNote.nilIfBlank {
                    ExecutionSummaryLine(title: "Reference signal", value: sourceNote)
                }
            }
        }
    }
}

struct InstagramExecutionSummary: View {
    let card: GeneratedDailyCardDraft

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                HStack(alignment: .firstTextBaseline, spacing: MCOSpace.s) {
                    Text("Shoot folio")
                        .font(MCOType.tinyLabel)
                        .foregroundStyle(MCOTheme.Color.oxblood)
                    Spacer(minLength: MCOSpace.s)
                    Text(formatLabel)
                        .font(MCOType.tinyLabel)
                        .foregroundStyle(MCOTheme.Color.paperRaised)
                        .padding(.horizontal, MCOSpace.s)
                        .frame(height: 26)
                        .background(MCOTheme.Color.oxblood, in: Capsule())
                    Text(durationLabel)
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                }

                VStack(alignment: .leading, spacing: MCOSpace.s) {
                    ExecutionSummaryLine(title: "Hook", value: hook)
                    ExecutionSummaryLine(title: "Shoot direction", value: premise)
                    if let postInstructions = card.postInstructions.nilIfBlank {
                        ExecutionSummaryLine(title: "Post instruction", value: postInstructions)
                    }
                }
            }
        }
    }

    private var formatLabel: String {
        card.format?.nilIfBlank ?? "Reel"
    }

    private var durationLabel: String {
        if let durationSeconds = card.durationSeconds, durationSeconds > 0 {
            return "\(durationSeconds) sec edit"
        }
        if let seconds = SceneTiming.totalSeconds(for: card.sceneList), seconds > 0 {
            return "\(seconds) sec edit"
        }
        return "\(card.estimatedShootMinutes) min shoot"
    }

    private var hook: String {
        card.hook?.nilIfBlank ?? card.title
    }

    private var premise: String {
        card.saveShareReason?.nilIfBlank ?? card.whyToday
    }
}

struct ExecutionSummaryLine: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xxs) {
            Text(title)
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.inkMuted)
            Text(value)
                .font(MCOType.bodySmall)
                .foregroundStyle(MCOTheme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ExecutionDetailsRegenerationNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: MCOSpace.s) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MCOTheme.Color.brass)
                .padding(.top, 2)
            Text("Details need regeneration for timestamped voiceover lines and exact video-portion mapping.")
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: MCOSpace.s)
        }
        .padding(.horizontal, MCOSpace.m)
        .padding(.vertical, MCOSpace.s)
        .background(MCOTheme.Color.paperRaised.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                .stroke(MCOTheme.Color.hairline, lineWidth: 1)
        }
    }
}

struct InstagramSceneChecklist: View {
    let scenes: [ShotScene]
    var shotTimeline: [ProductionTimelineItem] = []
    @State private var expandedSceneIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xs) {
            ProductionLabel(title: "Scenes to shoot", systemImage: "camera.viewfinder")
            if !shotTimeline.isEmpty {
                VStack(spacing: MCOSpace.xs) {
                    ForEach(shotTimeline) { item in
                        TimelineDisclosureRow(item: item, fallbackSystemImage: "video")
                    }
                }
            } else {
                VStack(spacing: MCOSpace.xs) {
                    ForEach(Array(scenes.enumerated()), id: \.element.id) { index, scene in
                        DisclosureGroup(isExpanded: binding(for: scene.id)) {
                            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                                if let window = SceneTiming.windows(for: scenes)[safe: index] {
                                    ProductionMiniNote(title: "Video portion", value: window)
                                }
                                Text("Capture \(scene.title.lowercased()) as a steady \(scene.duration.nilIfBlank ?? "short") clip. Keep the main subject readable and leave clear negative space for any on-screen text.")
                                    .font(MCOType.caption)
                                    .foregroundStyle(MCOTheme.Color.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, MCOSpace.xs)
                        } label: {
                            HStack(alignment: .top, spacing: MCOSpace.s) {
                                Text("\(scene.number)")
                                    .font(MCOType.caption)
                                    .foregroundStyle(MCOTheme.Color.paperRaised)
                                    .frame(width: 22, height: 22)
                                    .background(MCOTheme.Color.sageDeep, in: Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(scene.title)
                                        .font(MCOType.bodySmall)
                                        .foregroundStyle(MCOTheme.Color.ink)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let duration = scene.duration.nilIfBlank {
                                        Text(duration)
                                            .font(MCOType.caption)
                                            .foregroundStyle(MCOTheme.Color.inkMuted)
                                    }
                                }

                                Spacer(minLength: MCOSpace.xs)

                                Image(systemName: scene.symbol.nilIfBlank ?? "video")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(MCOTheme.Color.brass)
                                    .frame(width: 20)
                            }
                        }
                        .tint(MCOTheme.Color.oxblood)
                        .padding(.vertical, MCOSpace.xs)
                        .padding(.horizontal, MCOSpace.s)
                        .background(MCOTheme.Color.paperRaised.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
                    }
                }
            }
        }
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding {
            expandedSceneIDs.contains(id)
        } set: { isExpanded in
            if isExpanded {
                expandedSceneIDs.insert(id)
            } else {
                expandedSceneIDs.remove(id)
            }
        }
    }
}

struct TimelineDisclosureRow: View {
    let item: ProductionTimelineItem
    let fallbackSystemImage: String
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                if let target = item.timelineTarget {
                    ProductionMiniNote(title: "Video portion", value: target)
                }
                Text(item.timelineBody)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, MCOSpace.xs)
        } label: {
            HStack(alignment: .top, spacing: MCOSpace.s) {
                Text(item.timestamp.nilIfBlank ?? "--")
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                    .frame(width: 72, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title.nilIfBlank ?? item.timelineBody)
                        .font(MCOType.bodySmall)
                        .foregroundStyle(MCOTheme.Color.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let shot = item.shot?.nilIfBlank {
                        Text(shot)
                            .font(MCOType.caption)
                            .foregroundStyle(MCOTheme.Color.inkMuted)
                    }
                }
                Spacer(minLength: MCOSpace.xs)
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MCOTheme.Color.brass)
                    .frame(width: 20)
            }
        }
        .tint(MCOTheme.Color.oxblood)
        .padding(.vertical, MCOSpace.xs)
        .padding(.horizontal, MCOSpace.s)
        .background(MCOTheme.Color.paperRaised.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
    }
}

struct VoiceoverTimelineBlock: View {
    let card: GeneratedDailyCardDraft

    var body: some View {
        if !card.voiceoverTimeline.isEmpty {
            ExecutionTimelineBlock(
                title: "Voiceover timeline",
                systemImage: "waveform",
                rows: card.voiceoverTimeline.map { item in
                    ExecutionTimelineRow(
                        timecode: item.timestamp.nilIfBlank,
                        target: item.timelineTarget,
                        text: item.voiceover?.nilIfBlank ?? item.timelineBody
                    )
                }
            )
        } else {
            ProductionDetailBlock(
                title: "Voiceover timeline",
                systemImage: "waveform",
                bodyText: card.script
            )
        }
    }

}

struct OnScreenTextTimelineBlock: View {
    let card: GeneratedDailyCardDraft

    var body: some View {
        if !card.onScreenTextTimeline.isEmpty {
            ExecutionTimelineBlock(
                title: "On-screen text timeline",
                systemImage: "text.bubble",
                rows: card.onScreenTextTimeline.map { item in
                    ExecutionTimelineRow(
                        timecode: item.timestamp.nilIfBlank,
                        target: item.timelineTarget,
                        text: item.onScreenText?.nilIfBlank ?? item.timelineBody
                    )
                }
            )
        } else if !card.onScreenText.isEmpty {
            ExecutionTimelineBlock(
                title: "On-screen text timeline",
                systemImage: "text.bubble",
                rows: card.onScreenText.enumerated().map { index, line in
                    ExecutionTimelineRow(
                        timecode: SceneTiming.windows(for: card.sceneList)[safe: index],
                        target: SceneTiming.sceneTitle(for: card.sceneList, index: index),
                        text: line
                    )
                }
            )
        }
    }
}

struct SilentVersionTimelineBlock: View {
    let card: GeneratedDailyCardDraft

    var body: some View {
        if !card.silentVersionTimeline.isEmpty {
            ExecutionTimelineBlock(
                title: "Silent Reel version",
                systemImage: "speaker.slash",
                rows: card.silentVersionTimeline.map { item in
                    ExecutionTimelineRow(
                        timecode: item.timestamp.nilIfBlank,
                        target: item.timelineTarget,
                        text: item.timelineBody
                    )
                }
            )
        } else {
            ProductionDetailBlock(
                title: "Silent Reel version",
                systemImage: "speaker.slash",
                bodyText: card.noVoiceoverVersion
            )
        }
    }
}

struct ExecutionTimelineBlock: View {
    let title: String
    let systemImage: String
    let rows: [ExecutionTimelineRow]

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xs) {
            ProductionLabel(title: title, systemImage: systemImage)
            VStack(spacing: MCOSpace.xs) {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: MCOSpace.s) {
                        if let timecode = row.timecode {
                            Text(timecode)
                                .font(MCOType.caption)
                                .foregroundStyle(MCOTheme.Color.oxblood)
                                .frame(width: 72, alignment: .leading)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            if let target = row.target {
                                Text(target)
                                    .font(MCOType.tinyLabel)
                                    .foregroundStyle(MCOTheme.Color.inkMuted)
                            }
                            Text(row.text)
                                .font(MCOType.bodySmall)
                                .foregroundStyle(MCOTheme.Color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: MCOSpace.xs)
                    }
                    .padding(.vertical, MCOSpace.xs)
                    .padding(.horizontal, MCOSpace.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MCOTheme.Color.paperRaised.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
                }
            }
        }
    }
}

struct ExecutionTimelineRow: Identifiable {
    let id = UUID()
    let timecode: String?
    let target: String?
    let text: String
}

struct InstagramCaptionPostBlock: View {
    let card: GeneratedDailyCardDraft

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                Text("Caption + CTA + post instructions")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                GeneratedReadOnlyField(title: "Caption", value: card.caption)
                GeneratedReadOnlyField(title: "CTA", value: card.cta)
                GeneratedReadOnlyField(title: "Cover text", value: card.coverText)
                GeneratedReadOnlyField(title: "Post instructions", value: card.postInstructions)
                GeneratedReadOnlyField(title: "Hashtags", value: hashtagSummary)
            }
        }
    }

    private var hashtagSummary: String {
        card.hashtags.map { "#\($0.trimmingCharacters(in: CharacterSet(charactersIn: "#")))" }
            .joined(separator: " ")
    }
}

struct BackupExecutionOptions: View {
    let card: GeneratedDailyCardDraft
    @State private var expandedSections: Set<BackupSection> = [.story]

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xs) {
            ExpandableBackupBlock(
                title: "Backup Story",
                subtitle: "Open if the Reel cannot be finished today.",
                systemImage: "rectangle.stack",
                bodyText: card.backupStory,
                timelineItems: card.backupStoryDetail,
                isExpanded: binding(for: .story)
            )
            ExpandableBackupBlock(
                title: "Text-only backup post",
                subtitle: "Use this when there is no usable footage; publish as a caption-led fallback.",
                systemImage: "text.alignleft",
                bodyText: card.captionBackupDetail?.nilIfBlank ?? card.backupCaptionOnly,
                isExpanded: binding(for: .textOnly)
            )
        }
    }

    private func binding(for section: BackupSection) -> Binding<Bool> {
        Binding {
            expandedSections.contains(section)
        } set: { isExpanded in
            if isExpanded {
                expandedSections.insert(section)
            } else {
                expandedSections.remove(section)
            }
        }
    }

    private enum BackupSection: Hashable {
        case story
        case textOnly
    }
}

struct ExpandableBackupBlock: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let bodyText: String
    var timelineItems: [ProductionTimelineItem] = []
    @Binding var isExpanded: Bool

    var body: some View {
        if bodyText.nilIfBlank != nil || !timelineItems.isEmpty {
            JournalBlock {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: MCOSpace.s) {
                        if let text = bodyText.nilIfBlank {
                            Text(text)
                                .font(MCOType.bodySmall)
                                .foregroundStyle(MCOTheme.Color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(timelineItems) { item in
                            ProductionMiniNote(
                                title: item.timestamp.nilIfBlank ?? item.title,
                                value: item.timelineBody
                            )
                        }
                    }
                    .padding(.top, MCOSpace.s)
                } label: {
                    HStack(alignment: .top, spacing: MCOSpace.s) {
                        Image(systemName: systemImage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MCOTheme.Color.brass)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                            Text(title)
                                .font(MCOType.tinyLabel)
                                .foregroundStyle(MCOTheme.Color.oxblood)
                            Text(subtitle)
                                .font(MCOType.caption)
                                .foregroundStyle(MCOTheme.Color.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .tint(MCOTheme.Color.oxblood)
            }
        }
    }
}

enum SceneTiming {
    static func windows(for scenes: [ShotScene]) -> [String] {
        var cursor = 0
        return scenes.map { scene in
            let start = cursor
            cursor += seconds(from: scene.duration) ?? 0
            return "\(timecode(start))-\(timecode(cursor))"
        }
    }

    static func totalSeconds(for scenes: [ShotScene]) -> Int? {
        let durations = scenes.compactMap { seconds(from: $0.duration) }
        guard durations.count == scenes.count else { return nil }
        return durations.reduce(0, +)
    }

    static func sceneTitle(for scenes: [ShotScene], index: Int) -> String? {
        guard let scene = scenes[safe: index] else { return nil }
        return "Scene \(String(format: "%02d", scene.number)): \(scene.title)"
    }

    private static func seconds(from duration: String) -> Int? {
        let digits = duration.prefix { $0.isNumber }
        return Int(digits)
    }

    private static func timecode(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension ProductionTimelineItem {
    var timelineTarget: String? {
        videoPortion?.nilIfBlank ?? placement?.nilIfBlank ?? shot?.nilIfBlank
    }

    var timelineBody: String {
        voiceover?.nilIfBlank
            ?? onScreenText?.nilIfBlank
            ?? detail.nilIfBlank
            ?? title.nilIfBlank
            ?? "Detail not specified."
    }
}

extension String {
    var containsTimestamp: Bool {
        range(of: #"(\d{1,2}:\d{2}|\d+\s?-\s?\d+\s?s|\d+\s?s)"#, options: .regularExpression) != nil
    }
}

struct ProductionMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(MCOType.tinyLabel)
                .foregroundStyle(MCOTheme.Color.inkMuted)
            Text(value.nilIfBlank ?? "Not set")
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, MCOSpace.s)
        .padding(.vertical, MCOSpace.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MCOTheme.Color.paper.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                .stroke(MCOTheme.Color.hairline, lineWidth: 1)
        }
    }
}

struct GeneratedDayMetadataGrid: View {
    let card: GeneratedDailyCardDraft

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                Text("Planning notes")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                GeneratedReadOnlyField(title: "CTA", value: card.cta)
                GeneratedReadOnlyField(title: "Hashtags", value: hashtagSummary)
                GeneratedReadOnlyField(title: "Cover", value: card.coverText)
                GeneratedReadOnlyField(title: "Post instructions", value: card.postInstructions)
                GeneratedReadOnlyField(title: "Audio notes", value: card.audioOptionNotes)
                GeneratedReadOnlyField(title: "Brand notes", value: card.brandEventNotes)
                GeneratedReadOnlyField(title: "Risk notes", value: card.riskNotes.joined(separator: "\n"))
                GeneratedReadOnlyField(title: "Assumptions", value: card.assumptions.joined(separator: "\n"))
                GeneratedReadOnlyField(title: "Source", value: card.sourceNote)
            }
        }
    }

    private var hashtagSummary: String {
        card.hashtags.map { "#\($0.trimmingCharacters(in: CharacterSet(charactersIn: "#")))" }
            .joined(separator: " ")
    }
}

struct GeneratedTextField: View {
    let title: String
    @Binding var text: String
    var lineLimit: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xs) {
            Text(title)
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.inkMuted)
            TextField(title, text: $text, axis: lineLimit > 1 ? .vertical : .horizontal)
                .font(MCOType.bodySmall)
                .foregroundStyle(MCOTheme.Color.ink)
                .lineLimit(lineLimit)
                .textFieldStyle(.plain)
                .padding(MCOSpace.s)
                .background(MCOTheme.Color.paperRaised.opacity(0.58))
                .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
        }
    }
}

struct GeneratedTextEditor: View {
    let title: String
    @Binding var text: String
    var minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xs) {
            Text(title)
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.inkMuted)
            TextEditor(text: $text)
                .font(MCOType.bodySmall)
                .foregroundStyle(MCOTheme.Color.ink)
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
                .padding(MCOSpace.xs)
                .background(MCOTheme.Color.paperRaised.opacity(0.58))
                .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
        }
    }
}

struct WeeklyReadinessStrip: View {
    let plan: WeeklyPlan
    var selectedFilter: WeeklyDayState? = nil
    var onSelect: ((WeeklyDayState) -> Void)? = nil

    var body: some View {
        HStack(spacing: MCOSpace.m) {
            ReadinessItem(
                systemImage: "checkmark.circle.fill",
                text: "\(plan.plannedDayCount) ready",
                color: MCOTheme.Color.success,
                isSelected: selectedFilter == .planned
            ) {
                onSelect?(.planned)
            }
            ReadinessItem(
                systemImage: "exclamationmark.triangle",
                text: "\(plan.backupDayCount) backup",
                color: MCOTheme.Color.warning,
                isSelected: selectedFilter == .backup
            ) {
                onSelect?(.backup)
            }
            ReadinessItem(
                systemImage: "circle.dashed",
                text: "\(plan.openDayCount) open",
                color: MCOTheme.Color.inkMuted,
                isSelected: selectedFilter == .open
            ) {
                onSelect?(.open)
            }
        }
        .padding(MCOSpace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MCOTheme.Color.paperRaised.opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous)
                .stroke(MCOTheme.Color.hairline, lineWidth: 1)
        }
        .accessibilityLabel(plan.computedReadinessLine)
    }
}

struct ReadinessItem: View {
    let systemImage: String
    let text: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MCOSpace.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? MCOTheme.Color.paperRaised : color)
                Text(text)
                    .font(MCOType.caption)
                    .foregroundStyle(isSelected ? MCOTheme.Color.paperRaised : MCOTheme.Color.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, MCOSpace.xs)
            .frame(height: 32)
            .background(isSelected ? color : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct WeeklyRhythmList: View {
    let days: [WeeklyDay]
    let generatedCard: (WeeklyDay) -> GeneratedDailyCardDraft?
    let onSelect: (WeeklyDay) -> Void
    let dayStatuses: [WeeklyDayGenerationStatus]
    let retryingDayDate: String?
    let onRetryDay: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(days) { day in
                let status = dayStatus(day)
                let isRetrying = retryingDayDate == day.scheduledDate || status?.isRetrying == true
                HStack(alignment: .center, spacing: 0) {
                    Button {
                        onSelect(day)
                    } label: {
                        WeeklyDayRow(
                            day: day,
                            generatedCard: generatedCard(day),
                            dayStatus: status,
                            isRetrying: isRetrying
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(day.weekday) \(day.title). \(day.state.label). Open planned content.")
                    .accessibilityIdentifier("weekly.day.\(day.weekday)")

                    if isRetrying {
                        ProgressView()
                            .controlSize(.small)
                            .tint(MCOTheme.Color.oxblood)
                            .frame(width: 44, height: 44)
                            .accessibilityLabel("\(day.weekday) generation retrying")
                    } else if status?.isFailed == true {
                        Button {
                            onRetryDay(day.scheduledDate ?? "")
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(MCOTheme.Color.oxblood)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Retry \(day.weekday) generation")
                        .accessibilityIdentifier("weekly.day.\(day.weekday).retry")
                        .disabled(retryingDayDate != nil)
                    }
                }
                Hairline()
            }
        }
    }

    private func dayStatus(_ day: WeeklyDay) -> WeeklyDayGenerationStatus? {
        dayStatuses.first {
            $0.scheduledDate == day.scheduledDate && ($0.isFailed || $0.isRetrying)
        }
    }
}

struct WeeklyDayRow: View {
    let day: WeeklyDay
    let generatedCard: GeneratedDailyCardDraft?
    let dayStatus: WeeklyDayGenerationStatus?
    let isRetrying: Bool

    var body: some View {
        HStack(alignment: .center, spacing: MCOSpace.m) {
            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text(day.weekday)
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .foregroundStyle(day.state.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(day.date)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
            .frame(width: 56, alignment: .leading)

            Rectangle()
                .fill(MCOTheme.Color.hairline)
                .frame(width: 1)
                .padding(.vertical, MCOSpace.xs)

            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                Text(day.title)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(day.state == .open ? MCOTheme.Color.inkMuted : MCOTheme.Color.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.92)
            }

            Spacer(minLength: MCOSpace.s)

            VStack(alignment: .trailing, spacing: MCOSpace.xs) {
                WeeklySourceTag(text: formatLabel, tone: .quiet)
                HStack(spacing: MCOSpace.xxs) {
                    Text(isRetrying ? "Retrying" : day.state.label)
                        .font(MCOType.caption)
                        .foregroundStyle(isRetrying ? MCOTheme.Color.oxblood : day.state.accent)
                        .accessibilityIdentifier("weekly.day.\(day.weekday).status.\(day.state.label.lowercased())")
                    if day.isSoftLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(MCOTheme.Color.brass)
                            .accessibilityLabel("Soft locked")
                    }
                }
            }
            .frame(width: 58, alignment: .trailing)
        }
        .padding(.vertical, MCOSpace.xs)
    }

    private var formatLabel: String {
        generatedCard?.format?.nilIfBlank ?? generatedCard?.primarySurface?.nilIfBlank ?? "Reel"
    }
}

struct ProductionDetailBlock: View {
    let title: String
    let systemImage: String
    let bodyText: String
    var lineLimit: Int? = nil

    var body: some View {
        if let text = bodyText.nilIfBlank {
            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                ProductionLabel(title: title, systemImage: systemImage)
                Text(text)
                    .font(MCOType.bodySmall)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineLimit(lineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ProductionSceneChecklist: View {
    let scenes: [ShotScene]
    var visibleLimit: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xs) {
            ProductionLabel(title: "Scenes to shoot", systemImage: "camera.viewfinder")

            VStack(spacing: MCOSpace.xs) {
                ForEach(visibleScenes) { scene in
                    HStack(alignment: .top, spacing: MCOSpace.s) {
                        Text("\(scene.number)")
                            .font(MCOType.caption)
                            .foregroundStyle(MCOTheme.Color.paperRaised)
                            .frame(width: 22, height: 22)
                            .background(MCOTheme.Color.sageDeep, in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(scene.title)
                                .font(MCOType.bodySmall)
                                .foregroundStyle(MCOTheme.Color.ink)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            if let duration = scene.duration.nilIfBlank {
                                Text(duration)
                                    .font(MCOType.caption)
                                    .foregroundStyle(MCOTheme.Color.inkMuted)
                            }
                        }

                        Spacer(minLength: MCOSpace.xs)

                        Image(systemName: scene.symbol.nilIfBlank ?? "video")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MCOTheme.Color.brass)
                            .frame(width: 20)
                    }
                    .padding(.vertical, MCOSpace.xxs)
                }

                if hiddenSceneCount > 0 {
                    Text("+ \(hiddenSceneCount) more scenes in review")
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var visibleScenes: [ShotScene] {
        if let visibleLimit {
            return Array(scenes.prefix(visibleLimit))
        }
        return scenes
    }

    private var hiddenSceneCount: Int {
        guard let visibleLimit else { return 0 }
        return max(0, scenes.count - visibleLimit)
    }
}

struct ProductionPillList: View {
    let title: String
    let systemImage: String
    let items: [String]
    var limit: Int = 4

    var body: some View {
        let visibleItems = items.compactMap(\.nilIfBlank).prefix(limit)
        if !visibleItems.isEmpty {
            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                ProductionLabel(title: title, systemImage: systemImage)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: MCOSpace.xs)], alignment: .leading, spacing: MCOSpace.xs) {
                    ForEach(Array(visibleItems), id: \.self) { item in
                        Text(item)
                            .font(MCOType.caption)
                            .foregroundStyle(MCOTheme.Color.ink)
                            .lineLimit(2)
                            .padding(.horizontal, MCOSpace.s)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(MCOTheme.Color.paper.opacity(0.78))
                            .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                                    .stroke(MCOTheme.Color.hairline, lineWidth: 1)
                            }
                    }
                }
            }
        }
    }
}

struct ProductionFooterNotes: View {
    let card: GeneratedDailyCardDraft

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xs) {
            HStack(spacing: MCOSpace.xs) {
                if let cta = card.cta.nilIfBlank {
                    ProductionMiniNote(title: "CTA", value: cta)
                }
                if let cover = card.coverText.nilIfBlank {
                    ProductionMiniNote(title: "Cover", value: cover)
                }
            }

            if let postInstructions = card.postInstructions.nilIfBlank {
                ProductionDetailBlock(
                    title: "Post instructions",
                    systemImage: "checklist",
                    bodyText: postInstructions,
                    lineLimit: 3
                )
            }
        }
    }
}

struct ProductionMiniNote: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(MCOType.tinyLabel)
                .foregroundStyle(MCOTheme.Color.oxblood)
            Text(value)
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MCOSpace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MCOTheme.Color.paper.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                .stroke(MCOTheme.Color.hairline, lineWidth: 1)
        }
    }
}

struct ProductionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: MCOSpace.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MCOTheme.Color.brass)
                .frame(width: 14)
            Text(title)
                .font(MCOType.tinyLabel)
                .foregroundStyle(MCOTheme.Color.oxblood)
                .textCase(.uppercase)
        }
    }
}

struct WeeklySourceTag: View {
    let text: String
    let tone: ChipTone

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(tone.foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, MCOSpace.xs)
            .padding(.vertical, 5)
            .background(tone.background)
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(tone.stroke, lineWidth: 1)
            }
    }
}

struct WeeklySectionTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xs) {
            Text(title)
                .font(.system(size: 26, weight: .regular, design: .serif))
                .foregroundStyle(MCOTheme.Color.ink)
            Text(subtitle)
                .font(MCOType.bodySmall)
                .foregroundStyle(MCOTheme.Color.inkMuted)
        }
        .padding(.top, MCOSpace.s)
    }
}

struct WeeklySectionHeader: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: MCOSpace.m) {
            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                Text(title)
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.ink)
                Text(subtitle)
                    .font(MCOType.bodySmall)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }

            Spacer(minLength: MCOSpace.s)

            Button(actionTitle, action: action)
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.oxblood)
                .buttonStyle(.plain)
        }
        .padding(.top, MCOSpace.s)
    }
}

struct WeeklySetupSummary: View {
    let sections: [WeeklySetupSection]
    var onEdit: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ForEach(sections) { section in
                if let onEdit {
                    Button(action: onEdit) {
                        WeeklySetupRow(section: section, showsChevron: true)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit \(section.title) weekly brief input")
                } else {
                    WeeklySetupRow(section: section, showsChevron: false)
                }
                Hairline()
            }
        }
    }
}

struct WeeklySetupRow: View {
    let section: WeeklySetupSection
    let showsChevron: Bool

    var body: some View {
        HStack(alignment: .center, spacing: MCOSpace.m) {
            Image(systemName: section.systemImage)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(MCOTheme.Color.brass)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text(section.title)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.ink)
                Text(section.summary)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: MCOSpace.s)
            StatusChip(text: section.state, tone: section.state == "Needs detail" ? .warning : .ready)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
        }
        .padding(.vertical, MCOSpace.s)
    }
}

struct WeeklyIdeaBank: View {
    let ideas: [WeeklyIdea]
    let targetDayLabel: String?
    let onSelect: (WeeklyIdea) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(deduplicatedIdeas) { idea in
                WeeklyIdeaRow(
                    idea: idea,
                    targetDayLabel: targetDayLabel,
                    onSelect: { onSelect(idea) }
                )
                Hairline()
            }
        }
    }

    private var deduplicatedIdeas: [WeeklyIdea] {
        var seen = Set<String>()
        var result: [WeeklyIdea] = []

        for idea in ideas {
            let key = [
                idea.title.normalizedIdeaBankKey,
                idea.reason.normalizedIdeaBankKey,
                idea.source.rawValue.normalizedIdeaBankKey,
                idea.effortLabel.normalizedIdeaBankKey,
                (idea.selectedDay ?? "").normalizedIdeaBankKey
            ].joined(separator: "|")

            guard seen.insert(key).inserted else {
                continue
            }

            result.append(idea)
        }

        return result
    }
}

private extension String {
    var normalizedIdeaBankKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }
}

struct WeeklyIdeaRow: View {
    let idea: WeeklyIdea
    let targetDayLabel: String?
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: MCOSpace.m) {
            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                Text(idea.title)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineLimit(2)
                Text(idea.reason)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .lineLimit(2)
                HStack(spacing: MCOSpace.xs) {
                    StatusChip(text: idea.source.rawValue, tone: .quiet)
                    Text(idea.effortLabel)
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.warning)
                }
            }

            Spacer(minLength: MCOSpace.s)

            if let selectedDay = idea.selectedDay {
                StatusChip(text: selectedDay, tone: .ready)
            } else {
                Button(action: onSelect) {
                    Text(targetDayLabel.map { "Use \($0)" } ?? "Use")
                        .font(MCOType.caption)
                        .foregroundStyle(targetDayLabel == nil ? MCOTheme.Color.inkMuted : MCOTheme.Color.oxblood)
                        .frame(width: 70, height: 34)
                        .background(MCOTheme.Color.paperRaised.opacity(0.82))
                        .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                                .stroke(MCOTheme.Color.hairline, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(targetDayLabel == nil)
            }
        }
        .padding(.vertical, MCOSpace.s)
    }
}

extension WeeklyDayState {
    var accent: Color {
        switch self {
        case .planned:
            MCOTheme.Color.success
        case .backup:
            MCOTheme.Color.warning
        case .open:
            MCOTheme.Color.inkMuted
        }
    }

    var sourceTone: ChipTone {
        switch self {
        case .planned:
            .ready
        case .backup:
            .warning
        case .open:
            .quiet
        }
    }
}

#Preview {
    WeeklyControlView()
        .environment(AppServices.preview)
        .environment(AppState())
}
