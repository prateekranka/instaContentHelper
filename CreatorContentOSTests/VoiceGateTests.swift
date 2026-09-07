import XCTest
@testable import CreatorContentOS

/// Voice gate: generation is blocked until creator voice is configured or explicitly deferred.
@MainActor
final class VoiceGateTests: XCTestCase {

    private static let emptyProfile = CreatorProfileSummary(
        displayName: "Creator",
        positioning: "",
        voiceLine: "",
        noGoTopics: [],
        voiceRules: [],
        contentPillars: [],
        captionStyle: nil,
        recurringFormats: []
    )

    private static let deferredData = OnboardingCompletedData(
        selectedCategoryIDs: ["fitness"],
        categoryOtherText: "",
        references: [],
        voiceDeferred: true
    )

    override func setUp() {
        super.setUp()
        // AppServices.voiceDeferred reads the standard onboarding store; keep it deterministic.
        UserDefaultsOnboardingStore().resetAll()
    }

    override func tearDown() {
        UserDefaultsOnboardingStore().resetAll()
        super.tearDown()
    }

    private func makeServices(profile: CreatorProfileSummary) -> AppServices {
        let services = AppServices.fixtureBacked()
        services.creatorProfileSummary = profile
        return services
    }

    func testVoiceConfiguredWhenPositioningAndRulesSet() {
        // Fixture profile carries positioning + voice rules.
        let services = AppServices.fixtureBacked()
        XCTAssertTrue(services.voiceIsConfigured)
        XCTAssertFalse(services.voiceGateOpen)
        XCTAssertTrue(services.canGenerateContent)
    }

    func testVoiceGateBlocksGenerationWhenVoiceEmptyAndNotDeferred() {
        let services = makeServices(profile: Self.emptyProfile)
        XCTAssertFalse(services.voiceIsConfigured)
        XCTAssertFalse(services.voiceDeferred)
        XCTAssertTrue(services.voiceGateOpen)
        XCTAssertFalse(services.canGenerateContent)
    }

    func testPositioningAloneIsNotConfigured() {
        var profile = Self.emptyProfile
        profile.positioning = "Lifestyle creator after 60"
        let services = makeServices(profile: profile)
        XCTAssertFalse(services.voiceIsConfigured)
        XCTAssertTrue(services.voiceGateOpen)
        XCTAssertFalse(services.canGenerateContent)
    }

    func testVoiceRulesAloneAreNotConfigured() {
        var profile = Self.emptyProfile
        profile.voiceRules = ["Warm", "Direct"]
        let services = makeServices(profile: profile)
        XCTAssertFalse(services.voiceIsConfigured)
        XCTAssertTrue(services.voiceGateOpen)
        XCTAssertFalse(services.canGenerateContent)
    }

    func testLegacyUserDefaultsDeferralDoesNotOpenVoiceGate() {
        UserDefaultsOnboardingStore().markComplete(with: Self.deferredData)
        let services = makeServices(profile: Self.emptyProfile)
        XCTAssertFalse(services.voiceDeferred)
        XCTAssertTrue(services.voiceGateOpen)
        XCTAssertFalse(services.canGenerateContent)
    }

    func testGenerateDayCardRejectsWhenVoiceGateClosed() async throws {
        let services = makeServices(profile: Self.emptyProfile)
        let scheduledDate = "2026-09-10" // future, so only the voice gate can reject

        do {
            _ = try await services.generateDayCard(scheduledDate: scheduledDate, dayBrief: "Test brief")
            XCTFail("Expected creator_voice_required")
        } catch {
            XCTAssertEqual(services.dayBriefGenerationErrors[scheduledDate], "creator_voice_required")
        }
    }

