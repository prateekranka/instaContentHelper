import SwiftUI

struct YouContentCategoriesView: View {
    @Environment(AppServices.self) private var services
    let backLabel: String
    let onBack: () -> Void

    @State private var selection = ContentCategorySelection(selectedIDs: [], customOtherLabel: "")
    @State private var didLoad = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        YouDestinationScaffold(
            title: "Content categories",
            subtitle: "Choose the topics that should shape your daily ideas.",
            backLabel: backLabel,
            onBack: onBack
        ) {
            PocketSheetBlock(header: "Saved categories") {
                VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
                    Text("Pick 1–3 categories. They guide the angles and topics in Plan.")
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, PocketSheetSpace.m)
                        .padding(.top, PocketSheetSpace.s)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 112), spacing: PocketSheetSpace.s)],
                        spacing: PocketSheetSpace.s
                    ) {
                        ForEach(ContentCategoryOption.catalog) { option in
                            categoryChip(option)
                        }
                    }
                    .padding(.horizontal, PocketSheetSpace.m)

                    if selection.includesOther {
                        TextField(
                            "Your category…",
                            text: $selection.customOtherLabel
                        )
                        .font(PocketSheetType.rowTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .padding(PocketSheetSpace.m)
                        .background(PocketSheetTheme.Color.paper)
                        .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                                .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                        }
                        .padding(.horizontal, PocketSheetSpace.m)
                        .accessibilityIdentifier("you.categories.otherInput")
                        .onChange(of: selection.customOtherLabel) { _, _ in
                            scheduleSave()
                        }
                    }

                    statusLine
                        .padding(.horizontal, PocketSheetSpace.m)
                        .padding(.bottom, PocketSheetSpace.s)
                }
            }
        }
        .accessibilityIdentifier("you.screen.categories")
        .onAppear {
            guard !didLoad else { return }
            selection = ContentCategorySelection.from(
                contentPillars: services.creatorProfileSummary.contentPillars
            )
            didLoad = true
        }
        .onChange(of: services.creatorProfileSummary.contentPillars) { _, pillars in
            let incoming = ContentCategorySelection.from(contentPillars: pillars)
            if incoming.resolvedContentPillars() == selection.resolvedContentPillars() {
                return
            }
            selection = incoming
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

    private func categoryChip(_ option: ContentCategoryOption) -> some View {
        let isSelected = selection.selectedIDs.contains(option.id)
        let isDisabled = !isSelected && selection.selectedIDs.count >= ContentCategorySelection.maxSelectionCount

        return Button {
            selection.toggle(option.id)
            scheduleSave()
        } label: {
            Text(option.label)
                .font(PocketSheetType.chip)
                .foregroundStyle(isSelected ? PocketSheetTheme.Color.inversePaper : PocketSheetTheme.Color.ink)
                .padding(.horizontal, PocketSheetSpace.m)
                .padding(.vertical, PocketSheetSpace.s)
                .frame(maxWidth: .infinity)
                .background(
                    isSelected ? PocketSheetTheme.Color.inverseInk : PocketSheetTheme.Color.paperRaised,
                    in: Capsule()
                )
                .overlay {
                    Capsule().stroke(PocketSheetTheme.Color.hairline, lineWidth: isSelected ? 0 : 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .accessibilityIdentifier("you.categories.chip.\(option.id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

        let profile = services.creatorProfileSummary
        let update = CreatorProfileUpdate(
            positioning: profile.positioning,
            voiceRules: profile.voiceRules.isEmpty
                ? [profile.voiceLine].compactMap(\.nilIfBlank)
                : profile.voiceRules,
            contentPillars: selection.resolvedContentPillars(),
            captionStyle: profile.captionStyle ?? "",
            noGoTopics: profile.noGoTopics,
            recurringFormats: profile.recurringFormats
        )

        _ = await services.updateCreatorProfileImmediately(update)
    }
}
