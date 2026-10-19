import Foundation

#if DEBUG
/// Process-local one-shot failures used by native e2e recovery checks.
actor FixtureFailureState {
    static let shared = FixtureFailureState()
    private var consumed: Set<String> = []

    func consume(_ key: String) -> Bool {
        guard !consumed.contains(key) else { return false }
        consumed.insert(key)
        return true
    }
}
#endif

private struct FixturePublishedContentSnapshot: Codable {
    private enum CodingKeys: String, CodingKey {
        case weekCards
        case todayCard
        case generatedDrafts
    }

    var weekCards: [DailyCard]
    var todayCard: DailyCard?
    var generatedDrafts: [String: DailyCard]

    init(
        weekCards: [DailyCard],
        todayCard: DailyCard?,
        generatedDrafts: [String: DailyCard] = [:]
    ) {
        self.weekCards = weekCards
        self.todayCard = todayCard
        self.generatedDrafts = generatedDrafts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekCards = try container.decode([DailyCard].self, forKey: .weekCards)
        todayCard = try container.decodeIfPresent(DailyCard.self, forKey: .todayCard)
        generatedDrafts = try container.decodeIfPresent(
            [String: DailyCard].self,
            forKey: .generatedDrafts
        ) ?? [:]
    }
}

/// Keeps the fixture Today and weekly repositories on the same published content.
/// A QA session persists this state in its own defaults suite for relaunch proof.
actor FixturePublishedContentStore {
    private var weekCards: [DailyCard] = []
    private var todayCard: DailyCard?
    private var generatedDrafts: [String: DailyCard] = [:]
    private let defaults: UserDefaults?
    private let persistenceKey = "published-content"

    init() {
        if DebugLaunchConfiguration.fixtureSession != nil {
            let defaults = DebugLaunchConfiguration.fixtureDefaults
            self.defaults = defaults
            if let data = defaults.data(forKey: persistenceKey),
               let snapshot = try? JSONDecoder().decode(
                   FixturePublishedContentSnapshot.self,
                   from: data
               ) {
                weekCards = snapshot.weekCards
                todayCard = snapshot.todayCard
                generatedDrafts = snapshot.generatedDrafts
            }
        } else {
            defaults = nil
        }
    }

    func readWeekCards() -> [DailyCard] {
        weekCards
    }

    func readTodayCard() -> DailyCard? {
        todayCard
    }

    func readGeneratedDraft(for scheduledDate: String) -> DailyCard? {
        generatedDrafts[scheduledDate]
    }

    func readGeneratedDrafts() -> [GeneratedDailyCardDraft] {
        generatedDrafts.values
            .sorted { ($0.scheduledDate ?? "") < ($1.scheduledDate ?? "") }
            .map { card in
                let isPublished = weekCards.contains { $0.id == card.id }
                return GeneratedDailyCardDraft(
                    fromPublishedCard: card,
                    status: isPublished ? "published" : "draft"
                )
            }
    }

    func saveGeneratedDraft(_ draft: GeneratedDailyCardDraft) {
        generatedDrafts[draft.scheduledDate] = draft.dailyCard(completionState: nil)
        persist()
    }

    func savePublishedContent(cards: [DailyCard], todayCard: DailyCard?) {
        self.weekCards = cards
        self.todayCard = todayCard
        persist()
    }

    func saveDecisionCard(_ card: DailyCard) {
        var cards = weekCards
        if let index = cards.firstIndex(where: { $0.id == card.id }) {
            cards[index] = card
        } else if card.scheduledDate != nil {
            cards.removeAll { $0.scheduledDate == card.scheduledDate }
            cards.append(card)
            cards.sort { ($0.scheduledDate ?? "") < ($1.scheduledDate ?? "") }
        }
        weekCards = cards
        if card.scheduledDate == SupabaseDateFormatting.todayDateString()
            || todayCard?.id == card.id {
            todayCard = card
        }
        persist()
    }

    private func persist() {
        guard let defaults,
              let data = try? JSONEncoder().encode(
                  FixturePublishedContentSnapshot(
                      weekCards: weekCards,
                      todayCard: todayCard,
                      generatedDrafts: generatedDrafts
                  )
              )
        else {
            return
        }
        defaults.set(data, forKey: persistenceKey)
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
        if DebugLaunchFlags.forceEmptyToday {
            throw RepositoryError.noPublishedTodayCard(
                date: SupabaseDateFormatting.todayDateString()
            )
        }
#if DEBUG
        if DebugLaunchFlags.forceFixtureUI {
            var draft = DebugLaunchFlags.fixtureDailyCardDraft
            draft.scheduledDate = SupabaseDateFormatting.todayDateString()
            draft.status = "ready"
            return draft.dailyCard(completionState: nil)
        }
#endif
        if let generatedDraft = await publishedStore?.readGeneratedDraft(
            for: SupabaseDateFormatting.todayDateString()
        ) {
            return generatedDraft
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
#if DEBUG
        if DebugLaunchFlags.forceFixtureUI {
            var cards = DailyCard.weekFixtures
            var draft = DebugLaunchFlags.fixtureDailyCardDraft
            draft.scheduledDate = SupabaseDateFormatting.todayDateString()
            draft.status = "ready"
            let today = draft.dailyCard(completionState: nil)
            cards.removeAll { $0.scheduledDate == today.scheduledDate }
            cards.append(today)
            cards.sort { ($0.scheduledDate ?? "") < ($1.scheduledDate ?? "") }
            return cards
        }
#endif
        return DailyCard.weekFixtures
    }

    func completeToday(
        card: DailyCard,
        decision: DailyDecision,
        context: WorkspaceContext
    ) async throws -> ArchiveEntry {
#if DEBUG
        if DebugLaunchFlags.failTodayDecisionSyncOnce,
           await FixtureFailureState.shared.consume("today-decision-sync") {
            throw RepositoryError.edgeFunction("fixture_today_decision_sync_failed")
        }
#endif
        await publishedStore?.saveDecisionCard(card)
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
        let generatedDraft = await publishedStore?.readGeneratedDraft(for: scheduledDate)
        let generatedCard = generatedDraft
        let cardID = dailyCardID ?? generatedCard?.id ?? UUID()
        let readyCard = if let generatedCard,
                            generatedCard.id == cardID || dailyCardID == nil {
            generatedCard
        } else {
            DailyCard(
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
        }

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

/// Fixture-mode day generation used by `MCO_FORCE_FIXTURE_UI` / `AppRepositories.fixture`.
/// Returns a reviewable draft immediately so Plan can exercise onboarding → generate → draft
/// without a live edge function.
struct FixtureDayGenerationRepository: DayGenerationRepository {
    /// Brief artificial delay so Plan can show in-progress chrome before the draft lands.
    var artificialDelayNanoseconds: UInt64
    let publishedStore: FixturePublishedContentStore?

    init(
        artificialDelayNanoseconds: UInt64 = DebugLaunchFlags.fixtureFirstIdeaDelayNanoseconds,
        publishedStore: FixturePublishedContentStore? = nil
    ) {
        self.artificialDelayNanoseconds = artificialDelayNanoseconds
        self.publishedStore = publishedStore
    }

    func persistedDayPackages(context: WorkspaceContext) async -> [GeneratedDailyCardDraft] {
        _ = context
        return await publishedStore?.readGeneratedDrafts() ?? []
    }

    func generateDay(
        creatorID: UUID,
        scheduledDate: String,
        dayBrief: String,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        _ = creatorID
        _ = context
#if DEBUG
        if DebugLaunchFlags.failFirstIdea {
            throw RepositoryError.edgeFunction("fixture_first_idea_generation_failed")
        }
        if DebugLaunchFlags.failFirstIdeaOnce,
           await FixtureFailureState.shared.consume("first-idea-generation") {
            throw RepositoryError.edgeFunction("fixture_first_idea_generation_failed_once")
        }
#endif
        try await Task.sleep(nanoseconds: artificialDelayNanoseconds)
        let result = makeResult(scheduledDate: scheduledDate, dayBrief: dayBrief)
        await publishedStore?.saveGeneratedDraft(result.dailyCard)
        return result
    }

    func generatePieceDraft(
        creatorID: UUID,
        scheduledDate: String,
        dayBrief: String,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        _ = creatorID
        _ = context
        try await Task.sleep(nanoseconds: artificialDelayNanoseconds)
        return makeResult(scheduledDate: scheduledDate, dayBrief: dayBrief)
    }

    func regenerateDay(
        creatorID: UUID,
        weeklyPlanID: UUID,
        scheduledDate: String,
        preserveManualEdits: Bool,
        dayGuidance: String?,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        _ = creatorID
        _ = weeklyPlanID
        _ = preserveManualEdits
        _ = context
#if DEBUG
        if DebugLaunchFlags.failFirstIdea {
            throw RepositoryError.edgeFunction("fixture_first_idea_generation_failed")
        }
#endif
        try await Task.sleep(nanoseconds: artificialDelayNanoseconds)
        let guidance = dayGuidance?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let brief = guidance.isEmpty
            ? "Regenerated fixture day for \(scheduledDate)."
            : guidance
        let result = makeResult(scheduledDate: scheduledDate, dayBrief: brief)
        await publishedStore?.saveGeneratedDraft(result.dailyCard)
        return result
    }

    func resumeAcceptedDayGeneration(
        generationID: UUID,
        creatorID: UUID,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        _ = creatorID
        _ = context
        try await Task.sleep(nanoseconds: artificialDelayNanoseconds)
        let result = makeResult(
            scheduledDate: SupabaseDateFormatting.todayDateString(),
            dayBrief: "Resumed fixture generation \(generationID.uuidString.prefix(8))."
        )
        await publishedStore?.saveGeneratedDraft(result.dailyCard)
        return result
    }

    private func makeResult(scheduledDate: String, dayBrief: String) -> DailyGenerationResult {
        let trimmedBrief = dayBrief.trimmingCharacters(in: .whitespacesAndNewlines)
        let pillar = inferredContentPillar(from: trimmedBrief)
        let title = synthesizedTitle(from: trimmedBrief, pillar: pillar)
        let script = synthesizedScript(from: trimmedBrief, pillar: pillar)
        let format = fixtureFormat(from: trimmedBrief)
        let duration = format == "Post" ? nil : requestedDuration(from: trimmedBrief) ?? (format == "Story" ? 10 : 12)
        let scenes = fixtureScenes(for: pillar, format: format, duration: duration)
        var dailyCard = GeneratedDailyCardDraft(
            id: UUID(),
            scheduledDate: scheduledDate,
            status: "draft",
            title: title,
            whyToday: trimmedBrief.isEmpty
                ? "Fixture day generation for \(scheduledDate)."
                : trimmedBrief,
            growthJob: "Consistency.",
            contentPillar: pillar,
            shootability: "easy",
            estimatedShootMinutes: format == "Reel" ? 12 : 2,
            energyRequired: "low",
            languageMode: "English",
            format: format,
            primarySurface: format == "Story" ? "instagram_stories" : format == "Post" ? "instagram_feed" : "instagram_reels",
            durationSeconds: duration,
            hook: title,
            saveShareReason: "Save this as a reminder to shoot the day as planned.",
            sceneList: scenes,
            script: script,
            noVoiceoverVersion: format == "Post" ? "Use a photo you already have. No filming needed." : "Use bold captions over the same shots.",
            onScreenText: sceneOnScreenText(for: pillar),
            caption: script,
            cta: "Save this for later.",
            hashtags: hashtags(for: pillar),
            coverText: String(title.prefix(40)),
            postInstructions: "Keep it real, natural, and personal.",
            brandEventNotes: "",
            backupStory: "Post one phone clip with the same hook.",
            backupCaptionOnly: "Same angle, shorter cut.",
            audioOptionNotes: "",
            creatorFitScore: 90,
            riskNotes: [],
            assumptions: ["Fixture UI generation — no live model call."],
            sourceNote: "Based on your idea."
        )
#if DEBUG
        if DebugLaunchFlags.longContent {
            dailyCard = dailyCard.withLongContent
            dailyCard.scheduledDate = scheduledDate
            dailyCard.status = "draft"
        }
        dailyCard = DebugLaunchFlags.uiFixtureData.applying(to: dailyCard)
#endif
        return DailyGenerationResult(
            generationID: UUID(),
            weeklyPlanID: WeeklyPlan.raceWeek.id,
            status: "draft",
            targetScheduledDate: scheduledDate,
            dailyCard: dailyCard,
            warnings: [],
            assumptions: ["Fixture UI generation — no live model call."],
            sourceSummary: "Fixture day brief only.",
            generatedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    /// Keep simulated output consistent with the explicit brief used by e2e.
    /// These methods never run against the live generation repository.
    private func fixtureFormat(from brief: String) -> String {
        let lower = brief.lowercased()
        if lower.contains("photo") || lower.contains("carousel") || lower.contains("caption-only") { return "Post" }
        if lower.range(of: #"\bstory\b"#, options: .regularExpression) != nil { return "Story" }
        return "Reel"
    }

    private func requestedDuration(from brief: String) -> Int? {
        guard let expression = try? NSRegularExpression(pattern: #"(\d+)\s*(?:[-–]\s*)?(?:seconds?|secs?|s)\b"#, options: .caseInsensitive),
              let match = expression.firstMatch(in: brief, range: NSRange(brief.startIndex..., in: brief)),
              let range = Range(match.range(at: 1), in: brief),
              let seconds = Int(brief[range]), seconds > 0 else { return nil }
        return seconds
    }

    private func fixtureScenes(for pillar: String, format: String, duration: Int?) -> [ShotScene] {
        guard let duration else { return [] }
        let original = synthesizedScenes(for: pillar)
        let count = format == "Story" ? 1 : min(original.count, duration)
        return original.prefix(count).enumerated().map { index, scene in
            // Quotient and remainder preserve the requested total without zero-length shots.
            let seconds = duration / count + (index < duration % count ? 1 : 0)
            return ShotScene(number: index + 1, title: scene.title, duration: "\(seconds) sec", symbol: scene.symbol)
        }
    }

    private func inferredContentPillar(from brief: String) -> String {
        let lower = brief.lowercased()
        let hasBooks = lower.contains("book")
        let hasMovies = lower.contains("movie") || lower.contains(" tv") || lower.contains("tv ")
        if hasBooks && hasMovies { return "books" }
        if hasMovies { return "movies-tv" }
        if hasBooks { return "books" }
        if lower.contains("hyrox") || lower.contains("race week") || lower.contains("fitness") || lower.contains("gym") {
            return "fitness-wellness"
        }
        return "lifestyle"
    }

    private func synthesizedTitle(from brief: String, pillar: String) -> String {
        let lower = brief.lowercased()
        if lower.contains("book") && (lower.contains("movie") || lower.contains(" tv")) {
            return "What I'm reading and watching right now"
        }
        switch pillar {
        case "books":
            return "The book on my nightstand — one honest takeaway"
        case "movies-tv":
            return "One scene from what I'm watching that stuck with me"
        case "fitness-wellness":
            return "One small training win worth sharing today"
        default:
            let titleSeed = brief.split(separator: ".").first.map(String.init) ?? brief
            let title = String(titleSeed.prefix(72))
            return title.isEmpty ? "Fixture day draft" : title
        }
    }

    private func synthesizedScript(from brief: String, pillar: String) -> String {
        switch pillar {
        case "books":
            return """
            Here is the book I cannot stop thinking about.
            One line about why it landed for me.
            What I would tell a friend who asked if it is worth it.
            """
        case "movies-tv":
            return """
            Here is what I am watching this week.
            The moment that made me pause the scroll.
            Why it fits the mood I am in right now.
            """
        default:
            if brief.localizedCaseInsensitiveContains("book") && brief.localizedCaseInsensitiveContains("movie") {
                return """
                Two things on my mind this week: a book and a show.
                One honest line about each.
                Why they pair well for the kind of content I make.
                """
            }
            return brief.isEmpty
                ? "Open with the day's angle. Show one real beat. Close with a simple ask."
                : brief
        }
    }

    private func synthesizedScenes(for pillar: String) -> [ShotScene] {
        switch pillar {
        case "books":
            return [
                ShotScene(number: 1, title: "Book on the table", duration: "3 sec", symbol: "book.closed"),
                ShotScene(number: 2, title: "Favorite page", duration: "4 sec", symbol: "text.book.closed"),
                ShotScene(number: 3, title: "Quick rating", duration: "3 sec", symbol: "star"),
                ShotScene(number: 4, title: "Save for later", duration: "2 sec", symbol: "bookmark")
            ]
        case "movies-tv":
            return [
                ShotScene(number: 1, title: "Remote and couch", duration: "3 sec", symbol: "tv"),
                ShotScene(number: 2, title: "Pause on the scene", duration: "4 sec", symbol: "film"),
                ShotScene(number: 3, title: "Reaction beat", duration: "3 sec", symbol: "face.smiling"),
                ShotScene(number: 4, title: "Soft ask", duration: "2 sec", symbol: "heart")
            ]
        default:
            return [
                ShotScene(number: 1, title: "Talking-head hook", duration: "3 sec", symbol: "person.crop.rectangle"),
                ShotScene(number: 2, title: "Process b-roll", duration: "4 sec", symbol: "film.stack"),
                ShotScene(number: 3, title: "Proof moment", duration: "3 sec", symbol: "checkmark.circle"),
                ShotScene(number: 4, title: "Soft CTA", duration: "2 sec", symbol: "heart")
            ]
        }
    }

    private func sceneOnScreenText(for pillar: String) -> [String] {
        switch pillar {
        case "books":
            return ["Currently reading", "Worth it?", "Save this"]
        case "movies-tv":
            return ["Watching now", "This scene", "Save this"]
        default:
            return ["Today", "Keep it real", "Save this"]
        }
    }

    private func hashtags(for pillar: String) -> [String] {
        switch pillar {
        case "books":
            return ["books", "currentlyreading", "fixture"]
        case "movies-tv":
            return ["movies", "whattowatch", "fixture"]
        default:
            return ["fixture", "dayplan"]
        }
    }
}

/// Deterministic Plan idea one-liners for `MCO_FORCE_FIXTURE_UI` / preview / tests.
struct FixturePlanDayIdeaRepository: PlanDayIdeaRepository {
    func generatePlanDayIdeas(
        creatorID: UUID,
        scheduledDate: String,
        setup: PlanDaySetupSummary,
        context: WorkspaceContext
    ) async throws -> [PlanDayIdeaCandidate] {
        _ = creatorID
        _ = context
        return PlanDayIdeaBuilder.buildIdeas(scheduledDate: scheduledDate, setup: setup)
    }
}

/// Explicit unavailable stub for tests that assert missing day-generation wiring.
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
    private let store: FixtureCreatorProfileStore

    init(store: FixtureCreatorProfileStore = FixtureCreatorProfileStore()) {
        self.store = store
    }

    func activeProfileSummary(for context: WorkspaceContext) async throws -> CreatorProfileSummary {
        _ = context
        return await store.read()
    }

    func updateProfile(_ update: CreatorProfileUpdate, context: WorkspaceContext) async throws -> CreatorProfileSummary {
        _ = context
        return await store.apply(update)
    }
}

actor FixtureCreatorProfileStore {
    private var profile: CreatorProfileSummary = .creatorFixture

    func read() -> CreatorProfileSummary {
        profile
    }

    func apply(_ update: CreatorProfileUpdate) -> CreatorProfileSummary {
        profile = Self.mergedProfile(existing: profile, update: update)
        return profile
    }

    private static func mergedProfile(
        existing: CreatorProfileSummary,
        update: CreatorProfileUpdate
    ) -> CreatorProfileSummary {
        var summary = existing

        if let positioning = update.positioning {
            summary.positioning = positioning
        }
        if let voiceRules = update.voiceRules {
            summary.voiceRules = voiceRules
            summary.voiceLine = voiceRules.joined(separator: ", ")
        }
        if let contentPillars = update.contentPillars {
            summary.contentPillars = contentPillars
        }
        if let captionStyle = update.captionStyle {
            summary.captionStyle = captionStyle
        }
        if let noGoTopics = update.noGoTopics {
            summary.noGoTopics = noGoTopics
        }
        if let recurringFormats = update.recurringFormats {
            summary.recurringFormats = recurringFormats
        }
        if let onboardingState = update.onboardingState {
            summary.onboardingState = onboardingState
        }
        if let onboardingStep = update.onboardingStep {
            summary.onboardingStep = onboardingStep
        }
        if update.onboardingCompletedAt != nil {
            summary.onboardingCompletedAt = update.onboardingCompletedAt
        }
        if let startingPoint = update.startingPoint {
            summary.startingPoint = startingPoint
        }
        if let customSubjects = update.customSubjects {
            summary.customSubjects = customSubjects
        }
        if let tasteExampleIDs = update.tasteExampleIDs {
            summary.tasteExampleIDs = tasteExampleIDs
        }
        if let productionFormats = update.productionFormats {
            summary.productionFormats = productionFormats
        }
        if let timeToCreate = update.timeToCreate {
            summary.timeToCreate = timeToCreate
        }
        if let onCameraRestrictions = update.onCameraRestrictions {
            summary.onCameraRestrictions = onCameraRestrictions
        }
        if let recentContext = update.recentContext {
            summary.recentContext = recentContext
        }
        if update.creatorNote != nil {
            summary.creatorNote = update.creatorNote
        }
        if let firstIdeaHandoff = update.firstIdeaHandoff {
            summary.firstIdeaHandoff = firstIdeaHandoff
        }
        if let languagePreferences = update.languagePreferences,
           let primary = languagePreferences["primary"]?.nilIfBlank {
            summary.contentLanguage = primary
        }

        return summary
    }
}

actor FixtureArchiveStore {
    private let defaults: UserDefaults
    private let key = "archive"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func entries() -> [ArchiveEntry]? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([ArchiveEntry].self, from: data)
    }

    func save(_ entries: [ArchiveEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }
}

struct FixtureArchiveRepository: ArchiveRepository {
    private let store: FixtureArchiveStore?

    init(store: FixtureArchiveStore? = nil) {
        self.store = store ?? DebugLaunchConfiguration.fixtureSession.map {
            _ in FixtureArchiveStore(defaults: DebugLaunchConfiguration.fixtureDefaults)
        }
    }

    func entries(for context: WorkspaceContext) async throws -> [ArchiveEntry] {
        if let stored = await store?.entries() { return stored }
#if DEBUG
        switch DebugLaunchFlags.uiFixtureData {
        case .empty: return []
        case .one: return Array(ArchiveEntry.fixtures.prefix(1))
        case .worst, .huge:
            let count = DebugLaunchFlags.uiFixtureData == .huge ? 1_284 : 6
            return (0..<count).map { index in
                ArchiveEntry(day: "TUE", date: "6 OCT",
                    cardTitle: index == 0
                        ? "Đặng Thị Ngọc Hân — a small creative routine that helped me finish a difficult week"
                        : "Daily moment \(index + 1)",
                    decision: .posted, outputLine: "Posted", hasPostThumbnail: false)
            }
        case .demo: break
        }
#endif
        return ArchiveEntry.fixtures
    }

    func persistDecision(
        _ entry: ArchiveEntry,
        for card: DailyCard,
        context: WorkspaceContext
    ) async throws {
        _ = card
        _ = context
        guard let store else { return }
        var entries = await store.entries() ?? ArchiveEntry.fixtures
        if let index = entries.firstIndex(where: { archiveEntry in
            archiveEntry.dailyCardID == card.id || archiveEntry.cardTitle == card.title
        }) {
            entries[index] = entry
        } else {
            entries.insert(entry, at: 0)
        }
        await store.save(entries)
    }

    func upsertDecision(
        _ entry: ArchiveEntry,
        for card: DailyCard,
        context: WorkspaceContext
    ) async throws -> [ArchiveEntry] {
        try await persistDecision(entry, for: card, context: context)
        var entries = try await self.entries(for: context)
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
