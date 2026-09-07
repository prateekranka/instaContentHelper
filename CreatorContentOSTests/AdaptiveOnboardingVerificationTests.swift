import XCTest
@testable import CreatorContentOS

/// Workstream 3 verification: gating matrix, account isolation, first-idea handoff contracts.
@MainActor
final class AdaptiveOnboardingVerificationTests: XCTestCase {

    // MARK: - Gating matrix

    func testGatingMatrixNewPartialEstablished() {
        let empty = CreatorProfileSummary.emptyLiveFallback(displayName: "Alex")

        XCTAssertEqual(
            CreatorOnboardingPresentationMapper.presentation(
                from: empty,
                loadFailed: false,
                previousPresentation: nil
            ),
            .new
        )

        var partial = empty
        partial.onboardingState = .partial
        XCTAssertEqual(
            CreatorOnboardingPresentationMapper.presentation(
                from: partial,
                loadFailed: false,
                previousPresentation: nil
            ),
            .partial
        )

        var established = empty
        established.onboardingState = .established
        established.positioning = "Books creator."
        established.voiceRules = ["Honest"]
        XCTAssertEqual(
            CreatorOnboardingPresentationMapper.presentation(
                from: established,
                loadFailed: false,
                previousPresentation: nil
            ),
            .established
        )
    }

    func testGatingMatrixLoadFailedPreservesEstablishedSnapshot() {
        let established = CreatorProfileSummary(
            displayName: "Alex",
            positioning: "Books creator",
            voiceLine: "Warm",
            noGoTopics: [],
            voiceRules: ["Warm"],
            onboardingState: .established
        )

        let presentation = CreatorOnboardingPresentationMapper.presentation(
            from: established,
            loadFailed: true,
            previousPresentation: .established
        )

        guard case .loadFailed(let previousEstablished) = presentation else {
            return XCTFail("Expected loadFailed presentation")
        }
        XCTAssertTrue(previousEstablished)
        XCTAssertFalse(presentation.shouldForceOnboardingFlow)
    }

    func testMCOResetOnboardingClearsLegacyKeysOnly() {
        let defaults = UserDefaults(suiteName: "AdaptiveOnboardingVerificationTests.reset")!
        defaults.removePersistentDomain(forName: "AdaptiveOnboardingVerificationTests.reset")
        defaults.set("1", forKey: "ch-onboarding-done")
        defaults.set("{}", forKey: "ch-onboarding-progress")

        UserDefaultsOnboardingStore.resetLegacyGlobalKeys(defaults: defaults)

        XCTAssertNil(defaults.string(forKey: "ch-onboarding-done"))
        XCTAssertNil(defaults.string(forKey: "ch-onboarding-progress"))
        XCTAssertNil(defaults.string(forKey: "ch-onboarding-data"))

        let context = WorkspaceContext.creatorFixture
        let scoped = WorkspaceScopedOnboardingStore(
            workspaceID: context.workspaceID,
            creatorID: context.creatorID,
            defaults: defaults
        )
        scoped.saveProgress(.empty)
        XCTAssertNotNil(scoped.loadProgress())
        XCTAssertFalse(scoped.isComplete())
    }

    // MARK: - Account isolation

