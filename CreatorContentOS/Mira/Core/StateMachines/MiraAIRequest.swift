import Foundation

enum MiraAIRequestEvent {
    case send, saveFailed, accepted(UUID), refused, stop, reconnect(String?), received(MiraJob)
}

enum MiraAIRequest: Equatable {
    case idle
    case waitingToStart(attempts: Int)
    case sending(attempts: Int)
    case working(jobID: UUID)
    case stopping
    case needsReconnect(reason: String?)
    case failed(reason: String?)
    case stopped
    case done

    init(saved job: MiraJob?) {
        switch job?.state {
        case .none, .some(.idle): self = .idle
        case .working: self = .needsReconnect(reason: job?.error)
        case .failed: self = .failed(reason: job?.error)
        case .cancelled: self = .stopped
        case .succeeded: self = .done
        }
    }

    func handle(_ event: MiraAIRequestEvent) -> Self? {
        switch (self, event) {
        case (.needsReconnect, .send): .sending(attempts: 0)
        case (.waitingToStart(let attempts), .send): .sending(attempts: attempts)
        case (.sending, .saveFailed): .needsReconnect(reason: nil)
        case (.sending, .accepted(let id)): .working(jobID: id)
        case (.sending(let attempts), .refused):
            attempts < 30 ? .waitingToStart(attempts: attempts + 1)
                : .needsReconnect(reason: "Mira is busy. Tap Reconnect to try again.")
        case (.waitingToStart, .stop), (.sending, .stop), (.working, .stop), (.needsReconnect, .stop): .stopping
        case (.sending, .reconnect(let reason)), (.working, .reconnect(let reason)), (.stopping, .reconnect(let reason)):
            .needsReconnect(reason: reason)
        case (.working, .received(let job)), (.stopping, .received(let job)):
            Self(saved: job)
        default: nil
        }
    }

    var pending: Bool {
        switch self {
        case .waitingToStart, .sending, .working, .stopping, .needsReconnect: true
        case .idle, .failed, .stopped, .done: false
        }
    }

    var nextAction: MiraNextAction? {
        switch self {
        case .waitingToStart, .sending, .working: .stop
        case .stopping: .wait
        case .needsReconnect: .reconnect
        case .failed, .stopped: .retry
        case .idle, .done: nil
        }
    }
}
