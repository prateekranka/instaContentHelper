import XCTest
@testable import CreatorContentOS

final class PlanDayIdeaBuilderTests: XCTestCase {
    func testBuildIdeasReturnsExactlyFiveCandidates() {
        let setup = PlanDaySetupSummary(
            contentPillars: ["gym", "recovery"],
            voiceIsConfigured: true,
            confirmedReferenceCount: 2,
            totalReferenceCount: 3
        )

        let ideas = PlanDayIdeaBuilder.buildIdeas(
            scheduledDate: "2026-08-07",
            setup: setup
        )

        XCTAssertEqual(ideas.count, 5)
        XCTAssertEqual(Set(ideas.map(\.title)).count, 5)
    }

    func testBuildIdeasAreSuccinctOneLinersAboutContentTopics() {
        let setup = PlanDaySetupSummary(
            contentPillars: ["Fitness"],
            voiceIsConfigured: true,
            confirmedReferenceCount: 0,
            totalReferenceCount: 0
        )

        let ideas = PlanDayIdeaBuilder.buildIdeas(
            scheduledDate: "2026-08-07",
            setup: setup
        )

        for idea in ideas {
            XCTAssertFalse(idea.title.isEmpty)
            XCTAssertFalse(
                idea.title.contains("\n"),
                "Idea titles should be single-line: \(idea.title)"
            )
            XCTAssertTrue(
                idea.title.lowercased().contains("fitness"),
                "Expected pillar in one-liner title, got: \(idea.title)"
            )
            XCTAssertFalse(
                ["Behind the routine", "Small win, said plainly", "Process over outcome",
                 "Question you keep getting", "Contrast reel"].contains(idea.title),
                "Old abstract titles should be gone"
            )
        }
    }

    func testBuildIdeasUsesSelectedDateWeekdayWhenTemplateNeedsIt() {
        let setup = PlanDaySetupSummary(
            contentPillars: ["food"],
            voiceIsConfigured: false,
            confirmedReferenceCount: 0,
            totalReferenceCount: 0
        )

        let ideas = PlanDayIdeaBuilder.buildIdeas(
            scheduledDate: "2026-08-12",
            setup: setup
        )

        let weekdayMentions = ideas.filter { $0.title.contains("Wednesday") }
        XCTAssertFalse(
            weekdayMentions.isEmpty,
            "Expected at least one Wednesday-framed idea for 2026-08-12, got: \(ideas.map(\.title))"
        )
    }

    func testBuildIdeasIsDeterministicForSameInputs() {
        let setup = PlanDaySetupSummary(
            contentPillars: ["lifestyle"],
            voiceIsConfigured: true,
            confirmedReferenceCount: 1,
            totalReferenceCount: 2
        )
        let date = "2026-09-01"

        let first = PlanDayIdeaBuilder.buildIdeas(scheduledDate: date, setup: setup)
        let second = PlanDayIdeaBuilder.buildIdeas(scheduledDate: date, setup: setup)

        XCTAssertEqual(first, second)
    }

    func testBuildIdeasChangesWithDateOrPillars() {
        let base = PlanDaySetupSummary(
            contentPillars: ["fitness"],
            voiceIsConfigured: true,
            confirmedReferenceCount: 0,
            totalReferenceCount: 0
        )
        let otherPillar = PlanDaySetupSummary(
            contentPillars: ["travel"],
            voiceIsConfigured: true,
            confirmedReferenceCount: 0,
            totalReferenceCount: 0
        )

        let dateA = PlanDayIdeaBuilder.buildIdeas(scheduledDate: "2026-08-07", setup: base)
        let dateB = PlanDayIdeaBuilder.buildIdeas(scheduledDate: "2026-08-14", setup: base)
        let pillarB = PlanDayIdeaBuilder.buildIdeas(scheduledDate: "2026-08-07", setup: otherPillar)

        XCTAssertNotEqual(dateA.map(\.title), dateB.map(\.title))
        XCTAssertNotEqual(dateA.map(\.title), pillarB.map(\.title))
        XCTAssertTrue(pillarB.allSatisfy { $0.title.lowercased().contains("travel") })
    }

