import SwiftUI

/// DEBUG / fixture-only Manager shell (Daily · Weekly · References).
///
/// Not reachable from the live Creator product path (`authenticationPhase == .live`
/// always hosts `CreatorShellView`). Open only via:
/// - `MCO_FORCE_FIXTURE_UI=1` + `MCO_FORCE_APP_MODE=admin`, or
/// - `MCO_FORCE_FIXTURE_UI=1` + `MCO_FORCE_SCREEN=admin`
///
/// Weekly Control’s publish-week / soft-lock ceremony lives here only — not in Creator UX.
struct AdminShellView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        TabView {
            NavigationStack {
                DayGenerationView()
            }
            .tabItem { Label("Daily", systemImage: "calendar.badge.plus") }

            NavigationStack {
                WeeklyControlView()
            }
            .tabItem { Label("Weekly", systemImage: "calendar") }

            NavigationStack {
                IntelligenceHomeView()
            }
            .tabItem { Label("References", systemImage: "bookmark") }
        }
        .tint(MCOTheme.Color.oxblood)
    }
}

struct CreatorProfileAdminView: View {
    enum Presentation {
        /// Full-screen admin push with back chrome.
        case standalone
        /// Nested under Plan accordion — fields only, no screen chrome.
        case embedded
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @State private var positioning = ""
    @State private var voiceRulesText = ""
    @State private var contentPillarsText = ""
    @State private var captionStyle = ""
    @State private var noGoTopicsText = ""
    @State private var recurringFormatsText = ""
    @State private var didLoadDraft = false
    var presentation: Presentation = .standalone

    var body: some View {
        Group {
            switch presentation {
            case .standalone:
                EditorialScreen(bottomContentPadding: MCOSpace.l, showsBottomBar: false) {
                    VStack(alignment: .leading, spacing: MCOSpace.l) {
                        header
                        profileBody
                    }
                } bottomBar: {
                    EmptyView()
                }
                .navigationBarHidden(true)
            case .embedded:
                VStack(alignment: .leading, spacing: MCOSpace.l) {
                    profileBody
                }
            }
        }
        .onAppear {
            if !didLoadDraft {
                loadDraft(from: services.creatorProfileSummary)
                didLoadDraft = true
            }
        }
        .onChange(of: services.creatorProfileSummary) { oldProfile, profile in
            if normalizedUpdate == CreatorProfileUpdate(summary: oldProfile) {
                loadDraft(from: profile)
            }
        }
    }

    @ViewBuilder
    private var profileBody: some View {
        ActionFeedbackBanner(message: services.lastActionMessage, tone: .ready)
        if !canEditProfile {
            AdminSignalBlock(
                title: "Editor access required",
                value: "Only owner and editor sessions can update the creator profile.",
                systemImage: "lock",
                tone: .warning
            )
        }
        if let error = services.creatorProfileEditError {
            AdminSignalBlock(
                title: "Profile save error",
                value: error,
                systemImage: "exclamationmark.triangle",
                tone: .warning
            )
        }
        profileEditor
    }

    private var canEditProfile: Bool {
        services.memberRole == "owner" || services.memberRole == "editor"
    }

    private var canSave: Bool {
        canEditProfile && isDirty && !services.isSavingCreatorProfile
    }

    private var isDirty: Bool {
        normalizedUpdate != CreatorProfileUpdate(summary: services.creatorProfileSummary)
    }

