import XCTest
@testable import CreatorContentOS

@MainActor
final class ManagerAdminUsageTests: XCTestCase {
    func testFixtureNeedsReviewRowsAreActionable() throws {
        let needsReview = IntelligenceHome.raceWeekLibrary.needsReview

        XCTAssertFalse(needsReview.isEmpty)
        XCTAssertTrue(needsReview.allSatisfy { $0.reviewItem != nil })
        XCTAssertTrue(needsReview.contains { $0.typeChip == .reel && $0.sourceURL != nil })
        XCTAssertTrue(needsReview.contains { $0.typeChip == .unknown })
    }

    func testGrowthReferenceCatalogContainsCreatorSpecificInstagramPatterns() throws {
        let references = IntelligenceHome.raceWeekLibrary.growthReferences

        XCTAssertEqual(references.count, 6)
        XCTAssertTrue(references.contains { $0.id == "creator-age-myth-reversal" })
        XCTAssertTrue(references.contains { $0.id == "creator-real-life-contradiction-hook" })
        XCTAssertTrue(references.contains { $0.title == "Instagram Reels Default" })
        XCTAssertTrue(references.allSatisfy { !$0.hookFormulas.isEmpty })
        XCTAssertTrue(references.allSatisfy { !$0.sourceURLs.isEmpty })
        XCTAssertTrue(
            references.contains { reference in
                reference.hookFormulas.contains("I eat out. I drink sometimes. I still stay fit at 62.")
            }
        )
    }

    func testRegenerateDailyCardRejectsPastDate() async throws {
        let services = makeServices()

        do {
            _ = try await services.regeneratedDailyCard(scheduledDate: "2026-05-30", preserveManualEdits: false)
            XCTFail("Expected past_generation_date_not_allowed error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("past_generation_date_not_allowed"))
        }
    }

    func testRegenerateDailyCardAcceptsToday() async throws {
        let services = makeServices()

        do {
            _ = try await services.regeneratedDailyCard(scheduledDate: "2026-06-01", preserveManualEdits: false)
            XCTFail("Expected repository error (regeneration not configured), not past-date guard")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains("past_generation_date_not_allowed"),
                           "Should pass the past-date guard and reach repository")
        }
    }

    func testManagerUpdatesCreatorProfileOutsideWeeklySetup() async throws {
        let profileRepository = RecordingCreatorProfileRepository()
        let services = makeServices(creatorProfile: profileRepository)
        let update = CreatorProfileUpdate(
            positioning: "Lifestyle creator voice for busy weeks.",
            voiceRules: ["Warm", "Direct", "Light Hinglish when natural"],
            contentPillars: ["gym", "lifestyle", "eating", "recovery"],
            captionStyle: "Short and useful.",
            noGoTopics: ["Politics", "Weight talk"],
            recurringFormats: ["one practical detail", "caption-only backup"]
        )

        let didSave = await services.updateCreatorProfileImmediately(update)

        XCTAssertTrue(didSave)
        XCTAssertEqual(services.creatorProfileSummary.positioning, update.positioning)
        XCTAssertEqual(services.creatorProfileSummary.voiceRules, update.voiceRules)
        XCTAssertEqual(services.creatorProfileSummary.contentPillars, update.contentPillars)
        XCTAssertEqual(services.creatorProfileSummary.captionStyle, update.captionStyle)
        XCTAssertEqual(services.creatorProfileSummary.noGoTopics, update.noGoTopics)
        XCTAssertEqual(services.creatorProfileSummary.recurringFormats, update.recurringFormats)
        XCTAssertEqual(services.lastActionMessage, "Creator profile saved.")
        XCTAssertNil(services.creatorProfileEditError)

        let updates = await profileRepository.recordedUpdates()
        XCTAssertEqual(updates, [update])
    }

