import SwiftUI

/// Five idea bubbles plus **Other** for selected-day generation.
struct PlanDayIdeaLauncher: View {
    let ideas: [PlanDayIdeaCandidate]
    let isBusy: Bool
    let isInteractionDisabled: Bool
    @Binding var isOtherOpen: Bool
    @Binding var otherText: String
    let onSelectIdea: (PlanDayIdeaCandidate) -> Void
    let onSubmitOther: () -> Void

    private var controlsDisabled: Bool {
        isBusy || isInteractionDisabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
            Text("Choose an idea for this day")
                .font(PocketSheetType.sectionLabel)
                .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
                .textCase(.uppercase)
                .tracking(0.44)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("plan.daygen.title")

            ForEach(Array(ideas.enumerated()), id: \.element.id) { index, idea in
                ideaButton(idea, index: index)
            }

            otherButton

            if isOtherOpen {
                otherEditor
            }

            if isBusy {
                HStack(spacing: PocketSheetSpace.xs) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(PocketSheetTheme.Color.ink)
                    Text("Generating this day…")
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                }
                .accessibilityIdentifier("plan.daygen.busy")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.daygen.panel")
    }

    private func ideaButton(_ idea: PlanDayIdeaCandidate, index: Int) -> some View {
        Button {
            onSelectIdea(idea)
        } label: {
            VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                Text(idea.title)
                    .font(PocketSheetType.rowTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                Text(idea.summary)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PocketSheetSpace.s)
            .background(PocketSheetTheme.Color.paperRaised)
            .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                    .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(controlsDisabled)
        .opacity(controlsDisabled ? 0.45 : 1)
        .accessibilityLabel("Generate \(idea.title)")
        .accessibilityIdentifier("plan.daygen.idea.\(index)")
    }

    private var otherButton: some View {
        Button {
            isOtherOpen.toggle()
            if !isOtherOpen {
                otherText = ""
            }
        } label: {
            VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                Text("Other")
                    .font(PocketSheetType.rowTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                Text("Write your own direction for this day.")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PocketSheetSpace.s)
            .background(PocketSheetTheme.Color.paperRaised)
            .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                    .stroke(
                        isOtherOpen ? PocketSheetTheme.Color.ink : PocketSheetTheme.Color.hairline,
                        style: StrokeStyle(lineWidth: 1, dash: isOtherOpen ? [] : [4, 3])
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(controlsDisabled)
        .opacity(controlsDisabled ? 0.45 : 1)
        .accessibilityLabel("Write another idea")
        .accessibilityIdentifier("plan.daygen.other")
    }

    private var otherEditor: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
            VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                Text("Your direction")
                    .font(PocketSheetType.rowTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                Text("Use a specific idea, moment, or format. This creates one day only.")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }

            ZStack(alignment: .topLeading) {
                if otherText.isEmpty {
                    Text("e.g. A quiet pre-race check-in before the first mile…")
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $otherText)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .scrollContentBackground(.hidden)
                    .disabled(controlsDisabled)
                    .accessibilityIdentifier("plan.daygen.other.text")
            }
            .padding(PocketSheetSpace.s)
            .frame(minHeight: 96, alignment: .topLeading)
            .background(PocketSheetTheme.Color.paperRaised)
            .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                    .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
            }

            PocketSheetPrimaryAction(
                title: "Generate for this day",
                systemImage: "sparkles"
            ) {
                onSubmitOther()
            }
            .disabled(controlsDisabled || otherText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(
                controlsDisabled || otherText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? 0.48
                    : 1
            )
            .accessibilityIdentifier("plan.daygen.other.submit")
        }
    }
}
