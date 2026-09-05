import XCTest
@testable import CreatorContentOS

@MainActor
final class FirstIdeaHandoffTests: XCTestCase {
    func testBriefBuilderIncludesInterestsWithoutHyrox() {
        let record = OnboardingRecord(
            completedData: OnboardingCompletedData(
                selectedCategoryIDs: ["books"],
                categoryOtherText: "",
                references: [],
                voiceDeferred: false
            )
        )

        let brief = OnboardingFirstIdeaBriefBuilder.buildDayBrief(from: record)
        XCTAssertTrue(brief.localizedCaseInsensitiveContains("Books"))
        XCTAssertFalse(brief.localizedCaseInsensitiveContains("HYROX"))
    }

    func testPlannerSkipsReadyPackage() {
        let record = OnboardingRecord(
            completedData: OnboardingCompletedData(
                selectedCategoryIDs: ["movies"],
                categoryOtherText: "",
                references: [],
                voiceDeferred: false
            )
        )

        let plan = OnboardingFirstIdeaHandoffPlanner.plan(
            scheduledDate: "2026-09-05",
            record: record,
            existingPackageStatus: "published",
            hasUserEditedPackage: false
        )

        XCTAssertFalse(plan.shouldGenerate)
        XCTAssertEqual(plan.skipReason, .skippedExistingReady)
        XCTAssertFalse(plan.dayBrief.isEmpty)
    }

    func testPlannerGeneratesWhenNoExistingPackage() {
        let record = OnboardingRecord(
            completedData: OnboardingCompletedData(
                selectedCategoryIDs: ["travel"],
                categoryOtherText: "",
                references: [],
                voiceDeferred: false
            )
        )

        let plan = OnboardingFirstIdeaHandoffPlanner.plan(
            scheduledDate: "2026-09-05",
            record: record,
            existingPackageStatus: nil,
            hasUserEditedPackage: false
        )

        XCTAssertTrue(plan.shouldGenerate)
        XCTAssertNil(plan.skipReason)
    }

    func testPlannerGeneratesWhenDraftHasGeneratedContent() {
        let record = OnboardingRecord(
            completedData: OnboardingCompletedData(
                selectedCategoryIDs: ["travel"],
                categoryOtherText: "",
                references: [],
                voiceDeferred: false
            )
        )

        let hasUserEdited = OnboardingFirstIdeaPackageEditDetector.hasUserEditedPackage(
            packageStatus: "draft",
            packageTitle: "Generated title",
            packageScript: "Generated script",
            packageCaption: "Generated caption",
            lastGeneratedSnapshot: nil
        )
        XCTAssertFalse(hasUserEdited)

        let plan = OnboardingFirstIdeaHandoffPlanner.plan(
            scheduledDate: "2026-09-05",
            record: record,
            existingPackageStatus: "draft",
            hasUserEditedPackage: hasUserEdited
        )

        XCTAssertTrue(plan.shouldGenerate)
        XCTAssertFalse(plan.makeAvailableOnly)
    }

    func testPlannerRetryAfterFailureUsesConfirmOverwriteForDraft() {
        let record = OnboardingRecord(
            completedData: OnboardingCompletedData(
                selectedCategoryIDs: ["books"],
                categoryOtherText: "",
                references: [],
                voiceDeferred: false
            )
        )

        let plan = OnboardingFirstIdeaHandoffPlanner.plan(
            scheduledDate: "2026-09-05",
            record: record,
            existingPackageStatus: "draft",
            hasUserEditedPackage: false,
            firstIdeaHandoffStatus: OnboardingFirstIdeaHandoffStatus.failed.rawValue,
            existingDraftIsComplete: false
        )

        XCTAssertTrue(plan.shouldGenerate)
        XCTAssertTrue(plan.confirmOverwrite)
        XCTAssertFalse(plan.makeAvailableOnly)
    }

    func testPlannerRetryAfterFailureSkipsGenerateWhenDraftComplete() {
        let record = OnboardingRecord(
            completedData: OnboardingCompletedData(
                selectedCategoryIDs: ["books"],
                categoryOtherText: "",
                references: [],
                voiceDeferred: false
            )
        )

        let plan = OnboardingFirstIdeaHandoffPlanner.plan(
            scheduledDate: "2026-09-05",
            record: record,
            existingPackageStatus: "draft",
            hasUserEditedPackage: false,
            firstIdeaHandoffStatus: OnboardingFirstIdeaHandoffStatus.failed.rawValue,
            existingDraftIsComplete: true
        )

        XCTAssertFalse(plan.shouldGenerate)
        XCTAssertTrue(plan.makeAvailableOnly)
        XCTAssertTrue(plan.confirmOverwrite)
    }

