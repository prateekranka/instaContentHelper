import Foundation
import SwiftUI

// MARK: - Steps

enum OnboardingStep: Int, Codable, Hashable, Sendable, CaseIterable {
    case interests = 0
    case tasteExamples = 1
    case productionConstraints = 2
    case interestContext = 3
    case review = 4

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(Int.self)
        switch raw {
        case 0: self = .interests
        case 1: self = .tasteExamples
        case 2: self = .productionConstraints
        case 3: self = .interestContext
        case 4: self = .review
        default: self = .interests
        }
    }
}

// MARK: - Language default

enum OnboardingLanguageDefaults {
    static var preferredContentLanguage: String {
        guard let code = Locale.current.language.languageCode?.identifier else {
            return "English"
        }
        let locale = Locale.current
        if let name = locale.localizedString(forLanguageCode: code)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name.capitalized(with: locale)
        }
        return "English"
    }
}

// MARK: - Onboarding theme (scoped tokens)

enum OnboardingTheme {
    static let selectionFill = SwiftUI.Color(hex: 0xE8DEFF)
    static let selectionStroke = SwiftUI.Color(hex: 0xD4C4F0)
    static let startingPointFill = SwiftUI.Color(hex: 0xF0EBFF)
    static let startingPointStroke = SwiftUI.Color(hex: 0xB8A4E8)
    static let progressFill = PocketSheetTheme.Color.ink
    static let progressTrack = PocketSheetTheme.Color.hairline
}

// MARK: - Interest catalog

struct OnboardingInterestOption: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
}

enum OnboardingInterestCatalog {
    static let starter: [OnboardingInterestOption] = [
        OnboardingInterestOption(id: "lifestyle", label: "Lifestyle"),
        OnboardingInterestOption(id: "fitness-wellness", label: "Fitness & Wellness"),
        OnboardingInterestOption(id: "books", label: "Books"),
        OnboardingInterestOption(id: "movies-tv", label: "Movies & TV"),
        OnboardingInterestOption(id: "fashion-beauty", label: "Fashion & Beauty"),
        OnboardingInterestOption(id: "food-cooking", label: "Food & Cooking"),
        OnboardingInterestOption(id: "travel", label: "Travel"),
        OnboardingInterestOption(id: "business-career", label: "Business & Career"),
        OnboardingInterestOption(id: "gaming", label: "Gaming"),
        OnboardingInterestOption(id: "art-creativity", label: "Art & Creativity"),
        OnboardingInterestOption(id: "parenting", label: "Parenting"),
    ]

    static func label(for id: String) -> String {
        starter.first(where: { $0.id == id })?.label ?? id
    }

    static func displayLabels(interestIDs: [String], customSubjects: [String]) -> [String] {
        var labels = interestIDs.map { label(for: $0) }
        for subject in customSubjects {
            let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !labels.contains(trimmed) else { continue }
            labels.append(trimmed)
        }
        return labels
    }
}

/// Legacy alias kept for reference import and tests.
enum OnboardingCategories {
    static let otherID = "other"
    static var starter: [OnboardingCategoryOption] {
        OnboardingInterestCatalog.starter.map {
            OnboardingCategoryOption(id: $0.id, label: $0.label)
        }
    }

    static func label(for id: String, otherText: String) -> String {
        if id == otherID {
            let trimmed = otherText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Other" : trimmed
        }
        return OnboardingInterestCatalog.label(for: id)
    }

    static func displayLabels(selectedIDs: [String], otherText: String) -> [String] {
        let customs = otherText.nilIfBlank.map { [$0] } ?? []
        return OnboardingInterestCatalog.displayLabels(interestIDs: selectedIDs, customSubjects: customs)
    }
}

struct OnboardingCategoryOption: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
}

// MARK: - Starting point

enum OnboardingStartingPoint: String, Codable, Hashable, Sendable, CaseIterable {
    case justStarting = "just_starting"
    case alreadyPosting = "already_posting"

    var displayLabel: String {
        switch self {
        case .justStarting: "Just starting"
        case .alreadyPosting: "Already posting"
        }
    }
}

// MARK: - Production

