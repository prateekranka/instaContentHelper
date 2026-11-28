import Foundation

struct MiraInsightPost: Codable, Hashable, Sendable {
    enum Action {
        case usePostPattern

        var title: String { "Make one like this" }
    }

    let caption: String
    var views: Int?
    var reach: Int?
    var likes: Int?
    var comments: Int?
    var saves: Int?
    var shares: Int?

    var counts: [(label: String, value: Int)] {
        [("Views", views), ("Reach", reach), ("Likes", likes), ("Comments", comments),
         ("Saves", saves), ("Shares", shares)].compactMap { label, count in
            guard let count, count >= 0 else { return nil }
            return (label, count)
        }
    }

    var nextAction: Action { .usePostPattern }

    var pattern: String {
        let line = caption.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return MiraBrandDocument.trimmed(String(decoding: line.utf16.prefix(240), as: UTF16.self))
    }
}

struct MiraInsightSnapshot: Codable, Hashable, Sendable {
    var followers: Int?
    var reach7d: Int?
    var saves7d: Int?
    var topPosts: [MiraInsightPost]?

    var hasResults: Bool {
        followers != nil || reach7d != nil || saves7d != nil || topPosts?.isEmpty == false
    }
}

struct MiraHomeInsightMetric: Identifiable {
    var id: String { label }
    let label: String
    let value: String?
    let change: String?
}

struct MiraHomeInsightData {
    let metrics: [MiraHomeInsightMetric]
    let snapshots: [MiraInsightSnapshot]
    let posts: [MiraInsightPost]
    let sourceLabel: String?
}

enum MiraHomeInsightsEvent {
    case load(MiraDailyNoteScope, UUID)
    case received(UUID, MiraHomeInsightData?)
    case reset
}

enum MiraHomeInsightsState {
    case unopened
    case loading(MiraDailyNoteScope, UUID)
    case unavailable(MiraDailyNoteScope)
    case ready(MiraDailyNoteScope, MiraHomeInsightData)

    func handle(_ event: MiraHomeInsightsEvent) -> Self? {
        switch (self, event) {
        case (_, .load(let scope, let id)): return .loading(scope, id)
        case (_, .reset): return .unopened
        case (.loading(let scope, let current), .received(let id, let data)) where current == id:
            guard let data else { return .unavailable(scope) }
            return .ready(scope, data)
        default: return nil
        }
    }

    var scope: MiraDailyNoteScope? {
        switch self {
        case .unopened: nil
        case .loading(let scope, _), .unavailable(let scope), .ready(let scope, _): scope
        }
    }
}
