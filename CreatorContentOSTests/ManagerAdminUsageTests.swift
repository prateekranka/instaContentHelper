import XCTest
@testable import CreatorContentOS

@MainActor
final class ManagerAdminUsageTests: XCTestCase {
    func testWeeklyDayDetailHeaderDateUsesFullReadableFormat() {
        let day = WeeklyDay(
            weekday: "SUN",
            date: "05",
            scheduledDate: "2026-07-05",
            title: "Sunday ritual",
            reason: "This rationale is not shown in the detail header.",
            source: .pattern,
            state: .planned,
            isSoftLocked: false
        )

        XCTAssertEqual(day.detailHeaderDateText, "Sunday, 05 July 2026")
    }

    func testFixtureNeedsReviewRowsAreActionable() throws {
        let needsReview = IntelligenceHome.raceWeekLibrary.needsReview

        XCTAssertFalse(needsReview.isEmpty)
        XCTAssertTrue(needsReview.allSatisfy { $0.reviewItem != nil })
        XCTAssertTrue(needsReview.contains { $0.typeChip == .reel && $0.sourceURL != nil })
        XCTAssertTrue(needsReview.contains { $0.typeChip == .unknown })
    }

    func testGrowthReferenceCatalogContainsCreatorSpecificInstagramPatterns() throws {
        let references = IntelligenceHome.raceWeekLibrary.growthReferences

        XCTAssertEqual(references.count, 6)
        XCTAssertTrue(references.contains { $0.id == "creator-age-myth-reversal" })
        XCTAssertTrue(references.contains { $0.id == "creator-real-life-contradiction-hook" })
        XCTAssertTrue(references.contains { $0.title == "Instagram Reels Default" })
        XCTAssertTrue(references.allSatisfy { !$0.hookFormulas.isEmpty })
        XCTAssertTrue(references.allSatisfy { !$0.sourceURLs.isEmpty })
        XCTAssertTrue(
            references.contains { reference in
                reference.hookFormulas.contains("I eat out. I drink sometimes. I still stay fit at 62.")
            }
        )
    }

    func testManagerSelectsIdeaForNextOpenDay() async throws {
        let weeklyRepository = RecordingWeeklyPlanRepository()
        let services = makeServices(weeklyPlans: weeklyRepository)

        let targetDay = try XCTUnwrap(services.nextOpenWeeklyDay)
        let idea = try XCTUnwrap(services.weeklyIdeas.first { $0.selectedDay == nil })

        await services.selectIdeaForNextOpenDayImmediately(idea)

        let requests = await weeklyRepository.recordedSelectionRequests()
        XCTAssertEqual(requests.map(\.ideaID), [idea.id])
        XCTAssertEqual(requests.map(\.weeklyPlanID), [services.weeklyPlan.id])

        let updatedDay = try XCTUnwrap(
            services.weeklyPlan.days.first { $0.weekday == targetDay.weekday }
        )
        XCTAssertEqual(updatedDay.title, idea.title)
        XCTAssertEqual(updatedDay.reason, idea.reason)
        XCTAssertEqual(updatedDay.source, idea.source)
        XCTAssertEqual(updatedDay.state, .planned)
        XCTAssertNil(services.nextOpenWeeklyDay)
        XCTAssertEqual(
            services.weeklyIdeas.first { $0.id == idea.id }?.selectedDay,
            targetDay.weekday
        )
        XCTAssertEqual(services.lastActionMessage, "Idea added to the next open day.")
        XCTAssertNil(services.lastRepositoryError)
    }

    func testWeeklyReadinessLineReflectsCurrentPlanState() async throws {
        let services = makeServices()

        XCTAssertEqual(services.weeklyPlan.computedReadinessLine, "4 ready, 2 backup, 1 open")

        let idea = try XCTUnwrap(services.weeklyIdeas.first { $0.selectedDay == nil })
        await services.selectIdeaForNextOpenDayImmediately(idea)

        XCTAssertEqual(services.weeklyPlan.computedReadinessLine, "5 ready, 2 backup, 0 open")
    }

    func testRepositoryRefreshUsesSingleWeeklyContentRead() async throws {
        let weeklyRepository = SingleFetchWeeklyPlanRepository()
        let services = makeServices(weeklyPlans: weeklyRepository)

        await services.refreshFromRepositoriesImmediately()

        let calls = await weeklyRepository.recordedCalls()
        XCTAssertEqual(calls, ["currentWeeklyContent"])
        XCTAssertEqual(services.weeklyPlan.title, "Combined weekly content")
        XCTAssertEqual(services.weeklyIdeas.map(\.title), ["Combined idea"])
        XCTAssertNil(services.lastRepositoryError)
    }