    func testPlanGenerateDayCardRejectsEstablishedEmptyVoice() async throws {
        var profile = Self.emptyProfile
        profile.onboardingState = .established
        let services = makeServices(profile: profile)
        let scheduledDate = "2026-09-10"

        XCTAssertFalse(services.voiceIsConfigured)
        XCTAssertFalse(services.voiceDeferred)
        XCTAssertFalse(services.canGenerateContent)

        do {
            _ = try await services.generateDayCard(scheduledDate: scheduledDate, dayBrief: "Plan brief")
            XCTFail("Expected creator_voice_required")
        } catch {
            XCTAssertEqual(services.dayBriefGenerationErrors[scheduledDate], "creator_voice_required")
        }
    }

    func testGenerateDayCardAllowedWhenVoiceConfigured() async throws {
        let services = AppServices.fixtureBacked()
        do {
            _ = try await services.generateDayCard(scheduledDate: "2026-09-10", dayBrief: "Test brief")
        } catch {
            // With voice configured the gate is open; any error here is unrelated to the voice gate.
            XCTAssertFalse(services.dayBriefGenerationErrors["2026-09-10"] == "creator_voice_required")
        }
    }

    func testOnboardingEstablishedProfileUpdateOpensVoiceGate() {
        let update = OnboardingProfileMapper.profileUpdate(
            from: OnboardingRecord(
                completedData: OnboardingCompletedData(
                    selectedCategoryIDs: ["books"],
                    customSubjects: [],
                    startingPoint: .justStarting,
                    selectedTasteExampleIDs: ["books-rec-1"],
                    tasteExampleTitles: ["3 underrated books"],
                    formats: [.talkingToCamera],
                    timeToCreate: .tenToThirty,
                    contentLanguage: "English",
                    showFace: true,
                    useVoice: true,
                    contextAnswers: [:],
                    references: [],
                    voiceDeferred: false
                )
            ),
            onboardingState: .established,
            onboardingCompletedAt: "2026-09-05T12:00:00Z"
        )
        let services = makeServices(
            profile: CreatorProfileSummary(
                displayName: "Creator",
                positioning: update.positioning ?? "",
                voiceLine: "",
                noGoTopics: [],
                voiceRules: update.voiceRules ?? [],
                contentPillars: update.contentPillars ?? []
            )
        )
        XCTAssertTrue(services.voiceIsConfigured)
        XCTAssertTrue(services.canGenerateContent)
    }

    func testLiveGenerateDayCardBlocksWithoutAIConsent() async {
        let generation = CountingAIConsentDayGenerationRepository()
        let services = makeLiveServices(
            consent: InMemoryAIConsentStore(),
            dailyGeneration: generation
        )
        let scheduledDate = "2026-09-10"

        do {
            _ = try await services.generateDayCard(scheduledDate: scheduledDate, dayBrief: "Test brief")
            XCTFail("Expected ai_consent_required")
        } catch {
            XCTAssertEqual(error.localizedDescription, AIConsentCopy.errorCode)
            XCTAssertEqual(services.dayBriefGenerationErrors[scheduledDate], AIConsentCopy.blockedMessage)
            XCTAssertTrue(services.isAIConsentSheetPresented)
            XCTAssertEqual(generation.callCount, 0)
        }
    }

    func testLiveGenerateDayCardStaysBlockedAfterDecline() async {
        let generation = CountingAIConsentDayGenerationRepository()
        let services = makeLiveServices(
            consent: InMemoryAIConsentStore(),
            dailyGeneration: generation
        )
        let scheduledDate = "2026-09-10"
        _ = try? await services.generateDayCard(scheduledDate: scheduledDate, dayBrief: "Test brief")
        services.declineAIConsent()

        do {
            _ = try await services.generateDayCard(scheduledDate: scheduledDate, dayBrief: "Retry brief")
            XCTFail("Expected ai_consent_required after decline")
        } catch {
            XCTAssertEqual(generation.callCount, 0)
            XCTAssertEqual(services.aiConsentStore.load()?.decision, .declined)
            XCTAssertEqual(services.aiConsentStore.load()?.consentVersion, AIConsentPolicy.currentVersion)
            XCTAssertTrue(services.isAIConsentSheetPresented)
        }
    }

