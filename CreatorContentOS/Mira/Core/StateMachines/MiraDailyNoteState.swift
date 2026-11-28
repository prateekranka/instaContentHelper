import Foundation

struct MiraDailyNoteScope: Equatable {
    let workspaceID: UUID
    let creatorID: UUID
    let memberID: UUID
    let day: Int

    static var utcDay: Int { Int(floor(Date().timeIntervalSince1970 / 86_400)) }
}

struct MiraDailyNoteItem: Codable, Equatable, Sendable {
    let id: UUID
    let title: String

    init(id: UUID, title: String, fallback: String) {
        self.id = id
        let line = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        self.title = line.isEmpty ? fallback : MiraBrandDocument.trimmed(
            String(decoding: line.utf16.prefix(240), as: UTF16.self))
    }
}

struct MiraDailyNoteInput: Codable, Equatable, Sendable {
    var operation = "dailyNote"
    let language: MiraLanguage
    let writingSystem: MiraWritingSystem
    let snapshots: [MiraInsightSnapshot]
    let openReels: [MiraDailyNoteItem]
    let openDeals: [MiraDailyNoteItem]
}

struct MiraDailyNote: Decodable, Sendable {
    struct Action: Decodable, Equatable, Sendable {
        enum Kind: String, Decodable, Sendable { case makeIdea, continueReel, openDeal, none }
        let type: Kind
        let id: UUID?
    }

    let noticed: String
    let action: Action
    let buttonText: String

    func canAct(in work: MiraDailyNoteWork) -> Bool {
        switch action.type {
        case .makeIdea: action.id == nil
        case .continueReel: work.reels.contains { $0.id == action.id }
        case .openDeal: work.deals.contains { $0.id == action.id }
        case .none: false
        }
    }
}

struct MiraDailyNoteReply: Decodable, Sendable {
    struct Output: Decodable, Sendable { let dailyNote: MiraDailyNote }
    let id: UUID
    let inputRevision: Int
    let input: MiraDailyNoteInput
    let state: MiraGenerationState
    let output: Output?

    var note: MiraDailyNote? {
        guard input.operation == "dailyNote", inputRevision >= 0, state == .succeeded,
            let note = output?.dailyNote, MiraBrandDocument.validLine(note.noticed) else { return nil }
        switch note.action.type {
        case .none:
            guard note.buttonText.isEmpty, note.action.id == nil else { return nil }
        default:
            guard MiraBrandDocument.validLine(note.buttonText),
                note.canAct(in: .init(reels: input.openReels, deals: input.openDeals)) else { return nil }
        }
        return note
    }
}

struct MiraDailyNoteWork {
    let reels: [MiraDailyNoteItem]
    let deals: [MiraDailyNoteItem]
}

protocol MiraDailyNoteService: Sendable {
    func dailyNote(id: UUID, input: MiraDailyNoteInput?) async throws -> MiraDailyNoteReply
}

enum MiraDailyNoteEvent {
    case start(MiraDailyNoteScope, UUID)
    case received(UUID, MiraDailyNote, usesInstagram: Bool)
    case failed(UUID)
    case reset
}

enum MiraDailyNoteState {
    case idle
    case loading(MiraDailyNoteScope, UUID)
    case ready(MiraDailyNoteScope, MiraDailyNote, usesInstagram: Bool)
    case unavailable(MiraDailyNoteScope)

    func handle(_ event: MiraDailyNoteEvent) -> Self? {
        switch (self, event) {
        case (_, .reset): return .idle
        case (_, .start(let scope, let id)) where self.scope != scope:
            return .loading(scope, id)
        case (.loading(let scope, let current), .received(let id, let note, let usesInstagram)) where current == id:
            return .ready(scope, note, usesInstagram: usesInstagram)
        case (.loading(let scope, let current), .failed(let id)) where current == id:
            return .unavailable(scope)
        default: return nil
        }
    }

    var scope: MiraDailyNoteScope? {
        switch self {
        case .idle: nil
        case .loading(let scope, _), .ready(let scope, _, _), .unavailable(let scope): scope
        }
    }
}
