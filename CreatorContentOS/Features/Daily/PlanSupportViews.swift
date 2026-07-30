import SwiftUI

struct CreatorProfileEditorView: View {
    @Environment(AppServices.self) private var services
    @State private var positioning = ""
    @State private var voiceRulesText = ""
    @State private var contentPillarsText = ""
    @State private var captionStyle = ""
    @State private var noGoTopicsText = ""
    @State private var recurringFormatsText = ""
    @State private var didLoadDraft = false

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.l) {
            ActionFeedbackBanner(message: services.lastActionMessage, tone: .ready)
            if !canEditProfile {
                PlanSignalBlock(
                    title: "Editor access required",
                    value: "Only owner and editor sessions can update the creator profile.",
                    systemImage: "lock",
                    tone: .warning
                )
            }
            if let error = services.creatorProfileEditError {
                PlanSignalBlock(
                    title: "Profile save error",
                    value: error,
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                )
            }
            profileEditor
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
        let didSave = await services.updateCreatorProfileImmediately(normalizedUpdate)
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

private struct CreatorProfileTextEditor: View {
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

struct PlanSignalBlock: View {
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

private extension String {
    var trimmedForProfile: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
