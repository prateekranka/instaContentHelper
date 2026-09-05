import Foundation

struct ContentCategoryOption: Identifiable, Hashable, Sendable {
    let id: String
    let label: String

    static let otherID = "other"

    static var catalog: [ContentCategoryOption] {
        OnboardingInterestCatalog.starter.map {
            ContentCategoryOption(id: $0.id, label: $0.label)
        }
    }
}

/// Interests + starting point + custom subjects for You editing (aligned with onboarding).
struct YouInterestsSelection: Equatable, Sendable {
    var interestIDs: [String]
    var customSubjects: [String]
    var startingPoint: OnboardingStartingPoint?

    static func from(profile: CreatorProfileSummary) -> YouInterestsSelection {
        var interestIDs: [String] = []
        var customSubjects = profile.customSubjects

        for pillar in profile.contentPillars {
            let trimmed = pillar.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let match = OnboardingInterestCatalog.starter.first(where: {
                $0.label.compare(trimmed, options: .caseInsensitive) == .orderedSame
            }) {
                if !interestIDs.contains(match.id) {
                    interestIDs.append(match.id)
                }
                continue
            }

            if !customSubjects.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                customSubjects.append(trimmed)
            }
        }

        let startingPoint = profile.startingPoint.flatMap { OnboardingStartingPoint(rawValue: $0) }

        return YouInterestsSelection(
            interestIDs: interestIDs,
            customSubjects: customSubjects,
            startingPoint: startingPoint
        )
    }

    func resolvedContentPillars() -> [String] {
        OnboardingInterestCatalog.displayLabels(
            interestIDs: interestIDs,
            customSubjects: customSubjects
        )
    }

    var summarySubtitle: String {
        let pillars = resolvedContentPillars()
        guard !pillars.isEmpty else { return "Not set" }
        if let startingPoint {
            return "\(pillars.count) topics · \(startingPoint.displayLabel)"
        }
        return "\(pillars.count) selected"
    }

    mutating func toggleInterest(_ id: String) {
        if let index = interestIDs.firstIndex(of: id) {
            interestIDs.remove(at: index)
            return
        }
        guard totalCount < OnboardingValidation.maxTotalInterests else { return }
        interestIDs.append(id)
    }

    mutating func addCustomSubject(_ subject: String) {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard totalCount < OnboardingValidation.maxTotalInterests else { return }
        guard !customSubjects.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        customSubjects.append(trimmed)
    }

    mutating func removeCustomSubject(_ subject: String) {
        customSubjects.removeAll { $0 == subject }
    }

    mutating func setStartingPoint(_ point: OnboardingStartingPoint) {
        startingPoint = startingPoint == point ? nil : point
    }

    var totalCount: Int {
        interestIDs.count + customSubjects.count
    }

    var isValid: Bool {
        OnboardingValidation.interestsAreValid(
            interestIDs: interestIDs,
            customSubjects: customSubjects
        )
    }

    func profileUpdate(base: CreatorProfileSummary) -> CreatorProfileUpdate {
        var update = CreatorProfileUpdate(youEditorFields: base)
        update.contentPillars = resolvedContentPillars()
        update.customSubjects = customSubjects
        update.startingPoint = startingPoint?.rawValue
        return update
    }
}

/// Production preferences for You editing.
struct YouProductionSelection: Equatable, Sendable {
    var formats: [OnboardingProductionFormat]
    var timeToCreate: OnboardingTimeToCreate?
    var contentLanguage: String
    var showFace: Bool?
    var useVoice: Bool?

    static func from(profile: CreatorProfileSummary) -> YouProductionSelection {
        let formats = profile.productionFormats.compactMap { OnboardingProductionFormat(rawValue: $0) }
        let time = profile.timeToCreate.flatMap { OnboardingTimeToCreate(rawValue: $0) }
        return YouProductionSelection(
            formats: formats,
            timeToCreate: time,
            contentLanguage: profile.contentLanguage,
            showFace: profile.onCameraRestrictions.showFace,
            useVoice: profile.onCameraRestrictions.useVoice
        )
    }

    var summarySubtitle: String {
        guard !formats.isEmpty, timeToCreate != nil else { return "Not set" }
        let formatLabels = formats.map(\.displayLabel).joined(separator: ", ")
        let timeLabel = timeToCreate.map(\.displayLabel) ?? ""
        return "\(formatLabels) · \(timeLabel)"
    }

