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

    func currentWeeklyContent(for context: WorkspaceContext) async throws -> WeeklyRepositoryContent {
        let response: SupabaseWeeklyReadResponse = try await client.readContent(.weekly, context: context)
        return try makeWeeklyContent(from: response)
    }

    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan {
        try await currentWeeklyContent(for: context).publishedPlan
    }

    func currentGeneratedDraft(for context: WorkspaceContext) async throws -> GeneratedWeekDraft? {
        try await currentWeeklyContent(for: context).generatedDraft
    }

    func ideaBank(for context: WorkspaceContext) async throws -> [WeeklyIdea] {
        try await currentWeeklyContent(for: context).ideaBank
    }

    func updateDailyCardReviewState(
        dailyCardID: UUID,
        reviewState: String,
        context: WorkspaceContext
    ) async throws {
        try await client.writeContent(
            .updateDailyCardReviewState(
                dailyCardID: dailyCardID,
                reviewState: reviewState,
                context: context
            )
        )
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
            generatedDraft.markedPublished.weeklyPlan(
                setupSections: plan.setupSections,
                weeklyBriefText: plan.weeklyBriefText
            ).softLockedForPublish
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

    func makeDayAvailable(
        scheduledDate: String,
        dailyCardID: UUID?,
        context: WorkspaceContext
    ) async throws -> DayAvailabilityResult {
        do {
            let response: SupabaseMakeDayAvailableResponse = try await client.functions.invoke(
                "make-day-available",
                options: FunctionInvokeOptions(
                    body: SupabaseMakeDayAvailableRequest(
                        creatorID: context.creatorID,
                        scheduledDate: scheduledDate,
                        dailyCardID: dailyCardID
                    )
                )
            )
            return DayAvailabilityResult(
                dailyCardID: response.dailyCardID,
                scheduledDate: response.scheduledDate,
                status: response.status,
                weeklyPlanID: response.weeklyPlanID,
                weekIsSoftLocked: response.weekIsSoftLocked
            )
        } catch {
            if let code = SupabaseFunctionErrorMapper.errorCode(from: error) {
                throw RepositoryError.edgeFunction(code)
            }
            throw error
        }
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

    func updateWeeklyBrief(
        _ text: String,
        in plan: WeeklyPlan,
        context: WorkspaceContext
    ) async throws -> WeeklyPlan {
        try await client.writeContent(
            .updateWeeklyBrief(text: text, plan: plan, context: context)
        )

        var updatedPlan = plan
        updatedPlan.weeklyBriefText = text
        return updatedPlan
    }

    private func makeWeeklyContent(from response: SupabaseWeeklyReadResponse) throws -> WeeklyRepositoryContent {
        guard let planRow = response.publishedWeeklyPlan ?? response.weeklyPlan else {
            throw RepositoryError.missingFixture("No published weekly plan exists.")
        }

        let publishedCardRows = response.publishedDailyCards.isEmpty
            ? response.dailyCards
            : response.publishedDailyCards
        guard !publishedCardRows.isEmpty else {
            throw RepositoryError.edgeFunction("weekly_plan_has_no_daily_cards")
        }

        let publishedSetupSections = (response.publishedWeeklySetup ?? response.weeklySetup)?.setupSections ?? []
        let publishedBriefText = (response.publishedWeeklySetup ?? response.weeklySetup)?.weeklyBriefText ?? ""

        let publishedPlan = makeWeeklyPlan(
            row: planRow,
            cardRows: publishedCardRows,
            setupSections: publishedSetupSections,
            weeklyBriefText: publishedBriefText
        )

        let generatedDraft: GeneratedWeekDraft?
        if response.weeklyPlan != nil, !response.dailyCards.isEmpty {
            generatedDraft = response.generatedDraft()
        } else {
            generatedDraft = nil
        }

        let workingPlan: WeeklyPlan?
        if let workingPlanRow = response.weeklyPlan, !response.dailyCards.isEmpty {
            workingPlan = WeeklyRepositoryContent.makeWorkingPlan(
                from: response.dailyCards,
                planRow: workingPlanRow,
                setupSections: response.weeklySetup?.setupSections ?? [],
                weeklyBriefText: response.weeklySetup?.weeklyBriefText ?? ""
            )
        } else {
            workingPlan = WeeklyRepositoryContent.makeWorkingPlan(
                from: generatedDraft,
                weekStartDate: response.weeklyPlan?.weekStartDate,
                setupSections: response.weeklySetup?.setupSections ?? [],
                weeklyBriefText: response.weeklySetup?.weeklyBriefText ?? ""
            )
        }

        let ideaBank = response.ideaBank.map { $0.domainIdea() }

        return WeeklyRepositoryContent(
            publishedPlan: publishedPlan,
            workingPlan: workingPlan,
            generatedDraft: generatedDraft,
            ideaBank: ideaBank
        )
    }

    private func makeWeeklyPlan(
        row: SupabaseWeeklyPlanRow,
        cardRows: [SupabaseDailyCardRow],
        setupSections: [WeeklySetupSection],
        weeklyBriefText: String
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
            weeklyBriefText: weeklyBriefText,
            setupSections: setupSections
        )
    }
}

