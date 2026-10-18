import SwiftUI

/// Inline Today execution package — shared sections from Plan, with Today-specific actions.
struct TodayInlineExecutionPackage: View {
    @Environment(AppServices.self) private var services
    let card: GeneratedDailyCardDraft

    var body: some View {
        TodayPocketPresentation(card: card)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.package.content")
            .onAppear {
                _ = services.hydrateTodayStoryboardThumbnailsFromPlanPackage()
            }
    }

}

extension AppServices {
    /// Resolves the richest package model for inline Today rendering.
    func todayExecutionPackageDraft() -> GeneratedDailyCardDraft? {
        guard case .ready = todayContentState else { return nil }
        let date = todayCard.scheduledDate?.nilIfBlank ?? currentTodayDateString
        if let package = dayPackage(for: date), package.id == todayCard.id {
            return package
        }
        return GeneratedDailyCardDraft(fromPublishedCard: todayShootFolioCard)
    }
}