    private var normalizedUpdate: CreatorProfileUpdate {
        CreatorProfileUpdate(
            positioning: positioning.trimmedForProfile,
            voiceRules: lineValues(from: voiceRulesText),
            contentPillars: lineValues(from: contentPillarsText),
            captionStyle: captionStyle.trimmedForProfile,
            noGoTopics: lineValues(from: noGoTopicsText),
            recurringFormats: lineValues(from: recurringFormatsText)
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: MCOSpace.s) {
            Button {
                dismiss()
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
            .accessibilityLabel("Back")

            Text("Creator Profile")
                .font(MCOType.screenTitle)
                .foregroundStyle(MCOTheme.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: MCOSpace.s)

            Menu {
                Button {
                    appState.activeMode = .creator
                } label: {
                    Label("Creator mode", systemImage: "person.crop.circle")
                }

                Button {
                    services.refreshFromRepositories()
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
            .accessibilityLabel("Creator Profile options")
        }
    }

    private var profileEditor: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            creatorVoiceSection
            CreatorProfileTextEditor(
                title: "Content Pillars",
                systemImage: "square.grid.2x2",
                placeholder: "gym\nlifestyle\neating\nrecovery",
                text: $contentPillarsText
            )
            CreatorProfileTextEditor(
                title: "Recurring Formats",
                systemImage: "rectangle.stack",
                placeholder: "one practical detail\ncaption-only backup",
                text: $recurringFormatsText
            )
            saveProfileButton
        }
    }

    private var creatorVoiceSection: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            WeeklySectionTitle(
                title: "Creator voice",
                subtitle: "Shape how this creator sounds, feels, and never sounds."
            )

            JournalBlock {
                VStack(alignment: .leading, spacing: MCOSpace.xs) {
                    Label("Point of view", systemImage: "scope")
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                    TextField("Creator positioning", text: $positioning, axis: .vertical)
                        .font(MCOType.bodySmall)
                        .foregroundStyle(MCOTheme.Color.ink)
                        .lineLimit(2...8)
                        .padding(MCOSpace.m)
                        .background(MCOTheme.Color.paper.opacity(0.82))
                        .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                                .stroke(MCOTheme.Color.hairline, lineWidth: 1)
                        }
                }
            }
            .accessibilityLabel("Point of view, using positioning")

            CreatorProfileTextEditor(
                title: "Voice essence",
                systemImage: "quote.bubble",
                placeholder: "Warm\nPrecise\nLight Hinglish when natural",
                text: $voiceRulesText
            )

            CreatorProfileTextEditor(
                title: "Sounds like this creator",
                systemImage: "text.quote",
                placeholder: "Short, useful, and human.",
                text: $captionStyle,
                minimumLines: 2,
                maximumLines: 8
            )

            CreatorProfileTextEditor(
                title: "Never sounds like",
                systemImage: "nosign",
                placeholder: "Politics\nWeight talk\nNegativity",
                text: $noGoTopicsText
            )

            JournalBlock {
                VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                    Label("Identity context", systemImage: "person.text.rectangle")
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                    Text("Age or identity details should only be used when they add emotional weight or context, not in every post.")
                        .font(MCOType.bodySmall)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityLabel("Identity context rule, read-only")

            JournalBlock {
                VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                    Label("Writing test", systemImage: "pencil.and.scribble")
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                    Text("If another creator could say a line unchanged, rewrite it with this creator's lived detail, opinion, relationships, home context, or humour.")
                        .font(MCOType.bodySmall)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityLabel("Writing test rule, read-only")
        }
    }

    private var saveProfileButton: some View {
        PrimaryActionButton(
            title: saveButtonTitle,
            systemImage: services.isSavingCreatorProfile ? "hourglass" : "checkmark"
        ) {
            Task {
                await saveProfile()
            }
        }
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.52)
    }

    private var saveButtonTitle: String {
        if services.isSavingCreatorProfile {
            return "Saving"
        }

        return isDirty ? "Save profile" : "Saved"
    }

    private func loadDraft(from profile: CreatorProfileSummary) {
        positioning = profile.positioning
        voiceRulesText = profile.voiceRules.isEmpty ? profile.voiceLine : profile.voiceRules.joined(separator: "\n")
        contentPillarsText = profile.contentPillars.joined(separator: "\n")
        captionStyle = profile.captionStyle ?? ""
        noGoTopicsText = profile.noGoTopics.joined(separator: "\n")
        recurringFormatsText = profile.recurringFormats.joined(separator: "\n")
    }

    @MainActor
    private func saveProfile() async {
        let update = normalizedUpdate
        let didSave = await services.updateCreatorProfileImmediately(update)
        if didSave {
            loadDraft(from: services.creatorProfileSummary)
        }
    }

    private func lineValues(from text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmedForProfile }
            .filter { !$0.isEmpty }
    }
}