struct SupabaseDayGenerationRepository: DayGenerationRepository, StoryboardThumbnailRepository {
    private enum DailyGenerationLogAction: String {
        case generateDay = "generate_day"
        case regenerateDay = "regenerate_day"
    }

    let client: SupabaseClient
    var runtimeConfiguration: SupabaseRuntimeConfiguration?

    func regenerateDay(
        creatorID: UUID,
        weeklyPlanID: UUID,
        scheduledDate: String,
        preserveManualEdits: Bool,
        dayGuidance: String?,
        context: WorkspaceContext
    ) async throws -> RegeneratedDayResult {
        do {
            logGeneration("regenerate_day invoke_initial scheduled_date=\(scheduledDate) guidance_chars=\(dayGuidance?.count ?? 0)")
            let initial = try await invokeRegenerateDay(
                SupabaseRegenerateDayRequest(
                    creatorID: creatorID,
                    weeklyPlanID: weeklyPlanID,
                    scheduledDate: scheduledDate,
                    preserveManualEdits: preserveManualEdits,
                    responseMode: .async,
                    dayGuidance: dayGuidance,
                    clientContext: SupabaseGenerationClientContext(
                        uiSurface: "weekly_manager",
                        action: "regenerate_day",
                        selectedWeekStart: nil,
                        scheduledDate: scheduledDate,
                        dayGuidancePresent: dayGuidance != nil,
                        dayGuidanceChars: dayGuidance?.count
                    )
                )
            )
            logGeneration("regenerate_day initial \(dailyGenerationInvocationSummary(initial))")

            switch initial {
            case .completed(let response):
                return response.domainResult
            case .running(let status):
                logGeneration("regenerate_day polling_start \(statusSummary(status))")
                return try await pollDailyGeneration(
                    generationID: status.generationID,
                    creatorID: creatorID,
                    logAction: .regenerateDay
                )
            case .failed(let status):
                logGeneration("regenerate_day initial_failed \(statusSummary(status))")
                throw RepositoryError.edgeFunction(status.error ?? "invalid_generated_day")
            }
        } catch {
            if let code = SupabaseFunctionErrorMapper.errorCode(from: error) {
                logGeneration("regenerate_day failed mapped_error=\(code)")
                throw RepositoryError.edgeFunction(code)
            }
            logGeneration("regenerate_day failed error=\(error.localizedDescription)")
            throw error
        }
    }