    func testEditDetectorFlagsOnlyWhenDraftDiffersFromSnapshot() {
        let snapshot = OnboardingFirstIdeaGeneratedDraftSnapshot(
            title: "Original title",
            script: "Original script",
            caption: "Original caption"
        )

        XCTAssertFalse(
            OnboardingFirstIdeaPackageEditDetector.hasUserEditedPackage(
                packageStatus: "draft",
                packageTitle: "Original title",
                packageScript: "Original script",
                packageCaption: "Original caption",
                lastGeneratedSnapshot: snapshot
            )
        )

        XCTAssertTrue(
            OnboardingFirstIdeaPackageEditDetector.hasUserEditedPackage(
                packageStatus: "draft",
                packageTitle: "Edited title",
                packageScript: "Original script",
                packageCaption: "Original caption",
                lastGeneratedSnapshot: snapshot
            )
        )
    }

    func testConfirmOnboardingSkipsWhenTodayCardHasUsableReadyPackage() async {
        let today = "2026-09-05"
        let services = AppServices.fixtureBacked(todayDate: { today })
        XCTAssertFalse(services.todayCard.scenes.isEmpty)

        let result = await services.confirmOnboardingAndPrepareFirstIdea(
            completedData: OnboardingCompletedData(
                selectedCategoryIDs: ["books"],
                categoryOtherText: "",
                references: [],
                voiceDeferred: false
            ),
            scheduledDate: today
        )

        XCTAssertEqual(result, .skippedExistingReady)
    }

    func testConfirmOnboardingMapsOverwriteRequiredToSkippedExistingReady() async {
        let today = "2026-09-05"
        let services = AppServices.fixtureBacked(todayDate: { today })
        services.todayCard = DailyCard(
            title: "Checking today's plan",
            context: "Fixture",
            effortLabel: "Loading",
            whyToday: "Loading",
            scenes: []
        )
        services.dayBriefGeneratedCards[today] = GeneratedDailyCardDraft(
            id: UUID(),
            scheduledDate: today,
            status: "draft",
            title: "Existing draft card",
            whyToday: "Fixture",
            growthJob: "",
            contentPillar: "lifestyle",
            shootability: "easy",
            estimatedShootMinutes: 10,
            energyRequired: "low",
            languageMode: "English",
            format: "Reel",
            primarySurface: "instagram_reels",
            durationSeconds: 30,
            hook: "Hook",
            saveShareReason: "",
            sceneList: [ShotScene(number: 1, title: "Scene", duration: "3 sec", symbol: "star")],
            script: "Script",
            noVoiceoverVersion: "",
            onScreenText: [],
            caption: "Caption",
            cta: "",
            hashtags: [],
            coverText: "",
            postInstructions: "",
            brandEventNotes: "",
            backupStory: "",
            backupCaptionOnly: "",
            audioOptionNotes: "",
            creatorFitScore: 90,
            riskNotes: [],
            assumptions: [],
            sourceNote: ""
        )

        let result = await services.confirmOnboardingAndPrepareFirstIdea(
            completedData: OnboardingCompletedData(
                selectedCategoryIDs: ["movies-tv"],
                categoryOtherText: "",
                references: [],
                voiceDeferred: false
            ),
            scheduledDate: today
        )

        XCTAssertEqual(result, .skippedExistingReady)
    }

    func testConfirmOnboardingPersistFailureDoesNotMarkCompleteInPresentation() async {
        let repository = FailingCreatorProfileRepository()
        let repositories = AppRepositories(
            context: .creatorFixture,
            today: FixtureTodayCardRepository(),
            weeklyPlans: FixtureWeeklyPlanRepository(),
            references: FixtureReferenceRepository(),
            intelligence: FixtureIntelligenceRepository(),
            creatorProfile: repository,
            archive: FixtureArchiveRepository()
        )
        let services = AppServices.fixtureBacked(repositories: repositories)

        let result = await services.confirmOnboardingAndPrepareFirstIdea(
            completedData: OnboardingCompletedData(
                selectedCategoryIDs: ["books"],
                categoryOtherText: "",
                references: [],
                voiceDeferred: false
            ),
            scheduledDate: "2026-09-05"
        )

        XCTAssertEqual(result, .persistFailed)
        XCTAssertEqual(repository.updateAttempts, 2)
    }

    func testConfirmOnboardingGeneratesBooksMoviesWhenTodayEmpty() async {
        let today = "2026-09-05"
        let trackingGeneration = TrackingDayGenerationRepository()
        let trackingWeekly = TrackingMakeDayAvailableWeeklyRepository()
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: trackingWeekly,
                references: FixtureReferenceRepository(),
                dailyGeneration: trackingGeneration,
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayDate: { today }
        )
        services.todayCard = .emptyTodayPlaceholder

