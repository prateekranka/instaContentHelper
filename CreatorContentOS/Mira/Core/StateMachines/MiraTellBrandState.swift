import Foundation

enum MiraTellBrandEvent {
    case start(UUID, MiraDeliveryJob<MiraBrandNoteInput>)
    case received(UUID, String)
    case interrupted(UUID, String)
    case rejected(UUID, String)
    case opened(Date)
    case confirm(Date)
}

enum MiraTellBrandState {
    case needsNote
    case writing(MiraBrandMessage)
    case interrupted(MiraBrandMessage)
    case rejected(MiraBrandMessage)
    case draft(MiraBrandMessage)
    case opened(MiraBrandMessage)
    case sent(MiraBrandMessage)

    init(note: MiraBrandMessage?, running: Bool) {
        guard let note else { self = .needsNote; return }
        if note.sentAt != nil { self = .sent(note) }
        else if note.handoffAt != nil { self = .opened(note) }
        else if note.message != nil { self = .draft(note) }
        else if running { self = .writing(note) }
        else if note.job.creatorID == nil && note.issue != nil { self = .rejected(note) }
        else { self = .interrupted(note) }
    }

    var record: MiraBrandMessage? {
        switch self {
        case .needsNote: nil
        case .writing(let note), .interrupted(let note), .rejected(let note), .draft(let note),
            .opened(let note), .sent(let note): note
        }
    }

    func handle(_ event: MiraTellBrandEvent) -> Self? {
        switch (self, event) {
        case (.needsNote, .start(let deal, let job)), (.rejected, .start(let deal, let job)):
            return .writing(MiraBrandMessage(dealID: deal, job: job))
        case (.interrupted(var note), .start(let deal, let job)) where note.dealID == deal && note.job == job:
            note.issue = nil
            return .writing(note)
        case (.writing(var note), .received(let id, let message)) where note.job.id == id:
            let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.utf16.count <= 600 else { return nil }
            note.message = text
            return .draft(note)
        case (.writing(var note), .interrupted(let id, let issue)) where note.job.id == id:
            note.issue = issue
            return .interrupted(note)
        case (.writing(let note), .rejected(let id, let issue)) where note.job.id == id:
            let job = MiraDeliveryJob(id: id, creatorID: nil, input: note.job.input)
            return .rejected(MiraBrandMessage(dealID: note.dealID, job: job, issue: issue))
        case (.draft(var note), .opened(let date)), (.opened(var note), .opened(let date)):
            note.handoffAt = date
            return .opened(note)
        case (.opened(var note), .confirm(let date)) where note.handoffAt.map({ $0 <= date }) == true:
            note.sentAt = date
            return .sent(note)
        default:
            return nil
        }
    }

    var nextAction: MiraNextAction {
        switch self {
        case .needsNote: .writeBrandNote
        case .writing: .wait
        case .interrupted: .reconnect
        case .rejected: .retry
        case .draft: .openWhatsApp
        case .opened: .confirmBrandNote
        case .sent: .openDeal
        }
    }
}
