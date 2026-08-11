import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class OnboardingViewModel {
    var step: OnboardingStep = .categories
    var selectedCategoryIDs: [String] = []
    var categoryOtherText = ""
    var references: [OnboardingReference] = []
    var referenceInputKind: OnboardingReferenceInputKind = .reel
    var reelDraftText = ""
    var profileDraftText = ""
    var isVerifyingProfile = false
    var referenceValidation: OnboardingReferenceValidationFlags = .none
    var toastMessage: String?
    var sessionDismissed = false
    private(set) var onboardingCompletedThisSession = false

    private let store: any OnboardingStoring
    private let defaultProfileVerifier: any OnboardingProfileVerifying
    private var injectedProfileVerifier: (any OnboardingProfileVerifying)?

    init(
        store: any OnboardingStoring = UserDefaultsOnboardingStore(),
        profileVerifier: any OnboardingProfileVerifying = FixtureOnboardingProfileVerifier()
    ) {
        self.store = store
        self.defaultProfileVerifier = profileVerifier
        restoreProgressIfNeeded()
    }

    func configureProfileVerifier(_ verifier: any OnboardingProfileVerifying) {
        injectedProfileVerifier = verifier
    }

    private var activeProfileVerifier: any OnboardingProfileVerifying {
        injectedProfileVerifier ?? defaultProfileVerifier
    }

    var shouldPresentOnboarding: Bool {
        guard !onboardingCompletedThisSession else { return false }
        return OnboardingPresentationPolicy.shouldPresent(store: store, sessionDismissed: sessionDismissed)
    }

    var categoriesContinueEnabled: Bool {
        !selectedCategoryIDs.isEmpty
    }

    var categoriesAreValid: Bool {
        OnboardingValidation.categoriesAreValid(
            selectedIDs: selectedCategoryIDs,
            otherText: categoryOtherText
        )
    }

    var referenceValidationMessage: String? {
        OnboardingValidation.referenceValidationMessage(flags: referenceValidation)
    }

    var referenceMixHint: String? {
        OnboardingValidation.referenceMixHint(for: references)
    }

    var displayedReferenceHint: String? {
        referenceValidationMessage ?? referenceMixHint
    }

    var categoryDisplayLabels: [String] {
        OnboardingCategories.displayLabels(
            selectedIDs: selectedCategoryIDs,
            otherText: categoryOtherText
        )
    }

    func restoreProgressIfNeeded() {
        guard let progress = store.loadProgress() else { return }
        step = progress.step
        selectedCategoryIDs = progress.selectedCategoryIDs
        categoryOtherText = progress.categoryOtherText
        references = progress.references
    }

    func persistProgress() {
        store.saveProgress(
            OnboardingProgress(
                step: step,
                selectedCategoryIDs: selectedCategoryIDs,
                categoryOtherText: categoryOtherText,
                references: references
            )
        )
    }

    func toggleCategory(_ id: String) {
        if let index = selectedCategoryIDs.firstIndex(of: id) {
            selectedCategoryIDs.remove(at: index)
            if id == OnboardingCategories.otherID {
                categoryOtherText = ""
            }
        } else if selectedCategoryIDs.count < OnboardingValidation.maxCategories {
            selectedCategoryIDs.append(id)
        } else {
            toastMessage = "Max 3 categories"
        }
        persistProgress()
    }

    func updateCategoryOther(_ text: String) {
        categoryOtherText = text
        persistProgress()
    }

    func advanceFromCategories() {
        guard categoriesAreValid else {
            if selectedCategoryIDs.contains(OnboardingCategories.otherID),
               categoryOtherText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                toastMessage = "Enter your category"
            }
            return
        }
        step = .references
        persistProgress()
    }

    func setReferenceInputKind(_ kind: OnboardingReferenceInputKind) {
        referenceInputKind = kind
    }

    func addReference(from rawText: String? = nil, kind: OnboardingReferenceInputKind) async {
        let trimmed = (rawText ?? draftText(for: kind))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            toastMessage = kind == .reel ? "Paste a reel URL" : "Paste a profile @handle"
            return
        }
        guard !isVerifyingProfile else { return }
        guard references.count < OnboardingValidation.maxReferences else {
            toastMessage = "Max 10 references during onboarding"
            return
        }

        switch OnboardingReferenceParser.parse(trimmed, expected: kind) {
        case .failure(let error):
            toastMessage = error.userMessage
        case .success(let parsed):
            var ref = parsed.reference
            if parsed.needsProfileVerification, let handle = parsed.handle {
                isVerifyingProfile = true
                let verification = await activeProfileVerifier.verify(handle: handle)
                isVerifyingProfile = false

                if verification.status == .notFound {
                    toastMessage = "@\(verification.handle) wasn't found on Instagram"
                    return
                }

                ref = OnboardingReference(
                    id: ref.id,
                    kind: .profile,
                    label: "@\(verification.handle) · profile",
                    key: "handle:\(verification.handle)",
                    url: verification.url
                )

                if verification.status == .temporarilyUnavailable {
                    appendReference(ref, clearingKind: kind)
                    toastMessage = "Profile added. We couldn't check Instagram right now."
                    return
                }
            }

            if references.contains(where: { $0.key == ref.key }) {
                toastMessage = "Already added"
                return
            }

            appendReference(ref, clearingKind: kind)
            toastMessage = ref.isProfile ? "Profile added" : "Reel added"
        }
    }

    private func draftText(for kind: OnboardingReferenceInputKind) -> String {
        switch kind {
        case .reel: reelDraftText
        case .profile: profileDraftText
        }
    }

    private func appendReference(_ ref: OnboardingReference, clearingKind: OnboardingReferenceInputKind) {
        references.append(ref)
        clearDraft(for: clearingKind)
        reconcileReferenceValidationAfterListChange()
        persistProgress()
    }

    private func clearDraft(for kind: OnboardingReferenceInputKind) {
        switch kind {
        case .reel: reelDraftText = ""
        case .profile: profileDraftText = ""
        }
    }

    private func reconcileReferenceValidationAfterListChange() {
        if OnboardingValidation.referencesMixIsValid(references) {
            referenceValidation = .none
            return
        }

        let missing = OnboardingValidation.missingReferenceKinds(in: references)
        referenceValidation = OnboardingReferenceValidationFlags(
            reel: missing.contains(.reel),
            profile: missing.contains(.profile),
            motion: false
        )
    }

    func removeReference(id: String) {
        references.removeAll { $0.id == id }
        reconcileReferenceValidationAfterListChange()
        persistProgress()
    }

    func continueFromReferences(reduceMotion: Bool) {
        guard OnboardingValidation.referencesMixIsValid(references) else {
            referenceValidation = OnboardingValidation.validationFlagsAfterContinueAttempt(
                references: references,
                motionEnabled: !reduceMotion
            )
            if let firstMissing = OnboardingValidation.missingReferenceKinds(in: references).first {
                referenceInputKind = firstMissing
            }
            let message = OnboardingValidation.referenceValidationMessage(flags: referenceValidation)
            toastMessage = message ?? "Add at least one reel URL and one profile @handle to continue."
            return
        }
        referenceValidation = .none
        step = .confirm
        persistProgress()
    }

    func goToStep(_ target: OnboardingStep) {
        step = target
        if target != .references {
            referenceValidation = .none
        }
        persistProgress()
    }

    func softSkip() {
        persistProgress()
        sessionDismissed = true
        toastMessage = "Set up later — we'll ask again next launch"
    }

    func consumeReferenceAttentionMotionIfNeeded() {
        if referenceValidation.motion {
            referenceValidation.motion = false
        }
    }

    func completedData() -> OnboardingCompletedData {
        OnboardingCompletedData(
            selectedCategoryIDs: selectedCategoryIDs,
            categoryOtherText: categoryOtherText,
            references: references,
            voiceDeferred: true
        )
    }

    func finishAndGenerateFirstDay(todayDate: String) -> OnboardingFirstDayHandoff {
        let data = completedData()
        store.markComplete(with: data)
        sessionDismissed = false
        onboardingCompletedThisSession = true
        // No day brief: onboarding hands off to the five Plan idea options
        // so the creator picks the direction before anything is generated.
        return OnboardingFirstDayHandoff(
            scheduledDate: todayDate,
            dayBrief: nil,
            completedData: data
        )
    }
}

struct OnboardingFirstDayHandoff: Hashable, Sendable {
    var scheduledDate: String
    /// Optional day brief. When nil, Plan lands on the five idea options instead of auto-starting a generation.
    var dayBrief: String?
    var completedData: OnboardingCompletedData
}
