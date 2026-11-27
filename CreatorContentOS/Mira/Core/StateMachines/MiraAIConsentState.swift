enum MiraAIConsentEvent {
    case read(AIConsentRecord?, currentVersion: String)
}

enum MiraAIConsentState: Equatable {
    case notAsked, allowed, declined, outOfDate

    func handle(_ event: MiraAIConsentEvent) -> Self {
        switch event {
        case .read(let record, let currentVersion):
            guard let record else { return .notAsked }
            guard record.consentVersion == currentVersion else { return .outOfDate }
            switch record.decision {
            case .accepted: return .allowed
            case .declined: return .declined
            }
        }
    }

    var nextAction: MiraNextAction {
        switch self {
        case .allowed: .continueWork
        case .notAsked, .declined, .outOfDate: .reviewAIConsent
        }
    }
}
