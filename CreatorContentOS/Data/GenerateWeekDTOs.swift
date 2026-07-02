import Foundation

struct SupabaseGenerateWeekRequest: Encodable, Sendable {
    var creatorID: UUID
    var weekStartDate: String
    var weeklySetupID: UUID?
    var mode: GenerateWeekMode
    var preserveManualEdits: Bool
    var mock: Bool?
    var responseMode: GenerateWeekResponseMode? = nil
    var featureFlags: [String]? = ["parallel_week_generation"]

    enum CodingKeys: String, CodingKey {
        case creatorID = "creator_id"
        case weekStartDate = "week_start_date"
        case weeklySetupID = "weekly_setup_id"
        case mode
        case preserveManualEdits = "preserve_manual_edits"
        case mock
        case responseMode = "response_mode"
        case featureFlags = "feature_flags"
    }
}

enum GenerateWeekResponseMode: String, Encodable, Sendable {
    case sync
    case async
}

struct WeeklyGenerationProgress: Hashable, Sendable {
    enum Phase: String, Hashable, Sendable {
        case savingWeeklyBrief
        case loadingContext
        case draftingDays
        case savingDraftWeek
        case readyForReview
        case failed
    }

    var phase: Phase
    var generationID: UUID?
    var weeklyPlanID: UUID?
    var draftedDayCount: Int
    var checkedDayCount: Int
    var totalDayCount: Int
    var currentDay: String?
    var message: String?
    var error: String?
    var savedDayCount: Int? = nil
    var failedDayCount: Int? = nil
    var strategyCreated: Bool? = nil
    var dayStatuses: [WeeklyDayGenerationStatus] = []

    static let savingWeeklyBrief = WeeklyGenerationProgress(
        phase: .savingWeeklyBrief,
        generationID: nil,
        weeklyPlanID: nil,
        draftedDayCount: 0,
        checkedDayCount: 0,
        totalDayCount: 7,
        currentDay: nil,
        message: "Saving weekly brief",
        error: nil
    )

    static let loadingContext = WeeklyGenerationProgress(
        phase: .loadingContext,
        generationID: nil,
        weeklyPlanID: nil,
        draftedDayCount: 0,
        checkedDayCount: 0,
        totalDayCount: 7,
        currentDay: nil,
        message: "Collecting context",
        error: nil
    )

    static func savingDraftWeek(from draft: GeneratedWeekDraft) -> WeeklyGenerationProgress {
        WeeklyGenerationProgress(
            phase: .savingDraftWeek,
            generationID: draft.id,
            weeklyPlanID: draft.weeklyPlanID,
            draftedDayCount: draft.dailyCards.count,
            checkedDayCount: draft.dailyCards.count,
            totalDayCount: max(draft.dailyCards.count, 7),
            currentDay: nil,
            message: "Saving draft week",
            error: nil,
            savedDayCount: draft.dailyCards.count,
            failedDayCount: 0,
            strategyCreated: true,
            dayStatuses: draft.dailyCards.enumerated().map { index, card in
                WeeklyDayGenerationStatus(
                    scheduledDate: card.scheduledDate,
                    dayIndex: index,
                    status: "generated",
                    dailyCardID: card.id,
                    errorCode: nil,
                    retryAction: nil,
                    message: nil
                )
            }
        )
    }

    static func readyForReview(from draft: GeneratedWeekDraft) -> WeeklyGenerationProgress {
        WeeklyGenerationProgress(
            phase: .readyForReview,
            generationID: draft.id,
            weeklyPlanID: draft.weeklyPlanID,
            draftedDayCount: draft.dailyCards.count,
            checkedDayCount: draft.dailyCards.count,
            totalDayCount: max(draft.dailyCards.count, 7),
            currentDay: nil,
            message: "Draft week generated",
            error: nil,
            savedDayCount: draft.dailyCards.count,
            failedDayCount: 0,
            strategyCreated: true,
            dayStatuses: draft.dailyCards.enumerated().map { index, card in
                WeeklyDayGenerationStatus(
                    scheduledDate: card.scheduledDate,
                    dayIndex: index,
                    status: "generated",
                    dailyCardID: card.id,
                    errorCode: nil,
                    retryAction: nil,
                    message: nil
                )
            }
        )
    }

    static func partialFailure(
        from draft: GeneratedWeekDraft,
        message: String,
        preserving existingProgress: WeeklyGenerationProgress? = nil,
        expectedScheduledDates: [String] = []
    ) -> WeeklyGenerationProgress {
        let savedCount = min(draft.dailyCards.count, 7)
        let dayStatuses = partialFailureDayStatuses(
            for: draft,
            preserving: existingProgress,
            expectedScheduledDates: expectedScheduledDates
        )
        let failedCount = dayStatuses.isEmpty
            ? max(7 - savedCount, 0)
            : dayStatuses.filter(\.isFailed).count
        return WeeklyGenerationProgress(
            phase: .failed,
            generationID: existingProgress?.generationID ?? (draft.id != draft.weeklyPlanID ? draft.id : nil),
            weeklyPlanID: existingProgress?.weeklyPlanID ?? draft.weeklyPlanID,
            draftedDayCount: savedCount,
            checkedDayCount: savedCount,
            totalDayCount: existingProgress?.totalDayCount ?? 7,
            currentDay: nil,
            message: "Generation incomplete",
            error: message,
            savedDayCount: savedCount,
            failedDayCount: failedCount,
            strategyCreated: true,
            dayStatuses: dayStatuses
        )
    }

