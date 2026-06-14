import Foundation
import Supabase

struct SupabaseTodayCardRepository: TodayCardRepository {
    let client: SupabaseClient

    func todayCard(for context: WorkspaceContext) async throws -> DailyCard {
        let todayDate = SupabaseDateFormatting.todayDateString()
        let response: SupabaseTodayReadResponse = try await client.readContent(
            .today,
            context: context,
            todayDate: todayDate
        )

        guard let row = response.todayCard else {
            throw RepositoryError.noPublishedTodayCard(date: response.todayDate ?? todayDate)
        }

        return row.domainCard()
    }

    func weekCards(for context: WorkspaceContext) async throws -> [DailyCard] {
        let response: SupabaseTodayReadResponse = try await client.readContent(
            .today,
            context: context,
            todayDate: SupabaseDateFormatting.todayDateString()
        )

        return response.weekCards.map { $0.domainCard() }
    }

    func completeToday(
        card: DailyCard,
        decision: DailyDecision,
        context: WorkspaceContext
    ) async throws -> ArchiveEntry {
        try await client.writeContent(
            .completeToday(card: card, decision: decision, context: context)
        )

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

struct SupabaseTesterAccessRepository: TesterAccessRepository {
    let client: SupabaseClient

    func listTesters(context: WorkspaceContext) async throws -> [TesterAccessRecord] {
        let response: ManageTesterListResponse = try await invoke(
            ManageTesterRequest(action: "list", email: nil, memberID: nil, displayName: nil)
        )
        return response.testers
    }

    func inviteTester(email: String, displayName: String?, context: WorkspaceContext) async throws -> TesterAccessRecord {
        let response: ManageTesterMutationResponse = try await invoke(
            ManageTesterRequest(
                action: "invite",
                email: email,
                memberID: nil,
                displayName: displayName
            )
        )
        return response.tester
    }

    func resendTesterOTP(email: String, context: WorkspaceContext) async throws -> TesterAccessRecord {
        let response: ManageTesterMutationResponse = try await invoke(
            ManageTesterRequest(action: "resend", email: email, memberID: nil, displayName: nil)
        )
        return response.tester
    }

    func revokeTester(memberID: UUID, context: WorkspaceContext) async throws -> TesterAccessRecord {
        let response: ManageTesterMutationResponse = try await invoke(
            ManageTesterRequest(action: "revoke", email: nil, memberID: memberID, displayName: nil)
        )
        return response.tester
    }

    private func invoke<Response: Decodable>(_ request: ManageTesterRequest) async throws -> Response {
        do {
            return try await client.functions.invoke(
                "manage-testers",
                options: FunctionInvokeOptions(body: request)
            )
        } catch {
            if case FunctionsError.httpError(_, let data) = error,
               let response = try? JSONDecoder().decode(AuthenticationFunctionErrorResponse.self, from: data),
               let code = response.stableCode {
                throw RepositoryError.edgeFunction(code)
            }
            throw error
        }
    }
}

struct SupabaseWeeklyPlanRepository: WeeklyPlanRepository {
    let client: SupabaseClient

    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan {
        let response: SupabaseWeeklyReadResponse = try await client.readContent(.weekly, context: context)

        guard let planRow = response.weeklyPlan else {
            throw RepositoryError.missingFixture("No published weekly plan exists.")
        }

        return makeWeeklyPlan(
            row: planRow,
            cardRows: response.dailyCards,
            setupSections: response.weeklySetup?.setupSections ?? []
        )
    }

    func ideaBank(for context: WorkspaceContext) async throws -> [WeeklyIdea] {
        let response: SupabaseWeeklyReadResponse = try await client.readContent(.weekly, context: context)
        return response.ideaBank.map { $0.domainIdea() }
    }

    func publishWeek(
        _ plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        generatedDraft: GeneratedWeekDraft?,
        context: WorkspaceContext
    ) async throws -> WeeklyPublishResult {
        let response: SupabasePublishWeekResponse = try await client.functions.invoke(
            "publish-week",
            options: FunctionInvokeOptions(
                body: SupabasePublishWeekRequest(
                    plan: plan,
                    generatedDraft: generatedDraft,
                    context: context
                )
            )
        )

        let publishedPlan = if let generatedDraft, generatedDraft.weeklyPlanID == plan.id {
            generatedDraft.markedPublished.weeklyPlan(setupSections: plan.setupSections).softLockedForPublish
        } else {
            plan.softLockedForPublish
        }
        let cards = if let generatedDraft, generatedDraft.weeklyPlanID == plan.id {
            generatedDraft.markedPublished.publishedWeekCards
        } else {
            DailyCard.publishedCards(from: publishedPlan)
        }

        return WeeklyPublishResult(
            weeklyPlan: publishedPlan,
            weekCards: cards,
            todayCard: DailyCard.bestTodayCard(from: cards),
            summary: "Published \(response.dailyCardCount) cards to Creator Today."
        )
    }

    func selectIdeaForNextOpenDay(
        _ idea: WeeklyIdea,
        in plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        context: WorkspaceContext
    ) async throws -> WeeklySelectionUpdate {
        try await client.writeContent(
            .selectIdeaForNextOpenDay(idea: idea, plan: plan, context: context)
        )

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

    func updateWeeklySetupSections(
        _ sections: [WeeklySetupSection],
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        try await client.writeContent(
            .updateWeeklySetup(sections: sections, plan: plan, context: context)
        )

        var updatedPlan = plan
        updatedPlan.setupSections = sections
        return updatedPlan
    }

    private func makeWeeklyPlan(
        row: SupabaseWeeklyPlanRow,
        cardRows: [SupabaseDailyCardRow],
        setupSections: [WeeklySetupSection]
    ) -> WeeklyPlan {
        let days = cardRows.map { $0.weeklyDay() }
        let plannedCount = days.filter { $0.state == .planned }.count
        let backupCount = days.filter { $0.state == .backup }.count
        let openCount = days.filter { $0.state == .open }.count

        return WeeklyPlan(
            id: row.id,
            title: "Generate a Week",
            eyebrow: "MANAGER WEEKLY CONTROL",
            weekRange: SupabaseDateFormatting.weekRange(starting: row.weekStartDate),
            weekStartDate: row.weekStartDate,
            weekEndDate: SupabaseDateFormatting.weekEndDate(starting: row.weekStartDate),
            readinessLine: "\(plannedCount) ready, \(backupCount) backup, \(openCount) open",
            isSoftLocked: row.isSoftLocked || row.status == "published",
            days: days,
            setupSections: setupSections
        )
    }
}

struct SupabaseWeeklyGenerationRepository: WeeklyGenerationRepository {
    let client: SupabaseClient

    func generateWeek(
        creatorID: UUID,
        weekStartDate: String,
        weeklySetupID: UUID?,
        mode: GenerateWeekMode,
        context: WorkspaceContext
    ) async throws -> GeneratedWeekDraft {
        do {
            let initial = try await invokeGenerateWeek(
                SupabaseGenerateWeekRequest(
                    creatorID: creatorID,
                    weekStartDate: weekStartDate,
                    weeklySetupID: weeklySetupID,
                    mode: mode,
                    preserveManualEdits: true,
                    mock: nil,
                    responseMode: .sync
                )
            )

            switch initial {
            case .draft(let response):
                return response.domainDraft()
            case .running(let status):
                return try await pollGeneratedWeek(
                    generationID: status.generationID,
                    creatorID: creatorID
                )
            case .failed(let status):
                throw RepositoryError.edgeFunction(status.error ?? "invalid_generated_week")
            }
        } catch {
            if let code = SupabaseFunctionErrorMapper.errorCode(from: error) {
                throw RepositoryError.edgeFunction(code)
            }
            throw error
        }
    }

    func regenerateDay(
        creatorID: UUID,
        weeklyPlanID: UUID,
        scheduledDate: String,
        preserveManualEdits: Bool,
        context: WorkspaceContext
    ) async throws -> RegeneratedDayResult {
        do {
            let initial = try await invokeRegenerateDay(
                SupabaseRegenerateDayRequest(
                    creatorID: creatorID,
                    weeklyPlanID: weeklyPlanID,
                    scheduledDate: scheduledDate,
                    preserveManualEdits: preserveManualEdits
                )
            )

            switch initial {
            case .completed(let response):
                return response.domainResult
            case .running(let status):
                return try await pollRegeneratedDay(
                    generationID: status.generationID,
                    creatorID: creatorID
                )
            case .failed(let status):
                throw RepositoryError.edgeFunction(status.error ?? "invalid_generated_day")
            }
        } catch {
            if let code = SupabaseFunctionErrorMapper.errorCode(from: error) {
                throw RepositoryError.edgeFunction(code)
            }
            throw error
        }
    }

    private func pollGeneratedWeek(
        generationID: UUID,
        creatorID: UUID
    ) async throws -> GeneratedWeekDraft {
        let deadline = Date().addingTimeInterval(1_800)
        var pollAfterSeconds = 5

        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(pollAfterSeconds) * 1_000_000_000)
            let invocation = try await invokeGenerateWeek(
                SupabaseGenerateWeekStatusRequest(
                    generationID: generationID,
                    creatorID: creatorID
                )
            )

            switch invocation {
            case .draft(let response):
                return response.domainDraft()
            case .running(let status):
                pollAfterSeconds = max(2, min(status.pollAfterSeconds ?? 5, 15))
            case .failed(let status):
                throw RepositoryError.edgeFunction(status.error ?? "invalid_generated_week")
            }
        }

        throw RepositoryError.edgeFunction("generation_timeout")
    }

    private func invokeGenerateWeek<Body: Encodable>(
        _ body: Body
    ) async throws -> SupabaseGenerateWeekInvocation {
        try await client.functions.invoke(
            "generate-week",
            options: FunctionInvokeOptions(body: body)
        ) { data, _ in
            try SupabaseGenerateWeekInvocation.decode(data)
        }
    }

    private func pollRegeneratedDay(
        generationID: UUID,
        creatorID: UUID
    ) async throws -> RegeneratedDayResult {
        let deadline = Date().addingTimeInterval(600)
        var pollAfterSeconds = 3

        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(pollAfterSeconds) * 1_000_000_000)
            let invocation = try await invokeRegenerateDay(
                SupabaseGenerateWeekStatusRequest(
                    generationID: generationID,
                    creatorID: creatorID
                )
            )

            switch invocation {
            case .completed(let response):
                return response.domainResult
            case .running(let status):
                pollAfterSeconds = max(2, min(status.pollAfterSeconds ?? 3, 15))
            case .failed(let status):
                throw RepositoryError.edgeFunction(status.error ?? "invalid_generated_day")
            }
        }

