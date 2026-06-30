import Foundation

struct WorkspaceContext: Hashable, Sendable {
    let workspaceID: UUID
    let creatorID: UUID
    let memberID: UUID

    static let creatorFixture = WorkspaceContext(
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
        weeklyGeneration: any WeeklyGenerationRepository = AppFixtureWeeklyGenerationUnavailableRepository(),
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

    static var fixture: AppRepositories {
        let store = FixturePublishedContentStore()
        return AppRepositories(
            context: .creatorFixture,
            today: FixtureTodayCardRepository(publishedStore: store),
            weeklyPlans: FixtureWeeklyPlanRepository(publishedStore: store),
            references: FixtureReferenceRepository(),
            referenceImport: FixtureReferenceImportRepository(),
            weeklyGeneration: AppFixtureWeeklyGenerationUnavailableRepository(),
            intelligence: FixtureIntelligenceRepository(),
            creatorProfile: FixtureCreatorProfileRepository(),
            archive: FixtureArchiveRepository(),
            testerAccess: FixtureTesterAccessRepository()
        )
    }
}

enum RepositoryError: LocalizedError {
    case notConfigured(String)
    case edgeFunction(String)
    case missingFixture(String)
    case noPublishedTodayCard(date: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let message):
            message
        case .edgeFunction(let message):
            message
        case .missingFixture(let message):
            message
        case .noPublishedTodayCard(let date):
            "No published daily card exists for \(date)."
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

struct WeeklyRepositoryContent: Hashable, Sendable {
    var publishedPlan: WeeklyPlan
    var workingPlan: WeeklyPlan? = nil
    var generatedDraft: GeneratedWeekDraft?
    var ideaBank: [WeeklyIdea]

    /// Builds a manager-visible plan from a generated draft, filling all seven
    /// expected day slots. Existing generated cards retain their data; missing
    /// dates become visible open slots without invented card content.
    static func makeWorkingPlan(
        from draft: GeneratedWeekDraft?,
        weekStartDate: String?,
        setupSections: [WeeklySetupSection],
        weeklyBriefText: String
    ) -> WeeklyPlan? {
        guard let draft, !draft.dailyCards.isEmpty, let weekStartDate else { return nil }

        let draftCardsByDate = Dictionary(
            uniqueKeysWithValues: draft.dailyCards.map { ($0.scheduledDate, $0) }
        )
        let expectedDates = SupabaseDateFormatting.weekDates(starting: weekStartDate)

        let dateParser = DateFormatter()
        dateParser.locale = Locale(identifier: "en_US_POSIX")
        dateParser.dateFormat = "yyyy-MM-dd"
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
        weekdayFormatter.dateFormat = "EEE"
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "d"

        let days: [WeeklyDay] = expectedDates.map { dateString in
            if let card = draftCardsByDate[dateString] {
                return card.weeklyDay
            }
            let date = dateParser.date(from: dateString)
            return WeeklyDay(
                weekday: date.map { weekdayFormatter.string(from: $0).uppercased() } ?? "",
                date: date.map { dayFormatter.string(from: $0) } ?? "",
                scheduledDate: dateString,
                title: "Open",
                reason: "",
                source: .open,
                state: .open,
                isSoftLocked: false
            )
        }

        return WeeklyPlan(
            id: draft.weeklyPlanID,
            title: "Generate a Week",
            eyebrow: "MANAGER AI REVIEW",
            weekRange: SupabaseDateFormatting.weekRange(starting: weekStartDate),
            weekStartDate: weekStartDate,
            weekEndDate: SupabaseDateFormatting.weekEndDate(starting: weekStartDate),
            readinessLine: "\(days.filter { $0.state == .planned }.count) ready, \(days.filter { $0.state == .backup }.count) backup, \(days.filter { $0.state == .open }.count) open",
            isSoftLocked: draft.status == "published",
            days: days,
            weeklyBriefText: weeklyBriefText,
            setupSections: setupSections
        )
    }

