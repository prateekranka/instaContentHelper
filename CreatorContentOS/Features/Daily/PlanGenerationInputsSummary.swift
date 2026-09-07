import SwiftUI

/// Read-only Plan summary linking to You setup destinations (no inline editors).
struct PlanGenerationInputsSummary: View {
    @Environment(AppState.self) private var appState
    let setup: PlanDaySetupSummary
    let selectedDate: String

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
            Text("Idea settings")
                .font(PocketSheetType.sectionLabel)
                .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
                .tracking(0.44)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("plan.inputSummary.title")

            Text(inputSummaryCopy)
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: PocketSheetSpace.xs) {
                setupLink(.contentCategories, title: "Content categories", meta: categoriesMeta)
                setupLink(.creatorVoice, title: "Creator voice", meta: voiceMeta)
                setupLink(.references, title: "References", meta: referencesMeta)
            }
            .accessibilityIdentifier("plan.inputSummary.links")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.inputSummary")
    }

    private var inputSummaryCopy: String {
        "Your ideas use Content categories, Creator voice, and References."
    }

    private func setupLink(
        _ destination: YouRoute,
        title: String,
        meta: String
    ) -> some View {
        Button {
            appState.requestYouDestination(
                destination,
                from: .plan(selectedDate: selectedDate)
            )
        } label: {
            HStack(alignment: .center, spacing: PocketSheetSpace.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(PocketSheetType.rowTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                    Text(meta)
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                }
                Spacer(minLength: PocketSheetSpace.s)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
            }
            .padding(PocketSheetSpace.s)
            .background(PocketSheetTheme.Color.paperRaised)
            .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                    .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plan.inputSummary.link.\(accessibilitySuffix(for: destination))")
    }

    private var categoriesMeta: String {
        YouSetupMeta.categoriesSubtitle(from: setup.contentPillars)
    }

    private var voiceMeta: String {
        setup.voiceIsConfigured ? "Saved" : "Not set"
    }

    private var referencesMeta: String {
        "\(setup.confirmedReferenceCount) confirmed · \(setup.totalReferenceCount) total"
    }

    private func accessibilitySuffix(for destination: YouRoute) -> String {
        switch destination {
        case .contentCategories: "categories"
        case .productionPreferences: "production"
        case .currentContext: "context"
        case .creatorVoice: "voice"
        case .references: "references"
        case .account: "account"
        case .archive: "archive"
        }
    }
}
