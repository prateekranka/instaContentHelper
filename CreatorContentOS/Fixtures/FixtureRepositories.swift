import Foundation

/// Keeps the fixture today and weekly repositories on the same published content.
actor FixturePublishedContentStore {
    private var weekCards: [DailyCard] = []
    private var todayCard: DailyCard?

    func readWeekCards() -> [DailyCard] {
        weekCards
    }

    func readTodayCard() -> DailyCard? {
        todayCard
    }

    func savePublishedContent(cards: [DailyCard], todayCard: DailyCard?) {
        self.weekCards = cards
        self.todayCard = todayCard
    }
}

struct FixtureTodayCardRepository: TodayCardRepository {
    let publishedStore: FixturePublishedContentStore?

    init(publishedStore: FixturePublishedContentStore? = nil) {
        self.publishedStore = publishedStore
    }

    func todayCard(for context: WorkspaceContext) async throws -> DailyCard {
        if let publishedCard = await publishedStore?.readTodayCard() {
            return publishedCard
        }
        return DailyCard.raceWeekToday
    }

    func weekCards(for context: WorkspaceContext) async throws -> [DailyCard] {
        if let store = publishedStore {
            let publishedCards = await store.readWeekCards()
            if !publishedCards.isEmpty {
                return publishedCards
            }
        }
        return DailyCard.weekFixtures
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
    private let publishedStore: FixturePublishedContentStore?

    init(
        plan: WeeklyPlan = .raceWeek,
        ideas: [WeeklyIdea] = WeeklyIdea.raceWeekBank,
        publishedStore: FixturePublishedContentStore? = nil
    ) {
        self.plan = plan
        self.ideas = ideas
        self.publishedStore = publishedStore
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

        let todayCard = DailyCard.bestTodayCard(from: cards)
        await publishedStore?.savePublishedContent(cards: cards, todayCard: todayCard)

        return WeeklyPublishResult(
            weeklyPlan: publishedPlan,
            weekCards: cards,
            todayCard: todayCard,
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

    func updateDailyCardReviewState(
        dailyCardID: UUID,
        reviewState: String,
        context: WorkspaceContext
    ) async throws {
        guard var currentPlan = try? await currentPublishedPlan(for: context) else { return }
        guard let dayIndex = currentPlan.days.firstIndex(where: { $0.id == dailyCardID }) else { return }
        let newState = WeeklyDayState(reviewState: reviewState)
        currentPlan.days[dayIndex].state = newState
        self.plan = currentPlan
    }
}

struct AppFixtureWeeklyGenerationUnavailableRepository: WeeklyGenerationRepository {
    func generateWeek(
        creatorID: UUID,
        weekStartDate: String,
        weeklySetupID: UUID?,
        mode: GenerateWeekMode,
        context: WorkspaceContext,
        progress: WeeklyGenerationProgressHandler?
    ) async throws -> GeneratedWeekDraft {
        throw RepositoryError.notConfigured(
            "Fixture generation is unavailable. Use live generation or backend mock generation."
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
