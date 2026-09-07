import XCTest
@testable import CreatorContentOS

@MainActor
final class OnboardingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    private let reel = OnboardingReference(
        id: "1",
        kind: .reel,
        label: "instagram.com/reel/abc",
        key: "instagram:reel:abc",
        url: "https://www.instagram.com/reel/abc/"
    )
    private let profile = OnboardingReference(
        id: "2",
        kind: .profile,
        label: "@creator · profile",
        key: "handle:creator",
        url: "https://www.instagram.com/creator/"
    )

    override func setUp() {
        super.setUp()
        suiteName = UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Store

    func testProgressRoundTrip() {
        let store = UserDefaultsOnboardingStore(defaults: defaults)
        let progress = OnboardingProgress(
            step: .tasteExamples,
            interestIDs: ["books", "movies-tv"],
            customSubjects: ["Pottery"],
            startingPoint: .justStarting,
            selectedTasteExampleIDs: ["books-rec-1"],
            tasteRefreshCount: 0,
            formats: [.talkingToCamera],
            timeToCreate: .tenToThirty,
            contentLanguage: "English",
            showFace: true,
            useVoice: true,
            contextAnswers: [:],
            creatorNote: "",
            references: []
        )

        store.saveProgress(progress)
        let loaded = store.loadProgress()

        XCTAssertEqual(loaded?.step, .tasteExamples)
        XCTAssertEqual(loaded?.interestIDs, ["books", "movies-tv"])
        XCTAssertEqual(loaded?.customSubjects, ["Pottery"])
        XCTAssertEqual(loaded?.selectedTasteExampleIDs, ["books-rec-1"])
    }

    func testMarkCompleteClearsProgressAndSetsDoneFlag() {
        let store = UserDefaultsOnboardingStore(defaults: defaults)
        store.saveProgress(.empty)
        XCTAssertFalse(store.isComplete())

        let data = OnboardingCompletedData(
            selectedCategoryIDs: ["travel"],
            categoryOtherText: "",
            references: [],
            voiceDeferred: true
        )
        store.markComplete(with: data)

        XCTAssertTrue(store.isComplete())
        XCTAssertNil(store.loadProgress())
        XCTAssertEqual(store.loadCompletedData()?.selectedCategoryIDs, ["travel"])
    }

    func testResetAllClearsProgressCompletionAndData() {
        let store = UserDefaultsOnboardingStore(defaults: defaults)
        store.saveProgress(.empty)
        store.markComplete(
            with: OnboardingCompletedData(
                selectedCategoryIDs: ["food"],
                categoryOtherText: "",
                references: [],
                voiceDeferred: true
            )
        )

        store.resetAll()

        XCTAssertFalse(store.isComplete())
        XCTAssertNil(store.loadProgress())
        XCTAssertNil(store.loadCompletedData())
    }

    func testSoftSkipResumeOnNextLaunch() {
        let store = UserDefaultsOnboardingStore(defaults: defaults)
        store.saveProgress(
            OnboardingProgress(
                step: .interests,
                interestIDs: ["gaming"],
                customSubjects: [],
                startingPoint: nil,
                selectedTasteExampleIDs: [],
                tasteRefreshCount: 0,
                formats: [],
                timeToCreate: nil,
                contentLanguage: "English",
                showFace: nil,
                useVoice: nil,
                contextAnswers: [:],
                creatorNote: "",
                references: []
            )
        )

        XCTAssertFalse(
            OnboardingPresentationPolicy.shouldPresent(store: store, sessionDismissed: true)
        )
        XCTAssertTrue(
            OnboardingPresentationPolicy.shouldPresent(store: store, sessionDismissed: false)
        )
    }

    // MARK: - Launch-A one-screen validation

    func testLaunchContinueEnabledWithZeroFields() {
        let model = OnboardingViewModel(store: UserDefaultsOnboardingStore(defaults: defaults))
        XCTAssertTrue(model.launchContinueEnabled)
        XCTAssertFalse(model.interestsContinueEnabled)
    }

    func testLaunchContinueEnabledWithOnlyStartingPoint() {
        let model = OnboardingViewModel(store: UserDefaultsOnboardingStore(defaults: defaults))
        model.startingPoint = .justStarting
        XCTAssertTrue(model.launchContinueEnabled)
    }

    func testLegacyFiveStepProgressNormalizesToLaunchScreen() {
        let store = UserDefaultsOnboardingStore(defaults: defaults)
        store.saveProgress(
            OnboardingProgress(
                step: .productionConstraints,
                interestIDs: ["books"],
                customSubjects: ["Pottery"],
                startingPoint: .alreadyPosting,
                selectedTasteExampleIDs: ["books-rec-1"],
                tasteRefreshCount: 0,
                formats: [.talkingToCamera],
                timeToCreate: .tenToThirty,
                contentLanguage: "English",
                showFace: true,
                useVoice: true,
                contextAnswers: [:],
                creatorNote: "",
                references: []
            )
        )

        let model = OnboardingViewModel(store: store)
        XCTAssertEqual(model.step, .interests)
        XCTAssertEqual(model.interestIDs, ["books"])
        XCTAssertEqual(model.customSubjects, ["Pottery"])
        XCTAssertEqual(model.startingPoint, .alreadyPosting)
    }

    func testCompletedDataDefersVoiceWithoutPrefill() {
        let model = OnboardingViewModel(store: UserDefaultsOnboardingStore(defaults: defaults))
        model.interestIDs = ["books"]
        let data = model.completedData()
        XCTAssertTrue(data.voiceDeferred)
        XCTAssertNil(data.voicePrefilled)
    }

    func testGenericStarterBriefWhenNoLaunchPreferences() {
        let record = OnboardingRecord(
            completedData: OnboardingCompletedData(
                selectedCategoryIDs: [],
                categoryOtherText: "",
                references: [],
                voiceDeferred: true
            )
        )
        let brief = OnboardingFirstIdeaBriefBuilder.buildDayBrief(from: record)
        XCTAssertEqual(brief, OnboardingFirstIdeaBriefBuilder.genericStarterBrief)
        XCTAssertFalse(brief.localizedCaseInsensitiveContains("HYROX"))
    }

    // MARK: - Five-step validation (legacy helpers + You editors)

    func testInterestsRequireAtLeastOneTopicOrCustomSubject() {
        XCTAssertFalse(
            OnboardingValidation.interestsAreValid(interestIDs: [], customSubjects: [])
        )
        XCTAssertTrue(
            OnboardingValidation.interestsAreValid(interestIDs: ["books"], customSubjects: [])
        )
        XCTAssertTrue(
            OnboardingValidation.interestsAreValid(interestIDs: [], customSubjects: ["Pottery"])
        )
        XCTAssertFalse(
            OnboardingValidation.interestsAreValid(
                interestIDs: Array(repeating: "books", count: 5),
                customSubjects: Array(repeating: "Custom", count: 4)
            )
        )
    }

    func testStartingPointRequiredForInterestsStepContinue() {
        XCTAssertFalse(
            OnboardingValidation.startingPointIsValid(nil)
        )
        XCTAssertTrue(
            OnboardingValidation.startingPointIsValid(.justStarting)
        )
        XCTAssertTrue(
            OnboardingValidation.startingPointIsValid(.alreadyPosting)
        )
        XCTAssertFalse(
            OnboardingValidation.interestsStepIsValid(
                interestIDs: ["books"],
                customSubjects: [],
                startingPoint: nil
            )
        )
        XCTAssertTrue(
            OnboardingValidation.interestsStepIsValid(
                interestIDs: ["books"],
                customSubjects: [],
                startingPoint: .justStarting
            )
        )
    }

    func testInterestsContinueDisabledWithoutStartingPoint() {
        let model = OnboardingViewModel(store: UserDefaultsOnboardingStore(defaults: defaults))
        model.interestIDs = ["books", "movies-tv"]
        XCTAssertFalse(model.interestsContinueEnabled)

        model.startingPoint = .alreadyPosting
        XCTAssertTrue(model.interestsContinueEnabled)
    }

    func testCustomSubjectsAreFirstClassNotSilentlyLifestyle() {
        let model = OnboardingViewModel(store: UserDefaultsOnboardingStore(defaults: defaults))
        model.customSubjectDraft = "Pottery"
        model.addCustomSubject()
        model.startingPoint = .justStarting

        XCTAssertEqual(model.customSubjects, ["Pottery"])
        XCTAssertFalse(model.interestIDs.contains("lifestyle"))
        XCTAssertTrue(model.interestsContinueEnabled)
    }

    func testInterestChangeDropsStaleTasteExamples() {
        let model = OnboardingViewModel(store: UserDefaultsOnboardingStore(defaults: defaults))
        model.interestIDs = ["books", "movies-tv"]
        model.selectedTasteExampleIDs = ["books-rec-1", "movies-rec-1"]

        model.toggleInterest("books")

        XCTAssertFalse(model.selectedTasteExampleIDs.contains("books-rec-1"))
        XCTAssertTrue(model.selectedTasteExampleIDs.contains("movies-rec-1"))
    }

    func testBackNavigationPreservesAnswers() {
        let model = OnboardingViewModel(store: UserDefaultsOnboardingStore(defaults: defaults))
        model.interestIDs = ["books"]
        model.customSubjects = ["Pottery"]
        model.startingPoint = .justStarting
        model.selectedTasteExampleIDs = ["books-rec-1"]

        model.cancelSetup()

        XCTAssertEqual(model.interestIDs, ["books"])
        XCTAssertEqual(model.customSubjects, ["Pottery"])
        XCTAssertEqual(model.startingPoint, .justStarting)
        XCTAssertEqual(model.selectedTasteExampleIDs, ["books-rec-1"])
        XCTAssertTrue(model.sessionDismissed)
    }

    func testProductionValidationRequiresExplicitFaceAndVoice() {
        XCTAssertFalse(
            OnboardingValidation.productionIsValid(
                formats: [.talkingToCamera],
                timeToCreate: .tenToThirty,
                contentLanguage: "English",
                showFace: nil,
                useVoice: nil
            )
        )
        XCTAssertTrue(
            OnboardingValidation.productionIsValid(
                formats: [.talkingToCamera],
                timeToCreate: .tenToThirty,
                contentLanguage: "English",
                showFace: true,
                useVoice: false
            )
        )
    }

    func testFinishDoesNotMarkStoreCompleteBeforeConfirm() {
        let store = UserDefaultsOnboardingStore(defaults: defaults)
        let model = OnboardingViewModel(store: store)
        model.interestIDs = ["food"]
        model.formats = [.talkingToCamera]
        model.timeToCreate = .tenToThirty
        model.showFace = true
        model.useVoice = true
        model.selectedTasteExampleIDs = ["food-rec-1"]

        _ = model.finishAndGenerateFirstDay(todayDate: "2026-08-07")

        XCTAssertFalse(store.isComplete())
        XCTAssertTrue(model.shouldPresentOnboarding || model.shouldKeepOnboardingFlowVisible == false)
    }

    func testOnboardingRecordMapsExpandedCompletedData() {
        let data = OnboardingCompletedData(
            selectedCategoryIDs: ["books"],
            customSubjects: ["Pottery"],
            startingPoint: .alreadyPosting,
            selectedTasteExampleIDs: ["books-rec-1"],
            tasteExampleTitles: ["3 underrated books"],
            formats: [.voiceoverBroll],
            timeToCreate: .tenToThirty,
            contentLanguage: "English",
            showFace: false,
            useVoice: true,
            contextAnswers: ["books-reading": "Fourth Wing"],
            creatorNote: "Funny takes welcome",
            references: [],
            voiceDeferred: false
        )
        let record = OnboardingRecord(completedData: data)

        XCTAssertEqual(record.interestIDs, ["books"])
        XCTAssertEqual(record.customSubjects, ["Pottery"])
        XCTAssertEqual(record.startingPoint, "already_posting")
        XCTAssertEqual(record.selectedTasteExampleIDs, ["books-rec-1"])
        XCTAssertEqual(record.formats, ["voiceover_broll"])
        XCTAssertEqual(record.timeToCreate, "ten_to_thirty")
        XCTAssertEqual(record.showFace, false)
        XCTAssertEqual(record.useVoice, true)
        XCTAssertEqual(record.contextAnswers["books-reading"], "Fourth Wing")
        XCTAssertEqual(record.creatorNote, "Funny takes welcome")
    }

    func testFiveStepFlowDoesNotRequireInstagramReferences() {
        let model = OnboardingViewModel(store: UserDefaultsOnboardingStore(defaults: defaults))
        model.interestIDs = ["books"]
        model.startingPoint = .justStarting

        XCTAssertTrue(model.launchContinueEnabled)
        XCTAssertTrue(model.references.isEmpty)
    }

#if DEBUG
    func testEstablishedPresentationHiddenWithoutForceFlag() {
        XCTAssertFalse(
            OnboardingPresentationPolicy.shouldPresent(
                presentation: .established,
                sessionDismissed: false
            )
        )
        XCTAssertTrue(
            OnboardingPresentationPolicy.shouldPresent(
                presentation: .new,
                sessionDismissed: false
            )
        )
    }
#endif

    func testYouInterestsSelectionMapsCatalogAndCustomSubjects() {
        var profile = CreatorProfileSummary.creatorFixture
        profile.contentPillars = ["Books", "Movies & TV", "Pottery"]
        profile.customSubjects = ["Pottery"]
        profile.startingPoint = "already_posting"

        let selection = YouInterestsSelection.from(profile: profile)

        XCTAssertTrue(selection.interestIDs.contains("books"))
        XCTAssertTrue(selection.interestIDs.contains("movies-tv"))
        XCTAssertTrue(selection.customSubjects.contains("Pottery"))
        XCTAssertEqual(selection.startingPoint, .alreadyPosting)
        XCTAssertTrue(selection.isValid)
    }

    func testYouProductionSelectionRoundTripsProfileFields() {
        var profile = CreatorProfileSummary.creatorFixture
        profile.productionFormats = ["voiceover_broll", "talking_to_camera"]
        profile.timeToCreate = "ten_to_thirty"
        profile.contentLanguage = "English"
        profile.onCameraRestrictions = OnCameraRestrictionsPayload(showFace: false, useVoice: true)

        let selection = YouProductionSelection.from(profile: profile)

        XCTAssertEqual(selection.formats, [.voiceoverBroll, .talkingToCamera])
        XCTAssertEqual(selection.timeToCreate, .tenToThirty)
        XCTAssertEqual(selection.showFace, false)
        XCTAssertEqual(selection.useVoice, true)
        XCTAssertTrue(selection.isValid)
    }

    func testContextQuestionsDifferForFitnessVersusBooks() {
        let booksQuestions = OnboardingContextQuestions.promptedQuestions(
            interestIDs: ["books", "movies-tv"],
            customSubjects: []
        )
        let fitnessQuestions = OnboardingContextQuestions.promptedQuestions(
            interestIDs: ["fitness-wellness"],
            customSubjects: []
        )

        XCTAssertTrue(booksQuestions.contains(where: { $0.id == "books-reading" }))
        XCTAssertTrue(booksQuestions.contains(where: { $0.id == "movies-watching" }))
        XCTAssertFalse(booksQuestions.contains(where: { $0.id == "fitness-focus" }))
        XCTAssertTrue(fitnessQuestions.contains(where: { $0.id == "fitness-focus" }))
        XCTAssertTrue(fitnessQuestions.contains(where: { $0.id == "fitness-style" }))
        XCTAssertFalse(fitnessQuestions.contains(where: { $0.id == "books-reading" }))
    }

    func testDefaultContentLanguageUsesLocalizedName() {
        let language = OnboardingLanguageDefaults.preferredContentLanguage
        XCTAssertFalse(language.isEmpty)
        XCTAssertGreaterThan(language.count, 2)
        XCTAssertFalse(language == language.uppercased())
    }

    // MARK: - Legacy validation

    func testCategoriesRequireOneToThreeIncludingOtherText() {
        XCTAssertFalse(
            OnboardingValidation.categoriesAreValid(selectedIDs: [], otherText: "")
        )
        XCTAssertTrue(
            OnboardingValidation.categoriesAreValid(selectedIDs: ["fitness"], otherText: "")
        )
        XCTAssertFalse(
            OnboardingValidation.categoriesAreValid(
                selectedIDs: [OnboardingCategories.otherID],
                otherText: "   "
            )
        )
        XCTAssertTrue(
            OnboardingValidation.categoriesAreValid(
                selectedIDs: [OnboardingCategories.otherID],
                otherText: "Pottery"
            )
        )
    }

    func testReferenceMixRequiresReelAndProfile() {
        let reel = OnboardingReference(
            id: "1",
            kind: .reel,
            label: "reel",
            key: "instagram:reel:a",
            url: "https://www.instagram.com/reel/a/"
        )
        let profile = OnboardingReference(
            id: "2",
            kind: .profile,
            label: "@creator",
            key: "handle:creator",
            url: "https://www.instagram.com/creator/"
        )

        XCTAssertEqual(
            OnboardingValidation.missingReferenceKinds(in: []),
            [.reel, .profile]
        )
        XCTAssertEqual(
            OnboardingValidation.missingReferenceKinds(in: [reel]),
            [.profile]
        )
        XCTAssertEqual(
            OnboardingValidation.missingReferenceKinds(in: [profile]),
            [.reel]
        )
        XCTAssertTrue(OnboardingValidation.referencesMixIsValid([reel, profile]))
    }

    func testContinueValidationFlagsOnlyAfterAttempt() {
        let flags = OnboardingValidation.validationFlagsAfterContinueAttempt(
            references: [],
            motionEnabled: true
        )
        XCTAssertTrue(flags.reel)
        XCTAssertTrue(flags.profile)
        XCTAssertTrue(flags.motion)

        let staticFlags = OnboardingValidation.validationFlagsAfterContinueAttempt(
            references: [],
            motionEnabled: false
        )
        XCTAssertTrue(staticFlags.reel)
        XCTAssertTrue(staticFlags.profile)
        XCTAssertFalse(staticFlags.motion)
    }

    func testValidationMessageForMissingTypes() {
        let both = OnboardingReferenceValidationFlags(reel: true, profile: true, motion: false)
        XCTAssertEqual(
            OnboardingValidation.referenceValidationMessage(flags: both),
            "Add at least one reel URL and one profile @handle to continue."
        )

        let reelOnly = OnboardingReferenceValidationFlags(reel: true, profile: false, motion: false)
        XCTAssertEqual(
            OnboardingValidation.referenceValidationMessage(flags: reelOnly),
            "Add at least one reel URL to continue."
        )
    }

    func testReferenceListDisplayLabelDoesNotDoubleProfileAtSign() {
        XCTAssertEqual(profile.listDisplayLabel, "@creator · profile")
        XCTAssertEqual(reel.listDisplayLabel, "▶ instagram.com/reel/abc")
    }

    // MARK: - Reference parsing

    func testParsesReelURL() throws {
        let result = try OnboardingReferenceParser.parse(
            "https://www.instagram.com/reel/ABC123/"
        ).get()

        XCTAssertTrue(result.reference.isReel)
        XCTAssertFalse(result.needsProfileVerification)
        XCTAssertEqual(result.reference.key, "instagram:reel:ABC123")
    }

    func testParsesProfileHandle() throws {
        let result = try OnboardingReferenceParser.parse(
            "@Creator_Name"
        ).get()

        XCTAssertTrue(result.reference.isProfile)
        XCTAssertTrue(result.needsProfileVerification)
        XCTAssertEqual(result.handle, "creator_name")
    }

    func testParsesProfileURL() throws {
        let result = try OnboardingReferenceParser.parse(
            "https://instagram.com/somehandle"
        ).get()

        XCTAssertTrue(result.reference.isProfile)
        XCTAssertTrue(result.needsProfileVerification)
        XCTAssertEqual(result.handle, "somehandle")
        XCTAssertEqual(result.reference.key, "handle:somehandle")
    }

    func testClassifiesHandleAsProfileWithoutExpectedKind() throws {
        let result = try OnboardingReferenceParser.parse("@creator").get()
        XCTAssertTrue(result.reference.isProfile)
    }

    func testRejectsStoryAndNonInstagram() {
        let story = OnboardingReferenceParser.parse("https://www.instagram.com/stories/creator/123")
        guard case .failure(let storyError) = story else {
            return XCTFail("Expected story failure")
        }
        XCTAssertEqual(storyError, .unsupportedStory)

        let other = OnboardingReferenceParser.parse("https://youtube.com/watch?v=abc")
        guard case .failure(let otherError) = other else {
            return XCTFail("Expected non-Instagram failure")
        }
        XCTAssertEqual(otherError, .nonInstagram)
    }

    func testAutoAddDetectsCompleteReelURLOnPaste() {
        XCTAssertTrue(
            OnboardingReferenceParser.shouldAutoAddCompleteReelOrPost(
                previous: "",
                current: "https://www.instagram.com/reel/ABC123xyz/"
            )
        )
        XCTAssertFalse(
            OnboardingReferenceParser.shouldAutoAddCompleteReelOrPost(
                previous: "",
                current: "@creator"
            )
        )
        XCTAssertFalse(
            OnboardingReferenceParser.shouldAutoAddCompleteReelOrPost(
                previous: "https://www.instagram.com/reel/ABC",
                current: "https://www.instagram.com/reel/ABCD"
            )
        )
    }

    // MARK: - View model

    func testContinueFromReferencesDoesNotAdvanceWhenMixIncomplete() async {
        let store = UserDefaultsOnboardingStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let model = OnboardingViewModel(store: store)

        await model.continueFromReferences(reduceMotion: true)
        XCTAssertEqual(model.step, .interests)
        XCTAssertTrue(model.referenceValidation.reel)
        XCTAssertTrue(model.referenceValidation.profile)
        XCTAssertFalse(model.referenceValidation.motion)
        XCTAssertEqual(
            model.referenceValidationMessage,
            "Add at least one reel URL and one profile @handle to continue."
        )
    }

    func testContinueFromReferencesFlagsOnlyMissingReel() async {
        let model = OnboardingViewModel(store: UserDefaultsOnboardingStore(defaults: defaults))
        model.references = [profile]

        await model.continueFromReferences(reduceMotion: false)

        XCTAssertEqual(model.step, .interests)
        XCTAssertFalse(model.referenceValidation.profile)
        XCTAssertTrue(model.referenceValidation.motion)
        XCTAssertEqual(model.referenceInputKind, .reel)
        XCTAssertEqual(
            model.referenceValidationMessage,
            "Add at least one reel URL to continue."
        )
    }

    func testContinueFromReferencesFlagsOnlyMissingProfile() async {
        let model = OnboardingViewModel(store: UserDefaultsOnboardingStore(defaults: defaults))
        model.references = [reel]

        await model.continueFromReferences(reduceMotion: false)

        XCTAssertEqual(model.step, .interests)
        XCTAssertFalse(model.referenceValidation.reel)
        XCTAssertTrue(model.referenceValidation.profile)
        XCTAssertTrue(model.referenceValidation.motion)
        XCTAssertEqual(model.referenceInputKind, .profile)
        XCTAssertEqual(
            model.referenceValidationMessage,
            "Add at least one profile @handle to continue."
        )
    }

    func testContinueFromReferencesAdvancesWhenMixComplete() async {
        let model = OnboardingViewModel(store: UserDefaultsOnboardingStore(defaults: defaults))
        model.references = [reel, profile]

        await model.continueFromReferences(reduceMotion: false)

        XCTAssertEqual(model.step, .review)
        XCTAssertEqual(model.referenceValidation, .none)
    }

    func testConsumeReferenceAttentionMotionKeepsValidationFlags() {
        let model = OnboardingViewModel(store: UserDefaultsOnboardingStore(defaults: defaults))
        model.referenceValidation = OnboardingReferenceValidationFlags(reel: true, profile: true, motion: true)

        model.consumeReferenceAttentionMotionIfNeeded()

        XCTAssertTrue(model.referenceValidation.reel)
        XCTAssertTrue(model.referenceValidation.profile)
        XCTAssertFalse(model.referenceValidation.motion)
    }

    func testSoftSkipDoesNotRequireReferenceMix() {
        let model = OnboardingViewModel(store: UserDefaultsOnboardingStore(defaults: defaults))

        model.softSkip()

        XCTAssertTrue(model.sessionDismissed)
        XCTAssertEqual(model.step, .interests)
        XCTAssertEqual(model.references.count, 0)
        XCTAssertEqual(model.toastMessage, "You can finish setup in You.")
    }

    func testAddProfileVerificationVerifiedShowsProfileAdded() async {
        let model = OnboardingViewModel(
            store: UserDefaultsOnboardingStore(defaults: defaults),
            profileVerifier: FixtureOnboardingProfileVerifier(configuredStatus: .verified)
        )
        model.referenceInputKind = .profile
        model.referenceDraftText = "@creator"

        await model.addReference()

        XCTAssertEqual(model.references.count, 1)
        XCTAssertEqual(model.toastMessage, "Profile added")
    }

    func testAddProfileVerificationNotFoundDoesNotAppendReference() async {
        let model = OnboardingViewModel(
            store: UserDefaultsOnboardingStore(defaults: defaults),
            profileVerifier: FixtureOnboardingProfileVerifier(notFoundHandles: ["ghost"])
        )
        model.referenceInputKind = .profile
        model.referenceDraftText = "@ghost"

        await model.addReference()

        XCTAssertTrue(model.references.isEmpty)
        XCTAssertEqual(model.toastMessage, "@ghost wasn't found on Instagram")
    }

    func testAddProfileVerificationTemporarilyUnavailableKeepsProfile() async {
        let model = OnboardingViewModel(
            store: UserDefaultsOnboardingStore(defaults: defaults),
            profileVerifier: FixtureOnboardingProfileVerifier(configuredStatus: .temporarilyUnavailable)
        )
        model.referenceInputKind = .profile
        model.referenceDraftText = "@creator"

        await model.addReference()

        XCTAssertEqual(model.references.count, 1)
        XCTAssertEqual(model.toastMessage, "Profile added. We couldn't check Instagram right now.")
    }

    func testAddReelAndProfileFromDraftTextThenContinue() async {
        let model = OnboardingViewModel(
            store: UserDefaultsOnboardingStore(defaults: defaults),
            profileVerifier: FixtureOnboardingProfileVerifier(configuredStatus: .verified)
        )
        model.referenceDraftText = "https://www.instagram.com/reel/ABC123/"

        await model.addReference(from: "https://www.instagram.com/reel/ABC123/")

        XCTAssertEqual(model.references.count, 1)
        XCTAssertTrue(model.references[0].isReel)
        XCTAssertEqual(model.referenceDraftText, "")

        model.referenceDraftText = "@somehandle"
        await model.addReference(from: "@somehandle")

        XCTAssertEqual(model.references.count, 2)
        XCTAssertTrue(model.references.contains(where: \.isProfile))
        XCTAssertEqual(model.referenceValidation, .none)

        await model.continueFromReferences(reduceMotion: false)

        XCTAssertEqual(model.step, .review)
    }

    func testAddReferenceClearsValidationWhenMixBecomesComplete() async {
        let model = OnboardingViewModel(
            store: UserDefaultsOnboardingStore(defaults: defaults),
            profileVerifier: FixtureOnboardingProfileVerifier(configuredStatus: .verified)
        )
        model.references = [reel]
        await model.continueFromReferences(reduceMotion: false)

        XCTAssertTrue(model.referenceValidation.profile)

        model.referenceInputKind = .profile
        await model.addReference(from: "@creator")

        XCTAssertEqual(model.referenceValidation, .none)
    }

    func testHandleDraftChangeAutoAddsCompleteReelURL() async {
        let model = OnboardingViewModel(
            store: UserDefaultsOnboardingStore(defaults: defaults),
            profileVerifier: FixtureOnboardingProfileVerifier(configuredStatus: .verified)
        )

        await model.handleDraftChange(
            previous: "",
            current: "https://www.instagram.com/reel/ABC123xyz01/"
        )

        XCTAssertEqual(model.references.count, 1)
        XCTAssertTrue(model.references[0].isReel)
        XCTAssertEqual(model.referenceDraftText, "")
        XCTAssertEqual(model.toastMessage, "Reel added")
    }

    func testHandleDraftChangeDoesNotAutoAddHandle() async {
        let model = OnboardingViewModel(store: UserDefaultsOnboardingStore(defaults: defaults))

        await model.handleDraftChange(previous: "", current: "@creator")

        XCTAssertTrue(model.references.isEmpty)
        XCTAssertEqual(model.referenceDraftText, "@creator")
        XCTAssertNil(model.toastMessage)
    }

    func testSubmitDraftAddsHandle() async {
        let model = OnboardingViewModel(
            store: UserDefaultsOnboardingStore(defaults: defaults),
            profileVerifier: FixtureOnboardingProfileVerifier(configuredStatus: .verified)
        )
        model.referenceDraftText = "@creator"

        await model.submitDraftIfPresent()

        XCTAssertEqual(model.references.count, 1)
        XCTAssertTrue(model.references[0].isProfile)
        XCTAssertEqual(model.referenceDraftText, "")
    }

    func testContinueAddsLeftoverThenBlocksWhenMixIncomplete() async {
        let model = OnboardingViewModel(
            store: UserDefaultsOnboardingStore(defaults: defaults),
            profileVerifier: FixtureOnboardingProfileVerifier(configuredStatus: .verified)
        )
        model.referenceDraftText = "@creator"

        await model.continueFromReferences(reduceMotion: true)

        XCTAssertEqual(model.references.count, 1)
        XCTAssertTrue(model.references[0].isProfile)
        XCTAssertEqual(model.step, .interests)
        XCTAssertEqual(
            model.referenceValidationMessage,
            "Add at least one reel URL to continue."
        )
    }

    func testBadPasteKeepsTextAndWarns() async {
        let model = OnboardingViewModel(store: UserDefaultsOnboardingStore(defaults: defaults))
        let junk = "https://youtube.com/watch?v=notareel"

        await model.handleDraftChange(previous: "", current: junk)

        XCTAssertTrue(model.references.isEmpty)
        XCTAssertEqual(model.referenceDraftText, junk)
        XCTAssertEqual(
            model.toastMessage,
            "Paste an Instagram link — instagram.com/reel/… or instagram.com/handle"
        )
    }

    func testProfileVerificationInconclusivePreviewAllowsAdd() async {
        let preview = ReferenceImportPreview(
            parserVersion: "v1",
            previewChecksum: "checksum",
            destination: ReferenceImportDestination(watchlistID: nil, watchlistName: "Inspiration"),
            counts: ReferenceImportCounts(
                totalRows: 1,
                cleanAccounts: 0,
                cleanReels: 0,
                cleanAudio: 0,
                needsReview: 0,
                duplicates: 0,
                invalid: 1,
                importable: 0
            ),
            rows: []
        )
        let verifier = ImportPreviewOnboardingProfileVerifier(
            repository: PreviewPassthroughOnboardingTestRepository(preview: preview),
            context: WorkspaceContext(
                workspaceID: UUID(),
                creatorID: UUID(),
                memberID: UUID()
            )
        )

        let result = await verifier.verify(handle: "creator")

        XCTAssertEqual(result.status, .temporarilyUnavailable)
    }

    func testFinishMarksStoreComplete() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let store = UserDefaultsOnboardingStore(defaults: defaults)
        let model = OnboardingViewModel(store: store)
        model.interestIDs = ["food"]
        model.formats = [.talkingToCamera]
        model.timeToCreate = .tenToThirty
        model.showFace = true
        model.useVoice = true
        model.selectedTasteExampleIDs = ["food-rec-1"]

        let handoff = model.finishAndGenerateFirstDay(todayDate: "2026-08-07")
        XCTAssertEqual(handoff.scheduledDate, "2026-08-07")
        XCTAssertFalse(store.isComplete())
        XCTAssertNil(handoff.dayBrief)
    }

    // MARK: - Reference import

    func testRawTextMapsReelURLAndProfileHandle() {
        XCTAssertEqual(OnboardingReferenceImport.rawText(for: reel), reel.url)
        XCTAssertEqual(OnboardingReferenceImport.rawText(for: profile), "@creator")
        XCTAssertEqual(OnboardingReferenceImport.inputType(for: reel), .paste)
        XCTAssertEqual(OnboardingReferenceImport.inputType(for: profile), .paste)
    }

    func testImporterPreviewThenConfirmsEachReference() async {
        let recorder = OnboardingImportTestRecorder()

        let importer = OnboardingReferenceImporter(
            preview: { rawText, inputType in
                await recorder.recordPreview(rawText: rawText, inputType: inputType)
                let count = await recorder.previewCount()
                return ReferenceImportPreview(
                    parserVersion: "v1",
                    previewChecksum: "checksum-\(count)",
                    destination: ReferenceImportDestination(watchlistID: nil, watchlistName: "Inspiration"),
                    counts: ReferenceImportCounts(
                        totalRows: 1,
                        cleanAccounts: 1,
                        cleanReels: 0,
                        cleanAudio: 0,
                        needsReview: 0,
                        duplicates: 0,
                        invalid: 0,
                        importable: 1
                    ),
                    rows: []
                )
            },
            confirm: { rawText, inputType, previewChecksum in
                await recorder.recordConfirm(
                    rawText: rawText,
                    inputType: inputType,
                    previewChecksum: previewChecksum
                )
                return ReferenceImportConfirmResult(
                    parserVersion: "v1",
                    destination: ReferenceImportDestination(watchlistID: nil, watchlistName: "Inspiration"),
                    counts: ReferenceImportConfirmCounts(
                        imported: 1,
                        needsReview: 0,
                        duplicatesSkipped: 0,
                        invalid: 0
                    ),
                    toast: "Imported 1."
                )
            }
        )

        let outcome = await importer.importReferences([reel, profile])

        XCTAssertEqual(outcome, OnboardingReferenceImportOutcome(confirmed: 2, skipped: 0, failed: 0))
        let previewCalls = await recorder.previewCalls()
        let confirmCalls = await recorder.confirmCalls()
        XCTAssertEqual(previewCalls.map(\.0), [reel.url, "@creator"])
        XCTAssertEqual(previewCalls.map(\.1), [.paste, .paste])
        XCTAssertEqual(confirmCalls.map(\.0), [reel.url, "@creator"])
        XCTAssertEqual(confirmCalls.map(\.2), ["checksum-1", "checksum-2"])
    }

    func testImporterSkipsReferencesWithNothingImportable() async {
        let recorder = OnboardingImportTestRecorder()
        let importer = OnboardingReferenceImporter(
            preview: { _, _ in
                ReferenceImportPreview(
                    parserVersion: "v1",
                    previewChecksum: "checksum",
                    destination: ReferenceImportDestination(watchlistID: nil, watchlistName: "Inspiration"),
                    counts: ReferenceImportCounts(
                        totalRows: 1,
                        cleanAccounts: 0,
                        cleanReels: 0,
                        cleanAudio: 0,
                        needsReview: 0,
                        duplicates: 0,
                        invalid: 1,
                        importable: 0
                    ),
                    rows: []
                )
            },
            confirm: { rawText, inputType, previewChecksum in
                await recorder.recordConfirm(
                    rawText: rawText,
                    inputType: inputType,
                    previewChecksum: previewChecksum
                )
                return nil
            }
        )

        let outcome = await importer.importReferences([profile])

        let confirmCount = await recorder.confirmCalls().count
        XCTAssertEqual(outcome, OnboardingReferenceImportOutcome(confirmed: 0, skipped: 1, failed: 0))
        XCTAssertEqual(confirmCount, 0)
    }
}

