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
        XCTAssertEqual(object["feature_flags"] as? [String], ["queued_week_generation"])
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
        XCTAssertEqual(status.weekProgress.draftedDayCount, 7)
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
                  "content_pillar": "routine",
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
                contentPillar: "routine",
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
              "content_pillar": "routine",
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

    func testAppServicesGenerationSuccessWithFixtureRepository() async throws {
        let services = AppServices.fixtureBacked(todayCache: GenerateWeekMemoryTodayCacheStore())

        let generatedDraft = await services.generateCurrentWeekImmediately()
        let draft = try XCTUnwrap(generatedDraft)

        XCTAssertEqual(services.latestGenerationSummary?.id, draft.id)
        XCTAssertEqual(services.weeklyPlan.id, draft.weeklyPlanID)
        XCTAssertEqual(services.weeklyPlan.days.count, 7)
        XCTAssertEqual(services.weeklyGenerationProgress?.phase, .readyForReview)
        XCTAssertEqual(services.weeklyGenerationProgress?.draftedDayCount, 7)
        XCTAssertNil(services.generationError)
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
            todayCache: GenerateWeekMemoryTodayCacheStore()
        )
        let existingDraft = try await FixtureWeeklyGenerationRepository().generateWeek(
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
            todayCache: GenerateWeekMemoryTodayCacheStore()
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
            todayCache: GenerateWeekMemoryTodayCacheStore()
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
            todayCache: GenerateWeekMemoryTodayCacheStore()
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
        let generatedDraft = await services.generateCurrentWeekImmediately()
        var draft = try XCTUnwrap(generatedDraft)
        draft.dailyCards[0].caption = "Edited generated caption."
        draft.dailyCards[0].backupStory = "Edited backup story."
        services.applyGeneratedDraft(draft)
        for day in services.weeklyPlan.days {
            services.updateWeeklyDayState(dayID: day.id, state: .planned)
        }

        await services.publishCurrentWeekImmediately()

        XCTAssertEqual(services.weekCards.first?.caption, "Edited generated caption.")
        XCTAssertEqual(services.weekCards.first?.backupStory, "Edited backup story.")
        XCTAssertEqual(services.latestGenerationSummary?.status, "published")
        XCTAssertNil(services.lastRepositoryError)
    }

    func testPublishCurrentWeekIsLockedWhileDayStatusesAreStillGenerating() async throws {
        let services = AppServices.fixtureBacked(todayCache: GenerateWeekMemoryTodayCacheStore())
        let draft = try await FixtureWeeklyGenerationRepository().generateWeek(
            creatorID: services.context.creatorID,
            weekStartDate: "2026-07-13",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: services.context,
            progress: nil
        )
        services.applyGeneratedDraft(draft)
        for day in services.weeklyPlan.days {
            services.updateWeeklyDayState(dayID: day.id, state: .planned)
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
        let draft = try await FixtureWeeklyGenerationRepository().generateWeek(
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
            services.updateWeeklyDayState(dayID: day.id, state: .planned)
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