    private static func partialFailureDayStatuses(
        for draft: GeneratedWeekDraft,
        preserving existingProgress: WeeklyGenerationProgress?,
        expectedScheduledDates: [String]
    ) -> [WeeklyDayGenerationStatus] {
        let existingStatuses = existingProgress?.dayStatuses ?? []
        let existingByDate = existingStatuses.reduce(into: [String: WeeklyDayGenerationStatus]()) { statusesByDate, status in
            guard let scheduledDate = status.scheduledDate else { return }
            statusesByDate[scheduledDate] = status
        }

        let generatedDates = Set(draft.dailyCards.map(\.scheduledDate))
        let orderedDates = expectedScheduledDates.isEmpty
            ? draft.dailyCards.map(\.scheduledDate).sorted()
            : expectedScheduledDates

        return orderedDates.enumerated().map { index, scheduledDate in
            if let existingStatus = existingByDate[scheduledDate] {
                return existingStatus
            }

            if let generatedCard = draft.dailyCards.first(where: { $0.scheduledDate == scheduledDate }) {
                return WeeklyDayGenerationStatus(
                    scheduledDate: scheduledDate,
                    dayIndex: index,
                    status: "completed",
                    dailyCardID: generatedCard.id,
                    errorCode: nil,
                    retryAction: nil,
                    message: nil
                )
            }

            return WeeklyDayGenerationStatus(
                scheduledDate: scheduledDate,
                dayIndex: index,
                status: generatedDates.contains(scheduledDate) ? "completed" : "failed",
                dailyCardID: nil,
                errorCode: "generation_timeout",
                retryAction: "regenerate_day",
                message: nil
            )
        }
    }

    static func failed(_ message: String, generationID: UUID? = nil) -> WeeklyGenerationProgress {
        WeeklyGenerationProgress(
            phase: .failed,
            generationID: generationID,
            weeklyPlanID: nil,
            draftedDayCount: 0,
            checkedDayCount: 0,
            totalDayCount: 7,
            currentDay: nil,
            message: "Generation failed",
            error: message
        )
    }

    func failed(_ message: String) -> WeeklyGenerationProgress {
        WeeklyGenerationProgress(
            phase: .failed,
            generationID: generationID,
            weeklyPlanID: weeklyPlanID,
            draftedDayCount: draftedDayCount,
            checkedDayCount: checkedDayCount,
            totalDayCount: totalDayCount,
            currentDay: currentDay,
            message: "Generation failed",
            error: message,
            savedDayCount: savedDayCount,
            failedDayCount: failedDayCount,
            strategyCreated: strategyCreated,
            dayStatuses: dayStatuses
        )
    }

    var waitingForStatusRetry: WeeklyGenerationProgress {
        WeeklyGenerationProgress(
            phase: phase,
            generationID: generationID,
            weeklyPlanID: weeklyPlanID,
            draftedDayCount: draftedDayCount,
            checkedDayCount: checkedDayCount,
            totalDayCount: totalDayCount,
            currentDay: currentDay,
            message: "Still checking generation status",
            error: nil,
            savedDayCount: savedDayCount,
            failedDayCount: failedDayCount,
            strategyCreated: strategyCreated,
            dayStatuses: dayStatuses
        )
    }

    var effectiveSavedDayCount: Int {
        min(max(savedDayCount ?? checkedDayCount, 0), totalDayCount)
    }

    var effectiveFailedDayCount: Int {
        min(max(failedDayCount ?? dayStatuses.filter(\.isFailed).count, 0), totalDayCount)
    }

    var failedDayStatuses: [WeeklyDayGenerationStatus] {
        dayStatuses.filter(\.isFailed).sorted { lhs, rhs in
            switch (lhs.dayIndex, rhs.dayIndex) {
            case let (left?, right?):
                left < right
            case (nil, _?):
                false
            case (_?, nil):
                true
            case (nil, nil):
                (lhs.scheduledDate ?? "") < (rhs.scheduledDate ?? "")
            }
        }
    }
}

struct WeeklyDayGenerationStatus: Decodable, Hashable, Sendable {
    var scheduledDate: String?
    var dayIndex: Int?
    var status: String
    var dailyCardID: UUID?
    var errorCode: String?
    var retryAction: String?
    var message: String?

    enum CodingKeys: String, CodingKey {
        case scheduledDate = "scheduled_date"
        case dayIndex = "day_index"
        case status
        case dailyCardID = "daily_card_id"
        case errorCode = "error_code"
        case retryAction = "retry_action"
        case message
    }

