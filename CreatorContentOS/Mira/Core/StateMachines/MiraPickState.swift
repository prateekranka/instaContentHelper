import Foundation

struct MiraPickContext: Equatable {
    let dealID: UUID?
    let isDemo: Bool
    let skippedTitles: [String]
    var postPattern: String? = nil
}

enum MiraPickEvent {
    case start(MiraPickContext, MiraJob)
    case progress(UUID, MiraGenerationStep?)
    case received(MiraJob)
    case failed(MiraJob, String)
    case make
    case reset
}

enum MiraPickState: Equatable {
    case idle
    case working(MiraPickContext, MiraJob, previous: MiraOutput?, step: MiraGenerationStep?)
    case ready(MiraPickContext, MiraJob)
    case failed(MiraPickContext, MiraJob, previous: MiraOutput?, message: String)

    var request: String? {
        switch self {
        case .idle: nil
        case .working(_, let job, _, _), .ready(_, let job), .failed(_, let job, _, _): job.input.request
        }
    }

    var postPattern: String? {
        switch self {
        case .idle: nil
        case .working(let context, _, _, _), .ready(let context, _), .failed(let context, _, _, _): context.postPattern
        }
    }

    var nextAction: MiraNextAction {
        switch self {
        case .idle: .makeToday
        case .working: .wait
        case .ready: .makeCard
        case .failed: .retry
        }
    }

    func handle(_ event: MiraPickEvent) -> Self? {
        switch (self, event) {
        case (_, .reset), (.ready, .make):
            return .idle
        case (.idle, .start(let context, let job)):
            return .working(context, job, previous: nil, step: nil)
        case (.ready(_, let prior), .start(let context, let job)):
            return .working(context, job, previous: prior.output, step: nil)
        case (.failed(_, _, let previous, _), .start(let context, let job)):
            return .working(context, job, previous: previous, step: nil)
        case (.working(let context, let job, let previous, _), .progress(let id, let step)) where job.id == id:
            return .working(context, job, previous: previous, step: step)
        case (.working(let context, let job, _, _), .received(let reply))
            where job.id == reply.id && reply.state == .succeeded:
            return .ready(context, reply)
        case (.working(let context, let job, let previous, _), .failed(let reply, let message)) where job.id == reply.id:
            return .failed(context, reply, previous: previous, message: message)
        default:
            return nil
        }
    }
}