    func testManagerSeesErrorWhenIdeaSelectionFails() async throws {
        let weeklyRepository = RecordingWeeklyPlanRepository(
            selectionError: RepositoryError.notConfigured("Selection failed.")
        )
        let services = makeServices(weeklyPlans: weeklyRepository)
        let originalPlan = services.weeklyPlan
        let idea = try XCTUnwrap(services.weeklyIdeas.first { $0.selectedDay == nil })

        await services.selectIdeaForNextOpenDayImmediately(idea)

        XCTAssertEqual(services.weeklyPlan, originalPlan)
        XCTAssertEqual(services.lastRepositoryError, "Selection failed.")
    }

    // MARK: — Inline Retry

    func testRetryQueuedDayFromManagerInlineRetryUsesCentralizedService() async throws {
        let draft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: WorkspaceContext.creatorFixture.creatorID,
            weekStartDate: "2026-07-13",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: .creatorFixture,
            progress: nil
        )
        let failedDate = try XCTUnwrap(draft.dailyCards.first?.scheduledDate)
        let retryRepo = InlineRetryCompletesQueuedDayRepository(draft: draft)
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                weeklyGeneration: retryRepo,
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository()
            ),
            todayCache: AdminUsageMemoryTodayCacheStore()
        )
        services.applyGeneratedDraft(draft)
        services.weeklyGenerationProgress = WeeklyGenerationProgress(
            phase: .draftingDays,
            generationID: draft.id,
            weeklyPlanID: draft.weeklyPlanID,
            draftedDayCount: 7,
            checkedDayCount: 6,
            totalDayCount: 7,
            message: "generation_partial",
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

        XCTAssertNil(services.generationError,
                     "Retry via centralized service should clear generationError")
        XCTAssertEqual(services.weeklyGenerationProgress?.phase, .readyForReview,
                       "Retry should transition to ready for review")
    }

    func testInlineRetryPreventsDuplicateTapsWhileRetrying() async throws {
        let services = makeServices()
        let scheduledDate = "2026-06-01"

        services.regeneratingDayDates.insert(scheduledDate)

        do {
            try await services.retryQueuedGenerationDay(scheduledDate: scheduledDate)
            XCTFail("Should throw when day is already regenerating")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("generation_already_running") ||
                          error.localizedDescription.contains("generation_not_found"),
                          "Should reject duplicate retry")
        }
    }

    // MARK: — Manager Tab Bar

    func testManagerUpdatesWeeklySetupSections() async throws {
        let weeklyRepository = RecordingWeeklyPlanRepository()
        let services = makeServices(weeklyPlans: weeklyRepository)
        var updatedSections = services.weeklyPlan.setupSections
        updatedSections[0].summary = "Jersey City, early mornings."
        updatedSections[0].state = "Ready"

        let didSave = await services.updateWeeklySetupSectionsImmediately(updatedSections)

        XCTAssertTrue(didSave)
        XCTAssertEqual(services.weeklyPlan.setupSections, updatedSections)
        XCTAssertFalse(services.isSavingWeeklyBrief)
        XCTAssertNil(services.weeklyBriefEditError)
        XCTAssertNil(services.lastRepositoryError)
        XCTAssertEqual(services.lastActionMessage, "Weekly brief saved.")

        let requests = await weeklyRepository.recordedSetupRequests()
        XCTAssertEqual(requests, [updatedSections])
    }

    func testManagerKeepsWeeklySetupSectionsWhenSaveFails() async throws {
        let weeklyRepository = RecordingWeeklyPlanRepository(
            setupError: RepositoryError.edgeFunction("weekly_setup_update_failed")
        )
        let services = makeServices(weeklyPlans: weeklyRepository)
        let originalSections = services.weeklyPlan.setupSections
        var updatedSections = originalSections
        updatedSections[0].summary = "Jersey City, early mornings."

        let didSave = await services.updateWeeklySetupSectionsImmediately(updatedSections)

        XCTAssertFalse(didSave)
        XCTAssertEqual(services.weeklyPlan.setupSections, originalSections)
        XCTAssertFalse(services.isSavingWeeklyBrief)
        XCTAssertEqual(services.weeklyBriefEditError, "weekly_setup_update_failed")
        XCTAssertEqual(services.lastRepositoryError, "weekly_setup_update_failed")
    }

    func testWeeklyStartDateSetsSevenDayWindow() async throws {
        let services = makeServices()

        services.updateWeeklyStartDate("2026-07-13")

        XCTAssertEqual(services.weeklyPlan.weekStartDate, "2026-07-13")
        XCTAssertEqual(services.weeklyPlan.weekEndDate, "2026-07-19")
        XCTAssertEqual(services.weeklyPlan.weekRange, "13 Jul - 19 Jul")
    }

    func testWeeklyStartDatePreservesOverlappingGeneratedCardsByScheduledDate() async throws {
        let services = makeServices(todayDate: { "2026-07-02" })
        let existingDraft = try await TestWeeklyGenerationRepository().generateWeek(
            creatorID: services.context.creatorID,
            weekStartDate: "2026-06-30",
            weeklySetupID: nil,
            mode: .generateDraft,
            context: services.context,
            progress: nil
        )
        services.applyGeneratedDraft(existingDraft)

        services.updateWeeklyStartDate("2026-07-02")

        XCTAssertEqual(
            services.weeklyPlan.days.compactMap(\.scheduledDate),
            [
                "2026-07-02",
                "2026-07-03",
                "2026-07-04",
                "2026-07-05",
                "2026-07-06",
                "2026-07-07",
                "2026-07-08"
            ]
        )
        XCTAssertEqual(
            services.latestGenerationSummary?.dailyCards.map(\.scheduledDate),
            [
                "2026-07-02",
                "2026-07-03",
                "2026-07-04",
                "2026-07-05",
                "2026-07-06"
            ]
        )

        for date in ["2026-07-02", "2026-07-03", "2026-07-04", "2026-07-05", "2026-07-06"] {
            let day = try XCTUnwrap(services.weeklyPlan.days.first { $0.scheduledDate == date })
            XCTAssertNotEqual(day.title, "Open")
            XCTAssertEqual(services.generatedDailyCard(for: day)?.scheduledDate, date)
        }

        for date in ["2026-07-07", "2026-07-08"] {
            let day = try XCTUnwrap(services.weeklyPlan.days.first { $0.scheduledDate == date })
            XCTAssertEqual(day.title, "Open")
            XCTAssertNil(services.generatedDailyCard(for: day))
        }
    }

    func testUpdateWeeklyStartDateRejectsPastDate() async throws {
        let services = makeServices()

        services.updateWeeklyStartDate("2026-05-31")

        XCTAssertNotEqual(services.weeklyPlan.weekStartDate, "2026-05-31")
        XCTAssertEqual(services.generationError, "past_generation_date_not_allowed")
    }

    func testUpdateWeeklyStartDateAcceptsToday() async throws {
        let services = makeServices()

        services.updateWeeklyStartDate("2026-06-01")

        XCTAssertEqual(services.weeklyPlan.weekStartDate, "2026-06-01")
        XCTAssertNil(services.generationError)
    }

    func testRegenerateDailyCardRejectsPastDate() async throws {
        let services = makeServices()

        do {
            _ = try await services.regeneratedDailyCard(scheduledDate: "2026-05-30", preserveManualEdits: false)
            XCTFail("Expected past_generation_date_not_allowed error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("past_generation_date_not_allowed"))
        }
    }

    func testRetryQueuedGenerationDayRejectsPastDate() async throws {
        let services = makeServices()

        do {
            try await services.retryQueuedGenerationDay(scheduledDate: "2026-05-30")
            XCTFail("Expected past_generation_date_not_allowed error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("past_generation_date_not_allowed"))
        }
    }

    func testRegenerateDailyCardAcceptsToday() async throws {
        let services = makeServices()

        do {
            _ = try await services.regeneratedDailyCard(scheduledDate: "2026-06-01", preserveManualEdits: false)
            XCTFail("Expected repository error (regeneration not configured), not past-date guard")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains("past_generation_date_not_allowed"),
                           "Should pass the past-date guard and reach repository")
        }
    }

    func testRetryQueuedDayAcceptsToday() async throws {
        let services = makeServices()

        services.weeklyGenerationProgress = WeeklyGenerationProgress(
            phase: .draftingDays,
            generationID: UUID(),
            weeklyPlanID: services.weeklyPlan.id,
            draftedDayCount: 0,
            checkedDayCount: 0,
            totalDayCount: 7
        )

        do {
            try await services.retryQueuedGenerationDay(scheduledDate: "2026-06-01")
            XCTFail("Expected repository error (retry not configured), not past-date guard")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains("past_generation_date_not_allowed"),
                           "Should pass the past-date guard and reach repository")
        }
    }

    func testWorkflowStatusIsPublishedOnlyForSelectedPublishedWeek() async throws {
        let status = WeeklyWorkflowWindowStatus(
            plan: WeeklyPlan.raceWeek.softLockedForPublish,
            startDate: "2026-06-01",
            endDate: "2026-06-07"
        )

        XCTAssertEqual(status, .published)
        XCTAssertEqual(status.tone, .ready)
    }

    func testWorkflowStatusIsPlannedWhenSelectedWeekHasPlannedContent() async throws {
        let status = WeeklyWorkflowWindowStatus(
            plan: WeeklyPlan.raceWeek,
            startDate: "2026-06-01",
            endDate: "2026-06-07"
        )

        XCTAssertEqual(status, .planned)
        XCTAssertEqual(status.tone, .warning)
    }

    func testWorkflowStatusDoesNotPublishDifferentSelectedWeek() async throws {
        let status = WeeklyWorkflowWindowStatus(
            plan: WeeklyPlan.raceWeek.softLockedForPublish,
            startDate: "2026-07-13",
            endDate: "2026-07-19"
        )

        XCTAssertEqual(status, .draft)
        XCTAssertEqual(status.tone, .info)
    }

    func testManagerUpdatesCreatorProfileOutsideWeeklySetup() async throws {
        let profileRepository = RecordingCreatorProfileRepository()
        let services = makeServices(creatorProfile: profileRepository)
        let update = CreatorProfileUpdate(
            positioning: "Lifestyle creator voice for busy weeks.",
            voiceRules: ["Warm", "Direct", "Light Hinglish when natural"],
            contentPillars: ["gym", "lifestyle", "eating", "recovery"],
            captionStyle: "Short and useful.",
            noGoTopics: ["Politics", "Weight talk"],
            recurringFormats: ["one practical detail", "caption-only backup"]
        )

        let didSave = await services.updateCreatorProfileImmediately(update)

        XCTAssertTrue(didSave)
        XCTAssertEqual(services.creatorProfileSummary.positioning, update.positioning)
        XCTAssertEqual(services.creatorProfileSummary.voiceRules, update.voiceRules)
        XCTAssertEqual(services.creatorProfileSummary.contentPillars, update.contentPillars)
        XCTAssertEqual(services.creatorProfileSummary.captionStyle, update.captionStyle)
        XCTAssertEqual(services.creatorProfileSummary.noGoTopics, update.noGoTopics)
        XCTAssertEqual(services.creatorProfileSummary.recurringFormats, update.recurringFormats)
        XCTAssertEqual(services.lastActionMessage, "Creator profile saved.")
        XCTAssertNil(services.creatorProfileEditError)

        let updates = await profileRepository.recordedUpdates()
        XCTAssertEqual(updates, [update])
    }

    func testManagerReferenceImportPreviewAndConfirmRefreshesIntelligence() async throws {
        let refreshedHome = IntelligenceHome.adminUsageReviewCleared
        let importRepository = RecordingReferenceImportRepository()
        let intelligenceRepository = RecordingIntelligenceRepository(home: refreshedHome)
        let services = makeServices(
            referenceImport: importRepository,
            intelligence: intelligenceRepository,
            isLiveSupabaseRuntime: true
        )
        let rawText = """
        @fitover60
        https://www.instagram.com/reel/ABC123/
        post-run family moment
        """

        let preview = await services.previewReferenceImportImmediately(
            rawText: rawText,
            inputType: .paste
        )

        XCTAssertEqual(preview?.previewChecksum, "fixture")
        XCTAssertEqual(services.referenceImportPreview?.counts.importable, 6)
        XCTAssertNil(services.lastReferenceImportError)

        let result = await services.confirmReferenceImportImmediately(
            rawText: rawText,
            inputType: .paste,
            previewChecksum: "fixture"
        )

        XCTAssertEqual(result?.counts.imported, 5)
        XCTAssertEqual(result?.counts.needsReview, 1)
        XCTAssertEqual(services.referenceImportConfirmResult?.toast, "Imported 5. 1 needs review.")
        XCTAssertEqual(services.referenceImportToast, "Imported 5. 1 needs review.")
        XCTAssertEqual(services.lastActionMessage, "Imported 5. 1 needs review.")
        XCTAssertEqual(services.intelligenceHome, refreshedHome)
        XCTAssertNil(services.lastReferenceImportError)

        let previewRequests = await importRepository.recordedPreviewRequests()
        XCTAssertEqual(previewRequests.map(\.rawText), [rawText])
        XCTAssertEqual(previewRequests.map(\.inputType), [.paste])

        let confirmRequests = await importRepository.recordedConfirmRequests()
        XCTAssertEqual(confirmRequests.map(\.previewChecksum), ["fixture"])
        let homeCallCount = await intelligenceRepository.homeCallCount()
        XCTAssertEqual(homeCallCount, 1)
    }

    func testReferenceImportPreviewMapsRowLimitError() async {
        let importRepository = RecordingReferenceImportRepository(
            previewError: RepositoryError.edgeFunction("row_limit_exceeded")
        )
        let services = makeServices(
            referenceImport: importRepository,
            isLiveSupabaseRuntime: true
        )

        let preview = await services.previewReferenceImportImmediately(
            rawText: "@creator",
            inputType: .paste
        )

        XCTAssertNil(preview)
        XCTAssertNil(services.referenceImportPreview)
        XCTAssertEqual(
            services.lastReferenceImportError,
            "This import is too large. Split it into smaller batches and try again."
        )
        XCTAssertNil(services.referenceImportToast)
    }

    func testReferenceImportConfirmMapsChecksumMismatchError() async {
        let importRepository = RecordingReferenceImportRepository(
            confirmError: RepositoryError.edgeFunction("checksum_mismatch")
        )
        let intelligenceRepository = RecordingIntelligenceRepository(home: .adminUsageReviewCleared)
        let services = makeServices(
            referenceImport: importRepository,
            intelligence: intelligenceRepository,
            isLiveSupabaseRuntime: true
        )

        let result = await services.confirmReferenceImportImmediately(
            rawText: "@creator",
            inputType: .paste,
            previewChecksum: "stale"
        )

        XCTAssertNil(result)
        XCTAssertNil(services.referenceImportConfirmResult)
        XCTAssertEqual(services.lastReferenceImportError, "The import changed. Preview it again before saving.")
        XCTAssertNil(services.referenceImportToast)
        let homeCallCount = await intelligenceRepository.homeCallCount()
        XCTAssertEqual(homeCallCount, 0)
    }

    func testManagerReviewsNeedsYourCallItemAndHomeRefreshes() async throws {
        let reviewItemID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        let importRepository = RecordingReferenceImportRepository()
        let intelligenceRepository = RecordingIntelligenceRepository(home: .adminUsageReviewCleared)
        let services = makeServices(
            referenceImport: importRepository,
            intelligence: intelligenceRepository,
            isLiveSupabaseRuntime: true
        )
        let edit = ReferenceReviewEdit(
            targetType: .reel,
            handle: nil,
            url: "https://www.instagram.com/reel/ABC123/",
            notes: "Good race-week pattern."
        )

        let result = await services.reviewReferenceItemImmediately(
            ReferenceReviewRequest(
                item: ReferenceReviewItem(kind: .sourceReference, id: reviewItemID),
                action: .edit,
                edit: edit
            )
        )

        XCTAssertEqual(result?.itemID, reviewItemID)
        XCTAssertEqual(result?.action, .edit)
        XCTAssertEqual(result?.resultStatus, "confirmed")
        XCTAssertEqual(services.referenceReviewResult?.toast, "Reference confirmed.")
        XCTAssertEqual(services.referenceImportToast, "Reference confirmed.")
        XCTAssertEqual(services.lastActionMessage, "Reference confirmed.")
        XCTAssertEqual(services.intelligenceHome.needsReview, [])
        XCTAssertNil(services.lastReferenceImportError)

        let reviewRequests = await importRepository.recordedReviewRequests()
        XCTAssertEqual(reviewRequests.map(\.item.id), [reviewItemID])
        XCTAssertEqual(reviewRequests.map(\.action), [.edit])
        XCTAssertEqual(reviewRequests.map(\.edit), [edit])
        let homeCallCount = await intelligenceRepository.homeCallCount()
        XCTAssertEqual(homeCallCount, 1)
    }

    func testReferenceReviewMapsStoryURLRejection() async {
        let importRepository = RecordingReferenceImportRepository(
            reviewError: RepositoryError.edgeFunction("story_urls_not_allowed")
        )
        let intelligenceRepository = RecordingIntelligenceRepository(home: .adminUsageReviewCleared)
        let services = makeServices(
            referenceImport: importRepository,
            intelligence: intelligenceRepository,
            isLiveSupabaseRuntime: true
        )

        let result = await services.reviewReferenceItemImmediately(
            ReferenceReviewRequest(
                item: ReferenceReviewItem(
                    kind: .sourceReference,
                    id: UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!
                ),
                action: .edit,
                edit: ReferenceReviewEdit(
                    targetType: .reel,
                    handle: nil,
                    url: "https://www.instagram.com/stories/example/1/",
                    notes: nil
                )
            )
        )

        XCTAssertNil(result)
        XCTAssertNil(services.referenceReviewResult)
        XCTAssertEqual(
            services.lastReferenceImportError,
            "Story URLs cannot be used as references. Add a reel, post, audio link, or account instead."
        )
        XCTAssertNil(services.referenceImportToast)
        let homeCallCount = await intelligenceRepository.homeCallCount()
        XCTAssertEqual(homeCallCount, 0)
    }

    func testTesterAccessRequiresLiveOwnerRuntime() {
        XCTAssertFalse(makeServices().canManageTesterAccess)
        XCTAssertFalse(makeServices(isLiveSupabaseRuntime: true, memberRole: "editor").canManageTesterAccess)
        XCTAssertTrue(makeServices(isLiveSupabaseRuntime: true, memberRole: "owner").canManageTesterAccess)
    }

    // MARK: — Working Plan Visibility

    func testWeeklyRepositoryContentDistinguishesPublishedFromWorkingPlan() async throws {
        let publishedPlan = WeeklyPlan.raceWeek
        let draft = GeneratedWeekDraft(
            id: UUID(),
            weeklyPlanID: UUID(),
            status: "draft",
            strategySummary: "Working draft.",
            warnings: [],
            assumptions: [],
            dailyCards: [
                GeneratedDailyCardDraft(
                    id: UUID(),
                    scheduledDate: "2026-07-13",
                    status: "draft",
                    title: "Working Monday",
                    whyToday: "Test.",
                    growthJob: "Consistency.",
                    contentPillar: "lifestyle",
                    shootability: "easy",
                    estimatedShootMinutes: 10,
                    energyRequired: "low",
                    languageMode: "English",
                    sceneList: [],
                    script: "",
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
            ],
            ideaBank: [],
            sourceSummary: "Test.",
            generatedAt: "2026-07-13T00:00:00Z"
        )

        let repository = WorkingPlanVisibilityWeeklyPlanRepository(
            publishedPlan: publishedPlan,
            workingDraft: draft,
            weekStartDate: "2026-07-13"
        )

        let content = try await repository.currentWeeklyContent(for: .creatorFixture)

        XCTAssertNotNil(content.workingPlan, "Working plan should be present when draft exists")
        XCTAssertEqual(content.publishedPlan.id, publishedPlan.id)
        XCTAssertEqual(content.workingPlan?.id, draft.weeklyPlanID)
        XCTAssertNotEqual(content.publishedPlan.id, content.workingPlan?.id,
                          "Published and working plans should have distinct IDs")
        XCTAssertEqual(content.generatedDraft?.id, draft.id)
    }

    func testWeeklyRepositoryContentHasNoWorkingPlanWhenNoDraft() async throws {
        let publishedPlan = WeeklyPlan.raceWeek
        let repository = WorkingPlanVisibilityWeeklyPlanRepository(
            publishedPlan: publishedPlan,
            workingDraft: nil,
            weekStartDate: nil
        )

        let content = try await repository.currentWeeklyContent(for: .creatorFixture)

        XCTAssertNil(content.workingPlan, "Working plan should be nil when no draft exists")
        XCTAssertNil(content.generatedDraft)
        XCTAssertEqual(content.publishedPlan.id, publishedPlan.id)
    }

    private func makeServices(
        weeklyPlans: any WeeklyPlanRepository = RecordingWeeklyPlanRepository(),
        weeklyGeneration: any WeeklyGenerationRepository = AppFixtureWeeklyGenerationUnavailableRepository(),
        referenceImport: any ReferenceImportRepository = RecordingReferenceImportRepository(),
        intelligence: any IntelligenceRepository = FixtureIntelligenceRepository(),
        creatorProfile: any CreatorProfileRepository = FixtureCreatorProfileRepository(),
        isLiveSupabaseRuntime: Bool = false,
        memberRole: String = "owner",
        todayDate: @escaping TodayDateProvider = { "2026-06-01" }
    ) -> AppServices {
        let repositories = AppRepositories(
            context: .creatorFixture,
            today: FixtureTodayCardRepository(),
            weeklyPlans: weeklyPlans,
            references: FixtureReferenceRepository(),
            referenceImport: referenceImport,
            weeklyGeneration: weeklyGeneration,
            intelligence: intelligence,
            creatorProfile: creatorProfile,
            archive: FixtureArchiveRepository()
        )

        return AppServices.fixtureBacked(
            repositories: repositories,
            isLiveSupabaseRuntime: isLiveSupabaseRuntime,
            memberRole: memberRole,
            todayCache: AdminUsageMemoryTodayCacheStore(),
            notifications: NoopTodayNotificationScheduler(),
            todayDate: todayDate
        )
    }
}

