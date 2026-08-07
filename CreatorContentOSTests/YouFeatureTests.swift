import XCTest
@testable import CreatorContentOS

@MainActor
final class YouFeatureTests: XCTestCase {
    func testContentCategorySelectionMapsPresetAndCustomPillars() {
        let selection = ContentCategorySelection.from(contentPillars: ["Fitness", "Travel", "Custom niche"])
        XCTAssertEqual(selection.selectedIDs, ["fitness", "travel", "other"])
        XCTAssertEqual(selection.customOtherLabel, "Custom niche")
        XCTAssertEqual(selection.resolvedContentPillars(), ["Fitness", "Travel", "Custom niche"])
    }

    func testContentCategorySelectionEnforcesMaxThree() {
        var selection = ContentCategorySelection(selectedIDs: ["fitness", "travel"], customOtherLabel: "")
        selection.toggle("food")
        XCTAssertEqual(selection.selectedIDs, ["fitness", "travel", "food"])
        selection.toggle("tech")
        XCTAssertEqual(selection.selectedIDs, ["fitness", "travel", "food"])
    }

    func testContentCategoryOtherRequiresCustomLabel() {
        var selection = ContentCategorySelection(selectedIDs: ["other"], customOtherLabel: "")
        XCTAssertFalse(selection.isValid)
        selection.customOtherLabel = "Coaching"
        XCTAssertTrue(selection.isValid)
        XCTAssertEqual(selection.resolvedContentPillars(), ["Coaching"])
    }

    func testCreatorProfileUpdatePersistsCategoryPillars() async {
        let services = AppServices.fixtureBacked()
        let update = CreatorProfileUpdate(
            positioning: services.creatorProfileSummary.positioning,
            voiceRules: services.creatorProfileSummary.voiceRules,
            contentPillars: ["Fitness", "Food"],
            captionStyle: services.creatorProfileSummary.captionStyle ?? "",
            noGoTopics: services.creatorProfileSummary.noGoTopics,
            recurringFormats: services.creatorProfileSummary.recurringFormats
        )

        let didSave = await services.updateCreatorProfileImmediately(update)

        XCTAssertTrue(didSave)
        XCTAssertEqual(services.creatorProfileSummary.contentPillars, ["Fitness", "Food"])
    }

    func testPlanYouNavigationRequestsYouTabAndPreservesPlanDate() {
        let state = AppState(runtime: .fixtures(), authenticationPhase: .live)
        state.requestYouDestination(.creatorVoice, from: .plan(selectedDate: "2026-07-21"))

        XCTAssertEqual(state.pendingCreatorTab, .you)
        XCTAssertEqual(state.pendingYouNavigation?.destination, .creatorVoice)
        XCTAssertEqual(state.youNavigationOrigin, .plan(selectedDate: "2026-07-21"))
    }

    func testReturnToPlanRestoresSelectedDateAndPlanTab() {
        let state = AppState(runtime: .fixtures(), authenticationPhase: .live)
        state.recordYouNavigationOrigin(.plan(selectedDate: "2026-07-21"))
        state.returnToPlan(fromYouDestination: "2026-07-21")

        XCTAssertEqual(state.planSelectedDate, "2026-07-21")
        XCTAssertEqual(state.pendingCreatorTab, .plan)
        XCTAssertNil(state.youNavigationOrigin)
    }

    func testImportPreviewProfileVerificationMapsCleanAccountAsVerified() async {
        let preview = ReferenceImportPreview(
            parserVersion: "v1",
            previewChecksum: "checksum",
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
            rows: [
                ReferenceImportRow(
                    clientRowID: "1",
                    lineNumber: 1,
                    rawInput: "@fitover60",
                    typeChip: .account,
                    classification: "account",
                    title: "@fitover60",
                    url: nil,
                    notes: nil,
                    previewState: .clean,
                    duplicateReason: nil,
                    invalidReason: nil
                ),
            ]
        )
        let verifier = ImportPreviewOnboardingProfileVerifier(
            repository: YouFeaturePreviewRepository(preview: preview),
            context: .creatorFixture
        )

        let result = await verifier.verify(handle: "fitover60")

        XCTAssertEqual(result.status, .verified)
        XCTAssertEqual(result.handle, "fitover60")
    }

    func testImportPreviewProfileVerificationMapsNotFoundInvalidReason() async {
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
            rows: [
                ReferenceImportRow(
                    clientRowID: "1",
                    lineNumber: 1,
                    rawInput: "@missingcreator",
                    typeChip: .account,
                    classification: "account",
                    title: "@missingcreator",
                    url: nil,
                    notes: nil,
                    previewState: .invalid,
                    duplicateReason: nil,
                    invalidReason: "Instagram account not found"
                ),
            ]
        )
        let verifier = ImportPreviewOnboardingProfileVerifier(
            repository: YouFeaturePreviewRepository(preview: preview),
            context: .creatorFixture
        )

        let result = await verifier.verify(handle: "missingcreator")

        XCTAssertEqual(result.status, .notFound)
    }

    func testImportPreviewProfileVerificationMapsUnavailablePreview() async {
        let services = AppServices.fixtureBacked(isLiveSupabaseRuntime: false)
        let result = await services.verifyInstagramProfileImmediately("@creator")

        XCTAssertEqual(result.status, .temporarilyUnavailable)
    }

    func testCreatorVoiceSavePolicyAllowsEmptyWhenDeferred() {
        XCTAssertTrue(
            YouCreatorVoiceSavePolicy.canSave(
                isDirty: true,
                isSaving: false,
                canEdit: true,
                positioning: "",
                voiceRulesText: "",
                voiceDeferred: true
            )
        )
        XCTAssertFalse(
            YouCreatorVoiceSavePolicy.canSave(
                isDirty: true,
                isSaving: false,
                canEdit: true,
                positioning: "",
                voiceRulesText: "",
                voiceDeferred: false
            )
        )
        XCTAssertTrue(
            YouCreatorVoiceSavePolicy.canSave(
                isDirty: true,
                isSaving: false,
                canEdit: true,
                positioning: "Fitness coach",
                voiceRulesText: "Keep it punchy",
                voiceDeferred: false
            )
        )
    }
}

private struct YouFeaturePreviewRepository: ReferenceImportRepository {
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
        throw RepositoryError.notConfigured("Preview only.")
    }

    func reviewItem(
        _ request: ReferenceReviewRequest,
        context: WorkspaceContext
    ) async throws -> ReferenceReviewResult {
        throw RepositoryError.notConfigured("Preview only.")
    }
}