    func testLiveGenerateDayCardProceedsAfterAccept() async throws {
        let generation = CountingAIConsentDayGenerationRepository()
        let services = makeLiveServices(
            consent: InMemoryAIConsentStore(),
            dailyGeneration: generation
        )
        services.acceptAIConsent()

        _ = try await services.generateDayCard(scheduledDate: "2026-09-10", dayBrief: "Test brief")

        XCTAssertEqual(generation.callCount, 1)
        XCTAssertFalse(services.isAIConsentSheetPresented)
        XCTAssertEqual(services.aiConsentStore.load()?.decision, .accepted)
        XCTAssertEqual(services.aiConsentStore.load()?.consentVersion, AIConsentPolicy.currentVersion)
        XCTAssertEqual(
            services.aiConsentStore.load()?.destinationsAcknowledged,
            AIConsentPolicy.destinations
        )
    }

    func testYouAccountRetryAcceptUnblocksGenerate() async throws {
        let generation = CountingAIConsentDayGenerationRepository()
        let store = InMemoryAIConsentStore(
            record: AIConsentRecord(
                consentVersion: AIConsentPolicy.currentVersion,
                decision: .declined,
                decidedAt: "2026-09-07T12:00:00Z",
                destinationsAcknowledged: AIConsentPolicy.destinations
            )
        )
        let services = makeLiveServices(consent: store, dailyGeneration: generation)
        XCTAssertTrue(services.canRetryAIConsent)

        services.acceptAIConsent()
        _ = try await services.generateDayCard(scheduledDate: "2026-09-10", dayBrief: "Retry brief")

        XCTAssertEqual(generation.callCount, 1)
        XCTAssertFalse(services.canRetryAIConsent)
    }

    func testLivePlanIdeasSkipOutboundWithoutConsent() async {
        let ideas = RecordingAIConsentPlanDayIdeaRepository()
        let services = makeLiveServices(
            consent: InMemoryAIConsentStore(),
            planDayIdeas: ideas
        )
        let setup = PlanDaySetupSummary(
            contentPillars: ["gym"],
            voiceIsConfigured: true,
            confirmedReferenceCount: 0,
            totalReferenceCount: 0
        )
        let date = "2026-09-14"

        await services.refreshPlanDayIdeas(scheduledDate: date, setup: setup)

        let callCount = await ideas.callCount
        XCTAssertEqual(callCount, 0)
        XCTAssertTrue(services.isAIConsentSheetPresented)
        XCTAssertEqual(
            services.planDayIdeas(for: date, setup: setup),
            PlanDayIdeaBuilder.buildIdeas(scheduledDate: date, setup: setup)
        )
    }

    func testLivePlanIdeasStayLocalAfterDeclineWithoutReprompt() async {
        let ideas = RecordingAIConsentPlanDayIdeaRepository()
        let services = makeLiveServices(
            consent: InMemoryAIConsentStore(
                record: AIConsentRecord(
                    consentVersion: AIConsentPolicy.currentVersion,
                    decision: .declined,
                    decidedAt: "2026-09-07T12:00:00Z",
                    destinationsAcknowledged: AIConsentPolicy.destinations
                )
            ),
            planDayIdeas: ideas
        )
        let setup = PlanDaySetupSummary(
            contentPillars: ["gym"],
            voiceIsConfigured: true,
            confirmedReferenceCount: 0,
            totalReferenceCount: 0
        )

        await services.refreshPlanDayIdeas(scheduledDate: "2026-09-14", setup: setup)

        let callCount = await ideas.callCount
        XCTAssertEqual(callCount, 0)
        XCTAssertFalse(services.isAIConsentSheetPresented)
    }

    func testLiveStoryboardPrepSkipsOutboundWithoutConsent() async {
        let thumbnails = RecordingAIConsentStoryboardThumbnailRepository()
        let services = makeLiveServices(
            consent: InMemoryAIConsentStore(),
            storyboardThumbnails: thumbnails
        )
        var card = GeneratedDailyCardDraft.storyboardBreakdownFixture
        card.scheduledDate = "2026-09-10"
        services.dayBriefGeneratedCards[card.scheduledDate] = card

        await services.prepareStoryboardThumbnailsForVisibleCard(dailyCardID: card.id)

        let callCount = await thumbnails.callCount
        XCTAssertEqual(callCount, 0)
        XCTAssertTrue(services.isAIConsentSheetPresented)
        XCTAssertEqual(services.storyboardThumbnailErrors[card.id], AIConsentCopy.blockedMessage)
    }