    var normalizedStatus: String {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isCompleted: Bool {
        ["generated", "completed", "complete", "ready", "saved", "draft", "drafted"].contains(normalizedStatus)
    }

    var isFailed: Bool {
        ["failed", "error", "errored"].contains(normalizedStatus)
    }

    var isRunning: Bool {
        ["running", "generating", "drafting", "saving"].contains(normalizedStatus)
    }

    var isQueued: Bool {
        ["queued", "pending", "waiting"].contains(normalizedStatus)
    }

    var isRetrying: Bool {
        ["retrying", "retry", "retry_queued"].contains(normalizedStatus)
    }

    var isCancelled: Bool {
        ["cancelled", "canceled"].contains(normalizedStatus)
    }

    var statusSortKey: Int {
        if let dayIndex { return dayIndex }
        return Int.max
    }

    var displayStatusLabel: String {
        if isCompleted { return "Generated" }
        if isRunning { return "Generating" }
        if isRetrying { return "Retrying" }
        if isQueued { return "Queued" }
        if isCancelled { return "Cancelled" }
        if isFailed { return "Needs retry" }
        return "Pending"
    }

    var displayName: String {
        if let scheduledDate {
            return SupabaseDateFormatting.weekdayAbbreviation(for: scheduledDate).capitalized
        }

        if let dayIndex {
            return "Day \(dayIndex + 1)"
        }

        return "Day"
    }

    var failureDetail: String {
        let detail = errorCode ?? message
        switch detail {
        case "openai_request_failed":
            return "The AI service failed for this day."
        case "invalid_ai_json", "invalid_generated_week":
            return "The draft for this day did not pass validation."
        case "generation_persist_failed":
            return "The draft for this day could not be saved."
        case "weekly_setup_not_found":
            return "Save the weekly brief, then try this day again."
        case "generation_timeout":
            return "Generation took too long. Try this day again."
        case .some(let detail) where detail.contains("_"):
            return "This day needs another attempt."
        case .some(let detail):
            return detail
        case nil:
            return "This day needs another attempt."
        }
    }
}

struct SupabaseRegenerateDayRequest: Encodable, Sendable {
    var creatorID: UUID
    var weeklyPlanID: UUID
    var scheduledDate: String
    var preserveManualEdits: Bool
    var responseMode: GenerateWeekResponseMode = .sync
    var mock: Bool?
    var action = "regenerate_day"

    enum CodingKeys: String, CodingKey {
        case creatorID = "creator_id"
        case weeklyPlanID = "weekly_plan_id"
        case scheduledDate = "scheduled_date"
        case preserveManualEdits = "preserve_manual_edits"
        case responseMode = "response_mode"
        case mock
        case action
    }
}

struct SupabaseRetryQueuedDayRequest: Encodable, Sendable {
    var generationID: UUID
    var scheduledDate: String
    var action = "retry_day"

    enum CodingKeys: String, CodingKey {
        case generationID = "generation_id"
        case scheduledDate = "scheduled_date"
        case action
    }
}

struct SupabaseCancelGenerationRequest: Encodable, Sendable {
    let action = "cancel_generation"
    let generationID: UUID

    enum CodingKeys: String, CodingKey {
        case action
        case generationID = "generation_id"
    }
}

struct SupabaseCancelGenerationResponse: Decodable, Hashable, Sendable {
    var status: String
    var message: String?
}

struct SupabaseRetryQueuedDayResponse: Decodable, Hashable, Sendable {
    var generationID: UUID
    var weeklyPlanID: UUID?
    var status: String
    var message: String?
    var day: WeeklyDayGenerationStatus?
    var pollAfterSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case generationID = "generation_id"
        case weeklyPlanID = "weekly_plan_id"
        case status
        case message
        case day
        case pollAfterSeconds = "poll_after_seconds"
    }
}

struct SupabaseRegenerateDayResponse: Decodable, Hashable, Sendable {
    var generationID: UUID
    var weeklyPlanID: UUID
    var status: String
    var targetScheduledDate: String
    var dailyCard: SupabaseGeneratedDailyCardDTO
    var warnings: [String]
    var assumptions: [String]
    var sourceSummary: String
    var generatedAt: String

    enum CodingKeys: String, CodingKey {
        case generationID = "generation_id"
        case weeklyPlanID = "weekly_plan_id"
        case status
        case targetScheduledDate = "target_scheduled_date"
        case dailyCard = "daily_card"
        case warnings
        case assumptions
        case sourceSummary = "source_summary"
        case generatedAt = "generated_at"
    }

    var domainResult: RegeneratedDayResult {
        RegeneratedDayResult(
            generationID: generationID,
            weeklyPlanID: weeklyPlanID,
            status: status,
            targetScheduledDate: targetScheduledDate,
            dailyCard: dailyCard.domainCard,
            warnings: warnings,
            assumptions: assumptions,
            sourceSummary: sourceSummary,
            generatedAt: generatedAt
        )
    }
}

struct RegeneratedDayResult: Hashable, Sendable {
    var generationID: UUID
    var weeklyPlanID: UUID
    var status: String
    var targetScheduledDate: String
    var dailyCard: GeneratedDailyCardDraft
    var warnings: [String]
    var assumptions: [String]
    var sourceSummary: String
    var generatedAt: String
}

struct SupabaseGenerateStoryboardThumbnailRequest: Encodable, Hashable, Sendable {
    var creatorID: UUID
    var dailyCardID: UUID
    var rowIndexes: [Int]?
    var force: Bool
    var revisionInstructions: String?