        throw RepositoryError.edgeFunction("generation_timeout")
    }

    private func invokeRegenerateDay<Body: Encodable>(
        _ body: Body
    ) async throws -> SupabaseRegenerateDayInvocation {
        try await client.functions.invoke(
            "generate-week",
            options: FunctionInvokeOptions(body: body)
        ) { data, _ in
            try SupabaseRegenerateDayInvocation.decode(data)
        }
    }
}

private enum SupabaseFunctionErrorMapper {
    static func errorCode(from error: Error) -> String? {
        guard case FunctionsError.httpError(_, let data) = error else {
            return nil
        }

        return try? JSONDecoder().decode(SupabaseFunctionErrorPayload.self, from: data).error
    }
}

private struct SupabaseFunctionErrorPayload: Decodable {
    let error: String
}

struct SupabaseReferenceRepository: ReferenceRepository {
    let client: SupabaseClient

    func sourcePulse(for context: WorkspaceContext) async throws -> SourcePulseSummary {
        let response: SupabaseIntelligenceReadResponse = try await client.readContent(.intelligence, context: context)
        let rows = response.confirmedSourceReferences

        return SourcePulseSummary(
            title: "Source Pulse",
            subtitle: rows.isEmpty ? "No confirmed import references yet." : "\(rows.count) confirmed reel/audio references.",
            references: rows.map { $0.referenceSummary() }
        )
    }
}

