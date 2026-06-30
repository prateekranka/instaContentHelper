import Foundation

enum SupabaseWriteContentRequest: Encodable, Sendable {
    case completeToday(card: DailyCard, decision: DailyDecision, context: WorkspaceContext)
    case upsertArchiveDecision(ArchiveEntry, for: DailyCard, context: WorkspaceContext)
    case selectIdeaForNextOpenDay(idea: WeeklyIdea, plan: WeeklyPlan, context: WorkspaceContext)
    case updateWeeklySetup(sections: [WeeklySetupSection], plan: WeeklyPlan, context: WorkspaceContext)
    case updateWeeklyBrief(text: String, plan: WeeklyPlan, context: WorkspaceContext)
    case updateCreatorProfile(CreatorProfileUpdate, context: WorkspaceContext)
    case updateDailyCardReviewState(dailyCardID: UUID, reviewState: String, context: WorkspaceContext)

    private enum CodingKeys: String, CodingKey {
        case action
        case creatorID = "creator_id"
        case dailyCardID = "daily_card_id"
        case decision
        case decisionAt = "decision_at"
        case archiveDate = "archive_date"
        case outputLine = "output_line"
        case hasPostThumbnail = "has_post_thumbnail"
        case ideaID = "idea_id"
        case weeklyPlanID = "weekly_plan_id"
        case weekStartDate = "week_start_date"
        case setupSections = "setup_sections"
        case weeklyBrief = "weekly_brief"
        case positioning
        case voiceRules = "voice_rules"
        case contentPillars = "content_pillars"
        case captionStyle = "caption_style"
        case neverSay = "never_say"
        case recurringFormats = "recurring_formats"
        case reviewState = "review_state"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .completeToday(let card, let decision, let context):
            try container.encode("complete_today", forKey: .action)
            try container.encode(context.creatorID, forKey: .creatorID)
            try container.encode(card.id, forKey: .dailyCardID)
            try container.encode(SupabaseWriteDecisionRequest(decision: decision), forKey: .decision)
            try container.encode(SupabaseDateFormatting.isoTimestampString(), forKey: .decisionAt)

        case .upsertArchiveDecision(let entry, let card, let context):
            try container.encode("upsert_archive_decision", forKey: .action)
            try container.encode(context.creatorID, forKey: .creatorID)
            try container.encode(card.id, forKey: .dailyCardID)
            try container.encode(card.scheduledDate ?? SupabaseDateFormatting.todayDateString(), forKey: .archiveDate)
            try container.encode(entry.decision.supabaseStatus, forKey: .decision)
            try container.encode(entry.outputLine, forKey: .outputLine)
            try container.encode(entry.hasPostThumbnail, forKey: .hasPostThumbnail)

        case .selectIdeaForNextOpenDay(let idea, let plan, let context):
            try container.encode("select_idea_for_next_open_day", forKey: .action)
            try container.encode(context.creatorID, forKey: .creatorID)
            try container.encode(idea.id, forKey: .ideaID)
            try container.encode(plan.id, forKey: .weeklyPlanID)

        case .updateWeeklySetup(let sections, let plan, let context):
            try container.encode("update_weekly_setup", forKey: .action)
            try container.encode(context.creatorID, forKey: .creatorID)
            try container.encode(plan.id, forKey: .weeklyPlanID)
            try encodeWeekStartDateIfAvailable(plan.weekStartDate, into: &container)
            try container.encode(
                sections.map(SupabaseWeeklySetupSectionRequest.init(section:)),
                forKey: .setupSections
            )

        case .updateWeeklyBrief(let text, let plan, let context):
            try container.encode("update_weekly_setup", forKey: .action)
            try container.encode(context.creatorID, forKey: .creatorID)
            try container.encode(plan.id, forKey: .weeklyPlanID)
            try encodeWeekStartDateIfAvailable(plan.weekStartDate, into: &container)
            try container.encode(
                [SupabaseWeeklyBriefSetupRequest(text: text)],
                forKey: .setupSections
            )

