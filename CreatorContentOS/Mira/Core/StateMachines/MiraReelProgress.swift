enum MiraNextAction {
    case chooseIdea, writeScript, makeShots, updateShots, approveWords, startFilming
    case continueFilming, reviewPlan, wait, reconnect, stop, retry, makeCard
    case reviewProposal, editWords, retryShots, updateIdea
    case useMicrophone, openSettings, stopRecording, connectInstagram, refreshInsights
    case reviewAIConsent, tryOpeningLibrary, updateApp, continueWork
    case enterBrief, extractRequirements, confirmRequirements, editBrief
    case makeToday, readShotList, prepareClips

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
        case .useMicrophone: "Use microphone"
        case .openSettings: "Open Settings"
        case .stopRecording: "Stop recording"
        case .connectInstagram: "Connect Instagram"
        case .refreshInsights: "Check again"
        case .reviewAIConsent: "Review AI permission"
        case .tryOpeningLibrary: "Try opening saved work again"
        case .updateApp: "Update Mira"
        case .continueWork: "Continue"
        case .enterBrief: "Enter brand requirements"
        case .extractRequirements: "Extract proposed requirements"
        case .confirmRequirements: "Confirm these requirements"
        case .editBrief: "Edit brand requirements"
        case .makeToday: "Make today's Reel"
        case .readShotList: "Got it, I'll go shoot"
        case .prepareClips: "Open Instagram"
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
        case .ready: .reviewPlan
        case .filming: .continueFilming
        case .complete: .reviewPlan
        }
    }
}