    func generateDay(
        creatorID: UUID,
        scheduledDate: String,
        dayBrief: String,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        do {
            logGeneration("generate_day invoke_initial scheduled_date=\(scheduledDate) brief_chars=\(dayBrief.count)")
            let initial = try await invokeDailyGeneration(
                SupabaseDailyGenerationRequest(
                    creatorID: creatorID,
                    scheduledDate: scheduledDate,
                    dayBrief: dayBrief,
                    responseMode: .async,
                    clientContext: SupabaseGenerationClientContext(
                        uiSurface: "daily_generator",
                        action: "generate_day",
                        selectedWeekStart: nil,
                        scheduledDate: scheduledDate,
                        dayGuidancePresent: true,
                        dayGuidanceChars: dayBrief.count
                    )
                )
            )
            logGeneration("generate_day initial \(dailyGenerationInvocationSummary(initial))")

            switch initial {
            case .completed(let response):
                return response.domainResult
            case .running(let status):
                logGeneration("generate_day polling_start \(statusSummary(status))")
                return try await pollDailyGeneration(
                    generationID: status.generationID,
                    creatorID: creatorID,
                    logAction: .generateDay
                )
            case .failed(let status):
                logGeneration("generate_day initial_failed \(statusSummary(status))")
                throw RepositoryError.edgeFunction(status.error ?? "invalid_generated_day")
            }
        } catch {
            if let code = SupabaseFunctionErrorMapper.errorCode(from: error) {
                logGeneration("generate_day failed mapped_error=\(code)")
                throw RepositoryError.edgeFunction(code)
            }
            logGeneration("generate_day failed error=\(error.localizedDescription)")
            throw error
        }
    }

    func generateStoryboardThumbnails(
        creatorID: UUID,
        dailyCardID: UUID,
        rowIndexes: [Int]?,
        force: Bool,
        revisionInstructions: String?,
        context: WorkspaceContext
    ) async throws -> [StoryboardThumbnailAsset] {
        do {
            let response: SupabaseGenerateStoryboardThumbnailResponse = try await client.functions.invoke(
                "generate-storyboard-thumbnail",
                options: FunctionInvokeOptions(
                    body: SupabaseGenerateStoryboardThumbnailRequest(
                        creatorID: creatorID,
                        dailyCardID: dailyCardID,
                        rowIndexes: rowIndexes,
                        force: force,
                        revisionInstructions: revisionInstructions
                    )
                )
            )
            return response.assets
        } catch {
            if let code = SupabaseFunctionErrorMapper.errorCode(from: error) {
                throw RepositoryError.edgeFunction(code)
            }
            throw error
        }
    }

    private func pollDailyGeneration(
        generationID: UUID,
        creatorID: UUID,
        logAction: DailyGenerationLogAction
    ) async throws -> DailyGenerationResult {
        let action = logAction.rawValue
        return try await SupabaseDailyGenerationPoller.poll(
            deadline: Date().addingTimeInterval(SupabaseDailyGenerationPoller.defaultTimeoutSeconds),
            sleep: { nanoseconds in
                try await Task.sleep(nanoseconds: nanoseconds)
            },
            invokeStatus: {
                let invocation = try await invokeDailyGeneration(
                    statusRequest(generationID: generationID, creatorID: creatorID)
                )
                logGeneration("\(action) poll_result \(dailyGenerationInvocationSummary(invocation))")
                return invocation
            },
            observe: { event in
                switch event {
                case .waiting(let seconds):
                    logGeneration("\(action) poll_wait generation_id=\(generationID) seconds=\(seconds)")
                case .acceptedRunNotFound(let count, let retryAfterSeconds):
                    logGeneration("\(action) poll accepted_run_not_found count=\(count) retrying_after=\(retryAfterSeconds)s")
                case .retryableStatusFailure(let count, let retryAfterSeconds):
                    logGeneration("\(action) poll retryable_status_failure count=\(count) retrying_after=\(retryAfterSeconds)s")
                case .completed(let completedGenerationID, let scheduledDate):
                    logGeneration("\(action) poll_terminal completed generation_id=\(completedGenerationID) scheduled_date=\(scheduledDate)")
                case .failed(let status):
                    logGeneration("\(action) poll_terminal failed \(statusSummary(status))")
                case .timedOut:
                    logGeneration("\(action) poll_timeout generation_id=\(generationID)")
                }
            }
        )
    }

