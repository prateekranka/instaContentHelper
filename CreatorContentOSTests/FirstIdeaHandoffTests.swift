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
