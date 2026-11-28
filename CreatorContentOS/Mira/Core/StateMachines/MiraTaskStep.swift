enum MiraTaskStepEvent {
    case opened(MiraLocation, editorSection: MiraProjectScreen, approved: Bool)
}

enum MiraTaskStep {
    case idea, words, shotList, shoot, upload

    func handle(_ event: MiraTaskStepEvent) -> Self {
        switch event {
        case .opened(let location, let section, let approved):
            switch location {
            case .todayCards: .idea
            case .words: .words
            case .editor:
                switch section {
                case .ideas: .idea
                case .shots: .shotList
                default: .words
                }
            case .filming: approved ? .shoot : .words
            case .done: approved ? .upload : .words
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
        }
    }

    static let total = 6

    var title: String {
        switch self {
        case .idea: "Let's find a Reel you can make."
        case .words: "Let's get the words right."
        case .shotList: "Here's what you'll film."
        case .shoot: "Let's film your shots."
        case .upload: "Your filming is done."
        }
    }
}
