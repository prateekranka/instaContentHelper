import Foundation

struct MiraBrandDocument: Codable, Equatable, Sendable {
    var pillars: [String]
    var tone: String
    var audience: String
    var dos: [String]
    var donts: [String]
    var goals: [String]

    static func validLine(_ text: String) -> Bool {
        !text.isEmpty && text == trimmed(text) && text.utf16.count <= 240
            && !text.contains { $0.isNewline }
    }

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalized() -> Self {
        .init(pillars: pillars.map(Self.trimmed), tone: Self.trimmed(tone), audience: Self.trimmed(audience),
              dos: dos.map(Self.trimmed), donts: donts.map(Self.trimmed), goals: goals.map(Self.trimmed))
    }

    var isValid: Bool {
        (3...5).contains(pillars.count) && Set(pillars.map { $0.lowercased() }).count == pillars.count
            && (1...3).contains(goals.count) && dos.count <= 6 && donts.count <= 6
            && (pillars + [tone, audience] + dos + donts + goals).allSatisfy(Self.validLine)
    }
}

enum MiraBrandDocumentEvent {
    case read(MiraBrandDocument?)
    case draft(MiraBrandDocument)
    case edit
    case change(MiraBrandDocument)
    case confirm
}

enum MiraBrandDocumentState: Equatable {
    case empty
    case reviewing(MiraBrandDocument)
    case confirmed(MiraBrandDocument)

    var nextAction: MiraNextAction {
        switch self {
        case .empty: .startBrandInterview
        case .reviewing: .confirmBrandDoc
        case .confirmed: .editBrandDoc
        }
    }

    func handle(_ event: MiraBrandDocumentEvent) -> Self? {
        switch (self, event) {
        case (_, .read(let saved)):
            return saved.map(Self.confirmed) ?? .empty
        case (.empty, .draft(let draft)) where draft.isValid:
            return .reviewing(draft)
        case (.confirmed(let value), .edit):
            return .reviewing(value)
        case (.reviewing, .change(let draft)):
            return .reviewing(draft)
        case (.reviewing(let draft), .confirm) where draft.normalized().isValid:
            return .confirmed(draft.normalized())
        default:
            return nil
        }
    }
}
