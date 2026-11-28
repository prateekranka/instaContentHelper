import SwiftUI

struct MiraHomePickCard: View {
    let state: MiraPickState
    let onMake: () -> Void
    let onAnother: () -> Void

    var body: some View {
        MiraFeedCard {
            switch state {
            case .idle:
                EmptyView()
            case .working(_, _, let previous, let step):
                if let previous { idea(previous) }
                ProgressView(progressText(step))
                    .accessibilityIdentifier("mira.pick.wait")
            case .ready(_, let job):
                if let output = job.output { idea(output) }
                Button(state.nextAction.title, action: onMake)
                    .buttonStyle(MiraPrimaryStyle())
                    .accessibilityIdentifier("mira.pick.make")
                Button("Show another idea", action: onAnother)
                    .font(.subheadline).padding(.vertical, 8)
                    .accessibilityIdentifier("mira.pick.another")
            case .failed(_, _, let previous, let message):
                if let previous { idea(previous) }
                Text(message).accessibilityIdentifier("mira.pick.error")
                Button(state.nextAction.title, action: onAnother)
                    .buttonStyle(MiraPrimaryStyle())
                    .accessibilityIdentifier("mira.pick.retry")
            }
        }.accessibilityIdentifier("mira.pick.card")
    }

    @ViewBuilder private func idea(_ output: MiraOutput) -> some View {
        if let reason = output.reason, let idea = output.ideas?.first {
            MiraSectionTitle(text: "My pick for you")
            Text(reason).accessibilityIdentifier("mira.pick.reason")
            Text(idea.title).font(.title2.bold()).accessibilityIdentifier("mira.pick.title")
            Text(idea.visual)
        }
    }

    private func progressText(_ step: MiraGenerationStep?) -> String {
        switch step {
        case nil: "Finding one idea for you"
        case .ideaReady: "Writing your words"
        case .scriptReady: "Planning your shots"
        case .storyboardReady: "Finishing your pick"
        }
    }
}
