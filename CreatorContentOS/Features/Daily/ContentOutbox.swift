import Foundation

enum ContentIntentKind: String, Codable, Hashable, Sendable {
    case decide
    case editPackage
    case generate
    case replaceDay
    case firstIdea
}

enum PackageIntentAction: String, Codable, Hashable, Sendable {
    case update
    case makeReady
    case returnToDraft
}

struct ContentIntent: Codable, Hashable, Sendable, Identifiable {
    var id: String { idempotencyKey }
    var kind: ContentIntentKind
    var workspaceID: UUID
    var creatorID: UUID
    var scheduledDate: String
    var pieceID: UUID?
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

    var generationPieceID: UUID? { usesLegacyGenerationIdentity == true ? nil : pieceID }

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
