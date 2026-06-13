import Foundation

struct SupabaseReadContentRequest: Encodable, Sendable {
    enum Action: String, Encodable, Sendable {
        case today
        case weekly
        case archive
        case creatorProfile = "creator_profile"
        case intelligence
    }

    var action: Action
    var creatorID: UUID
    var todayDate: String?

    enum CodingKeys: String, CodingKey {
        case action
        case creatorID = "creator_id"
        case todayDate = "today_date"
    }
}

struct SupabaseTodayReadResponse: Decodable, Hashable, Sendable {
    var todayCard: SupabaseDailyCardRow?
    var weekCards: [SupabaseDailyCardRow]

    enum CodingKeys: String, CodingKey {
        case todayCard = "today_card"
        case weekCards = "week_cards"
    }
}

struct SupabaseWeeklyReadResponse: Decodable, Hashable, Sendable {
    var weeklyPlan: SupabaseWeeklyPlanRow?
    var dailyCards: [SupabaseDailyCardRow]
    var weeklySetup: SupabaseWeeklySetupRow?
    var ideaBank: [SupabaseIdeaRow]

    enum CodingKeys: String, CodingKey {
        case weeklyPlan = "weekly_plan"
        case dailyCards = "daily_cards"
        case weeklySetup = "weekly_setup"
        case ideaBank = "idea_bank"
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
