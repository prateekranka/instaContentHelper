import Foundation

enum MiraWordsEvent {
    case appeared, change, note(String), cancelChange, send(String), approve, startFilming
    case useProposal, keepWords, retry, reconnect, stop, received, requestStarted(UUID?)
    case shotsApplied, shotsRejected
}

enum MiraWordsEffect {
    case reconnect, stop, applyWords, clearProposal, approve, openFilming, applyShots(MiraJob)
    case generate(MiraOperation, String, UUID?, MiraLanguage?)
}

enum MiraWordsState {
    case reviewing
    case changing(String)
    case opening
    case updatingShots(UUID)
    case shotUpdateFailed(UUID)
    case waiting
    case waitingToRetry
    case writing(MiraOperation)
    case reconnecting
    case stopping
    case proposal(MiraScript)
    case retry(MiraJob)
    case needsShots
    case applyingShots(MiraJob)
    case ready

    func presentation(for project: MiraProject, request: MiraAIRequest) -> Self {
        if case .opening = self { return .opening }
        switch request {
        case .waitingToStart: return .waiting
        case .waitingToRetry: return .waitingToRetry
        case .sending, .working: return .writing(project.job?.input.operation ?? .reviseScript)
        case .needsReconnect: return .reconnecting
        case .stopping: return .stopping
        case .idle, .failed, .stopped, .done: break
        }
        if case .done = request, let job = project.job {
            if job.input.operation == .reviseScript, let script = job.output?.script {
                return .proposal(script)
            }
            if case .updatingShots(let id) = self, id == job.id, project.isApproved,
                job.input.operation == .reviseStoryboard, job.output != nil {
                return .applyingShots(job)
            }
        }
        if case .shotUpdateFailed(let id) = self, id == project.job?.id, project.isApproved {
            return .needsShots
        }
        if project.isApproved, !project.canFilm { return .needsShots }
        if case .changing = self { return self }
        if let job = project.job, job.input.operation == .reviseScript {
            switch request {
            case .failed, .stopped: return .retry(job)
            default: break
            }
        }
        return project.isApproved ? .ready : .reviewing
    }

    func handle(_ event: MiraWordsEvent) -> (Self, MiraWordsEffect?)? {
        switch (self, event) {
        case (.opening, .appeared), (_, .requestStarted(nil)): (.reviewing, nil)
        case (_, .requestStarted(let id?)): (.updatingShots(id), nil)
        case (_, .appeared): (self, nil)
        case (.reviewing, .change), (.ready, .change):
            (.changing(""), nil)
        case (.changing, .note(let text)): (.changing(text), nil)
        case (.changing, .cancelChange): (.reviewing, nil)
        case (.changing, .send(let text)), (.reviewing, .send(let text)), (.ready, .send(let text)):
            text.isEmpty ? nil : (self, .generate(.reviseScript, text, nil, nil))
        case (.reviewing, .approve): (.reviewing, .approve)
        case (.ready, .startFilming):
            (.opening, .openFilming)
        case (.proposal, .useProposal): (.reviewing, .applyWords)
        case (.proposal, .keepWords), (.retry, .keepWords): (.reviewing, .clearProposal)
        case (.retry(let job), .retry):
            (.reviewing, .generate(job.input.operation, job.input.request, job.input.targetShotID,
                                   job.input.profile.language))
        case (.needsShots, .retry): (.reviewing, .generate(.reviseStoryboard, Self.shotsRequest, nil, nil))
        case (.reconnecting, .reconnect): (self, .reconnect)
        case (.reconnecting, .stop), (.waiting, .stop), (.waitingToRetry, .stop), (.writing, .stop): (self, .stop)
        case (.applyingShots(let job), .received): (self, .applyShots(job))
        case (.applyingShots, .shotsApplied): (.opening, .openFilming)
        case (.applyingShots(let job), .shotsRejected): (.shotUpdateFailed(job.id), nil)
        default: nil
        }
    }

    var nextAction: MiraNextAction? {
        switch self {
        case .reviewing: .approveWords
        case .changing: .editWords
        case .waiting, .waitingToRetry, .writing: .stop
        case .reconnecting: .reconnect
        case .proposal: .reviewProposal
        case .retry: .retry
        case .needsShots: .retryShots
        case .ready: .startFilming
        case .opening, .stopping, .applyingShots, .updatingShots: .wait
        case .shotUpdateFailed: .retryShots
        }
    }

    static let shotsRequest =
        "Update the words to say and the on-screen text in each shot to match my approved words. Keep the same shots, places and framing."
}
