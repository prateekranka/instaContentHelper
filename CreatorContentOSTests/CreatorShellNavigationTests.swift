import XCTest
@testable import CreatorContentOS

@MainActor
final class CreatorShellNavigationTests: XCTestCase {
    func testCreatorTabsAreOrderedTodayArchiveProfile() {
        XCTAssertEqual(
            CreatorTab.allCases.map(\.rawValue),
            ["Today", "Archive", "Profile"]
        )
    }

    func testProfileDestinationsArePlanOnly() {
        XCTAssertEqual(ProfileDestination.allCases.map(\.rawValue), ["Plan"])
    }

    func testCreatorCanGenerateWithoutOwnerOrEditorRole() {
        XCTAssertTrue(AppServices.fixtureBacked(memberRole: "creator").canGenerateContent)
        XCTAssertTrue(AppServices.fixtureBacked(memberRole: "owner").canGenerateContent)
        XCTAssertTrue(AppServices.fixtureBacked(memberRole: "editor").canGenerateContent)
        XCTAssertFalse(AppServices.fixtureBacked(memberRole: "scout").canGenerateContent)
    }

    func testRequestCreatorTabSetsPendingTabForPlanAvailableNavigation() {
        let state = AppState(runtime: .fixtures(), authenticationPhase: .live)
        XCTAssertNil(state.pendingCreatorTab)
        state.requestCreatorTab(.today)
        XCTAssertEqual(state.pendingCreatorTab, .today)
    }

    func testPreparePlanSelectedDateForEditAndOverflowEntries() {
        let state = AppState(runtime: .fixtures(), authenticationPhase: .live)
        state.preparePlan(selecting: "2026-07-21")
        XCTAssertEqual(state.planSelectedDate, "2026-07-21")
        XCTAssertEqual(
            CreatorRoute.plan(selectedDate: state.planSelectedDate),
            CreatorRoute.plan(selectedDate: "2026-07-21")
        )
    }

    func testGenerateDayCardAllowsCreatorRole() async throws {
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                dailyGeneration: CreatorShellDayGenerationStub(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            memberRole: "creator",
            todayDate: { "2026-06-01" }
        )

        let card = try await services.generateDayCard(
            scheduledDate: "2026-06-03",
            dayBrief: "Creator brief for generation."
        )

        XCTAssertEqual(card.scheduledDate, "2026-06-03")
        XCTAssertNil(services.dayBriefGenerationErrors["2026-06-03"])
    }

    func testPairedSessionExposesAppleIdentityFields() {
        let session = PairedDeviceSession(
            projectURL: URL(string: "https://example.supabase.co")!,
            publishableKey: "key",
            workspaceID: UUID(),
            creatorID: UUID(),
            memberID: UUID(),
            deviceInstallationID: UUID(),
            deviceToken: "token",
            workspaceName: "Workspace",
            creatorDisplayName: "Ada Creator",
            memberRole: "creator",
            pairedAt: Date(),
            authenticatedEmail: "ada@privaterelay.appleid.com"
        )

        XCTAssertEqual(session.authenticatedEmail, "ada@privaterelay.appleid.com")
        XCTAssertEqual(session.creatorDisplayName, "Ada Creator")
        XCTAssertEqual(session.memberRole, "creator")
    }
}

private struct CreatorShellDayGenerationStub: DayGenerationRepository {
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
                title: "Day card: \(dayBrief)",
                whyToday: "Shell test.",
                growthJob: "Consistency.",
                contentPillar: "lifestyle",
                shootability: "easy",
                estimatedShootMinutes: 8,
                energyRequired: "low",
                languageMode: "English",
                sceneList: [
                    ShotScene(number: 1, title: "Test scene", duration: "3 sec", symbol: "sparkles")
                ],
                script: "Test script.",
                noVoiceoverVersion: "No VO.",
                onScreenText: ["Test"],
                caption: "Test caption.",
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
                sourceNote: "Stub."
            ),
            warnings: [],
            assumptions: [],
            sourceSummary: "Stub generation",
            generatedAt: "2026-06-01T00:00:00Z"
        )
    }
}
