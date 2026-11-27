enum MiraNextAction {
    case chooseIdea, writeScript, makeShots, updateShots, approveWords, startFilming
    case continueFilming, reviewPlan, wait, reconnect, stop, retry, makeCard
    case reviewProposal, editWords, retryShots, updateIdea

    var title: String {
        switch self {
        case .chooseIdea: "Choose an idea"
        case .writeScript: "Write your script"
        case .makeShots: "Make your shot list"
        case .updateShots: "Update shot list"
        case .approveWords: "Approve your words"
        case .startFilming: "Start filming"
        case .continueFilming: "Continue filming"
        case .reviewPlan: "Review your filming plan"
        case .wait: "Wait"
        case .reconnect: "Reconnect"
        case .stop: "Stop"
        case .retry: "Try again"
        case .makeCard: "Make this one"
        case .reviewProposal: "Use this"
        case .editWords: "Send"
        case .retryShots: "Try again"
        case .updateIdea: "Update this idea"
        }
    }
}

enum MiraReelProgressEvent {
    case workChanged(MiraProject)
}

enum MiraReelProgress: Equatable {
    case choosing, writing, planning(hasShots: Bool), approving, ready, filming, complete

    func handle(_ event: MiraReelProgressEvent) -> Self {
        switch event {
        case .workChanged(let project):
            guard project.selectedIdeaID != nil else { return .choosing }
            guard project.script != nil else { return .writing }
            guard let board = project.storyboard else { return .planning(hasShots: false) }
            guard !project.storyboardIsStale else { return .planning(hasShots: true) }
            guard project.isApproved else { return .approving }
            if !board.shots.isEmpty && board.shots.allSatisfy({
                project.filmed.contains($0.id) && !project.needsReview.contains($0.id)
            }) {
                return .complete
            }
            return project.startedFilming ? .filming : .ready
        }
    }

    var title: String {
        switch self {
        case .choosing: "Choosing an idea"
        case .writing: "Writing the script"
        case .planning: "Planning shots"
        case .approving: "Words to approve"
        case .ready: "Ready to film"
        case .filming: "Filming"
        case .complete: "Filming complete"
        }
    }

    var nextAction: MiraNextAction {
        switch self {
        case .choosing: .chooseIdea
        case .writing: .writeScript
        case .planning(let hasShots): hasShots ? .updateShots : .makeShots
        case .approving: .approveWords
        case .ready: .startFilming
        case .filming: .continueFilming
        case .complete: .reviewPlan
        }
    }
}
