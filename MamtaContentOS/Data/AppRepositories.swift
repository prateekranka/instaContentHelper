import Foundation

struct WorkspaceContext: Hashable, Sendable {
    let workspaceID: UUID
    let creatorID: UUID
    let memberID: UUID

    static let mamtaFixture = WorkspaceContext(
        workspaceID: UUID(uuidString: "D9F0C7CF-BC12-4D9C-9B2F-172930AA1201")!,
        creatorID: UUID(uuidString: "F0F6DA51-4F75-4D18-A01D-0C9E3C1E6A5C")!,
        memberID: UUID(uuidString: "3A0D2B4D-2D8E-4E6D-A8DE-65D2B75F6CC1")!
    )
}

struct AppRepositories: Sendable {
    let context: WorkspaceContext
    let today: any TodayCardRepository
    let weeklyPlans: any WeeklyPlanRepository
    let references: any ReferenceRepository
    let intelligence: any IntelligenceRepository
    let creatorProfile: any CreatorProfileRepository
    let archive: any ArchiveRepository

    static let fixture = AppRepositories(
        context: .mamtaFixture,
        today: FixtureTodayCardRepository(),
        weeklyPlans: FixtureWeeklyPlanRepository(),
        references: FixtureReferenceRepository(),
        intelligence: FixtureIntelligenceRepository(),
        creatorProfile: FixtureCreatorProfileRepository(),
        archive: FixtureArchiveRepository()
    )
}

enum RepositoryError: LocalizedError {
    case notConfigured(String)
    case missingFixture(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let message):
            message
        case .missingFixture(let message):
            message
        }
    }
}

protocol TodayCardRepository: Sendable {
    func todayCard(for context: WorkspaceContext) async throws -> DailyCard
    func weekCards(for context: WorkspaceContext) async throws -> [DailyCard]
    func completeToday(
        card: DailyCard,
        decision: DailyDecision,
        context: WorkspaceContext
    ) async throws -> ArchiveEntry
}

protocol WeeklyPlanRepository: Sendable {
    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan
    func ideaBank(for context: WorkspaceContext) async throws -> [WeeklyIdea]
    func publishWeek(
        _ plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        context: WorkspaceContext
    ) async throws -> WeeklyPublishResult
    func selectIdeaForNextOpenDay(
        _ idea: WeeklyIdea,
        in plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        context: WorkspaceContext
    ) async throws -> WeeklySelectionUpdate
}

protocol ReferenceRepository: Sendable {
    func sourcePulse(for context: WorkspaceContext) async throws -> SourcePulseSummary
}

protocol IntelligenceRepository: Sendable {
    func home(for context: WorkspaceContext) async throws -> IntelligenceHome
}

protocol CreatorProfileRepository: Sendable {
    func activeProfileSummary(for context: WorkspaceContext) async throws -> CreatorProfileSummary
}

protocol ArchiveRepository: Sendable {
    func entries(for context: WorkspaceContext) async throws -> [ArchiveEntry]
    func upsertDecision(
        _ entry: ArchiveEntry,
        for card: DailyCard,
        context: WorkspaceContext
    ) async throws -> [ArchiveEntry]
}

struct WeeklySelectionUpdate: Hashable, Sendable {
    var weeklyPlan: WeeklyPlan
    var ideaBank: [WeeklyIdea]
}

struct WeeklyPublishResult: Hashable, Sendable {
    var weeklyPlan: WeeklyPlan
    var weekCards: [DailyCard]
    var todayCard: DailyCard?
    var summary: String
}

struct CreatorProfileSummary: Hashable, Sendable {
    var displayName: String
    var positioning: String
    var voiceLine: String
    var noGoTopics: [String]

    static let mamtaFixture = CreatorProfileSummary(
        displayName: "Mamta",
        positioning: "Premium fitness-after-60 editorial voice.",
        voiceLine: "Warm, steady, precise, lightly Hinglish when it feels natural.",
        noGoTopics: ["Politics", "Weight talk", "Negativity"]
    )
}
