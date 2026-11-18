import Foundation

extension AppServices {
    func requireAIConsent() throws {
        guard isLiveSupabaseRuntime else { return }
        refreshAIConsentFlagsFromStore()
        guard !aiConsentAllowsOutbound else { return }

        if !aiConsentHasDeclined {
            isAIConsentSheetPresented = true
        }
        logAIConsentEvent("rejected")
        throw MiraError.invalid(AIConsentCopy.blockedMessage)
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
        if !presented, isAIConsentSheetPresented, !aiConsentAllowsOutbound,
            !aiConsentHasDeclined
        {
            saveAIConsentDecision(.declined)
            logAIConsentEvent("declined")
        }
        isAIConsentSheetPresented = presented
    }

    var aiConsentStatusCopy: String {
        if aiConsentAllowsOutbound {
            return AIConsentCopy.statusAllowed
        }
        if aiConsentHasDeclined {
            return AIConsentCopy.statusDeclined
        }
        return AIConsentCopy.statusUnknown
    }

    func refreshAIConsentFlagsFromStore() {
        let record = aiConsentStore.load()
        aiConsentAllowsOutbound = AIConsentPolicy.allowsOutbound(record)
        aiConsentHasDeclined = AIConsentPolicy.hasDeclinedCurrent(record)
    }

    private func saveAIConsentDecision(_ decision: AIConsentDecision) {
        aiConsentStore.save(
            AIConsentRecord(
                consentVersion: AIConsentPolicy.currentVersion,
                decision: decision,
                decidedAt: SupabaseDateFormatting.isoTimestampString(),
                destinationsAcknowledged: AIConsentPolicy.destinations))
        refreshAIConsentFlagsFromStore()
    }

    private func logAIConsentEvent(_ action: String) {
        print("[ContentHelperGeneration] \(SupabaseDateFormatting.isoTimestampString()) ai_consent \(action) version=\(AIConsentPolicy.currentVersion)")
    }
}
