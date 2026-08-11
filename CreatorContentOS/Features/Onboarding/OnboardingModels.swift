import Foundation

// MARK: - Steps

enum OnboardingStep: Int, Codable, Hashable, Sendable, CaseIterable {
    case categories = 0
    case references = 1
    case confirm = 2
}

// MARK: - Categories

struct OnboardingCategoryOption: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
}

enum OnboardingCategories {
    static let otherID = "other"

    static let starter: [OnboardingCategoryOption] = [
        OnboardingCategoryOption(id: "fitness", label: "Fitness"),
        OnboardingCategoryOption(id: "books", label: "Books & movies"),
        OnboardingCategoryOption(id: "food", label: "Food"),
        OnboardingCategoryOption(id: "travel", label: "Travel"),
        OnboardingCategoryOption(id: "lifestyle", label: "Lifestyle"),
        OnboardingCategoryOption(id: "makeup", label: "Makeup"),
        OnboardingCategoryOption(id: "tech", label: "Tech"),
        OnboardingCategoryOption(id: "finance", label: "Finance"),
        OnboardingCategoryOption(id: "parenting", label: "Parenting"),
        OnboardingCategoryOption(id: "gaming", label: "Gaming"),
    ]

    static func label(for id: String, otherText: String) -> String {
        if id == otherID {
            let trimmed = otherText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Other" : trimmed
        }
        return starter.first(where: { $0.id == id })?.label ?? id
    }

    static func displayLabels(selectedIDs: [String], otherText: String) -> [String] {
        selectedIDs.map { label(for: $0, otherText: otherText) }
    }
}

// MARK: - References

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

    /// Row text for references and confirm summary lists.
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

// MARK: - Validation attention (references step)

struct OnboardingReferenceValidationFlags: Equatable, Sendable {
    var reel: Bool = false
    var profile: Bool = false
    var motion: Bool = false

    static let none = Self()
}

// MARK: - Persisted progress / completion

struct OnboardingProgress: Codable, Hashable, Sendable {
    var step: OnboardingStep
    var selectedCategoryIDs: [String]
    var categoryOtherText: String
    var references: [OnboardingReference]

    static let empty = Self(
        step: .categories,
        selectedCategoryIDs: [],
        categoryOtherText: "",
        references: []
    )
}

struct OnboardingCompletedData: Codable, Hashable, Sendable {
    var selectedCategoryIDs: [String]
    var categoryOtherText: String
    var references: [OnboardingReference]
    var voiceDeferred: Bool
    /// UI-only: a template Creator Voice draft was prefilled after onboarding.
    /// Never used by generation; cleared on the creator's first voice save.
    /// Optional so older persisted JSON without the key still decodes.
    var voicePrefilled: Bool? = nil

    var categoryLabels: [String] {
        OnboardingCategories.displayLabels(
            selectedIDs: selectedCategoryIDs,
            otherText: categoryOtherText
        )
    }

    func firstDayBrief() -> String {
        let labels = categoryLabels
        guard !labels.isEmpty else {
            return "First day content plan"
        }
        if labels.count == 1 {
            return "Content about \(labels[0])"
        }
        return "Content about \(labels.joined(separator: ", "))"
    }
}

// MARK: - Voice prefill (post-onboarding UI draft only)

/// Template Creator Voice shown as a UI draft after onboarding. Never written
/// to the saved creator profile — generation keeps using references alone until
/// the creator saves their own voice (which clears `OnboardingCompletedData.voicePrefilled`).
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
        OnboardingCategories.displayLabels(
            selectedIDs: completedData.selectedCategoryIDs,
            otherText: completedData.categoryOtherText
        )
    }
}

// MARK: - Pure validation

enum OnboardingValidation {
    static let maxCategories = 3
    static let maxReferences = 10

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
        if reels == 0, profiles == 0 {
            return nil
        }
        return nil
    }

    /// Applies one-shot validation flags when Continue is tapped with an incomplete mix.
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
