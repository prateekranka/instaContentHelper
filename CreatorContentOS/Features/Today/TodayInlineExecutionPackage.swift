import SwiftUI

/// Inline Today execution package — shared sections from Plan, with Today-specific actions.
struct TodayInlineExecutionPackage: View {
    @Environment(AppServices.self) private var services
    let card: GeneratedDailyCardDraft

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.l) {
            Text(card.title)
                .font(MCOType.headline)
                .foregroundStyle(MCOTheme.Color.ink)
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
            JournalBlock {
                HStack(alignment: .center, spacing: MCOSpace.m) {
                    Image(systemName: services.areAllScenesShot ? "checkmark.seal.fill" : "target")
                        .font(MCOType.cardTitle)
                        .foregroundStyle(services.areAllScenesShot ? MCOTheme.Color.success : MCOTheme.Color.liveBlue)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                        Text(services.areAllScenesShot ? "All scenes shot" : "\(services.shotSceneCount) of \(services.todayCard.scenes.count) scenes shot")
                            .font(MCOType.headline)
                            .foregroundStyle(MCOTheme.Color.ink)
                        Text(services.areAllScenesShot ? "Ready to mark posted." : "\(services.unshotSceneCount) remaining before you can post.")
                            .font(MCOType.caption)
                            .foregroundStyle(MCOTheme.Color.inkMuted)
                    }

                    Spacer(minLength: MCOSpace.s)
                    StatusChip(
                        text: services.areAllScenesShot ? "Complete" : "\(services.unshotSceneCount) left",
                        tone: services.areAllScenesShot ? .ready : .info
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