struct CreatorProfileTextEditor: View {
    let title: String
    let systemImage: String
    let placeholder: String
    @Binding var text: String
    var minimumLines: Int = 4
    var maximumLines: Int = 12

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                Label(title, systemImage: systemImage)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                TextField("", text: $text, axis: .vertical)
                    .font(MCOType.bodySmall)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineLimit(minimumLines...maximumLines)
                    .padding(MCOSpace.s)
                    .background(MCOTheme.Color.paper.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                            .stroke(MCOTheme.Color.hairline, lineWidth: 1)
                    }
                    .overlay(alignment: .topLeading) {
                        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(placeholder)
                                .font(MCOType.bodySmall)
                                .foregroundStyle(MCOTheme.Color.inkMuted)
                                .padding(MCOSpace.s)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }
}

private extension String {
    var trimmedForProfile: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// DEBUG-only (`MCO_FORCE_SCREEN=ai-runway`). Not part of the Creator product.
struct AIRunwayView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services

    var body: some View {
        EditorialScreen {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                header
                runwayGrid
                if let generationError = services.generationError {
                    AdminSignalBlock(
                        title: "Generation error",
                        value: generationError,
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                }
                latestDraftBlock
                contextBlock
                ideaBankBlock
            }
        } bottomBar: {
            GlassCommandBar {
                SecondaryActionButton(title: "Creator mode") {
                    appState.activeMode = .creator
                }
                .frame(maxWidth: 150)
            }
        }
        .navigationBarHidden(true)
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
                Text("AI Runway")
                    .font(MCOType.display)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(services.weeklyPlan.weekRange)
                    .font(MCOType.body)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
        }
    }

    private var runwayGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: MCOSpace.s),
                GridItem(.flexible(), spacing: MCOSpace.s),
            ],
            spacing: MCOSpace.s
        ) {
            AdminMetricTile(
                title: "Runtime",
                value: services.isLiveSupabaseRuntime ? "Live" : "Fixtures",
                detail: services.memberRole.capitalized,
                systemImage: services.isLiveSupabaseRuntime ? "dot.radiowaves.left.and.right" : "tray.full"
            )
            AdminMetricTile(
                title: "Week",
                value: services.weeklyPlan.isSoftLocked ? "Locked" : "Draft",
                detail: services.weeklyPlan.computedReadinessLine,
                systemImage: services.weeklyPlan.isSoftLocked ? "lock.fill" : "calendar.badge.clock"
            )
            AdminMetricTile(
                title: "Draft cards",
                value: "\(services.latestGenerationSummary?.dailyCards.count ?? services.weeklyPlan.days.count)",
                detail: generationStateLine,
                systemImage: "rectangle.stack"
            )
            AdminMetricTile(
                title: "Sources",
                value: "\(services.intelligenceHome.sourcePulse.references.count)",
                detail: services.intelligenceHome.sourcePulse.subtitle,
                systemImage: "sparkle.magnifyingglass"
            )
        }
    }

    private var generationStateLine: String {
        if let draft = services.latestGenerationSummary {
            draft.status.capitalized
        } else {
            "No run this session"
        }
    }

    private var latestDraftBlock: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            WeeklySectionTitle(
                title: "Latest Draft",
                subtitle: services.latestGenerationSummary?.generatedAt ?? "No generation has completed in this session."
            )

            if let draft = services.latestGenerationSummary {
                JournalBlock {
                    VStack(alignment: .leading, spacing: MCOSpace.m) {
                        Text(draft.strategySummary)
                            .font(MCOType.body)
                            .foregroundStyle(MCOTheme.Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        AdminProofRow(
                            icon: "calendar",
                            title: "Cards",
                            value: "\(draft.dailyCards.count) planned days"
                        )
                        AdminProofRow(
                            icon: "lightbulb",
                            title: "Ideas",
                            value: "\(draft.ideaBank.count) saved options"
                        )
                        AdminProofRow(
                            icon: "quote.bubble",
                            title: "Source",
                            value: draft.sourceSummary
                        )
                        if !draft.warnings.isEmpty {
                            AdminInlineList(title: "Warnings", values: draft.warnings, tone: .warning)
                        }
                        if !draft.assumptions.isEmpty {
                            AdminInlineList(title: "Assumptions", values: draft.assumptions, tone: .quiet)
                        }
                    }
                }
            } else {
                AdminSignalBlock(
                    title: "No draft loaded",
                    value: "Day-wise generation populates strategy, sources, warnings, and daily cards here when a draft exists.",
                    systemImage: "wand.and.stars",
                    tone: .quiet
                )
            }
        }
    }

    private var contextBlock: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            WeeklySectionTitle(title: "Input Context", subtitle: "Profile, setup, references, archive, and ideas.")
            JournalBlock {
                VStack(alignment: .leading, spacing: MCOSpace.s) {
                    AdminProofRow(
                        icon: "person.crop.circle.badge.checkmark",
                        title: "Creator",
                        value: services.creatorProfileSummary.displayName
                    )
                    AdminProofRow(
                        icon: "person.badge.key",
                        title: "Access",
                        value: services.memberRole.capitalized
                    )
                    ForEach(services.weeklyPlan.setupSections.prefix(4)) { section in
                        AdminProofRow(
                            icon: section.systemImage,
                            title: section.title,
                            value: "\(section.state): \(section.summary)"
                        )
                    }
                }
            }
        }
    }

    private var ideaBankBlock: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            WeeklySectionTitle(title: "Idea Queue", subtitle: "\(services.weeklyIdeas.count) options under this week.")
            JournalBlock {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(services.weeklyIdeas.prefix(4).enumerated()), id: \.element.id) { index, idea in
                        AdminIdeaRow(idea: idea)
                        if index < min(services.weeklyIdeas.count, 4) - 1 {
                            Hairline()
                        }
                    }
                }
            }
        }
    }
}