enum OnboardingProductionFormat: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case talkingToCamera = "talking_to_camera"
    case voiceoverBroll = "voiceover_broll"
    case textLed = "text_led"
    case photoCarousel = "photo_carousel"

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .talkingToCamera: "Talking to camera"
        case .voiceoverBroll: "Voiceover (with b-roll)"
        case .textLed: "Text-led videos"
        case .photoCarousel: "Photo / carousel posts"
        }
    }

    var symbolName: String {
        switch self {
        case .talkingToCamera: "mic.fill"
        case .voiceoverBroll: "film"
        case .textLed: "text.bubble"
        case .photoCarousel: "photo.on.rectangle.angled"
        }
    }
}

enum OnboardingTimeToCreate: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case fiveToTen = "five_to_ten"
    case tenToThirty = "ten_to_thirty"
    case thirtyPlus = "thirty_plus"

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .fiveToTen: "5–10 min"
        case .tenToThirty: "10–30 min"
        case .thirtyPlus: "30+ min"
        }
    }
}

// MARK: - Taste examples

enum OnboardingTasteStyle: String, Codable, Hashable, Sendable {
    case recommendation
    case opinion
    case personalHumour = "personal_humour"
}

struct OnboardingTasteExample: Identifiable, Hashable, Sendable {
    let id: String
    let interestID: String
    let title: String
    let style: OnboardingTasteStyle
}

// MARK: - References (You import — not a required onboarding step)

enum OnboardingReferenceKind: String, Codable, Hashable, Sendable {
    case reel
    case profile
}

struct OnboardingReference: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var kind: OnboardingReferenceKind
    var label: String
    var key: String
    var url: String

    var isReel: Bool { kind == .reel }
    var isProfile: Bool { kind == .profile }

    var listDisplayLabel: String {
        isProfile ? label : "▶ \(label)"
    }
}

enum OnboardingReferenceInputKind: String, Hashable, Sendable {
    case reel
    case profile
}

// MARK: - Profile verification

enum OnboardingProfileVerificationStatus: String, Codable, Hashable, Sendable {
    case verified
    case notFound = "not_found"
    case temporarilyUnavailable = "temporarily_unavailable"
}

struct OnboardingProfileVerificationResult: Hashable, Sendable {
    var status: OnboardingProfileVerificationStatus
    var handle: String
    var url: String
    var diagnosticReason: String?
}

struct OnboardingReferenceValidationFlags: Equatable, Sendable {
    var reel: Bool = false
    var profile: Bool = false
    var motion: Bool = false

    static let none = Self()
}

// MARK: - Confirm state

enum OnboardingFirstIdeaConfirmState: Equatable, Sendable {
    case idle
    case preparing
    case persistFailed
    case generationFailed(message: String)
    case succeeded
}

// MARK: - Persisted progress / completion

struct OnboardingProgress: Codable, Hashable, Sendable {
    var step: OnboardingStep
    var interestIDs: [String]
    var customSubjects: [String]
    var startingPoint: OnboardingStartingPoint?
    var selectedTasteExampleIDs: [String]
    var tasteRefreshCount: Int
    var formats: [OnboardingProductionFormat]
    var timeToCreate: OnboardingTimeToCreate?
    var contentLanguage: String
    var showFace: Bool?
    var useVoice: Bool?
    var contextAnswers: [String: String]
    var creatorNote: String
    /// Legacy reference step data; preserved for decode only.
    var references: [OnboardingReference]

    enum CodingKeys: String, CodingKey {
        case step
        case interestIDs
        case customSubjects
        case startingPoint
        case selectedTasteExampleIDs
        case tasteRefreshCount
        case formats
        case timeToCreate
        case contentLanguage
        case showFace
        case useVoice
        case contextAnswers
        case creatorNote
        case references
        case selectedCategoryIDs
        case categoryOtherText
    }

    static let empty = Self(
        step: .interests,
        interestIDs: [],
        customSubjects: [],
        startingPoint: nil,
        selectedTasteExampleIDs: [],
        tasteRefreshCount: 0,
        formats: [],
        timeToCreate: nil,
        contentLanguage: OnboardingLanguageDefaults.preferredContentLanguage,
        showFace: nil,
        useVoice: nil,
        contextAnswers: [:],
        creatorNote: "",
        references: []
    )

