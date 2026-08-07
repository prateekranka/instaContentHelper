import SwiftUI

enum YouCreatorVoiceSavePolicy {
    static func canSave(
        isDirty: Bool,
        isSaving: Bool,
        canEdit: Bool,
        positioning: String,
        voiceRulesText: String,
        voiceDeferred: Bool
    ) -> Bool {
        guard canEdit, isDirty, !isSaving else { return false }
        if voiceDeferred { return true }
        return !positioning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !lineValues(from: voiceRulesText).isEmpty
    }

    private static func lineValues(from text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct YouCreatorVoiceView: View {
    @Environment(AppServices.self) private var services
    let backLabel: String
    let onBack: () -> Void

    private let onboardingStore: any OnboardingStoring

    @State private var positioning = ""
    @State private var voiceRulesText = ""
    @State private var recurringFormatsText = ""
    @State private var captionStyle = ""
    @State private var noGoTopicsText = ""
    @State private var didLoadDraft = false

    init(
        backLabel: String,
        onBack: @escaping () -> Void,
        onboardingStore: any OnboardingStoring = UserDefaultsOnboardingStore()
    ) {
        self.backLabel = backLabel
        self.onBack = onBack
        self.onboardingStore = onboardingStore
    }

    var body: some View {
        YouDestinationScaffold(
            title: "Creator voice",
            subtitle: voiceSubtitle,
            backLabel: backLabel,
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
                if let error = services.creatorProfileEditError {
                    Text(error)
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                }

                PocketSheetBlock(header: "Saved voice") {
                    VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
                        voiceField(
                            title: "Positioning",
                            requirement: voiceIsDeferred ? "Optional" : "Required",
                            hint: voiceIsDeferred
                                ? "Who you are on camera — add when you're ready"
                                : "Who you are on camera — tone and audience",
                            text: $positioning,
                            identifier: "you.voice.positioning"
                        )
                        voiceField(
                            title: "Voice rules",
                            requirement: voiceIsDeferred ? "Optional" : "Required",
                            hint: voiceIsDeferred
                                ? "Pacing, words to avoid, habits — skip for now if you prefer"
                                : "Hard rules — pacing, words to avoid, habits",
                            text: $voiceRulesText,
                            identifier: "you.voice.rules"
                        )
                        voiceField(
                            title: "Pillars",
                            requirement: "Optional",
                            hint: "Themes you rotate",
                            text: $recurringFormatsText,
                            identifier: "you.voice.pillars"
                        )
                        voiceField(
                            title: "Caption style",
                            requirement: "Optional",
                            hint: "How captions should sound",
                            text: $captionStyle,
                            identifier: "you.voice.captionStyle"
                        )
                        voiceField(
                            title: "Never sounds like",
                            requirement: "Optional",
                            hint: "Topics and tones to avoid",
                            text: $noGoTopicsText,
                            identifier: "you.voice.noGo"
                        )
                    }
                    .padding(PocketSheetSpace.m)
                }

                PocketSheetPrimaryAction(
                    title: services.isSavingCreatorProfile ? "Saving" : "Save voice",
                    systemImage: services.isSavingCreatorProfile ? "hourglass" : "checkmark"
                ) {
                    Task { await saveVoice() }
                }
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.52)
                .accessibilityIdentifier("you.voice.save")
            }
        }
        .accessibilityIdentifier("you.screen.voice")
        .onAppear {
            guard !didLoadDraft else { return }
            loadDraft(from: services.creatorProfileSummary)
            didLoadDraft = true
        }
        .onChange(of: services.creatorProfileSummary) { oldProfile, profile in
            if normalizedUpdate == CreatorProfileUpdate(summary: oldProfile) {
                loadDraft(from: profile)
            }
        }
    }

    private var voiceIsDeferred: Bool {
        onboardingStore.loadCompletedData()?.voiceDeferred == true
    }

    private var voiceSubtitle: String {
        if voiceIsDeferred {
            return "Optional for now — drafts still work, but voice helps them sound like you."
        }
        return "Set the tone, rules, and point of view your drafts should follow."
    }

    private var canSave: Bool {
        YouCreatorVoiceSavePolicy.canSave(
            isDirty: isDirty,
            isSaving: services.isSavingCreatorProfile,
            canEdit: canEditProfile,
            positioning: positioning,
            voiceRulesText: voiceRulesText,
            voiceDeferred: voiceIsDeferred
        )
    }

    private var canEditProfile: Bool {
        services.memberRole == "owner" || services.memberRole == "editor" || !services.isLiveSupabaseRuntime
    }

    private var isDirty: Bool {
        normalizedUpdate != CreatorProfileUpdate(summary: services.creatorProfileSummary)
    }

    private var normalizedUpdate: CreatorProfileUpdate {
        let profile = services.creatorProfileSummary
        return CreatorProfileUpdate(
            positioning: positioning.trimmedForYouProfile,
            voiceRules: lineValues(from: voiceRulesText),
            contentPillars: profile.contentPillars,
            captionStyle: captionStyle.trimmedForYouProfile,
            noGoTopics: lineValues(from: noGoTopicsText),
            recurringFormats: lineValues(from: recurringFormatsText)
        )
    }

    @ViewBuilder
    private func voiceField(
        title: String,
        requirement: String,
        hint: String,
        text: Binding<String>,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
            HStack(spacing: PocketSheetSpace.xs) {
                Text(title)
                    .font(PocketSheetType.rowTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                Text(requirement)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }
            Text(hint)
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            TextField("", text: text, axis: .vertical)
                .font(PocketSheetType.rowTitle)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .lineLimit(4...12)
                .padding(PocketSheetSpace.s)
                .background(PocketSheetTheme.Color.paper)
                .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                        .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                }
                .accessibilityIdentifier(identifier)
        }
    }

    private func loadDraft(from profile: CreatorProfileSummary) {
        positioning = profile.positioning
        voiceRulesText = profile.voiceRules.isEmpty ? profile.voiceLine : profile.voiceRules.joined(separator: "\n")
        recurringFormatsText = profile.recurringFormats.joined(separator: "\n")
        captionStyle = profile.captionStyle ?? ""
        noGoTopicsText = profile.noGoTopics.joined(separator: "\n")
    }

    @MainActor
    private func saveVoice() async {
        _ = await services.updateCreatorProfileImmediately(normalizedUpdate)
        loadDraft(from: services.creatorProfileSummary)
    }

    private func lineValues(from text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmedForYouProfile }
            .filter { !$0.isEmpty }
    }
}

private extension String {
    var trimmedForYouProfile: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
