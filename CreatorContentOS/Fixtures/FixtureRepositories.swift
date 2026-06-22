import Foundation

struct FixtureTodayCardRepository: TodayCardRepository {
    func todayCard(for context: WorkspaceContext) async throws -> DailyCard {
        DailyCard.raceWeekToday
    }

    func weekCards(for context: WorkspaceContext) async throws -> [DailyCard] {
        DailyCard.weekFixtures
    }

    func completeToday(
        card: DailyCard,
        decision: DailyDecision,
        context: WorkspaceContext
    ) async throws -> ArchiveEntry {
        let archiveDate = card.scheduledDate ?? SupabaseDateFormatting.todayDateString()
        return ArchiveEntry(
            dailyCardID: card.id,
            day: SupabaseDateFormatting.weekdayAbbreviation(for: archiveDate),
            date: SupabaseDateFormatting.shortDate(for: archiveDate),
            cardTitle: card.title,
            decision: decision.completionState,
            outputLine: decision.outputLine,
            hasPostThumbnail: decision.hasPostThumbnail
        )
    }
}

actor FixtureWeeklyPlanRepository: WeeklyPlanRepository {
    private var plan: WeeklyPlan
    private var ideas: [WeeklyIdea]

    init(
        plan: WeeklyPlan = .raceWeek,
        ideas: [WeeklyIdea] = WeeklyIdea.raceWeekBank
    ) {
        self.plan = plan
        self.ideas = ideas
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

    func publishWeek(
        _ plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        generatedDraft: GeneratedWeekDraft?,
        context: WorkspaceContext
    ) async throws -> WeeklyPublishResult {
        let publishedPlan = if let generatedDraft, generatedDraft.weeklyPlanID == plan.id {
            generatedDraft.markedPublished.weeklyPlan(
                setupSections: plan.setupSections,
                weeklyBriefText: plan.weeklyBriefText
            ).softLockedForPublish
        } else {
            plan.softLockedForPublish
        }
        let cards = if let generatedDraft, generatedDraft.weeklyPlanID == plan.id {
            generatedDraft.markedPublished.publishedWeekCards
        } else {
            DailyCard.publishedCards(from: publishedPlan)
        }

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
        self.plan = updatedPlan
        self.ideas = updatedIdeaBank

        return WeeklySelectionUpdate(weeklyPlan: updatedPlan, ideaBank: updatedIdeaBank)
    }

    func updateWeeklySetupSections(
        _ sections: [WeeklySetupSection],
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        var updatedPlan = plan
        updatedPlan.setupSections = sections
        self.plan = updatedPlan
        return updatedPlan
    }

    func updateWeeklyBrief(
        _ text: String,
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        var updatedPlan = plan
        updatedPlan.weeklyBriefText = text
        self.plan = updatedPlan
        return updatedPlan
    }
}

struct FixtureWeeklyGenerationRepository: WeeklyGenerationRepository {
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
                generationID: nil,
                weeklyPlanID: nil,
                draftedDayCount: 7,
                checkedDayCount: 7,
                totalDayCount: 7,
                currentDay: nil,
                message: "Fixture draft generated",
                error: nil
            )
        )

        let cards = SupabaseDateFormatting.weekDates(starting: weekStartDate).enumerated().map { index, date in
            GeneratedDailyCardDraft(
                id: UUID(),
                scheduledDate: date,
                status: "draft",
                title: [
                    "Generated Monday reset",
                    "Generated training detail",
                    "Generated recovery check",
                    "Generated kit note",
                    "Generated calm reminder",
                    "Generated family walk",
                    "Generated caption backup"
                ][index],
                whyToday: "A fixture AI draft grounded in Creator's weekly rhythm.",
                growthJob: "Build consistency with practical fitness content.",
                contentPillar: index == 5 ? "family" : "routine",
                shootability: index == 6 ? "backup" : "easy",
                estimatedShootMinutes: index == 6 ? 6 : 12,
                energyRequired: index == 6 ? "low" : "medium",
                languageMode: "English with light Hinglish if natural",
                sceneList: [
                    ShotScene(number: 1, title: "Opening detail", duration: "3 sec", symbol: "sparkles"),
                    ShotScene(number: 2, title: "One steady movement", duration: "5 sec", symbol: "figure.run"),
                    ShotScene(number: 3, title: "Useful close", duration: "4 sec", symbol: "text.quote")
                ],
                script: "One useful detail is enough today. Keep it simple and steady.",
                noVoiceoverVersion: "Three quiet clips with simple on-screen text.",
                onScreenText: ["Simple today", "One useful detail", "Done"],
                caption: "Keeping it simple today. One useful detail, done properly.",
                cta: "Save this for a low-effort training day.",
                hashtags: ["routine", "fitnessover60"],
                coverText: "Simple today",
                postInstructions: "Use calm audio only if it fits.",
                brandEventNotes: "",
                backupStory: "A 10-second story with one detail and one line.",
                backupCaptionOnly: "Caption-only backup for a crowded day.",
                audioOptionNotes: "Calm fallback audio, or no audio dependency.",
                creatorFitScore: 88,
                riskNotes: [],
                assumptions: ["Fixture generation used deterministic local context."],
                sourceNote: "Fixture AI weekly generation."
            )
        }

        return GeneratedWeekDraft(
            id: UUID(),
            weeklyPlanID: UUID(),
            strategySummary: "Fixture AI draft: seven shootable Creator-safe cards for review.",
            warnings: [],
            assumptions: ["Fixture mode does not call AI services."],
            dailyCards: cards,
            ideaBank: [
                WeeklyIdea(
                    title: "Fixture caption-only backup",
                    reason: "Saved from fixture AI generation.",
                    source: .pattern,
                    effortLabel: "Easy"
                )
            ],
            sourceSummary: "Fixture profile, setup, references, archive, and idea bank.",
            generatedAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}

