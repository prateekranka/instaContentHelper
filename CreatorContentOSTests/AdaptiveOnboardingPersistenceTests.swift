import XCTest
@testable import CreatorContentOS

final class AdaptiveOnboardingPersistenceTests: XCTestCase {
    func testPresentationMapsNewPartialEstablished() {
        let newSummary = CreatorProfileSummary.emptyLiveFallback(displayName: "Alex")
        XCTAssertEqual(
            CreatorOnboardingPresentationMapper.presentation(
                from: newSummary,
                loadFailed: false,
                previousPresentation: nil
            ),
            .new
        )

        var partialSummary = newSummary
        partialSummary.onboardingState = .partial
        XCTAssertEqual(
            CreatorOnboardingPresentationMapper.presentation(
                from: partialSummary,
                loadFailed: false,
                previousPresentation: nil
            ),
            .partial
        )

        var establishedSummary = newSummary
        establishedSummary.onboardingState = .established
        establishedSummary.positioning = "Books and movies creator."
        establishedSummary.voiceRules = ["Honest", "Warm"]
        XCTAssertEqual(
            CreatorOnboardingPresentationMapper.presentation(
                from: establishedSummary,
                loadFailed: false,
                previousPresentation: nil
            ),
            .established
        )
    }

    func testEmptyLiveFallbackNeverUsesCreatorFixture() {
        let summary = CreatorProfileSummary.emptyLiveFallback(displayName: "Alex")
        XCTAssertNotEqual(summary.positioning, CreatorProfileSummary.creatorFixture.positioning)
        XCTAssertTrue(summary.contentPillars.isEmpty)
        XCTAssertEqual(summary.onboardingState, .new)
    }

    func testWorkspaceScopedStoreDoesNotUseGlobalDoneFlag() {
        let defaults = UserDefaults(suiteName: "AdaptiveOnboardingPersistenceTests")!
        defaults.removePersistentDomain(forName: "AdaptiveOnboardingPersistenceTests")
        defaults.set("1", forKey: "ch-onboarding-done")

        let context = WorkspaceContext.creatorFixture
        let store = WorkspaceScopedOnboardingStore(
            workspaceID: context.workspaceID,
            creatorID: context.creatorID,
            defaults: defaults
        )

        XCTAssertFalse(store.isComplete())
    }

    func testOnboardingPresentationPolicyUsesProfileNotGlobalDone() {
        XCTAssertTrue(
            OnboardingPresentationPolicy.shouldPresent(
                presentation: .new,
                sessionDismissed: false
            )
        )
        XCTAssertFalse(
            OnboardingPresentationPolicy.shouldPresent(
                presentation: .established,
                sessionDismissed: false
            )
        )
    }

    func testProfileMapperOmitsVoiceWhenDeferred() {
        let record = OnboardingRecord(
            completedData: OnboardingCompletedData(
                selectedCategoryIDs: ["books"],
                categoryOtherText: "",
                references: [],
                voiceDeferred: true
            )
        )
        let update = OnboardingProfileMapper.profileUpdate(
            from: record,
            onboardingState: .established,
            onboardingCompletedAt: "2026-09-05T12:00:00Z"
        )

        XCTAssertEqual(update.onboardingState, .established)
        XCTAssertEqual(update.positioning, "")
        XCTAssertEqual(update.voiceRules, [])
        XCTAssertEqual(update.contentPillars, ["Books"])
    }

    func testProfileMapperSetsVoiceWhenNotDeferred() {
        let record = OnboardingRecord(
            completedData: OnboardingCompletedData(
                selectedCategoryIDs: ["books"],
                categoryOtherText: "",
                references: [],
                voiceDeferred: false
            )
        )
        let update = OnboardingProfileMapper.profileUpdate(
            from: record,
            onboardingState: .established,
            onboardingCompletedAt: "2026-09-05T12:00:00Z"
        )

        XCTAssertFalse(update.positioning?.isEmpty ?? true)
        XCTAssertFalse(update.voiceRules?.isEmpty ?? true)
    }

    func testProfileMapperMapsContextAnswersIntoRecentContext() {
        var completed = OnboardingCompletedData(
            selectedCategoryIDs: ["movies-tv", "books"],
            categoryOtherText: "",
            references: [],
            voiceDeferred: false
        )
        completed.contextAnswers = [
            "movies-watching": "Dune Part Two",
            "books-reading": "Fourth Wing",
            "custom-topic": "   "
        ]

        let record = OnboardingRecord(completedData: completed)
        let update = OnboardingProfileMapper.profileUpdate(
            from: record,
            onboardingState: .established
        )
        let recentContext = update.recentContext ?? []

        XCTAssertEqual(recentContext.count, 2)
        let moviesEntry = recentContext.first { $0["question_id"] == "movies-watching" }
        XCTAssertEqual(moviesEntry?["answer"], "Dune Part Two")
        XCTAssertEqual(moviesEntry?["interest_id"], "movies-tv")
        let booksEntry = recentContext.first { $0["question_id"] == "books-reading" }
        XCTAssertEqual(booksEntry?["answer"], "Fourth Wing")
        XCTAssertEqual(booksEntry?["interest_id"], "books")
    }

    func testFixtureProfileRepositoryRoundTripsOnboardingFields() async throws {
        let repository = FixtureCreatorProfileRepository()
        let context = WorkspaceContext.creatorFixture
        var completed = OnboardingCompletedData(
            selectedCategoryIDs: ["books", "movies-tv"],
            customSubjects: ["Indie comics"],
            startingPoint: .alreadyPosting,
            selectedTasteExampleIDs: ["books-rec-1"],
            tasteExampleTitles: ["3 underrated books"],
            formats: [.voiceoverBroll, .talkingToCamera],
            timeToCreate: .tenToThirty,
            contentLanguage: "English",
            showFace: false,
            useVoice: true,
            contextAnswers: ["books-reading": "Fourth Wing"],
            references: [],
            voiceDeferred: false
        )
        let update = OnboardingProfileMapper.profileUpdate(
            from: OnboardingRecord(completedData: completed),
            onboardingState: .established,
            onboardingCompletedAt: "2026-09-05T12:00:00Z"
        )

        let saved = try await repository.updateProfile(update, context: context)
        let reloaded = try await repository.activeProfileSummary(for: context)

        XCTAssertEqual(saved.productionFormats, ["voiceover_broll", "talking_to_camera"])
        XCTAssertEqual(reloaded.customSubjects, ["Indie comics"])
        XCTAssertEqual(reloaded.recentContext.first?["answer"], "Fourth Wing")
        XCTAssertFalse(YouProductionSelection.from(profile: reloaded).summarySubtitle.contains("Not set"))
        XCTAssertFalse(YouContextSelection.from(profile: reloaded).summarySubtitle.contains("Not set"))
    }
}
