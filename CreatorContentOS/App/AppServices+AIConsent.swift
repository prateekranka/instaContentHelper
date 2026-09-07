import Foundation

enum AIConsentSurface: Equatable {
    case generateDay(scheduledDate: String)
    case regenerateDay(scheduledDate: String)
    case planIdeas
    case storyboardThumbnails(cardID: UUID, promptIfDeclined: Bool)

    var promptsIfDeclined: Bool {
        switch self {
        case .generateDay, .regenerateDay:
            true
        case .planIdeas:
            false
        case .storyboardThumbnails(_, let promptIfDeclined):
            promptIfDeclined
        }
    }

    var logName: String {
        switch self {
        case .generateDay:
            "generate_day"
        case .regenerateDay:
            "regenerate_day"
        case .planIdeas:
            "plan_ideas"
        case .storyboardThumbnails:
            "storyboard_thumbnail"
        }
    }
}

extension AppServices {
    func requireAIConsent(for surface: AIConsentSurface) throws {
        guard isLiveSupabaseRuntime else { return }
        refreshAIConsentFlagsFromStore()
        if aiConsentAllowsOutbound { return }

        let record = aiConsentStore.load()
        let declinedCurrent = AIConsentPolicy.hasDeclinedCurrent(record)
        if !declinedCurrent || surface.promptsIfDeclined {
            isAIConsentSheetPresented = true
        }

        applyConsentBlockedMessage(for: surface)
        logAIConsentEvent("rejected", surface: surface)
        throw RepositoryError.edgeFunction(AIConsentCopy.errorCode)
    }

    func acceptAIConsent() {
        saveAIConsentDecision(.accepted)
        isAIConsentSheetPresented = false
        clearConsentBlockedMessages()
        aiConsentEpoch += 1
        logAIConsentEvent("accepted", surface: nil)
    }

    func declineAIConsent() {
        saveAIConsentDecision(.declined)
        isAIConsentSheetPresented = false
        logAIConsentEvent("declined", surface: nil)
    }

    func requestAIConsentPrompt() {
        guard !aiConsentAllowsOutbound else { return }
        isAIConsentSheetPresented = true
    }

    func setAIConsentSheetPresented(_ presented: Bool) {
        if !presented, isAIConsentSheetPresented, !aiConsentAllowsOutbound {
            let record = aiConsentStore.load()
            if !AIConsentPolicy.hasDeclinedCurrent(record) {
                saveAIConsentDecision(.declined)
                logAIConsentEvent("declined", surface: nil)
            }
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

    var canRetryAIConsent: Bool {
        !aiConsentAllowsOutbound
    }

    func refreshAIConsentFlagsFromStore() {
        aiConsentAllowsOutbound = AIConsentPolicy.allowsOutbound(aiConsentStore.load())
    }

    private func saveAIConsentDecision(_ decision: AIConsentDecision) {
        let record = AIConsentRecord(
            consentVersion: AIConsentPolicy.currentVersion,
            decision: decision,
            decidedAt: ISO8601DateFormatter().string(from: Date()),
            destinationsAcknowledged: AIConsentPolicy.destinations
        )
        aiConsentStore.save(record)
        refreshAIConsentFlagsFromStore()
    }

    private func applyConsentBlockedMessage(for surface: AIConsentSurface) {
        let message = AIConsentCopy.blockedMessage
        switch surface {
        case .generateDay(let scheduledDate):
            dayBriefGenerationErrors[scheduledDate] = message
        case .regenerateDay(let scheduledDate):
            regenerationDayErrors[scheduledDate] = message
        case .planIdeas:
            break
        case .storyboardThumbnails(let cardID, _):
            storyboardThumbnailErrors[cardID] = message
        }
    }

    private func clearConsentBlockedMessages() {
        let message = AIConsentCopy.blockedMessage
        for (date, value) in dayBriefGenerationErrors where value == message {
            dayBriefGenerationErrors[date] = nil
        }
        for (date, value) in regenerationDayErrors where value == message {
            regenerationDayErrors[date] = nil
        }
        for (cardID, value) in storyboardThumbnailErrors where value == message {
            storyboardThumbnailErrors[cardID] = nil
        }
    }

    private func logAIConsentEvent(_ action: String, surface: AIConsentSurface?) {
        var parts = [
            "ai_consent",
            action,
            "version=\(AIConsentPolicy.currentVersion)"
        ]
        if let surface {
            parts.append("surface=\(surface.logName)")
        }
        let line = "[ContentHelperGeneration] \(ISO8601DateFormatter().string(from: Date())) \(parts.joined(separator: " "))"
        print(line)
        GenerationLogFile.append(line)
    }
}
