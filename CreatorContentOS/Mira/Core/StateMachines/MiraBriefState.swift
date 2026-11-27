import Foundation

enum MiraBriefEvent {
    case textChanged(String), detailChanged(UUID, String), removeRequirement(UUID)
    case extracted(MiraBrief), confirm, stopUsing
}

enum MiraBriefState {
    case empty(MiraBrief)
    case draft(MiraBrief)
    case reviewing(MiraBrief)
    case unresolved(MiraBrief)
    case confirmed(MiraBrief)

    init(saved brief: MiraBrief) {
        if brief.confirmed {
            self = .confirmed(brief)
        } else if !brief.unresolved.isEmpty {
            self = .unresolved(brief)
        } else if !brief.requirements.isEmpty {
            self = .reviewing(brief)
        } else if brief.original.isEmpty {
            self = .empty(brief)
        } else {
            self = .draft(brief)
        }
    }

    func handle(_ event: MiraBriefEvent) -> Self? {
        var brief = record
        switch event {
        case .textChanged(let text):
            brief.original = text
            brief.confirmed = false
        case .detailChanged(let id, let text):
            guard let index = brief.requirements.firstIndex(where: { $0.id == id }) else { return nil }
            brief.requirements[index].value = text
            brief.confirmed = false
        case .removeRequirement(let id):
            brief.requirements.removeAll { $0.id == id }
            brief.confirmed = false
        case .extracted(let proposal):
            brief = proposal
            brief.confirmed = false
        case .confirm:
            guard canConfirm else { return nil }
            brief.confirmed = true
        case .stopUsing:
            brief.confirmed = false
        }
        brief.revision = record.revision + 1
        return Self(saved: brief)
    }

    var record: MiraBrief {
        switch self {
        case .empty(let brief), .draft(let brief), .reviewing(let brief),
            .unresolved(let brief), .confirmed(let brief): brief
        }
    }

    var confirmedRecord: MiraBrief? {
        if case .confirmed(let brief) = self { return brief }
        return nil
    }

    var canConfirm: Bool {
        let brief = record
        return !brief.requirements.isEmpty && brief.requirements.allSatisfy {
            matchesSource($0)
        }
    }

    func matchesSource(_ requirement: MiraRequirement) -> Bool {
        record.original.contains(requirement.excerpt) && record.original.contains(requirement.value)
    }

    var nextAction: MiraNextAction {
        switch self {
        case .empty: .enterBrief
        case .draft: .extractRequirements
        case .reviewing, .unresolved: canConfirm ? .confirmRequirements : .extractRequirements
        case .confirmed: .editBrief
        }
    }
}
