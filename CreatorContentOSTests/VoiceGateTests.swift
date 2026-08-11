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

    func testVoiceDeferredOpensGateWithEmptyVoice() {
        UserDefaultsOnboardingStore().markComplete(with: Self.deferredData)
        let services = makeServices(profile: Self.emptyProfile)
        XCTAssertTrue(services.voiceDeferred)
        XCTAssertFalse(services.voiceGateOpen)
        XCTAssertTrue(services.canGenerateContent)
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

    func testGenerateDayCardAllowedWhenVoiceConfigured() async throws {
        let services = AppServices.fixtureBacked()
        do {
            _ = try await services.generateDayCard(scheduledDate: "2026-09-10", dayBrief: "Test brief")
        } catch {
            // With voice configured the gate is open; any error here is unrelated to the voice gate.
            XCTAssertFalse(services.dayBriefGenerationErrors["2026-09-10"] == "creator_voice_required")
        }
    }
}
