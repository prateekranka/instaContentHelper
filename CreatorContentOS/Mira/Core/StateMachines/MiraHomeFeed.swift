import Foundation

struct MiraContinueReel: Identifiable, Equatable {
    let id: UUID
    let title: String
    let progress: MiraReelProgress
    let deliveryAction: MiraNextAction?

    var completedSteps: Int {
        if let deliveryAction { return [.prepareClips, .joinReel].contains(deliveryAction) ? 4 : 5 }
        return switch progress {
        case .choosing: 0
        case .writing, .approving: 1
        case .planning, .ready: 2
        case .filming: 3
        case .complete: 4
        }
    }

    var nextAction: MiraNextAction {
        deliveryAction ?? progress.nextAction
    }
}

enum MiraHomeFeedEvent {
    case workChanged([MiraProject], resume: UUID?, deals: [MiraDeal])
}

enum MiraHomeFeed {
    case empty
    case continuing([MiraContinueReel], [MiraDeal])
    case deals([MiraDeal])

    func handle(_ event: MiraHomeFeedEvent) -> Self {
        switch event {
        case .workChanged(let projects, let resume, let deals):
            let openDeals = deals.filter { $0.tracker.paidAt == nil }.sorted {
                if $0.terms.deadline == $1.terms.deadline { return $0.confirmedAt > $1.confirmedAt }
                if $0.terms.deadline.isEmpty { return false }
                if $1.terms.deadline.isEmpty { return true }
                return $0.terms.deadline < $1.terms.deadline
            }
            let openReels = projects.sorted { $0.updatedAt > $1.updatedAt }.compactMap { project -> MiraContinueReel? in
                let progress = project.stage
                guard !project.archived,
                    !project.ideas.isEmpty || !project.scripts.isEmpty || project.hasWorkingCards
                        || project.todayCards?.contains(where: { $0.output != nil }) == true
                else { return nil }
                let deal = project.deliveryDeal(in: deals)
                let action = project.canFilm ? project.deliveryNextAction(deal: deal) : nil
                if project.delivery?.post != nil && action == nil { return nil }
                return MiraContinueReel(id: project.id, title: project.idea?.title ?? project.title,
                    progress: progress, deliveryAction: action)
            }
            guard !openReels.isEmpty else { return openDeals.isEmpty ? .empty : .deals(openDeals) }
            if let reel = openReels.first(where: { $0.id == resume }) {
                return .continuing([reel] + openReels.filter { $0.id != reel.id }, openDeals)
            }
            return .continuing(openReels, openDeals)
        }
    }

    var nextAction: MiraNextAction {
        switch self {
        case .empty: .makeToday
        case .continuing(let reels, _): reels.first?.nextAction ?? .continueWork
        case .deals: .openDeal
        }
    }

    func contains(_ id: UUID) -> Bool {
        guard case .continuing(let reels, _) = self else { return false }
        return reels.contains { $0.id == id }
    }
}