struct FixtureReferenceRepository: ReferenceRepository {
    func sourcePulse(for context: WorkspaceContext) async throws -> SourcePulseSummary {
        IntelligenceHome.raceWeekLibrary.sourcePulse
    }
}

struct FixtureIntelligenceRepository: IntelligenceRepository {
    func home(for context: WorkspaceContext) async throws -> IntelligenceHome {
        IntelligenceHome.raceWeekLibrary
    }
}

struct FixtureCreatorProfileRepository: CreatorProfileRepository {
    func activeProfileSummary(for context: WorkspaceContext) async throws -> CreatorProfileSummary {
        .creatorFixture
    }

    func updateProfile(_ update: CreatorProfileUpdate, context: WorkspaceContext) async throws -> CreatorProfileSummary {
        CreatorProfileSummary(
            displayName: CreatorProfileSummary.creatorFixture.displayName,
            positioning: update.positioning,
            voiceLine: update.voiceRules.joined(separator: ", "),
            noGoTopics: update.noGoTopics,
            voiceRules: update.voiceRules,
            contentPillars: update.contentPillars,
            captionStyle: update.captionStyle,
            recurringFormats: update.recurringFormats
        )
    }
}

struct FixtureArchiveRepository: ArchiveRepository {
    func entries(for context: WorkspaceContext) async throws -> [ArchiveEntry] {
        ArchiveEntry.fixtures
    }

    func upsertDecision(
        _ entry: ArchiveEntry,
        for card: DailyCard,
        context: WorkspaceContext
    ) async throws -> [ArchiveEntry] {
        var entries = ArchiveEntry.fixtures
        if let index = entries.firstIndex(where: { archiveEntry in
            archiveEntry.dailyCardID == card.id || archiveEntry.cardTitle == card.title
        }) {
            entries[index] = entry
        } else {
            entries.insert(entry, at: 0)
        }
        return entries
    }
}

struct FixtureTesterAccessRepository: TesterAccessRepository {
    func listTesters(context: WorkspaceContext) async throws -> [TesterAccessRecord] {
        [
            TesterAccessRecord(
                id: UUID(uuidString: "4A6E72A4-4450-44B3-A83B-A5EFB87F6301")!,
                email: "tester@example.com",
                displayName: "Fixture Tester",
                role: "editor",
                status: "active",
                createdAt: nil,
                updatedAt: nil
            )
        ]
    }

    func inviteTester(email: String, displayName: String?, context: WorkspaceContext) async throws -> TesterAccessRecord {
        TesterAccessRecord(
            id: UUID(),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            displayName: displayName?.nilIfBlank,
            role: "editor",
            status: "active",
            createdAt: nil,
            updatedAt: nil
        )
    }

    func resendTesterOTP(email: String, context: WorkspaceContext) async throws -> TesterAccessRecord {
        TesterAccessRecord(
            id: UUID(),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            displayName: nil,
            role: "editor",
            status: "active",
            createdAt: nil,
            updatedAt: nil
        )
    }

    func revokeTester(memberID: UUID, context: WorkspaceContext) async throws -> TesterAccessRecord {
        TesterAccessRecord(
            id: memberID,
            email: "revoked@example.com",
            displayName: nil,
            role: "editor",
            status: "revoked",
            createdAt: nil,
            updatedAt: nil
        )
    }
}