struct SupabaseIntelligenceRepository: IntelligenceRepository {
    let client: SupabaseClient
    let references: SupabaseReferenceRepository

    func home(for context: WorkspaceContext) async throws -> IntelligenceHome {
        let response: SupabaseIntelligenceReadResponse = try await client.readContent(.intelligence, context: context)
        let confirmedReferences = response.confirmedSourceReferences
        let sourcePulseValue = SourcePulseSummary(
            title: "Source Pulse",
            subtitle: confirmedReferences.isEmpty ? "No confirmed import references yet." : "\(confirmedReferences.count) confirmed reel/audio references.",
            references: confirmedReferences.map { $0.referenceSummary() }
        )
        let patternItems = response.patterns.map { $0.intelligenceItem() }
        let trendItems = response.trends.map { $0.intelligenceItem() }
        let audioItems = response.audioOptions.map { $0.intelligenceItem() }
        let ideaItems = response.ideas.map { $0.intelligenceItem() }
        let reviewItems = (response.reviewSourceReferences.map { $0.reviewItem() }
            + response.candidateBenchmarkCreators.map { $0.reviewItem() })
            .sorted { ($0.sortKey ?? "") > ($1.sortKey ?? "") }
        let benchmarkCreatorCount = response.benchmarkCreatorCount
        let allSourceItems = patternItems + trendItems + audioItems
        let allItems = allSourceItems + ideaItems
        let needsReviewItems = (reviewItems + allItems.filter { $0.state == .needsReview })
            .sorted { ($0.sortKey ?? "") > ($1.sortKey ?? "") }

        return IntelligenceHome(
            sourcePulse: sourcePulseValue,
            readyForThisWeek: Array(allItems.filter { $0.state == .ready || $0.state == .approved }.prefix(4)),
            needsReview: Array(needsReviewItems.prefix(12)),
            ideaCandidates: Array(ideaItems.prefix(6)),
            recentlyUsed: Array(allItems.filter { $0.state == .usedThisWeek }.prefix(4)),
            librarySections: [
                IntelligenceLibrarySection(title: "Patterns", subtitle: "Reusable Creator-safe structures.", count: patternItems.count, symbol: "sun.max"),
                IntelligenceLibrarySection(title: "Trends", subtitle: "Manual USA feed observations.", count: trendItems.count, symbol: "sparkle.magnifyingglass"),
                IntelligenceLibrarySection(title: "Audio Options", subtitle: "Verified and fallback sounds.", count: audioItems.count, symbol: "music.note"),
                IntelligenceLibrarySection(title: "Ideas", subtitle: "Prepared card candidates.", count: ideaItems.count, symbol: "lightbulb"),
                IntelligenceLibrarySection(title: "Inspiration", subtitle: "Reference creators in the watchlist.", count: benchmarkCreatorCount, symbol: "at")
            ]
        )
    }
}