    enum CodingKeys: String, CodingKey {
        case creatorID = "creator_id"
        case dailyCardID = "daily_card_id"
        case rowIndexes = "row_indexes"
        case force
        case revisionInstructions = "revision_instructions"
    }
}

struct SupabaseGenerateStoryboardThumbnailResponse: Decodable, Hashable, Sendable {
    var dailyCardID: UUID
    var assets: [StoryboardThumbnailAsset]
    var generatedCount: Int
    var cachedCount: Int
    var model: String
    var promptVersion: String

    enum CodingKeys: String, CodingKey {
        case dailyCardID = "daily_card_id"
        case assets
        case generatedCount = "generated_count"
        case cachedCount = "cached_count"
        case model
        case promptVersion = "prompt_version"
    }
}

struct SupabaseGenerateStoryboardThumbnailsRequest: Encodable, Hashable, Sendable {
    var creatorID: UUID
    var weeklyPlanID: UUID
    var force: Bool
    var maxRows: Int

    enum CodingKeys: String, CodingKey {
        case creatorID = "creator_id"
        case weeklyPlanID = "weekly_plan_id"
        case force
        case maxRows = "max_rows"
    }
}

struct SupabaseGenerateStoryboardThumbnailsResponse: Decodable, Hashable, Sendable {
    var weeklyPlanID: UUID
    var cards: [SupabaseStoryboardThumbnailCardProgress]
    var generatedCount: Int
    var cachedCount: Int
    var remainingCount: Int
    var failedCount: Int
    var complete: Bool
    var model: String
    var promptVersion: String
    var lastError: String?

    enum CodingKeys: String, CodingKey {
        case weeklyPlanID = "weekly_plan_id"
        case cards
        case generatedCount = "generated_count"
        case cachedCount = "cached_count"
        case remainingCount = "remaining_count"
        case failedCount = "failed_count"
        case complete
        case model
        case promptVersion = "prompt_version"
        case lastError = "last_error"
    }
}

struct SupabaseStoryboardThumbnailCardProgress: Decodable, Hashable, Sendable {
    var dailyCardID: UUID
    var scheduledDate: String
    var assets: [StoryboardThumbnailAsset]
    var generatedCount: Int
    var cachedCount: Int
    var remainingCount: Int
    var failedCount: Int

    enum CodingKeys: String, CodingKey {
        case dailyCardID = "daily_card_id"
        case scheduledDate = "scheduled_date"
        case assets
        case generatedCount = "generated_count"
        case cachedCount = "cached_count"
        case remainingCount = "remaining_count"
        case failedCount = "failed_count"
    }
}

extension GeneratedWeekDraft {
    @discardableResult
    mutating func replaceDailyCard(_ regeneratedCard: GeneratedDailyCardDraft) -> Bool {
        if let index = dailyCards.firstIndex(where: {
            $0.id == regeneratedCard.id || $0.scheduledDate == regeneratedCard.scheduledDate
        }) {
            dailyCards[index] = regeneratedCard
            return true
        }

        dailyCards.append(regeneratedCard)
        dailyCards.sort { $0.scheduledDate < $1.scheduledDate }
        return true
    }
}

struct SupabaseGenerateWeekResponse: Decodable, Hashable, Sendable {
    var generationID: UUID
    var weeklyPlanID: UUID
    var status: String
    var strategySummary: String
    var warnings: [String]
    var assumptions: [String]
    var dailyCards: [SupabaseGeneratedDailyCardDTO]
    var ideaBank: [SupabaseIdeaRow]
    var sourceSummary: String
    var generatedAt: String
    var completedDayCount: Int?
    var totalDayCount: Int?
    var savedDayCount: Int?
    var failedDayCount: Int?
    var strategyCreated: Bool?
    var dayStatuses: [WeeklyDayGenerationStatus]

    enum CodingKeys: String, CodingKey {
        case generationID = "generation_id"
        case weeklyPlanID = "weekly_plan_id"
        case status
        case strategySummary = "strategy_summary"
        case warnings
        case assumptions
        case dailyCards = "daily_cards"
        case ideaBank = "idea_bank"
        case sourceSummary = "source_summary"
        case generatedAt = "generated_at"
        case completedDayCount = "completed_day_count"
        case totalDayCount = "total_day_count"
        case savedDayCount = "saved_day_count"
        case failedDayCount = "failed_day_count"
        case strategyCreated = "strategy_created"
        case days
        case dayStatuses = "day_statuses"
        case perDayStatuses = "per_day_statuses"
        case failedDays = "failed_days"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generationID = try container.decode(UUID.self, forKey: .generationID)
        weeklyPlanID = try container.decode(UUID.self, forKey: .weeklyPlanID)
        status = try container.decode(String.self, forKey: .status)
        strategySummary = try container.decodeIfPresent(String.self, forKey: .strategySummary) ?? ""
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        assumptions = try container.decodeIfPresent([String].self, forKey: .assumptions) ?? []
        dailyCards = try container.decode([SupabaseGeneratedDailyCardDTO].self, forKey: .dailyCards)
        ideaBank = try container.decodeIfPresent([SupabaseIdeaRow].self, forKey: .ideaBank) ?? []
        sourceSummary = try container.decodeIfPresent(String.self, forKey: .sourceSummary) ?? ""
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ISO8601DateFormatter().string(from: Date())
        completedDayCount = try container.decodeIfPresent(Int.self, forKey: .completedDayCount)
        totalDayCount = try container.decodeIfPresent(Int.self, forKey: .totalDayCount)
        savedDayCount = try container.decodeIfPresent(Int.self, forKey: .savedDayCount)
        failedDayCount = try container.decodeIfPresent(Int.self, forKey: .failedDayCount)
        strategyCreated = try container.decodeIfPresent(Bool.self, forKey: .strategyCreated)
        if let statuses = try container.decodeIfPresent([WeeklyDayGenerationStatus].self, forKey: .days) {
            dayStatuses = statuses
        } else if let statuses = try container.decodeIfPresent([WeeklyDayGenerationStatus].self, forKey: .dayStatuses) {
            dayStatuses = statuses
        } else if let statuses = try container.decodeIfPresent([WeeklyDayGenerationStatus].self, forKey: .perDayStatuses) {
            dayStatuses = statuses
        } else {
            dayStatuses = try container.decodeIfPresent([WeeklyDayGenerationStatus].self, forKey: .failedDays) ?? []
        }
    }