    private func invokeRegenerateDay<Body: Encodable>(
        _ body: Body
    ) async throws -> SupabaseRegenerateDayInvocation {
        try await invokeDailyGeneration(body)
    }

    private func invokeDailyGeneration<Body: Encodable>(
        _ body: Body
    ) async throws -> SupabaseDailyGenerationInvocation {
        if let statusBody = body as? SupabaseGenerationStatusRequest,
           let runtimeConfiguration {
            return try await invokeGenerationEdgeFunctionDirectly(
                statusBody,
                runtimeConfiguration: runtimeConfiguration,
                decode: { try SupabaseDailyGenerationInvocation.decode($0) }
            )
        }

        return try await client.functions.invoke(
            "generate-week",
            options: FunctionInvokeOptions(body: body)
        ) { data, _ in
            try SupabaseDailyGenerationInvocation.decode(data)
        }
    }

    private func statusRequest(
        generationID: UUID,
        creatorID: UUID
    ) -> SupabaseGenerationStatusRequest {
        SupabaseGenerationStatusRequest(
            generationID: generationID,
            creatorID: creatorID
        )
    }

    private func logGeneration(_ message: String) {
        print("[ContentHelperGenerationRepository] \(Date()) \(message)")
    }

    private func dailyGenerationInvocationSummary(_ invocation: SupabaseDailyGenerationInvocation) -> String {
        switch invocation {
        case .completed(let response):
            return "completed generation_id=\(response.generationID) weekly_plan_id=\(response.weeklyPlanID) scheduled_date=\(response.targetScheduledDate) status=\(response.status)"
        case .running(let status):
            return "running \(statusSummary(status))"
        case .failed(let status):
            return "failed \(statusSummary(status))"
        }
    }