private struct SelectionRequest: Hashable, Sendable {
    var ideaID: UUID
    var weeklyPlanID: UUID
}

private actor RecordingWeeklyPlanRepository: WeeklyPlanRepository {
    private var plan: WeeklyPlan
    private var ideas: [WeeklyIdea]
    private var selectionRequests: [SelectionRequest] = []
    private var setupRequests: [[WeeklySetupSection]] = []
    private var briefRequests: [String] = []
    private let selectionError: Error?
    private let setupError: Error?
    private let briefError: Error?

    init(
        plan: WeeklyPlan = .raceWeek,
        ideas: [WeeklyIdea] = WeeklyIdea.raceWeekBank,
        selectionError: Error? = nil,
        setupError: Error? = nil,
        briefError: Error? = nil
    ) {
        self.plan = plan
        self.ideas = ideas
        self.selectionError = selectionError
        self.setupError = setupError
        self.briefError = briefError
    }

    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan {
        plan
    }

    func currentGeneratedDraft(for context: WorkspaceContext) async throws -> GeneratedWeekDraft? {
        nil
    }

    func ideaBank(for context: WorkspaceContext) async throws -> [WeeklyIdea] {
        ideas
    }

    func currentWeeklyContent(for context: WorkspaceContext) async throws -> WeeklyRepositoryContent {
        WeeklyRepositoryContent(
            publishedPlan: plan,
            generatedDraft: nil,
            ideaBank: ideas
        )
    }

    func publishWeek(
        _ plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        generatedDraft: GeneratedWeekDraft?,
        context: WorkspaceContext
    ) async throws -> WeeklyPublishResult {
        let publishedPlan = plan.softLockedForPublish
        let cards = DailyCard.publishedCards(from: publishedPlan)
        self.plan = publishedPlan
        self.ideas = ideaBank

        return WeeklyPublishResult(
            weeklyPlan: publishedPlan,
            weekCards: cards,
            todayCard: DailyCard.bestTodayCard(from: cards),
            summary: "Published \(cards.count) cards to Creator Today."
        )
    }

    func selectIdeaForNextOpenDay(
        _ idea: WeeklyIdea,
        in plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        context: WorkspaceContext
    ) async throws -> WeeklySelectionUpdate {
        selectionRequests.append(
            SelectionRequest(ideaID: idea.id, weeklyPlanID: plan.id)
        )

        if let selectionError {
            throw selectionError
        }

        let update = Self.applySelection(idea, in: plan, ideaBank: ideaBank)
        self.plan = update.weeklyPlan
        self.ideas = update.ideaBank
        return update
    }

    func recordedSelectionRequests() -> [SelectionRequest] {
        selectionRequests
    }

    func updateWeeklySetupSections(
        _ sections: [WeeklySetupSection],
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        setupRequests.append(sections)

        if let setupError {
            throw setupError
        }

        var updatedPlan = plan
        updatedPlan.setupSections = sections
        self.plan = updatedPlan
        return updatedPlan
    }

    func recordedSetupRequests() -> [[WeeklySetupSection]] {
        setupRequests
    }

    func updateWeeklyBrief(
        _ text: String,
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        briefRequests.append(text)

        if let briefError {
            throw briefError
        }

        var updatedPlan = plan
        updatedPlan.weeklyBriefText = text
        self.plan = updatedPlan
        return updatedPlan
    }

    func recordedBriefRequests() -> [String] {
        briefRequests
    }

    private static func applySelection(
        _ idea: WeeklyIdea,
        in plan: WeeklyPlan,
        ideaBank: [WeeklyIdea]
    ) -> WeeklySelectionUpdate {
        var updatedPlan = plan
        var updatedIdeaBank = ideaBank

        guard
            let ideaIndex = updatedIdeaBank.firstIndex(where: { $0.id == idea.id }),
            let dayIndex = updatedPlan.days.firstIndex(where: { $0.state == .open })
        else {
            return WeeklySelectionUpdate(weeklyPlan: updatedPlan, ideaBank: updatedIdeaBank)
        }

        updatedPlan.days[dayIndex].title = idea.title
        updatedPlan.days[dayIndex].reason = idea.reason
        updatedPlan.days[dayIndex].source = idea.source
        updatedPlan.days[dayIndex].state = .planned
        updatedPlan.days[dayIndex].isSoftLocked = false
        updatedIdeaBank[ideaIndex].selectedDay = updatedPlan.days[dayIndex].weekday

        return WeeklySelectionUpdate(weeklyPlan: updatedPlan, ideaBank: updatedIdeaBank)
    }
}