    func testBuildIdeasReflectsVoiceAndReferencesInFormatSummary() {
        let withoutExtras = PlanDaySetupSummary(
            contentPillars: ["food"],
            voiceIsConfigured: false,
            confirmedReferenceCount: 0,
            totalReferenceCount: 0
        )
        let withExtras = PlanDaySetupSummary(
            contentPillars: ["food"],
            voiceIsConfigured: true,
            confirmedReferenceCount: 3,
            totalReferenceCount: 4
        )
        let withLabel = PlanDaySetupSummary(
            contentPillars: ["food"],
            voiceIsConfigured: true,
            confirmedReferenceCount: 1,
            totalReferenceCount: 1,
            confirmedReferenceLabels: ["Calm Drive"]
        )

        let plain = PlanDayIdeaBuilder.buildIdeas(
            scheduledDate: "2026-08-07",
            setup: withoutExtras
        )
        let enriched = PlanDayIdeaBuilder.buildIdeas(
            scheduledDate: "2026-08-07",
            setup: withExtras
        )
        let labeled = PlanDayIdeaBuilder.buildIdeas(
            scheduledDate: "2026-08-07",
            setup: withLabel
        )

        XCTAssertFalse(plain[0].summary.contains("in your voice"))
        XCTAssertFalse(plain[0].summary.contains("reference"))
        XCTAssertTrue(enriched[0].summary.contains("in your voice"))
        XCTAssertTrue(enriched[0].summary.contains("3 references"))
        XCTAssertTrue(labeled[0].summary.contains("paced like Calm Drive"))
    }

    func testFallbackPillarWhenSetupHasNone() {
        let setup = PlanDaySetupSummary(
            contentPillars: [],
            voiceIsConfigured: false,
            confirmedReferenceCount: 0,
            totalReferenceCount: 0
        )
        let ideas = PlanDayIdeaBuilder.buildIdeas(
            scheduledDate: "2026-08-07",
            setup: setup
        )

        XCTAssertEqual(ideas.count, 5)
        XCTAssertTrue(ideas.allSatisfy { $0.title.contains("your niche") })
    }

    func testDayBriefCombinesVisibleTitleAndSummary() {
        let setup = PlanDaySetupSummary(
            contentPillars: ["makeup"],
            voiceIsConfigured: true,
            confirmedReferenceCount: 0,
            totalReferenceCount: 0
        )
        let idea = PlanDayIdeaBuilder.buildIdeas(
            scheduledDate: "2026-08-07",
            setup: setup
        ).first!

        XCTAssertEqual(idea.dayBrief, "\(idea.title). \(idea.summary)")
    }

    func testMappingAcceptsRemoteTitleAndDayBrief() {
        let setup = PlanDaySetupSummary(
            contentPillars: ["gym"],
            voiceIsConfigured: true,
            confirmedReferenceCount: 1,
            totalReferenceCount: 1
        )
        let remote = [
            PlanDayIdeaRemoteIdea(title: "POV: gym mornings that feel honest", dayBrief: "POV: gym mornings that feel honest. POV Reel"),
            PlanDayIdeaRemoteIdea(title: "GRWM while I pack my gym bag", dayBrief: "GRWM while I pack my gym bag"),
            PlanDayIdeaRemoteIdea(title: "3 gym mistakes I still catch myself making", dayBrief: "3 gym mistakes I still catch myself making"),
            PlanDayIdeaRemoteIdea(title: "Myth vs reality: rest day advice", dayBrief: "Myth vs reality: rest day advice"),
            PlanDayIdeaRemoteIdea(title: "Hot take: busy days still count", dayBrief: "Hot take: busy days still count"),
        ]

        let ideas = PlanDayIdeaMapping.candidates(
            from: remote,
            scheduledDate: "2026-08-07",
            setup: setup
        )

        XCTAssertEqual(ideas.count, 5)
        XCTAssertEqual(ideas[0].title, "POV: gym mornings that feel honest")
        XCTAssertEqual(ideas[0].summary, "")
        XCTAssertTrue(ideas[0].dayBrief.contains("POV: gym mornings"))
        XCTAssertTrue(ideas.allSatisfy { !$0.title.contains("\n") })
    }

    func testMappingFallsBackToBuilderWhenRemoteIncomplete() {
        let setup = PlanDaySetupSummary(
            contentPillars: ["food"],
            voiceIsConfigured: false,
            confirmedReferenceCount: 0,
            totalReferenceCount: 0
        )
        let ideas = PlanDayIdeaMapping.candidates(
            from: [PlanDayIdeaRemoteIdea(title: "Only one LLM idea", dayBrief: "Only one LLM idea")],
            scheduledDate: "2026-08-07",
            setup: setup
        )

        XCTAssertEqual(ideas.count, 5)
        XCTAssertEqual(ideas[0].title, "Only one LLM idea")
        XCTAssertTrue(ideas.dropFirst().allSatisfy { $0.title.lowercased().contains("food") || $0.title.contains("your niche") })
    }

