import Foundation

enum ContentIntentKind: String, Codable, Hashable, Sendable {
    case decide
    case editPackage
    case generate
    case replaceDay
    case firstIdea
    case movePiece
}

enum PackageIntentAction: String, Codable, Hashable, Sendable {
    case update
    case makeReady
    case returnToDraft
}

enum PieceMoveErrorDisplay {
    private static func code(for error: Error) -> String {
        SupabaseFunctionErrorMapper.errorCode(from: error) ?? error.localizedDescription
    }

    static func isTerminal(_ error: Error) -> Bool {
        ["invalid_piece_id", "invalid_move_piece_payload", "invalid_json", "method_not_allowed",
         "piece_not_found", "piece_scope_mismatch", "piece_removed", "piece_date_conflict",
         "idempotency_key_conflict", "creator_not_found", "missing_device_token",
         "invalid_device_token", "role_not_allowed"].contains(code(for: error))
    }

    static func message(for error: Error, isQueued: Bool) -> String {
        switch code(for: error) {
        case "piece_generation_running":
            return isQueued
                ? "This piece is still being prepared. Your move is saved for retry."
                : "Wait for this piece to finish, then try the move again."
        case "piece_date_conflict":
            return "This piece has moved. Open its current date and try again."
        case "piece_removed":
            return "This piece was removed and cannot be moved."
        case "piece_not_found":
            return "This piece is no longer available. Refresh Plan and try again."
        case "piece_scope_mismatch", "creator_not_found":
            return "This piece is not available for this creator. Refresh Plan and try again."
        case "missing_device_token", "invalid_device_token":
            return "Sign in again before moving this piece."
        case "role_not_allowed":
            return "Your account cannot move this piece."
        case "invalid_piece_id", "invalid_move_piece_payload", "invalid_json", "method_not_allowed", "idempotency_key_conflict":
            return "This move could not be completed. Choose the date again."
        case "piece_move_pending":
            return isQueued
                ? "This piece already has a saved move. Wait for it to finish."
                : "Choose the date again to move this piece."
        case "move_piece_failed", "missing_function_secrets", "creator_lookup_failed", "device_lookup_failed", "member_lookup_failed":
            return isQueued
                ? "Moves are unavailable right now. Your move is saved and will retry."
                : "Moves are unavailable right now. Try again later."
        default:
            return isQueued
                ? "This move is saved. It will try again when the connection returns."
                : "This move could not be saved. Try again."
        }
    }
}

struct ContentIntent: Codable, Hashable, Sendable, Identifiable {
    var id: String { idempotencyKey }
    var kind: ContentIntentKind
    var workspaceID: UUID
    var creatorID: UUID
    var scheduledDate: String
    var pieceID: UUID?
    var targetScheduledDate: String?
    var usesDateOnlyGenerationIdentity: Bool?
    var usesLegacyGenerationIdentity: Bool?
    var usesLegacyPieceTarget: Bool?
    var revisionID: UUID
    var idempotencyKey: String = UUID().uuidString
    var createdAt: Date = Date()
    var requestedRevisionID: UUID = UUID()
    var generationID: UUID?
    var generatedRevisionID: UUID?
    var priorRevisionID: UUID?
    var supersededByServer: Bool?
    var terminalFailureCode: String?
    var dayBrief: String?
    var weeklyPlanID: UUID?
    var preserveManualEdits: Bool?
    var dayGuidance: String?
    var packageAction: PackageIntentAction?
    var package: ReadyDayPackageUpdate?
    var expectedVersion: String?
    var decision: DailyDecision?
    var undoPosted = false
    var cardSnapshot: DailyCard?
    var archiveSnapshot: ArchiveEntry?
    var completedData: OnboardingCompletedData?
    var profileSaved = false
    var firstIdeaSkipped = false

    var generationPieceID: UUID? { usesLegacyGenerationIdentity == true || usesDateOnlyGenerationIdentity == true ? nil : pieceID }

    var isGeneration: Bool {
        kind == .generate || kind == .replaceDay || kind == .firstIdea
    }

    init(kind: ContentIntentKind, context: WorkspaceContext, scheduledDate: String, revisionID: UUID = UUID(), pieceID: UUID? = nil) {
        self.kind = kind
        workspaceID = context.workspaceID
        creatorID = context.creatorID
        self.pieceID = pieceID
        self.scheduledDate = scheduledDate
        self.revisionID = revisionID
        if kind != .replaceDay { requestedRevisionID = revisionID }
    }
}

enum OutboxGenerationResponse: Sendable {
    case running(UUID, pollAfterSeconds: Int)
    case completed(DailyGenerationResult)
    case failed(String)
}

extension SupabaseDailyGenerationInvocation {
    func outboxResponse(for intent: ContentIntent, pieceID: UUID?, defaultPollAfterSeconds: Int) throws -> OutboxGenerationResponse {
        let serverPieceID: UUID?
        let generationID: UUID
        let result: OutboxGenerationResponse
        switch self {
        case .completed(let response):
            guard response.pieceID == nil || response.dailyCard.pieceID == nil || response.pieceID == response.dailyCard.pieceID else { throw DayTransitionError.mismatchedRevision }
            serverPieceID = response.pieceID ?? response.dailyCard.pieceID
            generationID = response.generationID
            result = .completed(response.domainResult)
        case .running(let response):
            serverPieceID = response.pieceID
            generationID = response.generationID
            result = .running(generationID, pollAfterSeconds: response.pollAfterSeconds ?? defaultPollAfterSeconds)
        case .failed(let response):
            serverPieceID = response.pieceID
            generationID = response.generationID
            result = .failed(response.error ?? "invalid_generated_day")
        }
        guard pieceID == nil || serverPieceID == pieceID,
              intent.generationID == nil || intent.generationID == generationID else { throw DayTransitionError.mismatchedRevision }
        return result
    }
}

enum OutboxReplayResult: Sendable {
    case decision(ArchiveEntry)
    case package(DayPackageUpdateResult)
    case available(DayAvailabilityResult)
    case unpublished(DayUnpublishResult)
    case moved(PieceMoveResult)
    case generated(GeneratedDailyCardDraft)
    case firstIdea(OnboardingFirstIdeaHandoffResult)
}

enum OutboxTerminalFailure: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self { case .server(let code): code }
    }
}

struct LegacyFirstIdeaMigration: Decodable {
    var creatorID: UUID
    var scheduledDate: String
    var completedData: OnboardingCompletedData
}

struct LegacyGenerationMigration: Decodable {
    var scheduledDate: String
    var generationID: UUID
    var creatorID: UUID
    var acceptedAt: Date
}
