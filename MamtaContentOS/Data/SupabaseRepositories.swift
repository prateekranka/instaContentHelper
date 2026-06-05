import Foundation
import Supabase

struct SupabaseTodayCardRepository: TodayCardRepository {
    let client: SupabaseClient

    func todayCard(for context: WorkspaceContext) async throws -> DailyCard {
        let rows: [SupabaseDailyCardRow] = try await client
            .from(SupabaseContentTable.dailyCards.rawValue)
            .select(SupabaseSelect.dailyCard)
            .eq("creator_id", value: context.creatorID.uuidString)
            .eq("scheduled_date", value: SupabaseDateFormatting.todayDateString())
            .limit(1)
            .execute()
            .value

        guard let row = rows.first else {
            throw RepositoryError.missingFixture("No published daily card exists for today.")
        }

        return row.domainCard()
    }

    func weekCards(for context: WorkspaceContext) async throws -> [DailyCard] {
        let rows: [SupabaseDailyCardRow] = try await client
            .from(SupabaseContentTable.dailyCards.rawValue)
            .select(SupabaseSelect.dailyCard)
            .eq("creator_id", value: context.creatorID.uuidString)
            .order("scheduled_date", ascending: true)
            .limit(14)
            .execute()
            .value

        return rows.map { $0.domainCard() }
    }

    func completeToday(
        card: DailyCard,
        decision: CompletionState,
        context: WorkspaceContext
    ) async throws -> ArchiveEntry {
        try await client
            .from(SupabaseContentTable.dailyCards.rawValue)
            .update(
                SupabaseDailyCardDecisionUpdate(
                    status: decision.supabaseStatus,
                    decisionAt: SupabaseDateFormatting.isoTimestampString(),
                    completedByMemberID: context.memberID
                )
            )
            .eq("id", value: card.id.uuidString)
            .execute()

        return ArchiveEntry(
            day: SupabaseDateFormatting.weekdayAbbreviation(for: SupabaseDateFormatting.todayDateString()),
            date: SupabaseDateFormatting.shortDate(for: SupabaseDateFormatting.todayDateString()),
            cardTitle: card.title,
            decision: decision,
            outputLine: decision.archiveLabel,
            hasPostThumbnail: decision == .posted
        )
    }
}

struct SupabaseWeeklyPlanRepository: WeeklyPlanRepository {
    let client: SupabaseClient

    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan {
        let rows: [SupabaseWeeklyPlanRow] = try await client
            .from(SupabaseContentTable.weeklyPlans.rawValue)
            .select(SupabaseSelect.weeklyPlan)
            .eq("creator_id", value: context.creatorID.uuidString)
            .eq("status", value: "published")
            .order("week_start_date", ascending: false)
            .limit(1)
            .execute()
            .value

        guard let planRow = rows.first else {
            throw RepositoryError.missingFixture("No published weekly plan exists.")
        }

        let cardRows: [SupabaseDailyCardRow] = try await client
            .from(SupabaseContentTable.dailyCards.rawValue)
            .select(SupabaseSelect.dailyCard)
            .eq("weekly_plan_id", value: planRow.id.uuidString)
            .order("scheduled_date", ascending: true)
            .execute()
            .value

        let setupSections = try await setupSections(for: planRow.weeklySetupID)
        return makeWeeklyPlan(row: planRow, cardRows: cardRows, setupSections: setupSections)
    }

    func ideaBank(for context: WorkspaceContext) async throws -> [WeeklyIdea] {
        let rows: [SupabaseIdeaRow] = try await client
            .from(SupabaseContentTable.ideas.rawValue)
            .select("id,title,summary,suggested_use,shootability,status")
            .eq("creator_id", value: context.creatorID.uuidString)
            .order("updated_at", ascending: false)
            .limit(25)
            .execute()
            .value

        return rows.map { $0.domainIdea() }
    }

    func publishWeek(
        _ plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        context: WorkspaceContext
    ) async throws -> WeeklyPublishResult {
        let response: SupabasePublishWeekResponse = try await client.functions.invoke(
            "publish-week",
            options: FunctionInvokeOptions(
                body: SupabasePublishWeekRequest(plan: plan, context: context)
            )
        )

        let publishedPlan = plan.softLockedForPublish
        let cards = DailyCard.publishedCards(from: publishedPlan)

        return WeeklyPublishResult(
            weeklyPlan: publishedPlan,
            weekCards: cards,
            todayCard: DailyCard.bestTodayCard(from: cards),
            summary: "Published \(response.dailyCardCount) cards to Mamta Today."
        )
    }