    func testLiveStoryboardPrepProceedsAfterAccept() async {
        let thumbnails = RecordingAIConsentStoryboardThumbnailRepository()
        let services = makeLiveServices(
            consent: InMemoryAIConsentStore(),
            storyboardThumbnails: thumbnails
        )
        var card = GeneratedDailyCardDraft.storyboardBreakdownFixture
        card.scheduledDate = "2026-09-10"
        services.dayBriefGeneratedCards[card.scheduledDate] = card
        services.acceptAIConsent()

        await services.prepareStoryboardThumbnailsForVisibleCard(dailyCardID: card.id)

        let callCount = await thumbnails.callCount
        XCTAssertEqual(callCount, 1)
    }

    private func makeLiveServices(
        consent: any AIConsentStoring,
        dailyGeneration: any DayGenerationRepository = CountingAIConsentDayGenerationRepository(),
        planDayIdeas: any PlanDayIdeaRepository = FixturePlanDayIdeaRepository(),
        storyboardThumbnails: any StoryboardThumbnailRepository = AppFixtureStoryboardThumbnailUnavailableRepository()
    ) -> AppServices {
        AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                dailyGeneration: dailyGeneration,
                planDayIdeas: planDayIdeas,
                storyboardThumbnails: storyboardThumbnails,
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            isLiveSupabaseRuntime: true,
            aiConsentStore: consent
        )
    }
}

private final class CountingAIConsentDayGenerationRepository: DayGenerationRepository, @unchecked Sendable {
    private(set) var callCount = 0

    func generateDay(
        creatorID: UUID,
        scheduledDate: String,
        dayBrief: String,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        callCount += 1
        var card = GeneratedDailyCardDraft.storyboardBreakdownFixture
        card.scheduledDate = scheduledDate
        card.status = "draft"
        return DailyGenerationResult(
            generationID: UUID(),
            weeklyPlanID: WeeklyPlan.raceWeek.id,
            status: "draft",
            targetScheduledDate: scheduledDate,
            dailyCard: card,
            warnings: [],
            assumptions: [],
            sourceSummary: "Consent test stub",
            generatedAt: "2026-09-07T00:00:00Z"
        )
    }
}

private actor RecordingAIConsentPlanDayIdeaRepository: PlanDayIdeaRepository {
    private(set) var callCount = 0

    func generatePlanDayIdeas(
        creatorID: UUID,
        scheduledDate: String,
        setup: PlanDaySetupSummary,
        context: WorkspaceContext
    ) async throws -> [PlanDayIdeaCandidate] {
        callCount += 1
        return PlanDayIdeaBuilder.buildIdeas(scheduledDate: scheduledDate, setup: setup)
    }
}

private actor RecordingAIConsentStoryboardThumbnailRepository: StoryboardThumbnailRepository {
    private(set) var callCount = 0

    func generateStoryboardThumbnails(
        creatorID: UUID,
        dailyCardID: UUID,
        rowIndexes: [Int]?,
        force: Bool,
        revisionInstructions: String?,
        context: WorkspaceContext
    ) async throws -> [StoryboardThumbnailAsset] {
        callCount += 1
        return [
            StoryboardThumbnailAsset(
                rowIndex: 0,
                promptHash: "consent-test",
                storagePath: "path/row-0.jpg",
                publicURL: "https://example.com/storyboard/row-0.jpg",
                model: "gemini-3.1-flash-lite-image",
                promptVersion: "storyboard_thumbnail_v1",
                status: "generated",
                generatedAt: "2026-09-07T00:00:00Z"
            )
        ]
    }
}
