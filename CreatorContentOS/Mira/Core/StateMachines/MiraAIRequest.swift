import Foundation

enum MiraGenerationStep: String, Sendable {
    case ideaReady = "idea_ready"
    case scriptReady = "script_ready"
    case storyboardReady = "storyboard_ready"
}

enum MiraShotPictureState: Equatable, Sendable {
    case pending
    case ready(URL, refreshedAt: Date?)
    case refreshing(URL, requestedAt: Date)
    case failed
}

struct MiraShotPictureReply: Decodable, Sendable {
    enum Status: String, Decodable, Sendable { case pending, ready, failed }
    let shotID: UUID
    let status: Status
    let url: URL?
}

struct MiraJobResponse: Decodable, Sendable {
    let job: MiraJob
    let phase: String?
    let step: MiraGenerationStep?
    let pictures: [MiraShotPictureReply]?

    init(job: MiraJob, phase: String? = nil, step: MiraGenerationStep? = nil, pictures: [MiraShotPictureReply]? = nil) {
        self.job = job
        self.phase = phase
        self.step = step
        self.pictures = pictures
    }

    private enum CodingKeys: String, CodingKey { case phase, step, pictures }

    init(from decoder: any Decoder) throws {
        job = try MiraJob(from: decoder)
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        phase = try fields.decodeIfPresent(String.self, forKey: .phase)
        step = (try? fields.decode(String.self, forKey: .step)).flatMap { MiraGenerationStep(rawValue: $0) }
        pictures = try? fields.decode([MiraShotPictureReply].self, forKey: .pictures)
    }
}

enum MiraAIRequestEvent {
    case send, saveFailed, accepted(MiraJobResponse), progress(MiraJobResponse), refused, stop, reconnect(String?), received(MiraJob)
    case picturesReceived([MiraShotPictureReply])
    case pictureLoadFailed(UUID, URL, at: Date)
}

enum MiraAIRequest: Equatable {
    case idle
    case waitingToStart(attempts: Int)
    case sending(attempts: Int)
    case working(jobID: UUID, step: MiraGenerationStep?)
    case waitingToRetry(jobID: UUID)
    case stopping
    case needsReconnect(reason: String?)
    case failed(reason: String?)
    case stopped
    case done(pictures: [UUID: MiraShotPictureState])

    init(saved job: MiraJob?) {
        switch job?.state {
        case .none, .some(.idle): self = .idle
        case .working: self = .needsReconnect(reason: job?.error)
        case .failed: self = .failed(reason: job?.error)
        case .cancelled: self = .stopped
        case .succeeded: self = .done(pictures: [:])
        }
    }

    func handle(_ event: MiraAIRequestEvent) -> Self? {
        switch (self, event) {
        case (.needsReconnect, .send): .sending(attempts: 0)
        case (.waitingToStart(let attempts), .send): .sending(attempts: attempts)
        case (.sending, .saveFailed): .needsReconnect(reason: nil)
        case (.sending, .accepted(let response)): Self.active(response)
        case (.working(let id, _), .progress(let response)) where id == response.job.id:
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
        case (.done(let pictures), .picturesReceived(let replies)):
            .done(pictures: Self.updatedPictures(pictures, replies: replies))
        case (.done(let pictures), .pictureLoadFailed(let shotID, let url, let now)):
            Self.failedPicture(pictures, shotID: shotID, url: url, now: now)
        default: nil
        }
    }

    static let retryMessage = "Waiting to try again"

    private static func active(_ response: MiraJobResponse) -> Self {
        if response.job.state == .working, response.phase == "waiting_to_retry" {
            return .waitingToRetry(jobID: response.job.id)
        }
        return .working(jobID: response.job.id, step: response.step)
    }

    private static func updatedPictures(
        _ pictures: [UUID: MiraShotPictureState], replies: [MiraShotPictureReply]
    ) -> [UUID: MiraShotPictureState] {
        var next: [UUID: MiraShotPictureState] = [:]
        for reply in replies {
            switch reply.status {
            case .pending: next[reply.shotID] = .pending
            case .failed: next[reply.shotID] = .failed
            case .ready:
                guard let url = reply.url, url.scheme == "https" || url.scheme == "http" else {
                    next[reply.shotID] = .failed
                    continue
                }
                switch pictures[reply.shotID] {
                case .refreshing(let rejectedURL, let requestedAt):
                    next[reply.shotID] = rejectedURL == url ? .failed : .ready(url, refreshedAt: requestedAt)
                case .ready(let current, let refreshedAt):
                    next[reply.shotID] = .ready(current, refreshedAt: refreshedAt)
                case .failed: next[reply.shotID] = .failed
                case .pending, nil: next[reply.shotID] = .ready(url, refreshedAt: nil)
                }
            }
        }
        return next
    }

    private static func failedPicture(
        _ pictures: [UUID: MiraShotPictureState], shotID: UUID, url: URL, now: Date
    ) -> Self? {
        guard case .ready(let current, let refreshedAt) = pictures[shotID], current == url else { return nil }
        var next = pictures
        if let refreshedAt, now.timeIntervalSince(refreshedAt) < 60 {
            next[shotID] = .failed
        } else {
            next[shotID] = .refreshing(url, requestedAt: now)
        }
        return .done(pictures: next)
    }

    var pictures: [UUID: MiraShotPictureState] {
        if case .done(let pictures) = self { return pictures }
        return [:]
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