    func selectIdeaForNextOpenDay(
        _ idea: WeeklyIdea,
        in plan: WeeklyPlan,
        ideaBank: [WeeklyIdea],
        context: WorkspaceContext
    ) async throws -> WeeklySelectionUpdate {
        try await client
            .from(SupabaseContentTable.ideas.rawValue)
            .update(["status": "scheduled"])
            .eq("id", value: idea.id.uuidString)
            .execute()

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

    private func setupSections(for setupID: UUID?) async throws -> [WeeklySetupSection] {
        guard let setupID else { return [] }

        let rows: [SupabaseWeeklySetupRow] = try await client
            .from(SupabaseContentTable.weeklySetups.rawValue)
            .select(
                """
                id,location,workout_race_schedule,family_travel_moments,energy_constraints,shooting_constraints,no_go_topics,selected_sources,notes
                """
            )
            .eq("id", value: setupID.uuidString)
            .limit(1)
            .execute()
            .value

        return rows.first?.setupSections ?? []
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
            title: "Weekly Plan",
            eyebrow: "PRATEEK WEEKLY CONTROL",
            weekRange: SupabaseDateFormatting.weekRange(starting: row.weekStartDate),
            weekStartDate: row.weekStartDate,
            readinessLine: "\(plannedCount) ready, \(backupCount) backup, \(openCount) open",
            isSoftLocked: row.isSoftLocked || row.status == "published",
            days: days,
            setupSections: setupSections
        )
    }
}

struct SupabaseReferenceRepository: ReferenceRepository {
    let client: SupabaseClient

    func sourcePulse(for context: WorkspaceContext) async throws -> SourcePulseSummary {
        let rows: [SupabaseSourceReferenceRow] = try await client
            .from(SupabaseContentTable.sourceReferences.rawValue)
            .select("id,source_type,source_url,storage_path,manual_notes,status,analysis_confidence")
            .eq("creator_id", value: context.creatorID.uuidString)
            .order("created_at", ascending: false)
            .limit(8)
            .execute()
            .value

        return SourcePulseSummary(
            title: "Source Pulse",
            subtitle: rows.isEmpty ? "No references yet." : "\(rows.count) recent references.",
            references: rows.map { $0.referenceSummary() }
        )
    }
}

struct SupabaseIntelligenceRepository: IntelligenceRepository {
    let client: SupabaseClient
    let references: SupabaseReferenceRepository

    func home(for context: WorkspaceContext) async throws -> IntelligenceHome {
        async let sourcePulse = references.sourcePulse(for: context)
        async let patterns = intelligencePatterns(for: context)
        async let trends = intelligenceTrends(for: context)
        async let audioOptions = intelligenceAudioOptions(for: context)
        async let ideas = intelligenceIdeas(for: context)

        let sourcePulseValue = try await sourcePulse
        let patternItems = try await patterns
        let trendItems = try await trends
        let audioItems = try await audioOptions
        let ideaItems = try await ideas
        let allSourceItems = patternItems + trendItems + audioItems
        let allItems = allSourceItems + ideaItems

        return IntelligenceHome(
            sourcePulse: sourcePulseValue,
            readyForThisWeek: Array(allItems.filter { $0.state == .ready || $0.state == .approved }.prefix(4)),
            needsReview: Array(allItems.filter { $0.state == .needsReview }.prefix(4)),
            ideaCandidates: Array(ideaItems.prefix(6)),
            recentlyUsed: Array(allItems.filter { $0.state == .usedThisWeek }.prefix(4)),
            librarySections: [
                IntelligenceLibrarySection(title: "Patterns", subtitle: "Reusable Mamta-safe structures.", count: patternItems.count, symbol: "sun.max"),
                IntelligenceLibrarySection(title: "Trends", subtitle: "Manual USA feed observations.", count: trendItems.count, symbol: "sparkle.magnifyingglass"),
                IntelligenceLibrarySection(title: "Audio Options", subtitle: "Verified and fallback sounds.", count: audioItems.count, symbol: "music.note"),
                IntelligenceLibrarySection(title: "Ideas", subtitle: "Prepared card candidates.", count: ideaItems.count, symbol: "lightbulb")
            ]
        )
    }

    private func intelligencePatterns(for context: WorkspaceContext) async throws -> [IntelligenceItem] {
        let rows: [SupabasePatternRow] = try await client
            .from(SupabaseContentTable.patterns.rawValue)
            .select("id,title,pattern_type,summary,status")
            .eq("creator_id", value: context.creatorID.uuidString)
            .order("updated_at", ascending: false)
            .limit(20)
            .execute()
            .value

        return rows.map { $0.intelligenceItem() }
    }

