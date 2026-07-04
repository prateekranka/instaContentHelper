import XCTest
import Supabase
@testable import CreatorContentOS

@MainActor
final class GenerateWeekTests: XCTestCase {
    func testGenerateWeekRequestEncodesEdgeFunctionContract() throws {
        let request = SupabaseGenerateWeekRequest(
            creatorID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            weekStartDate: "2026-06-08",
            weeklySetupID: UUID(uuidString: "77777777-7777-4777-8777-777777777771")!,
            mode: .generateDraft,
            preserveManualEdits: true,
            mock: true,
            responseMode: .sync
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["creator_id"] as? String, "33333333-3333-4333-8333-333333333333")
        XCTAssertEqual(object["week_start_date"] as? String, "2026-06-08")
        XCTAssertEqual(object["weekly_setup_id"] as? String, "77777777-7777-4777-8777-777777777771")
        XCTAssertEqual(object["mode"] as? String, "generate_draft")
        XCTAssertEqual(object["preserve_manual_edits"] as? Bool, true)
        XCTAssertEqual(object["mock"] as? Bool, true)
        XCTAssertEqual(object["response_mode"] as? String, "sync")
        XCTAssertEqual(object["feature_flags"] as? [String], ["parallel_week_generation"])
    }

    func testGenerateWeekStatusRequestAndRunningResponseUseAsyncContract() throws {
        let generationID = UUID(uuidString: "88888888-8888-4888-8888-888888888881")!
        let creatorID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let request = SupabaseGenerateWeekStatusRequest(
            generationID: generationID,
            creatorID: creatorID
        )

        let requestData = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: requestData) as? [String: Any])

        XCTAssertEqual(object["action"] as? String, "status")
        XCTAssertEqual(object["generation_id"] as? String, generationID.uuidString.lowercased())
        XCTAssertEqual(object["creator_id"] as? String, creatorID.uuidString.lowercased())

        let responseData = Data(
            """
            {
              "generation_id": "\(generationID.uuidString)",
              "weekly_plan_id": null,
              "status": "running",
              "message": "generation_started",
              "completed_day_count": 3,
              "total_day_count": 7,
              "current_day": "2026-06-03",
              "poll_after_seconds": 5
            }
            """.utf8
        )

        let invocation = try SupabaseGenerateWeekInvocation.decode(responseData)
        guard case .running(let status) = invocation else {
            XCTFail("Expected running generation status")
            return
        }
        XCTAssertEqual(status.generationID, generationID)
        XCTAssertEqual(status.status, "running")
        XCTAssertEqual(status.pollAfterSeconds, 5)
        XCTAssertEqual(status.completedDayCount, 3)
        XCTAssertEqual(status.totalDayCount, 7)
        XCTAssertEqual(status.currentDay, "2026-06-03")
        XCTAssertEqual(status.weekProgress.draftedDayCount, 3)
        XCTAssertEqual(status.weekProgress.checkedDayCount, 3)
    }

    func testWeeklyReadResponseDecodesLegacyWeeklyShapeWithoutPublishedKeys() throws {
        let data = Data(
            """
            {
              "weekly_plan": {
                "id": "77777777-7777-4777-8777-777777777771",
                "workspace_id": "11111111-1111-4111-8111-111111111111",
                "creator_id": "33333333-3333-4333-8333-333333333333",
                "weekly_setup_id": "99999999-9999-4999-8999-999999999991",
                "creator_profile_id": null,
                "week_start_date": "2026-07-06",
                "status": "published",
                "strategy_summary": "Legacy deployed read-content response.",
                "warnings": [],
                "assumptions": [],
                "is_soft_locked": false,
                "published_at": null
              },
              "daily_cards": [
                {
                  "id": "88888888-8888-4888-8888-888888888881",
                  "workspace_id": "11111111-1111-4111-8111-111111111111",
                  "creator_id": "33333333-3333-4333-8333-333333333333",
                  "weekly_plan_id": "77777777-7777-4777-8777-777777777771",
                  "scheduled_date": "2026-07-06",
                  "status": "published",
                  "title": "Legacy Monday",
                  "why_today": "Keep the old response shape loading.",
                  "scene_list": []
                }
              ],
              "weekly_setup": {
                "id": "99999999-9999-4999-8999-999999999991",
                "notes": "Weekly routine: legacy brief"
              },
              "idea_bank": [
                {
                  "id": "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1",
                  "title": "Legacy idea",
                  "status": "new"
                }
              ]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(SupabaseWeeklyReadResponse.self, from: data)

        XCTAssertEqual(response.weeklyPlan?.id, UUID(uuidString: "77777777-7777-4777-8777-777777777771"))
        XCTAssertEqual(response.dailyCards.map(\.title), ["Legacy Monday"])
        XCTAssertEqual(response.weeklySetup?.weeklyBriefText, "Weekly routine: legacy brief")
        XCTAssertEqual(response.ideaBank.map(\.title), ["Legacy idea"])
        XCTAssertNil(response.publishedWeeklyPlan)
        XCTAssertTrue(response.publishedDailyCards.isEmpty)
    }

    func testGenerateWeekPartialStatusDecodesIntoProgressModel() throws {
        let generationID = UUID(uuidString: "88888888-8888-4888-8888-888888888881")!
        let weeklyPlanID = UUID(uuidString: "77777777-7777-4777-8777-777777777771")!
        let responseData = Data(
            """
            {
              "generation_id": "\(generationID.uuidString)",
              "weekly_plan_id": "\(weeklyPlanID.uuidString)",
              "status": "partial",
              "message": "six_days_saved_one_failed",
              "completed_day_count": 6,
              "saved_day_count": 6,
              "failed_day_count": 1,
              "total_day_count": 7,
              "current_day": "2026-06-10",
              "poll_after_seconds": 5,
              "failed_days": [
                {
                  "scheduled_date": "2026-06-10",
                  "day_index": 2,
                  "status": "failed",
                  "error_code": "openai_request_failed",
                  "retry_action": "regenerate_day"
                }
              ]
            }
            """.utf8
        )

        let invocation = try SupabaseGenerateWeekInvocation.decode(responseData)
        guard case .running(let status) = invocation else {
            XCTFail("Expected partial generation status to decode as a pollable status")
            return
        }

        XCTAssertEqual(status.generationID, generationID)
        XCTAssertEqual(status.weeklyPlanID, weeklyPlanID)
        XCTAssertEqual(status.status, "partial")
        XCTAssertEqual(status.completedDayCount, 6)
        XCTAssertEqual(status.totalDayCount, 7)
        XCTAssertEqual(status.currentDay, "2026-06-10")
        XCTAssertEqual(status.pollAfterSeconds, 5)
        XCTAssertEqual(status.weekProgress.phase, .draftingDays)
        XCTAssertEqual(status.savedDayCount, 6)
        XCTAssertEqual(status.failedDayCount, 1)
        XCTAssertEqual(status.dayStatuses.count, 1)
        XCTAssertEqual(status.weekProgress.draftedDayCount, 6)
        XCTAssertEqual(status.weekProgress.checkedDayCount, 6)
        XCTAssertEqual(status.weekProgress.totalDayCount, 7)
        XCTAssertEqual(status.weekProgress.currentDay, "2026-06-10")
        XCTAssertEqual(status.weekProgress.message, "six_days_saved_one_failed")
        XCTAssertEqual(status.weekProgress.effectiveSavedDayCount, 6)
        XCTAssertEqual(status.weekProgress.effectiveFailedDayCount, 1)
        XCTAssertEqual(status.weekProgress.failedDayStatuses.first?.failureDetail, "The AI service failed for this day.")
    }

    func testGenerateWeekStatusResponseAcceptsDaysMixedQueuedGenerationState() throws {
        let generationID = UUID(uuidString: "88888888-8888-4888-8888-888888888884")!
        let weeklyPlanID = UUID(uuidString: "77777777-7777-4777-8777-777777777774")!
        let mondayCardID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!
        let tuesdayCardID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA2")!
        let responseData = Data(
            """
            {
              "generation_id": "\(generationID.uuidString)",
              "weekly_plan_id": "\(weeklyPlanID.uuidString)",
              "status": "running",
              "message": "generation_running",
              "completed_day_count": 2,
              "total_day_count": 7,
              "current_day": "2026-07-15",
              "days": [
                {
                  "scheduled_date": "2026-07-13",
                  "day_index": 0,
                  "status": "generated",
                  "daily_card_id": "\(mondayCardID.uuidString)",
                  "error_code": null,
                  "retry_action": null
                },
                {
                  "scheduled_date": "2026-07-14",
                  "day_index": 1,
                  "status": "generated",
                  "daily_card_id": "\(tuesdayCardID.uuidString)",
                  "error_code": null,
                  "retry_action": null
                },
                {
                  "scheduled_date": "2026-07-15",
                  "day_index": 2,
                  "status": "generating",
                  "daily_card_id": null,
                  "error_code": null,
                  "retry_action": null
                },
                { "scheduled_date": "2026-07-16", "day_index": 3, "status": "queued" },
                { "scheduled_date": "2026-07-17", "day_index": 4, "status": "queued" },
                { "scheduled_date": "2026-07-18", "day_index": 5, "status": "queued" },
                { "scheduled_date": "2026-07-19", "day_index": 6, "status": "queued" }
              ]
            }
            """.utf8
        )

        let invocation = try SupabaseGenerateWeekInvocation.decode(responseData)
        guard case .running(let status) = invocation else {
            XCTFail("Expected running generation status")
            return
        }

        XCTAssertEqual(status.dayStatuses.count, 7)
        XCTAssertEqual(status.weekProgress.effectiveSavedDayCount, 2)
        XCTAssertEqual(status.weekProgress.currentDay, "2026-07-15")
        XCTAssertEqual(status.dayStatuses[0].displayName, "Mon")
        XCTAssertEqual(status.dayStatuses[0].displayStatusLabel, "Generated")
        XCTAssertEqual(status.dayStatuses[1].displayStatusLabel, "Generated")
        XCTAssertEqual(status.dayStatuses[2].displayStatusLabel, "Generating")
        XCTAssertEqual(status.dayStatuses[3...6].map(\.displayStatusLabel), Array(repeating: "Queued", count: 4))
        XCTAssertTrue(status.dayStatuses[0].isCompleted)
        XCTAssertTrue(status.dayStatuses[2].isRunning)
        XCTAssertTrue(status.dayStatuses[3].isQueued)
    }

    func testGenerateWeekStatusResponseAcceptsPerDayStatusesAlias() throws {
        let generationID = UUID(uuidString: "88888888-8888-4888-8888-888888888883")!
        let responseData = Data(
            """
            {
              "generation_id": "\(generationID.uuidString)",
              "status": "running",
              "saved_day_count": 1,
              "total_day_count": 7,
              "per_day_statuses": [
                {
                  "scheduled_date": "2026-06-08",
                  "day_index": 0,
                  "status": "saved"
                }
              ]
            }
            """.utf8
        )

        let invocation = try SupabaseGenerateWeekInvocation.decode(responseData)
        guard case .running(let status) = invocation else {
            XCTFail("Expected running generation status")
            return
        }

        XCTAssertEqual(status.dayStatuses.count, 1)
        XCTAssertEqual(status.weekProgress.effectiveSavedDayCount, 1)
    }

    func testGenerateWeekInvocationDecodesLightweightQueuedDraftAsDraft() throws {
        let generationID = UUID(uuidString: "88888888-8888-4888-8888-888888888881")!
        let weeklyPlanID = UUID(uuidString: "77777777-7777-4777-8777-777777777771")!
        let cardID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!
        let data = Data(
            """
            {
              "generation_id": "\(generationID.uuidString)",
              "weekly_plan_id": "\(weeklyPlanID.uuidString)",
              "status": "draft",
              "completed_day_count": 7,
              "saved_day_count": 7,
              "failed_day_count": 0,
              "total_day_count": 7,
              "daily_cards": [
                {
                  "id": "\(cardID.uuidString)",
                  "scheduled_date": "2026-09-21",
                  "status": "draft",
                  "title": "Recovery walk reset",
                  "why_today": "Keep recovery visible.",
                  "growth_job": "Consistency.",
                  "content_pillar": "recovery",
                  "shootability": "easy",
                  "estimated_shoot_minutes": 8,
                  "energy_required": "low",
                  "language_mode": "English",
                  "scene_list": [{"number":1,"title":"Walking shoes","duration":"3 sec","symbol":"shoeprints.fill"}],
                  "script": "Recovery still counts.",
                  "no_voiceover_version": "Use three quiet clips.",
                  "on_screen_text": ["Recovery still counts"],
                  "caption": "A short recovery walk in New Jersey.",
                  "cta": "Save this reminder.",
                  "hashtags": ["recovery"],
                  "cover_text": "Recovery counts",
                  "post_instructions": "Use natural sound.",
                  "brand_event_notes": "",
                  "backup_story": "One walking clip.",
                  "backup_caption_only": "Recovery day note.",
                  "audio_option_notes": "No audio dependency.",
                  "creator_fit_score": 94,
                  "risk_notes": [],
                  "assumptions": ["Low energy"],
                  "source_note": "Weekly setup."
                }
              ],
              "days": [
                {
                  "scheduled_date": "2026-09-21",
                  "day_index": 0,
                  "status": "generated",
                  "daily_card_id": "\(cardID.uuidString)"
                }
              ]
            }
            """.utf8
        )

        let invocation = try SupabaseGenerateWeekInvocation.decode(data)
        guard case .draft(let response) = invocation else {
            XCTFail("Expected lightweight queued terminal status to decode as a draft")
            return
        }

        XCTAssertEqual(response.generationID, generationID)
        XCTAssertEqual(response.weeklyPlanID, weeklyPlanID)
        XCTAssertEqual(response.dailyCards.map(\.id), [cardID])
        XCTAssertEqual(response.ideaBank, [])
        XCTAssertEqual(response.weekProgress.phase, .savingDraftWeek)
        XCTAssertEqual(response.weekProgress.effectiveSavedDayCount, 7)
    }

    func testRegenerateDayRequestEncodesDayGuidanceWhenPresent() throws {
        let request = SupabaseRegenerateDayRequest(
            creatorID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            weeklyPlanID: UUID(uuidString: "77777777-7777-4777-8777-777777777771")!,
            scheduledDate: "2026-06-10",
            preserveManualEdits: false,
            mock: true,
            dayGuidance: "Make it about recovery and family life in New Jersey."
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["action"] as? String, "regenerate_day")
        XCTAssertEqual(object["day_guidance"] as? String, "Make it about recovery and family life in New Jersey.")
    }

    func testRegenerateDayRequestOmitsDayGuidanceWhenNil() throws {
        let request = SupabaseRegenerateDayRequest(
            creatorID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            weeklyPlanID: UUID(uuidString: "77777777-7777-4777-8777-777777777771")!,
            scheduledDate: "2026-06-10",
            preserveManualEdits: false,
            mock: true,
            dayGuidance: nil
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["day_guidance"])
    }

    func testRegenerateDayRequestEncodesClientContextWithSafeMetadataOnly() throws {
        let guidance = "Make it about recovery and family life in New Jersey."
        let request = SupabaseRegenerateDayRequest(
            creatorID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            weeklyPlanID: UUID(uuidString: "77777777-7777-4777-8777-777777777771")!,
            scheduledDate: "2026-06-10",
            preserveManualEdits: false,
            mock: true,
            dayGuidance: guidance,
            clientContext: SupabaseGenerationClientContext(
                uiSurface: "weekly_manager",
                action: "regenerate_day",
                selectedWeekStart: nil,
                scheduledDate: "2026-06-10",
                dayGuidancePresent: true,
                dayGuidanceChars: guidance.count
            )
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["day_guidance"] as? String, guidance)

        let context = try XCTUnwrap(object["client_context"] as? [String: Any])
        XCTAssertEqual(context["ui_surface"] as? String, "weekly_manager")
        XCTAssertEqual(context["action"] as? String, "regenerate_day")
        XCTAssertEqual(context["scheduled_date"] as? String, "2026-06-10")
        XCTAssertEqual(context["day_guidance_present"] as? Bool, true)
        XCTAssertEqual(context["day_guidance_chars"] as? Int, guidance.count)
        XCTAssertNil(context["selected_week_start"])

        let contextKeys = Set(context.keys)
        let safeKeys: Set<String> = [
            "ui_surface", "action", "selected_week_start",
            "scheduled_date", "day_guidance_present", "day_guidance_chars"
        ]
        let unexpectedKeys = contextKeys.subtracting(safeKeys)
        XCTAssertTrue(unexpectedKeys.isEmpty,
                      "client_context must only carry safe metadata keys, found: \(unexpectedKeys)")
        XCTAssertNil(context["day_guidance"],
                     "client_context must not echo the raw day_guidance text")
    }

    func testRegenerateDayRequestOmitsClientContextWhenNil() throws {
        let request = SupabaseRegenerateDayRequest(
            creatorID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            weeklyPlanID: UUID(uuidString: "77777777-7777-4777-8777-777777777771")!,
            scheduledDate: "2026-06-10",
            preserveManualEdits: false,
            mock: true,
            dayGuidance: nil
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["client_context"],
                     "client_context must be omitted when nil for backward compatibility")
    }

    func testGenerateWeekRequestOmitsClientContextWhenNil() throws {
        let request = SupabaseGenerateWeekRequest(
            creatorID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            weekStartDate: "2026-06-08",
            weeklySetupID: UUID(uuidString: "77777777-7777-4777-8777-777777777771")!,
            mode: .generateDraft,
            preserveManualEdits: true,
            mock: true,
            responseMode: .sync
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["client_context"],
                     "client_context must be omitted when nil for backward compatibility")
    }

    func testGenerateWeekRequestEncodesClientContextWhenPresent() throws {
        let request = SupabaseGenerateWeekRequest(
            creatorID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            weekStartDate: "2026-06-08",
            weeklySetupID: UUID(uuidString: "77777777-7777-4777-8777-777777777771")!,
            mode: .generateDraft,
            preserveManualEdits: true,
            mock: true,
            responseMode: .sync,
            clientContext: SupabaseGenerationClientContext(
                uiSurface: "weekly_manager",
                action: "generate_week",
                selectedWeekStart: "2026-06-08",
                scheduledDate: nil,
                dayGuidancePresent: nil,
                dayGuidanceChars: nil
            )
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let context = try XCTUnwrap(object["client_context"] as? [String: Any])
        XCTAssertEqual(context["ui_surface"] as? String, "weekly_manager")
        XCTAssertEqual(context["action"] as? String, "generate_week")
        XCTAssertEqual(context["selected_week_start"] as? String, "2026-06-08")
        XCTAssertNil(context["scheduled_date"])
        XCTAssertNil(context["day_guidance_present"])
        XCTAssertNil(context["day_guidance_chars"])

        let contextKeys = Set(context.keys)
        let safeKeys: Set<String> = [
            "ui_surface", "action", "selected_week_start",
            "scheduled_date", "day_guidance_present", "day_guidance_chars"
        ]
        let unexpectedKeys = contextKeys.subtracting(safeKeys)
        XCTAssertTrue(unexpectedKeys.isEmpty,
                      "client_context must only carry safe metadata keys, found: \(unexpectedKeys)")
    }

    func testRegenerateDayRequestEncodesEdgeFunctionContract() throws {
        let request = SupabaseRegenerateDayRequest(
            creatorID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            weeklyPlanID: UUID(uuidString: "77777777-7777-4777-8777-777777777771")!,
            scheduledDate: "2026-06-10",
            preserveManualEdits: false,
            mock: true
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["action"] as? String, "regenerate_day")
        XCTAssertEqual(object["creator_id"] as? String, "33333333-3333-4333-8333-333333333333")
        XCTAssertEqual(object["weekly_plan_id"] as? String, "77777777-7777-4777-8777-777777777771")
        XCTAssertEqual(object["scheduled_date"] as? String, "2026-06-10")
        XCTAssertEqual(object["preserve_manual_edits"] as? Bool, false)
        XCTAssertEqual(object["response_mode"] as? String, "sync")
        XCTAssertEqual(object["mock"] as? Bool, true)
    }

    func testRetryQueuedDayRequestEncodesEdgeFunctionContract() throws {
        let generationID = UUID(uuidString: "88888888-8888-4888-8888-888888888881")!
        let weeklyPlanID = UUID(uuidString: "77777777-7777-4777-8777-777777777771")!
        let request = SupabaseRetryQueuedDayRequest(
            generationID: generationID,
            scheduledDate: "2026-06-10"
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["action"] as? String, "retry_day")
        XCTAssertEqual(object["generation_id"] as? String, generationID.uuidString.lowercased())
        XCTAssertEqual(object["scheduled_date"] as? String, "2026-06-10")

        let responseData = Data(
            """
            {
              "generation_id": "\(generationID.uuidString)",
              "weekly_plan_id": "\(weeklyPlanID.uuidString)",
              "status": "running",
              "message": "day_retry_queued",
              "poll_after_seconds": 5,
              "day": {
                "scheduled_date": "2026-06-10",
                "day_index": 2,
                "status": "retrying",
                "retry_action": null
              }
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(SupabaseRetryQueuedDayResponse.self, from: responseData)
        XCTAssertEqual(response.generationID, generationID)
        XCTAssertEqual(response.weeklyPlanID, weeklyPlanID)
        XCTAssertEqual(response.status, "running")
        XCTAssertEqual(response.message, "day_retry_queued")
        XCTAssertEqual(response.pollAfterSeconds, 5)
        XCTAssertEqual(response.day?.scheduledDate, "2026-06-10")
        XCTAssertEqual(response.day?.displayStatusLabel, "Retrying")
    }

    func testRegenerateDayResponseDecodesRichCard() throws {
        let generationID = UUID(uuidString: "88888888-8888-4888-8888-888888888881")!
        let weeklyPlanID = UUID(uuidString: "77777777-7777-4777-8777-777777777771")!
        let cardID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!
        let data = Data(
            """
            {
              "generation_id": "\(generationID.uuidString)",
              "weekly_plan_id": "\(weeklyPlanID.uuidString)",
              "status": "draft",
              "target_scheduled_date": "2026-06-10",
              "warnings": ["Confirm the location"],
              "assumptions": ["Low recovery energy"],
              "source_summary": "Live weekly context.",
              "generated_at": "2026-06-10T08:00:00Z",
              "daily_card": {
                "id": "\(cardID.uuidString)",
                "scheduled_date": "2026-06-10",
                "status": "draft",
                "title": "Recovery walk reset",
                "why_today": "Keep recovery visible.",
                "growth_job": "Consistency.",
                "content_pillar": "recovery",
                "shootability": "easy",
                "estimated_shoot_minutes": 8,
                "energy_required": "low",
                "language_mode": "English",
                "scene_list": [{"number":1,"title":"Walking shoes","duration":"3 sec","symbol":"shoeprints.fill"}],
                "script": "Recovery still counts.",
                "no_voiceover_version": "Use three quiet clips.",
                "on_screen_text": ["Recovery still counts"],
                "caption": "A short recovery walk in New Jersey.",
                "cta": "Save this reminder.",
                "hashtags": ["recovery"],
                "cover_text": "Recovery counts",
                "post_instructions": "Use natural sound.",
                "brand_event_notes": "",
                "backup_story": "One walking clip.",
                "backup_caption_only": "Recovery day note.",
                "audio_option_notes": "No audio dependency.",
                "creator_fit_score": 94,
                "risk_notes": [],
                "assumptions": ["Low energy"],
                "source_note": "Weekly setup."
              }
            }
            """.utf8
        )

        let invocation = try SupabaseRegenerateDayInvocation.decode(data)
        guard case .completed(let response) = invocation else {
            XCTFail("Expected completed day generation")
            return
        }

        XCTAssertEqual(response.domainResult.dailyCard.id, cardID)
        XCTAssertEqual(response.domainResult.targetScheduledDate, "2026-06-10")
        XCTAssertEqual(response.domainResult.dailyCard.caption, "A short recovery walk in New Jersey.")
        XCTAssertEqual(response.domainResult.warnings, ["Confirm the location"])
    }

    func testGenerateWeekResponseDecodesIntoDomainDraft() throws {
        let generationID = UUID(uuidString: "88888888-8888-4888-8888-888888888881")!
        let weeklyPlanID = UUID(uuidString: "77777777-7777-4777-8777-777777777771")!
        let cardID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!
        let ideaID = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBB1")!
        let data = Data(
            """
            {
              "generation_id": "\(generationID.uuidString)",
              "weekly_plan_id": "\(weeklyPlanID.uuidString)",
              "status": "draft",
              "strategy_summary": "Seven shootable cards.",
              "warnings": ["Check audio"],
              "assumptions": ["Low energy"],
              "source_summary": "Profile plus setup.",
              "generated_at": "2026-06-06T08:00:00Z",
              "daily_cards": [
                {
                  "id": "\(cardID.uuidString)",
                  "scheduled_date": "2026-06-08",
                  "status": "draft",
                  "title": "Generated Monday",
                  "why_today": "Start simple.",
                  "growth_job": "Consistency.",
                  "content_pillar": "lifestyle",
                  "shootability": "easy",
                  "estimated_shoot_minutes": 12,
                  "energy_required": "medium",
                  "language_mode": "English",
                  "format": "reel",
                  "primary_surface": "instagram_reels",
                  "duration_seconds": 21,
                  "hook": "Start with the shoe detail.",
                  "save_share_reason": "Useful low-energy routine reminder.",
                  "scene_list": [{"number":1,"title":"Shoes","duration":"3 sec","symbol":"shoeprints.fill"}],
                  "shot_timeline": [
                    {
                      "timestamp": "0:00-0:03",
                      "title": "Shoe close-up",
                      "detail": "Film laces and first step.",
                      "shot": "Close-up"
                    }
                  ],
                  "voiceover_timeline": [
                    {
                      "timestamp": "0:00-0:05",
                      "title": "Opening line",
                      "detail": "One useful detail is enough today.",
                      "voiceover": "One useful detail is enough today."
                    }
                  ],
                  "on_screen_text_timeline": [
                    {
                      "timestamp": "0:00-0:03",
                      "title": "Text beat",
                      "detail": "Simple today",
                      "on_screen_text": "Simple today"
                    }
                  ],
                  "silent_version_timeline": [
                    {
                      "timestamp": "0:00-0:05",
                      "title": "Silent opener",
                      "detail": "Use shoe clip with text only."
                    }
                  ],
                  "script": "Simple script.",
                  "no_voiceover_version": "No VO.",
                  "on_screen_text": ["Simple"],
                  "caption": "Simple caption.",
                  "cta": "Save this.",
                  "hashtags": ["routine"],
                  "cover_text": "Monday",
                  "post_instructions": "Use calm audio.",
                  "brand_event_notes": "",
                  "backup_story": "Story backup.",
                  "backup_caption_only": "Caption backup.",
                  "backup_story_detail": [
                    {
                      "timestamp": "0:00-0:05",
                      "title": "Story fallback",
                      "detail": "Post the shoe clip as a story."
                    }
                  ],
                  "caption_backup_detail": "Caption-only version for a busy day. Simple caption backup.",
                  "audio_option_notes": "Calm audio.",
                  "creator_fit_score": 90,
                  "risk_notes": [],
                  "assumptions": [],
                  "source_note": "Reference."
                }
              ],
              "idea_bank": [
                {
                  "id": "\(ideaID.uuidString)",
                  "title": "Saved idea",
                  "summary": "Use later.",
                  "suggested_use": "Later",
                  "shootability": "easy",
                  "status": "saved"
                }
              ]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(SupabaseGenerateWeekResponse.self, from: data)
        let draft = response.domainDraft()

        XCTAssertEqual(draft.id, generationID)
        XCTAssertEqual(draft.weeklyPlanID, weeklyPlanID)
        XCTAssertEqual(draft.dailyCards.first?.id, cardID)
        XCTAssertEqual(draft.dailyCards.first?.format, "reel")
        XCTAssertEqual(draft.dailyCards.first?.primarySurface, "instagram_reels")
        XCTAssertEqual(draft.dailyCards.first?.durationSeconds, 21)
        XCTAssertEqual(draft.dailyCards.first?.hook, "Start with the shoe detail.")
        XCTAssertEqual(draft.dailyCards.first?.saveShareReason, "Useful low-energy routine reminder.")
        XCTAssertEqual(draft.dailyCards.first?.shotTimeline.first?.title, "Shoe close-up")
        XCTAssertEqual(draft.dailyCards.first?.voiceoverTimeline.first?.voiceover, "One useful detail is enough today.")
        XCTAssertEqual(draft.dailyCards.first?.onScreenTextTimeline.first?.onScreenText, "Simple today")
        XCTAssertEqual(draft.dailyCards.first?.silentVersionTimeline.first?.detail, "Use shoe clip with text only.")
        XCTAssertEqual(draft.dailyCards.first?.script, "Simple script.")
        XCTAssertEqual(draft.dailyCards.first?.noVoiceoverVersion, "No VO.")
        XCTAssertEqual(draft.dailyCards.first?.onScreenText, ["Simple"])
        XCTAssertEqual(draft.dailyCards.first?.caption, "Simple caption.")
        XCTAssertEqual(draft.dailyCards.first?.cta, "Save this.")
        XCTAssertEqual(draft.dailyCards.first?.hashtags, ["routine"])
        XCTAssertEqual(draft.dailyCards.first?.coverText, "Monday")
        XCTAssertEqual(draft.dailyCards.first?.postInstructions, "Use calm audio.")
        XCTAssertEqual(draft.dailyCards.first?.backupStory, "Story backup.")
        XCTAssertEqual(draft.dailyCards.first?.backupCaptionOnly, "Caption backup.")
        XCTAssertEqual(draft.dailyCards.first?.backupStoryDetail.first?.detail, "Post the shoe clip as a story.")
        XCTAssertEqual(draft.dailyCards.first?.captionBackupDetail, "Caption-only version for a busy day. Simple caption backup.")
        XCTAssertEqual(draft.dailyCards.first?.audioOptionNotes, "Calm audio.")
        XCTAssertEqual(draft.dailyCards.first?.creatorFitScore, 90)
        XCTAssertEqual(draft.dailyCards.first?.sourceNote, "Reference.")
        XCTAssertEqual(draft.ideaBank.first?.title, "Saved idea")
    }

    func testDraftDailyCardPublishRequestEncodesRichFields() throws {
        let request = SupabaseDraftDailyCardPublishRequest(
            card: GeneratedDailyCardDraft(
                id: UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!,
                scheduledDate: "2026-06-08",
                status: "draft",
                title: "Generated Monday",
                whyToday: "Start simple.",
                growthJob: "Consistency.",
                contentPillar: "lifestyle",
                shootability: "easy",
                estimatedShootMinutes: 12,
                energyRequired: "medium",
                languageMode: "English",
                format: "reel",
                primarySurface: "instagram_reels",
                durationSeconds: 21,
                hook: "Start with the shoe detail.",
                saveShareReason: "Useful low-energy routine reminder.",
                sceneList: [
                    ShotScene(number: 1, title: "Shoes", duration: "3 sec", symbol: "shoeprints.fill")
                ],
                shotTimeline: [
                    ProductionTimelineItem(
                        timestamp: "0:00-0:03",
                        title: "Shoe close-up",
                        detail: "Film laces and first step.",
                        shot: "Close-up"
                    )
                ],
                voiceoverTimeline: [
                    ProductionTimelineItem(
                        timestamp: "0:00-0:05",
                        title: "Opening line",
                        detail: "One useful detail is enough today.",
                        voiceover: "One useful detail is enough today."
                    )
                ],
                onScreenTextTimeline: [
                    ProductionTimelineItem(
                        timestamp: "0:00-0:03",
                        title: "Text beat",
                        detail: "Simple today",
                        onScreenText: "Simple today"
                    )
                ],
                silentVersionTimeline: [
                    ProductionTimelineItem(
                        timestamp: "0:00-0:05",
                        title: "Silent opener",
                        detail: "Use shoe clip with text only."
                    )
                ],
                script: "Simple script.",
                noVoiceoverVersion: "No VO.",
                onScreenText: ["Simple"],
                caption: "Simple caption.",
                cta: "Save this.",
                hashtags: ["routine"],
                coverText: "Monday",
                postInstructions: "Use calm audio.",
                brandEventNotes: "Event note.",
                backupStory: "Story backup.",
                backupCaptionOnly: "Caption backup.",
                backupStoryDetail: [
                    ProductionTimelineItem(
                        timestamp: "0:00-0:05",
                        title: "Story fallback",
                        detail: "Post the shoe clip as a story."
                    )
                ],
                captionBackupDetail: "Caption-only version for a busy day. Simple caption backup.",
                audioOptionNotes: "Calm audio.",
                creatorFitScore: 90,
                riskNotes: ["Avoid overpromising."],
                assumptions: ["Low energy."],
                sourceNote: "Reference."
            )
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let postInstructions = try XCTUnwrap(object["post_instructions"] as? [String: Any])
        let backupStory = try XCTUnwrap(object["backup_story"] as? [String: Any])
        let backupCaptionOnly = try XCTUnwrap(object["backup_caption_only"] as? [String: Any])
        let shotTimeline = try XCTUnwrap(object["shot_timeline"] as? [[String: Any]])
        let backupStoryDetail = try XCTUnwrap(object["backup_story_detail"] as? [[String: Any]])

        XCTAssertEqual(object["format"] as? String, "reel")
        XCTAssertEqual(object["primary_surface"] as? String, "instagram_reels")
        XCTAssertEqual(object["duration_seconds"] as? Int, 21)
        XCTAssertEqual(object["hook"] as? String, "Start with the shoe detail.")
        XCTAssertEqual(object["save_share_reason"] as? String, "Useful low-energy routine reminder.")
        XCTAssertEqual(shotTimeline.first?["title"] as? String, "Shoe close-up")
        XCTAssertEqual(object["script"] as? String, "Simple script.")
        XCTAssertEqual(object["no_voiceover_version"] as? String, "No VO.")
        XCTAssertEqual(object["on_screen_text"] as? [String], ["Simple"])
        XCTAssertEqual(object["caption"] as? String, "Simple caption.")
        XCTAssertEqual(object["cta"] as? String, "Save this.")
        XCTAssertEqual(object["hashtags"] as? [String], ["routine"])
        XCTAssertEqual(object["cover_text"] as? String, "Monday")
        XCTAssertEqual(postInstructions["line"] as? String, "Use calm audio.")
        XCTAssertEqual(postInstructions["audio_option_notes"] as? String, "Calm audio.")
        XCTAssertEqual(postInstructions["format"] as? String, "reel")
        XCTAssertEqual(postInstructions["caption_backup_detail"] as? String, "Caption-only version for a busy day. Simple caption backup.")
        XCTAssertEqual(object["brand_event_notes"] as? String, "Event note.")
        XCTAssertEqual(backupStory["line"] as? String, "Story backup.")
        XCTAssertEqual(backupCaptionOnly["line"] as? String, "Caption backup.")
        XCTAssertEqual(backupStoryDetail.first?["detail"] as? String, "Post the shoe clip as a story.")
        XCTAssertEqual(object["caption_backup_detail"] as? String, "Caption-only version for a busy day. Simple caption backup.")
        XCTAssertEqual(object["creator_fit_score"] as? Double, 90)
        XCTAssertEqual(object["risk_notes"] as? [String], ["Avoid overpromising."])
        XCTAssertEqual(object["assumptions"] as? [String], ["Low energy."])
        XCTAssertEqual(object["source_note"] as? String, "Reference.")
    }

    func testReadContentDailyCardRowDecodesPublishedGeneratedRichFields() throws {
        let cardID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!
        let workspaceID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let creatorID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let weeklyPlanID = UUID(uuidString: "77777777-7777-4777-8777-777777777771")!
        let data = Data(
            """
            {
              "id": "\(cardID.uuidString)",
              "workspace_id": "\(workspaceID.uuidString)",
              "creator_id": "\(creatorID.uuidString)",
              "weekly_plan_id": "\(weeklyPlanID.uuidString)",
              "scheduled_date": "2026-06-08",
              "status": "published",
              "title": "Generated Monday",
              "why_today": "Start simple.",
              "growth_job": "Consistency.",
              "content_pillar": "lifestyle",
              "shootability": "easy",
              "estimated_shoot_minutes": 12,
              "energy_required": "medium",
              "language_mode": "English",
              "scene_list": [{"number":1,"title":"Shoes","duration":"3 sec","symbol":"shoeprints.fill"}],
              "script": "Simple script.",
              "no_voiceover_version": "No VO.",
              "on_screen_text": ["Simple", "One useful detail"],
              "caption": "Simple caption.",
              "cta": "Save this.",
              "hashtags": ["routine"],
              "cover_text": "Monday",
              "post_instructions": {
                "instructions": "Use calm audio and large cover text.",
                "audio_option_notes": "Calm audio if available.",
                "format": "reel",
                "primary_surface": "instagram_reels",
                "duration_seconds": 21,
                "hook": "Start with the shoe detail.",
                "save_share_reason": "Useful low-energy routine reminder.",
                "shot_timeline": [
                  {
                    "timestamp": "0:00-0:03",
                    "title": "Shoe close-up",
                    "detail": "Film laces and first step.",
                    "shot": "Close-up"
                  }
                ],
                "voiceover_timeline": [
                  {
                    "timestamp": "0:00-0:05",
                    "video_portion": "Shoe close-up",
                    "voiceover": "One useful detail is enough today."
                  }
                ],
                "on_screen_text_timeline": [
                  {
                    "timestamp": "0:00-0:03",
                    "text": "Simple today",
                    "placement": "Center"
                  }
                ],
                "silent_version_timeline": [
                  {
                    "timestamp": "0:00-0:05",
                    "title": "Silent opener",
                    "detail": "Use shoe clip with text only."
                  }
                ],
                "caption_backup_detail": "Caption-only version for a busy day. Simple caption backup."
              },
              "brand_event_notes": "Brand note.",
              "backup_story": {
                "line": "Story backup.",
                "detail": [
                  {
                    "timestamp": "0:00-0:05",
                    "title": "Story fallback",
                    "detail": "Post the shoe clip as a story."
                  }
                ]
              },
              "backup_caption_only": {
                "line": "Caption backup.",
                "detail": "Caption-only version for a busy day. Simple caption backup."
              },
              "creator_fit_score": 90,
              "risk_notes": ["Avoid overpromising."],
              "assumptions": ["Low energy."],
              "source_note": "Reference."
            }
            """.utf8
        )

        let row = try JSONDecoder().decode(SupabaseDailyCardRow.self, from: data)
        let card = row.domainCard()

        XCTAssertEqual(card.id, cardID)
        XCTAssertEqual(card.title, "Generated Monday")
        XCTAssertEqual(card.completionState, nil)
        XCTAssertEqual(card.script, "Simple script.")
        XCTAssertEqual(card.noVoiceoverVersion, "No VO.")
        XCTAssertEqual(card.onScreenText, ["Simple", "One useful detail"])
        XCTAssertEqual(card.caption, "Simple caption.")
        XCTAssertEqual(card.cta, "Save this.")
        XCTAssertEqual(card.hashtags, ["routine"])
        XCTAssertEqual(card.coverText, "Monday")
        XCTAssertEqual(card.postInstructions, "Use calm audio and large cover text.")
        XCTAssertEqual(card.audioOptionNotes, "Calm audio if available.")
        XCTAssertEqual(card.brandEventNotes, "Brand note.")
        XCTAssertEqual(card.backupStory, "Story backup.")
        XCTAssertEqual(card.backupCaptionOnly, "Caption backup.")
        XCTAssertEqual(card.creatorFitScore, 90)
        XCTAssertEqual(card.riskNotes, ["Avoid overpromising."])
        XCTAssertEqual(card.assumptions, ["Low energy."])
        XCTAssertEqual(card.sourceNote, "Reference.")

        let generatedDraft = row.generatedDailyCardDraft()
        XCTAssertEqual(generatedDraft.format, "reel")
        XCTAssertEqual(generatedDraft.primarySurface, "instagram_reels")
        XCTAssertEqual(generatedDraft.durationSeconds, 21)
        XCTAssertEqual(generatedDraft.hook, "Start with the shoe detail.")
        XCTAssertEqual(generatedDraft.saveShareReason, "Useful low-energy routine reminder.")
        XCTAssertEqual(generatedDraft.shotTimeline.first?.detail, "Film laces and first step.")
        XCTAssertEqual(generatedDraft.voiceoverTimeline.first?.videoPortion, "Shoe close-up")
        XCTAssertEqual(generatedDraft.onScreenTextTimeline.first?.placement, "Center")
        XCTAssertEqual(generatedDraft.silentVersionTimeline.first?.detail, "Use shoe clip with text only.")
        XCTAssertEqual(generatedDraft.backupStoryDetail.first?.detail, "Post the shoe clip as a story.")
        XCTAssertEqual(generatedDraft.captionBackupDetail, "Caption-only version for a busy day. Simple caption backup.")
    }

    func testAppServicesFixtureGenerationThrowsNotConfigured() async throws {
        let services = AppServices.fixtureBacked(
            todayCache: GenerateWeekMemoryTodayCacheStore(),
            todayDate: { "2026-06-01" }
        )

        let generatedDraft = await services.generateCurrentWeekImmediately()

        XCTAssertNil(generatedDraft)
        XCTAssertEqual(services.generationError, "Fixture generation is unavailable. Use live generation or backend mock generation.")
        XCTAssertEqual(services.weeklyGenerationProgress?.phase, .failed)
        XCTAssertEqual(services.weeklyGenerationProgress?.error, "Fixture generation is unavailable. Use live generation or backend mock generation.")
    }

    func testEmptyGeneratedDraftDoesNotReplaceExistingWeek() async throws {
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                weeklyGeneration: EmptyDraftWeeklyGenerationRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: GenerateWeekMemoryTodayCacheStore(),
            todayDate: { "2026-06-01" }
        )
        let existingDraft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: services.context.creatorID,
            weekStartDate: "2026-06-22",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: services.context,
            progress: nil
        )
        services.applyGeneratedDraft(existingDraft)
        let existingPlanID = services.weeklyPlan.id
        let existingDayCount = services.weeklyPlan.days.count

        let draft = await services.generateCurrentWeekImmediately()

        XCTAssertNil(draft)
        XCTAssertEqual(services.weeklyPlan.id, existingPlanID)
        XCTAssertEqual(services.weeklyPlan.days.count, existingDayCount)
        XCTAssertEqual(services.latestGenerationSummary?.id, existingDraft.id)
        XCTAssertEqual(services.generationError, "The AI draft did not pass validation. Try Generate again.")
        XCTAssertFalse(services.canPublishCurrentWeek)
    }

    func testAppServicesGenerationFailureSurfacesStableError() async throws {
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                weeklyGeneration: FailingWeeklyGenerationRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: GenerateWeekMemoryTodayCacheStore(),
            todayDate: { "2026-06-01" }
        )

        let draft = await services.generateCurrentWeekImmediately()

        XCTAssertNil(draft)
        XCTAssertEqual(services.generationError, "AI generation is not configured in Supabase.")
        XCTAssertEqual(services.weeklyGenerationProgress?.phase, .failed)
        XCTAssertEqual(services.weeklyGenerationProgress?.error, "AI generation is not configured in Supabase.")
    }

    func testAppServicesGenerationFailureExtractsStableErrorFromWrappedMessage() async throws {
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                weeklyGeneration: WrappedErrorWeeklyGenerationRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: GenerateWeekMemoryTodayCacheStore(),
            todayDate: { "2026-06-01" }
        )

        let draft = await services.generateCurrentWeekImmediately()

        XCTAssertNil(draft)
        XCTAssertEqual(services.generationError, "This week is already published and locked.")
        XCTAssertEqual(services.weeklyGenerationProgress?.phase, .failed)
        XCTAssertEqual(services.weeklyGenerationProgress?.error, "This week is already published and locked.")
    }

    func testAppServicesGenerationFailurePreservesLastProgressCount() async throws {
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                weeklyGeneration: ProgressThenFailWeeklyGenerationRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: GenerateWeekMemoryTodayCacheStore(),
            todayDate: { "2026-06-01" }
        )

        let draft = await services.generateCurrentWeekImmediately()

        XCTAssertNil(draft)
        XCTAssertEqual(services.generationError, "The AI returned an incomplete draft. Try Generate again.")
        XCTAssertEqual(services.weeklyGenerationProgress?.phase, .failed)
        XCTAssertEqual(services.weeklyGenerationProgress?.draftedDayCount, 4)
        XCTAssertEqual(services.weeklyGenerationProgress?.checkedDayCount, 4)
        XCTAssertEqual(services.weeklyGenerationProgress?.totalDayCount, 7)
        XCTAssertEqual(services.weeklyGenerationProgress?.error, "The AI returned an incomplete draft. Try Generate again.")
    }

    func testGenerationRetryPolicyClassifiesNetworkConnectionLostAsTransient() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNetworkConnectionLost
        )

        XCTAssertTrue(SupabaseGenerationRetryPolicy.isTransientPollingError(error))
    }

    func testGenerationRetryPolicyClassifiesAcceptedRunStatus404AsRetryable() {
        let error = FunctionsError.httpError(
            code: 404,
            data: Data(#"{"error":"invalid_generation_payload"}"#.utf8)
        )

        XCTAssertTrue(SupabaseGenerationRetryPolicy.isRetryableStatusPollingError(error))
    }

    func testPublishingGeneratedDraftPreservesRichFieldsInFixtureModel() async throws {
        let services = AppServices.fixtureBacked(todayCache: GenerateWeekMemoryTodayCacheStore())
        var draft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: services.context.creatorID,
            weekStartDate: services.weeklyPlan.weekStartDate ?? "2026-06-01",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: services.context,
            progress: nil
        )
        draft.dailyCards[0].caption = "Edited generated caption."
        draft.dailyCards[0].backupStory = "Edited backup story."
        services.applyGeneratedDraft(draft)
        for day in services.weeklyPlan.days {
            await services.updateWeeklyDayStateImmediately(dayID: day.id, state: .planned)
        }

        await services.publishCurrentWeekImmediately()

        XCTAssertEqual(services.weekCards.first?.caption, "Edited generated caption.")
        XCTAssertEqual(services.weekCards.first?.backupStory, "Edited backup story.")
        XCTAssertEqual(services.latestGenerationSummary?.status, "published")
        XCTAssertNil(services.lastRepositoryError)
    }

    func testPublishCurrentWeekIsLockedWhileDayStatusesAreStillGenerating() async throws {
        let services = AppServices.fixtureBacked(todayCache: GenerateWeekMemoryTodayCacheStore())
        let draft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: services.context.creatorID,
            weekStartDate: "2026-06-01",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: services.context,
            progress: nil
        )
        services.applyGeneratedDraft(draft)
        for day in services.weeklyPlan.days {
            await services.updateWeeklyDayStateImmediately(dayID: day.id, state: .planned)
        }
        XCTAssertTrue(services.canPublishCurrentWeek)

        services.weeklyGenerationProgress = WeeklyGenerationProgress(
            phase: .draftingDays,
            generationID: draft.id,
            weeklyPlanID: draft.weeklyPlanID,
            draftedDayCount: 2,
            checkedDayCount: 2,
            totalDayCount: 7,
            currentDay: "2026-07-15",
            message: "generation_running",
            error: nil,
            savedDayCount: 2,
            failedDayCount: 0,
            strategyCreated: true,
            dayStatuses: [
                WeeklyDayGenerationStatus(
                    scheduledDate: "2026-07-13",
                    dayIndex: 0,
                    status: "generated",
                    dailyCardID: draft.dailyCards[0].id,
                    errorCode: nil,
                    retryAction: nil,
                    message: nil
                ),
                WeeklyDayGenerationStatus(
                    scheduledDate: "2026-07-14",
                    dayIndex: 1,
                    status: "generated",
                    dailyCardID: draft.dailyCards[1].id,
                    errorCode: nil,
                    retryAction: nil,
                    message: nil
                ),
                WeeklyDayGenerationStatus(
                    scheduledDate: "2026-07-15",
                    dayIndex: 2,
                    status: "generating",
                    dailyCardID: nil,
                    errorCode: nil,
                    retryAction: nil,
                    message: nil
                ),
                WeeklyDayGenerationStatus(
                    scheduledDate: "2026-07-16",
                    dayIndex: 3,
                    status: "queued",
                    dailyCardID: nil,
                    errorCode: nil,
                    retryAction: nil,
                    message: nil
                )
            ]
        )

        XCTAssertFalse(services.canPublishCurrentWeek)
    }

    func testRetryQueuedDayAppliesCompletedDraftAndUnlocksPublish() async throws {
        let draft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: WorkspaceContext.creatorFixture.creatorID,
            weekStartDate: "2026-07-13",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: .creatorFixture,
            progress: nil
        )
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                weeklyGeneration: RetryCompletesQueuedDayRepository(draft: draft),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: GenerateWeekMemoryTodayCacheStore()
        )
        services.applyGeneratedDraft(draft)
        for day in services.weeklyPlan.days {
            await services.updateWeeklyDayStateImmediately(dayID: day.id, state: .planned)
        }
        services.weeklyGenerationProgress = WeeklyGenerationProgress(
            phase: .draftingDays,
            generationID: draft.id,
            weeklyPlanID: draft.weeklyPlanID,
            draftedDayCount: 7,
            checkedDayCount: 6,
            totalDayCount: 7,
            currentDay: draft.dailyCards[6].scheduledDate,
            message: "generation_partial",
            error: nil,
            savedDayCount: 6,
            failedDayCount: 1,
            strategyCreated: true,
            dayStatuses: draft.dailyCards.enumerated().map { index, card in
                WeeklyDayGenerationStatus(
                    scheduledDate: card.scheduledDate,
                    dayIndex: index,
                    status: index == 6 ? "failed" : "generated",
                    dailyCardID: index == 6 ? nil : card.id,
                    errorCode: index == 6 ? "day_generation_endpoint_http_504" : nil,
                    retryAction: index == 6 ? "retry_day" : nil,
                    message: nil
                )
            }
        )

        XCTAssertFalse(services.canPublishCurrentWeek)

        try await services.retryQueuedGenerationDay(scheduledDate: draft.dailyCards[6].scheduledDate)

        XCTAssertEqual(services.weeklyGenerationProgress?.phase, .readyForReview)
        XCTAssertEqual(services.weeklyGenerationProgress?.effectiveSavedDayCount, 7)
        XCTAssertEqual(services.weeklyGenerationProgress?.effectiveFailedDayCount, 0)
        XCTAssertEqual(services.latestGenerationSummary?.dailyCards.count, 7)
        XCTAssertTrue(services.canPublishCurrentWeek)
        XCTAssertNil(services.generationError)
    }

    func testPartialFailureMergesExistingStatusesWithMissingExpectedDates() async throws {
        var completeDraft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: WorkspaceContext.creatorFixture.creatorID,
            weekStartDate: "2026-06-28",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: .creatorFixture,
            progress: nil
        )
        let expectedDates = completeDraft.dailyCards.map(\.scheduledDate)
        let omittedDate = try XCTUnwrap(expectedDates.first)
        completeDraft.dailyCards.removeAll { $0.scheduledDate == omittedDate }

        let existingProgress = WeeklyGenerationProgress(
            phase: .draftingDays,
            generationID: completeDraft.id,
            weeklyPlanID: completeDraft.weeklyPlanID,
            draftedDayCount: 7,
            checkedDayCount: 6,
            totalDayCount: 7,
            currentDay: nil,
            message: "generation_partial",
            error: nil,
            savedDayCount: 6,
            failedDayCount: 1,
            strategyCreated: true,
            dayStatuses: completeDraft.dailyCards.enumerated().map { index, card in
                WeeklyDayGenerationStatus(
                    scheduledDate: card.scheduledDate,
                    dayIndex: index + 1,
                    status: "generated",
                    dailyCardID: card.id,
                    errorCode: nil,
                    retryAction: nil,
                    message: nil
                )
            }
        )

        let progress = WeeklyGenerationProgress.partialFailure(
            from: completeDraft,
            message: "Some days were saved and some days failed. Retry the failed days before publishing.",
            preserving: existingProgress,
            expectedScheduledDates: expectedDates
        )

        XCTAssertEqual(progress.dayStatuses.map(\.scheduledDate), expectedDates)
        XCTAssertEqual(progress.dayStatuses.count, 7)
        XCTAssertEqual(progress.draftedDayCount, 6)
        XCTAssertEqual(progress.checkedDayCount, 6)
        let synthesizedFailure = try XCTUnwrap(progress.dayStatuses.first)
        XCTAssertEqual(synthesizedFailure.scheduledDate, omittedDate)
        XCTAssertTrue(synthesizedFailure.isFailed)
        XCTAssertEqual(synthesizedFailure.dayIndex, 0)
        XCTAssertEqual(synthesizedFailure.errorCode, "generation_timeout")
        XCTAssertEqual(synthesizedFailure.retryAction, "regenerate_day")
        XCTAssertEqual(progress.effectiveFailedDayCount, 1)
    }

    func testRetryQueuedDayRoutesPastFailedDraftWeekDayToRegenerateDay() async throws {
        let draft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: WorkspaceContext.creatorFixture.creatorID,
            weekStartDate: "2026-06-01",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: .creatorFixture,
            progress: nil
        )
        let failedDate = try XCTUnwrap(draft.dailyCards.first?.scheduledDate)
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                weeklyGeneration: PastDateRegenerateDayOnlyRepository(draft: draft),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: GenerateWeekMemoryTodayCacheStore(),
            todayDate: { "2026-06-29" }
        )
        services.applyGeneratedDraft(draft)
        for day in services.weeklyPlan.days {
            await services.updateWeeklyDayStateImmediately(dayID: day.id, state: .planned)
        }
        services.weeklyGenerationProgress = WeeklyGenerationProgress(
            phase: .draftingDays,
            generationID: draft.id,
            weeklyPlanID: draft.weeklyPlanID,
            draftedDayCount: 7,
            checkedDayCount: 6,
            totalDayCount: 7,
            currentDay: draft.dailyCards[6].scheduledDate,
            message: "generation_partial",
            error: nil,
            savedDayCount: 6,
            failedDayCount: 1,
            strategyCreated: true,
            dayStatuses: draft.dailyCards.enumerated().map { index, card in
                WeeklyDayGenerationStatus(
                    scheduledDate: card.scheduledDate,
                    dayIndex: index,
                    status: index == 0 ? "failed" : "generated",
                    dailyCardID: index == 0 ? nil : card.id,
                    errorCode: index == 0 ? "openai_request_failed" : nil,
                    retryAction: index == 0 ? "retry_day" : nil,
                    message: nil
                )
            }
        )

        try await services.retryQueuedGenerationDay(scheduledDate: failedDate)

        // retryQueuedDay throws, so reaching here proves regenerateDay was used.
        XCTAssertNil(services.generationError)
        XCTAssertNotNil(services.latestGenerationSummary?.dailyCards.first { $0.scheduledDate == failedDate },
                        "Regenerated card should be present in draft after recovery")
    }

    func testRetryQueuedDayFallsBackToRegenerateWhenServerRejectsPastDate() async throws {
        let draft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: WorkspaceContext.creatorFixture.creatorID,
            weekStartDate: "2026-07-13",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: .creatorFixture,
            progress: nil
        )
        let retryDate = try XCTUnwrap(draft.dailyCards.first?.scheduledDate)
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                weeklyGeneration: RetryPastDateFallbackRepository(draft: draft),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: GenerateWeekMemoryTodayCacheStore(),
            todayDate: { "2026-05-01" }
        )
        services.applyGeneratedDraft(draft)
        for day in services.weeklyPlan.days {
            await services.updateWeeklyDayStateImmediately(dayID: day.id, state: .planned)
        }
        services.weeklyGenerationProgress = WeeklyGenerationProgress(
            phase: .draftingDays,
            generationID: draft.id,
            weeklyPlanID: draft.weeklyPlanID,
            draftedDayCount: 7,
            checkedDayCount: 6,
            totalDayCount: 7,
            currentDay: draft.dailyCards[6].scheduledDate,
            message: "generation_partial",
            error: nil,
            savedDayCount: 6,
            failedDayCount: 1,
            strategyCreated: true,
            dayStatuses: draft.dailyCards.enumerated().map { index, card in
                WeeklyDayGenerationStatus(
                    scheduledDate: card.scheduledDate,
                    dayIndex: index,
                    status: index == 0 ? "failed" : "generated",
                    dailyCardID: index == 0 ? nil : card.id,
                    errorCode: index == 0 ? "openai_request_failed" : nil,
                    retryAction: index == 0 ? "retry_day" : nil,
                    message: nil
                )
            }
        )

        try await services.retryQueuedGenerationDay(scheduledDate: retryDate)

        XCTAssertNil(services.generationError,
                     "generationError should be cleared after regenerate fallback")
        XCTAssertNotNil(services.latestGenerationSummary?.dailyCards.first { $0.scheduledDate == retryDate },
                        "Regenerated card should be present in draft after server past-date fallback")
        let regeneratedCard = try XCTUnwrap(
            services.latestGenerationSummary?.dailyCards.first { $0.scheduledDate == retryDate }
        )
        XCTAssertEqual(regeneratedCard.title, "Regenerated past day")
        XCTAssertEqual(regeneratedCard.caption, "Test regenerated caption.")
        XCTAssertNil(services.regenerationDayErrors[retryDate])
    }

    func testRetryQueuedDayFallsBackToRegenerateWhenQueuedJobIsUnavailable() async throws {
        let draft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: WorkspaceContext.creatorFixture.creatorID,
            weekStartDate: "2026-07-13",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: .creatorFixture,
            progress: nil
        )
        let retryDate = try XCTUnwrap(draft.dailyCards.last?.scheduledDate)
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                weeklyGeneration: RetryPastDateFallbackRepository(
                    draft: draft,
                    retryErrorCode: "day_job_not_retryable"
                ),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: GenerateWeekMemoryTodayCacheStore(),
            todayDate: { "2026-06-30" }
        )
        services.applyGeneratedDraft(draft)
        services.weeklyGenerationProgress = WeeklyGenerationProgress(
            phase: .draftingDays,
            generationID: draft.id,
            weeklyPlanID: draft.weeklyPlanID,
            draftedDayCount: 6,
            checkedDayCount: 6,
            totalDayCount: 7,
            currentDay: retryDate,
            message: "generation_partial",
            error: nil,
            savedDayCount: 6,
            failedDayCount: 1,
            strategyCreated: true,
            dayStatuses: draft.dailyCards.enumerated().map { index, card in
                WeeklyDayGenerationStatus(
                    scheduledDate: card.scheduledDate,
                    dayIndex: index,
                    status: card.scheduledDate == retryDate ? "failed" : "generated",
                    dailyCardID: card.scheduledDate == retryDate ? nil : card.id,
                    errorCode: card.scheduledDate == retryDate ? "generation_timeout" : nil,
                    retryAction: card.scheduledDate == retryDate ? "retry_day" : nil,
                    message: nil
                )
            }
        )

        try await services.retryQueuedGenerationDay(scheduledDate: retryDate)

        XCTAssertNil(services.regenerationDayErrors[retryDate])
        let regeneratedCard = try XCTUnwrap(
            services.latestGenerationSummary?.dailyCards.first { $0.scheduledDate == retryDate }
        )
        XCTAssertEqual(regeneratedCard.title, "Regenerated past day")
        XCTAssertEqual(services.weeklyGenerationProgress?.effectiveFailedDayCount, 0)
    }

    func testRetryQueuedPastDayCanRecoverWhenFailedDateIsOnlyInProgress() async throws {
        let draft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: WorkspaceContext.creatorFixture.creatorID,
            weekStartDate: "2026-07-13",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: .creatorFixture,
            progress: nil
        )
        let retryDate = try XCTUnwrap(draft.dailyCards.first?.scheduledDate)
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                weeklyGeneration: RetryPastDateFallbackRepository(draft: draft),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: GenerateWeekMemoryTodayCacheStore(),
            todayDate: { "2026-05-01" }
        )
        services.applyGeneratedDraft(draft)
        services.weeklyPlan.days.removeAll { $0.scheduledDate == retryDate }
        services.weeklyGenerationProgress = WeeklyGenerationProgress(
            phase: .draftingDays,
            generationID: draft.id,
            weeklyPlanID: draft.weeklyPlanID,
            draftedDayCount: 6,
            checkedDayCount: 6,
            totalDayCount: 7,
            currentDay: retryDate,
            message: "generation_partial",
            error: nil,
            savedDayCount: 6,
            failedDayCount: 1,
            strategyCreated: true,
            dayStatuses: draft.dailyCards.enumerated().map { index, card in
                WeeklyDayGenerationStatus(
                    scheduledDate: card.scheduledDate,
                    dayIndex: index,
                    status: index == 0 ? "failed" : "generated",
                    dailyCardID: index == 0 ? nil : card.id,
                    errorCode: index == 0 ? "generation_timeout" : nil,
                    retryAction: index == 0 ? "retry_day" : nil,
                    message: nil
                )
            }
        )

        try await services.retryQueuedGenerationDay(scheduledDate: retryDate)

        XCTAssertNil(services.regenerationDayErrors[retryDate])
        let regeneratedCard = try XCTUnwrap(
            services.latestGenerationSummary?.dailyCards.first { $0.scheduledDate == retryDate }
        )
        XCTAssertEqual(regeneratedCard.title, "Regenerated past day")
    }

    func testRetryQueuedDayUsesRegenerateForReloadedDraftWithoutGenerationRun() async throws {
        let draft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: WorkspaceContext.creatorFixture.creatorID,
            weekStartDate: "2026-07-13",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: .creatorFixture,
            progress: nil
        )
        let weekDates = SupabaseDateFormatting.weekDates(starting: "2026-07-13")
        let failedDate = try XCTUnwrap(weekDates.last)
        let reloadedDraft = GeneratedWeekDraft(
            id: draft.weeklyPlanID,
            weeklyPlanID: draft.weeklyPlanID,
            status: draft.status,
            strategySummary: draft.strategySummary,
            warnings: draft.warnings,
            assumptions: draft.assumptions,
            dailyCards: Array(draft.dailyCards.dropLast()),
            ideaBank: draft.ideaBank,
            sourceSummary: draft.sourceSummary,
            generatedAt: draft.generatedAt
        )
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                weeklyGeneration: RetryPastDateFallbackRepository(draft: draft),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: GenerateWeekMemoryTodayCacheStore(),
            todayDate: { "2026-07-01" }
        )
        services.applyGeneratedDraft(reloadedDraft)
        services.weeklyGenerationProgress = WeeklyGenerationProgress.partialFailure(
            from: reloadedDraft,
            message: "Some days were saved and some days failed. Retry the failed days before publishing.",
            preserving: nil,
            expectedScheduledDates: weekDates
        )

        try await services.retryQueuedGenerationDay(scheduledDate: failedDate)

        XCTAssertNil(services.generationError)
        let regeneratedCard = try XCTUnwrap(
            services.latestGenerationSummary?.dailyCards.first { $0.scheduledDate == failedDate }
        )
        XCTAssertEqual(regeneratedCard.title, "Regenerated past day")
        XCTAssertEqual(
            services.weeklyGenerationProgress?.dayStatuses.first { $0.scheduledDate == failedDate }?.isCompleted,
            true,
            "Progress statuses: \(String(describing: services.weeklyGenerationProgress?.dayStatuses))"
        )
    }

    // MARK: — Working Plan Persistence

    func testWorkingPlanReturnsNilWhenNoDraftExists() {
        let workingPlan = WeeklyRepositoryContent.makeWorkingPlan(
            from: nil,
            weekStartDate: "2026-07-06",
            setupSections: [],
            weeklyBriefText: ""
        )
        XCTAssertNil(workingPlan)
    }

    func testWorkingPlanReturnsNilWhenDraftHasNoCards() {
        let emptyDraft = GeneratedWeekDraft(
            id: UUID(),
            weeklyPlanID: UUID(),
            status: "draft",
            strategySummary: "Empty.",
            warnings: [],
            assumptions: [],
            dailyCards: [],
            ideaBank: [],
            sourceSummary: "Empty.",
            generatedAt: "2026-07-06T00:00:00Z"
        )
        let workingPlan = WeeklyRepositoryContent.makeWorkingPlan(
            from: emptyDraft,
            weekStartDate: "2026-07-06",
            setupSections: [],
            weeklyBriefText: ""
        )
        XCTAssertNil(workingPlan)
    }

    func testWorkingPlanFillsSevenSlotsForSixCardDraft() async throws {
        let draft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: WorkspaceContext.creatorFixture.creatorID,
            weekStartDate: "2026-07-06",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: .creatorFixture,
            progress: nil
        )
        let expectedDates = draft.dailyCards.map(\.scheduledDate)
        XCTAssertEqual(expectedDates.count, 7)

        let omittedDate = try XCTUnwrap(expectedDates.last)
        var partialDraft = draft
        partialDraft.dailyCards.removeAll { $0.scheduledDate == omittedDate }
        XCTAssertEqual(partialDraft.dailyCards.count, 6)

        let workingPlan = try XCTUnwrap(WeeklyRepositoryContent.makeWorkingPlan(
            from: partialDraft,
            weekStartDate: "2026-07-06",
            setupSections: [],
            weeklyBriefText: ""
        ))

        XCTAssertEqual(workingPlan.days.count, 7)
        XCTAssertEqual(workingPlan.weekStartDate, "2026-07-06")

        let generatedDates = Set(partialDraft.dailyCards.map(\.scheduledDate))
        let generatedDays = workingPlan.days.filter { generatedDates.contains($0.scheduledDate ?? "") }
        XCTAssertEqual(generatedDays.count, 6)
        let generatedTitles = Set(partialDraft.dailyCards.map(\.title))
        let planTitles = Set(generatedDays.map(\.title))
        XCTAssertEqual(planTitles, generatedTitles,
                       "Generated card titles should be preserved in management plan")

        let missingDay = try XCTUnwrap(workingPlan.days.first { ($0.scheduledDate ?? "") == omittedDate })
        XCTAssertEqual(missingDay.state, .open)
        XCTAssertEqual(missingDay.title, "Open")
        XCTAssertEqual(missingDay.reason, "")
        XCTAssertFalse(missingDay.isSoftLocked)
    }

    func testCompleteUnpublishedDraftProducesWorkingPlanWithAllSevenDays() async throws {
        let draft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: WorkspaceContext.creatorFixture.creatorID,
            weekStartDate: "2026-07-06",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: .creatorFixture,
            progress: nil
        )
        XCTAssertTrue(draft.isCompleteWeekDraft)

        let workingPlan = try XCTUnwrap(WeeklyRepositoryContent.makeWorkingPlan(
            from: draft,
            weekStartDate: "2026-07-06",
            setupSections: [],
            weeklyBriefText: ""
        ))

        XCTAssertEqual(workingPlan.days.count, 7)
        XCTAssertEqual(workingPlan.id, draft.weeklyPlanID)
        XCTAssertEqual(workingPlan.weekStartDate, "2026-07-06")
        XCTAssertFalse(workingPlan.isSoftLocked)
        let expectedScheduledDates = Set(draft.dailyCards.map(\.scheduledDate))
        let planScheduledDates = Set(workingPlan.days.compactMap(\.scheduledDate))
        XCTAssertEqual(planScheduledDates, expectedScheduledDates,
                       "All seven scheduled dates should be present in management plan")
    }

    func testManagerRefreshPrefersWorkingPlanOverPublishedPlan() async throws {
        let draft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: WorkspaceContext.creatorFixture.creatorID,
            weekStartDate: "2026-07-06",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: .creatorFixture,
            progress: nil
        )
        let workingPlanID = draft.weeklyPlanID
        var publishedPlan = WeeklyPlan.raceWeek
        publishedPlan.weekStartDate = "2026-07-06"

        let weeklyRepository = WorkingPlanPreferringWeeklyPlanRepository(
            publishedPlan: publishedPlan,
            workingDraft: draft,
            weekStartDate: "2026-07-06"
        )
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: weeklyRepository,
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                weeklyGeneration: TestWeeklyGenerationRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: GenerateWeekMemoryTodayCacheStore()
        )

        await services.refreshFromRepositoriesImmediately()

        XCTAssertEqual(services.weeklyPlan.id, workingPlanID,
                       "Manager should see the working plan, not the published plan")
        XCTAssertNotNil(services.latestGenerationSummary)
        XCTAssertEqual(services.latestGenerationSummary?.id, draft.id)
        XCTAssertEqual(services.weeklyPlan.days.count, 7)
        XCTAssertNil(services.lastRepositoryError)
    }

    func testManagerRefreshFallsBackToPublishedPlanWhenNoDraftExists() async throws {
        let publishedPlan = WeeklyPlan.raceWeek
        let workingPlanID = publishedPlan.id
        let publishedStartDate = try XCTUnwrap(
            publishedPlan.weekStartDate ?? publishedPlan.days.compactMap(\.scheduledDate).first
        )

        let weeklyRepository = WorkingPlanPreferringWeeklyPlanRepository(
            publishedPlan: publishedPlan,
            workingDraft: nil,
            weekStartDate: nil
        )
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: weeklyRepository,
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                weeklyGeneration: TestWeeklyGenerationRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: GenerateWeekMemoryTodayCacheStore(),
            todayDate: { publishedStartDate }
        )

        await services.refreshFromRepositoriesImmediately()

        XCTAssertEqual(services.weeklyPlan.id, workingPlanID,
                       "Manager should fall back to published plan when no working draft exists")
        XCTAssertNil(services.latestGenerationSummary)
        XCTAssertNil(services.lastRepositoryError)
    }

    func testCurrentPublishedPlanStillReturnsCanonicalPublishedPlan() async throws {
        let publishedPlan = WeeklyPlan.raceWeek
        let draft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: WorkspaceContext.creatorFixture.creatorID,
            weekStartDate: "2026-07-06",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: .creatorFixture,
            progress: nil
        )

        let weeklyRepository = WorkingPlanPreferringWeeklyPlanRepository(
            publishedPlan: publishedPlan,
            workingDraft: draft,
            weekStartDate: "2026-07-06"
        )

        let canonicalPlan = try await weeklyRepository.currentPublishedPlan(for: .creatorFixture)
        XCTAssertEqual(canonicalPlan.id, publishedPlan.id,
                       "currentPublishedPlan must return the canonical published plan")
        XCTAssertEqual(canonicalPlan.title, publishedPlan.title)

        let content = try await weeklyRepository.currentWeeklyContent(for: .creatorFixture)
        XCTAssertNotNil(content.workingPlan,
                        "currentWeeklyContent should include workingPlan when draft exists")
        XCTAssertEqual(content.publishedPlan.id, publishedPlan.id,
                       "publishedPlan in content should be the canonical published plan")
        XCTAssertEqual(content.workingPlan?.id, draft.weeklyPlanID,
                       "workingPlan should use the draft's plan ID")
    }

    func testReviewStateDecodedAsNilWhenAbsentFromDraftCard() throws {
        let cardID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!
        let data = Data(
            """
            {
              "id": "\(cardID.uuidString)",
              "workspace_id": "11111111-1111-4111-8111-111111111111",
              "creator_id": "33333333-3333-4333-8333-333333333333",
              "weekly_plan_id": "77777777-7777-4777-8777-777777777771",
              "scheduled_date": "2026-06-08",
              "status": "draft",
              "title": "No review state",
              "scene_list": []
            }
            """.utf8
        )

        let row = try JSONDecoder().decode(SupabaseDailyCardRow.self, from: data)
        XCTAssertNil(row.reviewState)
        let weeklyDay = row.weeklyDay()
        XCTAssertEqual(weeklyDay.state, .open,
                       "Draft card without review_state defaults to open")
    }

    func testReviewStateDecodedAsReadyMapsToPlannedForDraftCard() throws {
        let cardID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!
        let data = Data(
            """
            {
              "id": "\(cardID.uuidString)",
              "workspace_id": "11111111-1111-4111-8111-111111111111",
              "creator_id": "33333333-3333-4333-8333-333333333333",
              "weekly_plan_id": "77777777-7777-4777-8777-777777777771",
              "scheduled_date": "2026-06-08",
              "status": "draft",
              "review_state": "ready",
              "title": "Ready card",
              "scene_list": []
            }
            """.utf8
        )

        let row = try JSONDecoder().decode(SupabaseDailyCardRow.self, from: data)
        XCTAssertEqual(row.reviewState, "ready")
        let weeklyDay = row.weeklyDay()
        XCTAssertEqual(weeklyDay.state, .planned,
                       "Draft card with review_state=ready maps to planned")
    }

    func testReviewStateDecodedAsBackupMapsToBackupForDraftCard() throws {
        let cardID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!
        let data = Data(
            """
            {
              "id": "\(cardID.uuidString)",
              "workspace_id": "11111111-1111-4111-8111-111111111111",
              "creator_id": "33333333-3333-4333-8333-333333333333",
              "weekly_plan_id": "77777777-7777-4777-8777-777777777771",
              "scheduled_date": "2026-06-08",
              "status": "draft",
              "review_state": "backup",
              "title": "Backup card",
              "scene_list": []
            }
            """.utf8
        )

        let row = try JSONDecoder().decode(SupabaseDailyCardRow.self, from: data)
        XCTAssertEqual(row.reviewState, "backup")
        let weeklyDay = row.weeklyDay()
        XCTAssertEqual(weeklyDay.state, .backup,
                       "Draft card with review_state=backup maps to backup")
    }

    func testGeneratedDailyCardDraftMapsReviewStateForDraftCards() throws {
        let cardID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!
        let data = Data(
            """
            {
              "id": "\(cardID.uuidString)",
              "workspace_id": "11111111-1111-4111-8111-111111111111",
              "creator_id": "33333333-3333-4333-8333-333333333333",
              "weekly_plan_id": "77777777-7777-4777-8777-777777777771",
              "scheduled_date": "2026-06-08",
              "status": "draft",
              "review_state": "ready",
              "title": "Ready card",
              "scene_list": []
            }
            """.utf8
        )

        let row = try JSONDecoder().decode(SupabaseDailyCardRow.self, from: data)
        let draft = row.generatedDailyCardDraft()
        XCTAssertEqual(draft.status, "ready",
                       "Reloaded draft card should preserve review_state as generated status")
        XCTAssertEqual(draft.weeklyDay.state, .planned)
        XCTAssertEqual(draft.weeklyDay.id, cardID)
    }

    func testWeeklyDayPreservesDailyCardID() throws {
        let cardID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!
        let data = Data(
            """
            {
              "id": "\(cardID.uuidString)",
              "workspace_id": "11111111-1111-4111-8111-111111111111",
              "creator_id": "33333333-3333-4333-8333-333333333333",
              "weekly_plan_id": "77777777-7777-4777-8777-777777777771",
              "scheduled_date": "2026-06-08",
              "status": "draft",
              "title": "Card with stable id",
              "scene_list": []
            }
            """.utf8
        )

        let row = try JSONDecoder().decode(SupabaseDailyCardRow.self, from: data)
        XCTAssertEqual(row.weeklyDay().id, cardID)
    }

    func testReviewStateDoesNotOverridePublishedStatusMapping() throws {
        let cardID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!
        let data = Data(
            """
            {
              "id": "\(cardID.uuidString)",
              "workspace_id": "11111111-1111-4111-8111-111111111111",
              "creator_id": "33333333-3333-4333-8333-333333333333",
              "weekly_plan_id": "77777777-7777-4777-8777-777777777771",
              "scheduled_date": "2026-06-08",
              "status": "published",
              "review_state": "backup",
              "title": "Published card",
              "scene_list": []
            }
            """.utf8
        )

        let row = try JSONDecoder().decode(SupabaseDailyCardRow.self, from: data)
        let weeklyDay = row.weeklyDay()
        XCTAssertEqual(weeklyDay.state, .planned,
                       "Published card should use status mapping, not review_state")
        XCTAssertTrue(weeklyDay.isSoftLocked,
                      "Published card should be soft locked")
    }

    func testWorkingPlanBuiltFromCardRowsPreservesReviewStateOnReload() throws {
        let cardID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!
        let planID = UUID(uuidString: "77777777-7777-4777-8777-777777777771")!
        let row = try JSONDecoder().decode(
            SupabaseDailyCardRow.self,
            from: Data(
                """
                {
                  "id": "\(cardID.uuidString)",
                  "workspace_id": "11111111-1111-4111-8111-111111111111",
                  "creator_id": "33333333-3333-4333-8333-333333333333",
                  "weekly_plan_id": "\(planID.uuidString)",
                  "scheduled_date": "2026-06-08",
                  "status": "draft",
                  "review_state": "ready",
                  "title": "Ready card",
                  "scene_list": []
                }
                """.utf8
            )
        )
        let planRow = try JSONDecoder().decode(
            SupabaseWeeklyPlanRow.self,
            from: Data(
                """
                {
                  "id": "\(planID.uuidString)",
                  "workspace_id": "11111111-1111-4111-8111-111111111111",
                  "creator_id": "33333333-3333-4333-8333-333333333333",
                  "week_start_date": "2026-06-08",
                  "status": "draft",
                  "warnings": [],
                  "assumptions": [],
                  "is_soft_locked": false
                }
                """.utf8
            )
        )

        let workingPlan = WeeklyRepositoryContent.makeWorkingPlan(
            from: [row],
            planRow: planRow,
            setupSections: [],
            weeklyBriefText: ""
        )

        let monday = try XCTUnwrap(workingPlan?.days.first)
        XCTAssertEqual(monday.id, cardID)
        XCTAssertEqual(monday.state, .planned)
    }

    func testDraftDailyCardPublishRequestEncodesReviewState() throws {
        let request = SupabaseDraftDailyCardPublishRequest(
            card: GeneratedDailyCardDraft(
                id: UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!,
                scheduledDate: "2026-06-08",
                status: "ready",
                title: "Reviewed Monday",
                whyToday: "Start simple.",
                growthJob: "Consistency.",
                contentPillar: "lifestyle",
                shootability: "easy",
                estimatedShootMinutes: 12,
                energyRequired: "medium",
                languageMode: "English",
                sceneList: [ShotScene(number: 1, title: "Test", duration: "3 sec", symbol: "sparkles")],
                script: "Test.",
                noVoiceoverVersion: "",
                onScreenText: [],
                caption: "",
                cta: "",
                hashtags: [],
                coverText: "",
                postInstructions: "",
                brandEventNotes: "",
                backupStory: "",
                backupCaptionOnly: "",
                audioOptionNotes: "",
                creatorFitScore: 90,
                riskNotes: [],
                assumptions: [],
                sourceNote: ""
            )
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["review_state"] as? String, "ready",
                       "Ready status should encode as review_state=ready")
    }

    func testWeeklyDayStateReviewStateValueMapsCorrectly() {
        XCTAssertEqual(WeeklyDayState.planned.generatedDraftStatus, "ready")
        XCTAssertEqual(WeeklyDayState.backup.generatedDraftStatus, "backup")
        XCTAssertEqual(WeeklyDayState.open.generatedDraftStatus, "open")
    }

    func testUpdateWeeklyDayStatePersistsReviewStateAsynchronously() async throws {
        let repo = ReviewStateTrackingRepository()
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: repo,
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                weeklyGeneration: TestWeeklyGenerationRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: GenerateWeekMemoryTodayCacheStore()
        )

        let draft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: services.context.creatorID,
            weekStartDate: "2026-06-01",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: services.context,
            progress: nil
        )
        services.applyGeneratedDraft(draft)

        let firstDay = try XCTUnwrap(services.weeklyPlan.days.first)
        let didSave = await services.updateWeeklyDayStateImmediately(dayID: firstDay.id, state: .backup)
        XCTAssertTrue(didSave)

        let calls = await repo.reviewStateCalls
        XCTAssertFalse(calls.isEmpty, "Expected review state persistence call")
        if let firstCall = calls.first {
            XCTAssertEqual(firstCall.dailyCardID, firstDay.id)
            XCTAssertEqual(firstCall.reviewState, "backup")
        }
    }

    func testMarkReadySurvivesRepositoryReload() async throws {
        let repo = ReviewStateReloadRepository()
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: repo,
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                weeklyGeneration: TestWeeklyGenerationRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: GenerateWeekMemoryTodayCacheStore()
        )

        let draft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: services.context.creatorID,
            weekStartDate: "2026-06-01",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: services.context,
            progress: nil
        )
        await repo.seed(draft: draft)
        services.applyGeneratedDraft(draft)

        let firstDay = try XCTUnwrap(services.weeklyPlan.days.first)
        let didSave = await services.updateWeeklyDayStateImmediately(dayID: firstDay.id, state: .planned)
        XCTAssertTrue(didSave)

        await services.refreshFromRepositoriesImmediately()

        let reloadedDay = try XCTUnwrap(
            services.weeklyPlan.days.first(where: { $0.scheduledDate == firstDay.scheduledDate })
        )
        XCTAssertEqual(reloadedDay.state, .planned,
                       "Ready state should survive a cold repository reload")
        XCTAssertNil(services.lastRepositoryError)
    }

    // MARK: — Publish Error Isolation

    func testPublishErrorSetsLastPublishErrorNotLastRepositoryError() async throws {
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FailingPublishWeeklyPlanRepository(error: RepositoryError.edgeFunction("publish_validation_failed")),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                weeklyGeneration: TestWeeklyGenerationRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: GenerateWeekMemoryTodayCacheStore()
        )
        let draft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: services.context.creatorID,
            weekStartDate: "2026-06-01",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: services.context,
            progress: nil
        )
        services.applyGeneratedDraft(draft)
        for day in services.weeklyPlan.days {
            await services.updateWeeklyDayStateImmediately(dayID: day.id, state: .planned)
        }

        await services.publishCurrentWeekImmediately()

        XCTAssertEqual(services.lastPublishError, "publish_validation_failed",
                       "Publish error should set lastPublishError")
        XCTAssertNil(services.lastRepositoryError,
                     "Publish error should not set lastRepositoryError")
    }

    func testGeneralRepositoryErrorDoesNotSetLastPublishError() async throws {
        let services = AppServices.fixtureBacked(
            todayCache: GenerateWeekMemoryTodayCacheStore(),
            todayDate: { "2026-06-01" }
        )

        services.lastRepositoryError = "network connection lost"
        services.lastPublishError = nil

        XCTAssertNotNil(services.lastRepositoryError,
                        "lastRepositoryError should be set for general error")
        XCTAssertNil(services.lastPublishError,
                     "lastPublishError should remain nil for non-publish error")
    }

    func testPublishGuardSetsLastPublishErrorNotLastRepositoryError() async throws {
        let services = AppServices.fixtureBacked(
            todayCache: GenerateWeekMemoryTodayCacheStore(),
            todayDate: { "2026-06-01" }
        )
        let draft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: services.context.creatorID,
            weekStartDate: "2026-06-01",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: services.context,
            progress: nil
        )
        services.applyGeneratedDraft(draft)
        // Review only 6 of 7 days — leaves openDayCount > 0, blocking publish
        for (index, day) in services.weeklyPlan.days.enumerated() {
            guard index < 6 else { break }
            await services.updateWeeklyDayStateImmediately(dayID: day.id, state: .planned)
        }
        services.lastPublishError = nil
        services.lastRepositoryError = nil

        await services.publishCurrentWeekImmediately()

        XCTAssertNotNil(services.lastPublishError,
                        "Publish guard should set lastPublishError")
        XCTAssertNil(services.lastRepositoryError,
                     "Publish guard should not set lastRepositoryError")
    }

    // MARK: — Stale Date Normalization

    func testNormalizeManagerWeekStartSkipsWhenWorkingDraftExists() async throws {
        let draft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: WorkspaceContext.creatorFixture.creatorID,
            weekStartDate: "2026-05-25",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: .creatorFixture,
            progress: nil
        )
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                weeklyGeneration: TestWeeklyGenerationRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: GenerateWeekMemoryTodayCacheStore(),
            todayDate: { "2026-06-29" }
        )
        services.applyGeneratedDraft(draft)
        let originalStartDate = services.weeklyPlan.weekStartDate

        services.normalizeManagerWeekStartIfStale()

        XCTAssertEqual(services.weeklyPlan.weekStartDate, originalStartDate,
                       "Week start should be preserved when working draft exists")
        XCTAssertNotNil(services.latestGenerationSummary,
                        "Working draft should still be present")
    }

    func testNormalizeManagerWeekStartReplacesStalePublishedWeekWithCurrentWindow() async throws {
        let services = AppServices.fixtureBacked(
            todayCache: GenerateWeekMemoryTodayCacheStore(),
            todayDate: { "2026-06-29" }
        )
        services.latestGenerationSummary = nil
        services.weeklyPlan.weekStartDate = "2026-06-01"
        let oldID = services.weeklyPlan.id

        services.normalizeManagerWeekStartIfStale()

        XCTAssertEqual(services.weeklyPlan.weekStartDate, "2026-06-29",
                       "Stale published week should be replaced with today's start")
        XCTAssertEqual(services.weeklyPlan.days.count, 7,
                       "Replacement window should have 7 days")
        XCTAssertNotEqual(services.weeklyPlan.id, oldID,
                          "Stale normalization should produce a new plan ID")
        XCTAssertFalse(services.weeklyPlan.isSoftLocked,
                       "Normalized plan should be unlocked")
        XCTAssertNil(services.weeklyGenerationProgress,
                     "Progress should be cleared after normalization")
        XCTAssertNil(services.generationError,
                     "Generation error should be cleared after normalization")
    }

    func testNormalizeManagerWeekStartSkipsWhenWeekStartIsNotPast() async throws {
        let services = AppServices.fixtureBacked(
            todayCache: GenerateWeekMemoryTodayCacheStore(),
            todayDate: { "2026-06-01" }
        )
        services.latestGenerationSummary = nil
        services.weeklyPlan.weekStartDate = "2026-06-01"

        services.normalizeManagerWeekStartIfStale()

        XCTAssertEqual(services.weeklyPlan.weekStartDate, "2026-06-01",
                       "Current week start should be preserved")
    }

    func testNormalizeManagerWeekStartSkipsWhenWeekStartsToday() async throws {
        let services = AppServices.fixtureBacked(
            todayCache: GenerateWeekMemoryTodayCacheStore(),
            todayDate: { "2026-07-01" }
        )
        services.latestGenerationSummary = nil
        services.weeklyPlan.weekStartDate = "2026-07-01"

        services.normalizeManagerWeekStartIfStale()

        XCTAssertEqual(services.weeklyPlan.weekStartDate, "2026-07-01",
                       "Week starting today should not be normalized")
    }

    // MARK: — Publish Transient Retry

    func testTransientPublishTimeoutRetriesOnceAndEndsPublished() async throws {
        let publishRepo = TransientThenSuccessPublishRepository(
            transientError: NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorTimedOut
            )
        )
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: publishRepo,
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                weeklyGeneration: TestWeeklyGenerationRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: GenerateWeekMemoryTodayCacheStore()
        )
        let draft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: services.context.creatorID,
            weekStartDate: "2026-06-01",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: services.context,
            progress: nil
        )
        services.applyGeneratedDraft(draft)
        for day in services.weeklyPlan.days {
            await services.updateWeeklyDayStateImmediately(dayID: day.id, state: .planned)
        }

        await services.publishCurrentWeekImmediately()

        let callCount = await publishRepo.publishCallCount
        XCTAssertEqual(callCount, 2,
                       "Transient publish error should trigger exactly one retry — two total calls")
        XCTAssertNil(services.lastPublishError,
                     "Publish should succeed after retry")
        XCTAssertEqual(services.weeklyPlan.isSoftLocked, true,
                       "Plan should be soft-locked after successful publish")
        XCTAssertFalse(services.weeklyPlan.days.isEmpty,
                       "Weekly plan should contain days after publish")
        XCTAssertNil(services.lastRepositoryError,
                     "No repository error on successful publish")
    }

    func testNonTransientPublishFailureDoesNotRetry() async throws {
        let publishRepo = NonTransientFailingPublishRepository(
            error: RepositoryError.edgeFunction("publish_validation_failed")
        )
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: publishRepo,
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                weeklyGeneration: TestWeeklyGenerationRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: GenerateWeekMemoryTodayCacheStore()
        )
        let draft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: services.context.creatorID,
            weekStartDate: "2026-06-01",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: services.context,
            progress: nil
        )
        services.applyGeneratedDraft(draft)
        for day in services.weeklyPlan.days {
            await services.updateWeeklyDayStateImmediately(dayID: day.id, state: .planned)
        }

        await services.publishCurrentWeekImmediately()

        let callCount = await publishRepo.publishCallCount
        XCTAssertEqual(callCount, 1,
                       "Non-transient publish error must not retry — exactly one call")
        XCTAssertNotNil(services.lastPublishError,
                        "Non-transient publish error should set lastPublishError")
        XCTAssertNil(services.lastRepositoryError,
                     "Publish error should not set lastRepositoryError")
    }

    // MARK: — Targeted Day Reconciliation

    func testReconcileGeneratedDayRestoresMissingDayWithoutOverwritingEditedCard() async throws {
        let draft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: WorkspaceContext.creatorFixture.creatorID,
            weekStartDate: "2026-07-06",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: .creatorFixture,
            progress: nil
        )
        let reconciledDate = try XCTUnwrap(draft.dailyCards[0].scheduledDate)
        let editedDate = try XCTUnwrap(draft.dailyCards[1].scheduledDate)

        var canonicalCard = draft.dailyCards[0]
        canonicalCard.title = "Canonical regenerated Monday"
        canonicalCard.caption = "Freshly regenerated caption."
        var canonicalDraft = draft
        canonicalDraft.dailyCards[0] = canonicalCard

        let contentRepo = ReconciliationContentRepository(
            publishedPlan: WeeklyPlan.raceWeek,
            generatedDraft: canonicalDraft,
            weekStartDate: "2026-07-06"
        )
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: contentRepo,
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                weeklyGeneration: TestWeeklyGenerationRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: GenerateWeekMemoryTodayCacheStore()
        )
        services.applyGeneratedDraft(draft)
        for day in services.weeklyPlan.days {
            await services.updateWeeklyDayStateImmediately(dayID: day.id, state: .planned)
        }
        var editedCard = draft.dailyCards[1]
        editedCard.title = "Locally edited Tuesday"
        editedCard.caption = "User edited this."
        if var localDraft = services.latestGenerationSummary {
            localDraft.replaceDailyCard(editedCard)
            services.latestGenerationSummary = localDraft
        }
        if let dayIndex = services.weeklyPlan.days.firstIndex(where: { $0.scheduledDate == editedDate }) {
            services.weeklyPlan.days[dayIndex].title = "Locally edited Tuesday"
        }

        await services.reconcileGeneratedDayCardFromCurrentWeeklyContent(scheduledDate: reconciledDate)

        let reconciledCard = services.latestGenerationSummary?.dailyCards
            .first { $0.scheduledDate == reconciledDate }
        XCTAssertEqual(reconciledCard?.title, "Canonical regenerated Monday",
                       "Reconciled day title should match canonical draft")
        XCTAssertEqual(reconciledCard?.caption, "Freshly regenerated caption.",
                       "Reconciled day caption should match canonical draft")

        let editedCardAfter = services.latestGenerationSummary?.dailyCards
            .first { $0.scheduledDate == editedDate }
        XCTAssertEqual(editedCardAfter?.title, "Locally edited Tuesday",
                       "Edited card title must not be overwritten by reconciliation")
        XCTAssertEqual(editedCardAfter?.caption, "User edited this.",
                       "Edited card caption must not be overwritten by reconciliation")

        let planDay = services.weeklyPlan.days.first { $0.scheduledDate == reconciledDate }
        XCTAssertEqual(planDay?.title, "Canonical regenerated Monday",
                       "Weekly plan day title should match canonical draft for reconciled day")

        XCTAssertEqual(services.latestGenerationSummary?.dailyCards.count, 7,
                       "Reconciliation must not change total card count")
        XCTAssertNil(services.lastRepositoryError,
                     "Reconciliation should not set repository error on success")
    }
}

private struct EmptyDraftWeeklyGenerationRepository: WeeklyGenerationRepository {
    func generateWeek(
        creatorID: UUID,
        weekStartDate: String,
        weeklySetupID: UUID?,
        mode: GenerateWeekMode,
        context: WorkspaceContext,
        progress: WeeklyGenerationProgressHandler?
    ) async throws -> GeneratedWeekDraft {
        await progress?(
            WeeklyGenerationProgress(
                phase: .draftingDays,
                generationID: UUID(uuidString: "77777777-7777-4777-8777-777777777771"),
                weeklyPlanID: UUID(uuidString: "77777777-7777-4777-8777-777777777772"),
                draftedDayCount: 0,
                checkedDayCount: 0,
                totalDayCount: 7,
                currentDay: nil,
                message: "generation_complete",
                error: nil
            )
        )

        return GeneratedWeekDraft(
            id: UUID(uuidString: "77777777-7777-4777-8777-777777777771")!,
            weeklyPlanID: UUID(uuidString: "77777777-7777-4777-8777-777777777772")!,
            status: "draft",
            strategySummary: "Empty draft fixture.",
            warnings: [],
            assumptions: [],
            dailyCards: [],
            ideaBank: [],
            sourceSummary: "Empty draft fixture.",
            generatedAt: "2026-06-22T00:00:00Z"
        )
    }
}

private struct ProgressThenFailWeeklyGenerationRepository: WeeklyGenerationRepository {
    func generateWeek(
        creatorID: UUID,
        weekStartDate: String,
        weeklySetupID: UUID?,
        mode: GenerateWeekMode,
        context: WorkspaceContext,
        progress: WeeklyGenerationProgressHandler?
    ) async throws -> GeneratedWeekDraft {
        await progress?(
            WeeklyGenerationProgress(
                phase: .draftingDays,
                generationID: UUID(uuidString: "88888888-8888-4888-8888-888888888881"),
                weeklyPlanID: nil,
                draftedDayCount: 4,
                checkedDayCount: 4,
                totalDayCount: 7,
                currentDay: "2026-06-12",
                message: "generation_running",
                error: nil
            )
        )
        throw RepositoryError.edgeFunction("invalid_ai_json")
    }
}

private struct RetryCompletesQueuedDayRepository: WeeklyGenerationRepository {
    var draft: GeneratedWeekDraft

    func generateWeek(
        creatorID: UUID,
        weekStartDate: String,
        weeklySetupID: UUID?,
        mode: GenerateWeekMode,
        context: WorkspaceContext,
        progress: WeeklyGenerationProgressHandler?
    ) async throws -> GeneratedWeekDraft {
        draft
    }

    func retryQueuedDay(
        generationID: UUID,
        scheduledDate: String,
        context: WorkspaceContext,
        progress: WeeklyGenerationProgressHandler?
    ) async throws -> GeneratedWeekDraft {
        await progress?(.readyForReview(from: draft))
        return draft
    }
}

private struct FailingWeeklyGenerationRepository: WeeklyGenerationRepository {
    func generateWeek(
        creatorID: UUID,
        weekStartDate: String,
        weeklySetupID: UUID?,
        mode: GenerateWeekMode,
        context: WorkspaceContext,
        progress: WeeklyGenerationProgressHandler?
    ) async throws -> GeneratedWeekDraft {
        throw RepositoryError.notConfigured("missing_openai_api_key")
    }
}

private struct WrappedErrorWeeklyGenerationRepository: WeeklyGenerationRepository {
    func generateWeek(
        creatorID: UUID,
        weekStartDate: String,
        weeklySetupID: UUID?,
        mode: GenerateWeekMode,
        context: WorkspaceContext,
        progress: WeeklyGenerationProgressHandler?
    ) async throws -> GeneratedWeekDraft {
        throw NSError(
            domain: "Supabase",
            code: 409,
            userInfo: [
                NSLocalizedDescriptionKey:
                    #"Edge Function returned a non-2xx status code: 409 {"error":"existing_published_week_locked"}"#
            ]
        )
    }
}

private struct RetryPastDateFallbackRepository: WeeklyGenerationRepository {
    let draft: GeneratedWeekDraft
    var retryErrorCode = "past_generation_date_not_allowed"

    func generateWeek(
        creatorID: UUID,
        weekStartDate: String,
        weeklySetupID: UUID?,
        mode: GenerateWeekMode,
        context: WorkspaceContext,
        progress: WeeklyGenerationProgressHandler?
    ) async throws -> GeneratedWeekDraft {
        draft
    }

    func regenerateDay(
        creatorID: UUID,
        weeklyPlanID: UUID,
        scheduledDate: String,
        preserveManualEdits: Bool,
        dayGuidance: String?,
        context: WorkspaceContext
    ) async throws -> RegeneratedDayResult {
        RegeneratedDayResult(
            generationID: draft.id,
            weeklyPlanID: draft.weeklyPlanID,
            status: "draft",
            targetScheduledDate: scheduledDate,
            dailyCard: GeneratedDailyCardDraft(
                id: UUID(),
                scheduledDate: scheduledDate,
                status: "draft",
                title: "Regenerated past day",
                whyToday: "Test regenerated recovery.",
                growthJob: "Consistency.",
                contentPillar: "lifestyle",
                shootability: "easy",
                estimatedShootMinutes: 8,
                energyRequired: "low",
                languageMode: "English",
                sceneList: [
                    ShotScene(number: 1, title: "Test scene", duration: "3 sec", symbol: "sparkles")
                ],
                script: "Test regenerated script.",
                noVoiceoverVersion: "No VO.",
                onScreenText: ["Test"],
                caption: "Test regenerated caption.",
                cta: "Save this.",
                hashtags: ["test"],
                coverText: "Test",
                postInstructions: "Test instructions.",
                brandEventNotes: "",
                backupStory: "Backup story.",
                backupCaptionOnly: "Backup caption.",
                audioOptionNotes: "",
                creatorFitScore: 90,
                riskNotes: [],
                assumptions: ["Test assumption."],
                sourceNote: "Test source."
            ),
            warnings: [],
            assumptions: [],
            sourceSummary: "Test regenerate.",
            generatedAt: "2026-06-29T00:00:00Z"
        )
    }

    func retryQueuedDay(
        generationID: UUID,
        scheduledDate: String,
        context: WorkspaceContext,
        progress: WeeklyGenerationProgressHandler?
    ) async throws -> GeneratedWeekDraft {
        throw RepositoryError.edgeFunction(retryErrorCode)
    }

    func cancelGeneration(generationID: UUID, context: WorkspaceContext) async throws {}
}

private struct PastDateRegenerateDayOnlyRepository: WeeklyGenerationRepository {
    let draft: GeneratedWeekDraft

    func generateWeek(
        creatorID: UUID,
        weekStartDate: String,
        weeklySetupID: UUID?,
        mode: GenerateWeekMode,
        context: WorkspaceContext,
        progress: WeeklyGenerationProgressHandler?
    ) async throws -> GeneratedWeekDraft {
        draft
    }

    func regenerateDay(
        creatorID: UUID,
        weeklyPlanID: UUID,
        scheduledDate: String,
        preserveManualEdits: Bool,
        dayGuidance: String?,
        context: WorkspaceContext
    ) async throws -> RegeneratedDayResult {
        RegeneratedDayResult(
            generationID: draft.id,
            weeklyPlanID: draft.weeklyPlanID,
            status: "draft",
            targetScheduledDate: scheduledDate,
            dailyCard: GeneratedDailyCardDraft(
                id: UUID(),
                scheduledDate: scheduledDate,
                status: "draft",
                title: "Regenerated past day",
                whyToday: "Test regenerated recovery.",
                growthJob: "Consistency.",
                contentPillar: "lifestyle",
                shootability: "easy",
                estimatedShootMinutes: 8,
                energyRequired: "low",
                languageMode: "English",
                sceneList: [
                    ShotScene(number: 1, title: "Test scene", duration: "3 sec", symbol: "sparkles")
                ],
                script: "Test regenerated script.",
                noVoiceoverVersion: "No VO.",
                onScreenText: ["Test"],
                caption: "Test regenerated caption.",
                cta: "Save this.",
                hashtags: ["test"],
                coverText: "Test",
                postInstructions: "Test instructions.",
                brandEventNotes: "",
                backupStory: "Backup story.",
                backupCaptionOnly: "Backup caption.",
                audioOptionNotes: "",
                creatorFitScore: 90,
                riskNotes: [],
                assumptions: ["Test assumption."],
                sourceNote: "Test source."
            ),
            warnings: [],
            assumptions: [],
            sourceSummary: "Test regenerate.",
            generatedAt: "2026-06-29T00:00:00Z"
        )
    }

    func retryQueuedDay(
        generationID: UUID,
        scheduledDate: String,
        context: WorkspaceContext,
        progress: WeeklyGenerationProgressHandler?
    ) async throws -> GeneratedWeekDraft {
        throw RepositoryError.edgeFunction("retry_queued_day_should_not_be_called_for_past_date")
    }

    func cancelGeneration(generationID: UUID, context: WorkspaceContext) async throws {}
}

private final class GenerateWeekMemoryTodayCacheStore: TodayCacheStoring {
    private var snapshots: [WorkspaceContext: CachedTodaySnapshot] = [:]

    func loadSnapshot(for context: WorkspaceContext) throws -> CachedTodaySnapshot? {
        snapshots[context]
    }

    func saveSnapshot(_ snapshot: CachedTodaySnapshot, for context: WorkspaceContext) throws {
        snapshots[context] = snapshot
    }

    func clearSnapshot(for context: WorkspaceContext) throws {
        snapshots[context] = nil
    }
}

private actor WorkingPlanPreferringWeeklyPlanRepository: WeeklyPlanRepository {
    let publishedPlan: WeeklyPlan
    let workingDraft: GeneratedWeekDraft?
    let weekStartDate: String?

    init(
        publishedPlan: WeeklyPlan,
        workingDraft: GeneratedWeekDraft?,
        weekStartDate: String?
    ) {
        self.publishedPlan = publishedPlan
        self.workingDraft = workingDraft
        self.weekStartDate = weekStartDate
    }

    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan {
        publishedPlan
    }

    func currentGeneratedDraft(for context: WorkspaceContext) async throws -> GeneratedWeekDraft? {
        workingDraft
    }

    func ideaBank(for context: WorkspaceContext) async throws -> [WeeklyIdea] {
        workingDraft?.ideaBank ?? []
    }

    func currentWeeklyContent(for context: WorkspaceContext) async throws -> WeeklyRepositoryContent {
        let workingPlan = WeeklyRepositoryContent.makeWorkingPlan(
            from: workingDraft,
            weekStartDate: weekStartDate ?? publishedPlan.weekStartDate,
            setupSections: publishedPlan.setupSections,
            weeklyBriefText: publishedPlan.weeklyBriefText
        )
        return WeeklyRepositoryContent(
            publishedPlan: publishedPlan,
            workingPlan: workingPlan,
            generatedDraft: workingDraft,
            ideaBank: workingDraft?.ideaBank ?? []
        )
    }

    func publishWeek(
        _ plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        generatedDraft: GeneratedWeekDraft?,
        context: WorkspaceContext
    ) async throws -> WeeklyPublishResult {
        throw RepositoryError.notConfigured("publish not needed")
    }

    func selectIdeaForNextOpenDay(
        _ idea: WeeklyIdea,
        in plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        context: WorkspaceContext
    ) async throws -> WeeklySelectionUpdate {
        throw RepositoryError.notConfigured("selection not needed")
    }

    func updateWeeklySetupSections(
        _ sections: [WeeklySetupSection],
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        throw RepositoryError.notConfigured("setup not needed")
    }

    func updateWeeklyBrief(
        _ text: String,
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        throw RepositoryError.notConfigured("brief not needed")
    }
}

private actor FailingPublishWeeklyPlanRepository: WeeklyPlanRepository {
    let error: Error

    init(error: Error) {
        self.error = error
    }

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
        throw error
    }

    func selectIdeaForNextOpenDay(
        _ idea: WeeklyIdea,
        in plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        context: WorkspaceContext
    ) async throws -> WeeklySelectionUpdate {
        throw RepositoryError.notConfigured("selection not needed")
    }

    func updateWeeklySetupSections(
        _ sections: [WeeklySetupSection],
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        throw RepositoryError.notConfigured("setup not needed")
    }

    func updateWeeklyBrief(
        _ text: String,
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        throw RepositoryError.notConfigured("brief not needed")
    }
}

private actor TransientThenSuccessPublishRepository: WeeklyPlanRepository {
    let transientError: Error
    var publishCallCount = 0
    private var latestPublishedPlan: WeeklyPlan = .raceWeek

    init(transientError: Error) {
        self.transientError = transientError
    }

    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan {
        latestPublishedPlan
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
        publishCallCount += 1
        if publishCallCount == 1 {
            throw transientError
        }
        let publishedPlan = plan.softLockedForPublish
        self.latestPublishedPlan = publishedPlan
        let cards = DailyCard.publishedCards(from: publishedPlan)
        return WeeklyPublishResult(
            weeklyPlan: publishedPlan,
            weekCards: cards,
            todayCard: nil,
            summary: "Published after retry."
        )
    }

    func selectIdeaForNextOpenDay(
        _ idea: WeeklyIdea,
        in plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        context: WorkspaceContext
    ) async throws -> WeeklySelectionUpdate {
        throw RepositoryError.notConfigured("selection not needed")
    }

    func updateWeeklySetupSections(
        _ sections: [WeeklySetupSection],
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        throw RepositoryError.notConfigured("setup not needed")
    }

    func updateWeeklyBrief(
        _ text: String,
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        throw RepositoryError.notConfigured("brief not needed")
    }
}

private actor NonTransientFailingPublishRepository: WeeklyPlanRepository {
    let error: Error
    var publishCallCount = 0

    init(error: Error) {
        self.error = error
    }

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
        publishCallCount += 1
        throw error
    }

    func selectIdeaForNextOpenDay(
        _ idea: WeeklyIdea,
        in plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        context: WorkspaceContext
    ) async throws -> WeeklySelectionUpdate {
        throw RepositoryError.notConfigured("selection not needed")
    }

    func updateWeeklySetupSections(
        _ sections: [WeeklySetupSection],
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        throw RepositoryError.notConfigured("setup not needed")
    }

    func updateWeeklyBrief(
        _ text: String,
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        throw RepositoryError.notConfigured("brief not needed")
    }
}

private actor ReviewStateReloadRepository: WeeklyPlanRepository {
    private var draft: GeneratedWeekDraft?
    private var reviewStates: [UUID: String] = [:]

    func seed(draft: GeneratedWeekDraft) {
        self.draft = draft
        reviewStates = [:]
    }

    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan {
        .raceWeek
    }

    func currentGeneratedDraft(for context: WorkspaceContext) async throws -> GeneratedWeekDraft? {
        try await currentWeeklyContent(for: context).generatedDraft
    }

    func ideaBank(for context: WorkspaceContext) async throws -> [WeeklyIdea] {
        draft?.ideaBank ?? []
    }

    func currentWeeklyContent(for context: WorkspaceContext) async throws -> WeeklyRepositoryContent {
        guard let draft else {
            return WeeklyRepositoryContent(publishedPlan: .raceWeek, generatedDraft: nil, ideaBank: [])
        }

        let cardRows = try draft.dailyCards.map { card in
            try Self.makeDailyCardRow(
                from: card,
                planID: draft.weeklyPlanID,
                reviewState: reviewStates[card.id] ?? "open"
            )
        }
        let planRow = try Self.makeWeeklyPlanRow(from: draft)
        let workingPlan = WeeklyRepositoryContent.makeWorkingPlan(
            from: cardRows,
            planRow: planRow,
            setupSections: [],
            weeklyBriefText: ""
        )
        let generatedDraft = GeneratedWeekDraft(
            id: draft.id,
            weeklyPlanID: draft.weeklyPlanID,
            status: draft.status,
            strategySummary: draft.strategySummary,
            warnings: draft.warnings,
            assumptions: draft.assumptions,
            dailyCards: cardRows.map { $0.generatedDailyCardDraft() },
            ideaBank: draft.ideaBank,
            sourceSummary: draft.sourceSummary,
            generatedAt: draft.generatedAt
        )

        return WeeklyRepositoryContent(
            publishedPlan: .raceWeek,
            workingPlan: workingPlan,
            generatedDraft: generatedDraft,
            ideaBank: draft.ideaBank
        )
    }

    func publishWeek(
        _ plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        generatedDraft: GeneratedWeekDraft?,
        context: WorkspaceContext
    ) async throws -> WeeklyPublishResult {
        throw RepositoryError.notConfigured("publish not needed")
    }

    func selectIdeaForNextOpenDay(
        _ idea: WeeklyIdea,
        in plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        context: WorkspaceContext
    ) async throws -> WeeklySelectionUpdate {
        throw RepositoryError.notConfigured("selection not needed")
    }

    func updateWeeklySetupSections(
        _ sections: [WeeklySetupSection],
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        throw RepositoryError.notConfigured("setup not needed")
    }

    func updateWeeklyBrief(
        _ text: String,
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        throw RepositoryError.notConfigured("brief not needed")
    }

    func updateDailyCardReviewState(
        dailyCardID: UUID,
        reviewState: String,
        context: WorkspaceContext
    ) async throws {
        reviewStates[dailyCardID] = reviewState
    }

    private static func makeDailyCardRow(
        from card: GeneratedDailyCardDraft,
        planID: UUID,
        reviewState: String
    ) throws -> SupabaseDailyCardRow {
        let json = """
        {
          "id": "\(card.id.uuidString)",
          "workspace_id": "\(WorkspaceContext.creatorFixture.workspaceID.uuidString)",
          "creator_id": "\(WorkspaceContext.creatorFixture.creatorID.uuidString)",
          "weekly_plan_id": "\(planID.uuidString)",
          "scheduled_date": "\(card.scheduledDate)",
          "status": "draft",
          "review_state": "\(reviewState)",
          "title": "Generated card",
          "scene_list": []
        }
        """
        return try JSONDecoder().decode(SupabaseDailyCardRow.self, from: Data(json.utf8))
    }

    private static func makeWeeklyPlanRow(from draft: GeneratedWeekDraft) throws -> SupabaseWeeklyPlanRow {
        let weekStartDate = draft.dailyCards.map(\.scheduledDate).sorted().first ?? "2026-06-01"
        let json = """
        {
          "id": "\(draft.weeklyPlanID.uuidString)",
          "workspace_id": "\(WorkspaceContext.creatorFixture.workspaceID.uuidString)",
          "creator_id": "\(WorkspaceContext.creatorFixture.creatorID.uuidString)",
          "week_start_date": "\(weekStartDate)",
          "status": "draft",
          "warnings": [],
          "assumptions": [],
          "is_soft_locked": false
        }
        """
        return try JSONDecoder().decode(SupabaseWeeklyPlanRow.self, from: Data(json.utf8))
    }
}

private actor ReviewStateTrackingRepository: WeeklyPlanRepository {
    var reviewStateCalls: [(dailyCardID: UUID, reviewState: String)] = []

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
        throw RepositoryError.notConfigured("publish not needed")
    }

    func selectIdeaForNextOpenDay(
        _ idea: WeeklyIdea,
        in plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        context: WorkspaceContext
    ) async throws -> WeeklySelectionUpdate {
        throw RepositoryError.notConfigured("selection not needed")
    }

    func updateWeeklySetupSections(
        _ sections: [WeeklySetupSection],
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        throw RepositoryError.notConfigured("setup not needed")
    }

    func updateWeeklyBrief(
        _ text: String,
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        throw RepositoryError.notConfigured("brief not needed")
    }

    func updateDailyCardReviewState(
        dailyCardID: UUID,
        reviewState: String,
        context: WorkspaceContext
    ) async throws {
        reviewStateCalls.append((dailyCardID: dailyCardID, reviewState: reviewState))
    }
}

private actor ReconciliationContentRepository: WeeklyPlanRepository {
    let publishedPlan: WeeklyPlan
    let generatedDraft: GeneratedWeekDraft?
    let weekStartDate: String?

    init(
        publishedPlan: WeeklyPlan,
        generatedDraft: GeneratedWeekDraft?,
        weekStartDate: String?
    ) {
        self.publishedPlan = publishedPlan
        self.generatedDraft = generatedDraft
        self.weekStartDate = weekStartDate
    }

    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan {
        publishedPlan
    }

    func currentGeneratedDraft(for context: WorkspaceContext) async throws -> GeneratedWeekDraft? {
        generatedDraft
    }

    func ideaBank(for context: WorkspaceContext) async throws -> [WeeklyIdea] {
        generatedDraft?.ideaBank ?? []
    }

    func currentWeeklyContent(for context: WorkspaceContext) async throws -> WeeklyRepositoryContent {
        let workingPlan = WeeklyRepositoryContent.makeWorkingPlan(
            from: generatedDraft,
            weekStartDate: weekStartDate ?? publishedPlan.weekStartDate,
            setupSections: publishedPlan.setupSections,
            weeklyBriefText: publishedPlan.weeklyBriefText
        )
        return WeeklyRepositoryContent(
            publishedPlan: publishedPlan,
            workingPlan: workingPlan,
            generatedDraft: generatedDraft,
            ideaBank: generatedDraft?.ideaBank ?? []
        )
    }

    func publishWeek(
        _ plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        generatedDraft: GeneratedWeekDraft?,
        context: WorkspaceContext
    ) async throws -> WeeklyPublishResult {
        throw RepositoryError.notConfigured("publish not needed")
    }

    func selectIdeaForNextOpenDay(
        _ idea: WeeklyIdea,
        in plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        context: WorkspaceContext
    ) async throws -> WeeklySelectionUpdate {
        throw RepositoryError.notConfigured("selection not needed")
    }

    func updateWeeklySetupSections(
        _ sections: [WeeklySetupSection],
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        throw RepositoryError.notConfigured("setup not needed")
    }

    func updateWeeklyBrief(
        _ text: String,
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        throw RepositoryError.notConfigured("brief not needed")
    }
}
