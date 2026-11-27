import Foundation

enum MiraTodayCardEvent {
    case workChanged(MiraTodayCard, MiraAIRequest, briefRevision: Int)
    case make, retry
}

enum MiraTodayCardState {
    case waiting(previous: MiraOutput?)
    case making(previous: MiraOutput?, step: MiraGenerationStep?)
    case waitingToRetry(previous: MiraOutput?)
    case reconnect(previous: MiraOutput?, reason: String?)
    case failed(previous: MiraOutput?, stopped: Bool)
    case ready(MiraOutput, pictures: [UUID: MiraShotPictureState])
    case needsUpdate(MiraOutput?)

    func handle(_ event: MiraTodayCardEvent) -> Self? {
        switch event {
        case .workChanged(let card, let request, let briefRevision):
            switch request {
            case .waitingToStart: return .waiting(previous: card.output)
            case .waitingToRetry: return .waitingToRetry(previous: card.output)
            case .sending, .stopping: return .making(previous: card.output, step: nil)
            case .working(_, let step): return .making(previous: card.output, step: step)
            case .needsReconnect(let reason): return .reconnect(previous: card.output, reason: reason)
            case .failed, .idle: return .failed(previous: card.output, stopped: false)
            case .stopped: return .failed(previous: card.output, stopped: true)
            case .done(let pictures):
                if let output = card.job.output, output.ideas?.count == 1, output.script != nil,
                    output.storyboard?.requirementsRevision == briefRevision {
                    return .ready(output, pictures: pictures)
                }
                return .needsUpdate(card.output)
            }
        case .make:
            if case .ready = self { return self }
        case .retry:
            switch self {
            case .failed, .ready, .needsUpdate: return self
            case .waiting, .making, .waitingToRetry, .reconnect: break
            }
        }
        return nil
    }

    var output: MiraOutput? {
        switch self {
        case .waiting(let output), .making(let output, _), .waitingToRetry(let output), .reconnect(let output, _),
            .failed(let output, _), .needsUpdate(let output): output
        case .ready(let output, _): output
        }
    }

    var ideaReady: Bool {
        switch self {
        case .making(_, .some), .ready: true
        default: false
        }
    }

    var pending: Bool {
        switch self {
        case .waiting, .making, .waitingToRetry, .reconnect: true
        case .failed, .ready, .needsUpdate: false
        }
    }

    var nextAction: MiraNextAction {
        switch self {
        case .waiting, .waitingToRetry: .stop
        case .making: .wait
        case .reconnect: .reconnect
        case .failed: .retry
        case .ready: .makeCard
        case .needsUpdate: .updateIdea
        }
    }
}
