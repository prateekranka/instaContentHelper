import XCTest
@testable import CreatorContentOS

final class GeneratedStoryboardBreakdownTests: XCTestCase {
    func testRowsAlignSceneShotVoiceoverAndOnScreenTextByIndex() {
        let card = makeCard(
            sceneList: [
                ShotScene(number: 1, title: "Talking head hook", duration: "3 sec", symbol: "person.crop.rectangle"),
                ShotScene(number: 2, title: "Gym b-roll", duration: "4 sec", symbol: "dumbbell")
            ],
            shotTimeline: [
                ProductionTimelineItem(
                    timestamp: "0-3 sec",
                    title: "Close-up talking head",
                    detail: "You looking into the camera with a confident hook.",
                    shot: "Close-up",
                    videoPortion: "Direct eye contact and confident expression.",
                    voiceover: nil,
                    onScreenText: nil,
                    placement: nil,
                    durationSeconds: 3
                ),
                ProductionTimelineItem(
                    timestamp: "3-7 sec",
                    title: "Wide gym shot",
                    detail: "Walking into the gym and looking around.",
                    shot: "B-roll",
                    videoPortion: "Gym entrance, slightly uncertain but steady.",
                    voiceover: nil,
                    onScreenText: nil,
                    placement: nil,
                    durationSeconds: 4
                )
            ],
            voiceoverTimeline: [
                ProductionTimelineItem(
                    timestamp: "0-3 sec",
                    title: "Hook line",
                    detail: "The biggest lie women are told after 40.",
                    shot: nil,
                    videoPortion: nil,
                    voiceover: "The biggest lie women are told after 40.",
                    onScreenText: nil,
                    placement: nil,
                    durationSeconds: 3
                ),
                ProductionTimelineItem(
                    timestamp: "3-7 sec",
                    title: "Belief line",
                    detail: "I believed that too.",
                    shot: nil,
                    videoPortion: nil,
                    voiceover: "I believed that too.",
                    onScreenText: nil,
                    placement: nil,
                    durationSeconds: 4
                )
            ],
            onScreenTextTimeline: [
                ProductionTimelineItem(
                    timestamp: "0-3 sec",
                    title: "Hook text",
                    detail: "The biggest lie women are told after 40?",
                    shot: nil,
                    videoPortion: nil,
                    voiceover: nil,
                    onScreenText: "The biggest lie women are told after 40?",
                    placement: nil,
                    durationSeconds: 3
                ),
                ProductionTimelineItem(
                    timestamp: "3-7 sec",
                    title: "Belief text",
                    detail: "I believed that too.",
                    shot: nil,
                    videoPortion: nil,
                    voiceover: nil,
                    onScreenText: "I believed that too.",
                    placement: nil,
                    durationSeconds: 4
                )
            ]
        )

        let rows = GeneratedStoryboardBreakdown.rows(for: card)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].timecode, "0-3 sec")
        XCTAssertEqual(rows[0].sceneNumber, 1)
        XCTAssertEqual(rows[0].visualShot, "Close-up")
        XCTAssertEqual(rows[0].whatToShow, "Direct eye contact and confident expression.")
        XCTAssertEqual(rows[0].audioDialogue, "The biggest lie women are told after 40.")
        XCTAssertEqual(rows[0].onScreenText, "The biggest lie women are told after 40?")
        XCTAssertEqual(rows[1].timecode, "3-7 sec")
        XCTAssertEqual(rows[1].sceneNumber, 2)
        XCTAssertEqual(rows[1].visualShot, "B-roll")
        XCTAssertEqual(rows[1].audioDialogue, "I believed that too.")
        XCTAssertEqual(rows[1].onScreenText, "I believed that too.")
    }

    func testRowsPreserveOnScreenTextCaptionAndPlacement() throws {
        let data = """
        {
          "timestamp": "0:00-0:03",
          "text": "Back in routine",
          "placement": "Upper third over motion"
        }
        """.data(using: .utf8)!
        let timelineItem = try JSONDecoder().decode(ProductionTimelineItem.self, from: data)
        let card = makeCard(
            sceneList: [
                ShotScene(number: 1, title: "Opening detail", duration: "3 sec", symbol: "sparkles")
            ],
            onScreenTextTimeline: [timelineItem]
        )

        let rows = GeneratedStoryboardBreakdown.rows(for: card)

        XCTAssertEqual(rows[0].onScreenText, "Back in routine")
        XCTAssertEqual(rows[0].onScreenTextPlacement, "Upper third over motion")
    }

    func testRowsFallbackToSceneDurationsScriptAndOnScreenTextArrays() {
        let card = makeCard(
            sceneList: [
                ShotScene(number: 1, title: "Opening detail", duration: "3 sec", symbol: "sparkles"),
                ShotScene(number: 2, title: "Action detail", duration: "5 sec", symbol: "figure.run")
            ],
            script: """
            First line.
            Second line.
            """,
            onScreenText: ["First text", "Second text"]
        )

        let rows = GeneratedStoryboardBreakdown.rows(for: card)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].timecode, "0:00-0:03")
        XCTAssertEqual(rows[0].visualShot, "Opening detail")
        XCTAssertEqual(rows[0].audioDialogue, "First line.")
        XCTAssertEqual(rows[0].onScreenText, "First text")
        XCTAssertEqual(rows[1].timecode, "0:03-0:08")
        XCTAssertEqual(rows[1].visualShot, "Action detail")
        XCTAssertEqual(rows[1].audioDialogue, "Second line.")
        XCTAssertEqual(rows[1].onScreenText, "Second text")
    }

    func testRowsAttachThumbnailURLsByRowIndex() {
        let thumbnailURL = URL(string: "https://example.com/storyboard/row-1.jpg")!
        let card = makeCard(
            sceneList: [
                ShotScene(number: 1, title: "Opening detail", duration: "3 sec", symbol: "sparkles"),
                ShotScene(number: 2, title: "Action detail", duration: "5 sec", symbol: "figure.run")
            ],
            storyboardThumbnailAssets: [
                StoryboardThumbnailAsset(
                    rowIndex: 1,
                    promptHash: "abc123",
                    storagePath: "path/row-1.jpg",
                    publicURL: thumbnailURL.absoluteString,
                    model: "gemini-3.1-flash-lite-image",
                    promptVersion: "storyboard_thumbnail_v1",
                    status: "generated",
                    generatedAt: "2026-07-01T09:00:00Z"
                )
            ]
        )

        let rows = GeneratedStoryboardBreakdown.rows(for: card)

        XCTAssertNil(rows[0].thumbnailURL)
        XCTAssertEqual(rows[1].thumbnailURL, thumbnailURL)
    }

    func testThumbnailRequestEncodesRevisionInstructions() throws {
        let request = SupabaseGenerateStoryboardThumbnailRequest(
            creatorID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            dailyCardID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            rowIndexes: [0, 2],
            force: true,
            revisionInstructions: "Make the gym shot brighter and closer."
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["creator_id"] as? String, "22222222-2222-4222-8222-222222222222")
        XCTAssertEqual(object["daily_card_id"] as? String, "33333333-3333-4333-8333-333333333333")
        XCTAssertEqual(object["row_indexes"] as? [Int], [0, 2])
        XCTAssertEqual(object["force"] as? Bool, true)
        XCTAssertEqual(object["revision_instructions"] as? String, "Make the gym shot brighter and closer.")
    }

    func testThumbnailWeekRequestEncodesResumeBatchFields() throws {
        let request = SupabaseGenerateStoryboardThumbnailsRequest(
            creatorID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            weeklyPlanID: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
            force: false,
            maxRows: 6
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["creator_id"] as? String, "22222222-2222-4222-8222-222222222222")
        XCTAssertEqual(object["weekly_plan_id"] as? String, "44444444-4444-4444-8444-444444444444")
        XCTAssertEqual(object["force"] as? Bool, false)
        XCTAssertEqual(object["max_rows"] as? Int, 6)
    }

    func testDirectDailyCardSelectIncludesStoryboardThumbnailAssets() {
        XCTAssertTrue(
            SupabaseSelect.dailyCard.contains("storyboard_thumbnail_assets"),
            "Direct weekly reads must include storyboard thumbnail assets so refreshed app state cannot hide DB-backed thumbnails."
        )
    }

    private func makeCard(
        sceneList: [ShotScene],
        shotTimeline: [ProductionTimelineItem] = [],
        voiceoverTimeline: [ProductionTimelineItem] = [],
        onScreenTextTimeline: [ProductionTimelineItem] = [],
        script: String = "Default script.",
        onScreenText: [String] = [],
        storyboardThumbnailAssets: [StoryboardThumbnailAsset] = []
    ) -> GeneratedDailyCardDraft {
        GeneratedDailyCardDraft(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            scheduledDate: "2026-07-06",
            status: "draft",
            title: "Storyboard test card",
            whyToday: "Tests the mobile storyboard output.",
            growthJob: "Make the review output easier to scan.",
            contentPillar: "lifestyle",
            shootability: "easy",
            estimatedShootMinutes: 12,
            energyRequired: "medium",
            languageMode: "English",
            format: "Reel",
            primarySurface: "Instagram",
            durationSeconds: nil,
            hook: "A clear hook",
            saveShareReason: "Easy to film and review.",
            sceneList: sceneList,
            shotTimeline: shotTimeline,
            voiceoverTimeline: voiceoverTimeline,
            onScreenTextTimeline: onScreenTextTimeline,
            script: script,
            noVoiceoverVersion: "Silent backup.",
            onScreenText: onScreenText,
            caption: "Caption",
            cta: "Save this.",
            hashtags: ["creator"],
            coverText: "Cover",
            postInstructions: "Keep captions bold and readable on mobile.",
            brandEventNotes: "",
            backupStory: "Backup story",
            backupCaptionOnly: "Backup caption",
            audioOptionNotes: "Use a quiet track.",
            creatorFitScore: 90,
            riskNotes: [],
            assumptions: [],
            sourceNote: "Test",
            storyboardThumbnailAssets: storyboardThumbnailAssets
        )
    }
}
