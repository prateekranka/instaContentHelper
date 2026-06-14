import SwiftUI

struct WeeklyControlView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @State private var isReviewingInputs = false
    @State private var isReviewingGeneratedDraft = false
    @State private var isEditingWeeklyBrief = false
    @State private var dayDetailSelection: WeeklyDayDetailSelection?

    var body: some View {
        EditorialScreen {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                header
                WeeklyReadinessStrip(plan: services.weeklyPlan)
                generationStrip
                WeeklySectionHeader(
                    title: "Weekly Brief",
                    subtitle: "Inputs are shaped, not managed.",
                    actionTitle: "Edit brief"
                ) {
                    isEditingWeeklyBrief = true
                }
                WeeklySetupSummary(sections: services.weeklyPlan.setupSections)
                WeeklyRhythmList(days: services.weeklyPlan.days) { day in
                    dayDetailSelection = makeDayDetailSelection(for: day.id)
                }
                WeeklySectionTitle(title: "Idea Bank", subtitle: "Prepared options underneath the week.")
                WeeklyIdeaBank(
                    ideas: services.weeklyIdeas,
                    targetDayLabel: services.nextOpenWeeklyDay?.weekday,
                    onSelect: services.selectIdeaForNextOpenDay
                )
            }
        } bottomBar: {
            GlassCommandBar {
                SecondaryActionButton(title: generateButtonTitle) {
                    services.generateCurrentWeek()
                }
                    .frame(maxWidth: 154)
                    .disabled(!services.canGenerateWeek)
                PrimaryActionButton(
                    title: publishButtonTitle,
                    systemImage: services.weeklyPlan.isSoftLocked ? "lock.fill" : "paperplane"
                ) {
                    services.publishCurrentWeek()
                }
                .disabled(services.isPublishingWeek || services.weeklyPlan.isSoftLocked)
            }
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
        .sheet(isPresented: $isEditingWeeklyBrief) {
            WeeklyBriefEditSheet(
                sections: services.weeklyPlan.setupSections,
                isSaving: services.isSavingWeeklyBrief,
                errorMessage: services.weeklyBriefEditError,
                onSave: services.updateWeeklySetupSectionsImmediately
            )
        }
        .sheet(item: $dayDetailSelection) { selection in
            WeeklyDayDetailSheet(
                day: selection.day,
                generatedCard: selection.generatedCard,
                isLocked: services.weeklyPlan.isSoftLocked || selection.day.isSoftLocked,
                canRegenerateDay: canRegenerateDay,
                onSetState: { state in
                    services.updateWeeklyDayState(dayID: selection.id, state: state)
                },
                onRegenerateDay: services.regeneratedDailyCard
            )
        }
        .onChange(of: services.latestGenerationSummary?.id) { _, generationID in
            if generationID != nil {
                isReviewingGeneratedDraft = true
            }
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
            "Generating"
        } else if services.latestGenerationSummary == nil {
            "Generate week"
        } else {
            "Regenerate"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            HStack {
                Spacer()
                FloatingIconButton(systemImage: "ellipsis", label: "Back to Creator Mode") {
                    appState.activeMode = .creator
                }
            }

            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                Text(services.weeklyPlan.title)
                    .font(MCOType.display)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                WeekDateRangeSelector(
                    startDate: selectedWeekStartDate,
                    endDate: selectedWeekEndDate,
                    isDisabled: services.weeklyPlan.isSoftLocked,
                    onChange: services.updateWeeklyDateWindow
                )
            }
        }
    }

    private var selectedWeekStartDate: String {
        services.weeklyPlan.weekStartDate
            ?? services.weeklyPlan.days.compactMap(\.scheduledDate).first
            ?? SupabaseDateFormatting.todayDateString()
    }

    private var selectedWeekEndDate: String {
        let fallbackEndDate = services.weeklyPlan.days.compactMap(\.scheduledDate).last
            ?? SupabaseDateFormatting.weekEndDate(starting: selectedWeekStartDate)
        return SupabaseDateFormatting.constrainedWeekEndDate(
            starting: selectedWeekStartDate,
            requestedEndDate: services.weeklyPlan.weekEndDate ?? fallbackEndDate
        )
    }

    private func makeDayDetailSelection(for dayID: UUID) -> WeeklyDayDetailSelection? {
        guard let day = services.weeklyPlan.days.first(where: { $0.id == dayID }) else {
            return nil
        }

        return WeeklyDayDetailSelection(
            day: day,
            generatedCard: services.generatedDailyCard(for: dayID)
        )
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
    private var generationStrip: some View {
        if let draft = services.latestGenerationSummary {
            HStack(alignment: .center, spacing: MCOSpace.s) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MCOTheme.Color.brass)
                VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                    Text("Generated draft ready")
                        .font(MCOType.bodySmall)
                        .foregroundStyle(MCOTheme.Color.ink)
                    Text(draft.strategySummary)
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                        .lineLimit(2)
                }
                Spacer(minLength: MCOSpace.s)
                Button {
                    isReviewingGeneratedDraft = true
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .foregroundStyle(MCOTheme.Color.oxblood)
                .accessibilityLabel("Review generated draft")
            }
            .padding(.horizontal, MCOSpace.m)
            .padding(.vertical, MCOSpace.s)
            .background(MCOTheme.Color.paperRaised.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous)
                    .stroke(MCOTheme.Color.hairline, lineWidth: 1)
            }
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
        }
    }
}

struct WeekDateRangeSelector: View {
    let startDate: String
    let endDate: String
    let isDisabled: Bool
    let onChange: (_ startDate: String, _ endDate: String) -> Void

