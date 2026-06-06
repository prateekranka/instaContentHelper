import XCTest
@testable import MamtaContentOS

final class SupabaseWriteContentDTOTests: XCTestCase {
    func testCompleteTodayRequestEncodesEdgeFunctionContract() throws {
        let context = fixtureContext()
        let card = fixtureCard()

        let object = try encodedObject(
            .completeToday(card: card, decision: .backupStory, context: context)
        )

        XCTAssertEqual(object["action"] as? String, "complete_today")
        XCTAssertEqual(try uuidValue(object, key: "creator_id"), context.creatorID)
        XCTAssertEqual(try uuidValue(object, key: "daily_card_id"), card.id)

        let decision = try XCTUnwrap(object["decision"] as? [String: Any])
        XCTAssertEqual(decision["status"] as? String, "used_backup")
        XCTAssertEqual(decision["output_line"] as? String, "Used backup: 10-second story")
        XCTAssertEqual(decision["has_post_thumbnail"] as? Bool, false)

        let decisionAt = try XCTUnwrap(object["decision_at"] as? String)
        XCTAssertNotNil(ISO8601DateFormatter().date(from: decisionAt))
    }

    func testUpsertArchiveDecisionRequestEncodesEdgeFunctionContract() throws {
        let context = fixtureContext()
        let card = fixtureCard()
        let entry = ArchiveEntry(
            id: UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA2")!,
            dailyCardID: card.id,
            day: "FRI",
            date: "5 JUN",
            cardTitle: card.title,
            decision: .usedBackup,
            outputLine: "Used backup: 10-second story",
            hasPostThumbnail: false
        )

        let object = try encodedObject(
            .upsertArchiveDecision(entry, for: card, context: context)
        )

        XCTAssertEqual(object["action"] as? String, "upsert_archive_decision")
        XCTAssertEqual(try uuidValue(object, key: "creator_id"), context.creatorID)
        XCTAssertEqual(try uuidValue(object, key: "daily_card_id"), card.id)
        XCTAssertEqual(object["archive_date"] as? String, "2026-06-05")
        XCTAssertEqual(object["decision"] as? String, "used_backup")
        XCTAssertEqual(object["output_line"] as? String, "Used backup: 10-second story")
        XCTAssertEqual(object["has_post_thumbnail"] as? Bool, false)
    }

    func testSelectIdeaForNextOpenDayRequestEncodesEdgeFunctionContract() throws {
        let context = fixtureContext()
        let idea = fixtureIdea()
        let plan = fixturePlan()

        let object = try encodedObject(
            .selectIdeaForNextOpenDay(idea: idea, plan: plan, context: context)
        )

        XCTAssertEqual(object["action"] as? String, "select_idea_for_next_open_day")
        XCTAssertEqual(try uuidValue(object, key: "creator_id"), context.creatorID)
        XCTAssertEqual(try uuidValue(object, key: "idea_id"), idea.id)
        XCTAssertEqual(try uuidValue(object, key: "weekly_plan_id"), plan.id)
    }

    func testWriteContentResponseDecodesStructuredSelectResult() throws {
        let cardID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!
        let memberID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA3")!
        let ideaID = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBB1")!
        let data = Data(
            """
            {
              "action": "select_idea_for_next_open_day",
              "daily_card": {
                "id": "\(cardID.uuidString)",
                "status": "published",
                "decision_at": "2026-06-05T08:00:00Z",
                "completed_by_member_id": "\(memberID.uuidString)"
              },
              "idea": {
                "id": "\(ideaID.uuidString)",
                "status": "scheduled"
              }
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(SupabaseWriteContentResponse.self, from: data)

        XCTAssertEqual(response.action, "select_idea_for_next_open_day")
        XCTAssertEqual(response.dailyCard?.id, cardID)
        XCTAssertEqual(response.dailyCard?.status, "published")
        XCTAssertEqual(response.dailyCard?.decisionAt, "2026-06-05T08:00:00Z")
        XCTAssertEqual(response.dailyCard?.completedByMemberID, memberID)
        XCTAssertEqual(response.idea?.id, ideaID)
        XCTAssertEqual(response.idea?.status, "scheduled")
        XCTAssertNil(response.archiveEntry)
    }

    private func encodedObject(_ request: SupabaseWriteContentRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(request)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func uuidValue(_ object: [String: Any], key: String) throws -> UUID {
        let rawValue = try XCTUnwrap(object[key] as? String)
        return try XCTUnwrap(UUID(uuidString: rawValue))
    }

    private func fixtureContext() -> WorkspaceContext {
        WorkspaceContext(
            workspaceID: UUID(uuidString: "D9F0C7CF-BC12-4D9C-9B2F-172930AA1201")!,
            creatorID: UUID(uuidString: "F0F6DA51-4F75-4D18-A01D-0C9E3C1E6A5C")!,
            memberID: UUID(uuidString: "3A0D2B4D-2D8E-4E6D-A8DE-65D2B75F6CC1")!
        )
    }

    private func fixtureCard() -> DailyCard {
        DailyCard(
            id: UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!,
            title: "Live proof Friday card",
            context: "Friday, Race Week",
            effortLabel: "Easy - 12 min",
            whyToday: "Stay visible without overthinking it.",
            scheduledDate: "2026-06-05",
            scenes: []
        )
    }

    private func fixtureIdea() -> WeeklyIdea {
        WeeklyIdea(
            id: UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBB1")!,
            title: "Creator idea",
            reason: "Acceptance idea",
            source: .pattern,
            effortLabel: "Easy"
        )
    }

    private func fixturePlan() -> WeeklyPlan {
        WeeklyPlan(
            id: UUID(uuidString: "77777777-7777-4777-8777-777777777771")!,
            title: "Weekly Plan",
            eyebrow: "PRATEEK WEEKLY CONTROL",
            weekRange: "1 Jun - 7 Jun",
            weekStartDate: "2026-06-01",
            readinessLine: "5 ready, 1 backup, 1 open",
            isSoftLocked: true,
            days: WeeklyPlan.raceWeek.days,
            setupSections: WeeklyPlan.raceWeek.setupSections
        )
    }
}