    private func intelligenceTrends(for context: WorkspaceContext) async throws -> [IntelligenceItem] {
        let rows: [SupabaseTrendRow] = try await client
            .from(SupabaseContentTable.trends.rawValue)
            .select("id,title,summary,status,timing_recommendation")
            .eq("creator_id", value: context.creatorID.uuidString)
            .order("updated_at", ascending: false)
            .limit(20)
            .execute()
            .value

        return rows.map { $0.intelligenceItem() }
    }

    private func intelligenceAudioOptions(for context: WorkspaceContext) async throws -> [IntelligenceItem] {
        let rows: [SupabaseAudioOptionRow] = try await client
            .from(SupabaseContentTable.audioOptions.rawValue)
            .select("id,title,artist_or_creator,availability_confidence,verification_note,status")
            .eq("creator_id", value: context.creatorID.uuidString)
            .order("updated_at", ascending: false)
            .limit(20)
            .execute()
            .value

        return rows.map { $0.intelligenceItem() }
    }

    private func intelligenceIdeas(for context: WorkspaceContext) async throws -> [IntelligenceItem] {
        let rows: [SupabaseIdeaRow] = try await client
            .from(SupabaseContentTable.ideas.rawValue)
            .select("id,title,summary,suggested_use,shootability,status")
            .eq("creator_id", value: context.creatorID.uuidString)
            .order("updated_at", ascending: false)
            .limit(20)
            .execute()
            .value

        return rows.map { $0.intelligenceItem() }
    }
}

struct SupabaseCreatorProfileRepository: CreatorProfileRepository {
    let client: SupabaseClient

    func activeProfileSummary(for context: WorkspaceContext) async throws -> CreatorProfileSummary {
        let rows: [SupabaseCreatorProfileRow] = try await client
            .from(SupabaseContentTable.creatorProfiles.rawValue)
            .select("positioning,voice_rules,never_say")
            .eq("creator_id", value: context.creatorID.uuidString)
            .eq("status", value: "active")
            .order("version", ascending: false)
            .limit(1)
            .execute()
            .value

        return rows.first?.summary() ?? .mamtaFixture
    }
}

struct SupabaseArchiveRepository: ArchiveRepository {
    let client: SupabaseClient

    func entries(for context: WorkspaceContext) async throws -> [ArchiveEntry] {
        let rows: [SupabaseArchiveEntryRow] = try await client
            .from(SupabaseContentTable.archiveEntries.rawValue)
            .select("id,archive_date,decision,output_line,has_post_thumbnail,daily_cards(title)")
            .eq("creator_id", value: context.creatorID.uuidString)
            .order("archive_date", ascending: false)
            .limit(50)
            .execute()
            .value

        return rows.map { $0.domainEntry() }
    }

    func upsertDecision(
        _ entry: ArchiveEntry,
        for card: DailyCard,
        context: WorkspaceContext
    ) async throws -> [ArchiveEntry] {
        try await client
            .from(SupabaseContentTable.archiveEntries.rawValue)
            .upsert(
                SupabaseArchiveEntryUpsert(
                    workspaceID: context.workspaceID,
                    creatorID: context.creatorID,
                    dailyCardID: card.id,
                    archiveDate: SupabaseDateFormatting.todayDateString(),
                    decision: entry.decision.supabaseStatus,
                    outputLine: entry.outputLine,
                    hasPostThumbnail: entry.hasPostThumbnail
                ),
                onConflict: "daily_card_id"
            )
            .execute()

        return try await entries(for: context)
    }
}

private enum SupabaseSelect {
    static let dailyCard = """
        id,workspace_id,creator_id,weekly_plan_id,origin_idea_id,brand_brief_id,key_moment_id,scheduled_date,status,title,why_today,growth_job,content_pillar,shootability,estimated_shoot_minutes,energy_required,language_mode,scene_list,script,no_voiceover_version,on_screen_text,caption,cta,hashtags,cover_text,post_instructions,brand_event_notes,backup_story,backup_caption_only,audio_option_id,audio_fallback_id,mamta_fit_score,risk_notes,assumptions,source_note,decision_at
        """

    static let weeklyPlan = """
        id,workspace_id,creator_id,weekly_setup_id,creator_profile_id,week_start_date,status,strategy_summary,warnings,assumptions,is_soft_locked,published_at
        """
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
