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
            step: .references,
            selectedCategoryIDs: ["fitness", "food"],
            categoryOtherText: "",
            references: [
                OnboardingReference(
                    id: "r1",
                    kind: .reel,
                    label: "instagram.com/reel/abc",
                    key: "instagram:reel:abc",
                    url: "https://www.instagram.com/reel/abc/"
                ),
            ]
        )

        store.saveProgress(progress)
        let loaded = store.loadProgress()

        XCTAssertEqual(loaded?.step, .references)
        XCTAssertEqual(loaded?.selectedCategoryIDs, ["fitness", "food"])
        XCTAssertEqual(loaded?.references.count, 1)
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
                step: .categories,
                selectedCategoryIDs: ["gaming"],
                categoryOtherText: "",
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

    // MARK: - Validation

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

    // MARK: - Reference parsing

    func testParsesReelURL() throws {
        let result = try OnboardingReferenceParser.parse(
            "https://www.instagram.com/reel/ABC123/",
            expected: .reel
        ).get()

        XCTAssertTrue(result.reference.isReel)
        XCTAssertFalse(result.needsProfileVerification)
        XCTAssertEqual(result.reference.key, "instagram:reel:ABC123")
    }

    func testParsesProfileHandle() throws {
        let result = try OnboardingReferenceParser.parse(
            "@Creator_Name",
            expected: .profile
        ).get()

        XCTAssertTrue(result.reference.isProfile)
        XCTAssertTrue(result.needsProfileVerification)
        XCTAssertEqual(result.handle, "creator_name")
    }

    func testRejectsHandleWhenExpectingReel() {
        let failure = OnboardingReferenceParser.parse("@creator", expected: .reel)
        guard case .failure(let error) = failure else {
            return XCTFail("Expected failure")
        }
        XCTAssertEqual(error, .invalidHandle(expected: .reel))
    }

    func testRejectsReelURLWhenExpectingProfile() {
        let failure = OnboardingReferenceParser.parse(
            "https://www.instagram.com/reel/ABC123/",
            expected: .profile
        )
        guard case .failure(let error) = failure else {
            return XCTFail("Expected failure")
        }
        XCTAssertEqual(error, .wrongKind(expected: .profile))
    }

    // MARK: - View model

    func testContinueFromReferencesDoesNotAdvanceWhenMixIncomplete() {
        let store = UserDefaultsOnboardingStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let model = OnboardingViewModel(store: store)

        model.continueFromReferences(reduceMotion: true)
        XCTAssertEqual(model.step, .categories)
        XCTAssertTrue(model.referenceValidation.reel)
        XCTAssertTrue(model.referenceValidation.profile)
        XCTAssertFalse(model.referenceValidation.motion)
    }

    func testFinishMarksStoreComplete() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let store = UserDefaultsOnboardingStore(defaults: defaults)
        let model = OnboardingViewModel(store: store)
        model.selectedCategoryIDs = ["food"]
        model.references = [
            OnboardingReference(
                id: "1",
                kind: .reel,
                label: "reel",
                key: "instagram:reel:a",
                url: "https://www.instagram.com/reel/a/"
            ),
            OnboardingReference(
                id: "2",
                kind: .profile,
                label: "@c",
                key: "handle:c",
                url: "https://www.instagram.com/c/"
            ),
        ]

        let handoff = model.finishAndGenerateFirstDay(todayDate: "2026-08-07")
        XCTAssertEqual(handoff.scheduledDate, "2026-08-07")
        XCTAssertTrue(store.isComplete())
        XCTAssertFalse(model.shouldPresentOnboarding)
        XCTAssertTrue(handoff.dayBrief.contains("Food"))
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