        let completedData = booksMoviesCompletedData()
        let result = await services.confirmOnboardingAndPrepareFirstIdea(
            completedData: completedData,
            scheduledDate: today
        )

        guard case .completed = result else {
            return XCTFail("Expected completed handoff, got \(result)")
        }
        let brief = await trackingGeneration.lastDayBrief ?? ""
        let generateCalls = await trackingGeneration.generateCallCount
        let makeAvailableCalls = await trackingWeekly.makeDayAvailableCallCount
        XCTAssertTrue(brief.localizedCaseInsensitiveContains("Books"))
        XCTAssertTrue(brief.localizedCaseInsensitiveContains("Movies"))
        XCTAssertEqual(generateCalls, 1)
        XCTAssertEqual(makeAvailableCalls, 1)
        XCTAssertFalse(services.todayCard.title.localizedCaseInsensitiveContains("Race week"))
        XCTAssertFalse(services.todayCard.title.localizedCaseInsensitiveContains("HYROX"))
    }

    func testConfirmOnboardingSkipsReadyRaceWeekTodayWhenFlagOff() async {
        let today = "2026-09-05"
        let trackingGeneration = TrackingDayGenerationRepository()
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                dailyGeneration: trackingGeneration,
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayDate: { today }
        )
        XCTAssertFalse(services.todayCard.scenes.isEmpty)

        let result = await services.confirmOnboardingAndPrepareFirstIdea(
            completedData: booksMoviesCompletedData(),
            scheduledDate: today
        )

        XCTAssertEqual(result, .skippedExistingReady)
        let generateCalls = await trackingGeneration.generateCallCount
        XCTAssertEqual(generateCalls, 0)
    }

    func testFixtureProfileUpdateRoundTripsProductionFormats() async throws {
        let repository = FixtureCreatorProfileRepository()
        let context = WorkspaceContext.creatorFixture
        let update = OnboardingProfileMapper.profileUpdate(
            from: OnboardingRecord(completedData: booksMoviesCompletedData()),
            onboardingState: .established,
            onboardingCompletedAt: "2026-09-05T12:00:00Z"
        )

        let saved = try await repository.updateProfile(update, context: context)
        let reloaded = try await repository.activeProfileSummary(for: context)

        XCTAssertEqual(saved.productionFormats, ["voiceover_broll"])
        XCTAssertEqual(reloaded.productionFormats, ["voiceover_broll"])
        XCTAssertEqual(saved.timeToCreate, "ten_to_thirty")
        XCTAssertEqual(reloaded.timeToCreate, "ten_to_thirty")
        XCTAssertEqual(saved.onCameraRestrictions.showFace, false)
        XCTAssertEqual(reloaded.onCameraRestrictions.showFace, false)
        XCTAssertEqual(saved.onCameraRestrictions.useVoice, true)

        let productionSubtitle = YouProductionSelection.from(profile: reloaded).summarySubtitle
        XCTAssertFalse(productionSubtitle.contains("Not set"))
        XCTAssertTrue(productionSubtitle.localizedCaseInsensitiveContains("Voiceover"))
    }

    func testFirstIdeaGenerationFailureUsesHumanCopy() async {
        let today = "2026-09-05"
        let failingGeneration = FailingDayGenerationRepository()
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                dailyGeneration: failingGeneration,
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayDate: { today }
        )
        services.todayCard = .emptyTodayPlaceholder

        let result = await services.confirmOnboardingAndPrepareFirstIdea(
            completedData: booksMoviesCompletedData(),
            scheduledDate: today
        )

        guard case .generationFailed(let message) = result else {
            return XCTFail("Expected generationFailed, got \(result)")
        }
        XCTAssertFalse(message.contains("ready_package_overwrite_required"))
        XCTAssertFalse(message.contains("fixture_first_idea_generation_failed"))
        XCTAssertTrue(message.localizedCaseInsensitiveContains("couldn't prepare your first idea"))
    }

    private func booksMoviesCompletedData() -> OnboardingCompletedData {
        OnboardingCompletedData(
            selectedCategoryIDs: ["books", "movies-tv"],
            customSubjects: [],
            startingPoint: .alreadyPosting,
            selectedTasteExampleIDs: ["books-rec-1"],
            tasteExampleTitles: ["3 underrated books"],
            formats: [.voiceoverBroll],
            timeToCreate: .tenToThirty,
            contentLanguage: "English",
            showFace: false,
            useVoice: true,
            contextAnswers: ["books-reading": "Fourth Wing"],
            references: [],
            voiceDeferred: false
        )
    }
}

private final class FailingCreatorProfileRepository: CreatorProfileRepository, @unchecked Sendable {
    var updateAttempts = 0

