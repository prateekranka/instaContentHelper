import XCTest
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
        XCTAssertEqual(object["generation_id"] as? String, generationID.uuidString)
        XCTAssertEqual(object["creator_id"] as? String, creatorID.uuidString)

        let responseData = Data(
            """
            {
              "generation_id": "\(generationID.uuidString)",
              "weekly_plan_id": null,
              "status": "running",
              "message": "generation_started",
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
                  "scene_list": [{"number":1,"title":"Shoes","duration":"3 sec","symbol":"shoeprints.fill"}],
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
                sceneList: [
                    ShotScene(number: 1, title: "Shoes", duration: "3 sec", symbol: "shoeprints.fill")
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

        XCTAssertEqual(object["script"] as? String, "Simple script.")
        XCTAssertEqual(object["no_voiceover_version"] as? String, "No VO.")
        XCTAssertEqual(object["on_screen_text"] as? [String], ["Simple"])
        XCTAssertEqual(object["caption"] as? String, "Simple caption.")
        XCTAssertEqual(object["cta"] as? String, "Save this.")
        XCTAssertEqual(object["hashtags"] as? [String], ["routine"])
        XCTAssertEqual(object["cover_text"] as? String, "Monday")
        XCTAssertEqual(postInstructions["line"] as? String, "Use calm audio.")
        XCTAssertEqual(postInstructions["audio_option_notes"] as? String, "Calm audio.")
        XCTAssertEqual(object["brand_event_notes"] as? String, "Event note.")
        XCTAssertEqual(backupStory["line"] as? String, "Story backup.")
        XCTAssertEqual(backupCaptionOnly["line"] as? String, "Caption backup.")
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
                "audio_option_notes": "Calm audio if available."
              },
              "brand_event_notes": "Brand note.",
              "backup_story": {"line": "Story backup."},
              "backup_caption_only": {"line": "Caption backup."},
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
    }

    func testAppServicesGenerationSuccessWithFixtureRepository() async throws {
        let services = AppServices.fixtureBacked(todayCache: GenerateWeekMemoryTodayCacheStore())

        let generatedDraft = await services.generateCurrentWeekImmediately()
        let draft = try XCTUnwrap(generatedDraft)

        XCTAssertEqual(services.latestGenerationSummary?.id, draft.id)
        XCTAssertEqual(services.weeklyPlan.id, draft.weeklyPlanID)
        XCTAssertEqual(services.weeklyPlan.days.count, 7)
        XCTAssertNil(services.generationError)
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
        XCTAssertEqual(services.generationError, "missing_openai_api_key")
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
        XCTAssertEqual(services.generationError, "existing_published_week_locked")
    }

    func testPublishingGeneratedDraftPreservesRichFieldsInFixtureModel() async throws {
        let services = AppServices.fixtureBacked(todayCache: GenerateWeekMemoryTodayCacheStore())
        let generatedDraft = await services.generateCurrentWeekImmediately()
        var draft = try XCTUnwrap(generatedDraft)
        draft.dailyCards[0].caption = "Edited generated caption."
        draft.dailyCards[0].backupStory = "Edited backup story."
        services.applyGeneratedDraft(draft)

        await services.publishCurrentWeekImmediately()

        XCTAssertEqual(services.weekCards.first?.caption, "Edited generated caption.")
        XCTAssertEqual(services.weekCards.first?.backupStory, "Edited backup story.")
        XCTAssertEqual(services.latestGenerationSummary?.status, "published")
        XCTAssertNil(services.lastRepositoryError)
    }
}

private struct FailingWeeklyGenerationRepository: WeeklyGenerationRepository {
    func generateWeek(
        creatorID: UUID,
        weekStartDate: String,
        weeklySetupID: UUID?,
        mode: GenerateWeekMode,
        context: WorkspaceContext
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
        context: WorkspaceContext
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