    func domainDraft() -> GeneratedWeekDraft {
        GeneratedWeekDraft(
            id: generationID,
            weeklyPlanID: weeklyPlanID,
            status: status,
            strategySummary: strategySummary,
            warnings: warnings,
            assumptions: assumptions,
            dailyCards: dailyCards.map(\.domainCard),
            ideaBank: ideaBank.map { $0.domainIdea() },
            sourceSummary: sourceSummary,
            generatedAt: generatedAt
        )
    }

    var weekProgress: WeeklyGenerationProgress {
        let total = max(totalDayCount ?? 7, 1)
        let saved = min(max(savedDayCount ?? dailyCards.count, 0), total)
        let failed = min(max(failedDayCount ?? dayStatuses.filter(\.isFailed).count, 0), total)
        return WeeklyGenerationProgress(
            phase: status == "partial" || failed > 0 ? .failed : .savingDraftWeek,
            generationID: generationID,
            weeklyPlanID: weeklyPlanID,
            draftedDayCount: saved,
            checkedDayCount: saved,
            totalDayCount: total,
            currentDay: nil,
            message: status == "partial" ? "Generation incomplete" : "Saving draft week",
            error: status == "partial" || failed > 0 ? "Some days were saved and some days failed. Retry the failed days before publishing." : nil,
            savedDayCount: saved,
            failedDayCount: failed,
            strategyCreated: strategyCreated ?? true,
            dayStatuses: dayStatuses
        )
    }
}

struct SupabaseGenerateWeekStatusRequest: Encodable, Sendable {
    var generationID: UUID
    var creatorID: UUID
    var action = "status"

    enum CodingKeys: String, CodingKey {
        case generationID = "generation_id"
        case creatorID = "creator_id"
        case action
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(generationID.uuidString.lowercased(), forKey: .generationID)
        try container.encode(creatorID.uuidString.lowercased(), forKey: .creatorID)
        try container.encode(action, forKey: .action)
    }
}

struct SupabaseGenerateWeekStatusResponse: Decodable, Hashable, Sendable {
    var generationID: UUID
    var status: String
    var weeklyPlanID: UUID?
    var message: String?
    var completedDayCount: Int?
    var totalDayCount: Int?
    var currentDay: String?
    var targetScheduledDate: String?
    var pollAfterSeconds: Int?
    var error: String?
    var savedDayCount: Int?
    var failedDayCount: Int?
    var strategyCreated: Bool?
    var dayStatuses: [WeeklyDayGenerationStatus]

    enum CodingKeys: String, CodingKey {
        case generationID = "generation_id"
        case status
        case weeklyPlanID = "weekly_plan_id"
        case message
        case completedDayCount = "completed_day_count"
        case totalDayCount = "total_day_count"
        case currentDay = "current_day"
        case targetScheduledDate = "target_scheduled_date"
        case pollAfterSeconds = "poll_after_seconds"
        case error
        case savedDayCount = "saved_day_count"
        case failedDayCount = "failed_day_count"
        case strategyCreated = "strategy_created"
        case days
        case dayStatuses = "day_statuses"
        case perDayStatuses = "per_day_statuses"
        case failedDays = "failed_days"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generationID = try container.decode(UUID.self, forKey: .generationID)
        status = try container.decode(String.self, forKey: .status)
        weeklyPlanID = try container.decodeIfPresent(UUID.self, forKey: .weeklyPlanID)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        completedDayCount = try container.decodeIfPresent(Int.self, forKey: .completedDayCount)
        totalDayCount = try container.decodeIfPresent(Int.self, forKey: .totalDayCount)
        currentDay = try container.decodeIfPresent(String.self, forKey: .currentDay)
        targetScheduledDate = try container.decodeIfPresent(String.self, forKey: .targetScheduledDate)
        pollAfterSeconds = try container.decodeIfPresent(Int.self, forKey: .pollAfterSeconds)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        savedDayCount = try container.decodeIfPresent(Int.self, forKey: .savedDayCount)
        failedDayCount = try container.decodeIfPresent(Int.self, forKey: .failedDayCount)
        strategyCreated = try container.decodeIfPresent(Bool.self, forKey: .strategyCreated)