        case .updateCreatorProfile(let update, let context):
            try container.encode("update_creator_profile", forKey: .action)
            try container.encode(context.creatorID, forKey: .creatorID)
            try container.encode(update.positioning, forKey: .positioning)
            try container.encode(update.voiceRules, forKey: .voiceRules)
            try container.encode(update.contentPillars, forKey: .contentPillars)
            try container.encode(update.captionStyle, forKey: .captionStyle)
            try container.encode(update.noGoTopics, forKey: .neverSay)
            try container.encode(update.recurringFormats, forKey: .recurringFormats)

        case .updateDailyCardReviewState(let dailyCardID, let reviewState, let context):
            try container.encode("update_daily_card_review_state", forKey: .action)
            try container.encode(context.creatorID, forKey: .creatorID)
            try container.encode(dailyCardID, forKey: .dailyCardID)
            try container.encode(reviewState, forKey: .reviewState)
        }
    }

    private func encodeWeekStartDateIfAvailable(
        _ weekStartDate: String?,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        if let weekStartDate = weekStartDate?.nilIfBlank {
            try container.encode(weekStartDate, forKey: .weekStartDate)
        }
    }
}

struct SupabaseWeeklyBriefSetupRequest: Encodable, Sendable {
    var key = "notes"
    var title = "weekly_brief"
    var value: String

    init(text: String) {
        value = text
    }
}

struct SupabaseWeeklySetupSectionRequest: Encodable, Sendable {
    var id: UUID
    var systemImage: String
    var title: String
    var summary: String
    var state: String

    enum CodingKeys: String, CodingKey {
        case id
        case systemImage = "system_image"
        case title
        case summary
        case state
    }

    init(section: WeeklySetupSection) {
        id = section.id
        systemImage = section.systemImage
        title = section.title
        summary = section.summary
        state = section.state
    }
}

struct SupabaseWriteDecisionRequest: Encodable, Sendable {
    var status: String
    var outputLine: String
    var hasPostThumbnail: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case outputLine = "output_line"
        case hasPostThumbnail = "has_post_thumbnail"
    }

    init(decision: DailyDecision) {
        status = decision.completionState.supabaseStatus
        outputLine = decision.outputLine
        hasPostThumbnail = decision.hasPostThumbnail
    }
}

struct SupabaseWriteContentResponse: Decodable, Hashable, Sendable {
    var action: String?
    var dailyCard: SupabaseWriteDailyCardResponse?
    var archiveEntry: SupabaseWriteArchiveEntryResponse?
    var idea: SupabaseWriteIdeaResponse?
    var weeklySetup: SupabaseWeeklySetupRow?
    var creatorProfile: SupabaseCreatorProfileRow?

    enum CodingKeys: String, CodingKey {
        case action
        case dailyCard = "daily_card"
        case archiveEntry = "archive_entry"
        case idea
        case weeklySetup = "weekly_setup"
        case creatorProfile = "creator_profile"
    }
}

struct SupabaseWriteDailyCardResponse: Decodable, Hashable, Sendable {
    var id: UUID
    var status: String
    var decisionAt: String?
    var completedByMemberID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case decisionAt = "decision_at"
        case completedByMemberID = "completed_by_member_id"
    }
}

struct SupabaseWriteArchiveEntryResponse: Decodable, Hashable, Sendable {
    var id: UUID
    var dailyCardID: UUID
    var archiveDate: String
    var decision: String
    var outputLine: String?
    var hasPostThumbnail: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case dailyCardID = "daily_card_id"
        case archiveDate = "archive_date"
        case decision
        case outputLine = "output_line"
        case hasPostThumbnail = "has_post_thumbnail"
    }
}

struct SupabaseWriteIdeaResponse: Decodable, Hashable, Sendable {
    var id: UUID
    var status: String
}
