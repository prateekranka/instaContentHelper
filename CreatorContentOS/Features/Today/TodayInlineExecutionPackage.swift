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
        guard let id = selectedTodayPieceID else { return nil }
        return dayPackage(for: currentTodayDateString, pieceID: id)
    }
}
