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

    func testBuildIdeasUsesSelectedDateWeekdayForNonTodayDate() {
        let setup = PlanDaySetupSummary(
            contentPillars: [],
            voiceIsConfigured: false,
            confirmedReferenceCount: 0,
            totalReferenceCount: 0
        )

        let ideas = PlanDayIdeaBuilder.buildIdeas(
            scheduledDate: "2026-08-12",
            setup: setup
        )

        XCTAssertTrue(
            ideas[0].summary.contains("Wednesday"),
            "Expected Wednesday in first idea summary, got: \(ideas[0].summary)"
        )
        XCTAssertTrue(
            ideas[3].summary.contains("Wednesday"),
            "Expected Wednesday in fourth idea summary, got: \(ideas[3].summary)"
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

    func testBuildIdeasReflectsSetupSummaryInCopy() {
        let withoutVoice = PlanDaySetupSummary(
            contentPillars: [],
            voiceIsConfigured: false,
            confirmedReferenceCount: 0,
            totalReferenceCount: 0
        )
        let withVoice = PlanDaySetupSummary(
            contentPillars: [],
            voiceIsConfigured: true,
            confirmedReferenceCount: 0,
            totalReferenceCount: 0
        )

        let noVoiceIdeas = PlanDayIdeaBuilder.buildIdeas(
            scheduledDate: "2026-08-07",
            setup: withoutVoice
        )
        let voiceIdeas = PlanDayIdeaBuilder.buildIdeas(
            scheduledDate: "2026-08-07",
            setup: withVoice
        )

        XCTAssertTrue(noVoiceIdeas[2].summary.contains("your positioning"))
        XCTAssertTrue(voiceIdeas[2].summary.contains("your voice"))

        let withRefs = PlanDaySetupSummary(
            contentPillars: [],
            voiceIsConfigured: true,
            confirmedReferenceCount: 3,
            totalReferenceCount: 4
        )
        let refIdeas = PlanDayIdeaBuilder.buildIdeas(
            scheduledDate: "2026-08-07",
            setup: withRefs
        )
        XCTAssertTrue(refIdeas[4].summary.contains("3 references"))
    }

    func testDayBriefCombinesVisibleTitleAndSummary() {
        let setup = PlanDaySetupSummary(
            contentPillars: [],
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

    func testSetupSummaryFromServicesFields() {
        let profile = CreatorProfileSummary(
            displayName: "Creator",
            positioning: "Warm fitness creator",
            voiceLine: "Warm",
            noGoTopics: [],
            voiceRules: ["Conversational"],
            contentPillars: ["gym", "food"],
            captionStyle: "Short",
            recurringFormats: []
        )
        let intelligence = IntelligenceHome(
            sourcePulse: SourcePulseSummary(
                title: "Pulse",
                subtitle: "Refs",
                references: [
                    ReferenceSummary(
                        title: "Reel",
                        sourceType: "Reel",
                        note: "Note",
                        state: .approved,
                        symbol: "link"
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
    }
}
