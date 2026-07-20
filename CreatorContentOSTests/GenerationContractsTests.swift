import XCTest
import Supabase
@testable import CreatorContentOS

private struct WeeklyPublishResult: Sendable {
    var weeklyPlan: WeeklyPlan
    var weekCards: [DailyCard]
    var todayCard: DailyCard?
    var summary: String
}

@MainActor
final class GenerationContractsTests: XCTestCase {


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

    func testGenerationStatusRequestAndRunningResponseUseAsyncContract() throws {
        let generationID = UUID(uuidString: "88888888-8888-4888-8888-888888888881")!
        let creatorID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let request = SupabaseGenerationStatusRequest(
            generationID: generationID,
            creatorID: creatorID
        )

        let requestData = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: requestData) as? [String: Any])

        XCTAssertEqual(object["action"] as? String, "status")
        XCTAssertEqual(object["generation_id"] as? String, generationID.uuidString.lowercased())
        XCTAssertEqual(object["creator_id"] as? String, creatorID.uuidString.lowercased())

        let weeklyPlanID = UUID(uuidString: "77777777-7777-4777-8777-777777777771")!
        let responseData = Data(
            """
            {
              "generation_id": "\(generationID.uuidString)",
              "weekly_plan_id": "\(weeklyPlanID.uuidString)",
              "status": "running",
              "message": "generation_started",
              "target_scheduled_date": "2026-06-10",
              "poll_after_seconds": 5
            }
            """.utf8
        )

        let invocation = try SupabaseDailyGenerationInvocation.decode(responseData)
        guard case .running(let status) = invocation else {
            XCTFail("Expected running generation status")
            return
        }
        XCTAssertEqual(status.generationID, generationID)
        XCTAssertEqual(status.weeklyPlanID, weeklyPlanID)
        XCTAssertEqual(status.status, "running")
        XCTAssertEqual(status.message, "generation_started")
        XCTAssertEqual(status.targetScheduledDate, "2026-06-10")
        XCTAssertEqual(status.pollAfterSeconds, 5)
    }

    func testGenerateDayRequestEncodesEdgeFunctionContract() throws {
        let request = SupabaseDailyGenerationRequest(
            creatorID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            scheduledDate: "2026-06-10",
            dayBrief: "Brand unboxing at home, honest tone.",
            mock: true
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["action"] as? String, "generate_day")
        XCTAssertEqual(object["creator_id"] as? String, "33333333-3333-4333-8333-333333333333")
        XCTAssertEqual(object["scheduled_date"] as? String, "2026-06-10")
        XCTAssertEqual(object["day_brief"] as? String, "Brand unboxing at home, honest tone.")
        XCTAssertEqual(object["response_mode"] as? String, "sync")
        XCTAssertEqual(object["mock"] as? Bool, true)
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

        let invocation = try SupabaseDailyGenerationInvocation.decode(data)
        guard case .completed(let response) = invocation else {
            XCTFail("Expected completed day generation")
            return
        }

        XCTAssertEqual(response.domainResult.dailyCard.id, cardID)
        XCTAssertEqual(response.domainResult.targetScheduledDate, "2026-06-10")
        XCTAssertEqual(response.domainResult.dailyCard.caption, "A short recovery walk in New Jersey.")
        XCTAssertEqual(response.domainResult.warnings, ["Confirm the location"])
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

    func testSelectedDayPublishMarksOnlyThatGeneratedCardPublished() async throws {
        let repository = RecordingDayPublishRepository()
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                dailyGeneration: repository,
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore(),
            todayDate: { "2026-07-18" }
        )
        let draft = await TestGeneratedDraftFactory.makeDraft(weekStartDate: "2026-07-20")
        let selected = draft.dailyCards[0]
        services.dayBriefGeneratedCards = Dictionary(
            uniqueKeysWithValues: draft.dailyCards.prefix(2).map { ($0.scheduledDate, $0) }
        )

        let succeeded = await services.publishDayCard(selected)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(services.dayBriefGeneratedCards[selected.scheduledDate]?.status, "published")
        XCTAssertEqual(services.dayBriefGeneratedCards[draft.dailyCards[1].scheduledDate]?.status, "draft")
        XCTAssertNil(services.lastPublishError)
        let request = await repository.lastRequest
        XCTAssertEqual(request?.creatorID, WorkspaceContext.creatorFixture.creatorID)
        XCTAssertEqual(request?.dailyCardID, selected.id)
    }

    func testPublishDayCardRejectsViewerRoleWithoutCallingRepository() async throws {
        let repository = RecordingDayPublishRepository()
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                dailyGeneration: repository,
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            memberRole: "viewer",
            todayCache: InMemoryTodayCacheStore(),
            todayDate: { "2026-07-18" }
        )
        let draft = await TestGeneratedDraftFactory.makeDraft(weekStartDate: "2026-07-20")
        let selected = draft.dailyCards[0]
        services.dayBriefGeneratedCards = [selected.scheduledDate: selected]

        XCTAssertFalse(services.canPublishDay(selected))
        let succeeded = await services.publishDayCard(selected)

        XCTAssertFalse(succeeded)
        XCTAssertEqual(
            services.lastPublishError,
            "This daily card cannot be published from the current session."
        )
        let request = await repository.lastRequest
        XCTAssertNil(request, "Viewer sessions must not invoke publish-day")
    }

    func testPublishDayCardRejectsAlreadyPublishedCard() async throws {
        let repository = RecordingDayPublishRepository()
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                dailyGeneration: repository,
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore(),
            todayDate: { "2026-07-18" }
        )
        let draft = await TestGeneratedDraftFactory.makeDraft(weekStartDate: "2026-07-20")
        var published = draft.dailyCards[0]
        published.status = "published"
        services.dayBriefGeneratedCards = [published.scheduledDate: published]

        XCTAssertFalse(services.canPublishDay(published))
        let succeeded = await services.publishDayCard(published)

        XCTAssertFalse(succeeded)
        XCTAssertNil(services.lastPublishError, "Already published cards should fail silently")
        let request = await repository.lastRequest
        XCTAssertNil(request)
    }

    func testPublishDayCardRejectsMismatchedPublishResponse() async throws {
        let repository = MismatchDayPublishRepository()
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                dailyGeneration: repository,
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore(),
            todayDate: { "2026-07-18" }
        )
        let draft = await TestGeneratedDraftFactory.makeDraft(weekStartDate: "2026-07-20")
        let selected = draft.dailyCards[0]
        services.dayBriefGeneratedCards = [selected.scheduledDate: selected]

        let succeeded = await services.publishDayCard(selected)

        XCTAssertFalse(succeeded)
        XCTAssertEqual(services.lastPublishError, RepositoryError.edgeFunction("invalid_publish_day_response").localizedDescription)
        XCTAssertEqual(services.dayBriefGeneratedCards[selected.scheduledDate]?.status, "draft")
    }

    func testPublishDayCardSurfacesRepositoryPublishErrors() async throws {
        let repository = FailingDayPublishRepository()
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                dailyGeneration: repository,
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore(),
            todayDate: { "2026-07-18" }
        )
        let draft = await TestGeneratedDraftFactory.makeDraft(weekStartDate: "2026-07-20")
        let selected = draft.dailyCards[0]
        services.dayBriefGeneratedCards = [selected.scheduledDate: selected]

        let succeeded = await services.publishDayCard(selected)

        XCTAssertFalse(succeeded)
        XCTAssertEqual(
            services.lastPublishError,
            RepositoryError.edgeFunction("daily_card_not_publishable").localizedDescription
        )
        XCTAssertEqual(services.dayBriefGeneratedCards[selected.scheduledDate]?.status, "draft")
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

    func testGenerateDayCardStoresResultForTheRequestedDate() async throws {
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                dailyGeneration: BriefEchoDayGenerationRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore(),
            todayDate: { "2026-06-01" }
        )

        let card = try await services.generateDayCard(
            scheduledDate: "2026-06-03",
            dayBrief: "  Brand unboxing at home, honest tone.  "
        )

        XCTAssertEqual(card.scheduledDate, "2026-06-03")
        XCTAssertEqual(card.title, "Day card: Brand unboxing at home, honest tone.")
        XCTAssertEqual(services.dayBriefGeneratedCards["2026-06-03"]?.id, card.id)
        XCTAssertNil(services.dayBriefGenerationErrors["2026-06-03"])
        XCTAssertFalse(services.generatingDayBriefDates.contains("2026-06-03"))
    }

    func testGenerateDayCardRejectsPastDates() async throws {
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore(),
            todayDate: { "2026-06-01" }
        )

        do {
            _ = try await services.generateDayCard(
                scheduledDate: "2026-05-30",
                dayBrief: "Yesterday's plan."
            )
            XCTFail("Expected past date rejection")
        } catch {
            XCTAssertEqual(
                services.dayBriefGenerationErrors["2026-05-30"],
                "past_generation_date_not_allowed"
            )
        }
        XCTAssertTrue(services.dayBriefGeneratedCards.isEmpty)
    }

    func testGenerateDayCardRequiresBrief() async throws {
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore(),
            todayDate: { "2026-06-01" }
        )

        do {
            _ = try await services.generateDayCard(
                scheduledDate: "2026-06-03",
                dayBrief: "   "
            )
            XCTFail("Expected empty brief rejection")
        } catch {
            XCTAssertEqual(
                services.dayBriefGenerationErrors["2026-06-03"],
                "day_brief_required"
            )
        }
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

    func testGenerationRetryPolicyClassifiesServerUnavailableStatusAsRetryable() {
        let error = FunctionsError.httpError(
            code: 503,
            data: Data(#"{"error":"temporarily_unavailable"}"#.utf8)
        )

        XCTAssertTrue(SupabaseGenerationRetryPolicy.isRetryableStatusPollingError(error))
    }

    func testGenerationRetryPolicyDoesNotRetryStableProviderConfigurationError() {
        let error = FunctionsError.httpError(
            code: 500,
            data: Data(#"{"error":"missing_openai_api_key"}"#.utf8)
        )

        XCTAssertFalse(SupabaseGenerationRetryPolicy.isRetryableStatusPollingError(error))
    }

    func testRegenerateDayMalformedCompletedPayloadThrowsInsteadOfPolling() {
        let data = Data(
            #"{"generation_id":"88888888-8888-4888-8888-888888888881","weekly_plan_id":"77777777-7777-4777-8777-777777777771","status":"draft","target_scheduled_date":"2026-06-10","daily_card":{}}"#.utf8
        )

        XCTAssertThrowsError(try SupabaseDailyGenerationInvocation.decode(data))
    }

    func testRegenerateDayCancelledStatusDecodesAsTerminalFailure() throws {
        let data = Data(
            #"{"generation_id":"88888888-8888-4888-8888-888888888881","weekly_plan_id":"77777777-7777-4777-8777-777777777771","status":"cancelled","target_scheduled_date":"2026-06-10"}"#.utf8
        )

        let invocation = try SupabaseDailyGenerationInvocation.decode(data)
        guard case .failed(let status) = invocation else {
            XCTFail("Expected cancellation to be terminal.")
            return
        }
        XCTAssertEqual(status.error, "generation_cancelled")
    }

    func testRegenerateDayFailedStatusDecodesGenerationTimeoutError() throws {
        let data = Data(
            #"{"generation_id":"88888888-8888-4888-8888-888888888881","weekly_plan_id":"77777777-7777-4777-8777-777777777771","status":"failed","target_scheduled_date":"2026-06-10","error":"generation_timeout"}"#.utf8
        )

        let invocation = try SupabaseDailyGenerationInvocation.decode(data)
        guard case .failed(let status) = invocation else {
            XCTFail("Expected failed generation status.")
            return
        }
        XCTAssertEqual(status.error, "generation_timeout")
    }

    func testDailyGenerationPollerTimesOutWithGenerationTimeout() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let running = try SupabaseDailyGenerationInvocation.decode(
            Data(
                #"{"generation_id":"88888888-8888-4888-8888-888888888881","weekly_plan_id":"77777777-7777-4777-8777-777777777771","status":"running","target_scheduled_date":"2026-06-10","poll_after_seconds":5}"#.utf8
            )
        )

        do {
            _ = try await SupabaseDailyGenerationPoller.poll(
                deadline: now,
                now: { now },
                initialPollAfterSeconds: 0,
                sleep: { _ in },
                invokeStatus: {
                    guard case .running = running else {
                        XCTFail("Expected running status fixture.")
                        return running
                    }
                    return running
                }
            )
            XCTFail("Expected polling to time out.")
        } catch RepositoryError.edgeFunction(let code) {
            XCTAssertEqual(code, "generation_timeout")
        }
    }

    func testGenerateDayCardSurfacesReliabilityErrorsWithRetryGuidance() async throws {
        let targetDate = "2026-06-03"
        let cases: [(code: String, message: String)] = [
            (
                "generation_timeout",
                "Generation timed out. Wait a moment, then try Generate again."
            ),
            (
                "generation_cancelled",
                "Generation was cancelled. Try Generate again."
            ),
            (
                "accepted_run_not_found",
                "Generation status is still syncing. Refresh and try Generate again."
            ),
        ]

        for testCase in cases {
            let services = AppServices.fixtureBacked(
                repositories: AppRepositories(
                    context: .creatorFixture,
                    today: FixtureTodayCardRepository(),
                    weeklyPlans: FixtureWeeklyPlanRepository(),
                    references: FixtureReferenceRepository(),
                    referenceImport: FixtureReferenceImportRepository(),
                    dailyGeneration: CodeThrowingDayGenerationRepository(errorCode: testCase.code),
                    intelligence: FixtureIntelligenceRepository(),
                    creatorProfile: FixtureCreatorProfileRepository(),
                    archive: FixtureArchiveRepository()
                ),
                todayCache: InMemoryTodayCacheStore(),
                todayDate: { "2026-06-01" }
            )

            do {
                _ = try await services.generateDayCard(
                    scheduledDate: targetDate,
                    dayBrief: "Brand unboxing at home, honest tone."
                )
                XCTFail("Expected \(testCase.code) to fail for generate_day.")
            } catch RepositoryError.edgeFunction(let message) {
                XCTAssertEqual(message, testCase.message)
            }

            XCTAssertEqual(services.dayBriefGenerationErrors[targetDate], testCase.message)
            XCTAssertFalse(services.generatingDayBriefDates.contains(targetDate))
        }
    }

    func testGenerateDayCardSurfacesAlreadyRunningWithRetryGuidance() async throws {
        let targetDate = "2026-06-03"
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                dailyGeneration: CodeThrowingDayGenerationRepository(errorCode: "unused"),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore(),
            todayDate: { "2026-06-01" }
        )
        services.generatingDayBriefDates.insert(targetDate)

        do {
            _ = try await services.generateDayCard(
                scheduledDate: targetDate,
                dayBrief: "Second overlapping request."
            )
            XCTFail("Expected generation_already_running rejection.")
        } catch RepositoryError.edgeFunction(let message) {
            XCTAssertEqual(
                message,
                "A generation is already in progress for this day. Wait for it to finish, then try again."
            )
        }

        XCTAssertEqual(
            services.dayBriefGenerationErrors[targetDate],
            "A generation is already in progress for this day. Wait for it to finish, then try again."
        )
    }

    func testGenerateDayCardRejectsDuplicateInFlightWhenStaleCachedCardExists() async throws {
        let targetDate = "2026-06-03"
        let staleCard = GeneratedDailyCardDraft(
            id: UUID(),
            scheduledDate: targetDate,
            status: "draft",
            title: "Stale cached day card from first request",
            whyToday: "Prior in-flight generation.",
            growthJob: "Consistency.",
            contentPillar: "lifestyle",
            shootability: "easy",
            estimatedShootMinutes: 8,
            energyRequired: "low",
            languageMode: "English",
            sceneList: [
                ShotScene(number: 1, title: "Stale scene", duration: "3 sec", symbol: "sparkles")
            ],
            script: "Stale script.",
            noVoiceoverVersion: "No VO.",
            onScreenText: ["Stale"],
            caption: "Stale caption.",
            cta: "Save this.",
            hashtags: ["stale"],
            coverText: "Stale",
            postInstructions: "Stale instructions.",
            brandEventNotes: "",
            backupStory: "Stale backup.",
            backupCaptionOnly: "Stale backup caption.",
            audioOptionNotes: "",
            creatorFitScore: 90,
            riskNotes: [],
            assumptions: ["Stale cache fixture."],
            sourceNote: "Stale cache fixture."
        )
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                dailyGeneration: CodeThrowingDayGenerationRepository(errorCode: "must_not_call_provider"),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore(),
            todayDate: { "2026-06-01" }
        )
        services.generatingDayBriefDates.insert(targetDate)
        services.dayBriefGeneratedCards[targetDate] = staleCard

        do {
            _ = try await services.generateDayCard(
                scheduledDate: targetDate,
                dayBrief: "Second overlapping request."
            )
            XCTFail("Expected generation_already_running rejection instead of stale cached card.")
        } catch RepositoryError.edgeFunction(let message) {
            XCTAssertEqual(
                message,
                "A generation is already in progress for this day. Wait for it to finish, then try again."
            )
        }

        XCTAssertEqual(services.dayBriefGeneratedCards[targetDate]?.title, "Stale cached day card from first request")
        XCTAssertEqual(
            services.dayBriefGenerationErrors[targetDate],
            "A generation is already in progress for this day. Wait for it to finish, then try again."
        )
    }

    func testRegenerateDailyCardRejectsDuplicateInFlightWhenStaleSummaryCardExists() async throws {
        let targetDate = "2026-06-03"
        var draft = await TestGeneratedDraftFactory.makeDraft(weekStartDate: "2026-06-01")
        draft.weeklyPlanID = WeeklyPlan.raceWeek.id
        guard let targetIndex = draft.dailyCards.firstIndex(where: { $0.scheduledDate == targetDate }) else {
            XCTFail("Expected draft to include \(targetDate)")
            return
        }
        draft.dailyCards[targetIndex].title = "Stale summary card from first regenerate"
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                dailyGeneration: CodeThrowingDayGenerationRepository(errorCode: "must_not_call_provider"),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore(),
            todayDate: { "2026-06-01" }
        )
        services.applyGeneratedDraft(draft)
        services.regeneratingDayDates.insert(targetDate)

        do {
            _ = try await services.regeneratedDailyCard(
                scheduledDate: targetDate,
                preserveManualEdits: false
            )
            XCTFail("Expected generation_already_running rejection instead of stale summary card.")
        } catch RepositoryError.edgeFunction(let message) {
            XCTAssertEqual(
                message,
                "A generation is already in progress for this day. Wait for it to finish, then try again."
            )
        }

        XCTAssertEqual(
            services.latestGenerationSummary?.dailyCards.first { $0.scheduledDate == targetDate }?.title,
            "Stale summary card from first regenerate"
        )
        XCTAssertEqual(
            services.regenerationDayErrors[targetDate],
            "A generation is already in progress for this day. Wait for it to finish, then try again."
        )
    }

    func testDailyGenerationPollerAllowsBackendRecoveryBudget() {
        XCTAssertGreaterThanOrEqual(
            SupabaseDailyGenerationPoller.defaultTimeoutSeconds,
            1_800,
            "The day poller must outlive the backend's bounded recovery attempts."
        )
    }

    func testDailyGenerationPollerCompletesTwentyOfTwentyRecoverableScenarios() async throws {
        let completed = try completedDayPollingInvocation()
        let running = try SupabaseDailyGenerationInvocation.decode(
            Data(
                #"{"generation_id":"88888888-8888-4888-8888-888888888881","weekly_plan_id":"77777777-7777-4777-8777-777777777771","status":"running","target_scheduled_date":"2026-06-10","poll_after_seconds":5}"#.utf8
            )
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        for scenario in 0..<20 {
            let steps: [DailyGenerationPollingScript.Step]
            switch scenario % 5 {
            case 0:
                steps = [.networkConnectionLost, .completed]
            case 1:
                steps = [.acceptedRunNotFound, .running, .completed]
            case 2:
                steps = [.networkConnectionLost, .networkConnectionLost, .completed]
            case 3:
                steps = [.running, .completed]
            default:
                steps = [.serverUnavailable, .completed]
            }
            let script = DailyGenerationPollingScript(
                steps: steps,
                running: running,
                completed: completed
            )
            let result = try await SupabaseDailyGenerationPoller.poll(
                deadline: now.addingTimeInterval(60),
                now: { now },
                initialPollAfterSeconds: 0,
                sleep: { _ in },
                invokeStatus: {
                    try await script.next()
                }
            )

            XCTAssertEqual(result.targetScheduledDate, "2026-06-10")
            XCTAssertEqual(result.status, "draft")
        }
    }

    func testDailyGenerationPollerBacksOffRepeatedRetryableStatusFailures() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let completed = try completedDayPollingInvocation()
        let script = DailyGenerationPollingScript(
            steps: [
                .networkConnectionLost,
                .serverUnavailable,
                .networkConnectionLost,
                .completed,
            ],
            running: completed,
            completed: completed
        )
        let sleeper = DailyGenerationPollingSleeper()

        _ = try await SupabaseDailyGenerationPoller.poll(
            deadline: now.addingTimeInterval(60),
            now: { now },
            initialPollAfterSeconds: 0,
            sleep: { nanoseconds in
                await sleeper.record(nanoseconds)
            },
            invokeStatus: {
                try await script.next()
            }
        )

        let recordedNanoseconds = await sleeper.recordedNanoseconds
        XCTAssertEqual(
            recordedNanoseconds,
            [0, 2_000_000_000, 4_000_000_000, 8_000_000_000]
        )
    }

    func testDailyGenerationPollerDoesNotRetryNonTransientStatusError() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let completed = try completedDayPollingInvocation()
        for terminalStep in [
            DailyGenerationPollingScript.Step.unauthorized,
            .missingProviderConfiguration,
        ] {
            let script = DailyGenerationPollingScript(
                steps: [terminalStep, .completed],
                running: completed,
                completed: completed
            )

            do {
                _ = try await SupabaseDailyGenerationPoller.poll(
                    deadline: now.addingTimeInterval(60),
                    now: { now },
                    initialPollAfterSeconds: 0,
                    sleep: { _ in },
                    invokeStatus: {
                        try await script.next()
                    }
                )
                XCTFail("Expected the non-transient status error to fail immediately.")
            } catch {
                let invocationCount = await script.invocationCount
                XCTAssertEqual(invocationCount, 1)
            }
        }
    }

    private func completedDayPollingInvocation() throws -> SupabaseDailyGenerationInvocation {
        let data = Data(
            """
            {
              "generation_id": "88888888-8888-4888-8888-888888888881",
              "weekly_plan_id": "77777777-7777-4777-8777-777777777771",
              "status": "draft",
              "target_scheduled_date": "2026-06-10",
              "warnings": [],
              "assumptions": [],
              "source_summary": "Polling reliability fixture.",
              "generated_at": "2026-06-10T08:00:00Z",
              "daily_card": {
                "id": "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1",
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
        return try SupabaseDailyGenerationInvocation.decode(data)
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
        let draft = await TestGeneratedDraftFactory.makeDraft(
            weekStartDate: "2026-07-06"
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
        let draft = await TestGeneratedDraftFactory.makeDraft(
            weekStartDate: "2026-07-06"
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
        let draft = await TestGeneratedDraftFactory.makeDraft(
            weekStartDate: "2026-07-06"
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
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore()
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
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore(),
            todayDate: { publishedStartDate }
        )

        await services.refreshFromRepositoriesImmediately()

        XCTAssertEqual(services.weeklyPlan.id, workingPlanID,
                       "Manager should fall back to published plan when no working draft exists")
        XCTAssertNil(services.latestGenerationSummary)
        XCTAssertNil(services.lastRepositoryError)
    }

    func testColdRefreshHydratesPersistedOpenDayCardAndExcludesPublished() async throws {
        var draft = await TestGeneratedDraftFactory.makeDraft(
            weekStartDate: "2026-07-06"
        )
        draft.dailyCards[0].status = "open"
        draft.dailyCards[1].status = "published"

        let openDate = draft.dailyCards[0].scheduledDate
        let publishedDate = draft.dailyCards[1].scheduledDate
        let openCardID = draft.dailyCards[0].id

        let weeklyRepository = WorkingPlanPreferringWeeklyPlanRepository(
            publishedPlan: WeeklyPlan.raceWeek,
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
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore(),
            todayDate: { "2026-07-06" }
        )

        XCTAssertTrue(services.dayBriefGeneratedCards.isEmpty)

        await services.refreshFromRepositoriesImmediately()

        XCTAssertEqual(services.latestGenerationSummary?.id, draft.id)
        XCTAssertEqual(services.dayBriefGeneratedCards[openDate]?.id, openCardID)
        XCTAssertNil(services.dayBriefGeneratedCards[publishedDate])
        XCTAssertEqual(services.generatedDailyCard(for: openCardID)?.scheduledDate, openDate)
    }

    func testRefreshHydrationPreservesInFlightDayBriefCardOverDraftCard() async throws {
        var draft = await TestGeneratedDraftFactory.makeDraft(
            weekStartDate: "2026-07-06"
        )
        let generatingDate = draft.dailyCards[0].scheduledDate
        let draftCardID = draft.dailyCards[0].id
        draft.dailyCards[0].status = "open"
        draft.dailyCards[0].title = "Repository draft card"

        var inFlightCard = draft.dailyCards[1]
        inFlightCard.scheduledDate = generatingDate
        inFlightCard.status = "draft"
        inFlightCard.title = "In-flight day brief card"
        let inFlightCardID = inFlightCard.id

        let weeklyRepository = WorkingPlanPreferringWeeklyPlanRepository(
            publishedPlan: WeeklyPlan.raceWeek,
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
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore(),
            todayDate: { "2026-07-06" }
        )

        services.dayBriefGeneratedCards[generatingDate] = inFlightCard
        services.generatingDayBriefDates.insert(generatingDate)

        await services.refreshFromRepositoriesImmediately()

        XCTAssertEqual(services.dayBriefGeneratedCards[generatingDate]?.id, inFlightCardID)
        XCTAssertEqual(services.dayBriefGeneratedCards[generatingDate]?.title, "In-flight day brief card")
        XCTAssertNotEqual(services.dayBriefGeneratedCards[generatingDate]?.id, draftCardID)
        XCTAssertTrue(services.generatingDayBriefDates.contains(generatingDate))
    }

    func testRefreshWithoutDraftPreservesCompletedDayBriefGeneratedCards() async throws {
        let publishedPlan = WeeklyPlan.raceWeek
        let draft = await TestGeneratedDraftFactory.makeDraft(
            weekStartDate: "2026-07-06"
        )
        var completedCard = draft.dailyCards[1]
        completedCard.scheduledDate = "2026-07-07"
        completedCard.status = "draft"
        completedCard.title = "Completed day brief card"
        let completedDate = completedCard.scheduledDate
        let completedCardID = completedCard.id

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
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore(),
            todayDate: { completedDate }
        )

        services.dayBriefGeneratedCards[completedDate] = completedCard

        await services.refreshFromRepositoriesImmediately()

        XCTAssertNil(services.latestGenerationSummary)
        XCTAssertEqual(services.dayBriefGeneratedCards[completedDate]?.id, completedCardID)
        XCTAssertEqual(services.dayBriefGeneratedCards[completedDate]?.title, "Completed day brief card")
    }

    func testCurrentPublishedPlanStillReturnsCanonicalPublishedPlan() async throws {
        let publishedPlan = WeeklyPlan.raceWeek
        let draft = await TestGeneratedDraftFactory.makeDraft(
            weekStartDate: "2026-07-06"
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
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore()
        )

        let draft = await TestGeneratedDraftFactory.makeDraft(
            weekStartDate: "2026-06-01"
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
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore()
        )

        let draft = await TestGeneratedDraftFactory.makeDraft(
            weekStartDate: "2026-06-01"
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

    func testGeneralRepositoryErrorDoesNotSetLastPublishError() async throws {
        let services = AppServices.fixtureBacked(
            todayCache: InMemoryTodayCacheStore(),
            todayDate: { "2026-06-01" }
        )

        services.lastRepositoryError = "network connection lost"
        services.lastPublishError = nil

        XCTAssertNotNil(services.lastRepositoryError,
                        "lastRepositoryError should be set for general error")
        XCTAssertNil(services.lastPublishError,
                     "lastPublishError should remain nil for non-publish error")
    }

    // MARK: — Stale Date Normalization

    func testNormalizeManagerWeekStartSkipsWhenWorkingDraftExists() async throws {
        let draft = await TestGeneratedDraftFactory.makeDraft(
            weekStartDate: "2026-05-25"
        )
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore(),
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
            todayCache: InMemoryTodayCacheStore(),
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
        XCTAssertNil(services.generationError,
                     "Generation error should be cleared after normalization")
    }

    func testNormalizeManagerWeekStartSkipsWhenWeekStartIsNotPast() async throws {
        let services = AppServices.fixtureBacked(
            todayCache: InMemoryTodayCacheStore(),
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
            todayCache: InMemoryTodayCacheStore(),
            todayDate: { "2026-07-01" }
        )
        services.latestGenerationSummary = nil
        services.weeklyPlan.weekStartDate = "2026-07-01"

        services.normalizeManagerWeekStartIfStale()

        XCTAssertEqual(services.weeklyPlan.weekStartDate, "2026-07-01",
                       "Week starting today should not be normalized")
    }

    // MARK: — Targeted Day Reconciliation

    func testReconcileGeneratedDayRestoresMissingDayWithoutOverwritingEditedCard() async throws {
        let draft = await TestGeneratedDraftFactory.makeDraft(
            weekStartDate: "2026-07-06"
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
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore()
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

    func testGenerateDayCardSeedsLatestGenerationSummaryFromCanonicalContentWhenNil() async throws {
        let targetDate = "2026-06-03"
        var canonicalDraft = await TestGeneratedDraftFactory.makeDraft(weekStartDate: "2026-06-01")
        canonicalDraft.weeklyPlanID = WeeklyPlan.raceWeek.id
        guard let targetIndex = canonicalDraft.dailyCards.firstIndex(where: { $0.scheduledDate == targetDate }) else {
            XCTFail("Expected canonical draft to include \(targetDate)")
            return
        }
        var canonicalCard = canonicalDraft.dailyCards[targetIndex]
        canonicalCard.title = "Canonical persisted Wednesday"
        canonicalCard.caption = "Canonical persisted caption."
        canonicalDraft.dailyCards[targetIndex] = canonicalCard

        var generatedCard = canonicalCard
        generatedCard.title = "Day card: Brand unboxing at home, honest tone."
        let contentRepo = ReconciliationContentRepository(
            publishedPlan: WeeklyPlan.raceWeek,
            generatedDraft: canonicalDraft,
            weekStartDate: "2026-06-01"
        )
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: contentRepo,
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                dailyGeneration: DeterministicDayGenerationRepository(generatedCard: generatedCard),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore(),
            todayDate: { "2026-06-01" }
        )

        XCTAssertNil(services.latestGenerationSummary)

        let returnedCard = try await services.generateDayCard(
            scheduledDate: targetDate,
            dayBrief: "Brand unboxing at home, honest tone."
        )

        XCTAssertEqual(returnedCard.id, generatedCard.id)
        XCTAssertEqual(services.latestGenerationSummary?.id, canonicalDraft.id)
        XCTAssertEqual(services.latestGenerationSummary?.weeklyPlanID, WeeklyPlan.raceWeek.id)
        let weeklyReviewCard = services.latestGenerationSummary?.dailyCards
            .first { $0.scheduledDate == targetDate }
        XCTAssertEqual(weeklyReviewCard?.title, "Canonical persisted Wednesday")
        XCTAssertEqual(weeklyReviewCard?.caption, "Canonical persisted caption.")
        XCTAssertEqual(services.dayBriefGeneratedCards[targetDate]?.id, generatedCard.id)
        XCTAssertEqual(services.dayBriefGeneratedCards[targetDate]?.title, "Canonical persisted Wednesday")
        XCTAssertNil(services.lastRepositoryError)
    }

    func testGenerateDayCardReconcilesTargetDayWithoutOverwritingEditedCard() async throws {
        let targetDate = "2026-06-03"
        let editedDate = "2026-06-04"
        var localDraft = await TestGeneratedDraftFactory.makeDraft(weekStartDate: "2026-06-01")
        localDraft.weeklyPlanID = WeeklyPlan.raceWeek.id
        guard let targetIndex = localDraft.dailyCards.firstIndex(where: { $0.scheduledDate == targetDate }),
              let editedIndex = localDraft.dailyCards.firstIndex(where: { $0.scheduledDate == editedDate })
        else {
            XCTFail("Expected draft to include target and edited dates")
            return
        }

        var canonicalDraft = localDraft
        var canonicalCard = canonicalDraft.dailyCards[targetIndex]
        canonicalCard.title = "Canonical persisted Wednesday"
        canonicalCard.caption = "Canonical persisted caption."
        canonicalDraft.dailyCards[targetIndex] = canonicalCard

        var generatedCard = canonicalCard
        generatedCard.title = "Day card: Brand unboxing at home, honest tone."
        let contentRepo = ReconciliationContentRepository(
            publishedPlan: WeeklyPlan.raceWeek,
            generatedDraft: canonicalDraft,
            weekStartDate: "2026-06-01"
        )
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: contentRepo,
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                dailyGeneration: DeterministicDayGenerationRepository(generatedCard: generatedCard),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore(),
            todayDate: { "2026-06-01" }
        )
        services.applyGeneratedDraft(localDraft)
        localDraft.dailyCards[editedIndex].title = "Locally edited Thursday"
        localDraft.dailyCards[editedIndex].caption = "User edited this."
        if var seededDraft = services.latestGenerationSummary {
            seededDraft.replaceDailyCard(localDraft.dailyCards[editedIndex])
            services.latestGenerationSummary = seededDraft
        }
        if let dayIndex = services.weeklyPlan.days.firstIndex(where: { $0.scheduledDate == editedDate }) {
            services.weeklyPlan.days[dayIndex].title = "Locally edited Thursday"
        }

        _ = try await services.generateDayCard(
            scheduledDate: targetDate,
            dayBrief: "Brand unboxing at home, honest tone."
        )

        let reconciledCard = services.latestGenerationSummary?.dailyCards
            .first { $0.scheduledDate == targetDate }
        XCTAssertEqual(reconciledCard?.title, "Canonical persisted Wednesday")
        XCTAssertEqual(reconciledCard?.caption, "Canonical persisted caption.")

        let editedCardAfter = services.latestGenerationSummary?.dailyCards
            .first { $0.scheduledDate == editedDate }
        XCTAssertEqual(editedCardAfter?.title, "Locally edited Thursday")
        XCTAssertEqual(editedCardAfter?.caption, "User edited this.")
        XCTAssertEqual(services.latestGenerationSummary?.dailyCards.count, 7)
        XCTAssertEqual(services.dayBriefGeneratedCards[targetDate]?.title, "Canonical persisted Wednesday")
    }

    func testGenerateDayCardSurvivesReconciliationReadFailure() async throws {
        let targetDate = "2026-06-03"
        let cardID = UUID()
        let generatedCard = GeneratedDailyCardDraft(
            id: cardID,
            scheduledDate: targetDate,
            status: "draft",
            title: "Day card: Brand unboxing at home, honest tone.",
            whyToday: "Test day-at-a-time generation.",
            growthJob: "Consistency.",
            contentPillar: "lifestyle",
            shootability: "easy",
            estimatedShootMinutes: 8,
            energyRequired: "low",
            languageMode: "English",
            sceneList: [
                ShotScene(number: 1, title: "Test scene", duration: "3 sec", symbol: "sparkles")
            ],
            script: "Test day script.",
            noVoiceoverVersion: "No VO.",
            onScreenText: ["Test"],
            caption: "Test day caption.",
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
        )

        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FailingCurrentWeeklyContentRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                dailyGeneration: DeterministicDayGenerationRepository(generatedCard: generatedCard),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore(),
            todayDate: { "2026-06-01" }
        )

        let returnedCard = try await services.generateDayCard(
            scheduledDate: targetDate,
            dayBrief: "Brand unboxing at home, honest tone."
        )

        XCTAssertEqual(returnedCard.id, cardID)
        XCTAssertEqual(services.dayBriefGeneratedCards[targetDate]?.id, cardID)
        XCTAssertNil(services.latestGenerationSummary)
        XCTAssertNil(services.lastRepositoryError)
        XCTAssertNil(services.dayBriefGenerationErrors[targetDate])
    }

    func testGenerateDayCardRejectsMismatchedResponseDates() async throws {
        let requestedDate = "2026-06-03"
        let wrongDate = "2026-06-04"
        var localDraft = await TestGeneratedDraftFactory.makeDraft(weekStartDate: "2026-06-01")
        localDraft.weeklyPlanID = WeeklyPlan.raceWeek.id
        guard let targetIndex = localDraft.dailyCards.firstIndex(where: { $0.scheduledDate == requestedDate }) else {
            XCTFail("Expected draft to include \(requestedDate)")
            return
        }

        let mismatches = [
            (label: "top-level target", targetDate: wrongDate, cardDate: requestedDate),
            (label: "daily card", targetDate: requestedDate, cardDate: wrongDate),
        ]

        for mismatch in mismatches {
            var generatedCard = localDraft.dailyCards[targetIndex]
            generatedCard.scheduledDate = mismatch.cardDate
            generatedCard.title = "Wrong-date day card title"
            let services = AppServices.fixtureBacked(
                repositories: AppRepositories(
                    context: .creatorFixture,
                    today: FixtureTodayCardRepository(),
                    weeklyPlans: ReconciliationContentRepository(
                        publishedPlan: WeeklyPlan.raceWeek,
                        generatedDraft: localDraft,
                        weekStartDate: "2026-06-01"
                    ),
                    references: FixtureReferenceRepository(),
                    referenceImport: FixtureReferenceImportRepository(),
                    dailyGeneration: DeterministicDayGenerationRepository(
                        generatedCard: generatedCard,
                        targetScheduledDate: mismatch.targetDate
                    ),
                    intelligence: FixtureIntelligenceRepository(),
                    creatorProfile: FixtureCreatorProfileRepository(),
                    archive: FixtureArchiveRepository()
                ),
                todayCache: InMemoryTodayCacheStore(),
                todayDate: { "2026-06-01" }
            )
            services.applyGeneratedDraft(localDraft)
            let summaryBefore = services.latestGenerationSummary
            let weeklyDayBefore = services.weeklyPlan.days.first { $0.scheduledDate == requestedDate }

            do {
                _ = try await services.generateDayCard(
                    scheduledDate: requestedDate,
                    dayBrief: "Brand unboxing at home, honest tone."
                )
                XCTFail("Expected \(mismatch.label) mismatch rejection")
            } catch {
                XCTAssertEqual(
                    services.dayBriefGenerationErrors[requestedDate],
                    "The generated card did not match the requested date. Try Generate again."
                )
            }

            XCTAssertNil(services.dayBriefGeneratedCards[requestedDate])
            XCTAssertEqual(services.latestGenerationSummary?.id, summaryBefore?.id)
            XCTAssertEqual(
                services.latestGenerationSummary?.dailyCards.first { $0.scheduledDate == requestedDate }?.title,
                summaryBefore?.dailyCards.first { $0.scheduledDate == requestedDate }?.title
            )
            XCTAssertEqual(
                services.weeklyPlan.days.first { $0.scheduledDate == requestedDate }?.title,
                weeklyDayBefore?.title
            )
            XCTAssertFalse(services.generatingDayBriefDates.contains(requestedDate))
        }
    }

    func testGenerateDayCardWithDifferentWeeklyPlanIDDoesNotMutateCurrentWeeklyReviewState() async throws {
        let targetDate = "2026-06-03"
        let otherWeeklyPlanID = UUID(uuidString: "88888888-8888-4888-8888-888888888881")!
        var localDraft = await TestGeneratedDraftFactory.makeDraft(weekStartDate: "2026-06-01")
        localDraft.weeklyPlanID = WeeklyPlan.raceWeek.id
        guard let targetIndex = localDraft.dailyCards.firstIndex(where: { $0.scheduledDate == targetDate }) else {
            XCTFail("Expected draft to include \(targetDate)")
            return
        }

        let originalSummaryCardTitle = localDraft.dailyCards[targetIndex].title
        var generatedCard = localDraft.dailyCards[targetIndex]
        generatedCard.title = "Other-plan day card title"
        generatedCard.caption = "Other-plan day card caption."

        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: ReconciliationContentRepository(
                    publishedPlan: WeeklyPlan.raceWeek,
                    generatedDraft: localDraft,
                    weekStartDate: "2026-06-01"
                ),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                dailyGeneration: DeterministicDayGenerationRepository(
                    generatedCard: generatedCard,
                    weeklyPlanID: otherWeeklyPlanID
                ),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: InMemoryTodayCacheStore(),
            todayDate: { "2026-06-01" }
        )
        services.applyGeneratedDraft(localDraft)
        let summaryBefore = services.latestGenerationSummary
        let weeklyDayBefore = services.weeklyPlan.days.first { $0.scheduledDate == targetDate }

        let returnedCard = try await services.generateDayCard(
            scheduledDate: targetDate,
            dayBrief: "Brand unboxing at home, honest tone."
        )

        XCTAssertEqual(returnedCard.id, generatedCard.id)
        XCTAssertEqual(returnedCard.title, "Other-plan day card title")
        XCTAssertEqual(services.dayBriefGeneratedCards[targetDate]?.id, generatedCard.id)
        XCTAssertEqual(services.dayBriefGeneratedCards[targetDate]?.title, "Other-plan day card title")
        XCTAssertEqual(services.latestGenerationSummary?.id, summaryBefore?.id)
        XCTAssertEqual(
            services.latestGenerationSummary?.dailyCards.first { $0.scheduledDate == targetDate }?.title,
            originalSummaryCardTitle
        )
        XCTAssertEqual(services.weeklyPlan.days.first { $0.scheduledDate == targetDate }?.title, weeklyDayBefore?.title)
    }
}

private struct CodeThrowingDayGenerationRepository: DayGenerationRepository {
    let errorCode: String

    func generateDay(
        creatorID: UUID,
        scheduledDate: String,
        dayBrief: String,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        throw RepositoryError.edgeFunction(errorCode)
    }
}

private struct DeterministicDayGenerationRepository: DayGenerationRepository {
    let generatedCard: GeneratedDailyCardDraft
    var weeklyPlanID: UUID = WeeklyPlan.raceWeek.id
    var targetScheduledDate: String?

    func generateDay(
        creatorID: UUID,
        scheduledDate: String,
        dayBrief: String,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        DailyGenerationResult(
            generationID: UUID(),
            weeklyPlanID: weeklyPlanID,
            status: "draft",
            targetScheduledDate: targetScheduledDate ?? scheduledDate,
            dailyCard: generatedCard,
            warnings: [],
            assumptions: [],
            sourceSummary: "Day brief only.",
            generatedAt: "2026-06-01T00:00:00Z"
        )
    }
}

private actor FailingCurrentWeeklyContentRepository: WeeklyPlanRepository {
    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan {
        .raceWeek
    }

    func currentGeneratedDraft(for context: WorkspaceContext) async throws -> GeneratedWeekDraft? {
        nil
    }

    func ideaBank(for context: WorkspaceContext) async throws -> [WeeklyIdea] {
        WeeklyIdea.raceWeekBank
    }

    func currentWeeklyContent(for context: WorkspaceContext) async throws -> WeeklyRepositoryContent {
        throw RepositoryError.notConfigured("reconciliation read failed")
    }

    func retiredFixturePublication(
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

/// Echoes the day brief back in the generated card title so tests can prove
/// the brief reached the repository unchanged (after trimming).
private struct BriefEchoDayGenerationRepository: DayGenerationRepository {
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
                whyToday: "Test day-at-a-time generation.",
                growthJob: "Consistency.",
                contentPillar: "lifestyle",
                shootability: "easy",
                estimatedShootMinutes: 8,
                energyRequired: "low",
                languageMode: "English",
                sceneList: [
                    ShotScene(number: 1, title: "Test scene", duration: "3 sec", symbol: "sparkles")
                ],
                script: "Test day script.",
                noVoiceoverVersion: "No VO.",
                onScreenText: ["Test"],
                caption: "Test day caption.",
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
            sourceSummary: "Day brief only.",
            generatedAt: "2026-06-01T00:00:00Z"
        )
    }
}

private final class InMemoryTodayCacheStore: TodayCacheStoring {
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

    func retiredFixturePublication(
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

    func retiredFixturePublication(
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

    func retiredFixturePublication(
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

    func retiredFixturePublication(
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

    func retiredFixturePublication(
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

    func retiredFixturePublication(
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

private actor RecordingDayPublishRepository: DayGenerationRepository {
    struct Request: Sendable {
        var creatorID: UUID
        var dailyCardID: UUID
    }

    private(set) var lastRequest: Request?

    func publishDay(
        creatorID: UUID,
        dailyCardID: UUID,
        context: WorkspaceContext
    ) async throws -> DailyPublishResult {
        lastRequest = Request(creatorID: creatorID, dailyCardID: dailyCardID)
        return DailyPublishResult(
            dailyCardID: dailyCardID,
            scheduledDate: "2026-07-20",
            publishedAt: "2026-07-18T08:00:00Z"
        )
    }
}

private actor MismatchDayPublishRepository: DayGenerationRepository {
    func publishDay(
        creatorID: UUID,
        dailyCardID: UUID,
        context: WorkspaceContext
    ) async throws -> DailyPublishResult {
        DailyPublishResult(
            dailyCardID: dailyCardID,
            scheduledDate: "2099-01-01",
            publishedAt: "2026-07-18T08:00:00Z"
        )
    }
}

private actor FailingDayPublishRepository: DayGenerationRepository {
    func publishDay(
        creatorID: UUID,
        dailyCardID: UUID,
        context: WorkspaceContext
    ) async throws -> DailyPublishResult {
        throw RepositoryError.edgeFunction("daily_card_not_publishable")
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

    func retiredFixturePublication(
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

private actor DailyGenerationPollingScript {
    enum Step: Sendable {
        case networkConnectionLost
        case acceptedRunNotFound
        case serverUnavailable
        case unauthorized
        case missingProviderConfiguration
        case running
        case completed
    }

    private var steps: [Step]
    private let running: SupabaseDailyGenerationInvocation
    private let completed: SupabaseDailyGenerationInvocation
    private(set) var invocationCount = 0

    init(
        steps: [Step],
        running: SupabaseDailyGenerationInvocation,
        completed: SupabaseDailyGenerationInvocation
    ) {
        self.steps = steps
        self.running = running
        self.completed = completed
    }

    func next() throws -> SupabaseDailyGenerationInvocation {
        invocationCount += 1
        let step = steps.isEmpty ? .completed : steps.removeFirst()

        switch step {
        case .networkConnectionLost:
            throw URLError(.networkConnectionLost)
        case .acceptedRunNotFound:
            throw FunctionsError.httpError(
                code: 404,
                data: Data(#"{"error":"invalid_generation_payload"}"#.utf8)
            )
        case .serverUnavailable:
            throw FunctionsError.httpError(
                code: 503,
                data: Data(#"{"error":"temporarily_unavailable"}"#.utf8)
            )
        case .unauthorized:
            throw FunctionsError.httpError(
                code: 401,
                data: Data(#"{"error":"invalid_device_session"}"#.utf8)
            )
        case .missingProviderConfiguration:
            throw FunctionsError.httpError(
                code: 500,
                data: Data(#"{"error":"missing_openai_api_key"}"#.utf8)
            )
        case .running:
            return running
        case .completed:
            return completed
        }
    }
}

private actor DailyGenerationPollingSleeper {
    private(set) var recordedNanoseconds: [UInt64] = []

    func record(_ nanoseconds: UInt64) {
        recordedNanoseconds.append(nanoseconds)
    }
}
