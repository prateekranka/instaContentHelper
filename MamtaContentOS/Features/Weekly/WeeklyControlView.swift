import SwiftUI

struct WeeklyControlView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @State private var isReviewingInputs = false
    @State private var isReviewingGeneratedDraft = false

    var body: some View {
        EditorialScreen {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                header
                WeeklyReadinessStrip(plan: services.weeklyPlan)
                softLockStrip
                generationStrip
                WeeklyRhythmList(days: services.weeklyPlan.days)
                WeeklySectionTitle(title: "Weekly Brief", subtitle: "Inputs are shaped, not managed.")
                WeeklySetupSummary(sections: services.weeklyPlan.setupSections)
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
                    onSave: services.applyGeneratedDraft,
                    onPublish: { draft in
                        services.applyGeneratedDraft(draft)
                        services.publishCurrentWeek()
                    }
                )
            }
        }
        .onChange(of: services.latestGenerationSummary?.id) { _, generationID in
            if generationID != nil {
                isReviewingGeneratedDraft = true
            }
        }
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
        VStack(alignment: .leading, spacing: MCOSpace.m) {
            HStack(alignment: .top) {
                Text("MC")
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.brass)
                    .frame(width: 42, height: 42)
                    .background(MCOTheme.Color.paperRaised, in: Circle())
                    .overlay {
                        Circle().stroke(MCOTheme.Color.hairline, lineWidth: 1)
                    }
                Spacer()
                FloatingIconButton(systemImage: "ellipsis", label: "Back to Mamta Mode") {
                    appState.activeMode = .mamta
                }
            }

            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                Text(services.weeklyPlan.eyebrow)
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                Text(services.weeklyPlan.title)
                    .font(MCOType.display)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(services.weeklyPlan.weekRange)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
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
        } else {
            HStack(spacing: MCOSpace.s) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MCOTheme.Color.brass)
                Text("Review weekly inputs")
                    .font(MCOType.bodySmall)
                    .foregroundStyle(MCOTheme.Color.ink)
                Spacer()
                Button("Open") {
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
            Text("PRATEEK WEEKLY CONTROL")
                .font(MCOType.tinyLabel)
                .foregroundStyle(MCOTheme.Color.oxblood)
            Text("Review inputs")
                .font(MCOType.screenTitle)
                .foregroundStyle(MCOTheme.Color.ink)
            Text("Confirm the week is grounded before Mamta sees the daily cards.")
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

struct GeneratedWeekReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GeneratedWeekDraft
    let onSave: (GeneratedWeekDraft) -> Void
    let onPublish: (GeneratedWeekDraft) -> Void

    init(
        draft: GeneratedWeekDraft,
        onSave: @escaping (GeneratedWeekDraft) -> Void,
        onPublish: @escaping (GeneratedWeekDraft) -> Void
    ) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
        self.onPublish = onPublish
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
                            GeneratedDailyCardEditor(card: $card)
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
            Text("PRATEEK AI REVIEW")
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
    @State private var isInspectingGeneratedFields = false

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text(card.scheduledDate)
                        .font(MCOType.tinyLabel)
                        .foregroundStyle(MCOTheme.Color.oxblood)
                    Spacer()
                    Text("\(Int(card.mamtaFitScore.rounded())) fit")
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
                GeneratedCardInspectionBlock(
                    card: card,
                    isExpanded: $isInspectingGeneratedFields
                )
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

    var body: some View {
        VStack(spacing: 0) {
            ForEach(days) { day in
                WeeklyDayRow(day: day)
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
            ForEach(ideas) { idea in
                WeeklyIdeaRow(
                    idea: idea,
                    targetDayLabel: targetDayLabel,
                    onSelect: { onSelect(idea) }
                )
                Hairline()
            }
        }
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
