import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class OnboardingViewModel {
    var step: OnboardingStep = .interests
    var interestIDs: [String] = []
    var customSubjects: [String] = []
    var customSubjectDraft = ""
    var startingPoint: OnboardingStartingPoint?
    var selectedTasteExampleIDs: [String] = []
    var tasteRefreshCount = 0
    private(set) var displayedTasteExampleIDs: [String] = []
    var formats: [OnboardingProductionFormat] = []
    var timeToCreate: OnboardingTimeToCreate?
    var contentLanguage: String = OnboardingLanguageDefaults.preferredContentLanguage
    var showFace: Bool?
    var useVoice: Bool?
    var contextAnswers: [String: String] = [:]
    var creatorNote = ""
    var contextSkippedThisSession = false

    // Reference import (You — not a required onboarding step)
    var references: [OnboardingReference] = []
    var referenceInputKind: OnboardingReferenceInputKind = .reel
    var referenceDraftText = ""
    var isVerifyingProfile = false
    private var isAddingReference = false
    var referenceValidation: OnboardingReferenceValidationFlags = .none

    var toastMessage: String?
    var sessionDismissed = false
    private(set) var onboardingCompletedThisSession = false
    var confirmState: OnboardingFirstIdeaConfirmState = .idle

    // Legacy aliases for reference-parser tests
    var selectedCategoryIDs: [String] {
        get { interestIDs }
        set { interestIDs = newValue }
    }

    var categoryOtherText: String {
        get { customSubjects.first ?? "" }
        set {
            if let trimmed = newValue.nilIfBlank {
                if customSubjects.isEmpty {
                    customSubjects = [trimmed]
                } else {
                    customSubjects[0] = trimmed
                }
            } else {
                customSubjects = []
            }
        }
    }

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
        refreshDisplayedTasteExamples(force: true)
    }

    func configureProfileVerifier(_ verifier: any OnboardingProfileVerifying) {
        injectedProfileVerifier = verifier
    }

    private var activeProfileVerifier: any OnboardingProfileVerifying {
        injectedProfileVerifier ?? defaultProfileVerifier
    }

    var shouldKeepOnboardingFlowVisible: Bool {
        switch confirmState {
        case .preparing, .generationFailed, .persistFailed:
            return true
        case .idle, .succeeded:
            return false
        }
    }

    var shouldPresentOnboarding: Bool {
        guard !onboardingCompletedThisSession else { return false }
        if shouldKeepOnboardingFlowVisible { return true }
        return OnboardingPresentationPolicy.shouldPresent(store: store, sessionDismissed: sessionDismissed)
    }

    var promptedContextQuestions: [OnboardingContextQuestion] {
        OnboardingContextQuestions.promptedQuestions(
            interestIDs: interestIDs,
            customSubjects: customSubjects
        )
    }

    var displayedTasteExamples: [OnboardingTasteExample] {
        displayedTasteExampleIDs.compactMap { OnboardingExamplePacks.example(by: $0) }
    }

    var interestDisplayLabels: [String] {
        OnboardingInterestCatalog.displayLabels(interestIDs: interestIDs, customSubjects: customSubjects)
    }

    var categoryDisplayLabels: [String] { interestDisplayLabels }

    // MARK: - Step validation

    var interestsContinueEnabled: Bool {
        OnboardingValidation.interestsStepIsValid(
            interestIDs: interestIDs,
            customSubjects: customSubjects,
            startingPoint: startingPoint
        )
    }

    var interestsAreValid: Bool { interestsContinueEnabled }

    var tasteContinueEnabled: Bool {
        OnboardingValidation.tasteIsValid(
            selectedExampleIDs: selectedTasteExampleIDs,
            refreshCount: tasteRefreshCount
        )
    }

    var productionContinueEnabled: Bool {
        OnboardingValidation.productionIsValid(
            formats: formats,
            timeToCreate: timeToCreate,
            contentLanguage: contentLanguage,
            showFace: showFace,
            useVoice: useVoice
        )
    }

    var contextContinueEnabled: Bool {
        contextSkippedThisSession
            || OnboardingValidation.contextIsValid(
                promptedQuestionIDs: promptedContextQuestions.filter(\.isRequired).map(\.id),
                answers: contextAnswers
            )
    }

    var categoriesContinueEnabled: Bool { interestsContinueEnabled }

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
        if isVerifyingProfile { return "Checking on Instagram…" }
        return referenceValidationMessage ?? referenceMixHint
    }

    var confirmErrorMessage: String? {
        switch confirmState {
        case .persistFailed:
            return "We couldn't save your preferences. Check your connection and try again."
        case .generationFailed(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("ready_package_overwrite_required") {
                return "We saved your preferences, but Today already has an idea, so we left it."
            }
            if trimmed.contains("_") && !trimmed.contains(" ") {
                return "We saved your preferences but couldn't prepare your first idea."
            }
            return trimmed.nilIfBlank ?? "We saved your preferences but couldn't prepare your first idea."
        default:
            return nil
        }
    }

    var isConfirmingFirstIdea: Bool {
        confirmState == .preparing
    }

    // MARK: - Persistence

    func restoreProgressIfNeeded() {
        guard let progress = store.loadProgress() else { return }
        step = progress.step
        interestIDs = progress.interestIDs
        customSubjects = progress.customSubjects
        startingPoint = progress.startingPoint
        selectedTasteExampleIDs = progress.selectedTasteExampleIDs
        tasteRefreshCount = progress.tasteRefreshCount
        formats = progress.formats
        timeToCreate = progress.timeToCreate
        contentLanguage = progress.contentLanguage
        showFace = progress.showFace
        useVoice = progress.useVoice
        contextAnswers = progress.contextAnswers
        creatorNote = progress.creatorNote
        references = progress.references
        refreshDisplayedTasteExamples(force: true)
    }

    func persistProgress() {
        store.saveProgress(
            OnboardingProgress(
                step: step,
                interestIDs: interestIDs,
                customSubjects: customSubjects,
                startingPoint: startingPoint,
                selectedTasteExampleIDs: selectedTasteExampleIDs,
                tasteRefreshCount: tasteRefreshCount,
                formats: formats,
                timeToCreate: timeToCreate,
                contentLanguage: contentLanguage,
                showFace: showFace,
                useVoice: useVoice,
                contextAnswers: contextAnswers,
                creatorNote: creatorNote,
                references: references
            )
        )
    }

    // MARK: - Step 1: Interests

    func toggleInterest(_ id: String) {
        if let index = interestIDs.firstIndex(of: id) {
            interestIDs.remove(at: index)
            reconcileTasteAfterInterestChange()
        } else if totalInterestCount < OnboardingValidation.maxTotalInterests {
            interestIDs.append(id)
            reconcileTasteAfterInterestChange()
        } else {
            toastMessage = "Max \(OnboardingValidation.maxTotalInterests) topics"
        }
        persistProgress()
    }

    func addCustomSubject() {
        let trimmed = customSubjectDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard totalInterestCount < OnboardingValidation.maxTotalInterests else {
            toastMessage = "Max \(OnboardingValidation.maxTotalInterests) topics"
            return
        }
        guard !customSubjects.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            customSubjectDraft = ""
            return
        }
        customSubjects.append(trimmed)
        customSubjectDraft = ""
        reconcileTasteAfterInterestChange()
        persistProgress()
    }

    func removeCustomSubject(_ subject: String) {
        customSubjects.removeAll { $0 == subject }
        reconcileTasteAfterInterestChange()
        persistProgress()
    }

    func setStartingPoint(_ point: OnboardingStartingPoint) {
        startingPoint = startingPoint == point ? nil : point
        persistProgress()
    }

    private var totalInterestCount: Int {
        interestIDs.count + customSubjects.count
    }

    private func reconcileTasteAfterInterestChange() {
        selectedTasteExampleIDs = OnboardingExamplePacks.pruneStaleSelections(
            selectedIDs: selectedTasteExampleIDs,
            interestIDs: interestIDs,
            customSubjects: customSubjects
        )
        refreshDisplayedTasteExamples(force: true)
    }

    func advanceFromInterests() {
        guard OnboardingValidation.interestsAreValid(interestIDs: interestIDs, customSubjects: customSubjects) else {
            toastMessage = "Pick at least one topic"
            return
        }
        guard OnboardingValidation.startingPointIsValid(startingPoint) else {
            toastMessage = "Choose Just starting or Already posting"
            return
        }
        refreshDisplayedTasteExamples(force: true)
        step = .tasteExamples
        persistProgress()
    }

    // MARK: - Step 2: Taste

    func refreshDisplayedTasteExamples(force: Bool = false) {
        if !force, !displayedTasteExampleIDs.isEmpty { return }
        let pack = OnboardingExamplePacks.displayPack(
            interestIDs: interestIDs,
            customSubjects: customSubjects,
            excluding: [],
            shuffleSeed: tasteRefreshCount &+ interestIDs.hashValue
        )
        displayedTasteExampleIDs = pack.map(\.id)
    }

    func toggleTasteExample(_ id: String) {
        if let index = selectedTasteExampleIDs.firstIndex(of: id) {
            selectedTasteExampleIDs.remove(at: index)
        } else {
            selectedTasteExampleIDs.append(id)
        }
        persistProgress()
    }

    func refreshTasteExamples() {
        tasteRefreshCount += 1
        let pack = OnboardingExamplePacks.displayPack(
            interestIDs: interestIDs,
            customSubjects: customSubjects,
            excluding: displayedTasteExampleIDs,
            shuffleSeed: tasteRefreshCount &+ interestIDs.hashValue &+ 17
        )
        displayedTasteExampleIDs = pack.map(\.id)
        selectedTasteExampleIDs = OnboardingExamplePacks.pruneStaleSelections(
            selectedIDs: selectedTasteExampleIDs,
            interestIDs: interestIDs,
            customSubjects: customSubjects
        )
        persistProgress()
    }

    func advanceFromTasteExamples() {
        guard tasteContinueEnabled else {
            toastMessage = "Pick at least one example, or show different examples"
            return
        }
        step = .productionConstraints
        persistProgress()
    }

    // MARK: - Step 3: Production

    func toggleFormat(_ format: OnboardingProductionFormat) {
        if let index = formats.firstIndex(of: format) {
            formats.remove(at: index)
        } else {
            formats.append(format)
        }
        persistProgress()
    }

    func setTimeToCreate(_ time: OnboardingTimeToCreate) {
        timeToCreate = time
        persistProgress()
    }

    func updateContentLanguage(_ language: String) {
        contentLanguage = language
        persistProgress()
    }

    func setShowFace(_ value: Bool) {
        showFace = value
        persistProgress()
    }

    func setUseVoice(_ value: Bool) {
        useVoice = value
        persistProgress()
    }

    func advanceFromProductionConstraints() {
        guard productionContinueEnabled else {
            toastMessage = "Select formats, time, language, and face/voice preferences"
            return
        }
        step = .interestContext
        persistProgress()
    }

    // MARK: - Step 4: Context

    func updateContextAnswer(questionID: String, answer: String) {
        contextAnswers[questionID] = answer
        persistProgress()
    }

    func updateCreatorNote(_ note: String) {
        creatorNote = note
        persistProgress()
    }

    func skipContextStep() {
        contextSkippedThisSession = true
        step = .review
        persistProgress()
    }

    func advanceFromInterestContext() {
        guard contextContinueEnabled else { return }
        contextSkippedThisSession = false
        step = .review
        persistProgress()
    }

    // MARK: - Navigation

    func goToStep(_ target: OnboardingStep) {
        step = target
        if target == .tasteExamples {
            refreshDisplayedTasteExamples(force: displayedTasteExampleIDs.isEmpty)
        }
        persistProgress()
    }

    func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        goToStep(previous)
    }

    func softSkip() {
        persistProgress()
        sessionDismissed = true
        toastMessage = "Set up later — we'll ask again next launch"
    }

    // MARK: - Confirm / first idea

    func completedData() -> OnboardingCompletedData {
        let titles = selectedTasteExampleIDs.compactMap { OnboardingExamplePacks.example(by: $0)?.title }
        return OnboardingCompletedData(
            selectedCategoryIDs: interestIDs,
            customSubjects: customSubjects,
            startingPoint: startingPoint,
            selectedTasteExampleIDs: selectedTasteExampleIDs,
            tasteExampleTitles: titles,
            formats: formats,
            timeToCreate: timeToCreate,
            contentLanguage: contentLanguage,
            showFace: showFace,
            useVoice: useVoice,
            contextAnswers: contextAnswers,
            creatorNote: creatorNote.nilIfBlank,
            references: references,
            voiceDeferred: false,
            voicePrefilled: true
        )
    }

    func confirmFirstIdea(
        services: AppServices,
        scheduledDate: String
    ) async -> OnboardingFirstIdeaHandoffResult {
        confirmState = .preparing
        let data = completedData()
        let result = await services.confirmOnboardingAndPrepareFirstIdea(
            completedData: data,
            scheduledDate: scheduledDate
        )
        switch result {
        case .completed, .skippedExistingReady:
            confirmState = .succeeded
            store.clearProgress()
            sessionDismissed = false
            onboardingCompletedThisSession = true
        case .persistFailed:
            confirmState = .persistFailed
        case .generationFailed(let message):
            confirmState = .generationFailed(message: message)
            store.clearProgress()
            onboardingCompletedThisSession = true
        }
        return result
    }

    /// Legacy handoff helper — does not mark complete before persist.
    func finishAndGenerateFirstDay(todayDate: String) -> OnboardingFirstDayHandoff {
        OnboardingFirstDayHandoff(
            scheduledDate: todayDate,
            dayBrief: nil,
            completedData: completedData()
        )
    }

    // MARK: - Legacy reference import (tests + You)

    func toggleCategory(_ id: String) { toggleInterest(id) }

    func updateCategoryOther(_ text: String) { categoryOtherText = text; persistProgress() }

    func advanceFromCategories() { advanceFromInterests() }

    func setReferenceInputKind(_ kind: OnboardingReferenceInputKind) {
        referenceInputKind = kind
    }

    func handleDraftChange(previous: String, current: String) async {
        referenceDraftText = current
        let inserted = current.count - previous.count
        if OnboardingReferenceParser.shouldAutoAddCompleteReelOrPost(previous: previous, current: current) {
            await addReference(from: current)
            return
        }
        guard inserted >= 12 else { return }
        switch OnboardingReferenceParser.parse(current) {
        case .success:
            break
        case .failure(let error) where error != .empty:
            toastMessage = error.userMessage
        default:
            break
        }
    }

    func submitDraftIfPresent() async {
        if isAddingReference {
            while isAddingReference {
                try? await Task.sleep(for: .milliseconds(40))
            }
            return
        }
        let trimmed = referenceDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await addReference(from: trimmed)
    }

    func addReference(from rawText: String? = nil) async {
        if isAddingReference {
            while isAddingReference {
                try? await Task.sleep(for: .milliseconds(40))
            }
            return
        }
        isAddingReference = true
        defer { isAddingReference = false }

        let trimmed = (rawText ?? referenceDraftText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard references.count < OnboardingValidation.maxReferences else {
            toastMessage = "Max 10 references during onboarding"
            return
        }

        switch OnboardingReferenceParser.parse(trimmed) {
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
                    appendReference(ref)
                    toastMessage = "Profile added. We couldn't check Instagram right now."
                    return
                }
            }

            if references.contains(where: { $0.key == ref.key }) {
                toastMessage = "Already added"
                return
            }

            appendReference(ref)
            toastMessage = ref.isProfile ? "Profile added" : "Reel added"
        }
    }

    private func appendReference(_ ref: OnboardingReference) {
        references.append(ref)
        referenceDraftText = ""
        reconcileReferenceValidationAfterListChange()
        persistProgress()
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

    func continueFromReferences(reduceMotion: Bool) async {
        await submitDraftIfPresent()
        let leftover = referenceDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard leftover.isEmpty else { return }

        guard OnboardingValidation.referencesMixIsValid(references) else {
            referenceValidation = OnboardingValidation.validationFlagsAfterContinueAttempt(
                references: references,
                motionEnabled: !reduceMotion
            )
            if let firstMissing = OnboardingValidation.missingReferenceKinds(in: references).first {
                referenceInputKind = firstMissing
            }
            toastMessage = referenceValidationMessage ?? "Add at least one reel URL and one profile @handle to continue."
            return
        }
        referenceValidation = .none
        step = .review
        persistProgress()
    }

    func consumeReferenceAttentionMotionIfNeeded() {
        if referenceValidation.motion {
            referenceValidation.motion = false
        }
    }
}

struct OnboardingFirstDayHandoff: Hashable, Sendable {
    var scheduledDate: String
    var dayBrief: String?
    var completedData: OnboardingCompletedData
}
