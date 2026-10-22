import Foundation

private typealias FakeObject = [String: SupabaseJSONValue]

private enum FakeJSON {
    static func value(_ value: some Encodable) throws -> SupabaseJSONValue {
        try JSONDecoder().decode(SupabaseJSONValue.self, from: JSONEncoder().encode(value))
    }

    static func object(_ value: some Encodable) throws -> FakeObject {
        guard let object = try self.value(value).objectValue else { throw RepositoryError.edgeFunction("invalid_write_payload") }
        return object
    }

    static func decode<T: Decodable>(_ value: SupabaseJSONValue, as type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(value))
    }
}

private extension Dictionary where Key == String, Value == SupabaseJSONValue {
    func text(_ key: String) -> String? {
        guard case .string(let text) = self[key] else { return nil }
        return text
    }

    func uuid(_ key: String) -> UUID? { text(key).flatMap(UUID.init(uuidString:)) }
    func flag(_ key: String) -> Bool { self[key] == .bool(true) }
}

struct FakeServerResponse: Sendable {
    var statusCode: Int
    var body: SupabaseJSONValue
}

private struct FakeServerDay: Codable, Sendable {
    var currentRevisionID: UUID?
    var generationKey: String?
    var updatedAt: String = SupabaseDateFormatting.isoTimestampString()
}

private struct FakeServerPiece: Codable, Sendable {
    var id: UUID = UUID()
    var workspaceID: UUID
    var creatorID: UUID
    var scheduledDate: String
    var position: Int
    var currentRevisionID: UUID?
    var generationKey: String?
    var updatedAt: String = SupabaseDateFormatting.isoTimestampString()
    var removedAt: String?
}

private struct FakePieceTargetError: Error {
    var code: String
    var status: Int
}

private struct LegacyFakeServerDays: Decodable {
    var days: [String: FakeServerDay]
}

private struct FakeServerRun: Codable, Sendable {
    var pieceID: UUID? = nil
    var id: UUID = UUID()
    var revisionID: UUID = UUID()
    var planID: UUID
    var scheduledDate: String
    var identity: FakeObject
    var replacedRevisionID: UUID?
    var status: String = "running"
    var error: String?
    var readyAt: Date
    var updatedAt: Date = Date()
    var completedAt: String?
    var result: SupabaseJSONValue?
}

private struct FakeServerSnapshot: Codable, Sendable {
    var schemaVersion = 2
    var revisions: [UUID: FakeObject] = [:]
    var pieces: [UUID: FakeServerPiece] = [:]
    var archives: [UUID: FakeObject] = [:]
    var runs: [String: FakeServerRun] = [:]
    var profile: FakeObject = [:]
    var plans: [UUID: WeeklyPlan] = [:]
    var plan: WeeklyPlan = .raceWeek
    var ideas: [FakeObject] = []
    var consumedFailures: Set<String> = []
    var moves: [String: FakeObject] = [:]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, revisions, pieces, archives, runs, profile, plans, plan, ideas, consumedFailures, moves
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        moves = try values.decodeIfPresent([String: FakeObject].self, forKey: .moves) ?? [:]
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        revisions = try values.decode([UUID: FakeObject].self, forKey: .revisions)
        pieces = try values.decodeIfPresent([UUID: FakeServerPiece].self, forKey: .pieces) ?? [:]
        archives = try values.decode([UUID: FakeObject].self, forKey: .archives)
        runs = try values.decode([String: FakeServerRun].self, forKey: .runs)
        profile = try values.decode(FakeObject.self, forKey: .profile)
        plans = try values.decode([UUID: WeeklyPlan].self, forKey: .plans)
        plan = try values.decode(WeeklyPlan.self, forKey: .plan)
        ideas = try values.decode([FakeObject].self, forKey: .ideas)
        consumedFailures = try values.decode(Set<String>.self, forKey: .consumedFailures)
    }

    mutating func compatibilityPiece(for date: String, context: WorkspaceContext) -> UUID {
        if let piece = pieces.values.first(where: {
            $0.workspaceID == context.workspaceID && $0.creatorID == context.creatorID
                && $0.scheduledDate == date && $0.position == 0 && $0.removedAt == nil
        }) { return piece.id }
        let piece = FakeServerPiece(workspaceID: context.workspaceID, creatorID: context.creatorID,
                                    scheduledDate: date, position: 0)
        pieces[piece.id] = piece
        return piece.id
    }

    mutating func migrate(days: [String: FakeServerDay], context: WorkspaceContext) {
        let dates = Set(days.keys).union(revisions.values.compactMap { $0.text("scheduled_date") })
            .union(runs.values.map(\.scheduledDate))
        for date in dates.sorted() {
            let id = compatibilityPiece(for: date, context: context)
            pieces[id]?.currentRevisionID = days[date]?.currentRevisionID
            pieces[id]?.generationKey = days[date]?.generationKey
            if let updatedAt = days[date]?.updatedAt { pieces[id]?.updatedAt = updatedAt }
            for revisionID in revisions.keys where revisions[revisionID]?.text("scheduled_date") == date {
                revisions[revisionID]?["piece_id"] = .string(id.uuidString)
                if revisions[revisionID]?.flag("is_current") == true, revisionID != days[date]?.currentRevisionID {
                    revisions[revisionID]?["is_current"] = .bool(false)
                }
            }
            for key in runs.keys where runs[key]?.scheduledDate == date {
                runs[key]?.pieceID = id
                if var result = runs[key]?.result?.objectValue {
                    result["piece_id"] = .string(id.uuidString)
                    if var card = result["daily_card"]?.objectValue {
                        card["piece_id"] = .string(id.uuidString)
                        result["daily_card"] = .object(card)
                    }
                    runs[key]?.result = .object(result)
                }
            }
        }
        for id in archives.keys { archives[id]?["piece_id"] = revisions[id]?["piece_id"] }
        schemaVersion = 2
    }
}