    func testManagerReferenceImportPreviewAndConfirmRefreshesIntelligence() async throws {
        let refreshedHome = IntelligenceHome.adminUsageReviewCleared
        let importRepository = RecordingReferenceImportRepository()
        let intelligenceRepository = RecordingIntelligenceRepository(home: refreshedHome)
        let services = makeServices(
            referenceImport: importRepository,
            intelligence: intelligenceRepository,
            isLiveSupabaseRuntime: true
        )
        let rawText = """
        @fitover60
        https://www.instagram.com/reel/ABC123/
        post-run family moment
        """

        let preview = await services.previewReferenceImportImmediately(
            rawText: rawText,
            inputType: .paste
        )

        XCTAssertEqual(preview?.previewChecksum, "fixture")
        XCTAssertEqual(services.referenceImportPreview?.counts.importable, 6)
        XCTAssertNil(services.lastReferenceImportError)

        let result = await services.confirmReferenceImportImmediately(
            rawText: rawText,
            inputType: .paste,
            previewChecksum: "fixture"
        )

        XCTAssertEqual(result?.counts.imported, 5)
        XCTAssertEqual(result?.counts.needsReview, 1)
        XCTAssertEqual(services.referenceImportConfirmResult?.toast, "Imported 5. 1 needs review.")
        XCTAssertEqual(services.referenceImportToast, "Imported 5. 1 needs review.")
        XCTAssertEqual(services.lastActionMessage, "Imported 5. 1 needs review.")
        XCTAssertEqual(services.intelligenceHome, refreshedHome)
        XCTAssertNil(services.lastReferenceImportError)

        let previewRequests = await importRepository.recordedPreviewRequests()
        XCTAssertEqual(previewRequests.map(\.rawText), [rawText])
        XCTAssertEqual(previewRequests.map(\.inputType), [.paste])

        let confirmRequests = await importRepository.recordedConfirmRequests()
        XCTAssertEqual(confirmRequests.map(\.previewChecksum), ["fixture"])
        let homeCallCount = await intelligenceRepository.homeCallCount()
        XCTAssertEqual(homeCallCount, 1)
    }

    func testReferenceImportPreviewMapsRowLimitError() async {
        let importRepository = RecordingReferenceImportRepository(
            previewError: RepositoryError.edgeFunction("row_limit_exceeded")
        )
        let services = makeServices(
            referenceImport: importRepository,
            isLiveSupabaseRuntime: true
        )

        let preview = await services.previewReferenceImportImmediately(
            rawText: "@creator",
            inputType: .paste
        )

        XCTAssertNil(preview)
        XCTAssertNil(services.referenceImportPreview)
        XCTAssertEqual(
            services.lastReferenceImportError,
            "This import is too large. Split it into smaller batches and try again."
        )
        XCTAssertNil(services.referenceImportToast)
    }

    func testReferenceImportConfirmMapsChecksumMismatchError() async {
        let importRepository = RecordingReferenceImportRepository(
            confirmError: RepositoryError.edgeFunction("checksum_mismatch")
        )
        let intelligenceRepository = RecordingIntelligenceRepository(home: .adminUsageReviewCleared)
        let services = makeServices(
            referenceImport: importRepository,
            intelligence: intelligenceRepository,
            isLiveSupabaseRuntime: true
        )

        let result = await services.confirmReferenceImportImmediately(
            rawText: "@creator",
            inputType: .paste,
            previewChecksum: "stale"
        )

        XCTAssertNil(result)
        XCTAssertNil(services.referenceImportConfirmResult)
        XCTAssertEqual(services.lastReferenceImportError, "The import changed. Preview it again before saving.")
        XCTAssertNil(services.referenceImportToast)
        let homeCallCount = await intelligenceRepository.homeCallCount()
        XCTAssertEqual(homeCallCount, 0)
    }

    func testManagerReviewsNeedsYourCallItemAndHomeRefreshes() async throws {
        let reviewItemID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        let importRepository = RecordingReferenceImportRepository()
        let intelligenceRepository = RecordingIntelligenceRepository(home: .adminUsageReviewCleared)
        let services = makeServices(
            referenceImport: importRepository,
            intelligence: intelligenceRepository,
            isLiveSupabaseRuntime: true
        )
        let edit = ReferenceReviewEdit(
            targetType: .reel,
            handle: nil,
            url: "https://www.instagram.com/reel/ABC123/",
            notes: "Good race-week pattern."
        )

        let result = await services.reviewReferenceItemImmediately(
            ReferenceReviewRequest(
                item: ReferenceReviewItem(kind: .sourceReference, id: reviewItemID),
                action: .edit,
                edit: edit
            )
        )

        XCTAssertEqual(result?.itemID, reviewItemID)
        XCTAssertEqual(result?.action, .edit)
        XCTAssertEqual(result?.resultStatus, "confirmed")
        XCTAssertEqual(services.referenceReviewResult?.toast, "Reference confirmed.")
        XCTAssertEqual(services.referenceImportToast, "Reference confirmed.")
        XCTAssertEqual(services.lastActionMessage, "Reference confirmed.")
        XCTAssertEqual(services.intelligenceHome.needsReview, [])
        XCTAssertNil(services.lastReferenceImportError)

        let reviewRequests = await importRepository.recordedReviewRequests()
        XCTAssertEqual(reviewRequests.map(\.item.id), [reviewItemID])
        XCTAssertEqual(reviewRequests.map(\.action), [.edit])
        XCTAssertEqual(reviewRequests.map(\.edit), [edit])
        let homeCallCount = await intelligenceRepository.homeCallCount()
        XCTAssertEqual(homeCallCount, 1)
    }