        if let statuses = try container.decodeIfPresent([WeeklyDayGenerationStatus].self, forKey: .days) {
            dayStatuses = statuses
        } else if let statuses = try container.decodeIfPresent([WeeklyDayGenerationStatus].self, forKey: .dayStatuses) {
            dayStatuses = statuses
        } else if let statuses = try container.decodeIfPresent([WeeklyDayGenerationStatus].self, forKey: .perDayStatuses) {
            dayStatuses = statuses
        } else {
            dayStatuses = try container.decodeIfPresent([WeeklyDayGenerationStatus].self, forKey: .failedDays) ?? []
        }
    }

    var weekProgress: WeeklyGenerationProgress {
        let total = max(totalDayCount ?? 7, 1)
        let saved = min(max(savedDayCount ?? dayStatuses.filter(\.isCompleted).count, 0), total)
        let failed = min(max(failedDayCount ?? dayStatuses.filter(\.isFailed).count, 0), total)
        let completed = min(max(completedDayCount ?? 0, saved + failed), total)
        let effectiveSaved = savedDayCount == nil && dayStatuses.isEmpty ? completed : saved
        return WeeklyGenerationProgress(
            phase: completed >= total && failed == 0 ? .savingDraftWeek : .draftingDays,
            generationID: generationID,
            weeklyPlanID: weeklyPlanID,
            draftedDayCount: effectiveSaved,
            checkedDayCount: effectiveSaved,
            totalDayCount: total,
            currentDay: currentDay ?? targetScheduledDate ?? dayStatuses.first(where: \.isRunning)?.scheduledDate,
            message: message,
            error: error,
            savedDayCount: effectiveSaved,
            failedDayCount: failed,
            strategyCreated: strategyCreated ?? (completed > 0 || status != "pending"),
            dayStatuses: dayStatuses
        )
    }

    var isAmbiguousEarlyWeekFailure: Bool {
        status == "failed" &&
            (error == nil || error == "invalid_generated_week") &&
            (savedDayCount ?? 0) == 0 &&
            (failedDayCount ?? 0) == 0 &&
            dayStatuses.isEmpty
    }
}

enum SupabaseGenerateWeekInvocation: Sendable {
    case draft(SupabaseGenerateWeekResponse)
    case running(SupabaseGenerateWeekStatusResponse)
    case failed(SupabaseGenerateWeekStatusResponse)

    static func decode(_ data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> SupabaseGenerateWeekInvocation {
        let probe = try? decoder.decode(SupabaseGenerationStatusProbe.self, from: data)
        if probe?.status == "draft" || probe?.status == "partial" {
            if let response = try? decoder.decode(SupabaseGenerateWeekResponse.self, from: data) {
                return .draft(response)
            }
        }

        let status = try decoder.decode(SupabaseGenerateWeekStatusResponse.self, from: data)
        if status.status == "failed" {
            return .failed(status)
        }
        return .running(status)
    }
}

enum SupabaseRegenerateDayInvocation: Sendable {
    case completed(SupabaseRegenerateDayResponse)
    case running(SupabaseGenerateWeekStatusResponse)
    case failed(SupabaseGenerateWeekStatusResponse)

    static func decode(_ data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> SupabaseRegenerateDayInvocation {
        let probe = try? decoder.decode(SupabaseGenerationStatusProbe.self, from: data)
        if probe?.status == "draft" || probe?.status == "completed" {
            if let response = try? decoder.decode(SupabaseRegenerateDayResponse.self, from: data) {
                return .completed(response)
            }
        }

        let status = try decoder.decode(SupabaseGenerateWeekStatusResponse.self, from: data)
        if status.status == "failed" {
            return .failed(status)
        }
        return .running(status)
    }
}

private struct SupabaseGenerationStatusProbe: Decodable {
    let status: String?
}

struct SupabaseGeneratedDailyCardDTO: Codable, Hashable, Sendable {
    var id: UUID?
    var scheduledDate: String
    var status: String?
    var title: String
    var whyToday: String
    var growthJob: String
    var contentPillar: String
    var shootability: String
    var estimatedShootMinutes: Int
    var energyRequired: String
    var languageMode: String
    var format: String?
    var primarySurface: String?
    var durationSeconds: Int?
    var hook: String?
    var saveShareReason: String?
    var sceneList: [SupabaseShotSceneDTO]
    var shotTimeline: [ProductionTimelineItem]?
    var voiceoverTimeline: [ProductionTimelineItem]?
    var onScreenTextTimeline: [ProductionTimelineItem]?
    var silentVersionTimeline: [ProductionTimelineItem]?
    var script: String
    var noVoiceoverVersion: String
    var onScreenText: [String]
    var caption: String
    var cta: String
    var hashtags: [String]
    var coverText: String
    var postInstructions: String
    var brandEventNotes: String
    var backupStory: String
    var backupCaptionOnly: String
    var backupStoryDetail: [ProductionTimelineItem]?
    var captionBackupDetail: String?
    var audioOptionNotes: String
    var creatorFitScore: Double
    var riskNotes: [String]
    var assumptions: [String]
    var sourceNote: String
    var reviewState: String?
    var storyboardThumbnailAssets: [StoryboardThumbnailAsset]?