    private var startOptions: [String] {
        SupabaseDateFormatting.dateOptions(
            around: startDate,
            daysBefore: 21,
            daysAfter: 42
        )
    }

    private var endOptions: [String] {
        SupabaseDateFormatting.dateOptions(starting: startDate, dayCount: 7)
    }

    var body: some View {
        HStack(spacing: MCOSpace.xs) {
            Menu {
                ForEach(startOptions, id: \.self) { date in
                    Button {
                        let nextEndDate = SupabaseDateFormatting.constrainedWeekEndDate(
                            starting: date,
                            requestedEndDate: endDate
                        )
                        onChange(date, nextEndDate)
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

            Text("-")
                .font(.system(size: 16, weight: .regular, design: .serif))
                .foregroundStyle(MCOTheme.Color.inkMuted)

            Menu {
                ForEach(endOptions, id: \.self) { date in
                    Button {
                        onChange(startDate, date)
                    } label: {
                        dateMenuLabel(
                            date: date,
                            isSelected: date == endDate
                        )
                    }
                }
            } label: {
                dateChip(title: SupabaseDateFormatting.displayDate(for: endDate))
            }
            .disabled(isDisabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Week range \(SupabaseDateFormatting.dateRange(starting: startDate, ending: endDate))")
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
                }
            }
            .safeAreaInset(edge: .bottom) {
                GlassCommandBar {
                    SecondaryActionButton(title: "Save edits") {
                        onSave(draft)
                    }
                    PrimaryActionButton(title: "Publish draft", systemImage: "paperplane") {
                        onPublish(draft)
                        dismiss()
                    }
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
    let onSetState: (WeeklyDayState) -> Void
    let onRegenerateDay: RegenerateDayAction?
    @State private var preserveManualEdits = true
    @State private var isRegenerating = false
    @State private var regenerationError: String?

    init(
        day: WeeklyDay,
        generatedCard: GeneratedDailyCardDraft?,
        isLocked: Bool,
        canRegenerateDay: Bool = false,
        onSetState: @escaping (WeeklyDayState) -> Void,
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
                        plannedContent
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
                        isDisabled: isLocked
                    ) {
                        onSetState(.planned)
                        dismiss()
                    }
                    WeeklyDayStateActionButton(
                        state: .backup,
                        selectedState: day.state,
                        isDisabled: isLocked
                    ) {
                        onSetState(.backup)
                        dismiss()
                    }
                    WeeklyDayStateActionButton(
                        state: .open,
                        selectedState: day.state,
                        isDisabled: isLocked
                    ) {
                        onSetState(.open)
                        dismiss()
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
            GenerationSummaryBlock(title: "Why today", bodyText: card.whyToday)
            GenerationSummaryBlock(title: "Shootability", bodyText: effortSummary)
            if !sceneLines.isEmpty {
                GenerationBulletBlock(title: "Scene list", items: sceneLines)
            }
            GenerationSummaryBlock(title: "Script", bodyText: card.script)
            GenerationSummaryBlock(title: "Caption", bodyText: card.caption)
            if !card.onScreenText.isEmpty {
                GenerationBulletBlock(title: "On-screen text", items: card.onScreenText)
            }
            GenerationSummaryBlock(title: "Backup story", bodyText: card.backupStory)
            GenerationSummaryBlock(title: "Caption-only backup", bodyText: card.backupCaptionOnly)
            GeneratedDayMetadataGrid(card: card)
        }
    }

    private var effortSummary: String {
        "\(card.shootability) / \(card.estimatedShootMinutes) min / \(card.energyRequired) / \(card.languageMode)"
    }

    private var sceneLines: [String] {
        card.sceneList.map { scene in
            "\(scene.number). \(scene.title) (\(scene.duration))"
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

    var body: some View {
        HStack(spacing: MCOSpace.m) {
            ReadinessItem(
                systemImage: "checkmark.circle.fill",
                text: "\(plan.plannedDayCount) ready",
                color: MCOTheme.Color.sageDeep
            )
            ReadinessItem(
                systemImage: "exclamationmark.triangle",
                text: "\(plan.backupDayCount) backup",
                color: MCOTheme.Color.brass
            )
            ReadinessItem(
                systemImage: "circle.dashed",
                text: "\(plan.openDayCount) open",
                color: MCOTheme.Color.inkMuted
            )
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

    var body: some View {
        HStack(spacing: MCOSpace.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(color)
            Text(text)
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.ink)
                .lineLimit(1)
        }
    }
}

struct WeeklyRhythmList: View {
    let days: [WeeklyDay]
    let onSelect: (WeeklyDay) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(days) { day in
                Button {
                    onSelect(day)
                } label: {
                    WeeklyDayRow(day: day)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(day.weekday) \(day.title). \(day.state.label). Open planned content.")
                Hairline()
            }
        }
    }
}

struct WeeklyDayRow: View {
    let day: WeeklyDay

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
                Text(day.reason)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: MCOSpace.s)

            VStack(alignment: .trailing, spacing: MCOSpace.xs) {
                WeeklySourceTag(text: day.source.rawValue, tone: day.state.sourceTone)
                HStack(spacing: MCOSpace.xxs) {
                    Text(day.state.label)
                        .font(MCOType.caption)
                        .foregroundStyle(day.state.accent)
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

    var body: some View {
        VStack(spacing: 0) {
            ForEach(sections) { section in
                WeeklySetupRow(section: section)
                Hairline()
            }
        }
    }
}

struct WeeklySetupRow: View {
    let section: WeeklySetupSection

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
                        .foregroundStyle(MCOTheme.Color.brass)
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
            MCOTheme.Color.sageDeep
        case .backup:
            MCOTheme.Color.brass
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
