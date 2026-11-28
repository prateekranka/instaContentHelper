enum MiraNextAction {
    case chooseIdea, writeScript, makeShots, updateShots, approveWords, startFilming
    case continueFilming, reviewPlan, wait, reconnect, stop, retry, makeCard
    case reviewProposal, editWords, retryShots, updateIdea
    case useMicrophone, openSettings, stopRecording, connectInstagram, reconnectInstagram, refreshInsights
    case reviewAIConsent, tryOpeningLibrary, updateApp, continueWork
    case enterBrief, extractRequirements, confirmRequirements, editBrief
    case makeToday, readShotList, markFilmed, finishFilming, prepareClips

    case startBrandInterview, nextQuestion, makeBrandDoc, confirmBrandDoc, editBrandDoc
    case pasteDealBrief, readDealBrief, confirmDeal, openDeal
    case joinReel, previewReel, checkReelBrief, shareReel, confirmReelPost, writeBrandNote, openWhatsApp, confirmBrandNote
    case markDealPosted, markBrandTold, markDealConfirmed, markDealPaid

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
        case .reconnectInstagram: "Connect again"
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
        case .markFilmed: "Mark filmed"
        case .finishFilming: "Finish"
        case .prepareClips: "Add your clips"
        case .joinReel: "Join your Reel"
        case .previewReel: "Watch your Reel"
        case .checkReelBrief: "Check the brief"
        case .shareReel: "Share to Instagram"
        case .confirmReelPost: "Yes, I posted it"
        case .writeBrandNote: "Write the WhatsApp note"
        case .openWhatsApp: "Open WhatsApp"
        case .confirmBrandNote: "Yes, I sent it"
        case .startBrandInterview: "Start the interview"
        case .nextQuestion: "Next"
        case .makeBrandDoc: "Make my brand doc"
        case .confirmBrandDoc: "This is me"
        case .editBrandDoc: "Edit my brand doc"
        case .pasteDealBrief: "Paste a brief"
        case .readDealBrief: "Read this brief"
        case .confirmDeal: "Looks right"
        case .openDeal: "Open deal"
        case .markDealPosted: "Mark as posted"
        case .markBrandTold: "Mark brand told"
        case .markDealConfirmed: "Mark as confirmed"
        case .markDealPaid: "Mark as paid"
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
            guard project.isApproved else { return .approving }
            guard !project.shotsNeedUpdate else { return .planning(hasShots: true) }
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