    /// Builds the manager-visible working plan directly from persisted daily card
    /// rows so review_state survives reload without an extra status round-trip.
    static func makeWorkingPlan(
        from cardRows: [SupabaseDailyCardRow],
        planRow: SupabaseWeeklyPlanRow,
        setupSections: [WeeklySetupSection],
        weeklyBriefText: String
    ) -> WeeklyPlan? {
        guard !cardRows.isEmpty else { return nil }

        let daysByDate = Dictionary(
            uniqueKeysWithValues: cardRows.map { ($0.scheduledDate, $0.weeklyDay()) }
        )
        let expectedDates = SupabaseDateFormatting.weekDates(starting: planRow.weekStartDate)

        let dateParser = DateFormatter()
        dateParser.locale = Locale(identifier: "en_US_POSIX")
        dateParser.dateFormat = "yyyy-MM-dd"
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
        weekdayFormatter.dateFormat = "EEE"
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "d"

        let days: [WeeklyDay] = expectedDates.map { dateString in
            if let day = daysByDate[dateString] {
                return day
            }
            let date = dateParser.date(from: dateString)
            return WeeklyDay(
                weekday: date.map { weekdayFormatter.string(from: $0).uppercased() } ?? "",
                date: date.map { dayFormatter.string(from: $0) } ?? "",
                scheduledDate: dateString,
                title: "Open",
                reason: "",
                source: .open,
                state: .open,
                isSoftLocked: false
            )
        }

        return WeeklyPlan(
            id: planRow.id,
            title: "Generate a Week",
            eyebrow: "MANAGER AI REVIEW",
            weekRange: SupabaseDateFormatting.weekRange(starting: planRow.weekStartDate),
            weekStartDate: planRow.weekStartDate,
            weekEndDate: SupabaseDateFormatting.weekEndDate(starting: planRow.weekStartDate),
            readinessLine: "\(days.filter { $0.state == .planned }.count) ready, \(days.filter { $0.state == .backup }.count) backup, \(days.filter { $0.state == .open }.count) open",
            isSoftLocked: planRow.isSoftLocked || planRow.status == "published",
            days: days,
            weeklyBriefText: weeklyBriefText,
            setupSections: setupSections
        )
    }
}

protocol WeeklyPlanRepository: Sendable {
    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan
    func currentGeneratedDraft(for context: WorkspaceContext) async throws -> GeneratedWeekDraft?
    func ideaBank(for context: WorkspaceContext) async throws -> [WeeklyIdea]
    func currentWeeklyContent(for context: WorkspaceContext) async throws -> WeeklyRepositoryContent
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
    func updateWeeklySetupSections(
        _ sections: [WeeklySetupSection],
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan
    func updateWeeklyBrief(
        _ text: String,
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan
    func updateDailyCardReviewState(
        dailyCardID: UUID,
        reviewState: String,
        context: WorkspaceContext
    ) async throws
}

typealias WeeklyGenerationProgressHandler = @MainActor (WeeklyGenerationProgress) -> Void

protocol WeeklyGenerationRepository: Sendable {
    func generateWeek(
        creatorID: UUID,
        weekStartDate: String,
        weeklySetupID: UUID?,
        mode: GenerateWeekMode,
        context: WorkspaceContext,
        progress: WeeklyGenerationProgressHandler?
    ) async throws -> GeneratedWeekDraft

    func regenerateDay(
        creatorID: UUID,
        weeklyPlanID: UUID,
        scheduledDate: String,
        preserveManualEdits: Bool,
        context: WorkspaceContext
    ) async throws -> RegeneratedDayResult

    func retryQueuedDay(
        generationID: UUID,
        scheduledDate: String,
        context: WorkspaceContext,
        progress: WeeklyGenerationProgressHandler?
    ) async throws -> GeneratedWeekDraft

    func cancelGeneration(
        generationID: UUID,
        context: WorkspaceContext
    ) async throws
}

extension WeeklyPlanRepository {
    func currentWeeklyContent(for context: WorkspaceContext) async throws -> WeeklyRepositoryContent {
        let publishedPlan = try await currentPublishedPlan(for: context)
        let generatedDraft = try await currentGeneratedDraft(for: context)
        let ideaBank = try await ideaBank(for: context)
        let workingPlan = WeeklyRepositoryContent.makeWorkingPlan(
            from: generatedDraft,
            weekStartDate: publishedPlan.weekStartDate,
            setupSections: publishedPlan.setupSections,
            weeklyBriefText: publishedPlan.weeklyBriefText
        )
        return WeeklyRepositoryContent(
            publishedPlan: publishedPlan,
            workingPlan: workingPlan,
            generatedDraft: generatedDraft,
            ideaBank: ideaBank
        )
    }

    func updateDailyCardReviewState(
        dailyCardID: UUID,
        reviewState: String,
        context: WorkspaceContext
    ) async throws {
    }
}

extension WeeklyGenerationRepository {
    func generateWeek(
        creatorID: UUID,
        weekStartDate: String,
        weeklySetupID: UUID?,
        mode: GenerateWeekMode,
        context: WorkspaceContext
    ) async throws -> GeneratedWeekDraft {
        try await generateWeek(
            creatorID: creatorID,
            weekStartDate: weekStartDate,
            weeklySetupID: weeklySetupID,
            mode: mode,
            context: context,
            progress: nil
        )
    }

    func regenerateDay(
        creatorID: UUID,
        weeklyPlanID: UUID,
        scheduledDate: String,
        preserveManualEdits: Bool,
        context: WorkspaceContext
    ) async throws -> RegeneratedDayResult {
        throw RepositoryError.notConfigured("regenerate_day_not_configured")
    }

    func retryQueuedDay(
        generationID: UUID,
        scheduledDate: String,
        context: WorkspaceContext,
        progress: WeeklyGenerationProgressHandler?
    ) async throws -> GeneratedWeekDraft {
        throw RepositoryError.notConfigured("retry_day_not_configured")
    }

    func cancelGeneration(
        generationID: UUID,
        context: WorkspaceContext
    ) async throws {
        throw RepositoryError.notConfigured("cancel_generation_not_configured")
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
    func updateProfile(_ update: CreatorProfileUpdate, context: WorkspaceContext) async throws -> CreatorProfileSummary
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
    var voiceRules: [String] = []
    var contentPillars: [String] = []
    var captionStyle: String? = nil
    var recurringFormats: [String] = []

    static let creatorFixture = CreatorProfileSummary(
        displayName: "Creator",
        positioning: "Indian mother, wife, and HYROX athlete building a second-half-of-life fitness brand around strength, softness, humour, family, consistency, and choosing yourself later in life.",
        voiceLine: "Warm, witty, self-aware, lightly Indian, proud without show-off, wise without preaching.",
        noGoTopics: [
            "Politics",
            "Weight talk",
            "No excuses",
            "Beast mode",
            "Age is just a number"
        ],
        voiceRules: [
            "Conversational",
            "Warm",
            "Witty",
            "Slightly sarcastic",
            "Self-aware",
            "Indian but not caricatured",
            "Proud but not show-offy"
        ],
        contentPillars: ["gym", "lifestyle", "eating", "recovery"],
        captionStyle: "Practical, ready-to-use, sharp, warm, and creator-focused. Simple strong lines over long explanations.",
        recurringFormats: [
            "Today's Hyrox Homework",
            "The Set I Did Not Ask For",
            "Food That Supports Training",
            "Training While Life Is Still Happening",
            "Brand In My Real Routine"
        ]
    )
}

struct CreatorProfileUpdate: Hashable, Sendable {
    var positioning: String
    var voiceRules: [String]
    var contentPillars: [String]
    var captionStyle: String
    var noGoTopics: [String]
    var recurringFormats: [String]

    init(
        positioning: String,
        voiceRules: [String],
        contentPillars: [String],
        captionStyle: String,
        noGoTopics: [String],
        recurringFormats: [String]
    ) {
        self.positioning = positioning
        self.voiceRules = voiceRules
        self.contentPillars = contentPillars
        self.captionStyle = captionStyle
        self.noGoTopics = noGoTopics
        self.recurringFormats = recurringFormats
    }

    init(summary: CreatorProfileSummary) {
        positioning = summary.positioning
        voiceRules = summary.voiceRules.isEmpty
            ? [summary.voiceLine].compactMap(\.nilIfBlank)
            : summary.voiceRules
        contentPillars = summary.contentPillars
        captionStyle = summary.captionStyle ?? ""
        noGoTopics = summary.noGoTopics
        recurringFormats = summary.recurringFormats
    }
}
