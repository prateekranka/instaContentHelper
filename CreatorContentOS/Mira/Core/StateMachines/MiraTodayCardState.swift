enum MiraTodayCardEvent {
    case workChanged(MiraTodayCard, MiraAIRequest, briefRevision: Int)
    case make, retry
}

enum MiraTodayCardState {
    case waiting(previous: MiraOutput?)
    case making(previous: MiraOutput?)
    case reconnect(previous: MiraOutput?, reason: String?)
    case failed(previous: MiraOutput?, stopped: Bool)
    case ready(MiraOutput)
    case needsUpdate(MiraOutput?)

    func handle(_ event: MiraTodayCardEvent) -> Self? {
        switch event {
        case .workChanged(let card, let request, let briefRevision):
            switch request {
            case .waitingToStart: return .waiting(previous: card.output)
            case .sending, .working, .stopping: return .making(previous: card.output)
            case .needsReconnect(let reason): return .reconnect(previous: card.output, reason: reason)
            case .failed, .idle: return .failed(previous: card.output, stopped: false)
            case .stopped: return .failed(previous: card.output, stopped: true)
            case .done:
                if let output = card.job.output, output.ideas?.count == 1, output.script != nil,
                    output.storyboard?.requirementsRevision == briefRevision {
                    return .ready(output)
                }
                return .needsUpdate(card.output)
            }
        case .make:
            if case .ready = self { return self }
        case .retry:
            switch self {
            case .failed, .ready, .needsUpdate: return self
            case .waiting, .making, .reconnect: break
            }
        }
        return nil
    }

    var output: MiraOutput? {
        switch self {
        case .waiting(let output), .making(let output), .reconnect(let output, _),
            .failed(let output, _), .needsUpdate(let output): output
        case .ready(let output): output
        }
    }

    var pending: Bool {
        switch self {
        case .waiting, .making, .reconnect: true
        case .failed, .ready, .needsUpdate: false
        }
    }

    var nextAction: MiraNextAction {
        switch self {
        case .waiting: .stop
        case .making: .wait
        case .reconnect: .reconnect
        case .failed: .retry
        case .ready: .makeCard
        case .needsUpdate: .updateIdea
        }
    }
}
