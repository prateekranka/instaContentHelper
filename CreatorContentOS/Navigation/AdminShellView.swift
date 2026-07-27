import SwiftUI

struct AdminShellView: View {
    var body: some View {
        TabView {
            NavigationStack {
                DayGenerationView()
            }
            .tabItem { Label("Daily", systemImage: "calendar.badge.plus") }

            NavigationStack {
                IntelligenceHomeView()
            }
            .tabItem { Label("References", systemImage: "bookmark") }
        }
        .tint(MCOTheme.Color.oxblood)
    }
}

struct CreatorProfileAdminView: View {
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

    var body: some View {
        EditorialScreen(bottomContentPadding: MCOSpace.l, showsBottomBar: false) {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                header
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
        } bottomBar: {
            EmptyView()
        }
        .navigationBarHidden(true)
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
            SectionTitle(
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
            SectionTitle(
                title: "Approved Testers",
                subtitle: services.testers.isEmpty ? "No editor testers loaded." : "\(services.testers.count) editor testers"
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