    init(
        step: OnboardingStep,
        interestIDs: [String],
        customSubjects: [String],
        startingPoint: OnboardingStartingPoint?,
        selectedTasteExampleIDs: [String],
        tasteRefreshCount: Int,
        formats: [OnboardingProductionFormat],
        timeToCreate: OnboardingTimeToCreate?,
        contentLanguage: String,
        showFace: Bool?,
        useVoice: Bool?,
        contextAnswers: [String: String],
        creatorNote: String,
        references: [OnboardingReference]
    ) {
        self.step = step
        self.interestIDs = interestIDs
        self.customSubjects = customSubjects
        self.startingPoint = startingPoint
        self.selectedTasteExampleIDs = selectedTasteExampleIDs
        self.tasteRefreshCount = tasteRefreshCount
        self.formats = formats
        self.timeToCreate = timeToCreate
        self.contentLanguage = contentLanguage
        self.showFace = showFace
        self.useVoice = useVoice
        self.contextAnswers = contextAnswers
        self.creatorNote = creatorNote
        self.references = references
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        step = try container.decode(OnboardingStep.self, forKey: .step)
        if let ids = try container.decodeIfPresent([String].self, forKey: .interestIDs) {
            interestIDs = ids
        } else {
            interestIDs = try container.decodeIfPresent([String].self, forKey: .selectedCategoryIDs) ?? []
        }
        if let customs = try container.decodeIfPresent([String].self, forKey: .customSubjects) {
            customSubjects = customs
        } else if let other = try container.decodeIfPresent(String.self, forKey: .categoryOtherText),
                  let trimmed = other.nilIfBlank {
            customSubjects = [trimmed]
        } else {
            customSubjects = []
        }
        startingPoint = try container.decodeIfPresent(OnboardingStartingPoint.self, forKey: .startingPoint)
        selectedTasteExampleIDs = try container.decodeIfPresent([String].self, forKey: .selectedTasteExampleIDs) ?? []
        tasteRefreshCount = try container.decodeIfPresent(Int.self, forKey: .tasteRefreshCount) ?? 0
        formats = try container.decodeIfPresent([OnboardingProductionFormat].self, forKey: .formats) ?? []
        timeToCreate = try container.decodeIfPresent(OnboardingTimeToCreate.self, forKey: .timeToCreate)
        contentLanguage = try container.decodeIfPresent(String.self, forKey: .contentLanguage)
            ?? OnboardingLanguageDefaults.preferredContentLanguage
        showFace = try container.decodeIfPresent(Bool.self, forKey: .showFace)
        useVoice = try container.decodeIfPresent(Bool.self, forKey: .useVoice)
        contextAnswers = try container.decodeIfPresent([String: String].self, forKey: .contextAnswers) ?? [:]
        creatorNote = try container.decodeIfPresent(String.self, forKey: .creatorNote) ?? ""
        references = try container.decodeIfPresent([OnboardingReference].self, forKey: .references) ?? []

        if step == .productionConstraints, !references.isEmpty, formats.isEmpty {
            step = .review
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(step, forKey: .step)
        try container.encode(interestIDs, forKey: .interestIDs)
        try container.encode(customSubjects, forKey: .customSubjects)
        try container.encodeIfPresent(startingPoint, forKey: .startingPoint)
        try container.encode(selectedTasteExampleIDs, forKey: .selectedTasteExampleIDs)
        try container.encode(tasteRefreshCount, forKey: .tasteRefreshCount)
        try container.encode(formats, forKey: .formats)
        try container.encodeIfPresent(timeToCreate, forKey: .timeToCreate)
        try container.encode(contentLanguage, forKey: .contentLanguage)
        try container.encodeIfPresent(showFace, forKey: .showFace)
        try container.encodeIfPresent(useVoice, forKey: .useVoice)
        try container.encode(contextAnswers, forKey: .contextAnswers)
        try container.encode(creatorNote, forKey: .creatorNote)
        try container.encode(references, forKey: .references)
    }
}

struct OnboardingCompletedData: Codable, Hashable, Sendable {
    var selectedCategoryIDs: [String]
    var customSubjects: [String]
    var startingPoint: OnboardingStartingPoint?
    var selectedTasteExampleIDs: [String]
    var tasteExampleTitles: [String]
    var formats: [OnboardingProductionFormat]
    var timeToCreate: OnboardingTimeToCreate?
    var contentLanguage: String
    var showFace: Bool?
    var useVoice: Bool?
    var contextAnswers: [String: String]
    var creatorNote: String?
    var references: [OnboardingReference]
    var voiceDeferred: Bool
    var voicePrefilled: Bool? = nil