struct SupabaseCreatorProfileRepository: CreatorProfileRepository {
    let client: SupabaseClient

    func activeProfileSummary(for context: WorkspaceContext) async throws -> CreatorProfileSummary {
        let response: SupabaseCreatorProfileReadResponse = try await client.readContent(.creatorProfile, context: context)
        return response.profile?.summary() ?? .creatorFixture
    }
}

struct SupabaseArchiveRepository: ArchiveRepository {
    let client: SupabaseClient

    func entries(for context: WorkspaceContext) async throws -> [ArchiveEntry] {
        let response: SupabaseArchiveReadResponse = try await client.readContent(.archive, context: context)
        return response.entries.map { $0.domainEntry() }
    }

    func upsertDecision(
        _ entry: ArchiveEntry,
        for card: DailyCard,
        context: WorkspaceContext
    ) async throws -> [ArchiveEntry] {
        try await client.writeContent(
            .upsertArchiveDecision(entry, for: card, context: context)
        )

        return try await entries(for: context)
    }
}

private enum SupabaseSelect {
    static let dailyCard = """
        id,workspace_id,creator_id,weekly_plan_id,origin_idea_id,brand_brief_id,key_moment_id,scheduled_date,status,title,why_today,growth_job,content_pillar,shootability,estimated_shoot_minutes,energy_required,language_mode,scene_list,script,no_voiceover_version,on_screen_text,caption,cta,hashtags,cover_text,post_instructions,brand_event_notes,backup_story,backup_caption_only,audio_option_id,audio_fallback_id,creator_fit_score,risk_notes,assumptions,source_note,decision_at
        """

    static let weeklyPlan = """
        id,workspace_id,creator_id,weekly_setup_id,creator_profile_id,week_start_date,status,strategy_summary,warnings,assumptions,is_soft_locked,published_at
        """
}

private extension SupabaseClient {
    func readContent<Response: Decodable>(
        _ action: SupabaseReadContentRequest.Action,
        context: WorkspaceContext,
        todayDate: String? = nil
    ) async throws -> Response {
        try await functions.invoke(
            "read-content",
            options: FunctionInvokeOptions(
                body: SupabaseReadContentRequest(
                    action: action,
                    creatorID: context.creatorID,
                    todayDate: todayDate
                )
            )
        )
    }

    func writeContent(_ request: SupabaseWriteContentRequest) async throws {
        let _: SupabaseWriteContentResponse = try await functions.invoke(
            "write-content",
            options: FunctionInvokeOptions(body: request)
        )
    }
}

private extension SupabaseIdeaRow {
    func intelligenceItem() -> IntelligenceItem {
        IntelligenceItem(
            id: id,
            title: title,
            subtitle: summary ?? suggestedUse ?? "Idea",
            kind: .idea,
            state: IntelligenceReviewState(sourceStatus: status),
            trailingNote: shootability ?? status.displayTitle,
            symbol: "lightbulb"
        )
    }
}
