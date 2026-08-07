import SwiftUI

enum YouNavigationOrigin: Hashable, Sendable {
    case you
    case plan(selectedDate: String?)
}

struct YouNavigationIntent: Hashable, Sendable {
    var destination: YouRoute
    var origin: YouNavigationOrigin
}

struct YouBackHeader: View {
    let backLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PocketSheetSpace.xxs) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                Text(backLabel)
                    .font(PocketSheetType.rowTitle)
            }
            .foregroundStyle(PocketSheetTheme.Color.ink)
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to \(backLabel)")
    }
}

struct YouDestinationScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    let backLabel: String
    let onBack: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
                YouBackHeader(backLabel: backLabel, action: onBack)
                VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                    Text(title)
                        .font(PocketSheetType.screenTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                    Text(subtitle)
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content()
            }
            .padding(.horizontal, PocketSheetSpace.l)
            .padding(.top, PocketSheetSpace.xs)
            .padding(.bottom, PocketSheetSpace.xl)
        }
        .background(PocketSheetTheme.Color.paper.ignoresSafeArea())
    }
}

enum YouSetupMeta {
    static func categoriesSubtitle(from pillars: [String]) -> String {
        ContentCategorySelection.from(contentPillars: pillars).summarySubtitle
    }

    static func voiceSubtitle(profile: CreatorProfileSummary) -> String {
        let positioning = profile.positioning.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasVoice = !positioning.isEmpty &&
            !(profile.voiceRules.isEmpty && profile.voiceLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        return hasVoice ? "Saved" : "Not set"
    }

    static func referencesSubtitle(home: IntelligenceHome) -> String {
        let references = home.sourcePulse.references
        let confirmed = references.filter { $0.state != .needsReview }.count
        let total = references.count
        if total == 0 {
            return confirmed == 0 ? "None saved" : "\(confirmed) confirmed"
        }
        return "\(confirmed) confirmed · \(total) total"
    }
}
