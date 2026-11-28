import Foundation

extension AppServices {
    func requireAIConsent() throws {
        guard isLiveSupabaseRuntime else { return }
        refreshAIConsent()
        switch aiConsent {
        case .allowed: return
        case .notAsked, .outOfDate: isAIConsentSheetPresented = true
        case .declined: break
        }
        logAIConsentEvent("rejected")
        throw AIConsentRequired()
    }

    func acceptAIConsent() {
        saveAIConsentDecision(.accepted)
        isAIConsentSheetPresented = false
        logAIConsentEvent("accepted")
    }

    func declineAIConsent() {
        saveAIConsentDecision(.declined)
        isAIConsentSheetPresented = false
        logAIConsentEvent("declined")
    }

    func setAIConsentSheetPresented(_ presented: Bool) {
        if !presented, isAIConsentSheetPresented, aiConsent != .allowed, aiConsent != .declined
        {
            saveAIConsentDecision(.declined)
            logAIConsentEvent("declined")
        }
        isAIConsentSheetPresented = presented
    }

    var aiConsentStatusCopy: String {
        switch aiConsent {
        case .allowed: AIConsentCopy.statusAllowed
        case .declined: AIConsentCopy.statusDeclined
        case .notAsked: AIConsentCopy.statusUnknown
        case .outOfDate: "Review needed"
        }
    }

    private func saveAIConsentDecision(_ decision: AIConsentDecision) {
        aiConsentStore.save(
            AIConsentRecord(
                consentVersion: AIConsentPolicy.currentVersion,
                decision: decision,
                decidedAt: SupabaseDateFormatting.isoTimestampString(),
                destinationsAcknowledged: AIConsentPolicy.destinations))
        refreshAIConsent()
    }

    private func logAIConsentEvent(_ action: String) {
        print("[ContentHelperGeneration] \(SupabaseDateFormatting.isoTimestampString()) ai_consent \(action) version=\(AIConsentPolicy.currentVersion)")
    }
}
