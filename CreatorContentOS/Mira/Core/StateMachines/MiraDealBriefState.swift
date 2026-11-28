import Foundation

enum MiraDealBriefEvent {
    case begin(UUID, String)
    case edit(String)
    case read(MiraDealBriefJob)
    case resume
    case interrupted(String)
    case received(MiraDealBriefReply)
    case confirmed
}

enum MiraDealBriefState {
    case empty
    case editing(MiraDealBriefDraft)
    case reading(MiraDealBriefDraft)
    case reconnect(MiraDealBriefDraft)
    case failed(MiraDealBriefDraft)
    case reviewing(MiraDealBriefDraft)

    init(record: MiraDealBriefDraft?, running: Bool) {
        if let record {
            if record.terms != nil {
                self = .reviewing(record)
            } else if record.job != nil {
                self = running ? .reading(record) : .reconnect(record)
            } else {
                self = record.issue == nil ? .editing(record) : .failed(record)
            }
        } else {
            self = .empty
        }
    }

    func handle(_ event: MiraDealBriefEvent) -> Self? {
        switch (self, event) {
        case (.empty, .begin(let id, let text)):
            return .editing(MiraDealBriefDraft(id: id, text: text))
        case (.editing(let draft), .begin(let id, let text)) where draft.text.isEmpty && !text.isEmpty:
            return .editing(MiraDealBriefDraft(id: id, text: text))
        case (.editing(var draft), .edit(let text)), (.failed(var draft), .edit(let text)),
            (.reviewing(var draft), .edit(let text)):
            draft.text = text
            draft.issue = nil
            draft.terms = nil
            return .editing(draft)
        case (.editing(var draft), .read(let job)), (.failed(var draft), .read(let job)):
            guard MiraDealBriefInput.canRead(draft.text), job.input.briefText == draft.text else { return nil }
            draft.job = job
            draft.issue = nil
            return .reading(draft)
        case (.reconnect(var draft), .resume):
            draft.issue = nil
            return .reading(draft)
        case (.reading(var draft), .interrupted(let message)):
            draft.issue = message
            return .reconnect(draft)
        case (.reading(var draft), .received(let reply)):
            guard let job = draft.job, reply.matches(job), reply.state != .working else { return nil }
            draft.job = nil
            if reply.state == .succeeded, let terms = reply.output?.deal, terms.matchesSource(draft.text) {
                draft.terms = terms
                return .reviewing(draft)
            }
            draft.issue = reply.error == "operation_daily_cap_reached"
                ? "Mira has reached today's limit for reading briefs. Try again tomorrow."
                : "Mira couldn't read this brief. Your text is still here."
            return .failed(draft)
        case (.reviewing, .confirmed):
            return .empty
        default:
            return nil
        }
    }

    var record: MiraDealBriefDraft? {
        switch self {
        case .empty: nil
        case .editing(let draft), .reading(let draft), .reconnect(let draft), .failed(let draft), .reviewing(let draft): draft
        }
    }

    var nextAction: MiraNextAction {
        switch self {
        case .empty: .pasteDealBrief
        case .editing: .readDealBrief
        case .reading: .wait
        case .reconnect: .reconnect
        case .failed: .retry
        case .reviewing: .confirmDeal
        }
    }
}