struct LiveQAView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services

    var body: some View {
        EditorialScreen {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                header
                ActionFeedbackBanner(message: services.lastActionMessage, tone: .ready)
                proofGrid
                todayBlock
                weekBlock
                repositoryBlock
            }
        } bottomBar: {
            GlassCommandBar {
                SecondaryActionButton(title: "Refresh") {
                    services.refreshFromRepositories()
                }
                .frame(maxWidth: 130)
                PrimaryActionButton(title: "Open Today", systemImage: "sun.max") {
                    appState.activeMode = .creator
                }
            }
        }
        .navigationBarHidden(true)
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
                Text("Live QA")
                    .font(MCOType.display)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text("Checks that live data is loading, writable, and safe to publish.")
                    .font(MCOType.body)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
        }
    }

    private var proofGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: MCOSpace.s),
                GridItem(.flexible(), spacing: MCOSpace.s),
            ],
            spacing: MCOSpace.s
        ) {
            AdminMetricTile(
                title: "Runtime",
                value: services.isLiveSupabaseRuntime ? "Live" : "Fixture",
                detail: services.context.workspaceID.uuidString.prefix(8).description,
                systemImage: "server.rack"
            )
            AdminMetricTile(
                title: "Today",
                value: services.todayCard.scheduledDate ?? "Loaded",
                detail: services.todayCard.title,
                systemImage: "sun.max"
            )
            AdminMetricTile(
                title: "Archive",
                value: "\(services.archiveEntries.count)",
                detail: "Recorded decisions",
                systemImage: "archivebox"
            )
            AdminMetricTile(
                title: "Publish",
                value: services.weeklyPlan.isSoftLocked ? "Locked" : "Draft",
                detail: services.lastPublishSummary ?? "No publish summary",
                systemImage: "paperplane"
            )
        }
    }

    private var todayBlock: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            WeeklySectionTitle(title: "Creator Today Card", subtitle: services.todayCard.context)
            JournalBlock {
                VStack(alignment: .leading, spacing: MCOSpace.m) {
                    Text(services.todayCard.title)
                        .font(MCOType.cardTitle)
                        .foregroundStyle(MCOTheme.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(services.todayCard.whyToday)
                        .font(MCOType.body)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    AdminProofRow(icon: "timer", title: "Effort", value: services.todayCard.effortLabel)
                    if let caption = services.todayCard.caption?.nilIfBlank {
                        AdminProofRow(icon: "text.quote", title: "Caption", value: caption)
                    }
                    if let backup = services.todayCard.backupStory?.nilIfBlank {
                        AdminProofRow(icon: "arrow.uturn.backward", title: "Backup", value: backup)
                    }
                }
            }
        }
    }

    private var weekBlock: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            WeeklySectionTitle(title: "Published Week Path", subtitle: services.weeklyPlan.weekRange)
            JournalBlock {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(services.weeklyPlan.days.prefix(7).enumerated()), id: \.element.id) { index, day in
                        AdminDayProofRow(day: day)
                        if index < min(services.weeklyPlan.days.count, 7) - 1 {
                            Hairline()
                        }
                    }
                }
            }
        }
    }

    private var repositoryBlock: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            WeeklySectionTitle(title: "Live data signals", subtitle: "Latest app-side sync state.")
            JournalBlock {
                VStack(alignment: .leading, spacing: MCOSpace.s) {
                    AdminProofRow(
                        icon: services.lastRepositoryError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle",
                        title: "Repository",
                        value: services.lastRepositoryError ?? "No sync error"
                    )
                    AdminProofRow(
                        icon: services.generationError == nil ? "checkmark.seal.fill" : "exclamationmark.triangle",
                        title: "Generation",
                        value: services.generationError ?? "Ready"
                    )
                    AdminProofRow(
                        icon: "key.horizontal",
                        title: "AI boundary",
                        value: "Edge Function only"
                    )
                    if let schedule = services.lastNotificationSchedule {
                        AdminProofRow(
                            icon: "bell.badge",
                            title: "Reminder",
                            value: "\(schedule.scheduledDate) at \(schedule.hour):\(paddedMinute(schedule.minute)) for \(schedule.title)"
                        )
                    }
                }
            }
        }
    }

    private func paddedMinute(_ minute: Int) -> String {
        minute < 10 ? "0\(minute)" : "\(minute)"
    }
}