    func testWorkspaceScopedStoresDoNotShareProgress() {
        let defaults = UserDefaults(suiteName: "AdaptiveOnboardingVerificationTests.isolation")!
        defaults.removePersistentDomain(forName: "AdaptiveOnboardingVerificationTests.isolation")

        let workspaceA = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let workspaceB = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let creatorA = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let creatorB = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!

        let storeA = WorkspaceScopedOnboardingStore(
            workspaceID: workspaceA,
            creatorID: creatorA,
            defaults: defaults
        )
        let storeB = WorkspaceScopedOnboardingStore(
            workspaceID: workspaceB,
            creatorID: creatorB,
            defaults: defaults
        )

        storeA.saveProgress(
            OnboardingProgress(
                step: .interests,
                interestIDs: ["books"],
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

        XCTAssertNotNil(storeA.loadProgress())
        XCTAssertNil(storeB.loadProgress())
    }

    // MARK: - Record mapping and brief synthesis

    func testCustomSubjectSurvivesRecordAndProfileMapping() {
        let data = Self.booksMoviesCompletedData(customSubjects: ["Pottery"])
        let record = OnboardingRecord(completedData: data)

        XCTAssertEqual(record.customSubjects, ["Pottery"])
        XCTAssertTrue(record.interestLabels.contains("Pottery"))

        let update = OnboardingProfileMapper.profileUpdate(
            from: record,
            onboardingState: .established,
            onboardingCompletedAt: "2026-09-05T12:00:00Z"
        )
        XCTAssertEqual(update.customSubjects, ["Pottery"])
        XCTAssertTrue(update.contentPillars?.contains("Pottery") ?? false)
    }

    func testBooksMoviesBriefDiffersFromFitnessBrief() {
        let booksBrief = OnboardingFirstIdeaBriefBuilder.buildDayBrief(
            from: OnboardingRecord(completedData: Self.booksMoviesCompletedData())
        )
        let fitnessBrief = OnboardingFirstIdeaBriefBuilder.buildDayBrief(
            from: OnboardingRecord(completedData: Self.fitnessCompletedData())
        )

        XCTAssertTrue(booksBrief.localizedCaseInsensitiveContains("Books"))
        XCTAssertTrue(booksBrief.localizedCaseInsensitiveContains("Movies"))
        XCTAssertTrue(fitnessBrief.localizedCaseInsensitiveContains("Fitness"))
        XCTAssertNotEqual(booksBrief, fitnessBrief)
        XCTAssertFalse(booksBrief.localizedCaseInsensitiveContains("HYROX"))
    }

    func testProfileMapperMapsContextAnswersIntoRecentContext() {
        let record = OnboardingRecord(
            completedData: Self.booksMoviesCompletedData(
                contextAnswers: ["books-reading": "Fourth Wing"]
            )
        )
        let update = OnboardingProfileMapper.profileUpdate(
            from: record,
            onboardingState: .established
        )
        XCTAssertEqual(
            update.recentContext,
            [[
                "question_id": "books-reading",
                "interest_id": "books",
                "answer": "Fourth Wing"
            ]]
        )
    }

    func testFaceVoiceAndTimeReachSynthesizedDayBrief() {
        let brief = OnboardingFirstIdeaBriefBuilder.buildDayBrief(
            from: OnboardingRecord(completedData: Self.booksMoviesCompletedData())
        )

        XCTAssertTrue(brief.contains("No face on camera"))
        XCTAssertTrue(brief.contains("Voiceover allowed"))
        XCTAssertTrue(brief.contains("about 20 minutes"))
    }

    func testEmptyLiveFallbackNeverLeaksHyroxFixture() {
        let summary = CreatorProfileSummary.emptyLiveFallback(displayName: "New Creator")
        XCTAssertTrue(summary.positioning.isEmpty)
        XCTAssertTrue(summary.contentPillars.isEmpty)
        XCTAssertNotEqual(summary.positioning, CreatorProfileSummary.creatorFixture.positioning)
        XCTAssertFalse(summary.contentPillars.contains("gym"))
    }


    // MARK: - Instagram not required

    func testReviewValidWithoutInstagramReferences() {
        let data = Self.booksMoviesCompletedData(references: [])
        XCTAssertTrue(
            OnboardingValidation.interestsAreValid(
                interestIDs: data.selectedCategoryIDs,
                customSubjects: data.customSubjects
            )
        )
        XCTAssertTrue(
            OnboardingValidation.tasteIsValid(
                selectedExampleIDs: data.selectedTasteExampleIDs,
                refreshCount: 0
            )
        )
        XCTAssertTrue(
            OnboardingValidation.productionIsValid(
                formats: data.formats,
                timeToCreate: data.timeToCreate,
                contentLanguage: data.contentLanguage,
                showFace: data.showFace,
                useVoice: data.useVoice
            )
        )
        XCTAssertTrue(data.references.isEmpty)
    }

    // MARK: - Persist before complete / first idea handoff

    func testConfirmOnboardingPersistFailureDoesNotMarkEstablished() async {
        let repository = VerificationFailingProfileRepository()
        let services = Self.makeServices(creatorProfile: repository)

        let result = await services.confirmOnboardingAndPrepareFirstIdea(
            completedData: Self.booksMoviesCompletedData(),
            scheduledDate: "2026-09-05"
        )

        XCTAssertEqual(result, .persistFailed)
        XCTAssertGreaterThanOrEqual(repository.updateAttempts, 2)
        XCTAssertTrue(repository.rolledBackToPartial)
    }

    func testConfirmOnboardingSuccessUsesMakeDayAvailableAndLandsToday() async throws {
        let today = "2026-09-05"
        let trackingWeekly = VerificationTrackingWeeklyPlanRepository()
        let services = Self.makeServices(
            creatorProfile: FixtureCreatorProfileRepository(),
            weeklyPlans: trackingWeekly,
            dailyGeneration: VerificationDayGenerationStub(),
            todayDate: today
        )
        services.todayCard = .emptyTodayPlaceholder

        let result = await services.confirmOnboardingAndPrepareFirstIdea(
            completedData: Self.booksMoviesCompletedData(),
            scheduledDate: today
        )

        guard case .completed(let navigatedToday) = result else {
            return XCTFail("Expected completed handoff, got \(result)")
        }
        XCTAssertTrue(navigatedToday)
        let makeDayAvailableCalls = await trackingWeekly.makeDayAvailableCallCount
        let lastMakeAvailableDate = await trackingWeekly.lastMakeAvailableDate
        XCTAssertEqual(makeDayAvailableCalls, 1)
        XCTAssertEqual(lastMakeAvailableDate, today)

        let state = AppState(runtime: .fixtures(), authenticationPhase: .live)
        state.handoffFirstDayFromOnboarding(
            OnboardingFirstDayHandoff(
                scheduledDate: today,
                dayBrief: OnboardingFirstIdeaBriefBuilder.buildDayBrief(
                    from: OnboardingRecord(completedData: Self.booksMoviesCompletedData())
                ),
                completedData: Self.booksMoviesCompletedData()
            )
        )
        XCTAssertEqual(state.pendingCreatorTab, .today)
        XCTAssertNil(state.planSelectedDate)
    }

    func testFirstIdeaIdempotencySkipsReadyPackage() async {
        let today = "2026-09-05"
        let services = Self.makeServices(todayDate: today)
        services.dayBriefGeneratedCards[today] = Self.readyDraft(
            scheduledDate: today,
            status: "published",
            title: "Existing ready card"
        )

        let result = await services.confirmOnboardingAndPrepareFirstIdea(
            completedData: Self.booksMoviesCompletedData(),
            scheduledDate: today
        )

        XCTAssertEqual(result, .skippedExistingReady)
    }

    func testHasUserEditedFirstIdeaPackageTreatsGeneratedDraftAsEditedGap() {
        let today = "2026-09-05"
        let services = Self.makeServices(todayDate: today)
        services.dayBriefGeneratedCards[today] = Self.readyDraft(
            scheduledDate: today,
            status: "draft",
            title: "Generated title"
        )

        let plan = OnboardingFirstIdeaHandoffPlanner.plan(
            scheduledDate: today,
            record: OnboardingRecord(completedData: Self.booksMoviesCompletedData()),
            existingPackageStatus: "draft",
            hasUserEditedPackage: true
        )
        XCTAssertFalse(plan.shouldGenerate)
        XCTAssertEqual(plan.skipReason, .skippedExistingReady)
        _ = services
    }

    // MARK: - Helpers

    private static func booksMoviesCompletedData(
        customSubjects: [String] = [],
        contextAnswers: [String: String] = [:],
        references: [OnboardingReference] = []
    ) -> OnboardingCompletedData {
        OnboardingCompletedData(
            selectedCategoryIDs: ["books", "movies-tv"],
            customSubjects: customSubjects,
            startingPoint: .alreadyPosting,
            selectedTasteExampleIDs: ["books-rec-1"],
            tasteExampleTitles: ["3 underrated books"],
            formats: [.voiceoverBroll],
            timeToCreate: .tenToThirty,
            contentLanguage: "English",
            showFace: false,
            useVoice: true,
            contextAnswers: contextAnswers,
            creatorNote: nil,
            references: references,
            voiceDeferred: false
        )
    }

    private static func fitnessCompletedData() -> OnboardingCompletedData {
        OnboardingCompletedData(
            selectedCategoryIDs: ["fitness-wellness"],
            customSubjects: [],
            startingPoint: .justStarting,
            selectedTasteExampleIDs: ["fitness-rec-1"],
            tasteExampleTitles: ["Morning mobility routine"],
            formats: [.talkingToCamera],
            timeToCreate: .fiveToTen,
            contentLanguage: "English",
            showFace: true,
            useVoice: false,
            contextAnswers: ["fitness-goal": "HYROX prep"],
            creatorNote: nil,
            references: [],
            voiceDeferred: false
        )
    }

    private static func readyDraft(
        scheduledDate: String,
        status: String,
        title: String
    ) -> GeneratedDailyCardDraft {
        GeneratedDailyCardDraft(
            id: UUID(),
            scheduledDate: scheduledDate,
            status: status,
            title: title,
            whyToday: "Why.",
            growthJob: "Growth.",
            contentPillar: "books",
            shootability: "easy",
            estimatedShootMinutes: 12,
            energyRequired: "low",
            languageMode: "English",
            sceneList: [],
            script: "Generated script body.",
            noVoiceoverVersion: "",
            onScreenText: [],
            caption: "Generated caption.",
            cta: "Save.",
            hashtags: [],
            coverText: "Draft",
            postInstructions: "",
            brandEventNotes: "",
            backupStory: "",
            backupCaptionOnly: "",
            audioOptionNotes: "",
            creatorFitScore: 90,
            riskNotes: [],
            assumptions: [],
            sourceNote: "Fixture."
        )
    }

    private static func makeServices(
        creatorProfile: any CreatorProfileRepository = FixtureCreatorProfileRepository(),
        weeklyPlans: (any WeeklyPlanRepository)? = nil,
        dailyGeneration: (any DayGenerationRepository)? = nil,
        todayDate: String = "2026-09-05"
    ) -> AppServices {
        AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: weeklyPlans ?? FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                dailyGeneration: dailyGeneration ?? VerificationDayGenerationStub(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: creatorProfile,
                archive: FixtureArchiveRepository()
            ),
            todayDate: { todayDate }
        )
    }
}

// MARK: - Test doubles

private final class VerificationFailingProfileRepository: CreatorProfileRepository, @unchecked Sendable {
    var updateAttempts = 0
    var rolledBackToPartial = false