    /// Legacy single-other field for older callers.
    var categoryOtherText: String {
        customSubjects.first ?? ""
    }

    var categoryLabels: [String] {
        OnboardingInterestCatalog.displayLabels(
            interestIDs: selectedCategoryIDs,
            customSubjects: customSubjects
        )
    }

    enum CodingKeys: String, CodingKey {
        case selectedCategoryIDs
        case customSubjects
        case categoryOtherText
        case startingPoint
        case selectedTasteExampleIDs
        case tasteExampleTitles
        case formats
        case timeToCreate
        case contentLanguage
        case showFace
        case useVoice
        case contextAnswers
        case creatorNote
        case references
        case voiceDeferred
        case voicePrefilled
    }

    init(
        selectedCategoryIDs: [String],
        customSubjects: [String] = [],
        startingPoint: OnboardingStartingPoint? = nil,
        selectedTasteExampleIDs: [String] = [],
        tasteExampleTitles: [String] = [],
        formats: [OnboardingProductionFormat] = [],
        timeToCreate: OnboardingTimeToCreate? = nil,
        contentLanguage: String = OnboardingLanguageDefaults.preferredContentLanguage,
        showFace: Bool? = nil,
        useVoice: Bool? = nil,
        contextAnswers: [String: String] = [:],
        creatorNote: String? = nil,
        references: [OnboardingReference] = [],
        voiceDeferred: Bool,
        voicePrefilled: Bool? = nil
    ) {
        self.selectedCategoryIDs = selectedCategoryIDs
        self.customSubjects = customSubjects
        self.startingPoint = startingPoint
        self.selectedTasteExampleIDs = selectedTasteExampleIDs
        self.tasteExampleTitles = tasteExampleTitles
        self.formats = formats
        self.timeToCreate = timeToCreate
        self.contentLanguage = contentLanguage
        self.showFace = showFace
        self.useVoice = useVoice
        self.contextAnswers = contextAnswers
        self.creatorNote = creatorNote
        self.references = references
        self.voiceDeferred = voiceDeferred
        self.voicePrefilled = voicePrefilled
    }