/// DEBUG-only (`MCO_FORCE_SCREEN=tester-access`). OTP allowlist UI is not a product path.
struct TesterAccessView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @State private var email = ""
    @State private var displayName = ""

    var body: some View {
        EditorialScreen {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                header
                inviteBlock
                statusBlock
                testerList
            }
        } bottomBar: {
            GlassCommandBar {
                SecondaryActionButton(title: "Creator mode") {
                    appState.activeMode = .creator
                }
                .frame(maxWidth: 145)
                PrimaryActionButton(
                    title: services.isLoadingTesters ? "Checking" : "Refresh",
                    systemImage: "arrow.clockwise"
                ) {
                    services.loadTesterAccess()
                }
                .disabled(!services.canManageTesterAccess || services.isLoadingTesters)
            }
        }
        .navigationBarHidden(true)
        .task {
            services.loadTesterAccess()
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
                Text("Testers")
                    .font(MCOType.display)
                    .foregroundStyle(MCOTheme.Color.ink)
                Text("Approve email OTP access for people testing Creator's live workspace.")
                    .font(MCOType.body)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var inviteBlock: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                Text("Invite tester")
                    .font(MCOType.headline)
                    .foregroundStyle(MCOTheme.Color.ink)
                TextField("approved@example.com", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .padding(.horizontal, MCOSpace.m)
                    .frame(minHeight: 50)
                    .background(MCOTheme.Color.paperRaised.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                TextField("Display name", text: $displayName)
                    .padding(.horizontal, MCOSpace.m)
                    .frame(minHeight: 50)
                    .background(MCOTheme.Color.paperRaised.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                PrimaryActionButton(
                    title: "Send email code",
                    systemImage: "paperplane"
                ) {
                    services.inviteTester(email: email, displayName: displayName.nilIfBlank)
                    email = ""
                    displayName = ""
                }
                .disabled(!services.canManageTesterAccess || services.isLoadingTesters || email.nilIfBlank == nil)
            }
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            if !services.canManageTesterAccess {
                AdminSignalBlock(
                    title: "Owner access required",
                    value: "Only owner sessions can invite, resend, or revoke tester access.",
                    systemImage: "lock",
                    tone: .warning
                )
            }
            if let message = services.testerAccessMessage {
                AdminSignalBlock(
                    title: "Tester access",
                    value: message,
                    systemImage: "checkmark.circle.fill",
                    tone: .ready
                )
            }
            if let error = services.testerAccessError {
                AdminSignalBlock(
                    title: "Tester access error",
                    value: error,
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                )
            }
        }
    }

    private var testerList: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            WeeklySectionTitle(
                title: "Approved Testers",
                subtitle: services.testers.isEmpty ? "No editor testers loaded." : "(services.testers.count) editor testers"
            )
            JournalBlock {
                VStack(alignment: .leading, spacing: 0) {
                    if services.testers.isEmpty {
                        Text("Refresh to load approved tester emails from Supabase.")
                            .font(MCOType.bodySmall)
                            .foregroundStyle(MCOTheme.Color.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(Array(services.testers.enumerated()), id: \.element.id) { index, tester in
                            TesterAccessRow(tester: tester)
                            if index < services.testers.count - 1 {
                                Hairline()
                            }
                        }
                    }
                }
            }
        }
    }
}

