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
    let referenceImport: any ReferenceImportRepository
    let weeklyGeneration: any WeeklyGenerationRepository
    let intelligence: any IntelligenceRepository
    let creatorProfile: any CreatorProfileRepository
    let archive: any ArchiveRepository
    let testerAccess: any TesterAccessRepository

    init(
        context: WorkspaceContext,
        today: any TodayCardRepository,
        weeklyPlans: any WeeklyPlanRepository,
        references: any ReferenceRepository,
        referenceImport: any ReferenceImportRepository = FixtureReferenceImportRepository(),
        weeklyGeneration: any WeeklyGenerationRepository = FixtureWeeklyGenerationRepository(),
        intelligence: any IntelligenceRepository,
        creatorProfile: any CreatorProfileRepository,
        archive: any ArchiveRepository,
        testerAccess: any TesterAccessRepository = FixtureTesterAccessRepository()
    ) {
        self.context = context
        self.today = today
        self.weeklyPlans = weeklyPlans
        self.references = references
        self.referenceImport = referenceImport
        self.weeklyGeneration = weeklyGeneration
        self.intelligence = intelligence
        self.creatorProfile = creatorProfile
        self.archive = archive
        self.testerAccess = testerAccess
    }

    static let fixture = AppRepositories(
        context: .mamtaFixture,
        today: FixtureTodayCardRepository(),
        weeklyPlans: FixtureWeeklyPlanRepository(),
        references: FixtureReferenceRepository(),
        referenceImport: FixtureReferenceImportRepository(),
        weeklyGeneration: FixtureWeeklyGenerationRepository(),
        intelligence: FixtureIntelligenceRepository(),
        creatorProfile: FixtureCreatorProfileRepository(),
        archive: FixtureArchiveRepository(),
        testerAccess: FixtureTesterAccessRepository()
    )
}

enum RepositoryError: LocalizedError {
    case notConfigured(String)
    case edgeFunction(String)
    case missingFixture(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let message):
            message
        case .edgeFunction(let message):
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
        generatedDraft: GeneratedWeekDraft?,
        context: WorkspaceContext
    ) async throws -> WeeklyPublishResult
    func selectIdeaForNextOpenDay(
        _ idea: WeeklyIdea,
        in plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        context: WorkspaceContext
    ) async throws -> WeeklySelectionUpdate
}

protocol WeeklyGenerationRepository: Sendable {
    func generateWeek(
        creatorID: UUID,
        weekStartDate: String,
        weeklySetupID: UUID?,
        mode: GenerateWeekMode,
        context: WorkspaceContext
    ) async throws -> GeneratedWeekDraft

    func regenerateDay(
        creatorID: UUID,
        weeklyPlanID: UUID,
        scheduledDate: String,
        preserveManualEdits: Bool,
        context: WorkspaceContext
    ) async throws -> RegeneratedDayResult
}

extension WeeklyGenerationRepository {
    func regenerateDay(
        creatorID: UUID,
        weeklyPlanID: UUID,
        scheduledDate: String,
        preserveManualEdits: Bool,
        context: WorkspaceContext
    ) async throws -> RegeneratedDayResult {
        throw RepositoryError.notConfigured("regenerate_day_not_configured")
    }
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

protocol TesterAccessRepository: Sendable {
    func listTesters(context: WorkspaceContext) async throws -> [TesterAccessRecord]
    func inviteTester(email: String, displayName: String?, context: WorkspaceContext) async throws -> TesterAccessRecord
    func resendTesterOTP(email: String, context: WorkspaceContext) async throws -> TesterAccessRecord
    func revokeTester(memberID: UUID, context: WorkspaceContext) async throws -> TesterAccessRecord
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
