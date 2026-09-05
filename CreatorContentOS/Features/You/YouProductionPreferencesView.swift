import SwiftUI

struct YouProductionPreferencesView: View {
    @Environment(AppServices.self) private var services
    let backLabel: String
    let onBack: () -> Void

    @State private var selection = YouProductionSelection(
        formats: [],
        timeToCreate: nil,
        contentLanguage: "English",
        showFace: nil,
        useVoice: nil
    )
    @State private var didLoad = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        YouDestinationScaffold(
            title: "Content preferences",
            subtitle: "Formats, time, language, and on-camera comfort.",
            backLabel: backLabel,
            onBack: onBack
        ) {
            PocketSheetBlock(header: "Production setup") {
                VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
                    OnboardingProductionForm(
                        formats: Binding(
                            get: { selection.formats },
                            set: { selection.formats = $0; scheduleSave() }
                        ),
                        timeToCreate: Binding(
                            get: { selection.timeToCreate },
                            set: { selection.timeToCreate = $0; scheduleSave() }
                        ),
                        contentLanguage: Binding(
                            get: { selection.contentLanguage },
                            set: { selection.contentLanguage = $0; scheduleSave() }
                        ),
                        showFace: Binding(
                            get: { selection.showFace },
                            set: { selection.showFace = $0; scheduleSave() }
                        ),
                        useVoice: Binding(
                            get: { selection.useVoice },
                            set: { selection.useVoice = $0; scheduleSave() }
                        ),
                        identifierPrefix: "you.production"
                    )
                    .padding(.horizontal, PocketSheetSpace.m)
                    .padding(.top, PocketSheetSpace.s)

                    statusLine
                        .padding(.horizontal, PocketSheetSpace.m)
                        .padding(.bottom, PocketSheetSpace.s)
                }
            }
        }
        .accessibilityIdentifier("you.screen.production")
        .onAppear {
            guard !didLoad else { return }
            selection = YouProductionSelection.from(profile: services.creatorProfileSummary)
            didLoad = true
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if services.isSavingCreatorProfile {
            Text("Saving…")
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
        } else if let error = services.creatorProfileEditError {
            Text(error)
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.ink)
        } else {
            Text("Changes save automatically and shape future ideas.")
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        guard selection.isValid else { return }

        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await persistSelection()
        }
    }

    @MainActor
    private func persistSelection() async {
        guard selection.isValid else { return }
        let update = selection.profileUpdate(base: services.creatorProfileSummary)
        _ = await services.updateCreatorProfileImmediately(update)
    }
}
