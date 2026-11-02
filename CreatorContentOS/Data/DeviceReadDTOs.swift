import Foundation

struct SupabaseReadContentRequest: Encodable, Sendable {
    enum Action: String, Encodable, Sendable {
        case today
        case days
        case weekly
        case archive
        case creatorProfile = "creator_profile"
        case intelligence
    }

    var action: Action
    var creatorID: UUID
    var todayDate: String?
    var includeAllPieces: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case action
        case creatorID = "creator_id"
        case todayDate = "today_date"
        case includeAllPieces = "include_all_pieces"
    }
}

struct SupabaseTodayReadResponse: Decodable, Hashable, Sendable {
    var todayCard: SupabaseDailyCardRow?
    var weekCards: [SupabaseDailyCardRow]
    var todayStatus: String?
    var todayDate: String?

    enum CodingKeys: String, CodingKey {
        case todayCard = "today_card"
        case weekCards = "week_cards"
        case todayStatus = "today_status"
        case todayDate = "today_date"
    }
}

struct SupabaseWeeklyReadResponse: Decodable, Hashable, Sendable {
    var weeklyPlan: SupabaseWeeklyPlanRow?
    var dailyCards: [SupabaseDailyCardRow]
    var weeklySetup: SupabaseWeeklySetupRow?
    var ideaBank: [SupabaseIdeaRow]
    var publishedWeeklyPlan: SupabaseWeeklyPlanRow?
    var publishedDailyCards: [SupabaseDailyCardRow]
    var publishedWeeklySetup: SupabaseWeeklySetupRow?

    enum CodingKeys: String, CodingKey {
        case weeklyPlan = "weekly_plan"
        case dailyCards = "daily_cards"
        case weeklySetup = "weekly_setup"
        case ideaBank = "idea_bank"
        case publishedWeeklyPlan = "published_weekly_plan"
        case publishedDailyCards = "published_daily_cards"
        case publishedWeeklySetup = "published_weekly_setup"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weeklyPlan = try container.decodeIfPresent(SupabaseWeeklyPlanRow.self, forKey: .weeklyPlan)
        dailyCards = (try? container.decode([SupabaseDailyCardRow].self, forKey: .dailyCards)) ?? []
        weeklySetup = try container.decodeIfPresent(SupabaseWeeklySetupRow.self, forKey: .weeklySetup)
        ideaBank = (try? container.decode([SupabaseIdeaRow].self, forKey: .ideaBank)) ?? []
        publishedWeeklyPlan = try container.decodeIfPresent(SupabaseWeeklyPlanRow.self, forKey: .publishedWeeklyPlan)
        publishedDailyCards = (try? container.decode([SupabaseDailyCardRow].self, forKey: .publishedDailyCards)) ?? []
        publishedWeeklySetup = try container.decodeIfPresent(SupabaseWeeklySetupRow.self, forKey: .publishedWeeklySetup)
    }

    func generatedDraft() -> GeneratedWeekDraft? {
        guard let weeklyPlan else { return nil }

        return GeneratedWeekDraft(
            id: weeklyPlan.id,
            weeklyPlanID: weeklyPlan.id,
            status: weeklyPlan.status,
            strategySummary: weeklyPlan.strategySummary ?? "Daily content loaded from live cards.",
            warnings: weeklyPlan.warnings.compactMap(\.displayText),
            assumptions: weeklyPlan.assumptions.compactMap(\.displayText),
            dailyCards: dailyCards
                .map { $0.generatedDailyCardDraft() }
                .sorted { $0.scheduledDate < $1.scheduledDate },
            ideaBank: ideaBank.map { $0.domainIdea() },
            sourceSummary: "Live daily cards.",
            generatedAt: weeklyPlan.publishedAt ?? SupabaseDateFormatting.todayDateString()
        )
    }
}

struct SupabaseArchiveReadResponse: Decodable, Hashable, Sendable {
    var entries: [SupabaseArchiveEntryRow]
}

struct SupabaseCreatorProfileReadResponse: Decodable, Hashable, Sendable {
    var profile: SupabaseCreatorProfileRow?
}

struct SupabaseIntelligenceReadResponse: Decodable, Hashable, Sendable {
    var confirmedSourceReferences: [SupabaseSourceReferenceRow]
    var reviewSourceReferences: [SupabaseSourceReferenceRow]
    var candidateBenchmarkCreators: [SupabaseBenchmarkCreatorRow]
    var benchmarkCreatorCount: Int
    var patterns: [SupabasePatternRow]
    var trends: [SupabaseTrendRow]
    var audioOptions: [SupabaseAudioOptionRow]
    var ideas: [SupabaseIdeaRow]

    enum CodingKeys: String, CodingKey {
        case confirmedSourceReferences = "confirmed_source_references"
        case reviewSourceReferences = "review_source_references"
        case candidateBenchmarkCreators = "candidate_benchmark_creators"
        case benchmarkCreatorCount = "benchmark_creator_count"
        case patterns
        case trends
        case audioOptions = "audio_options"
        case ideas
    }
}


struct SupabaseCreatorDaysResponse: Decodable, Sendable {
    var days: [SupabaseCreatorDayRow]
}

struct SupabaseCreatorDayRow: Decodable, Sendable {
    struct Generation: Decodable, Sendable {
        var pieceID: UUID? = nil
        var generationID: UUID
        var status: String
        var idempotencyKey: String?

        enum CodingKeys: String, CodingKey {
            case pieceID = "piece_id"
            case generationID = "generation_id"
            case status
            case idempotencyKey = "idempotency_key"
        }
    }

    var pieceID: UUID? = nil
    var position: Int? = nil
    var scheduledDate: String
    var currentRevisionID: UUID?
    var revision: SupabaseDailyCardRow?
    var generation: Generation?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case pieceID = "piece_id"
        case position
        case scheduledDate = "scheduled_date"
        case currentRevisionID = "current_revision_id"
        case revision, generation
        case updatedAt = "updated_at"
    }
}