    enum CodingKeys: String, CodingKey {
        case id
        case scheduledDate = "scheduled_date"
        case status
        case title
        case whyToday = "why_today"
        case growthJob = "growth_job"
        case contentPillar = "content_pillar"
        case shootability
        case estimatedShootMinutes = "estimated_shoot_minutes"
        case energyRequired = "energy_required"
        case languageMode = "language_mode"
        case format
        case primarySurface = "primary_surface"
        case durationSeconds = "duration_seconds"
        case hook
        case saveShareReason = "save_share_reason"
        case sceneList = "scene_list"
        case shotTimeline = "shot_timeline"
        case voiceoverTimeline = "voiceover_timeline"
        case onScreenTextTimeline = "on_screen_text_timeline"
        case silentVersionTimeline = "silent_version_timeline"
        case script
        case noVoiceoverVersion = "no_voiceover_version"
        case onScreenText = "on_screen_text"
        case caption
        case cta
        case hashtags
        case coverText = "cover_text"
        case postInstructions = "post_instructions"
        case brandEventNotes = "brand_event_notes"
        case backupStory = "backup_story"
        case backupCaptionOnly = "backup_caption_only"
        case backupStoryDetail = "backup_story_detail"
        case captionBackupDetail = "caption_backup_detail"
        case audioOptionNotes = "audio_option_notes"
        case creatorFitScore = "creator_fit_score"
        case riskNotes = "risk_notes"
        case assumptions
        case sourceNote = "source_note"
        case reviewState = "review_state"
        case storyboardThumbnailAssets = "storyboard_thumbnail_assets"
    }

    var domainCard: GeneratedDailyCardDraft {
        GeneratedDailyCardDraft(
            id: id ?? UUID(),
            scheduledDate: scheduledDate,
            status: status ?? "draft",
            title: title,
            whyToday: whyToday,
            growthJob: growthJob,
            contentPillar: contentPillar,
            shootability: shootability,
            estimatedShootMinutes: estimatedShootMinutes,
            energyRequired: energyRequired,
            languageMode: languageMode,
            format: format,
            primarySurface: primarySurface,
            durationSeconds: durationSeconds,
            hook: hook,
            saveShareReason: saveShareReason,
            sceneList: sceneList.enumerated().map { index, scene in
                scene.domainScene(fallbackNumber: index + 1)
            },
            shotTimeline: shotTimeline ?? [],
            voiceoverTimeline: voiceoverTimeline ?? [],
            onScreenTextTimeline: onScreenTextTimeline ?? [],
            silentVersionTimeline: silentVersionTimeline ?? [],
            script: script,
            noVoiceoverVersion: noVoiceoverVersion,
            onScreenText: onScreenText,
            caption: caption,
            cta: cta,
            hashtags: hashtags,
            coverText: coverText,
            postInstructions: postInstructions,
            brandEventNotes: brandEventNotes,
            backupStory: backupStory,
            backupCaptionOnly: backupCaptionOnly,
            backupStoryDetail: backupStoryDetail ?? [],
            captionBackupDetail: captionBackupDetail,
            audioOptionNotes: audioOptionNotes,
            creatorFitScore: creatorFitScore,
            riskNotes: riskNotes,
            assumptions: assumptions,
            sourceNote: sourceNote,
            storyboardThumbnailAssets: storyboardThumbnailAssets ?? []
        )
    }
}

struct SupabaseDraftDailyCardPublishRequest: Encodable, Sendable {
    var id: UUID
    var scheduledDate: String
    var title: String
    var whyToday: String
    var growthJob: String
    var contentPillar: String
    var shootability: String
    var estimatedShootMinutes: Int
    var energyRequired: String
    var languageMode: String
    var format: String?
    var primarySurface: String?
    var durationSeconds: Int?
    var hook: String?
    var saveShareReason: String?
    var sceneList: [SupabasePublishSceneRequest]
    var shotTimeline: [ProductionTimelineItem]
    var voiceoverTimeline: [ProductionTimelineItem]
    var onScreenTextTimeline: [ProductionTimelineItem]
    var silentVersionTimeline: [ProductionTimelineItem]
    var script: String
    var noVoiceoverVersion: String
    var onScreenText: [String]
    var caption: String
    var cta: String
    var hashtags: [String]
    var coverText: String
    var postInstructions: SupabaseJSONValue
    var brandEventNotes: String
    var backupStory: SupabaseJSONValue
    var backupCaptionOnly: SupabaseJSONValue
    var backupStoryDetail: [ProductionTimelineItem]
    var captionBackupDetail: String?
    var creatorFitScore: Double
    var riskNotes: [String]
    var assumptions: [String]
    var sourceNote: String
    var reviewState: String
    var storyboardThumbnailAssets: [StoryboardThumbnailAsset]

