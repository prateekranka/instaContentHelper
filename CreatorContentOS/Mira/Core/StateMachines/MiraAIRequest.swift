import Foundation

struct MiraJobResponse: Decodable, Sendable {
    let job: MiraJob
    let phase: String?

    init(job: MiraJob, phase: String? = nil) {
        self.job = job
        self.phase = phase
    }

    private enum CodingKeys: String, CodingKey { case phase }

    init(from decoder: any Decoder) throws {
        job = try MiraJob(from: decoder)
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        phase = try fields.decodeIfPresent(String.self, forKey: .phase)
    }
}

enum MiraAIRequestEvent {
    case send, saveFailed, accepted(MiraJobResponse), progress(MiraJobResponse), refused, stop, reconnect(String?), received(MiraJob)
}

enum MiraAIRequest: Equatable {
    case idle
    case waitingToStart(attempts: Int)
    case sending(attempts: Int)
    case working(jobID: UUID)
    case waitingToRetry(jobID: UUID)
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
        case (.sending, .accepted(let response)): Self.active(response)
        case (.working(let id), .progress(let response)) where id == response.job.id:
            Self.active(response)
        case (.waitingToRetry(let id), .progress(let response)) where id == response.job.id:
            Self.active(response)
        case (.sending(let attempts), .refused):
            attempts < 30 ? .waitingToStart(attempts: attempts + 1)
                : .needsReconnect(reason: "Mira is busy. Tap Reconnect to try again.")
        case (.waitingToStart, .stop), (.sending, .stop), (.working, .stop), (.waitingToRetry, .stop), (.needsReconnect, .stop): .stopping
        case (.sending, .reconnect(let reason)), (.working, .reconnect(let reason)),
            (.waitingToRetry, .reconnect(let reason)), (.stopping, .reconnect(let reason)):
            .needsReconnect(reason: reason)
        case (.working, .received(let job)), (.waitingToRetry, .received(let job)), (.stopping, .received(let job)):
            Self(saved: job)
        default: nil
        }
    }

    static let retryMessage = "Waiting to try again"

    private static func active(_ response: MiraJobResponse) -> Self {
        if response.job.state == .working, response.phase == "waiting_to_retry" {
            return .waitingToRetry(jobID: response.job.id)
        }
        return .working(jobID: response.job.id)
    }

    var pending: Bool {
        switch self {
        case .waitingToStart, .sending, .working, .waitingToRetry, .stopping, .needsReconnect: true
        case .idle, .failed, .stopped, .done: false
        }
    }

    var nextAction: MiraNextAction? {
        switch self {
        case .waitingToStart, .sending, .working, .waitingToRetry: .stop
        case .stopping: .wait
        case .needsReconnect: .reconnect
        case .failed, .stopped: .retry
        case .idle, .done: nil
        }
    }
}
