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
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            Text("Choose an idea for this day")
                .font(MCOType.tinyLabel)
                .foregroundStyle(MCOTheme.Color.inkMuted)
                .textCase(.uppercase)
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
                HStack(spacing: MCOSpace.xs) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating this day…")
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
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
            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text(idea.title)
                    .font(MCOType.bodyEmphasis)
                    .foregroundStyle(MCOTheme.Color.ink)
                Text(idea.summary)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MCOSpace.s)
            .background(MCOTheme.Color.paperRaised.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                    .stroke(MCOTheme.Color.hairlineStrong, lineWidth: 1)
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
            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text("Other")
                    .font(MCOType.bodyEmphasis)
                    .foregroundStyle(MCOTheme.Color.ink)
                Text("Write your own direction for this day.")
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MCOSpace.s)
            .background(MCOTheme.Color.paperRaised.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                    .stroke(
                        isOtherOpen ? MCOTheme.Color.ink : MCOTheme.Color.hairlineStrong,
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
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text("Your direction")
                    .font(MCOType.bodyEmphasis)
                    .foregroundStyle(MCOTheme.Color.ink)
                Text("Use a specific idea, moment, or format. This creates one day only.")
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }

            ZStack(alignment: .topLeading) {
                if otherText.isEmpty {
                    Text("e.g. A quiet pre-race check-in before the first mile…")
                        .font(MCOType.bodySmall)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $otherText)
                    .font(MCOType.bodySmall)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .scrollContentBackground(.hidden)
                    .disabled(controlsDisabled)
                    .accessibilityIdentifier("plan.daygen.other.text")
            }
            .padding(MCOSpace.s)
            .frame(minHeight: 96, alignment: .topLeading)
            .background(MCOTheme.Color.paperRaised.opacity(0.86))
            .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                    .stroke(MCOTheme.Color.hairlineStrong.opacity(0.8), lineWidth: 1)
            }

            PrimaryActionButton(
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
