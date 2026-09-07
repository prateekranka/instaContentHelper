import SwiftUI

struct YouCurrentContextView: View {
    @Environment(AppServices.self) private var services
    let backLabel: String
    let onBack: () -> Void

    @State private var selection = YouContextSelection(contextAnswers: [:], creatorNote: "")
    @State private var didLoad = false
    @State private var saveTask: Task<Void, Never>?

    private var promptedQuestions: [OnboardingContextQuestion] {
        let interests = YouInterestsSelection.from(profile: services.creatorProfileSummary)
        return OnboardingContextQuestions.promptedQuestions(
            interestIDs: interests.interestIDs,
            customSubjects: interests.customSubjects
        )
    }

    var body: some View {
        YouDestinationScaffold(
            title: "Current reads & watches",
            subtitle: "What's current for you — helps ideas feel personal.",
            backLabel: backLabel,
            onBack: onBack
        ) {
            PocketSheetBlock(header: "Your context") {
                VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
                    ForEach(promptedQuestions) { question in
                        VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                            Text(question.prompt)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(PocketSheetTheme.Color.ink)
                            TextField(question.placeholder, text: Binding(
                                get: { selection.contextAnswers[question.id, default: ""] },
                                set: { updateAnswer(questionID: question.id, answer: $0) }
                            ), axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .padding(PocketSheetSpace.s)
                            .background(PocketSheetTheme.Color.paperRaised)
                            .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                                    .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                            }
                            .accessibilityIdentifier("you.context.\(question.id)")
                        }
                    }

                    VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                        Text("Anything else you want to share? (Optional)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                        TextField("I love fantasy, and I like funny takes too.", text: Binding(
                            get: { selection.creatorNote },
                            set: { updateCreatorNote($0) }
                        ), axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .padding(PocketSheetSpace.s)
                        .background(PocketSheetTheme.Color.paperRaised)
                        .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                                .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                        }
                        .accessibilityIdentifier("you.context.creatorNote")
                    }

                    statusLine
                }
                .padding(.horizontal, PocketSheetSpace.m)
                .padding(.vertical, PocketSheetSpace.s)
            }
        }
        .accessibilityIdentifier("you.screen.context")
        .onAppear {
            guard !didLoad else { return }
            selection = YouContextSelection.from(profile: services.creatorProfileSummary)
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

    private func updateAnswer(questionID: String, answer: String) {
        selection.contextAnswers[questionID] = answer
        scheduleSave()
    }

    private func updateCreatorNote(_ note: String) {
        selection.creatorNote = note
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await persistSelection()
        }
    }

    @MainActor
    private func persistSelection() async {
        let interests = YouInterestsSelection.from(profile: services.creatorProfileSummary)
        let update = selection.profileUpdate(
            base: services.creatorProfileSummary,
            interestIDs: interests.interestIDs,
            customSubjects: interests.customSubjects
        )
        _ = await services.updateCreatorProfileImmediately(update)
    }
}
