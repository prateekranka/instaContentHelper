import Foundation

/// Database-backed onboarding lifecycle (`creator_profiles.onboarding_state`).
enum CreatorProfileOnboardingState: String, Codable, Hashable, Sendable {
    case new
    case partial
    case established

    init(rawDatabaseValue: String?) {
        guard let rawDatabaseValue else {
            self = .new
            return
        }
        self = CreatorProfileOnboardingState(rawValue: rawDatabaseValue) ?? .new
    }
}

/// Client presentation state for onboarding gating.
enum CreatorOnboardingPresentation: Equatable, Hashable, Sendable {
    case new
    case partial
    case established
    case loadFailed(previousEstablished: Bool)

    var shouldForceOnboardingFlow: Bool {
        switch self {
        case .new, .partial:
            return true
        case .established, .loadFailed:
            return false
        }
    }
}

enum CreatorOnboardingPresentationMapper {
    static func presentation(
        from summary: CreatorProfileSummary,
        loadFailed: Bool,
        previousPresentation: CreatorOnboardingPresentation?
    ) -> CreatorOnboardingPresentation {
        if loadFailed {
            let hadEstablished = previousPresentation == .established
                || summary.onboardingState == .established
            return .loadFailed(previousEstablished: hadEstablished)
        }

        switch summary.onboardingState {
        case .new:
            return .new
        case .partial:
            return .partial
        case .established:
            return .established
        }
    }
}

/// Confirmed onboarding record mapped for persistence and first-idea synthesis.
/// Evolves with the five-step UI; today bridges `OnboardingCompletedData`.
struct OnboardingRecord: Hashable, Sendable {
    var interestIDs: [String]
    var customSubjects: [String]
    var startingPoint: String?
    var selectedTasteExampleIDs: [String]
    var tasteExampleTitles: [String]
    var formats: [String]
    var timeToCreate: String?
    var contentLanguage: String
    var showFace: Bool?
    var useVoice: Bool?
    var contextAnswers: [String: String]
    var creatorNote: String?
    var voiceDeferred: Bool

    init(completedData: OnboardingCompletedData) {
        interestIDs = completedData.selectedCategoryIDs
        customSubjects = completedData.customSubjects
        startingPoint = completedData.startingPoint?.rawValue
        selectedTasteExampleIDs = completedData.selectedTasteExampleIDs
        tasteExampleTitles = completedData.tasteExampleTitles
        formats = completedData.formats.map(\.rawValue)
        timeToCreate = completedData.timeToCreate?.rawValue
        contentLanguage = completedData.contentLanguage
        showFace = completedData.showFace
        useVoice = completedData.useVoice
        contextAnswers = completedData.contextAnswers
        creatorNote = completedData.creatorNote
        voiceDeferred = completedData.voiceDeferred
    }

    var interestLabels: [String] {
        OnboardingInterestCatalog.displayLabels(
            interestIDs: interestIDs,
            customSubjects: customSubjects
        )
    }

    /// True when the creator chose at least one launch-A preference on the one-screen flow.
    var hasLaunchPreferences: Bool {
        !interestIDs.isEmpty
            || !customSubjects.isEmpty
            || startingPoint?.nilIfBlank != nil
            || !selectedTasteExampleIDs.isEmpty
            || !formats.isEmpty
            || timeToCreate != nil
            || showFace != nil
            || useVoice != nil
            || contextAnswers.values.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            || creatorNote?.nilIfBlank != nil
    }
}

enum OnboardingProfileMapper {
    static func profileUpdate(
        from record: OnboardingRecord,
        onboardingState: CreatorProfileOnboardingState,
        onboardingStep: Int? = nil,
        onboardingCompletedAt: String? = nil,
        firstIdeaHandoff: [String: String]? = nil
    ) -> CreatorProfileUpdate {
        let pillars = record.interestLabels
        let deferVoice = record.voiceDeferred
        let positioning = deferVoice ? "" : synthesizedPositioning(pillars: pillars, record: record)
        let voiceRules = deferVoice ? [] : synthesizedVoiceRules(record: record)
        let recurringFormats = deferVoice ? [] : VoicePrefill.recurringFormats(pillars: pillars)
        let captionStyle = deferVoice ? nil : VoicePrefill.captionStyle

        return CreatorProfileUpdate(
            positioning: positioning,
            voiceRules: voiceRules,
            contentPillars: pillars,
            captionStyle: captionStyle ?? "",
            noGoTopics: [],
            recurringFormats: recurringFormats,
            onboardingState: onboardingState,
            onboardingStep: onboardingStep,
            onboardingCompletedAt: onboardingCompletedAt,
            startingPoint: record.startingPoint,
            customSubjects: record.customSubjects,
            tasteExampleIDs: record.selectedTasteExampleIDs,
            productionFormats: record.formats,
            timeToCreate: record.timeToCreate,
            onCameraRestrictions: OnCameraRestrictionsPayload(
                showFace: record.showFace,
                useVoice: record.useVoice
            ),
            recentContext: recentContextEntries(from: record),
            creatorNote: record.creatorNote,
            firstIdeaHandoff: firstIdeaHandoff ?? [:],
            languagePreferences: ["primary": record.contentLanguage]
        )
    }

    private static func synthesizedPositioning(
        pillars: [String],
        record: OnboardingRecord
    ) -> String {
        VoicePrefill.positioning(pillars: pillars)
    }

    private static func synthesizedVoiceRules(record: OnboardingRecord) -> [String] {
        VoicePrefill.voiceRules
    }

    static func recentContextEntries(from record: OnboardingRecord) -> [[String: String]] {
        record.contextAnswers.compactMap { questionID, answer in
            let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedAnswer.isEmpty else { return nil }

            var entry: [String: String] = [
                "question_id": questionID,
                "answer": trimmedAnswer
            ]
            if let interestID = interestID(forQuestionID: questionID, selectedInterestIDs: record.interestIDs) {
                entry["interest_id"] = interestID
            }
            return entry
        }
    }

    static func interestID(forQuestionID questionID: String, selectedInterestIDs: [String]) -> String? {
        guard let prefix = questionIDPrefix(questionID) else { return nil }
        if prefix == "custom" {
            return "custom"
        }
        if let matchedInterest = selectedInterestIDs.first(where: { $0 == prefix || $0.hasPrefix("\(prefix)-") }) {
            return matchedInterest
        }
        return prefix
    }

    private static func questionIDPrefix(_ questionID: String) -> String? {
        guard let separator = questionID.firstIndex(of: "-") else { return nil }
        let prefix = String(questionID[..<separator])
        return prefix.isEmpty ? nil : prefix
    }
}

struct OnCameraRestrictionsPayload: Hashable, Sendable, Codable {
    var showFace: Bool?
    var useVoice: Bool?
}
