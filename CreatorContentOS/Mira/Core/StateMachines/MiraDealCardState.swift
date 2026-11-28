import Foundation

enum MiraDealCardEvent {
    case confirm(at: Date)
    case track(MiraDealTrackerEvent)
}

enum MiraDealCardState {
    case reviewing(MiraDealBriefDraft, MiraDealTerms)
    case saved(MiraDeal)

    func handle(_ event: MiraDealCardEvent) -> Self? {
        switch (self, event) {
        case (.reviewing(let draft, let terms), .confirm(let date)):
            return .saved(MiraDeal(id: draft.id, source: draft.text, terms: terms, confirmedAt: date))
        case (.saved(var deal), .track(let trackerEvent)):
            guard let next = MiraDealTrackerState(saved: deal.tracker).handle(trackerEvent) else { return nil }
            deal.tracker = next.record
            return .saved(deal)
        default:
            return nil
        }
    }

    var nextAction: MiraNextAction {
        switch self {
        case .reviewing: .confirmDeal
        case .saved: .openDeal
        }
    }
}