    func testMappingDropsBlankAndDuplicateTitles() {
        let setup = PlanDaySetupSummary(
            contentPillars: ["travel"],
            voiceIsConfigured: false,
            confirmedReferenceCount: 0,
            totalReferenceCount: 0
        )
        let ideas = PlanDayIdeaMapping.candidates(
            from: [
                PlanDayIdeaRemoteIdea(title: "  ", dayBrief: ""),
                PlanDayIdeaRemoteIdea(title: "Same idea", dayBrief: "Same idea"),
                PlanDayIdeaRemoteIdea(title: "same idea", dayBrief: "same idea"),
                PlanDayIdeaRemoteIdea(title: "Travel packing reel", dayBrief: "Travel packing reel"),
            ],
            scheduledDate: "2026-08-07",
            setup: setup
        )

        XCTAssertEqual(ideas.count, 5)
        XCTAssertEqual(ideas.filter { $0.title.lowercased() == "same idea" }.count, 1)
    }

    func testResponseDecodingUsesSnakeCaseDayBrief() throws {
        let json = """
        {
          "scheduled_date": "2026-08-07",
          "source": "llm",
          "ideas": [
            { "title": "POV travel morning", "day_brief": "POV travel morning. POV Reel" }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PlanDayIdeasResponse.self, from: json)
        XCTAssertEqual(decoded.scheduledDate, "2026-08-07")
        XCTAssertEqual(decoded.ideas.count, 1)
        XCTAssertEqual(decoded.ideas[0].dayBrief, "POV travel morning. POV Reel")
    }

    func testFixtureRepositoryReturnsBuilderIdeas() async throws {
        let setup = PlanDaySetupSummary(
            contentPillars: ["lifestyle"],
            voiceIsConfigured: true,
            confirmedReferenceCount: 0,
            totalReferenceCount: 0
        )
        let ideas = try await FixturePlanDayIdeaRepository().generatePlanDayIdeas(
            creatorID: UUID(),
            scheduledDate: "2026-08-07",
            setup: setup,
            context: .creatorFixture
        )
        let expected = PlanDayIdeaBuilder.buildIdeas(scheduledDate: "2026-08-07", setup: setup)
        XCTAssertEqual(ideas, expected)
    }

    @MainActor
    func testAppServicesFixtureRefreshUsesOnDeviceBuilder() async {
        let services = AppServices.fixtureBacked()
        let setup = PlanDaySetupSummary.from(
            profile: services.creatorProfileSummary,
            intelligenceHome: services.intelligenceHome
        )
        let date = "2026-08-14"
        await services.refreshPlanDayIdeas(scheduledDate: date, setup: setup)
        XCTAssertEqual(
            services.planDayIdeas(for: date, setup: setup),
            PlanDayIdeaBuilder.buildIdeas(scheduledDate: date, setup: setup)
        )
    }

    func testSetupSummaryFromServicesFields() {
        let profile = CreatorProfileSummary(
            displayName: "Creator",
            positioning: "Warm fitness creator",
            voiceLine: "Warm",
            noGoTopics: ["Politics", "Weight talk"],
            voiceRules: ["Conversational", "Self-aware"],
            contentPillars: ["gym", "food"],
            captionStyle: "Short sharp lines",
            recurringFormats: []
        )
        let intelligence = IntelligenceHome(
            sourcePulse: SourcePulseSummary(
                title: "Pulse",
                subtitle: "Refs",
                references: [
                    ReferenceSummary(
                        title: "Calm Drive",
                        sourceType: "Audio link",
                        note: "Note",
                        state: .approved,
                        symbol: "music.note"
                    ),
                    ReferenceSummary(
                        title: "Needs work",
                        sourceType: "Profile",
                        note: "Note",
                        state: .needsReview,
                        symbol: "person"
                    ),
                ]
            ),
            readyForThisWeek: [],
            needsReview: [],
            ideaCandidates: [],
            recentlyUsed: [],
            librarySections: []
        )

        let setup = PlanDaySetupSummary.from(profile: profile, intelligenceHome: intelligence)

        XCTAssertEqual(setup.contentPillars, ["gym", "food"])
        XCTAssertTrue(setup.voiceIsConfigured)
        XCTAssertEqual(setup.confirmedReferenceCount, 1)
        XCTAssertEqual(setup.totalReferenceCount, 2)
        XCTAssertEqual(setup.positioning, "Warm fitness creator")
        XCTAssertEqual(setup.voiceRulesText, "Conversational; Self-aware")
        XCTAssertEqual(setup.captionStyle, "Short sharp lines")
        XCTAssertEqual(setup.noGoTopicsText, "Politics; Weight talk")
        XCTAssertEqual(setup.confirmedReferenceLabels, ["Calm Drive"])
        XCTAssertTrue(setup.cacheFingerprint.contains("Calm Drive"))
        XCTAssertTrue(setup.cacheFingerprint.contains("Warm fitness creator"))
    }

    func testSetupSummaryTruncatesVoiceAndReferenceLabels() {
        let longPositioning = String(repeating: "p", count: 600)
        let longLabel = String(repeating: "L", count: 120)
        let manyLabels = (0..<20).map { "Ref \($0) \(longLabel)" }
        let profile = CreatorProfileSummary(
            displayName: "Creator",
            positioning: longPositioning,
            voiceLine: "Warm",
            noGoTopics: [String(repeating: "n", count: 300)],
            voiceRules: [String(repeating: "v", count: 500)],
            contentPillars: ["gym"],
            captionStyle: String(repeating: "c", count: 300),
            recurringFormats: []
        )
        let intelligence = IntelligenceHome(
            sourcePulse: SourcePulseSummary(
                title: "Pulse",
                subtitle: "Refs",
                references: manyLabels.map {
                    ReferenceSummary(
                        title: $0,
                        sourceType: "Reel",
                        note: "ok",
                        state: .approved,
                        symbol: "link"
                    )
                }
            ),
            readyForThisWeek: [],
            needsReview: [],
            ideaCandidates: [],
            recentlyUsed: [],
            librarySections: []
        )

        let setup = PlanDaySetupSummary.from(profile: profile, intelligenceHome: intelligence)

        XCTAssertEqual(setup.positioning.count, PlanDayIdeaPayloadLimits.positioningMaxChars)
        XCTAssertEqual(setup.voiceRulesText.count, PlanDayIdeaPayloadLimits.voiceRulesMaxChars)
        XCTAssertEqual(setup.captionStyle.count, PlanDayIdeaPayloadLimits.captionStyleMaxChars)
        XCTAssertLessThanOrEqual(setup.noGoTopicsText.count, PlanDayIdeaPayloadLimits.noGoTopicsMaxChars)
        XCTAssertEqual(setup.confirmedReferenceLabels.count, PlanDayIdeaPayloadLimits.maxReferenceLabels)
        XCTAssertTrue(
            setup.confirmedReferenceLabels.allSatisfy {
                $0.count <= PlanDayIdeaPayloadLimits.referenceLabelMaxChars
            }
        )
    }

    @MainActor
    func testAppServicesCacheInvalidatesWhenSetupFingerprintChanges() async {
        let services = AppServices.fixtureBacked()
        let date = "2026-08-14"
        let base = PlanDaySetupSummary(
            contentPillars: ["gym"],
            voiceIsConfigured: true,
            confirmedReferenceCount: 0,
            totalReferenceCount: 0,
            positioning: "Voice A"
        )
        let changed = PlanDaySetupSummary(
            contentPillars: ["gym"],
            voiceIsConfigured: true,
            confirmedReferenceCount: 0,
            totalReferenceCount: 0,
            positioning: "Voice B"
        )

        await services.refreshPlanDayIdeas(scheduledDate: date, setup: base)
        let first = services.planDayIdeas(for: date, setup: base)
        XCTAssertEqual(first, PlanDayIdeaBuilder.buildIdeas(scheduledDate: date, setup: base))

        // Same date, new fingerprint → builder for new setup (cache miss).
        let second = services.planDayIdeas(for: date, setup: changed)
        XCTAssertEqual(second, PlanDayIdeaBuilder.buildIdeas(scheduledDate: date, setup: changed))
        XCTAssertNotEqual(base.cacheFingerprint, changed.cacheFingerprint)
    }
}
