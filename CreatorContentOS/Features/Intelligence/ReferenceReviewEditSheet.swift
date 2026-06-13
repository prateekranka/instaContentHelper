import SwiftUI

struct ReferenceReviewEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let item: IntelligenceItem
    let isSaving: Bool
    let onSave: (ReferenceReviewEdit) -> Void

    @State private var targetType: ReferenceReviewEditTarget
    @State private var handle: String
    @State private var url: String
    @State private var notes: String

    init(
        item: IntelligenceItem,
        isSaving: Bool,
        onSave: @escaping (ReferenceReviewEdit) -> Void
    ) {
        self.item = item
        self.isSaving = isSaving
        self.onSave = onSave

        let initialTarget = item.typeChip?.reviewEditTarget ?? .unknown
        _targetType = State(initialValue: initialTarget)
        _handle = State(initialValue: item.typeChip == .account ? item.title : "")
        _url = State(initialValue: item.sourceURL ?? "")
        _notes = State(initialValue: item.subtitle)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MCOTheme.Color.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: MCOSpace.l) {
                        VStack(alignment: .leading, spacing: MCOSpace.xs) {
                            Text("NEEDS YOUR CALL")
                                .font(MCOType.tinyLabel)
                                .foregroundStyle(MCOTheme.Color.oxblood)
                            Text("Resolve reference")
                                .font(MCOType.screenTitle)
                                .foregroundStyle(MCOTheme.Color.ink)
                            Text(item.title)
                                .font(.system(size: 16, weight: .regular, design: .serif))
                                .foregroundStyle(MCOTheme.Color.inkMuted)
                        }

                        JournalBlock {
                            VStack(alignment: .leading, spacing: MCOSpace.m) {
                                Text("TYPE")
                                    .font(MCOType.tinyLabel)
                                    .foregroundStyle(MCOTheme.Color.oxblood)

                                Picker("Reference type", selection: $targetType) {
                                    Text("Account").tag(ReferenceReviewEditTarget.account)
                                    Text("Reel").tag(ReferenceReviewEditTarget.reel)
                                    Text("Audio").tag(ReferenceReviewEditTarget.audio)
                                    Text("Unknown").tag(ReferenceReviewEditTarget.unknown)
                                }
                                .pickerStyle(.segmented)

                                if targetType == .account {
                                    LabeledContentField(
                                        title: "Handle",
                                        placeholder: "@creator",
                                        text: $handle
                                    )
                                } else {
                                    LabeledContentField(
                                        title: "URL",
                                        placeholder: "https://www.instagram.com/reel/...",
                                        text: $url
                                    )
                                }

                                VStack(alignment: .leading, spacing: MCOSpace.xs) {
                                    Text("Notes")
                                        .font(MCOType.caption)
                                        .foregroundStyle(MCOTheme.Color.inkMuted)
                                    TextEditor(text: $notes)
                                        .font(MCOType.bodySmall)
                                        .foregroundStyle(MCOTheme.Color.ink)
                                        .scrollContentBackground(.hidden)
                                        .frame(minHeight: 96)
                                        .padding(MCOSpace.xs)
                                        .background(MCOTheme.Color.paper.opacity(0.76))
                                        .clipShape(RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous)
                                                .stroke(MCOTheme.Color.hairline, lineWidth: 1)
                                        }
                                }
                            }
                        }
                    }
                    .padding(MCOSpace.l)
                    .padding(.bottom, 120)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GlassCommandBar {
                    SecondaryActionButton(title: "Cancel") {
                        dismiss()
                    }
                    .frame(maxWidth: 120)

                    PrimaryActionButton(
                        title: isSaving ? "Saving" : "Save",
                        systemImage: "checkmark"
                    ) {
                        onSave(
                            ReferenceReviewEdit(
                                targetType: targetType,
                                handle: handle.nilIfBlank,
                                url: url.nilIfBlank,
                                notes: notes.nilIfBlank
                            )
                        )
                        dismiss()
                    }
                    .disabled(isSaving || !canSave)
                }
                .padding(.horizontal, MCOSpace.m)
                .padding(.bottom, MCOSpace.s)
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium, .large])
    }

    private var canSave: Bool {
        switch targetType {
        case .account:
            return !handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .reel, .audio:
            return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .unknown:
            return !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

private struct LabeledContentField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xs) {
            Text(title)
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.inkMuted)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(MCOType.bodySmall)
                .foregroundStyle(MCOTheme.Color.ink)
                .padding(MCOSpace.s)
                .background(MCOTheme.Color.paper.opacity(0.76))
                .clipShape(RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous)
                        .stroke(MCOTheme.Color.hairline, lineWidth: 1)
                }
        }
    }
}

private extension ReferenceImportTypeChip {
    var reviewEditTarget: ReferenceReviewEditTarget {
        switch self {
        case .account:
            .account
        case .reel:
            .reel
        case .audio:
            .audio
        case .unknown:
            .unknown
        }
    }
}

#Preview {
    ReferenceReviewEditSheet(
        item: IntelligenceHome.raceWeekLibrary.needsReview[0],
        isSaving: false
    ) { _ in }
}
