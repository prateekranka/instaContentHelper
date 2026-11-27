import Foundation

enum MiraInsightsEvent {
    case load(UUID), connect(UUID), connected(UUID)
    case loaded(UUID, InstagramInsightsState), failed(UUID, String), cancelled(UUID)
}

enum MiraInsightsState {
    case unopened
    case loading(UUID, previous: InstagramInsightsState?)
    case connecting(UUID)
    case loaded(InstagramInsightsState)
    case loadFailed(String, previous: InstagramInsightsState?)
    case connectionFailed(String)

    func handle(_ event: MiraInsightsEvent) -> Self? {
        switch (self, event) {
        case (.unopened, .load(let id)): .loading(id, previous: nil)
        case (.loaded(let report), .load(let id)): .loading(id, previous: report)
        case (.loadFailed(_, let report), .load(let id)): .loading(id, previous: report)
        case (.loaded(.notConnected), .connect(let id)), (.connectionFailed, .connect(let id)):
            .connecting(id)
        case (.connecting(let id), .connected(let reply)) where id == reply:
            .loading(id, previous: nil)
        case (.loading(let id, _), .loaded(let reply, let report)) where id == reply: .loaded(report)
        case (.loading(let id, let report), .failed(let reply, let message)) where id == reply:
            .loadFailed(message, previous: report)
        case (.connecting(let id), .failed(let reply, let message)) where id == reply:
            .connectionFailed(message)
        case (.loading(let id, let report), .cancelled(let reply)) where id == reply:
            report.map { .loaded($0) } ?? .unopened
        case (.connecting(let id), .cancelled(let reply)) where id == reply: .loaded(.notConnected)
        default: nil
        }
    }

    var nextAction: MiraNextAction {
        switch self {
        case .unopened, .loading, .connecting: .wait
        case .loaded(.notConnected), .connectionFailed: .connectInstagram
        case .loaded, .loadFailed: .refreshInsights
        }
    }
}
