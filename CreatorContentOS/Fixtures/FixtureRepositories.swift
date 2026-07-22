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

    func makeDayAvailable(
        scheduledDate: String,
        dailyCardID: UUID?,
        context: WorkspaceContext
    ) async throws -> DayAvailabilityResult {
        let cardID = dailyCardID ?? UUID()
        let readyCard = DailyCard(
            id: cardID,
            title: "Ready package \(scheduledDate)",
            context: SupabaseDateFormatting.contextLine(for: scheduledDate),
            effortLabel: "Easy - 12 min",
            whyToday: "Available on Today from draft.",
            scheduledDate: scheduledDate,
            scenes: [
                ShotScene(number: 1, title: "Opening detail", duration: "3 sec", symbol: "sparkles"),
                ShotScene(number: 2, title: "One steady movement", duration: "5 sec", symbol: "figure.run"),
                ShotScene(number: 3, title: "Useful close", duration: "4 sec", symbol: "text.quote")
            ]
        )

        var cards = await publishedStore?.readWeekCards() ?? []
        cards.removeAll { $0.scheduledDate == scheduledDate }
        cards.append(readyCard)
        cards.sort { ($0.scheduledDate ?? "") < ($1.scheduledDate ?? "") }

        let today = SupabaseDateFormatting.todayDateString()
        let todayCard = cards.first { $0.scheduledDate == today }
        await publishedStore?.savePublishedContent(cards: cards, todayCard: todayCard)

        return DayAvailabilityResult(
            dailyCardID: cardID,
            scheduledDate: scheduledDate,
            status: "published",
            weeklyPlanID: plan.id,
            weekIsSoftLocked: false
        )
    }

    func unpublishDay(
        scheduledDate: String,
        dailyCardID: UUID?,
        context: WorkspaceContext
    ) async throws -> DayUnpublishResult {
        var cards = await publishedStore?.readWeekCards() ?? []
        let existing = cards.first { card in
            if let dailyCardID { return card.id == dailyCardID }
            return card.scheduledDate == scheduledDate
        }
        guard let existing else {
            throw RepositoryError.edgeFunction("daily_card_not_found")
        }

        cards.removeAll { $0.id == existing.id }
        let today = SupabaseDateFormatting.todayDateString()
        let todayCard = cards.first { $0.scheduledDate == today }
        await publishedStore?.savePublishedContent(cards: cards, todayCard: todayCard)

        return DayUnpublishResult(
            dailyCardID: existing.id,
            scheduledDate: existing.scheduledDate ?? scheduledDate,
            status: "draft",
            previousStatus: "published",
            clearedLiveDecision: false,
            archiveRetained: true,
            weeklyPlanID: plan.id
        )
    }

    func updateReadyDayPackage(
        scheduledDate: String,
        dailyCardID: UUID?,
        package: ReadyDayPackageUpdate,
        context: WorkspaceContext
    ) async throws -> DayPackageUpdateResult {
        var cards = await publishedStore?.readWeekCards() ?? []
        guard let index = cards.firstIndex(where: { card in
            if let dailyCardID { return card.id == dailyCardID }
            return card.scheduledDate == scheduledDate
        }) else {
            throw RepositoryError.edgeFunction("daily_card_not_found")
        }

        var card = cards[index]
        if let title = package.title?.nilIfBlank {
            card.title = title
        }
        if let whyToday = package.whyToday?.nilIfBlank {
            card.whyToday = whyToday
        }
        if let caption = package.caption {
            card.caption = caption
        }
        if let script = package.script {
            card.script = script
        }
        if let sceneList = package.sceneList {
            card.scenes = sceneList
        }
        cards[index] = card

        let today = SupabaseDateFormatting.todayDateString()
        let todayCard = cards.first { $0.scheduledDate == today }
        await publishedStore?.savePublishedContent(cards: cards, todayCard: todayCard)

        return DayPackageUpdateResult(
            dailyCardID: card.id,
            scheduledDate: card.scheduledDate ?? scheduledDate,
            status: "published",
            weeklyPlanID: plan.id,
            title: card.title,
            caption: card.caption
        )
    }
}

struct AppFixtureDayGenerationUnavailableRepository: DayGenerationRepository {}

struct AppFixtureStoryboardThumbnailUnavailableRepository: StoryboardThumbnailRepository {}

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

    func persistDecision(
        _ entry: ArchiveEntry,
        for card: DailyCard,
        context: WorkspaceContext
    ) async throws {
        _ = entry
        _ = card
        _ = context
    }

    func upsertDecision(
        _ entry: ArchiveEntry,
        for card: DailyCard,
        context: WorkspaceContext
    ) async throws -> [ArchiveEntry] {
        try await persistDecision(entry, for: card, context: context)
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

struct FixtureRuntimeHealthRepository: RuntimeHealthRepository {
    func checkHealth(for context: WorkspaceContext) async throws -> RuntimeHealthReport {
        _ = context
        return RuntimeHealthReport(
            supabaseOK: false,
            geminiOK: false,
            supabaseDetail: "sample_runtime",
            geminiDetail: "sample_runtime",
            checkedAt: Date()
        )
    }
}