    func activeProfileSummary(for context: WorkspaceContext) async throws -> CreatorProfileSummary {
        .emptyLiveFallback(displayName: "Creator")
    }

    func updateProfile(_ update: CreatorProfileUpdate, context: WorkspaceContext) async throws -> CreatorProfileSummary {
        updateAttempts += 1
        throw RepositoryError.edgeFunction("profile_save_failed")
    }
}

private actor TrackingDayGenerationRepository: DayGenerationRepository {
    private(set) var generateCallCount = 0
    private(set) var lastDayBrief: String?

    func generateDay(
        creatorID: UUID,
        scheduledDate: String,
        dayBrief: String,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        _ = creatorID
        _ = context
        generateCallCount += 1
        lastDayBrief = dayBrief
        return try await FixtureDayGenerationRepository().generateDay(
            creatorID: creatorID,
            scheduledDate: scheduledDate,
            dayBrief: dayBrief,
            context: context
        )
    }

    func regenerateDay(
        creatorID: UUID,
        weeklyPlanID: UUID,
        scheduledDate: String,
        preserveManualEdits: Bool,
        dayGuidance: String?,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        throw RepositoryError.notConfigured("not_used")
    }

    func resumeAcceptedDayGeneration(
        generationID: UUID,
        creatorID: UUID,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        throw RepositoryError.notConfigured("not_used")
    }
}

private actor TrackingMakeDayAvailableWeeklyRepository: WeeklyPlanRepository {
    private(set) var makeDayAvailableCallCount = 0

    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan {
        .raceWeek
    }

    func currentGeneratedDraft(for context: WorkspaceContext) async throws -> GeneratedWeekDraft? {
        nil
    }

    func ideaBank(for context: WorkspaceContext) async throws -> [WeeklyIdea] {
        []
    }

    func currentWeeklyContent(for context: WorkspaceContext) async throws -> WeeklyRepositoryContent {
        WeeklyRepositoryContent(publishedPlan: .raceWeek, generatedDraft: nil, ideaBank: [])
    }

    func publishWeek(
        _ plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        generatedDraft: GeneratedWeekDraft?,
        context: WorkspaceContext
    ) async throws -> WeeklyPublishResult {
        throw RepositoryError.notConfigured("not_used")
    }

    func selectIdeaForNextOpenDay(
        _ idea: WeeklyIdea,
        in plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        context: WorkspaceContext
    ) async throws -> WeeklySelectionUpdate {
        WeeklySelectionUpdate(weeklyPlan: plan, ideaBank: ideaBank)
    }

    func updateWeeklySetupSections(
        _ sections: [WeeklySetupSection],
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        plan
    }

    func updateWeeklyBrief(
        _ text: String,
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        plan
    }

    func updateDailyCardReviewState(
        dailyCardID: UUID,
        reviewState: String,
        context: WorkspaceContext
    ) async throws {}

    func makeDayAvailable(
        scheduledDate: String,
        dailyCardID: UUID?,
        context: WorkspaceContext
    ) async throws -> DayAvailabilityResult {
        _ = dailyCardID
        _ = context
        makeDayAvailableCallCount += 1
        return DayAvailabilityResult(
            dailyCardID: dailyCardID ?? UUID(),
            scheduledDate: scheduledDate,
            status: "published",
            weeklyPlanID: WeeklyPlan.raceWeek.id,
            weekIsSoftLocked: false
        )
    }

    func unpublishDay(
        scheduledDate: String,
        dailyCardID: UUID?,
        context: WorkspaceContext
    ) async throws -> DayUnpublishResult {
        throw RepositoryError.notConfigured("not_used")
    }

    func updateReadyDayPackage(
        scheduledDate: String,
        dailyCardID: UUID?,
        package: ReadyDayPackageUpdate,
        context: WorkspaceContext
    ) async throws -> DayPackageUpdateResult {
        throw RepositoryError.notConfigured("not_used")
    }
}

private struct FailingDayGenerationRepository: DayGenerationRepository {
    func generateDay(
        creatorID: UUID,
        scheduledDate: String,
        dayBrief: String,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        _ = creatorID
        _ = scheduledDate
        _ = dayBrief
        _ = context
        throw RepositoryError.edgeFunction("fixture_first_idea_generation_failed")
    }

    func regenerateDay(
        creatorID: UUID,
        weeklyPlanID: UUID,
        scheduledDate: String,
        preserveManualEdits: Bool,
        dayGuidance: String?,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        throw RepositoryError.notConfigured("not_used")
    }

    func resumeAcceptedDayGeneration(
        generationID: UUID,
        creatorID: UUID,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        throw RepositoryError.notConfigured("not_used")
    }
}
