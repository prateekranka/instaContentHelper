import Foundation

struct MiraDealTrackerDates: Codable, Equatable, Sendable {
    var postedAt: Date?
    var brandToldAt: Date?
    var confirmedAt: Date?
    var paidAt: Date?
}

enum MiraDealTrackerEvent {
    case posted(Date)
    case brandTold(Date)
    case confirmed(Date)
    case paid(Date)
}

enum MiraDealTrackerState {
    case toPost(MiraDealTrackerDates)
    case toTellBrand(MiraDealTrackerDates)
    case toConfirm(MiraDealTrackerDates)
    case toPay(MiraDealTrackerDates)
    case paid(MiraDealTrackerDates)

    init(saved: MiraDealTrackerDates) {
        if saved.postedAt == nil { self = .toPost(saved) }
        else if saved.brandToldAt == nil { self = .toTellBrand(saved) }
        else if saved.confirmedAt == nil { self = .toConfirm(saved) }
        else if saved.paidAt == nil { self = .toPay(saved) }
        else { self = .paid(saved) }
    }

    func handle(_ event: MiraDealTrackerEvent) -> Self? {
        switch (self, event) {
        case (.toPost(var dates), .posted(let date)):
            dates.postedAt = date
            return .toTellBrand(dates)
        case (.toTellBrand(var dates), .brandTold(let date)):
            dates.brandToldAt = date
            return .toConfirm(dates)
        case (.toConfirm(var dates), .confirmed(let date)):
            dates.confirmedAt = date
            return .toPay(dates)
        case (.toPay(var dates), .paid(let date)):
            dates.paidAt = date
            return .paid(dates)
        default:
            return nil
        }
    }

    var record: MiraDealTrackerDates {
        switch self {
        case .toPost(let dates), .toTellBrand(let dates), .toConfirm(let dates), .toPay(let dates), .paid(let dates): dates
        }
    }

    var nextAction: MiraNextAction? {
        switch self {
        case .toPost: .markDealPosted
        case .toTellBrand: .markBrandTold
        case .toConfirm: .markDealConfirmed
        case .toPay: .markDealPaid
        case .paid: nil
        }
    }
}
