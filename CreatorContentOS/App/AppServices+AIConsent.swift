import Foundation

extension AppServices {
    func requireAIConsent() throws {
        guard isLiveSupabaseRuntime else { return }
        refreshAIConsentFlagsFromStore()
        guard !aiConsentAllowsOutbound else { return }

        if !AIConsentPolicy.hasDeclinedCurrent(aiConsentStore.load()) {
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
            !AIConsentPolicy.hasDeclinedCurrent(aiConsentStore.load())
        {
            saveAIConsentDecision(.declined)
            logAIConsentEvent("declined")
        }
        isAIConsentSheetPresented = presented
    }

    var aiConsentStatusCopy: String {
        let record = aiConsentStore.load()
        if AIConsentPolicy.allowsOutbound(record) {
            return AIConsentCopy.statusAllowed
        }
        if AIConsentPolicy.hasDeclinedCurrent(record) {
            return AIConsentCopy.statusDeclined
        }
        return AIConsentCopy.statusUnknown
    }

    func refreshAIConsentFlagsFromStore() {
        aiConsentAllowsOutbound = AIConsentPolicy.allowsOutbound(aiConsentStore.load())
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
