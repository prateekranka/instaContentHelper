import Foundation

struct PieceSyncUpload: Encodable, Sendable {
    var id: UUID
    var scheduledDate: String
    var document: SupabaseJSONValue
    var baseRevision: Int?
    var clientUpdatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case scheduledDate = "scheduled_date"
        case document
        case baseRevision = "base_revision"
        case clientUpdatedAt = "client_updated_at"
    }
}

struct PieceSyncRemote: Decodable, Sendable {
    var id: UUID
    var scheduledDate: String
    var document: SupabaseJSONValue
    var revision: Int
    var syncSequence: Int

    enum CodingKeys: String, CodingKey {
        case id
        case scheduledDate = "scheduled_date"
        case document
        case revision
        case syncSequence = "sync_sequence"
    }
}

struct PieceSyncAccepted: Decodable, Sendable {
    var id: UUID
    var revision: Int
    var syncSequence: Int

    enum CodingKeys: String, CodingKey {
        case id
        case revision
        case syncSequence = "sync_sequence"
    }
}

struct PieceSyncPushResult: Decodable, Sendable {
    var accepted: [PieceSyncAccepted]
    var conflicts: [PieceSyncRemote]
}

struct PieceSyncPullResult: Decodable, Sendable {
    var pieces: [PieceSyncRemote]
    var cursor: Int
    var hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case pieces
        case cursor
        case hasMore = "has_more"
    }
}

protocol PieceSyncRepository: Sendable {
    var isEnabled: Bool { get }
    func pullPieces(since cursor: Int, context: WorkspaceContext) async throws -> PieceSyncPullResult
    func pushPieces(_ uploads: [PieceSyncUpload], context: WorkspaceContext) async throws -> PieceSyncPushResult
}

struct LocalOnlyPieceSyncRepository: PieceSyncRepository {
    var isEnabled: Bool { false }

    func pullPieces(since cursor: Int, context: WorkspaceContext) async throws -> PieceSyncPullResult {
        PieceSyncPullResult(pieces: [], cursor: cursor, hasMore: false)
    }

    func pushPieces(_ uploads: [PieceSyncUpload], context: WorkspaceContext) async throws -> PieceSyncPushResult {
        throw RepositoryError.notConfigured("piece_sync_not_configured")
    }
}

enum PieceSyncStatus: Equatable, Sendable {
    case localOnly
    case idle
    case syncing
    case synced(Date)
    case failed(String)
}

enum PieceDocumentCoding {
    static func document(for piece: ContentPiece) throws -> SupabaseJSONValue {
        let data = try encoder.encode(piece)
        return try JSONDecoder().decode(SupabaseJSONValue.self, from: data)
    }

    static func piece(from document: SupabaseJSONValue) throws -> ContentPiece {
        let data = try JSONEncoder().encode(document)
        return try decoder.decode(ContentPiece.self, from: data)
    }

    static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