actor FakeServer {
    static let shared = FakeServer()
    nonisolated let initialDayPackages: [GeneratedDailyCardDraft]
    nonisolated let initialArchiveEntries: [ArchiveEntry]
    nonisolated let initialProfile: CreatorProfileSummary
    private var state: FakeServerSnapshot
    private let defaults: UserDefaults?
    private let context: WorkspaceContext
    private static let persistenceKey = "fake-server-v1"
    private static let readyStatuses = DayPackageLifecycleStatus.readyOrDecision
    private static let decisions: Set<String> = ["shot", "posted", "used_backup", "saved_for_tomorrow", "skipped_intentionally"]

    init(context: WorkspaceContext = .creatorFixture, defaults: UserDefaults? = DebugLaunchConfiguration.fixtureSession == nil ? nil : DebugLaunchConfiguration.fixtureDefaults) {
        self.context = context
        self.defaults = defaults
        do {
            var snapshot: FakeServerSnapshot
            if let data = defaults?.data(forKey: Self.persistenceKey) {
                snapshot = try JSONDecoder().decode(FakeServerSnapshot.self, from: data)
                if snapshot.schemaVersion < 2 {
                    let legacy = try JSONDecoder().decode(LegacyFakeServerDays.self, from: data)
                    snapshot.migrate(days: legacy.days, context: context)
                }
            } else {
                snapshot = try Self.seed(context: context, defaults: defaults)
            }
            for (pieceID, day) in snapshot.pieces {
                guard let id = day.currentRevisionID, let row = snapshot.revisions[id],
                      row.text("script")?.nilIfBlank == nil, row.text("caption")?.nilIfBlank == nil else { continue }
                if case .array(let scenes) = row["scene_list"], !scenes.isEmpty { continue }
                snapshot.pieces[pieceID]?.currentRevisionID = nil
                snapshot.revisions[id]?["is_current"] = .bool(false)
            }
            if let defaults { defaults.set(try JSONEncoder().encode(snapshot), forKey: Self.persistenceKey) }
            state = snapshot
            initialDayPackages = try snapshot.pieces.values.filter { $0.position == 0 && $0.removedAt == nil }.compactMap { day in
                guard let id = day.currentRevisionID, let row = snapshot.revisions[id] else { return nil }
                return try FakeJSON.decode(.object(row), as: SupabaseDailyCardRow.self).generatedDailyCardDraft()
            }
            initialArchiveEntries = try snapshot.archives.values.filter { $0.text("decision") != "replaced" }.map { row in
                try FakeJSON.decode(.object(row), as: SupabaseArchiveEntryRow.self).domainEntry()
            }
            initialProfile = try FakeJSON.decode(.object(snapshot.profile), as: SupabaseCreatorProfileRow.self).summary()
        } catch {
            preconditionFailure("Cannot load fake server: \(error.localizedDescription)")
        }
    }

    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ function: String, body: Request, context: WorkspaceContext,
        delayNanoseconds: UInt64 = DebugLaunchFlags.fixtureFirstIdeaDelayNanoseconds
    ) async throws -> Response {
        let response = try await request(function, body: body, context: context, delayNanoseconds: delayNanoseconds)
        if response.statusCode >= 400 {
            throw RepositoryError.edgeFunction(response.body.objectValue?.text("error") ?? "fake_server_request_failed")
        }
        return try FakeJSON.decode(response.body)
    }

    func generation<Request: Encodable & Sendable>(
        _ function: String, body: Request, context: WorkspaceContext, delayNanoseconds: UInt64
    ) async throws -> SupabaseDailyGenerationInvocation {
        let response = try await request(function, body: body, context: context, delayNanoseconds: delayNanoseconds)
        if response.statusCode >= 400 {
            throw RepositoryError.edgeFunction(response.body.objectValue?.text("error") ?? "invalid_generation_payload")
        }
        return try SupabaseDailyGenerationInvocation.decode(JSONEncoder().encode(response.body))
    }

    func request<Request: Encodable & Sendable>(
        _ function: String, body: Request, context: WorkspaceContext,
        delayNanoseconds: UInt64 = DebugLaunchFlags.fixtureFirstIdeaDelayNanoseconds
    ) async throws -> FakeServerResponse {
        let payload = try FakeJSON.object(body)
        if function == "move-piece", payload.uuid("creator_id") == nil {
            return Self.failure("invalid_move_piece_payload", status: 400)
        }
        guard context.workspaceID == self.context.workspaceID,
              context.creatorID == self.context.creatorID,
              payload.uuid("creator_id") == context.creatorID else {
            return Self.failure("creator_not_found", status: 404)
        }
        let before = state
        var response: FakeServerResponse
        do {
            switch function {
            case "read-content":
                try completeDueRuns()
                response = try read(payload)
            case "generate-week", "replace-day":
                response = try generate(payload, replacing: function == "replace-day", delayNanoseconds: delayNanoseconds)
            case "make-day-available", "unpublish-day", "update-ready-day-package", "publish-day":
                response = try lifecycle(function, payload: payload)
            case "move-piece":
                try completeDueRuns()
                response = try movePiece(payload)
            case "write-content": response = try write(payload)
            case "generate-plan-ideas":
                let date = payload.text("scheduled_date") ?? SupabaseDateFormatting.todayDateString()
                let setup = PlanDaySetupSummary(
                    contentPillars: payload["content_pillars"]?.decoded([String].self) ?? [],
                    voiceIsConfigured: payload.flag("voice_configured"),
                    confirmedReferenceCount: payload["reference_count"]?.intValue ?? 0,
                    totalReferenceCount: payload["reference_count"]?.intValue ?? 0,
                    positioning: payload.text("positioning") ?? "", voiceRulesText: payload.text("voice_rules") ?? "",
                    captionStyle: payload.text("caption_style") ?? "", noGoTopicsText: payload.text("no_go_topics") ?? "",
                    confirmedReferenceLabels: payload["reference_labels"]?.decoded([String].self) ?? [])
                response = Self.success(["ideas": .array(PlanDayIdeaBuilder.buildIdeas(scheduledDate: date, setup: setup).map { .object(["title": .string($0.title), "summary": .string($0.summary), "day_brief": .string($0.dayBrief)]) })])
            default: response = Self.failure("unsupported_action", status: 400)
            }
            try persist()
        } catch let error as FakePieceTargetError {
            response = Self.failure(error.code, status: error.status)
            try persist()
        } catch {
            state = before
            throw error
        }
        if payload.text("action") != "status", payload.text("response_mode") != "async", response.statusCode == 202,
           let id = response.body.objectValue?.uuid("generation_id"),
           let key = state.runs.first(where: { $0.value.id == id })?.key {
            try await Task.sleep(nanoseconds: delayNanoseconds)
            try finishRun(key)
            try persist()
            return runResponse(key, replayed: false)
        }
        return response
    }

    private func read(_ payload: FakeObject) throws -> FakeServerResponse {
        switch payload.text("action") {
        case "days":
            let days = state.pieces.values.filter {
                $0.removedAt == nil && (payload.flag("include_all_pieces") || $0.position == 0)
            }.sorted { ($0.scheduledDate, $0.position) < ($1.scheduledDate, $1.position) }.map { day -> SupabaseJSONValue in
                var value: FakeObject = [
                    "scheduled_date": .string(day.scheduledDate),
                    "piece_id": .string(day.id.uuidString), "position": .number(Double(day.position)),
                    "current_revision_id": day.currentRevisionID.map { .string($0.uuidString) } ?? .null,
                    "revision": day.currentRevisionID.flatMap { state.revisions[$0] }.map(SupabaseJSONValue.object) ?? .null,
                    "updated_at": .string(day.updatedAt), "generation": .null, "generation_id": .null
                ]
                if let key = day.generationKey, let run = state.runs[key] {
                    value["generation_id"] = .string(run.id.uuidString)
                    value["generation"] = .object([
                        "piece_id": .string(day.id.uuidString), "generation_id": .string(run.id.uuidString), "status": .string(run.status),
                        "idempotency_key": .string(key), "error_code": run.error.map(SupabaseJSONValue.string) ?? .null,
                        "completed_at": run.completedAt.map(SupabaseJSONValue.string) ?? .null
                    ])
                }
                return .object(value)
            }
            return Self.success(["days": .array(days)])
        case "today":
            let date = payload.text("today_date") ?? SupabaseDateFormatting.todayDateString()
            let cards = currentRows().filter { Self.readyStatuses.contains($0.text("status") ?? "") }
            let today = cards.first { $0.text("scheduled_date") == date }
            return Self.success([
                "today_card": today.map(SupabaseJSONValue.object) ?? .null,
                "week_cards": .array(cards.prefix(14).map(SupabaseJSONValue.object)),
                "today_date": .string(date), "today_status": .string(today == nil ? "missing_published_card" : "published")
            ])
        case "archive":
            let entries = state.archives.values.filter { $0.text("decision") != "replaced" }.sorted {
                ($0.text("archive_date") ?? "", $0.text("decision_at") ?? "") > ($1.text("archive_date") ?? "", $1.text("decision_at") ?? "")
            }
            return Self.success(["entries": .array(entries.map { entry in
                var row = entry
                row["revision_id"] = row["daily_card_id"]
                row["piece_id"] = row.uuid("daily_card_id").flatMap { state.revisions[$0] }?["piece_id"]
                row["daily_cards"] = .object(["piece_id": row["piece_id"] ?? .null, "title": row["title_snapshot"] ?? .null, "caption": row["caption_snapshot"] ?? .null])
                return .object(row)
            })])
        case "creator_profile": return Self.success(["profile": .object(state.profile)])
        case "weekly":
            let plan = state.plan
            let planRow = try Self.planRow(plan, context: context)
            let cards = currentRows().filter { $0.uuid("weekly_plan_id") == plan.id }
            return Self.success([
                "weekly_plan": planRow, "daily_cards": .array(cards.map(SupabaseJSONValue.object)),
                "idea_bank": .array(state.ideas.map(SupabaseJSONValue.object)), "published_weekly_plan": plan.isSoftLocked ? planRow : .null,
                "published_daily_cards": .array(plan.isSoftLocked ? cards.map(SupabaseJSONValue.object) : []),
                "weekly_setup": .object(["id": .string(plan.id.uuidString), "notes": .string(plan.weeklyBriefText)])
            ])
        default: return Self.failure("unsupported_action", status: 400)
        }
    }

    private func lifecycle(_ function: String, payload: FakeObject) throws -> FakeServerResponse {
        let invalid = function == "make-day-available" ? "invalid_make_day_available_payload"
            : function == "unpublish-day" ? "invalid_unpublish_day_payload" : "invalid_update_ready_day_package_payload"
        guard payload.uuid("daily_card_id") != nil || payload.text("scheduled_date") != nil || payload["piece_id"] != nil else { return Self.failure(invalid, status: 400) }
        if payload["daily_card_id"] != nil, payload.uuid("daily_card_id") == nil { return Self.failure(invalid, status: 400) }
        if let date = payload.text("scheduled_date"), !Self.validDate(date) { return Self.failure(invalid, status: 400) }
        if payload["piece_id"] != nil, payload.uuid("piece_id") == nil { return Self.failure("invalid_piece_id", status: 400) }
        let patch: FakeObject
        if payload["package"] == nil || payload["package"] == .null { patch = [:] }
        else if let object = payload["package"]?.objectValue { patch = object }
        else { return Self.failure(invalid, status: 400) }
        let fields = ["title", "why_today", "caption", "script", "backup_story", "backup_caption_only", "shootability"]
        if function == "update-ready-day-package" {
            for field in fields where patch[field] != nil {
                guard let text = patch.text(field) else { return Self.failure("invalid_package_text", status: 400, field: field) }
                guard text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))).isEmpty == false else {
                    return Self.failure("blank_package_text", status: 400, field: field)
                }
            }
            if let sceneList = patch["scene_list"] {
                guard case .array(let scenes) = sceneList else { return Self.failure("invalid_package_scene_list", status: 400, field: "scene_list") }
                var shotIDs: Set<UUID> = []
                for (index, scene) in scenes.enumerated() {
                    guard let shot = scene.objectValue,
                          let id = shot.uuid("id"), shot.text("title") != nil, shot.text("duration") != nil,
                          shot["dialogue"] == nil || shot.text("dialogue") != nil,
                          shot["symbol"] == nil || shot.text("symbol") != nil,
                          shot["number"] == nil || Self.validShotNumber(shot["number"]),
                          !shotIDs.contains(id) else {
                        return FakeServerResponse(statusCode: 400, body: .object(["error": .string("invalid_package_scene_list"), "field": .string("scene_list"), "shot_index": .number(Double(index))]))
                    }
                    shotIDs.insert(id)
                }
            }
        }
        guard var row = try currentRow(payload) else { return Self.failure("daily_card_not_found", status: 404) }
        let id = row.uuid("id")!
        let date = row.text("scheduled_date")!
        let oldStatus = row.text("status")!
        var result: FakeObject = ["piece_id": row["piece_id"]!, "daily_card_id": .string(id.uuidString), "scheduled_date": .string(date), "weekly_plan_id": row["weekly_plan_id"]!]
        switch function {
        case "make-day-available":
            guard oldStatus == "draft" else { return Self.failure("daily_card_not_draft", status: 409) }
            guard row.text("title")?.nilIfBlank != nil else { return Self.failure("daily_card_incomplete", status: 400) }
            row["status"] = .string("published")
            result["status"] = .string("published")
            result["week_is_soft_locked"] = .bool(row.uuid("weekly_plan_id").flatMap { state.plans[$0] }?.isSoftLocked ?? false)
        case "unpublish-day":
            guard oldStatus != "draft" else { return Self.failure("daily_card_already_draft", status: 409) }
            guard Self.readyStatuses.contains(oldStatus) else { return Self.failure("daily_card_not_ready", status: 409) }
            row["status"] = .string("draft")
            row["decision_at"] = .null
            row["completed_by_member_id"] = .null
            result["status"] = .string("draft")
            result["previous_status"] = .string(oldStatus)
            result["cleared_live_decision"] = .bool(oldStatus != "published" || state.revisions[id]?["decision_at"] != nil && state.revisions[id]?["decision_at"] != .null)
            result["archive_retained"] = .bool(state.archives[id] != nil)
        case "publish-day":
            guard oldStatus == "draft" || oldStatus == "published" else { return Self.failure("daily_card_not_publishable", status: 409) }
            row["status"] = .string("published")
            result["published_at"] = .string(SupabaseDateFormatting.isoTimestampString())
            result["archived_card_count"] = .number(0)
        default:
            guard Self.readyStatuses.contains(oldStatus) else { return Self.failure("daily_card_not_ready", status: 409) }
            for field in fields {
                if let text = patch.text(field) {
                    let trimmedCharacters: CharacterSet = field == "script" ? CharacterSet(charactersIn: " ") : .whitespacesAndNewlines
                    row[field] = .string(text.trimmingCharacters(in: trimmedCharacters))
                }
            }
            if let minutes = patch["estimated_shoot_minutes"], minutes != .null { row["estimated_shoot_minutes"] = minutes }
            if case .array(let scenes) = patch["scene_list"] {
                row["shot_content_owned"] = .bool(true)
                let stored = row["scene_list"]?.decoded([SupabaseShotSceneDTO].self) ?? []
                row["scene_list"] = .array(scenes.map { value in
                    guard var scene = value.objectValue, scene["id"] == nil,
                          let number = scene["number"]?.intValue,
                          let id = stored.first(where: { $0.number == number })?.id else { return value }
                    scene["id"] = .string(id.uuidString)
                    return .object(scene)
                })
            }
            guard row.text("title")?.nilIfBlank != nil else { return Self.failure("daily_card_incomplete", status: 400) }
            result["status"] = .string(oldStatus)
            result["title"] = row["title"]
            result["caption"] = row["caption"] ?? .null
        }
        state.revisions[id] = row
        state.pieces[row.uuid("piece_id")!]?.updatedAt = SupabaseDateFormatting.isoTimestampString()
        return Self.success(result)
    }

    private func movePiece(_ payload: FakeObject) throws -> FakeServerResponse {
        guard let id = payload.uuid("piece_id") else { return Self.failure("invalid_piece_id", status: 400) }
        guard let source = payload.text("scheduled_date"), Self.validDate(source),
              let target = payload.text("target_scheduled_date"), Self.validDate(target),
              let key = payload.text("idempotency_key")?.nilIfBlank, key.count <= 200 else {
            return Self.failure("invalid_move_piece_payload", status: 400)
        }
        let identity: FakeObject = ["piece_id": .string(id.uuidString), "scheduled_date": .string(source), "target_scheduled_date": .string(target)]
        if let saved = state.moves[key] {
            guard saved["request_identity"] == .object(identity) else { return Self.failure("idempotency_key_conflict", status: 409) }
            var result = saved["result"]!.objectValue!
            result["replayed"] = .bool(true)
            return Self.success(result)
        }
        guard let piece = state.pieces[id] else { return Self.failure("piece_not_found", status: 404) }
        guard piece.workspaceID == context.workspaceID, piece.creatorID == context.creatorID else { return Self.failure("piece_scope_mismatch", status: 409) }
        guard piece.removedAt == nil else { return Self.failure("piece_removed", status: 409) }
        guard piece.scheduledDate == source else { return Self.failure("piece_date_conflict", status: 409) }
        guard !state.runs.values.contains(where: { $0.pieceID == id && $0.status == "running" }) else { return Self.failure("piece_generation_running", status: 409) }
        if source != target {
            let position = (state.pieces.values.filter { $0.scheduledDate == target && $0.removedAt == nil }.map(\.position).max() ?? -1) + 1
            state.pieces[id]?.scheduledDate = target
            state.pieces[id]?.position = position
            state.pieces[id]?.updatedAt = SupabaseDateFormatting.isoTimestampString()
            for (position, other) in state.pieces.values.filter({ $0.scheduledDate == source && $0.removedAt == nil }).sorted(by: { $0.position < $1.position }).enumerated() {
                state.pieces[other.id]?.position = position
                state.pieces[other.id]?.updatedAt = SupabaseDateFormatting.isoTimestampString()
            }
            for revisionID in state.revisions.keys where state.revisions[revisionID]?.uuid("piece_id") == id {
                state.revisions[revisionID]?["scheduled_date"] = .string(target)
            }
            for runKey in state.runs.keys where state.runs[runKey]?.pieceID == id {
                state.runs[runKey]?.scheduledDate = target
                if var result = state.runs[runKey]?.result?.objectValue {
                    result["target_scheduled_date"] = .string(target)
                    result["scheduled_date"] = .string(target)
                    if var card = result["daily_card"]?.objectValue {
                        card["scheduled_date"] = .string(target)
                        result["daily_card"] = .object(card)
                    }
                    state.runs[runKey]?.result = .object(result)
                }
            }
        }
        let affected = state.pieces.values.filter { [source, target].contains($0.scheduledDate) && $0.removedAt == nil }
            .sorted { ($0.scheduledDate, $0.position) < ($1.scheduledDate, $1.position) }.map {
                PieceMoveTarget(pieceID: $0.id, scheduledDate: $0.scheduledDate, position: $0.position)
            }
        let result = try FakeJSON.object(PieceMoveResult(pieceID: id, sourceScheduledDate: source, scheduledDate: target,
            position: state.pieces[id]!.position, affectedPieces: affected, replayed: false))
        state.moves[key] = ["request_identity": .object(identity), "result": .object(result)]
        return Self.success(result)
    }

    private func write(_ payload: FakeObject) throws -> FakeServerResponse {
        switch payload.text("action") {
        case "complete_today", "upsert_archive_decision": return try decide(payload)
        case "update_creator_profile":
            for (key, value) in payload where key != "action" && key != "creator_id" { state.profile[key] = value }
            return Self.success(["action": .string("update_creator_profile"), "creator_profile": .object(state.profile)])
        case "update_daily_card_review_state":
            guard let id = payload.uuid("daily_card_id"), state.revisions[id] != nil else { return Self.failure("daily_card_not_found", status: 404) }
            guard state.revisions[id]?.flag("is_current") == true else { return Self.failure("historical_revision_immutable", status: 409) }
            state.revisions[id]?["review_state"] = payload["review_state"]
            return Self.success(["piece_id": state.revisions[id]?["piece_id"] ?? .null, "daily_card_id": .string(id.uuidString), "review_state": payload["review_state"] ?? .null])
        case "update_weekly_setup":
            guard payload.uuid("weekly_plan_id") == state.plan.id else { return Self.failure("weekly_plan_not_found", status: 404) }
            if case .array(let sections) = payload["setup_sections"] {
                if let brief = sections.compactMap(\.objectValue).first(where: { $0.text("title") == "weekly_brief" })?.text("value") {
                    state.plan.weeklyBriefText = brief
                } else {
                    state.plan.setupSections = sections.map { value in
                        let section = value.objectValue ?? [:]
                        return WeeklySetupSection(id: section.uuid("id") ?? UUID(), systemImage: section.text("system_image") ?? "circle", title: section.text("title") ?? "", summary: section.text("summary") ?? "", state: section.text("state") ?? "")
                    }
                }
                state.plans[state.plan.id] = state.plan
            }
            return Self.success(["action": .string("update_weekly_setup")])
        case "select_idea_for_next_open_day":
            guard let id = payload.uuid("idea_id"), let index = state.ideas.firstIndex(where: { $0.uuid("id") == id }) else { return Self.failure("idea_not_found", status: 404) }
            if let day = state.plan.days.firstIndex(where: { $0.state == .open }) {
                let idea = state.ideas[index]
                state.plan.days[day].title = idea.text("title") ?? ""
                state.plan.days[day].reason = idea.text("summary") ?? ""
                state.plan.days[day].state = .planned
                state.ideas[index]["selected_day"] = .string(state.plan.days[day].weekday)
                state.plans[state.plan.id] = state.plan
            }
            return Self.success(["idea": .object(["id": .string(id.uuidString), "status": .string("selected")])])
        default: return Self.failure("unsupported_action", status: 400)
        }
    }

    private func decide(_ payload: FakeObject) throws -> FakeServerResponse {
#if DEBUG
        if DebugLaunchConfiguration.isEnabled("MCO_FAIL_TODAY_DECISION_SYNC") {
            return Self.failure("fixture_today_decision_sync_failed", status: 503)
        }
        if DebugLaunchFlags.failTodayDecisionSyncOnce, !state.consumedFailures.contains("today-decision-sync") {
            state.consumedFailures.insert("today-decision-sync")
            return Self.failure("fixture_today_decision_sync_failed", status: 503)
        }
#endif
        if payload["piece_id"] != nil && payload.uuid("piece_id") == nil { return Self.failure("invalid_write_payload", status: 400) }
        if payload["daily_card_id"] != nil, payload.uuid("daily_card_id") == nil { return Self.failure("invalid_write_payload", status: 400) }
        let target = try resolveRevision(payload)
        guard var card = target, let id = card.uuid("id") else { return Self.failure("daily_card_not_found", status: 404) }
        let complete = payload.text("action") == "complete_today"
        let decisionPayload = complete ? payload["decision"]?.objectValue ?? [:] : payload
        let decision = complete ? decisionPayload.text("status") : payload.text("decision")
        let date = complete ? card.text("scheduled_date") : payload.text("archive_date")
        guard let decision, Self.decisions.contains(decision), let date else { return Self.failure("invalid_write_payload", status: 400) }
        let output = decisionPayload["output_line"] ?? .null
        let thumbnail = decisionPayload.flag("has_post_thumbnail")
        let existing = state.archives[id]
        let current = card.flag("is_current") && card.text("status") != "archived"
            && card.uuid("piece_id").flatMap { state.pieces[$0]?.currentRevisionID } == id
        if !current {
            guard let existing, existing.text("decision") == decision, existing.text("archive_date") == date,
                  (existing["output_line"] ?? .null) == output, existing.flag("has_post_thumbnail") == thumbnail,
                  payload.text("decision_at") == nil || Self.sameTimestamp(payload.text("decision_at"), existing.text("decision_at")) else {
                return Self.failure("historical_revision_immutable", status: 409)
            }
            return Self.success(decisionReply(payload, card: card, archive: existing))
        }
        if let existing, existing.text("decision") == "posted", decision == "posted" {
            if complete, card.text("status") != "posted" || !Self.sameTimestamp(card.text("decision_at"), existing.text("decision_at")) {
                card["status"] = .string("posted")
                card["decision_at"] = existing["decision_at"]
                card["completed_by_member_id"] = .string(context.memberID.uuidString)
                state.revisions[id] = card
                state.pieces[card.uuid("piece_id")!]?.updatedAt = SupabaseDateFormatting.isoTimestampString()
            }
            return Self.success(decisionReply(payload, card: card, archive: existing))
        }
        let same = existing?.text("decision") == decision
        let keepText = same || existing?.text("decision") == "posted"
        var time = same ? existing?.text("decision_at") : payload.text("decision_at") ?? SupabaseDateFormatting.isoTimestampString()
        if !same, Self.sameTimestamp(time, existing?.text("decision_at")) {
            let previous = Self.timestamp(existing?.text("decision_at")) ?? .distantPast
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            time = formatter.string(from: max(Date(), previous.addingTimeInterval(0.001)))
        }
        var archive: FakeObject = [
            "id": existing?["id"] ?? .string(UUID().uuidString), "daily_card_id": .string(id.uuidString),
            "archive_date": .string(date), "decision": .string(decision), "output_line": output,
            "has_post_thumbnail": .bool(thumbnail), "decision_at": time.map(SupabaseJSONValue.string) ?? .null,
            "title_snapshot": keepText ? existing?["title_snapshot"] ?? card["title"]! : card["title"]!,
            "caption_snapshot": keepText ? existing?["caption_snapshot"] ?? .null : card["caption"] ?? .null
        ]
        archive["revision_id"] = .string(id.uuidString)
        archive["piece_id"] = card["piece_id"]
        state.archives[id] = archive
        if complete {
            card["status"] = .string(decision)
            card["decision_at"] = archive["decision_at"]
            card["completed_by_member_id"] = .string(context.memberID.uuidString)
            state.revisions[id] = card
            state.pieces[card.uuid("piece_id")!]?.updatedAt = SupabaseDateFormatting.isoTimestampString()
        }
        return Self.success(decisionReply(payload, card: card, archive: archive))
    }

    private func decisionReply(_ payload: FakeObject, card: FakeObject, archive: FakeObject) -> FakeObject {
        var result: FakeObject = ["action": payload["action"]!, "archive_entry": .object(archive)]
        if payload.text("action") == "complete_today" {
            result["daily_card"] = .object([
                "id": card["id"]!, "piece_id": card["piece_id"]!, "status": archive["decision"]!,
                "decision_at": archive["decision_at"] ?? .null,
                "completed_by_member_id": card["completed_by_member_id"] ?? .null
            ])
        }
        return result
    }

    private func generate(_ payload: FakeObject, replacing: Bool, delayNanoseconds: UInt64) throws -> FakeServerResponse {
        if payload.text("action") == "status", !replacing {
            guard let id = payload.uuid("generation_id"), let key = state.runs.first(where: { $0.value.id == id })?.key else {
                return Self.failure("generation_run_not_found", status: 404)
            }
            try refreshRun(key)
            return runResponse(key, replayed: false)
        }
        let action = replacing ? "replace_day" : payload.text("action") ?? ""
        let isReplacement = action == "replace_day"
        if ["generate_week", "retry_day", "cancel_generation"].contains(action) {
            return Self.failure("full_week_generation_retired", status: 400)
        }
        guard ["generate_day", "regenerate_day", "replace_day"].contains(action),
              let date = payload.text("scheduled_date"), Self.validDate(date),
              payload["response_mode"] == nil || ["sync", "async"].contains(payload.text("response_mode") ?? "") else {
            return Self.failure("invalid_generation_payload", status: 400)
        }
        if payload["daily_card_id"] != nil, payload.uuid("daily_card_id") == nil { return Self.failure("invalid_generation_payload", status: 400) }
        if payload["piece_id"] != nil, payload.uuid("piece_id") == nil { return Self.failure("invalid_generation_payload", status: 400) }
        let key: String
        if let supplied = payload["idempotency_key"] {
            guard case .string(let raw) = supplied else { return Self.failure("invalid_idempotency_key", status: 400) }
            key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, key.utf16.count <= 200 else { return Self.failure("invalid_idempotency_key", status: 400) }
        } else { key = UUID().uuidString }
        let brief = String((payload.text(action == "regenerate_day" ? "day_guidance" : "day_brief") ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
        if action != "regenerate_day", brief.isEmpty { return Self.failure("day_brief_required", status: 400) }
        var identity: FakeObject = [
            "action": .string(action), "creator_id": payload["creator_id"]!, "scheduled_date": .string(date),
            "mock": .bool(payload.flag("mock")), "daily_card_id": payload["daily_card_id"] ?? .null
        ]
        if let pieceID = payload.uuid("piece_id") { identity["piece_id"] = .string(pieceID.uuidString) }
        if let pieceID = payload.uuid("piece_id"), let piece = state.pieces[pieceID] {
            try validatePiece(piece, date: date)
        }
        if action == "regenerate_day" {
            guard let planID = payload.uuid("weekly_plan_id") else { return Self.failure("invalid_generation_payload", status: 400) }
            identity["weekly_plan_id"] = .string(planID.uuidString)
            identity["preserve_manual_edits"] = .bool(payload["preserve_manual_edits"] != .bool(false))
            if payload.text("day_guidance")?.isEmpty == false { identity["day_guidance"] = .string(brief) }
            if let overrides = payload["input_overrides"], overrides.objectValue != nil { identity["input_overrides"] = overrides }
        } else { identity["day_brief"] = .string(brief) }
        if let previous = state.runs[key] {
            guard previous.identity == identity else { return Self.failure("idempotency_key_conflict", status: 409) }
            try refreshRun(key)
            return runResponse(key, replayed: true)
        }
        guard date >= Self.serverTodayDate(timeZone: payload.text("time_zone")) else { return Self.failure("past_generation_date_not_allowed", status: 400) }
#if DEBUG
        if DebugLaunchFlags.failFirstIdea { return Self.failure("fixture_first_idea_generation_failed", status: 503) }
        if DebugLaunchFlags.failFirstIdeaOnce, !state.consumedFailures.contains("first-idea-generation") {
            state.consumedFailures.insert("first-idea-generation")
            return Self.failure("fixture_first_idea_generation_failed_once", status: 503)
        }
#endif
        let pieceID = try resolvePiece(payload)
        let existing = state.pieces[pieceID]?.currentRevisionID.flatMap { state.revisions[$0] }
        let recovering = existing?.text("status") == "archived" && existing?.flag("is_current") == false
        let plan: WeeklyPlan
        if isReplacement {
            guard let existing, payload.uuid("daily_card_id") == nil || payload.uuid("daily_card_id") == existing.uuid("id") else { return Self.failure("daily_card_not_found", status: 404) }
            guard let found = existing.uuid("weekly_plan_id").flatMap({ state.plans[$0] }) else { return Self.failure("weekly_plan_not_found", status: 404) }
            plan = found
        } else if action == "regenerate_day" {
            guard let found = payload.uuid("weekly_plan_id").flatMap({ state.plans[$0] }) else { return Self.failure("weekly_plan_not_found", status: 404) }
            plan = found
        } else {
            plan = state.plans.values.first { $0.weekStartDate.map { $0 <= date && date <= SupabaseDateFormatting.weekEndDate(starting: $0) } == true }
                ?? Self.emptyPlan(for: date)
        }
        guard let start = plan.weekStartDate, start <= date, date <= SupabaseDateFormatting.weekEndDate(starting: start) else { return Self.failure("date_not_in_plan", status: 400) }
        if !isReplacement {
            guard payload.uuid("piece_id") != nil || !plan.isSoftLocked || recovering else { return Self.failure("existing_published_week_locked", status: 409) }
            if let existing, existing.text("status") != "draft", !recovering { return Self.failure("replace_day_required", status: 409) }
        }
        if let previous = state.pieces[pieceID]?.generationKey, state.runs[previous]?.status == "running" { failRun(previous, code: "generation_superseded") }
        if isReplacement, !recovering, let existing { archiveRevision(existing) }
        state.plans[plan.id] = plan
        state.plan = plan
        let run = FakeServerRun(pieceID: pieceID, planID: plan.id, scheduledDate: date, identity: identity,
                                replacedRevisionID: isReplacement ? existing?.uuid("id") : nil,
                                readyAt: Date().addingTimeInterval(Double(delayNanoseconds) / 1_000_000_000))
        state.runs[key] = run
        state.pieces[pieceID]?.generationKey = key
        state.pieces[pieceID]?.updatedAt = SupabaseDateFormatting.isoTimestampString()
        return runResponse(key, replayed: false)
    }

    private func refreshRun(_ key: String) throws {
        guard let run = state.runs[key], run.status == "running" else { return }
        if Date().timeIntervalSince(run.updatedAt) > 600 { failRun(key, code: "generation_stale") }
        else if Date() >= run.readyAt { try finishRun(key) }
    }

    private func completeDueRuns() throws {
        for key in Array(state.runs.keys) { try refreshRun(key) }
    }

    private func failRun(_ key: String, code: String) {
        guard state.runs[key]?.status == "running" else { return }
        state.runs[key]?.status = "failed"
        state.runs[key]?.error = code
        state.runs[key]?.completedAt = SupabaseDateFormatting.isoTimestampString()
        state.runs[key]?.updatedAt = Date()
    }

    private func finishRun(_ key: String) throws {
        guard var run = state.runs[key] else { throw RepositoryError.edgeFunction("generation_run_not_found") }
        if run.result != nil { return }
        guard let pieceID = run.pieceID, run.status == "running", state.pieces[pieceID]?.generationKey == key else { throw RepositoryError.edgeFunction("generation_run_closed") }
        var result = FakeGenerationOutput().makeResult(scheduledDate: run.scheduledDate,
            dayBrief: run.identity.text("day_brief") ?? run.identity.text("day_guidance") ?? "Regenerated fixture day for \(run.scheduledDate).", revisionID: run.revisionID)
        result.generationID = run.id
        result.weeklyPlanID = run.planID
        result.dailyCard.sceneList = result.dailyCard.sceneList.map { scene in
            ShotScene(id: ShotScene.stableID(revisionID: run.revisionID, number: scene.number), number: scene.number,
                      title: scene.title, duration: scene.duration, symbol: scene.symbol, dialogue: scene.dialogue)
        }
        if let oldID = state.pieces[pieceID]?.currentRevisionID, let old = state.revisions[oldID] {
            if run.identity.flag("preserve_manual_edits"), old.flag("is_current"), old.text("status") == "draft" {
                let saved = try FakeJSON.decode(.object(old), as: SupabaseDailyCardRow.self).generatedDailyCardDraft()
                result.dailyCard.title = saved.title.nilIfBlank ?? result.dailyCard.title
                result.dailyCard.whyToday = saved.whyToday.nilIfBlank ?? result.dailyCard.whyToday
                result.dailyCard.shootability = saved.shootability.nilIfBlank ?? result.dailyCard.shootability
                result.dailyCard.estimatedShootMinutes = saved.estimatedShootMinutes
                let storedScenes = old["scene_list"]?.decoded([SupabaseShotSceneDTO].self) ?? []
                let shotOwned = old.flag("shot_content_owned") || !storedScenes.isEmpty && storedScenes.allSatisfy { $0.dialogue != nil }
                result.dailyCard.sceneList = storedScenes.enumerated().map { $0.element.domainScene(fallbackNumber: $0.offset + 1, revisionID: oldID) }
                result.dailyCard.shotContentOwned = shotOwned
                if shotOwned { result.dailyCard.script = saved.script }
                result.dailyCard.caption = saved.caption.nilIfBlank ?? result.dailyCard.caption
                result.dailyCard.backupStory = saved.backupStory.nilIfBlank ?? result.dailyCard.backupStory
                result.dailyCard.backupCaptionOnly = saved.backupCaptionOnly.nilIfBlank ?? result.dailyCard.backupCaptionOnly
                result.dailyCard.normalizeShotContent()
            }
            if old.flag("is_current") { archiveRevision(old) }
        }
        let row = try Self.revision(result.dailyCard, planID: run.planID, context: context, generationID: run.id, pieceID: pieceID)
        state.revisions[run.revisionID] = row
        state.pieces[pieceID]?.currentRevisionID = run.revisionID
        state.pieces[pieceID]?.updatedAt = SupabaseDateFormatting.isoTimestampString()
        run.status = "completed"
        run.completedAt = SupabaseDateFormatting.isoTimestampString()
        run.updatedAt = Date()
        run.result = .object([
            "piece_id": .string(pieceID.uuidString), "generation_id": .string(run.id.uuidString), "weekly_plan_id": .string(run.planID.uuidString), "status": .string("draft"),
            "target_scheduled_date": .string(run.scheduledDate), "daily_card": .object(row),
            "warnings": try FakeJSON.value(result.warnings), "assumptions": try FakeJSON.value(result.assumptions),
            "source_summary": .string(result.sourceSummary), "generated_at": .string(result.generatedAt)
        ])
        state.runs[key] = run
    }

    private func runResponse(_ key: String, replayed: Bool) -> FakeServerResponse {
        guard let run = state.runs[key] else { return Self.failure("generation_run_not_found", status: 404) }
        var object = run.result?.objectValue ?? [
            "generation_id": .string(run.id.uuidString), "weekly_plan_id": .string(run.planID.uuidString),
            "target_scheduled_date": .string(run.scheduledDate), "status": .string(run.status),
            "poll_after_seconds": run.status == "running" ? .number(1) : .null
        ]
        if let card = object["daily_card"]?.objectValue {
            object["daily_card"] = .object(Self.generatedCard(card))
        }
        object["piece_id"] = run.pieceID.map { .string($0.uuidString) } ?? .null
        object["idempotency_key"] = .string(key)
        object["replaced_daily_card_id"] = run.replacedRevisionID.map { .string($0.uuidString) } ?? .null
        if let error = run.error { object["error"] = .string(error) }
        if replayed { object["replayed"] = .bool(true) }
        return Self.success(object, status: run.status == "running" ? 202 : 200)
    }

    private static func generatedCard(_ row: FakeObject) -> FakeObject {
        var card = row
        let instructions = row["post_instructions"]?.objectValue ?? [:]
        for field in ["format", "primary_surface", "duration_seconds", "hook", "save_share_reason",
                      "shot_timeline", "voiceover_timeline", "silent_version_timeline", "on_screen_text_timeline"] {
            if let value = instructions[field] { card[field] = value }
        }
        card["post_instructions"] = .string(instructions.text("instructions") ?? row.text("post_instructions") ?? "")
        card["backup_story"] = .string(row["backup_story"]?.displayText ?? "")
        card["backup_caption_only"] = .string(row["backup_caption_only"]?.displayText ?? "")
        card["backup_story_detail"] = row["backup_story"]?.objectValue?["detail"] ?? row["backup_story_detail"] ?? .array([])
        card["caption_backup_detail"] = instructions["caption_backup_detail"]
            ?? row["backup_caption_only"]?.objectValue?["detail"] ?? row["caption_backup_detail"] ?? .string("")
        card["audio_option_notes"] = instructions["audio_option_notes"] ?? row["audio_option_notes"] ?? .string("")
        return card
    }

    private func archiveRevision(_ row: FakeObject) {
        let id = row.uuid("id")!
        if state.archives[id] == nil {
            let decision = row.text("status").flatMap { Self.decisions.contains($0) ? $0 : nil } ?? "replaced"
            state.archives[id] = [
                "id": .string(UUID().uuidString), "daily_card_id": .string(id.uuidString), "piece_id": row["piece_id"]!,
                "archive_date": row["scheduled_date"]!, "decision": .string(decision), "output_line": row["title"]!,
                "has_post_thumbnail": .bool(false), "title_snapshot": row["title"]!,
                "caption_snapshot": row["caption"] ?? .null, "decision_at": row["decision_at"] ?? .string(SupabaseDateFormatting.isoTimestampString())
            ]
        }
        state.revisions[id]?["status"] = .string("archived")
        state.revisions[id]?["is_current"] = .bool(false)
    }

    private func currentRows() -> [FakeObject] {
        state.pieces.values.filter { $0.position == 0 && $0.removedAt == nil }
            .compactMap { $0.currentRevisionID.flatMap { state.revisions[$0] } }
            .sorted { ($0.text("scheduled_date") ?? "") < ($1.text("scheduled_date") ?? "") }
    }

    private func validatePiece(_ piece: FakeServerPiece, date: String?) throws {
        guard piece.workspaceID == context.workspaceID, piece.creatorID == context.creatorID,
              date == nil || piece.scheduledDate == date else {
            throw FakePieceTargetError(code: "piece_scope_mismatch", status: 409)
        }
        guard piece.removedAt == nil else { throw FakePieceTargetError(code: "piece_removed", status: 409) }
    }

    private func resolvePiece(_ payload: FakeObject) throws -> UUID {
        let date = payload.text("scheduled_date")
        if payload["piece_id"] != nil, payload.uuid("piece_id") == nil {
            throw FakePieceTargetError(code: "invalid_piece_id", status: 400)
        }
        if let id = payload.uuid("piece_id"), let piece = state.pieces[id] {
            try validatePiece(piece, date: date)
            return id
        }
        guard let date else {
            throw FakePieceTargetError(code: payload.uuid("piece_id") == nil ? "invalid_piece_target" : "piece_not_found", status: payload.uuid("piece_id") == nil ? 400 : 404)
        }
        guard let id = payload.uuid("piece_id") else { return state.compatibilityPiece(for: date, context: context) }
        let position = state.pieces.values.filter { $0.scheduledDate == date && $0.removedAt == nil }
            .map(\.position).max().map { $0 + 1 } ?? 0
        state.pieces[id] = FakeServerPiece(id: id, workspaceID: context.workspaceID, creatorID: context.creatorID,
                                          scheduledDate: date, position: position)
        return id
    }

    private func resolveRevision(_ payload: FakeObject) throws -> FakeObject? {
        var target = payload
        var revision: FakeObject?
        if let id = payload.uuid("daily_card_id") {
            guard let row = state.revisions[id], row.uuid("workspace_id") == context.workspaceID,
                  row.uuid("creator_id") == context.creatorID else { return nil }
            revision = row
            if payload["piece_id"] == nil && payload["scheduled_date"] == nil { target["piece_id"] = row["piece_id"] }
            if target["scheduled_date"] == nil { target["scheduled_date"] = row["scheduled_date"] }
        }
        let pieceID = try resolvePiece(target)
        if let revision {
            guard revision.uuid("piece_id") == pieceID else { throw FakePieceTargetError(code: "piece_revision_mismatch", status: 409) }
            return revision
        }
        return state.pieces[pieceID]?.currentRevisionID.flatMap { state.revisions[$0] }
    }

    private func currentRow(_ payload: FakeObject) throws -> FakeObject? {
        guard let row = try resolveRevision(payload), row.flag("is_current"),
              let pieceID = row.uuid("piece_id"), state.pieces[pieceID]?.currentRevisionID == row.uuid("id") else { return nil }
        return row
    }

    private func persist() throws {
        if let defaults { defaults.set(try JSONEncoder().encode(state), forKey: Self.persistenceKey) }
    }

    private static func success(_ object: FakeObject, status: Int = 200) -> FakeServerResponse {
        FakeServerResponse(statusCode: status, body: .object(object))
    }

    private static func failure(_ error: String, status: Int, field: String? = nil) -> FakeServerResponse {
        var body: FakeObject = ["error": .string(error)]
        if let field { body["field"] = .string(field) }
        return FakeServerResponse(statusCode: status, body: .object(body))
    }

    private static func revision(_ draft: GeneratedDailyCardDraft, planID: UUID, context: WorkspaceContext, generationID: UUID? = nil, pieceID: UUID? = nil) throws -> FakeObject {
        var row = try FakeJSON.object(SupabaseDraftDailyCardPublishRequest(card: draft))
        row["piece_id"] = pieceID.map { .string($0.uuidString) } ?? .null
        row["workspace_id"] = .string(context.workspaceID.uuidString)
        row["creator_id"] = .string(context.creatorID.uuidString)
        row["weekly_plan_id"] = .string(planID.uuidString)
        row["status"] = .string(DayPackageLifecycleStatus.isDraftPackage(draft.status) ? "draft" : draft.status)
        row["is_current"] = .bool(true)
        row["generation_run_id"] = generationID.map { .string($0.uuidString) } ?? .null
        row["shot_content_owned"] = .bool(draft.shotContentOwned)
        row["scene_list"] = try FakeJSON.value(draft.sceneList)
        return row
    }

    private static func profile(_ summary: CreatorProfileSummary, context: WorkspaceContext) throws -> FakeObject {
        let update = CreatorProfileUpdate(positioning: summary.positioning, voiceRules: summary.voiceRules,
            contentPillars: summary.contentPillars, captionStyle: summary.captionStyle ?? "", noGoTopics: summary.noGoTopics,
            recurringFormats: summary.recurringFormats, onboardingState: summary.onboardingState, onboardingStep: summary.onboardingStep,
            onboardingCompletedAt: summary.onboardingCompletedAt, startingPoint: summary.startingPoint, customSubjects: summary.customSubjects,
            tasteExampleIDs: summary.tasteExampleIDs, productionFormats: summary.productionFormats, timeToCreate: summary.timeToCreate,
            onCameraRestrictions: summary.onCameraRestrictions, recentContext: summary.recentContext, creatorNote: summary.creatorNote,
            firstIdeaHandoff: summary.firstIdeaHandoff, languagePreferences: ["primary": summary.contentLanguage])
        var result = try FakeJSON.object(SupabaseWriteContentRequest.updateCreatorProfile(update, context: context))
        result.removeValue(forKey: "action")
        result["display_name"] = .string(summary.displayName)
        result["onboarding_version"] = .number(Double(summary.onboardingVersion))
        return result
    }

    private static func planRow(_ plan: WeeklyPlan, context: WorkspaceContext) throws -> SupabaseJSONValue {
        .object([
            "id": .string(plan.id.uuidString), "workspace_id": .string(context.workspaceID.uuidString), "creator_id": .string(context.creatorID.uuidString),
            "week_start_date": .string(plan.weekStartDate ?? ""), "status": .string(plan.isSoftLocked ? "published" : "draft"),
            "is_soft_locked": .bool(plan.isSoftLocked), "warnings": .array([]), "assumptions": .array([]),
            "strategy_summary": .string(plan.weeklyBriefText)
        ])
    }

    private static func timestamp(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private static func sameTimestamp(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = timestamp(lhs), let rhs = timestamp(rhs) else { return false }
        return lhs == rhs
    }

    private static func validShotNumber(_ value: SupabaseJSONValue?) -> Bool {
        guard case .number(let number) = value else { return false }
        return number.isFinite && number.rounded(.towardZero) == number && number >= -9_223_372_036_854_775_808 && number < 9_223_372_036_854_775_808
    }

    private static func serverTodayDate(timeZone: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone.flatMap { TimeZone.knownTimeZoneIdentifiers.contains($0) || $0 == "UTC" ? TimeZone(identifier: $0) : nil } ?? TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func validDate(_ value: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value).map { formatter.string(from: $0) == value } ?? false
    }

    private static func emptyPlan(for date: String) -> WeeklyPlan {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = formatter.date(from: date)!
        let offset = (calendar.component(.weekday, from: day) + 5) % 7
        let start = formatter.string(from: calendar.date(byAdding: .day, value: -offset, to: day)!)
        var plan = WeeklyPlan(title: "Generate a Week", eyebrow: "MANAGER WEEKLY CONTROL", weekRange: SupabaseDateFormatting.weekRange(starting: start),
            weekStartDate: start, weekEndDate: SupabaseDateFormatting.weekEndDate(starting: start), readinessLine: "0 ready, 0 backup, 7 open", isSoftLocked: false, days: [], setupSections: WeeklyPlan.raceWeek.setupSections)
        plan.days = SupabaseDateFormatting.weekDates(starting: start).map { date in
            WeeklyDay(weekday: SupabaseDateFormatting.weekdayAbbreviation(for: date), date: SupabaseDateFormatting.dayNumber(for: date), scheduledDate: date,
                title: "Open", reason: "", source: .open, state: .open, isSoftLocked: false)
        }
        return plan
    }

    private static func seed(context: WorkspaceContext, defaults: UserDefaults?) throws -> FakeServerSnapshot {
        var snapshot = FakeServerSnapshot()
        var days: [String: FakeServerDay] = [:]
        let savedProfile = defaults?.data(forKey: "creator-profile").flatMap { try? JSONDecoder().decode(CreatorProfileSummary.self, from: $0) }
        snapshot.profile = try profile(savedProfile ?? .creatorFixture, context: context)
        snapshot.plans[snapshot.plan.id] = snapshot.plan
        snapshot.ideas = WeeklyIdea.raceWeekBank.map { idea in
            ["id": .string(idea.id.uuidString), "title": .string(idea.title), "summary": .string(idea.reason),
             "suggested_use": .string(idea.source.rawValue), "shootability": .string(idea.effortLabel), "status": .string("candidate")]
        }
        var cards = DailyCard.weekFixtures
        var drafts: [String: DailyCard] = [:]
#if DEBUG
        let loopCards = DebugLaunchFlags.loopScenarioCards
#else
        let loopCards: [DailyCard]? = nil
#endif
        if let data = defaults?.data(forKey: "published-content"),
           let legacy = try? JSONDecoder().decode(LegacyFixtureContent.self, from: data) {
            cards = legacy.weekCards
            drafts = legacy.generatedDrafts
            if let today = legacy.todayCard, !cards.contains(where: { $0.id == today.id }) { cards.append(today) }
            for card in legacy.historicalCards.values {
                guard let date = card.scheduledDate else { continue }
                let plan = emptyPlan(for: date)
                snapshot.plans[plan.id] = plan
                var row = try revision(GeneratedDailyCardDraft(fromPublishedCard: card, status: "archived"), planID: plan.id, context: context)
                row["is_current"] = .bool(false)
                snapshot.revisions[card.id] = row
            }
            for entry in legacy.decisions.values {
                let date = entry.scheduledDate ?? cards.first(where: { $0.id == entry.dailyCardID })?.scheduledDate ?? SupabaseDateFormatting.todayDateString()
                let id = entry.dailyCardID ?? UUID()
                snapshot.archives[id] = archiveSeed(entry, revisionID: id, date: date)
            }
        } else if let loopCards {
            cards = loopCards
        } else if !DebugLaunchFlags.forceEmptyToday {
#if DEBUG
            var draft = DebugLaunchFlags.forceFixtureUI ? DebugLaunchFlags.fixtureDailyCardDraft : GeneratedDailyCardDraft(fromPublishedCard: .raceWeekToday)
#else
            var draft = GeneratedDailyCardDraft(fromPublishedCard: .raceWeekToday)
#endif
            draft.scheduledDate = SupabaseDateFormatting.todayDateString()
            draft.status = "published"
            cards.removeAll { $0.scheduledDate == draft.scheduledDate }
            cards.append(draft.dailyCard(completionState: nil))
        }
        for card in cards { if let date = card.scheduledDate { drafts.removeValue(forKey: date) } }
        for card in Array(drafts.values) + cards {
            guard let date = card.scheduledDate else { continue }
            let plan = snapshot.plans.values.first { $0.weekStartDate.map { $0 <= date && date <= SupabaseDateFormatting.weekEndDate(starting: $0) } == true } ?? emptyPlan(for: date)
            snapshot.plans[plan.id] = plan
            let status = cards.contains(where: { $0.id == card.id }) ? card.completionState?.supabaseStatus ?? "published" : "draft"
            snapshot.revisions[card.id] = try revision(GeneratedDailyCardDraft(fromPublishedCard: card, status: status), planID: plan.id, context: context)
            days[date] = FakeServerDay(currentRevisionID: card.id)
        }
        let archiveEntries: [ArchiveEntry]
        if let saved = defaults?.data(forKey: "archive"), let entries = try? JSONDecoder().decode([ArchiveEntry].self, from: saved) {
            archiveEntries = entries
        } else {
#if DEBUG
            switch DebugLaunchFlags.uiFixtureData {
            case .empty: archiveEntries = []
            case .one: archiveEntries = Array(ArchiveEntry.fixtures.prefix(1))
            case .worst, .huge:
                let count = DebugLaunchFlags.uiFixtureData == .huge ? 1_284 : 6
                archiveEntries = (0..<count).map { index in
                    ArchiveEntry(day: "TUE", date: "6 OCT", cardTitle: index == 0 ? "Đặng Thị Ngọc Hân — a small creative routine that helped me finish a difficult week" : "Daily moment \(index + 1)", decision: .posted, outputLine: "Posted", hasPostThumbnail: false)
                }
            case .demo: archiveEntries = ArchiveEntry.fixtures
            }
#else
            archiveEntries = ArchiveEntry.fixtures
#endif
        }
        for (index, entry) in archiveEntries.enumerated() {
            let id = entry.dailyCardID ?? UUID()
            if snapshot.archives[id] == nil {
                let dates = ["2026-06-03", "2026-06-02", "2026-06-01", "2026-05-31"]
                snapshot.archives[id] = archiveSeed(entry, revisionID: id, date: entry.scheduledDate ?? (index < dates.count ? dates[index] : "2026-10-06"))
            }
        }
        for (id, archive) in snapshot.archives where snapshot.revisions[id] == nil {
            guard let date = archive.text("archive_date") else { continue }
            let plan = snapshot.plans.values.first { $0.weekStartDate.map { $0 <= date && date <= SupabaseDateFormatting.weekEndDate(starting: $0) } == true } ?? emptyPlan(for: date)
            snapshot.plans[plan.id] = plan
            let card = DailyCard(id: id, title: archive.text("title_snapshot") ?? "Archived package",
                context: SupabaseDateFormatting.contextLine(for: date), effortLabel: "", whyToday: "", scheduledDate: date,
                scenes: [], caption: archive.text("caption_snapshot"))
            var row = try revision(GeneratedDailyCardDraft(fromPublishedCard: card, status: "archived"), planID: plan.id, context: context)
            row["is_current"] = .bool(false)
            snapshot.revisions[id] = row
        }
        if let id = days[SupabaseDateFormatting.todayDateString()]?.currentRevisionID,
           let planID = snapshot.revisions[id]?.uuid("weekly_plan_id"), let plan = snapshot.plans[planID] {
            snapshot.plan = plan
        }
        snapshot.migrate(days: days, context: context)
        return snapshot
    }

    private static func archiveSeed(_ entry: ArchiveEntry, revisionID: UUID, date: String) -> FakeObject {
        ["id": .string(entry.id.uuidString), "daily_card_id": .string(revisionID.uuidString), "archive_date": .string(date),
         "decision": .string(entry.decision.supabaseStatus), "output_line": .string(entry.outputLine),
         "has_post_thumbnail": .bool(entry.hasPostThumbnail), "title_snapshot": .string(entry.cardTitle),
         "caption_snapshot": entry.captionSnapshot.map(SupabaseJSONValue.string) ?? .null,
         "decision_at": .string(entry.decisionAt ?? "\(date)T12:00:00Z")]
    }


    func publishWeek(_ plan: WeeklyPlan, ideaBank: [WeeklyIdea], generatedDraft: GeneratedWeekDraft?) throws -> WeeklyPublishResult {
        let published = generatedDraft.flatMap { $0.weeklyPlanID == plan.id ? $0.markedPublished.weeklyPlan(setupSections: plan.setupSections, weeklyBriefText: plan.weeklyBriefText) : nil }?.softLockedForPublish ?? plan.softLockedForPublish
        let cards = generatedDraft.flatMap { $0.weeklyPlanID == plan.id ? $0.markedPublished.publishedWeekCards : nil } ?? DailyCard.publishedCards(from: published)
        try savePublishedContent(cards: cards, todayCard: nil, plan: published)
        state.plan = published
        try persist()
        return WeeklyPublishResult(weeklyPlan: published, weekCards: cards, todayCard: DailyCard.bestTodayCard(from: cards), summary: "Published \(cards.count) cards to Creator Today.")
    }

    func readWeekCards() throws -> [DailyCard] {
        try currentRows().filter { Self.readyStatuses.contains($0.text("status") ?? "") }.map { try FakeJSON.decode(.object($0), as: SupabaseDailyCardRow.self).domainCard() }
    }

    func readTodayCard() throws -> DailyCard? {
        try readWeekCards().first { $0.scheduledDate == SupabaseDateFormatting.todayDateString() }
    }

    func saveGeneratedDraft(_ draft: GeneratedDailyCardDraft) throws {
        let plan = state.plans.values.first { $0.weekStartDate.map { $0 <= draft.scheduledDate && draft.scheduledDate <= SupabaseDateFormatting.weekEndDate(starting: $0) } == true } ?? Self.emptyPlan(for: draft.scheduledDate)
        state.plans[plan.id] = plan
        let pieceID = state.compatibilityPiece(for: draft.scheduledDate, context: context)
        if let id = state.pieces[pieceID]?.currentRevisionID, id != draft.id, let row = state.revisions[id] { archiveRevision(row) }
        state.revisions[draft.id] = try Self.revision(draft, planID: plan.id, context: context, pieceID: pieceID)
        state.pieces[pieceID]?.currentRevisionID = draft.id
        state.pieces[pieceID]?.generationKey = nil
        state.pieces[pieceID]?.updatedAt = SupabaseDateFormatting.isoTimestampString()
        try persist()
    }

    func savePublishedContent(cards: [DailyCard], todayCard: DailyCard?, plan: WeeklyPlan? = nil) throws {
        if let plan { state.plans[plan.id] = plan }
        for card in cards {
            guard let date = card.scheduledDate else { continue }
            let container = plan ?? state.plans.values.first { $0.weekStartDate.map { $0 <= date && date <= SupabaseDateFormatting.weekEndDate(starting: $0) } == true } ?? Self.emptyPlan(for: date)
            state.plans[container.id] = container
            let pieceID = state.compatibilityPiece(for: date, context: context)
            if let id = state.pieces[pieceID]?.currentRevisionID, id != card.id, let old = state.revisions[id] { archiveRevision(old) }
            state.revisions[card.id] = try Self.revision(GeneratedDailyCardDraft(fromPublishedCard: card, status: card.completionState?.supabaseStatus ?? "published"), planID: container.id, context: context, pieceID: pieceID)
            state.pieces[pieceID]?.currentRevisionID = card.id
            state.pieces[pieceID]?.generationKey = nil
            state.pieces[pieceID]?.updatedAt = SupabaseDateFormatting.isoTimestampString()
        }
        try persist()
    }
}

private struct LegacyFixtureContent: Decodable {
    var weekCards: [DailyCard]
    var todayCard: DailyCard?
    var generatedDrafts: [String: DailyCard]
    var historicalCards: [UUID: DailyCard]
    var decisions: [UUID: ArchiveEntry]

    private enum CodingKeys: String, CodingKey { case weekCards, todayCard, generatedDrafts, historicalCards, decisions }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        weekCards = try values.decode([DailyCard].self, forKey: .weekCards)
        todayCard = try values.decodeIfPresent(DailyCard.self, forKey: .todayCard)
        generatedDrafts = try values.decodeIfPresent([String: DailyCard].self, forKey: .generatedDrafts) ?? [:]
        historicalCards = try values.decodeIfPresent([UUID: DailyCard].self, forKey: .historicalCards) ?? [:]
        decisions = try values.decodeIfPresent([UUID: ArchiveEntry].self, forKey: .decisions) ?? [:]
    }
}

struct FixturePublishedContentStore: Sendable {
    let server: FakeServer
    init(server: FakeServer = .shared) { self.server = server }
    func readWeekCards() async -> [DailyCard] { (try? await server.readWeekCards()) ?? [] }
    func readTodayCard() async -> DailyCard? { try? await server.readTodayCard() }
    func saveGeneratedDraft(_ draft: GeneratedDailyCardDraft) async { try? await server.saveGeneratedDraft(draft) }
    func savePublishedContent(cards: [DailyCard], todayCard: DailyCard?) async { try? await server.savePublishedContent(cards: cards, todayCard: todayCard) }
}

struct FixtureTodayCardRepository: TodayCardRepository {
    let server: FakeServer
    init(publishedStore: FixturePublishedContentStore? = nil) { server = publishedStore?.server ?? .shared }

    func creatorDays(for context: WorkspaceContext) async throws -> [SupabaseCreatorDayRow]? {
        let response: SupabaseCreatorDaysResponse = try await server.invoke("read-content", body: SupabaseReadContentRequest(action: .days, creatorID: context.creatorID, includeAllPieces: true), context: context)
        return response.days
    }

    func todayCard(for context: WorkspaceContext) async throws -> DailyCard {
        let date = SupabaseDateFormatting.todayDateString()
        let response: SupabaseTodayReadResponse = try await server.invoke("read-content", body: SupabaseReadContentRequest(action: .today, creatorID: context.creatorID, todayDate: date), context: context)
        guard let card = response.todayCard else { throw RepositoryError.noPublishedTodayCard(date: date) }
        return card.domainCard()
    }

    func weekCards(for context: WorkspaceContext) async throws -> [DailyCard] {
        let response: SupabaseTodayReadResponse = try await server.invoke("read-content", body: SupabaseReadContentRequest(action: .today, creatorID: context.creatorID, todayDate: SupabaseDateFormatting.todayDateString()), context: context)
        return response.weekCards.map { $0.domainCard() }
    }

    func replayDecision(_ intent: ContentIntent, pieceID: UUID?, context: WorkspaceContext) async throws -> ArchiveEntry {
        guard let card = intent.cardSnapshot else { throw DayTransitionError.incompletePackage }
        let response: SupabaseWriteContentResponse = try await server.invoke("write-content", body: SupabaseWriteContentRequest.queuedDecision(intent, context: context, pieceID: pieceID), context: context)
        guard let entry = response.archiveEntry else { throw RepositoryError.edgeFunction("complete_today_missing_archive") }
        return entry.domainEntry(fallbackCard: card)
    }

    func completeToday(card: DailyCard, decision: DailyDecision, pieceID: UUID?, context: WorkspaceContext) async throws -> ArchiveEntry {
        let response: SupabaseWriteContentResponse = try await server.invoke("write-content", body: SupabaseWriteContentRequest.completeToday(card: card, decision: decision, context: context, pieceID: pieceID), context: context)
        guard let entry = response.archiveEntry else { throw RepositoryError.edgeFunction("complete_today_missing_archive") }
        return entry.domainEntry(fallbackCard: card)
    }
}

struct FixtureWeeklyPlanRepository: WeeklyPlanRepository {

    func movePiece(_ intent: ContentIntent, context: WorkspaceContext) async throws -> PieceMoveResult {
        try await server.invoke("move-piece", body: MovePieceRequest(intent: intent), context: context)
    }
    let server: FakeServer
    init(publishedStore: FixturePublishedContentStore? = nil) {
        server = publishedStore?.server ?? .shared
    }

    func currentPublishedPlan(for context: WorkspaceContext) async throws -> WeeklyPlan { try await currentWeeklyContent(for: context).publishedPlan }
    func currentGeneratedDraft(for context: WorkspaceContext) async throws -> GeneratedWeekDraft? { try await currentWeeklyContent(for: context).generatedDraft }
    func ideaBank(for context: WorkspaceContext) async throws -> [WeeklyIdea] { try await currentWeeklyContent(for: context).ideaBank }
    func currentWeeklyContent(for context: WorkspaceContext) async throws -> WeeklyRepositoryContent {
        let response: SupabaseWeeklyReadResponse = try await server.invoke("read-content", body: SupabaseReadContentRequest(action: .weekly, creatorID: context.creatorID), context: context)
        guard let row = response.publishedWeeklyPlan ?? response.weeklyPlan else { throw RepositoryError.missingFixture("No published weekly plan exists.") }
        let cards = response.publishedDailyCards.isEmpty ? response.dailyCards : response.publishedDailyCards
        let setup = response.publishedWeeklySetup ?? response.weeklySetup
        guard let publishedPlan = WeeklyRepositoryContent.makeWorkingPlan(from: cards, planRow: row,
            setupSections: setup?.setupSections ?? [], weeklyBriefText: setup?.weeklyBriefText ?? "") else { throw DayTransitionError.incompletePackage }
        let workingPlan = response.weeklyPlan.flatMap { plan in
            WeeklyRepositoryContent.makeWorkingPlan(from: response.dailyCards, planRow: plan,
                setupSections: response.weeklySetup?.setupSections ?? [], weeklyBriefText: response.weeklySetup?.weeklyBriefText ?? "")
        }
        return WeeklyRepositoryContent(publishedPlan: publishedPlan, workingPlan: workingPlan,
            generatedDraft: response.dailyCards.isEmpty ? nil : response.generatedDraft(), ideaBank: response.ideaBank.map { $0.domainIdea() })
    }

    func publishWeek(_ plan: WeeklyPlan, ideaBank: [WeeklyIdea], generatedDraft: GeneratedWeekDraft?, context: WorkspaceContext) async throws -> WeeklyPublishResult {
        try await server.publishWeek(plan, ideaBank: ideaBank, generatedDraft: generatedDraft)
    }

    func selectIdeaForNextOpenDay(_ idea: WeeklyIdea, in plan: WeeklyPlan, ideaBank: [WeeklyIdea], context: WorkspaceContext) async throws -> WeeklySelectionUpdate {
        let _: SupabaseWriteContentResponse = try await server.invoke("write-content", body: SupabaseWriteContentRequest.selectIdeaForNextOpenDay(idea: idea, plan: plan, context: context), context: context)
        let content = try await currentWeeklyContent(for: context)
        return WeeklySelectionUpdate(weeklyPlan: content.publishedPlan, ideaBank: content.ideaBank)
    }

    func updateWeeklySetupSections(_ sections: [WeeklySetupSection], in plan: WeeklyPlan, context: WorkspaceContext) async throws -> WeeklyPlan {
        let _: SupabaseWriteContentResponse = try await server.invoke("write-content", body: SupabaseWriteContentRequest.updateWeeklySetup(sections: sections, plan: plan, context: context), context: context)
        return try await currentPublishedPlan(for: context)
    }

    func updateWeeklyBrief(_ text: String, in plan: WeeklyPlan, context: WorkspaceContext) async throws -> WeeklyPlan {
        let _: SupabaseWriteContentResponse = try await server.invoke("write-content", body: SupabaseWriteContentRequest.updateWeeklyBrief(text: text, plan: plan, context: context), context: context)
        return try await currentPublishedPlan(for: context)
    }

    func updateDailyCardReviewState(dailyCardID: UUID, reviewState: String, context: WorkspaceContext) async throws {
        let _: SupabaseWriteContentResponse = try await server.invoke("write-content", body: SupabaseWriteContentRequest.updateDailyCardReviewState(dailyCardID: dailyCardID, reviewState: reviewState, context: context), context: context)
    }

    func replayPackage(_ intent: ContentIntent, pieceID: UUID?, context: WorkspaceContext) async throws -> OutboxReplayResult {
        do {
            switch intent.packageAction {
            case .makeReady:
                let response: SupabaseMakeDayAvailableResponse = try await server.invoke("make-day-available", body: SupabaseMakeDayAvailableRequest(pieceID: pieceID, creatorID: intent.creatorID, scheduledDate: intent.scheduledDate, dailyCardID: intent.revisionID, idempotencyKey: intent.id, expectedVersion: intent.expectedVersion), context: context)
                return .available(DayAvailabilityResult(pieceID: response.pieceID, dailyCardID: response.dailyCardID, scheduledDate: response.scheduledDate, status: response.status, weeklyPlanID: response.weeklyPlanID, weekIsSoftLocked: response.weekIsSoftLocked))
            case .returnToDraft:
                let response: SupabaseUnpublishDayResponse = try await server.invoke("unpublish-day", body: SupabaseUnpublishDayRequest(pieceID: pieceID, creatorID: intent.creatorID, scheduledDate: intent.scheduledDate, dailyCardID: intent.revisionID, idempotencyKey: intent.id, expectedVersion: intent.expectedVersion), context: context)
                return .unpublished(DayUnpublishResult(pieceID: response.pieceID, dailyCardID: response.dailyCardID, scheduledDate: response.scheduledDate, status: response.status, previousStatus: response.previousStatus, clearedLiveDecision: response.clearedLiveDecision, archiveRetained: response.archiveRetained, weeklyPlanID: response.weeklyPlanID))
            case .update:
                guard let package = intent.package else { throw DayTransitionError.incompletePackage }
                try package.validate()
                let response: SupabaseUpdateReadyDayPackageResponse = try await server.invoke("update-ready-day-package", body: SupabaseUpdateReadyDayPackageRequest(pieceID: pieceID, creatorID: intent.creatorID, scheduledDate: intent.scheduledDate, dailyCardID: intent.revisionID, package: package, idempotencyKey: intent.id, expectedVersion: intent.expectedVersion), context: context)
                return .package(DayPackageUpdateResult(pieceID: response.pieceID, dailyCardID: response.dailyCardID, scheduledDate: response.scheduledDate, status: response.status, weeklyPlanID: response.weeklyPlanID, title: response.title, caption: response.caption))
            case nil: throw DayTransitionError.illegalMove
            }
        } catch {
            let code = error.localizedDescription
            if code == "daily_card_not_draft" && intent.packageAction == .makeReady || code == "daily_card_already_draft" && intent.packageAction == .returnToDraft {
                let response: SupabaseCreatorDaysResponse = try await server.invoke("read-content", body: SupabaseReadContentRequest(action: .days, creatorID: context.creatorID, includeAllPieces: pieceID == nil ? nil : true), context: context)
                if let row = response.days.first(where: { $0.scheduledDate == intent.scheduledDate && $0.currentRevisionID == intent.revisionID }), let card = row.revision {
                    if intent.packageAction == .makeReady, DayPackageLifecycleStatus.requiresOverwriteConfirmation(card.status) {
                        return .available(DayAvailabilityResult(pieceID: card.pieceID, dailyCardID: card.id, scheduledDate: card.scheduledDate, status: card.status, weeklyPlanID: card.weeklyPlanID, weekIsSoftLocked: false))
                    }
                    if intent.packageAction == .returnToDraft, card.status == "draft" {
                        return .unpublished(DayUnpublishResult(pieceID: card.pieceID, dailyCardID: card.id, scheduledDate: card.scheduledDate, status: "draft", previousStatus: "draft", clearedLiveDecision: false, archiveRetained: true, weeklyPlanID: card.weeklyPlanID))
                    }
                }
            }
            throw error
        }
    }

    func makeDayAvailable(scheduledDate: String, dailyCardID: UUID?, pieceID: UUID?, context: WorkspaceContext) async throws -> DayAvailabilityResult {
        let response: SupabaseMakeDayAvailableResponse = try await server.invoke("make-day-available", body: SupabaseMakeDayAvailableRequest(pieceID: pieceID, creatorID: context.creatorID, scheduledDate: scheduledDate, dailyCardID: dailyCardID), context: context)
        return DayAvailabilityResult(pieceID: response.pieceID, dailyCardID: response.dailyCardID, scheduledDate: response.scheduledDate, status: response.status, weeklyPlanID: response.weeklyPlanID, weekIsSoftLocked: response.weekIsSoftLocked)
    }

    func unpublishDay(scheduledDate: String, dailyCardID: UUID?, pieceID: UUID?, context: WorkspaceContext) async throws -> DayUnpublishResult {
        let response: SupabaseUnpublishDayResponse = try await server.invoke("unpublish-day", body: SupabaseUnpublishDayRequest(pieceID: pieceID, creatorID: context.creatorID, scheduledDate: scheduledDate, dailyCardID: dailyCardID), context: context)
        return DayUnpublishResult(pieceID: response.pieceID, dailyCardID: response.dailyCardID, scheduledDate: response.scheduledDate, status: response.status, previousStatus: response.previousStatus, clearedLiveDecision: response.clearedLiveDecision, archiveRetained: response.archiveRetained, weeklyPlanID: response.weeklyPlanID)
    }

    func updateReadyDayPackage(scheduledDate: String, dailyCardID: UUID?, package: ReadyDayPackageUpdate, pieceID: UUID?, context: WorkspaceContext) async throws -> DayPackageUpdateResult {
        try package.validate()
        let response: SupabaseUpdateReadyDayPackageResponse = try await server.invoke("update-ready-day-package", body: SupabaseUpdateReadyDayPackageRequest(pieceID: pieceID, creatorID: context.creatorID, scheduledDate: scheduledDate, dailyCardID: dailyCardID, package: package), context: context)
        return DayPackageUpdateResult(pieceID: response.pieceID, dailyCardID: response.dailyCardID, scheduledDate: response.scheduledDate, status: response.status, weeklyPlanID: response.weeklyPlanID, title: response.title, caption: response.caption)
    }
}

struct FixtureDayGenerationRepository: DayGenerationRepository {
    var artificialDelayNanoseconds: UInt64
    let server: FakeServer
    init(artificialDelayNanoseconds: UInt64 = DebugLaunchFlags.fixtureFirstIdeaDelayNanoseconds, publishedStore: FixturePublishedContentStore? = nil) {
        self.artificialDelayNanoseconds = artificialDelayNanoseconds
        server = publishedStore?.server ?? .shared
    }

    func persistedDayPackages(context: WorkspaceContext) async -> [GeneratedDailyCardDraft] {
        guard let response: SupabaseCreatorDaysResponse = try? await server.invoke("read-content", body: SupabaseReadContentRequest(action: .days, creatorID: context.creatorID), context: context) else { return [] }
        return response.days.compactMap { $0.revision?.generatedDailyCardDraft() }
    }

    func replayGeneration(_ intent: ContentIntent, pieceID: UUID?, context: WorkspaceContext) async throws -> OutboxGenerationResponse {
        let invocation: SupabaseDailyGenerationInvocation
        if let id = intent.generationID {
            invocation = try await server.generation("generate-week", body: SupabaseGenerationStatusRequest(generationID: id, creatorID: intent.creatorID), context: context, delayNanoseconds: artificialDelayNanoseconds)
        } else if intent.kind == .replaceDay {
            invocation = try await server.generation("replace-day", body: SupabaseReplaceDayRequest(pieceID: pieceID, creatorID: intent.creatorID, scheduledDate: intent.scheduledDate, dailyCardID: intent.revisionID, dayBrief: intent.dayBrief ?? "", idempotencyKey: intent.id), context: context, delayNanoseconds: artificialDelayNanoseconds)
        } else if let planID = intent.weeklyPlanID, let preserve = intent.preserveManualEdits {
            invocation = try await server.generation("generate-week", body: SupabaseRegenerateDayRequest(pieceID: pieceID, creatorID: intent.creatorID, weeklyPlanID: planID, scheduledDate: intent.scheduledDate, preserveManualEdits: preserve, responseMode: .async, dayGuidance: intent.dayGuidance, idempotencyKey: intent.id), context: context, delayNanoseconds: artificialDelayNanoseconds)
        } else {
            invocation = try await server.generation("generate-week", body: SupabaseDailyGenerationRequest(pieceID: pieceID, creatorID: intent.creatorID, scheduledDate: intent.scheduledDate, dayBrief: intent.dayBrief ?? "", responseMode: .async, idempotencyKey: intent.id), context: context, delayNanoseconds: artificialDelayNanoseconds)
        }
        return try invocation.outboxResponse(for: intent, pieceID: pieceID, defaultPollAfterSeconds: 1)
    }

    func generateDay(creatorID: UUID, scheduledDate: String, dayBrief: String, pieceID: UUID?, context: WorkspaceContext) async throws -> DailyGenerationResult {
        try await finish(try await server.generation("generate-week", body: SupabaseDailyGenerationRequest(pieceID: pieceID, creatorID: creatorID, scheduledDate: scheduledDate, dayBrief: dayBrief, responseMode: .async), context: context, delayNanoseconds: artificialDelayNanoseconds), creatorID: creatorID, context: context)
    }

    func regenerateDay(creatorID: UUID, weeklyPlanID: UUID, scheduledDate: String, preserveManualEdits: Bool, dayGuidance: String?, pieceID: UUID?, context: WorkspaceContext) async throws -> DailyGenerationResult {
        try await finish(try await server.generation("generate-week", body: SupabaseRegenerateDayRequest(pieceID: pieceID, creatorID: creatorID, weeklyPlanID: weeklyPlanID, scheduledDate: scheduledDate, preserveManualEdits: preserveManualEdits, responseMode: .async, dayGuidance: dayGuidance), context: context, delayNanoseconds: artificialDelayNanoseconds), creatorID: creatorID, context: context)
    }

    func resumeAcceptedDayGeneration(generationID: UUID, creatorID: UUID, context: WorkspaceContext) async throws -> DailyGenerationResult {
        try await finish(try await server.generation("generate-week", body: SupabaseGenerationStatusRequest(generationID: generationID, creatorID: creatorID), context: context, delayNanoseconds: artificialDelayNanoseconds), creatorID: creatorID, context: context)
    }

    private func finish(_ initial: SupabaseDailyGenerationInvocation, creatorID: UUID, context: WorkspaceContext) async throws -> DailyGenerationResult {
        var invocation = initial
        while true {
            switch invocation {
            case .completed(let response): return response.domainResult
            case .failed(let response): throw RepositoryError.edgeFunction(response.error ?? "invalid_generated_day")
            case .running(let response):
                try await Task.sleep(nanoseconds: UInt64(response.pollAfterSeconds ?? 1) * 1_000_000_000)
                invocation = try await server.generation("generate-week", body: SupabaseGenerationStatusRequest(generationID: response.generationID, creatorID: creatorID), context: context, delayNanoseconds: artificialDelayNanoseconds)
            }
        }
    }
}

struct FixtureCreatorProfileRepository: CreatorProfileRepository {
    let server: FakeServer
    init(server: FakeServer = .shared) { self.server = server }

    func activeProfileSummary(for context: WorkspaceContext) async throws -> CreatorProfileSummary {
        let response: SupabaseCreatorProfileReadResponse = try await server.invoke("read-content", body: SupabaseReadContentRequest(action: .creatorProfile, creatorID: context.creatorID), context: context)
        return response.profile?.summary() ?? .creatorFixture
    }

    func updateProfile(_ update: CreatorProfileUpdate, context: WorkspaceContext) async throws -> CreatorProfileSummary {
        let response: SupabaseWriteContentResponse = try await server.invoke("write-content", body: SupabaseWriteContentRequest.updateCreatorProfile(update, context: context), context: context)
        guard let profile = response.creatorProfile else { throw RepositoryError.edgeFunction("creator_profile_update_failed") }
        return profile.summary()
    }
}

struct FixtureArchiveRepository: ArchiveRepository {
    let server: FakeServer
    init(server: FakeServer = .shared) { self.server = server }

    func entries(for context: WorkspaceContext) async throws -> [ArchiveEntry] {
        let response: SupabaseArchiveReadResponse = try await server.invoke("read-content", body: SupabaseReadContentRequest(action: .archive, creatorID: context.creatorID), context: context)
        return response.entries.map { $0.domainEntry() }
    }

    func persistDecision(_ entry: ArchiveEntry, for card: DailyCard, pieceID: UUID?, context: WorkspaceContext) async throws {
        let _: SupabaseWriteContentResponse = try await server.invoke("write-content", body: SupabaseWriteContentRequest.upsertArchiveDecision(entry, for: card, context: context, pieceID: pieceID), context: context)
    }

    func upsertDecision(_ entry: ArchiveEntry, for card: DailyCard, pieceID: UUID?, context: WorkspaceContext) async throws -> [ArchiveEntry] {
        try await persistDecision(entry, for: card, pieceID: pieceID, context: context)
        return try await entries(for: context)
    }
}

private struct FakePlanIdea: Decodable, Sendable {
    var title: String
    var summary: String
    var dayBrief: String
    enum CodingKeys: String, CodingKey { case title, summary; case dayBrief = "day_brief" }
}

private struct FakePlanIdeasResponse: Decodable, Sendable {
    var ideas: [FakePlanIdea]
}

struct FixturePlanDayIdeaRepository: PlanDayIdeaRepository {
    var server: FakeServer = .shared
    func generatePlanDayIdeas(creatorID: UUID, scheduledDate: String, setup: PlanDaySetupSummary, context: WorkspaceContext) async throws -> [PlanDayIdeaCandidate] {
        var payload: FakeObject = [
            "creator_id": .string(creatorID.uuidString), "scheduled_date": .string(scheduledDate),
            "content_pillars": try FakeJSON.value(setup.contentPillars), "voice_configured": .bool(setup.voiceIsConfigured),
            "reference_count": .number(Double(setup.confirmedReferenceCount)),
            "positioning": .string(setup.positioning), "voice_rules": .string(setup.voiceRulesText),
            "caption_style": .string(setup.captionStyle), "no_go_topics": .string(setup.noGoTopicsText),
            "reference_labels": try FakeJSON.value(setup.confirmedReferenceLabels)
        ]
        for key in ["positioning", "voice_rules", "caption_style", "no_go_topics"] where payload.text(key)?.isEmpty == true { payload.removeValue(forKey: key) }
        let response: FakePlanIdeasResponse = try await server.invoke("generate-plan-ideas", body: payload, context: context)
        return response.ideas.map { PlanDayIdeaCandidate(title: $0.title, summary: $0.summary, dayBrief: $0.dayBrief) }
    }
}

struct AppFixtureStoryboardThumbnailUnavailableRepository: StoryboardThumbnailRepository {}

struct FixtureReferenceRepository: ReferenceRepository {
    func sourcePulse(for context: WorkspaceContext) async throws -> SourcePulseSummary {
        IntelligenceHome.raceWeekLibrary.sourcePulse
    }
}

struct FixtureIntelligenceRepository: IntelligenceRepository {
    func home(for context: WorkspaceContext) async throws -> IntelligenceHome {
        IntelligenceHome.raceWeekLibrary
    }
}

struct FixtureTesterAccessRepository: TesterAccessRepository {
    func listTesters(context: WorkspaceContext) async throws -> [TesterAccessRecord] {
        [
            TesterAccessRecord(
                id: UUID(uuidString: "4A6E72A4-4450-44B3-A83B-A5EFB87F6301")!,
                email: "tester@example.com",
                displayName: "Fixture Tester",
                role: "editor",
                status: "active",
                createdAt: nil,
                updatedAt: nil
            )
        ]
    }

    func inviteTester(email: String, displayName: String?, context: WorkspaceContext) async throws -> TesterAccessRecord {
        TesterAccessRecord(
            id: UUID(),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            displayName: displayName?.nilIfBlank,
            role: "editor",
            status: "active",
            createdAt: nil,
            updatedAt: nil
        )
    }

    func resendTesterOTP(email: String, context: WorkspaceContext) async throws -> TesterAccessRecord {
        TesterAccessRecord(
            id: UUID(),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            displayName: nil,
            role: "editor",
            status: "active",
            createdAt: nil,
            updatedAt: nil
        )
    }

    func revokeTester(memberID: UUID, context: WorkspaceContext) async throws -> TesterAccessRecord {
        TesterAccessRecord(
            id: memberID,
            email: "revoked@example.com",
            displayName: nil,
            role: "editor",
            status: "revoked",
            createdAt: nil,
            updatedAt: nil
        )
    }
}

struct FixtureRuntimeHealthRepository: RuntimeHealthRepository {
    func checkHealth(for context: WorkspaceContext) async throws -> RuntimeHealthReport {
        _ = context
        return RuntimeHealthReport(
            supabaseOK: false,
            geminiOK: false,
            supabaseDetail: "sample_runtime",
            geminiDetail: "sample_runtime",
            checkedAt: Date()
        )
    }
}

extension FixtureTodayCardRepository {
    func replayDecision(_ intent: ContentIntent, context: WorkspaceContext) async throws -> ArchiveEntry {
        try await replayDecision(intent, pieceID: nil, context: context)
    }

    func completeToday(
        card: DailyCard,
        decision: DailyDecision,
        context: WorkspaceContext
    ) async throws -> ArchiveEntry {
        try await completeToday(card: card, decision: decision, pieceID: nil, context: context)
    }
}

extension FixtureWeeklyPlanRepository {
    func replayPackage(_ intent: ContentIntent, context: WorkspaceContext) async throws -> OutboxReplayResult {
        try await replayPackage(intent, pieceID: nil, context: context)
    }

    func makeDayAvailable(
        scheduledDate: String,
        dailyCardID: UUID?,
        context: WorkspaceContext
    ) async throws -> DayAvailabilityResult {
        try await makeDayAvailable(scheduledDate: scheduledDate, dailyCardID: dailyCardID, pieceID: nil, context: context)
    }

    func unpublishDay(
        scheduledDate: String,
        dailyCardID: UUID?,
        context: WorkspaceContext
    ) async throws -> DayUnpublishResult {
        try await unpublishDay(scheduledDate: scheduledDate, dailyCardID: dailyCardID, pieceID: nil, context: context)
    }

    func updateReadyDayPackage(
        scheduledDate: String,
        dailyCardID: UUID?,
        package: ReadyDayPackageUpdate,
        context: WorkspaceContext
    ) async throws -> DayPackageUpdateResult {
        try await updateReadyDayPackage(scheduledDate: scheduledDate, dailyCardID: dailyCardID, package: package, pieceID: nil, context: context)
    }
}

extension FixtureDayGenerationRepository {
    func replayGeneration(_ intent: ContentIntent, context: WorkspaceContext) async throws -> OutboxGenerationResponse {
        try await replayGeneration(intent, pieceID: nil, context: context)
    }

    func generateDay(
        creatorID: UUID,
        scheduledDate: String,
        dayBrief: String,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        try await generateDay(creatorID: creatorID, scheduledDate: scheduledDate, dayBrief: dayBrief, pieceID: nil, context: context)
    }

    func regenerateDay(
        creatorID: UUID,
        weeklyPlanID: UUID,
        scheduledDate: String,
        preserveManualEdits: Bool,
        dayGuidance: String?,
        context: WorkspaceContext
    ) async throws -> DailyGenerationResult {
        try await regenerateDay(creatorID: creatorID, weeklyPlanID: weeklyPlanID, scheduledDate: scheduledDate, preserveManualEdits: preserveManualEdits, dayGuidance: dayGuidance, pieceID: nil, context: context)
    }
}

extension FixtureArchiveRepository {
    func persistDecision(
        _ entry: ArchiveEntry,
        for card: DailyCard,
        context: WorkspaceContext
    ) async throws {
        try await persistDecision(entry, for: card, pieceID: nil, context: context)
    }

    func upsertDecision(
        _ entry: ArchiveEntry,
        for card: DailyCard,
        context: WorkspaceContext
    ) async throws -> [ArchiveEntry] {
        try await upsertDecision(entry, for: card, pieceID: nil, context: context)
    }
}