    func testReferenceReviewMapsStoryURLRejection() async {
        let importRepository = RecordingReferenceImportRepository(
            reviewError: RepositoryError.edgeFunction("story_urls_not_allowed")
        )
        let intelligenceRepository = RecordingIntelligenceRepository(home: .adminUsageReviewCleared)
        let services = makeServices(
            referenceImport: importRepository,
            intelligence: intelligenceRepository,
            isLiveSupabaseRuntime: true
        )

        let result = await services.reviewReferenceItemImmediately(
            ReferenceReviewRequest(
                item: ReferenceReviewItem(
                    kind: .sourceReference,
                    id: UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!
                ),
                action: .edit,
                edit: ReferenceReviewEdit(
                    targetType: .reel,
                    handle: nil,
                    url: "https://www.instagram.com/stories/example/1/",
                    notes: nil
                )
            )
        )

        XCTAssertNil(result)
        XCTAssertNil(services.referenceReviewResult)
        XCTAssertEqual(
            services.lastReferenceImportError,
            "Story URLs cannot be used as references. Add a reel, post, audio link, or account instead."
        )
        XCTAssertNil(services.referenceImportToast)
        let homeCallCount = await intelligenceRepository.homeCallCount()
        XCTAssertEqual(homeCallCount, 0)
    }

    func testTesterAccessRequiresLiveOwnerRuntime() {
        XCTAssertFalse(makeServices().canManageTesterAccess)
        XCTAssertFalse(makeServices(isLiveSupabaseRuntime: true, memberRole: "editor").canManageTesterAccess)
        XCTAssertTrue(makeServices(isLiveSupabaseRuntime: true, memberRole: "owner").canManageTesterAccess)
    }

    private func makeServices(
        referenceImport: any ReferenceImportRepository = RecordingReferenceImportRepository(),
        intelligence: any IntelligenceRepository = FixtureIntelligenceRepository(),
        creatorProfile: any CreatorProfileRepository = FixtureCreatorProfileRepository(),
        isLiveSupabaseRuntime: Bool = false,
        memberRole: String = "owner",
        todayDate: @escaping TodayDateProvider = { "2026-06-01" }
    ) -> AppServices {
        let repositories = AppRepositories(
            context: .creatorFixture,
            today: FixtureTodayCardRepository(),
            weeklyPlans: FixtureWeeklyPlanRepository(),
            references: FixtureReferenceRepository(),
            referenceImport: referenceImport,
            intelligence: intelligence,
            creatorProfile: creatorProfile,
            archive: FixtureArchiveRepository()
        )

        return AppServices.fixtureBacked(
            repositories: repositories,
            isLiveSupabaseRuntime: isLiveSupabaseRuntime,
            memberRole: memberRole,
            todayCache: AdminUsageMemoryTodayCacheStore(),
            notifications: NoopTodayNotificationScheduler(),
            todayDate: todayDate
        )
    }
}

private actor RecordingCreatorProfileRepository: CreatorProfileRepository {
    private var summary: CreatorProfileSummary
    private var updates: [CreatorProfileUpdate] = []
    private let error: Error?

    init(
        summary: CreatorProfileSummary = .creatorFixture,
        error: Error? = nil
    ) {
        self.summary = summary
        self.error = error
    }

    func activeProfileSummary(for context: WorkspaceContext) async throws -> CreatorProfileSummary {
        summary
    }

    func updateProfile(_ update: CreatorProfileUpdate, context: WorkspaceContext) async throws -> CreatorProfileSummary {
        updates.append(update)

        if let error {
            throw error
        }

        summary = CreatorProfileSummary(
            displayName: summary.displayName,
            positioning: update.positioning,
            voiceLine: update.voiceRules.joined(separator: ", "),
            noGoTopics: update.noGoTopics,
            voiceRules: update.voiceRules,
            contentPillars: update.contentPillars,
            captionStyle: update.captionStyle,
            recurringFormats: update.recurringFormats
        )
        return summary
    }

    func recordedUpdates() -> [CreatorProfileUpdate] {
        updates
    }
}