struct TesterAccessRow: View {
    @Environment(AppServices.self) private var services
    let tester: TesterAccessRecord

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            HStack(alignment: .top, spacing: MCOSpace.s) {
                VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                    Text(tester.displayName?.nilIfBlank ?? tester.email)
                        .font(.system(size: 16, weight: .regular, design: .serif))
                        .foregroundStyle(MCOTheme.Color.ink)
                    Text(tester.email)
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                Spacer(minLength: 0)
                StatusChip(
                    text: tester.status.capitalized,
                    tone: tester.status == "active" ? .ready : .warning
                )
            }
            HStack(spacing: MCOSpace.s) {
                SecondaryActionButton(title: "Resend code") {
                    services.resendTesterOTP(email: tester.email)
                }
                .disabled(!services.canManageTesterAccess || services.isLoadingTesters || tester.status != "active")
                SecondaryActionButton(title: "Revoke") {
                    services.revokeTester(memberID: tester.id)
                }
                .disabled(!services.canManageTesterAccess || services.isLoadingTesters || tester.status != "active")
            }
        }
        .padding(.vertical, MCOSpace.s)
    }
}

struct AdminMetricTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MCOTheme.Color.oxblood)
                    .frame(width: 28, height: 28, alignment: .leading)
                VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                    Text(title.uppercased())
                        .font(MCOType.tinyLabel)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                    Text(value)
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .foregroundStyle(MCOTheme.Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(detail)
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        }
    }
}

struct AdminSignalBlock: View {
    let title: String
    let value: String
    let systemImage: String
    let tone: ChipTone

    var body: some View {
        JournalBlock {
            HStack(alignment: .top, spacing: MCOSpace.s) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tone.foreground)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                    Text(title)
                        .font(MCOType.headline)
                        .foregroundStyle(MCOTheme.Color.ink)
                    Text(value)
                        .font(MCOType.bodySmall)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct AdminProofRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: MCOSpace.s) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MCOTheme.Color.sageDeep)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                Text(value)
                    .font(MCOType.bodySmall)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

struct AdminInlineList: View {
    let title: String
    let values: [String]
    let tone: ChipTone

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xs) {
            StatusChip(text: title, tone: tone)
            ForEach(values.prefix(3), id: \.self) { value in
                Text(value)
                    .font(MCOType.bodySmall)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct AdminIdeaRow: View {
    let idea: WeeklyIdea

    var body: some View {
        HStack(alignment: .top, spacing: MCOSpace.s) {
            StatusChip(text: idea.source.rawValue, tone: .quiet)
                .frame(width: 86, alignment: .leading)
            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text(idea.title)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.ink)
                Text(idea.reason)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, MCOSpace.s)
    }
}

struct AdminDayProofRow: View {
    let day: WeeklyDay

    var body: some View {
        HStack(alignment: .center, spacing: MCOSpace.s) {
            VStack(alignment: .leading, spacing: 0) {
                Text(day.weekday)
                    .font(.system(size: 19, weight: .regular, design: .serif))
                    .foregroundStyle(day.state == .open ? MCOTheme.Color.brass : MCOTheme.Color.sageDeep)
                Text(day.date)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
            .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text(day.title)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.ink)
                Text(day.reason)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: MCOSpace.s)
            StatusChip(text: day.state.label, tone: day.state.sourceTone)
        }
        .padding(.vertical, MCOSpace.s)
    }
}

struct AdminPlaceholderScreen: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        ZStack {
            MCOTheme.Color.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                Text("Manager Weekly Control")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                Text(title)
                    .font(MCOType.screenTitle)
                    .foregroundStyle(MCOTheme.Color.ink)
                Text(subtitle)
                    .font(MCOType.body)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                SecondaryActionButton(title: actionTitle, action: action)
            }
            .padding(MCOSpace.l)
        }
    }
}