private struct PreviewPassthroughOnboardingTestRepository: ReferenceImportRepository {
    let preview: ReferenceImportPreview

    func previewImport(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String?,
        context: WorkspaceContext
    ) async throws -> ReferenceImportPreview {
        preview
    }

    func confirmImport(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String?,
        previewChecksum: String,
        context: WorkspaceContext
    ) async throws -> ReferenceImportConfirmResult {
        throw RepositoryError.notConfigured("Preview passthrough only.")
    }

    func reviewItem(
        _ request: ReferenceReviewRequest,
        context: WorkspaceContext
    ) async throws -> ReferenceReviewResult {
        throw RepositoryError.notConfigured("Preview passthrough only.")
    }
}

private actor OnboardingImportTestRecorder {
    private var previews: [(String, ReferenceImportInputType)] = []
    private var confirms: [(String, ReferenceImportInputType, String)] = []

    func recordPreview(rawText: String, inputType: ReferenceImportInputType) {
        previews.append((rawText, inputType))
    }

    func recordConfirm(rawText: String, inputType: ReferenceImportInputType, previewChecksum: String) {
        confirms.append((rawText, inputType, previewChecksum))
    }

    func previewCount() -> Int {
        previews.count
    }

    func previewCalls() -> [(String, ReferenceImportInputType)] {
        previews
    }

    func confirmCalls() -> [(String, ReferenceImportInputType, String)] {
        confirms
    }
}
