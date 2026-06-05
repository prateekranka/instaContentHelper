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
        decision: CompletionState,
        context: WorkspaceContext
    ) async throws -> ArchiveEntry {
        ArchiveEntry(
            day: "TUE",
            date: "3 JUN",
            cardTitle: card.title,
            decision: decision,
            outputLine: decision.archiveLabel,
            hasPostThumbnail: decision == .posted
        )
    }
}

struct FixtureWeeklyPlanRepository: WeeklyPlanRepository {
    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan {
        WeeklyPlan.raceWeek
    }

    func ideaBank(for context: WorkspaceContext) async throws -> [WeeklyIdea] {
        WeeklyIdea.raceWeekBank
    }

    func publishWeek(
        _ plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        context: WorkspaceContext
    ) async throws -> WeeklyPublishResult {
        let publishedPlan = plan.softLockedForPublish
        let cards = DailyCard.publishedCards(from: publishedPlan)

        return WeeklyPublishResult(
            weeklyPlan: publishedPlan,
            weekCards: cards,
            todayCard: DailyCard.bestTodayCard(from: cards),
            summary: "Published \(cards.count) cards to Mamta Today."
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

        return WeeklySelectionUpdate(weeklyPlan: updatedPlan, ideaBank: updatedIdeaBank)
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
        .mamtaFixture
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
        if let index = entries.firstIndex(where: { $0.cardTitle == card.title }) {
            entries[index].decision = entry.decision
        } else {
            entries.insert(entry, at: 0)
        }
        return entries
    }
}
