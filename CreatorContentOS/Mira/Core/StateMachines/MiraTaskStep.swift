enum MiraTaskStepEvent {
    case opened(MiraLocation, editorSection: MiraProjectScreen, progress: MiraReelProgress, approved: Bool, hasExport: Bool)
}

enum MiraTaskStep {
    case idea
    case words(MiraNextAction)
    case shotList(MiraNextAction)
    case shoot(MiraNextAction)
    case upload
    case deliver

    func handle(_ event: MiraTaskStepEvent) -> Self {
        switch event {
        case .opened(let location, let section, let progress, let approved, let hasExport):
            switch location {
            case .todayCards:
                return .idea
            case .words:
                return .words(approved ? .reviewPlan : .approveWords)
            case .editor:
                switch section {
                case .ideas:
                    return .idea
                case .shots:
                    switch progress {
                    case .ready: return .shotList(.readShotList)
                    case .filming, .complete: return .shotList(.continueFilming)
                    default: return .shotList(progress.nextAction)
                    }
                default:
                    return .words(progress.nextAction)
                }
            case .filming:
                guard approved else { return .words(.approveWords) }
                return .shoot(progress == .complete ? .finishFilming : .markFilmed)
            case .done:
                guard approved else { return .words(.approveWords) }
                return hasExport ? .deliver : .upload
            }
        }
    }

    var number: Int {
        switch self {
        case .idea: 1
        case .words: 2
        case .shotList: 3
        case .shoot: 4
        case .upload: 5
        case .deliver: 6
        }
    }

    static let total = 6

    var title: String {
        switch self {
        case .idea: "Let's find a Reel you can make."
        case .words: "Let's get the words right."
        case .shotList: "Here's what you'll film."
        case .shoot: "Let's film your shots."
        case .upload: "Add your clips."
        case .deliver: "Your Reel is ready"
        }
    }

    var nextAction: MiraNextAction {
        switch self {
        case .idea: .chooseIdea
        case .words(let action), .shotList(let action), .shoot(let action): action
        case .upload: .prepareClips
        case .deliver: .previewReel
        }
    }
}
