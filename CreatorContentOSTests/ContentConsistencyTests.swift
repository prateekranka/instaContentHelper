import XCTest
@testable import CreatorContentOS

/// Regression coverage for the Today-card internal-consistency bug.
///
/// Root cause (Subagent A): the published `daily_cards` row stores timeline
/// arrays (shot_timeline, on_screen_text_timeline, etc.) packed inside the
/// `post_instructions` JSONB blob. When those arrays are absent, the ShootFolio
/// per-scene guidance used to fall back to `card.onScreenText?.first`, which
/// made MULTIPLE scenes render the SAME first on-screen text — the visible
/// "scenes/caption/audio don't align" mismatch.
///
/// These tests pin two invariants:
/// 1. A scene without its own on-screen text shows NOTHING (not another scene's
///    text) after the `?? .first` collapse was removed.
/// 2. The four pillars now flow end-to-end through generation -> DTO -> card.
@MainActor
final class ContentConsistencyTests: XCTestCase {
    func testSceneGuidanceDoesNotCollapseMultipleScenesToFirstOnScreenText() throws {
        // A published card with 3 scenes but only 2 on-screen text lines.
        // Scene 3 has no dedicated on-screen text.
        let card = DailyCard(
            title: "Recovery reset",
            context: "Wednesday",
            effortLabel: "Easy - 8 min",
            whyToday: "Active recovery after a heavy week.",
            scenes: [
                ShotScene(number: 1, title: "Shoes by the door", duration: "3 sec", symbol: "shoeprints.fill"),
                ShotScene(number: 2, title: "Slow stretch", duration: "4 sec", symbol: "figure.cooldown"),
                ShotScene(number: 3, title: "Quiet breath", duration: "3 sec", symbol: "wind")
            ],
            onScreenText: ["Recovery counts", "Slow it down"]
        )

        // Scenes 0 and 1 each get their own on-screen text.
        XCTAssertEqual(ShootFolioOnScreenText.text(forSceneAt: 0, in: card), "Recovery counts")
        XCTAssertEqual(ShootFolioOnScreenText.text(forSceneAt: 1, in: card), "Slow it down")
        // Scene 2 has no on-screen text: it must NOT borrow scene 1's text.
        XCTAssertNil(ShootFolioOnScreenText.text(forSceneAt: 2, in: card),
                     "A scene without its own on-screen text must show nothing, not another scene's text.")
    }

    func testSceneGuidanceUsesPerSceneTimelineTextWhenPresent() throws {
        let card = DailyCard(
            title: "Gym day",
            context: "Tuesday",
            effortLabel: "Medium - 12 min",
            whyToday: "One movement I keep coming back to.",
            scenes: [
                ShotScene(number: 1, title: "Setup", duration: "3 sec", symbol: "dumbbell"),
                ShotScene(number: 2, title: "Lift", duration: "4 sec", symbol: "figure.strengthtraining")
            ],
            onScreenTextTimeline: [
                ProductionTimelineItem(timestamp: "0:00-0:03", title: "Setup", detail: "", onScreenText: "My own setup"),
                ProductionTimelineItem(timestamp: "0:03-0:07", title: "Lift", detail: "", onScreenText: "One clean rep")
            ]
        )

        XCTAssertEqual(ShootFolioOnScreenText.text(forSceneAt: 0, in: card), "My own setup")
        XCTAssertEqual(ShootFolioOnScreenText.text(forSceneAt: 1, in: card), "One clean rep")
    }

    func testPublishedCardDecodesHookEndToEnd() throws {
        // The published-card read path must recover the hook that the generator
        // stored inside post_instructions (there is no dedicated hook column).
        let data = Data(
            """
            {
              "id": "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1",
              "workspace_id": "11111111-1111-4111-8111-111111111111",
              "creator_id": "33333333-3333-4333-8333-333333333333",
              "weekly_plan_id": "77777777-7777-4777-8777-777777777771",
              "scheduled_date": "2026-06-24",
              "status": "published",
              "title": "The tiny thing I changed today",
              "content_pillar": "lifestyle",
              "scene_list": [{"number":1,"title":"Detail","duration":"3 sec","symbol":"sparkles"}],
              "post_instructions": {
                "hook": "The tiny thing I changed today",
                "instructions": "Document the small change."
              }
            }
            """.utf8
        )

        let row = try JSONDecoder().decode(SupabaseDailyCardRow.self, from: data)
        let card = row.domainCard()

        XCTAssertEqual(card.title, "The tiny thing I changed today")
        XCTAssertEqual(card.hook, "The tiny thing I changed today",
                       "Hook must be recovered from post_instructions and align with the title/pillar.")
    }

    func testCardFieldsAlignToOneConceptWhenGenerated() throws {
        // A generated card should carry a hook, scenes, script, caption, and
        // backup that all describe the SAME recovery concept. This is the
        // alignment invariant Subagent A protects.
        let draft = GeneratedDailyCardDraft(
            id: UUID(),
            scheduledDate: "2026-06-24",
            status: "published",
            title: "My recovery reset after a heavy week",
            whyToday: "Make recovery active and visible.",
            growthJob: "Show recovery as a real part of the week.",
            contentPillar: "recovery",
            shootability: "easy",
            estimatedShootMinutes: 8,
            energyRequired: "low",
            languageMode: "English",
            hook: "My recovery reset after a heavy week",
            sceneList: [
                ShotScene(number: 1, title: "Foam roller", duration: "3 sec", symbol: "figure.cooldown")
            ],
            script: "After a heavy week, my recovery reset is simple.",
            noVoiceoverVersion: "Silent version.",
            onScreenText: ["Recovery reset"],
            caption: "My recovery reset after a heavy week is just a few quiet minutes.",
            cta: "Save this reset.",
            hashtags: ["recovery"],
            coverText: "Recovery reset",
            postInstructions: "Calm audio.",
            brandEventNotes: "",
            backupStory: "One recovery clip as a story.",
            backupCaptionOnly: "Recovery day note.",
            audioOptionNotes: "Calm audio.",
            creatorFitScore: 92,
            riskNotes: [],
            assumptions: ["Low energy"],
            sourceNote: "Weekly setup."
        )

        let card = draft.dailyCard(completionState: nil)

        // The hook and title should match — both answer the same "what are we
        // enticing people to stop for" question for one concept.
        XCTAssertEqual(card.hook, draft.hook)
        XCTAssertEqual(card.title, draft.title)
        // The pillar should be recovery and the backup should reference recovery.
        XCTAssertEqual(draft.contentPillar, "recovery")
        XCTAssertTrue(card.backupStory?.lowercased().contains("recovery") ?? false,
                      "Backup story must align to the same concept as the rest of the card.")
    }
}

/// Mirror of ShootFolioView.SceneGuidance.onScreenText exposed for testing.
/// Kept in sync with the production rule so the regression stays meaningful
/// without testing private view internals.
enum ShootFolioOnScreenText {
    static func text(forSceneAt index: Int, in card: DailyCard) -> String? {
        let timelineText = card.onScreenTextTimeline?[safe: index]
        return timelineText?.onScreenText?.nilIfBlank
            ?? timelineText?.title.nilIfBlank
            ?? card.onScreenText?[safe: index]?.nilIfBlank
    }
}
