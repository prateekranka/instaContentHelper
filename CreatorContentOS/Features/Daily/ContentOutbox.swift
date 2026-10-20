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

    var isGeneration: Bool {
        kind == .generate || kind == .replaceDay || kind == .firstIdea
    }

    init(kind: ContentIntentKind, context: WorkspaceContext, scheduledDate: String, revisionID: UUID = UUID()) {
        self.kind = kind
        workspaceID = context.workspaceID
        creatorID = context.creatorID
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