    var isValid: Bool {
        OnboardingValidation.productionIsValid(
            formats: formats,
            timeToCreate: timeToCreate,
            contentLanguage: contentLanguage,
            showFace: showFace,
            useVoice: useVoice
        )
    }

    func profileUpdate(base: CreatorProfileSummary) -> CreatorProfileUpdate {
        var update = CreatorProfileUpdate(youEditorFields: base)
        update.productionFormats = formats.map(\.rawValue)
        update.timeToCreate = timeToCreate?.rawValue
        update.onCameraRestrictions = OnCameraRestrictionsPayload(
            showFace: showFace,
            useVoice: useVoice
        )
        update.languagePreferences = ["primary": contentLanguage]
        return update
    }
}

/// Context answers + optional note for You editing.
struct YouContextSelection: Equatable, Sendable {
    var contextAnswers: [String: String]
    var creatorNote: String

    static func from(profile: CreatorProfileSummary) -> YouContextSelection {
        var answers: [String: String] = [:]
        for entry in profile.recentContext {
            guard let questionID = entry["question_id"],
                  let answer = entry["answer"]
            else { continue }
            answers[questionID] = answer
        }
        return YouContextSelection(
            contextAnswers: answers,
            creatorNote: profile.creatorNote ?? ""
        )
    }

    var summarySubtitle: String {
        let filled = contextAnswers.values.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        if filled == 0, creatorNote.nilIfBlank == nil {
            return "Not set"
        }
        if filled == 0 {
            return "Note saved"
        }
        return "\(filled) answer\(filled == 1 ? "" : "s") saved"
    }

    func profileUpdate(
        base: CreatorProfileSummary,
        interestIDs: [String],
        customSubjects: [String]
    ) -> CreatorProfileUpdate {
        let record = OnboardingRecord(completedData: OnboardingCompletedData(
            selectedCategoryIDs: interestIDs,
            customSubjects: customSubjects,
            contextAnswers: contextAnswers,
            creatorNote: creatorNote.nilIfBlank,
            references: [],
            voiceDeferred: false
        ))
        var update = CreatorProfileUpdate(youEditorFields: base)
        update.recentContext = OnboardingProfileMapper.recentContextEntries(from: record)
        update.creatorNote = creatorNote.nilIfBlank
        return update
    }
}

/// Legacy three-category picker kept for Plan subtitle helpers.
struct ContentCategorySelection: Equatable, Sendable {
    var selectedIDs: [String]
    var customOtherLabel: String

    static let maxSelectionCount = 3

    static func from(contentPillars: [String]) -> ContentCategorySelection {
        let interests = YouInterestsSelection.from(
            profile: CreatorProfileSummary(
                displayName: "",
                positioning: "",
                voiceLine: "",
                noGoTopics: [],
                contentPillars: contentPillars
            )
        )
        var selectedIDs = Array(interests.interestIDs.prefix(maxSelectionCount))
        var customOtherLabel = ""
        if let firstCustom = interests.customSubjects.first, selectedIDs.count < maxSelectionCount {
            selectedIDs.append(ContentCategoryOption.otherID)
            customOtherLabel = firstCustom
        }
        return ContentCategorySelection(selectedIDs: selectedIDs, customOtherLabel: customOtherLabel)
    }

    func resolvedContentPillars() -> [String] {
        selectedIDs.compactMap { id in
            if id == ContentCategoryOption.otherID {
                let trimmed = customOtherLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return ContentCategoryOption.catalog.first(where: { $0.id == id })?.label
        }
    }

    func label(for id: String) -> String? {
        ContentCategoryOption.catalog.first(where: { $0.id == id })?.label
    }

    var summarySubtitle: String {
        YouInterestsSelection.from(
            profile: CreatorProfileSummary(
                displayName: "",
                positioning: "",
                voiceLine: "",
                noGoTopics: [],
                contentPillars: resolvedContentPillars()
            )
        ).summarySubtitle
    }

    mutating func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.removeAll { $0 == id }
            if id == ContentCategoryOption.otherID {
                customOtherLabel = ""
            }
            return
        }

        guard selectedIDs.count < Self.maxSelectionCount else { return }
        selectedIDs.append(id)
    }

    var includesOther: Bool {
        selectedIDs.contains(ContentCategoryOption.otherID)
    }

    var isValid: Bool {
        guard !selectedIDs.isEmpty, selectedIDs.count <= Self.maxSelectionCount else { return false }
        if includesOther {
            return !customOtherLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }
}