    /// Legacy initializer for callers that still pass a single `categoryOtherText` slot.
    init(
        selectedCategoryIDs: [String],
        categoryOtherText: String,
        references: [OnboardingReference],
        voiceDeferred: Bool,
        voicePrefilled: Bool? = nil
    ) {
        self.init(
            selectedCategoryIDs: selectedCategoryIDs,
            customSubjects: categoryOtherText.nilIfBlank.map { [$0] } ?? [],
            references: references,
            voiceDeferred: voiceDeferred,
            voicePrefilled: voicePrefilled
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedCategoryIDs = try container.decode([String].self, forKey: .selectedCategoryIDs)
        if let customs = try container.decodeIfPresent([String].self, forKey: .customSubjects) {
            customSubjects = customs
        } else if let other = try container.decodeIfPresent(String.self, forKey: .categoryOtherText),
                  let trimmed = other.nilIfBlank {
            customSubjects = [trimmed]
        } else {
            customSubjects = []
        }
        startingPoint = try container.decodeIfPresent(OnboardingStartingPoint.self, forKey: .startingPoint)
        selectedTasteExampleIDs = try container.decodeIfPresent([String].self, forKey: .selectedTasteExampleIDs) ?? []
        tasteExampleTitles = try container.decodeIfPresent([String].self, forKey: .tasteExampleTitles) ?? []
        formats = try container.decodeIfPresent([OnboardingProductionFormat].self, forKey: .formats) ?? []
        timeToCreate = try container.decodeIfPresent(OnboardingTimeToCreate.self, forKey: .timeToCreate)
        contentLanguage = try container.decodeIfPresent(String.self, forKey: .contentLanguage) ?? "English"
        showFace = try container.decodeIfPresent(Bool.self, forKey: .showFace)
        useVoice = try container.decodeIfPresent(Bool.self, forKey: .useVoice)
        contextAnswers = try container.decodeIfPresent([String: String].self, forKey: .contextAnswers) ?? [:]
        creatorNote = try container.decodeIfPresent(String.self, forKey: .creatorNote)
        references = try container.decodeIfPresent([OnboardingReference].self, forKey: .references) ?? []
        voiceDeferred = try container.decode(Bool.self, forKey: .voiceDeferred)
        voicePrefilled = try container.decodeIfPresent(Bool.self, forKey: .voicePrefilled)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedCategoryIDs, forKey: .selectedCategoryIDs)
        try container.encode(customSubjects, forKey: .customSubjects)
        try container.encodeIfPresent(startingPoint, forKey: .startingPoint)
        try container.encode(selectedTasteExampleIDs, forKey: .selectedTasteExampleIDs)
        try container.encode(tasteExampleTitles, forKey: .tasteExampleTitles)
        try container.encode(formats, forKey: .formats)
        try container.encodeIfPresent(timeToCreate, forKey: .timeToCreate)
        try container.encode(contentLanguage, forKey: .contentLanguage)
        try container.encodeIfPresent(showFace, forKey: .showFace)
        try container.encodeIfPresent(useVoice, forKey: .useVoice)
        try container.encode(contextAnswers, forKey: .contextAnswers)
        try container.encodeIfPresent(creatorNote, forKey: .creatorNote)
        try container.encode(references, forKey: .references)
        try container.encode(voiceDeferred, forKey: .voiceDeferred)
        try container.encodeIfPresent(voicePrefilled, forKey: .voicePrefilled)
    }
}

// MARK: - Voice prefill (post-onboarding UI draft only)

enum VoicePrefill {
    static func positioning(pillars: [String]) -> String {
        let pillarsText = pillars.isEmpty ? "everyday life" : pillars.joined(separator: ", ")
        return "A creator sharing real \(pillarsText) — honest, warm, and down to earth, paced like your saved references."
    }

    static let voiceRules: [String] = [
        "No hype words.",
        "Short, honest sentences.",
        "Show the moment before the lesson."
    ]

    static let captionStyle: String = "One honest line. Rare emoji. One clear ask at the end."

    static func recurringFormats(pillars: [String]) -> [String] {
        pillars.isEmpty ? ["Everyday moments", "Quick tips", "Honest behind-the-scenes"] : pillars
    }

    static func pillarLabels(from completedData: OnboardingCompletedData) -> [String] {
        completedData.categoryLabels
    }
}

// MARK: - Pure validation

enum OnboardingValidation {
    static let maxTotalInterests = 8
    static let maxReferences = 10

    static func interestsAreValid(interestIDs: [String], customSubjects: [String]) -> Bool {
        let trimmedCustoms = customSubjects
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !interestIDs.isEmpty || !trimmedCustoms.isEmpty else { return false }
        return interestIDs.count + trimmedCustoms.count <= maxTotalInterests
    }

    static func startingPointIsValid(_ startingPoint: OnboardingStartingPoint?) -> Bool {
        startingPoint != nil
    }

    static func interestsStepIsValid(
        interestIDs: [String],
        customSubjects: [String],
        startingPoint: OnboardingStartingPoint?
    ) -> Bool {
        interestsAreValid(interestIDs: interestIDs, customSubjects: customSubjects)
            && startingPointIsValid(startingPoint)
    }

    static func tasteIsValid(selectedExampleIDs: [String], refreshCount: Int) -> Bool {
        !selectedExampleIDs.isEmpty || refreshCount > 0
    }

