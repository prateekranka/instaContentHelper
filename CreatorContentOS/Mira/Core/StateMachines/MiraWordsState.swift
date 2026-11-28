import Foundation

enum MiraWordsEvent {
    case appeared, change, note(String), cancelChange, send(String), approve, reviewPlan
    case useProposal, keepWords, retry, reconnect, stop, received, requestStarted
    case shotsApplied, shotsRejected
}

enum MiraWordsEffect {
    case reconnect, stop, applyWords, clearProposal, approve, openPlan, applyShots(MiraJob)
    case generate(MiraOperation, String, UUID?, MiraLanguage?)
}

enum MiraWordsState {
    case reviewing
    case changing(String)
    case opening
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
            if project.isApproved, job.input.operation == .reviseStoryboard, job.output?.storyboard != nil {
                if case .shotUpdateFailed(let id) = self, id == job.id { return .needsShots }
                return .applyingShots(job)
            }
        }
        if case .changing = self { return self }
        if project.isApproved, project.storyboard != nil, project.storyboardIsStale { return .needsShots }
        if let job = project.job, [.reviseScript, .reviseStoryboard].contains(job.input.operation) {
            switch request {
            case .failed, .stopped: return .retry(job)
            default: break
            }
        }
        return project.isApproved ? .ready : .reviewing
    }

    func handle(_ event: MiraWordsEvent) -> (Self, MiraWordsEffect?)? {
        switch (self, event) {
        case (.opening, .appeared), (_, .requestStarted): (.reviewing, nil)
        case (_, .appeared): (self, nil)
        case (.reviewing, .change), (.ready, .change), (.needsShots, .change), (.retry, .change):
            (.changing(""), nil)
        case (.changing, .note(let text)): (.changing(text), nil)
        case (.changing, .cancelChange): (.reviewing, nil)
        case (.changing, .send(let text)), (.reviewing, .send(let text)), (.ready, .send(let text)),
            (.needsShots, .send(let text)), (.retry, .send(let text)):
            text.isEmpty ? nil : (self, .generate(.reviseScript, text, nil, nil))
        case (.reviewing, .approve), (.retry, .approve), (.changing, .approve): (.reviewing, .approve)
        case (.ready, .reviewPlan), (.retry, .reviewPlan), (.changing, .reviewPlan):
            (.opening, .openPlan)
        case (.proposal, .useProposal): (.reviewing, .applyWords)
        case (.proposal, .keepWords), (.retry, .keepWords): (.reviewing, .clearProposal)
        case (.retry(let job), .retry):
            (.reviewing, .generate(job.input.operation, job.input.request, job.input.targetShotID,
                                   job.input.profile.language))
        case (.needsShots, .retry): (.reviewing, .generate(.reviseStoryboard, Self.shotsRequest, nil, nil))
        case (.reconnecting, .reconnect): (self, .reconnect)
        case (.reconnecting, .stop), (.waiting, .stop), (.waitingToRetry, .stop), (.writing, .stop): (self, .stop)
        case (.applyingShots(let job), .received): (self, .applyShots(job))
        case (.applyingShots, .shotsApplied): (.opening, .openPlan)
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
        case .ready: .reviewPlan
        case .opening, .stopping, .applyingShots: .wait
        case .shotUpdateFailed: .retryShots
        }
    }

    static let shotsRequest =
        "Update the words to say and the on-screen text in each shot to match my approved words. Keep the same shots, places and framing."
}