    func activeProfileSummary(for context: WorkspaceContext) async throws -> CreatorProfileSummary {
        .emptyLiveFallback(displayName: "Creator")
    }

    func updateProfile(_ update: CreatorProfileUpdate, context: WorkspaceContext) async throws -> CreatorProfileSummary {
        updateAttempts += 1
        if update.onboardingState == .partial {
            rolledBackToPartial = true
        }
        throw RepositoryError.edgeFunction("profile_save_failed")
    }
}

private struct VerificationDayGenerationStub: DayGenerationRepository {
    func generateDay(
        creatorID: UUID,
        scheduledDate: String,
        dayBrief: String,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        DailyGenerationResult(
            generationID: UUID(),
            weeklyPlanID: UUID(),
            status: "draft",
            targetScheduledDate: scheduledDate,
            dailyCard: GeneratedDailyCardDraft(
                id: UUID(),
                scheduledDate: scheduledDate,
                status: "draft",
                title: "First idea: \(dayBrief.prefix(40))",
                whyToday: "Onboarding first idea.",
                growthJob: "Consistency.",
                contentPillar: "books",
                shootability: "easy",
                estimatedShootMinutes: 20,
                energyRequired: "low",
                languageMode: "English",
                sceneList: [
                    ShotScene(number: 1, title: "Opening", duration: "3 sec", symbol: "sparkles")
                ],
                script: "Verification script.",
                noVoiceoverVersion: "No VO.",
                onScreenText: ["Test"],
                caption: "Verification caption.",
                cta: "Save this.",
                hashtags: ["test"],
                coverText: "Test",
                postInstructions: "Test instructions.",
                brandEventNotes: "",
                backupStory: "Backup.",
                backupCaptionOnly: "Caption backup.",
                audioOptionNotes: "",
                creatorFitScore: 90,
                riskNotes: [],
                assumptions: [],
                sourceNote: "Verification stub."
            ),
            warnings: [],
            assumptions: [],
            sourceSummary: "Verification stub",
            generatedAt: "2026-09-05T00:00:00Z"
        )
    }
}

private actor VerificationTrackingWeeklyPlanRepository: WeeklyPlanRepository {
    private(set) var makeDayAvailableCallCount = 0
    private(set) var lastMakeAvailableDate: String?

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
        throw RepositoryError.notConfigured("publish_not_used")
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
        makeDayAvailableCallCount += 1
        lastMakeAvailableDate = scheduledDate
        return DayAvailabilityResult(
            dailyCardID: dailyCardID ?? UUID(),
            scheduledDate: scheduledDate,
            status: "published",
            weeklyPlanID: UUID(),
            weekIsSoftLocked: false
        )
    }

    func unpublishDay(
        scheduledDate: String,
        dailyCardID: UUID?,
        context: WorkspaceContext
    ) async throws -> DayUnpublishResult {
        throw RepositoryError.notConfigured("unpublish_not_used")
    }

    func updateReadyDayPackage(
        scheduledDate: String,
        dailyCardID: UUID?,
        package: ReadyDayPackageUpdate,
        context: WorkspaceContext
    ) async throws -> DayPackageUpdateResult {
        throw RepositoryError.notConfigured("update_ready_not_used")
    }
}