private actor SingleFetchWeeklyPlanRepository: WeeklyPlanRepository {
    private var calls: [String] = []

    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan {
        calls.append("currentPublishedPlan")
        throw RepositoryError.notConfigured("legacy published read should not be used")
    }

    func currentGeneratedDraft(for context: WorkspaceContext) async throws -> GeneratedWeekDraft? {
        calls.append("currentGeneratedDraft")
        throw RepositoryError.notConfigured("legacy generated draft read should not be used")
    }

    func ideaBank(for context: WorkspaceContext) async throws -> [WeeklyIdea] {
        calls.append("ideaBank")
        throw RepositoryError.notConfigured("legacy idea bank read should not be used")
    }

    func currentWeeklyContent(for context: WorkspaceContext) async throws -> WeeklyRepositoryContent {
        calls.append("currentWeeklyContent")
        var plan = WeeklyPlan.raceWeek
        plan.title = "Combined weekly content"
        return WeeklyRepositoryContent(
            publishedPlan: plan,
            generatedDraft: nil,
            ideaBank: [
                WeeklyIdea(
                    title: "Combined idea",
                    reason: "Loaded through the single weekly content read.",
                    source: .routine,
                    effortLabel: "Easy"
                )
            ]
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

    func recordedCalls() -> [String] {
        calls
    }
}

private actor RecordingCreatorProfileRepository: CreatorProfileRepository {
    private var summary: CreatorProfileSummary
    private var updates: [CreatorProfileUpdate] = []
    private let error: Error?

    init(
        summary: CreatorProfileSummary = .creatorFixture,
        error: Error? = nil
    ) {
        self.summary = summary
        self.error = error
    }

    func activeProfileSummary(for context: WorkspaceContext) async throws -> CreatorProfileSummary {
        summary
    }

    func updateProfile(_ update: CreatorProfileUpdate, context: WorkspaceContext) async throws -> CreatorProfileSummary {
        updates.append(update)

        if let error {
            throw error
        }

        summary = CreatorProfileSummary(
            displayName: summary.displayName,
            positioning: update.positioning,
            voiceLine: update.voiceRules.joined(separator: ", "),
            noGoTopics: update.noGoTopics,
            voiceRules: update.voiceRules,
            contentPillars: update.contentPillars,
            captionStyle: update.captionStyle,
            recurringFormats: update.recurringFormats
        )
        return summary
    }

    func recordedUpdates() -> [CreatorProfileUpdate] {
        updates
    }
}

private struct PreviewRequest: Hashable, Sendable {
    var rawText: String
    var inputType: ReferenceImportInputType
    var filename: String?
}

private struct ConfirmRequest: Hashable, Sendable {
    var rawText: String
    var inputType: ReferenceImportInputType
    var filename: String?
    var previewChecksum: String
}

private actor RecordingReferenceImportRepository: ReferenceImportRepository {
    private var previewRequests: [PreviewRequest] = []
    private var confirmRequests: [ConfirmRequest] = []
    private var reviewRequests: [ReferenceReviewRequest] = []
    private let previewError: Error?
    private let confirmError: Error?
    private let reviewError: Error?

    init(
        previewError: Error? = nil,
        confirmError: Error? = nil,
        reviewError: Error? = nil
    ) {
        self.previewError = previewError
        self.confirmError = confirmError
        self.reviewError = reviewError
    }

    func previewImport(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String?,
        context: WorkspaceContext
    ) async throws -> ReferenceImportPreview {
        previewRequests.append(
            PreviewRequest(rawText: rawText, inputType: inputType, filename: filename)
        )
        if let previewError {
            throw previewError
        }
        return .referenceImportFixture
    }

    func confirmImport(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String?,
        previewChecksum: String,
        context: WorkspaceContext
    ) async throws -> ReferenceImportConfirmResult {
        confirmRequests.append(
            ConfirmRequest(
                rawText: rawText,
                inputType: inputType,
                filename: filename,
                previewChecksum: previewChecksum
            )
        )
        if let confirmError {
            throw confirmError
        }
        return ReferenceImportConfirmResult(
            parserVersion: "v1",
            destination: ReferenceImportDestination(watchlistID: nil, watchlistName: "Inspiration"),
            counts: ReferenceImportConfirmCounts(
                imported: 5,
                needsReview: 1,
                duplicatesSkipped: 1,
                invalid: 1
            ),
            toast: "Imported 5. 1 needs review."
        )
    }

    func reviewItem(
        _ request: ReferenceReviewRequest,
        context: WorkspaceContext
    ) async throws -> ReferenceReviewResult {
        reviewRequests.append(request)
        if let reviewError {
            throw reviewError
        }
        return ReferenceReviewResult(
            itemID: request.item.id,
            kind: request.item.kind,
            action: request.action,
            resultStatus: "confirmed",
            toast: "Reference confirmed."
        )
    }

    func recordedPreviewRequests() -> [PreviewRequest] {
        previewRequests
    }

    func recordedConfirmRequests() -> [ConfirmRequest] {
        confirmRequests
    }

    func recordedReviewRequests() -> [ReferenceReviewRequest] {
        reviewRequests
    }
}

private actor RecordingIntelligenceRepository: IntelligenceRepository {
    private let home: IntelligenceHome
    private var calls = 0

    init(home: IntelligenceHome) {
        self.home = home
    }

    func home(for context: WorkspaceContext) async throws -> IntelligenceHome {
        calls += 1
        return home
    }

    func homeCallCount() -> Int {
        calls
    }
}

private final class AdminUsageMemoryTodayCacheStore: TodayCacheStoring {
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

private extension IntelligenceHome {
    static var adminUsageReviewCleared: IntelligenceHome {
        IntelligenceHome(
            sourcePulse: SourcePulseSummary(
                title: "Source Pulse",
                subtitle: "1 confirmed reel/audio reference.",
                references: [
                    ReferenceSummary(
                        title: "Race week warmup reel",
                        sourceType: "Reel link",
                        note: "Confirmed",
                        state: .approved,
                        symbol: "link",
                        sourceURL: "https://www.instagram.com/reel/ABC123/"
                    )
                ]
            ),
            readyForThisWeek: IntelligenceHome.raceWeekLibrary.readyForThisWeek,
            needsReview: [],
            ideaCandidates: IntelligenceHome.raceWeekLibrary.ideaCandidates,
            recentlyUsed: IntelligenceHome.raceWeekLibrary.recentlyUsed,
            librarySections: IntelligenceHome.raceWeekLibrary.librarySections
        )
    }
}

private actor WorkingPlanVisibilityWeeklyPlanRepository: WeeklyPlanRepository {
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
        []
    }

    func currentWeeklyContent(for context: WorkspaceContext) async throws -> WeeklyRepositoryContent {
        let workingPlan = WeeklyRepositoryContent.makeWorkingPlan(
            from: workingDraft,
            weekStartDate: weekStartDate,
            setupSections: publishedPlan.setupSections,
            weeklyBriefText: publishedPlan.weeklyBriefText
        )
        return WeeklyRepositoryContent(
            publishedPlan: publishedPlan,
            workingPlan: workingPlan,
            generatedDraft: workingDraft,
            ideaBank: []
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

private actor InlineRetryCompletesQueuedDayRepository: WeeklyGenerationRepository {
    let draft: GeneratedWeekDraft

    init(draft: GeneratedWeekDraft) {
        self.draft = draft
    }

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

    func cancelGeneration(generationID: UUID, context: WorkspaceContext) async throws {}
}