    private func statusSummary(_ status: SupabaseGenerationStatusResponse) -> String {
        [
            "generation_id=\(status.generationID)",
            "weekly_plan_id=\(status.weeklyPlanID?.uuidString ?? "none")",
            "status=\(status.status)",
            status.targetScheduledDate.map { "target_scheduled_date=\($0)" },
            status.message.map { "message=\($0)" },
            status.pollAfterSeconds.map { "poll_after=\($0)" },
            status.error.map { "error=\($0)" }
        ]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private func invokeGenerationEdgeFunctionDirectly<Response>(
        _ body: some Encodable,
        runtimeConfiguration: SupabaseRuntimeConfiguration,
        decode: (Data) throws -> Response
    ) async throws -> Response {
        let endpoint = runtimeConfiguration.projectURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent("generate-week")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(runtimeConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue(
            "Bearer \(runtimeConfiguration.publishableKey)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("CreatorContentOS-iOS", forHTTPHeaderField: "x-client")
        if let deviceToken = runtimeConfiguration.deviceToken?.nilIfBlank {
            request.setValue(deviceToken, forHTTPHeaderField: "x-mco-device-token")
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DirectFunctionHTTPError(
                status: (response as? HTTPURLResponse)?.statusCode ?? -1,
                data: data
            )
        }
        return try decode(data)
    }
}

private struct DirectFunctionHTTPError: Error {
    let status: Int
    let data: Data
}

enum SupabaseDailyGenerationPoller {
    enum Event: Sendable {
        case waiting(seconds: Int)
        case acceptedRunNotFound(count: Int, retryAfterSeconds: Int)
        case retryableStatusFailure(count: Int, retryAfterSeconds: Int)
        case completed(generationID: UUID, scheduledDate: String)
        case failed(SupabaseGenerationStatusResponse)
        case timedOut
    }

    static let defaultTimeoutSeconds: TimeInterval = 1_800

    static func poll(
        deadline: Date,
        now: @Sendable () -> Date = Date.init,
        initialPollAfterSeconds: Int = 3,
        sleep: @Sendable (UInt64) async throws -> Void,
        invokeStatus: @Sendable () async throws -> SupabaseDailyGenerationInvocation,
        observe: @Sendable (Event) -> Void = { _ in }
    ) async throws -> DailyGenerationResult {
        var pollAfterSeconds = initialPollAfterSeconds
        var acceptedRunNotFoundCount = 0
        var retryableStatusFailureCount = 0

        while now() < deadline {
            observe(.waiting(seconds: pollAfterSeconds))
            try await sleep(UInt64(max(pollAfterSeconds, 0)) * 1_000_000_000)
            let invocation: SupabaseDailyGenerationInvocation
            do {
                invocation = try await invokeStatus()
            } catch {
                if SupabaseGenerationRetryPolicy.isAcceptedRunNotFoundStatusError(error) {
                    acceptedRunNotFoundCount += 1
                    pollAfterSeconds = acceptedRunNotFoundCount < 6 ? 2 : 5
                    observe(.acceptedRunNotFound(
                        count: acceptedRunNotFoundCount,
                        retryAfterSeconds: pollAfterSeconds
                    ))
                    continue
                }
                guard SupabaseGenerationRetryPolicy.isRetryableStatusPollingError(error) else {
                    throw error
                }
                retryableStatusFailureCount += 1
                pollAfterSeconds = switch retryableStatusFailureCount {
                case 1: 2
                case 2: 4
                case 3: 8
                default: 15
                }
                observe(.retryableStatusFailure(
                    count: retryableStatusFailureCount,
                    retryAfterSeconds: pollAfterSeconds
                ))
                continue
            }

            retryableStatusFailureCount = 0
            switch invocation {
            case .completed(let response):
                observe(.completed(
                    generationID: response.generationID,
                    scheduledDate: response.targetScheduledDate
                ))
                return response.domainResult
            case .running(let status):
                acceptedRunNotFoundCount = 0
                pollAfterSeconds = max(2, min(status.pollAfterSeconds ?? 3, 15))
            case .failed(let status):
                observe(.failed(status))
                throw RepositoryError.edgeFunction(status.error ?? "invalid_generated_day")
            }
        }

        observe(.timedOut)
        throw RepositoryError.edgeFunction("generation_timeout")
    }
}

enum SupabaseGenerationRetryPolicy {
    private static let terminalStatusErrorCodes: Set<String> = [
        "creator_member_not_found",
        "creator_not_found",
        "cross_workspace_forbidden",
        "daily_card_not_found",
        "date_not_in_plan",
        "device_session_failed",
        "existing_published_week_locked",
        "invalid_auth_session",
        "invalid_device_session",
        "invalid_device_token",
        "invalid_generated_week",
        "invalid_generation_payload",
        "method_not_allowed",
        "missing_device_token",
        "missing_function_secrets",
        "missing_openai_api_key",
        "past_generation_date_not_allowed",
        "weekly_plan_not_found",
        "weekly_setup_not_found",
    ]

    static func isTransientPollingError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return [
                NSURLErrorNetworkConnectionLost,
                NSURLErrorTimedOut,
                NSURLErrorCannotConnectToHost,
                NSURLErrorCannotFindHost,
                NSURLErrorDNSLookupFailed,
                NSURLErrorNotConnectedToInternet
            ].contains(nsError.code)
        }

        let description = error.localizedDescription.lowercased()
        return description.contains("network connection was lost") ||
            description.contains("timed out") ||
            description.contains("could not connect to the server") ||
            description.contains("internet connection appears to be offline")
    }

    static func isRetryableStatusPollingError(_ error: Error) -> Bool {
        if isAcceptedRunNotFoundStatusError(error) {
            return true
        }

        if let code = SupabaseFunctionErrorMapper.errorCode(from: error),
           terminalStatusErrorCodes.contains(code) {
            return false
        }

        if isTransientPollingError(error) {
            return true
        }

        guard let httpError = functionHTTPError(error) else {
            return false
        }

        return [408, 429, 500, 502, 503, 504].contains(httpError.status)
    }

    static func isAcceptedRunNotFoundStatusError(_ error: Error) -> Bool {
        guard let httpError = functionHTTPError(error),
              httpError.status == 404,
              let payload = try? JSONDecoder().decode(SupabaseFunctionErrorPayload.self, from: httpError.data)
        else {
            return false
        }

        return payload.error == "invalid_generation_payload"
    }
}

private enum SupabaseFunctionErrorMapper {
    static func errorCode(from error: Error) -> String? {
        guard let httpError = functionHTTPError(error) else {
            return nil
        }

        return try? JSONDecoder().decode(SupabaseFunctionErrorPayload.self, from: httpError.data).error
    }
}

private func functionHTTPError(_ error: Error) -> (status: Int, data: Data)? {
    if case FunctionsError.httpError(let status, let data) = error {
        return (status, data)
    }
    if let directError = error as? DirectFunctionHTTPError {
        return (directError.status, directError.data)
    }
    return nil
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

    func updateProfile(_ update: CreatorProfileUpdate, context: WorkspaceContext) async throws -> CreatorProfileSummary {
        let response: SupabaseWriteContentResponse = try await client.functions.invoke(
            "write-content",
            options: FunctionInvokeOptions(
                body: SupabaseWriteContentRequest.updateCreatorProfile(update, context: context)
            )
        )

        return response.creatorProfile?.summary() ?? CreatorProfileSummary(
            displayName: "Creator",
            positioning: update.positioning,
            voiceLine: update.voiceRules.joined(separator: ", "),
            noGoTopics: update.noGoTopics,
            voiceRules: update.voiceRules,
            contentPillars: update.contentPillars,
            captionStyle: update.captionStyle,
            recurringFormats: update.recurringFormats
        )
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

enum SupabaseSelect {
    static let dailyCard = """
        id,workspace_id,creator_id,weekly_plan_id,origin_idea_id,brand_brief_id,key_moment_id,scheduled_date,status,review_state,title,why_today,growth_job,content_pillar,shootability,estimated_shoot_minutes,energy_required,language_mode,scene_list,script,no_voiceover_version,on_screen_text,caption,cta,hashtags,cover_text,post_instructions,brand_event_notes,backup_story,backup_caption_only,audio_option_id,audio_fallback_id,creator_fit_score,risk_notes,assumptions,source_note,decision_at,storyboard_thumbnail_assets
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
        let requestBody = SupabaseReadContentRequest(
            action: action,
            creatorID: context.creatorID,
            todayDate: todayDate
        )
        var attempts = 0
        while true {
            do {
                return try await functions.invoke(
                    "read-content",
                    options: FunctionInvokeOptions(body: requestBody)
                )
            } catch {
                attempts += 1
                guard attempts < 3, SupabaseGenerationRetryPolicy.isTransientPollingError(error) else {
                    throw error
                }
                try await Task.sleep(nanoseconds: UInt64(attempts) * 1_000_000_000)
            }
        }
    }

    func writeContent(_ request: SupabaseWriteContentRequest) async throws {
        do {
            let response: SupabaseWriteContentResponse = try await functions.invoke(
                "write-content",
                options: FunctionInvokeOptions(body: request)
            )
            if let error = response.error?.nilIfBlank {
                throw RepositoryError.edgeFunction(error)
            }
        } catch {
            if let code = SupabaseFunctionErrorMapper.errorCode(from: error) {
                throw RepositoryError.edgeFunction(code)
            }
            throw error
        }
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
