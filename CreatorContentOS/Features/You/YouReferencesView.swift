import SwiftUI

struct YouReferencesView: View {
    let backLabel: String
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            YouDestinationScaffold(
                title: "References",
                subtitle: "Save reels, audio, and inspiration accounts for future drafts.",
                backLabel: backLabel,
                onBack: onBack
            ) {
                IntelligenceHomeView(presentation: .you)
            }
        }
        .accessibilityIdentifier("you.screen.references")
    }
}
