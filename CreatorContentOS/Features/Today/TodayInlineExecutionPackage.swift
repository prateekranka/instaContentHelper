import SwiftUI

/// Inline Today execution package — shared sections from Plan, with Today-specific actions.
struct TodayInlineExecutionPackage: View {
    @Environment(AppServices.self) private var services
    let card: GeneratedDailyCardDraft

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
            Text(card.title)
                .font(PocketSheetType.rowTitle)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("today.package.title")

            sceneProgressBlock

            GeneratedDayPlannedContent(card: card) { assets in
                services.applyStoryboardThumbnailAssets(assets, toDailyCardID: card.id)
            }
            .accessibilityIdentifier("today.package.content")
        }
        .onAppear {
            _ = services.hydrateTodayStoryboardThumbnailsFromPlanPackage()
        }
    }

    @ViewBuilder
    private var sceneProgressBlock: some View {
        if !services.todayCard.scenes.isEmpty {
            PocketSheetCard {
                HStack(alignment: .center, spacing: PocketSheetSpace.m) {
                    Image(systemName: services.areAllScenesShot ? "checkmark.seal.fill" : "target")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                        Text(services.areAllScenesShot ? "All scenes shot" : "\(services.shotSceneCount) of \(services.todayCard.scenes.count) scenes shot")
                            .font(PocketSheetType.rowTitle)
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                        Text(services.areAllScenesShot ? "Ready to mark posted." : "\(services.unshotSceneCount) remaining before you can post.")
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    }

                    Spacer(minLength: PocketSheetSpace.s)
                    PocketSheetStatus(
                        text: services.areAllScenesShot ? "Complete" : "\(services.unshotSceneCount) left",
                        kind: services.areAllScenesShot ? .ready : .pending
                    )
                }
            }
            .accessibilityIdentifier("today.package.sceneProgress")
        }
    }
}

extension AppServices {
    /// Resolves the richest package model for inline Today rendering.
    func todayExecutionPackageDraft() -> GeneratedDailyCardDraft? {
        guard case .ready = todayContentState else { return nil }
        let date = todayCard.scheduledDate?.nilIfBlank ?? currentTodayDateString
        if let package = dayPackage(for: date) {
            return package
        }
        return GeneratedDailyCardDraft(fromPublishedCard: todayShootFolioCard)
    }
}