    static func productionIsValid(
        formats: [OnboardingProductionFormat],
        timeToCreate: OnboardingTimeToCreate?,
        contentLanguage: String,
        showFace: Bool?,
        useVoice: Bool?
    ) -> Bool {
        guard !formats.isEmpty else { return false }
        guard timeToCreate != nil else { return false }
        guard !contentLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard showFace != nil, useVoice != nil else { return false }
        return true
    }

    static func contextIsValid(
        promptedQuestionIDs: [String],
        answers: [String: String]
    ) -> Bool {
        for questionID in promptedQuestionIDs {
            let answer = answers[questionID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if answer.isEmpty { return false }
        }
        return true
    }

    // Legacy reference validation (You import)

    static let maxCategories = 3

    static func categoriesAreValid(selectedIDs: [String], otherText: String) -> Bool {
        guard !selectedIDs.isEmpty, selectedIDs.count <= maxCategories else { return false }
        if selectedIDs.contains(OnboardingCategories.otherID) {
            return !otherText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    static func reelCount(in references: [OnboardingReference]) -> Int {
        references.filter(\.isReel).count
    }

    static func profileCount(in references: [OnboardingReference]) -> Int {
        references.filter(\.isProfile).count
    }

    static func missingReferenceKinds(in references: [OnboardingReference]) -> [OnboardingReferenceInputKind] {
        var missing: [OnboardingReferenceInputKind] = []
        if reelCount(in: references) < 1 { missing.append(.reel) }
        if profileCount(in: references) < 1 { missing.append(.profile) }
        return missing
    }

    static func referencesMixIsValid(_ references: [OnboardingReference]) -> Bool {
        missingReferenceKinds(in: references).isEmpty
    }

    static func referenceValidationMessage(flags: OnboardingReferenceValidationFlags) -> String? {
        var missing: [String] = []
        if flags.reel { missing.append("reel URL") }
        if flags.profile { missing.append("profile @handle") }
        switch missing.count {
        case 2:
            return "Add at least one reel URL and one profile @handle to continue."
        case 1:
            return "Add at least one \(missing[0]) to continue."
        default:
            return nil
        }
    }

    static func referenceMixHint(for references: [OnboardingReference]) -> String? {
        guard !referencesMixIsValid(references) else { return nil }
        let reels = reelCount(in: references)
        let profiles = profileCount(in: references)
        if reels == 0, profiles >= 1 {
            return "Add at least one reel URL to continue."
        }
        if profiles == 0, reels >= 1 {
            return "Add at least one profile @handle to continue."
        }
        return nil
    }

    static func validationFlagsAfterContinueAttempt(
        references: [OnboardingReference],
        motionEnabled: Bool
    ) -> OnboardingReferenceValidationFlags {
        let missing = missingReferenceKinds(in: references)
        return OnboardingReferenceValidationFlags(
            reel: missing.contains(.reel),
            profile: missing.contains(.profile),
            motion: motionEnabled && !missing.isEmpty
        )
    }
}

// MARK: - Review summary helpers

enum OnboardingReviewSummary {
    static func stylePhrase(
        selectedExamples: [OnboardingTasteExample],
        formats: [OnboardingProductionFormat]
    ) -> String {
        var parts: [String] = []
        let styles = Set(selectedExamples.map(\.style))
        if styles.contains(.recommendation) { parts.append("recommendations") }
        if styles.contains(.opinion) { parts.append("opinions") }
        if styles.contains(.personalHumour) { parts.append("humour") }
        if parts.isEmpty, !formats.isEmpty {
            return "Mix of \(formats.map(\.displayLabel).joined(separator: ", ").lowercased())"
        }
        guard !parts.isEmpty else { return "Your own mix" }
        if parts.count == 1 { return "Mostly \(parts[0])" }
        return "Mix of \(parts.dropLast().joined(separator: ", ")) and \(parts.last ?? "")"
    }

    static func timeLabel(_ time: OnboardingTimeToCreate?) -> String {
        time?.displayLabel ?? "Not set"
    }

    static func faceVoiceLabel(showFace: Bool?, useVoice: Bool?) -> String {
        let face = showFace == true ? "face on camera" : (showFace == false ? "no face" : "")
        let voice = useVoice == true ? "voiceover" : (useVoice == false ? "no voiceover" : "")
        return [face, voice].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