private struct PreviewRequest: Hashable, Sendable {
    var rawText: String
    var inputType: ReferenceImportInputType
    var filename: String?
}

private struct ConfirmRequest: Hashable, Sendable {
    var rawText: String
    var inputType: ReferenceImportInputType
    var filename: String?
    var previewChecksum: String
}

private actor RecordingReferenceImportRepository: ReferenceImportRepository {
    private var previewRequests: [PreviewRequest] = []
    private var confirmRequests: [ConfirmRequest] = []
    private var reviewRequests: [ReferenceReviewRequest] = []
    private let previewError: Error?
    private let confirmError: Error?
    private let reviewError: Error?

    init(
        previewError: Error? = nil,
        confirmError: Error? = nil,
        reviewError: Error? = nil
    ) {
        self.previewError = previewError
        self.confirmError = confirmError
        self.reviewError = reviewError
    }

    func previewImport(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String?,
        context: WorkspaceContext
    ) async throws -> ReferenceImportPreview {
        previewRequests.append(
            PreviewRequest(rawText: rawText, inputType: inputType, filename: filename)
        )
        if let previewError {
            throw previewError
        }
        return .referenceImportFixture
    }

    func confirmImport(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String?,
        previewChecksum: String,
        context: WorkspaceContext
    ) async throws -> ReferenceImportConfirmResult {
        confirmRequests.append(
            ConfirmRequest(
                rawText: rawText,
                inputType: inputType,
                filename: filename,
                previewChecksum: previewChecksum
            )
        )
        if let confirmError {
            throw confirmError
        }
        return ReferenceImportConfirmResult(
            parserVersion: "v1",
            destination: ReferenceImportDestination(watchlistID: nil, watchlistName: "Inspiration"),
            counts: ReferenceImportConfirmCounts(
                imported: 5,
                needsReview: 1,
                duplicatesSkipped: 1,
                invalid: 1
            ),
            toast: "Imported 5. 1 needs review."
        )
    }

    func reviewItem(
        _ request: ReferenceReviewRequest,
        context: WorkspaceContext
    ) async throws -> ReferenceReviewResult {
        reviewRequests.append(request)
        if let reviewError {
            throw reviewError
        }
        return ReferenceReviewResult(
            itemID: request.item.id,
            kind: request.item.kind,
            action: request.action,
            resultStatus: "confirmed",
            toast: "Reference confirmed."
        )
    }

    func recordedPreviewRequests() -> [PreviewRequest] {
        previewRequests
    }

    func recordedConfirmRequests() -> [ConfirmRequest] {
        confirmRequests
    }

    func recordedReviewRequests() -> [ReferenceReviewRequest] {
        reviewRequests
    }
}

private actor RecordingIntelligenceRepository: IntelligenceRepository {
    private let home: IntelligenceHome
    private var calls = 0

    init(home: IntelligenceHome) {
        self.home = home
    }

    func home(for context: WorkspaceContext) async throws -> IntelligenceHome {
        calls += 1
        return home
    }

    func homeCallCount() -> Int {
        calls
    }
}

private final class AdminUsageMemoryTodayCacheStore: TodayCacheStoring {
    private var snapshots: [WorkspaceContext: CachedTodaySnapshot] = [:]

    func loadSnapshot(for context: WorkspaceContext) throws -> CachedTodaySnapshot? {
        snapshots[context]
    }

    func saveSnapshot(_ snapshot: CachedTodaySnapshot, for context: WorkspaceContext) throws {
        snapshots[context] = snapshot
    }

    func clearSnapshot(for context: WorkspaceContext) throws {
        snapshots[context] = nil
    }
}

private extension IntelligenceHome {
    static var adminUsageReviewCleared: IntelligenceHome {
        IntelligenceHome(
            sourcePulse: SourcePulseSummary(
                title: "Source Pulse",
                subtitle: "1 confirmed reel/audio reference.",
                references: [
                    ReferenceSummary(
                        title: "Race week warmup reel",
                        sourceType: "Reel link",
                        note: "Confirmed",
                        state: .approved,
                        symbol: "link",
                        sourceURL: "https://www.instagram.com/reel/ABC123/"
                    )
                ]
            ),
            readyForThisWeek: IntelligenceHome.raceWeekLibrary.readyForThisWeek,
            needsReview: [],
            ideaCandidates: IntelligenceHome.raceWeekLibrary.ideaCandidates,
            recentlyUsed: IntelligenceHome.raceWeekLibrary.recentlyUsed,
            librarySections: IntelligenceHome.raceWeekLibrary.librarySections
        )
    }
}
