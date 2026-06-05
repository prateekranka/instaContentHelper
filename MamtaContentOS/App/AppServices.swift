import Foundation
import Observation

@MainActor
@Observable
final class AppServices {
    let context: WorkspaceContext
    private let repositories: AppRepositories

    var todayCard: DailyCard
    var archiveEntries: [ArchiveEntry]
    var weeklyPlan: WeeklyPlan
    var weeklyIdeas: [WeeklyIdea]
    var intelligenceHome: IntelligenceHome
    var creatorProfileSummary: CreatorProfileSummary
    var weekCards: [DailyCard]
    var lastRepositoryError: String?
    var isPublishingWeek = false
    var lastPublishSummary: String?

    init(
        repositories: AppRepositories,
        todayCard: DailyCard,
        archiveEntries: [ArchiveEntry],
        weeklyPlan: WeeklyPlan,
        weeklyIdeas: [WeeklyIdea],
        intelligenceHome: IntelligenceHome,
        creatorProfileSummary: CreatorProfileSummary,
        weekCards: [DailyCard]
    ) {
        self.context = repositories.context
        self.repositories = repositories
        self.todayCard = todayCard
        self.archiveEntries = archiveEntries
        self.weeklyPlan = weeklyPlan
        self.weeklyIdeas = weeklyIdeas
        self.intelligenceHome = intelligenceHome
        self.creatorProfileSummary = creatorProfileSummary
        self.weekCards = weekCards
    }

    static var preview: AppServices {
        fixtureBacked(repositories: .fixture)
    }

    static func fixtureBacked(repositories: AppRepositories) -> AppServices {
        AppServices(
            repositories: repositories,
            todayCard: .raceWeekToday,
            archiveEntries: ArchiveEntry.fixtures,
            weeklyPlan: .raceWeek,
            weeklyIdeas: WeeklyIdea.raceWeekBank,
            intelligenceHome: .raceWeekLibrary,
            creatorProfileSummary: .mamtaFixture,
            weekCards: DailyCard.weekFixtures
        )
    }

    func completeToday(with decision: CompletionState) {
        todayCard.completionState = decision

        Task {
            do {
                let entry = try await repositories.today.completeToday(
                    card: todayCard,
                    decision: decision,
                    context: context
                )
                archiveEntries = try await repositories.archive.upsertDecision(
                    entry,
                    for: todayCard,
                    context: context
                )
                lastRepositoryError = nil
            } catch {
                lastRepositoryError = error.localizedDescription
            }
        }
    }

    var nextOpenWeeklyDay: WeeklyDay? {
        weeklyPlan.days.first { $0.state == .open }
    }

    func selectIdeaForNextOpenDay(_ idea: WeeklyIdea) {
        Task {
            do {
                let update = try await repositories.weeklyPlans.selectIdeaForNextOpenDay(
                    idea,
                    in: weeklyPlan,
                    ideaBank: weeklyIdeas,
                    context: context
                )
                weeklyPlan = update.weeklyPlan
                weeklyIdeas = update.ideaBank
                lastRepositoryError = nil
            } catch {
                lastRepositoryError = error.localizedDescription
            }
        }
    }

    func publishCurrentWeek() {
        Task {
            await publishCurrentWeekImmediately()
        }
    }

    func publishCurrentWeekImmediately() async {
        guard !isPublishingWeek else { return }

        isPublishingWeek = true
        defer { isPublishingWeek = false }

        do {
            let result = try await repositories.weeklyPlans.publishWeek(
                weeklyPlan,
                ideaBank: weeklyIdeas,
                context: context
            )
            weeklyPlan = result.weeklyPlan
            weekCards = result.weekCards
            if let todayCard = result.todayCard {
                self.todayCard = todayCard
            }
            lastPublishSummary = result.summary
            lastRepositoryError = nil
        } catch {
            lastRepositoryError = error.localizedDescription
        }
    }

    func refreshFromRepositories() {
        Task {
            do {
                async let loadedTodayCard = repositories.today.todayCard(for: context)
                async let loadedArchiveEntries = repositories.archive.entries(for: context)
                async let loadedWeeklyPlan = repositories.weeklyPlans.currentPublishedPlan(for: context)
                async let loadedWeeklyIdeas = repositories.weeklyPlans.ideaBank(for: context)
                async let loadedIntelligenceHome = repositories.intelligence.home(for: context)
                async let loadedCreatorProfile = repositories.creatorProfile.activeProfileSummary(for: context)
                async let loadedWeekCards = repositories.today.weekCards(for: context)

                todayCard = try await loadedTodayCard
                archiveEntries = try await loadedArchiveEntries
                weeklyPlan = try await loadedWeeklyPlan
                weeklyIdeas = try await loadedWeeklyIdeas
                intelligenceHome = try await loadedIntelligenceHome
                creatorProfileSummary = try await loadedCreatorProfile
                weekCards = try await loadedWeekCards
                lastRepositoryError = nil
            } catch {
                lastRepositoryError = error.localizedDescription
            }
        }
    }
}