    enum CodingKeys: String, CodingKey {
        case id
        case scheduledDate = "scheduled_date"
        case title
        case whyToday = "why_today"
        case growthJob = "growth_job"
        case contentPillar = "content_pillar"
        case shootability
        case estimatedShootMinutes = "estimated_shoot_minutes"
        case energyRequired = "energy_required"
        case languageMode = "language_mode"
        case format
        case primarySurface = "primary_surface"
        case durationSeconds = "duration_seconds"
        case hook
        case saveShareReason = "save_share_reason"
        case sceneList = "scene_list"
        case shotTimeline = "shot_timeline"
        case voiceoverTimeline = "voiceover_timeline"
        case onScreenTextTimeline = "on_screen_text_timeline"
        case silentVersionTimeline = "silent_version_timeline"
        case script
        case noVoiceoverVersion = "no_voiceover_version"
        case onScreenText = "on_screen_text"
        case caption
        case cta
        case hashtags
        case coverText = "cover_text"
        case postInstructions = "post_instructions"
        case brandEventNotes = "brand_event_notes"
        case backupStory = "backup_story"
        case backupCaptionOnly = "backup_caption_only"
        case backupStoryDetail = "backup_story_detail"
        case captionBackupDetail = "caption_backup_detail"
        case creatorFitScore = "creator_fit_score"
        case riskNotes = "risk_notes"
        case assumptions
        case sourceNote = "source_note"
        case reviewState = "review_state"
        case storyboardThumbnailAssets = "storyboard_thumbnail_assets"
    }

    init(card: GeneratedDailyCardDraft) {
        id = card.id
        scheduledDate = card.scheduledDate
        title = card.title
        whyToday = card.whyToday
        growthJob = card.growthJob
        contentPillar = card.contentPillar
        shootability = card.shootability
        estimatedShootMinutes = card.estimatedShootMinutes
        energyRequired = card.energyRequired
        languageMode = card.languageMode
        format = card.format
        primarySurface = card.primarySurface
        durationSeconds = card.durationSeconds
        hook = card.hook
        saveShareReason = card.saveShareReason
        sceneList = card.sceneList.map { scene in
            SupabasePublishSceneRequest(
                number: scene.number,
                title: scene.title,
                duration: scene.duration,
                symbol: scene.symbol
            )
        }
        shotTimeline = card.shotTimeline
        voiceoverTimeline = card.voiceoverTimeline
        onScreenTextTimeline = card.onScreenTextTimeline
        silentVersionTimeline = card.silentVersionTimeline
        script = card.script
        noVoiceoverVersion = card.noVoiceoverVersion
        onScreenText = card.onScreenText
        caption = card.caption
        cta = card.cta
        hashtags = card.hashtags
        coverText = card.coverText
        postInstructions = .object([
            "line": .string(card.postInstructions),
            "instructions": .string(card.postInstructions),
            "audio_option_notes": .string(card.audioOptionNotes),
            "format": .string(card.format ?? ""),
            "primary_surface": .string(card.primarySurface ?? ""),
            "duration_seconds": .number(Double(card.durationSeconds ?? 0)),
            "hook": .string(card.hook ?? ""),
            "save_share_reason": .string(card.saveShareReason ?? ""),
            "shot_timeline": .array(card.shotTimeline.map(\.supabaseJSONValue)),
            "voiceover_timeline": .array(card.voiceoverTimeline.map(\.supabaseJSONValue)),
            "silent_version_timeline": .array(card.silentVersionTimeline.map(\.supabaseJSONValue)),
            "on_screen_text_timeline": .array(card.onScreenTextTimeline.map(\.supabaseJSONValue)),
            "caption_backup_detail": .string(card.captionBackupDetail ?? "")
        ])
        brandEventNotes = card.brandEventNotes
        backupStory = .object([
            "line": .string(card.backupStory),
            "detail": .array(card.backupStoryDetail.map(\.supabaseJSONValue))
        ])
        backupCaptionOnly = .object([
            "line": .string(card.backupCaptionOnly),
            "detail": .string(card.captionBackupDetail ?? "")
        ])
        backupStoryDetail = card.backupStoryDetail
        captionBackupDetail = card.captionBackupDetail
        creatorFitScore = card.creatorFitScore
        riskNotes = card.riskNotes
        assumptions = card.assumptions
        sourceNote = card.sourceNote
        reviewState = card.status.lowercased() == "ready" ? "ready"
            : card.status.lowercased() == "backup" ? "backup"
            : "open"
        storyboardThumbnailAssets = card.storyboardThumbnailAssets
    }
}

private extension ProductionTimelineItem {
    var supabaseJSONValue: SupabaseJSONValue {
        var object: [String: SupabaseJSONValue] = [
            "timestamp": .string(timestamp),
            "title": .string(title),
            "detail": .string(detail)
        ]
        if let shot {
            object["shot"] = .string(shot)
        }
        if let videoPortion {
            object["video_portion"] = .string(videoPortion)
        }
        if let voiceover {
            object["voiceover"] = .string(voiceover)
        }
        if let onScreenText {
            object["on_screen_text"] = .string(onScreenText)
            object["text"] = .string(onScreenText)
        }
        if let placement {
            object["placement"] = .string(placement)
        }
        if let durationSeconds {
            object["duration_seconds"] = .number(Double(durationSeconds))
        }
        return .object(object)
    }
}
