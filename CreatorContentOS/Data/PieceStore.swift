import Foundation
import Observation

@MainActor
@Observable
final class PieceStore {
    private(set) var library: PieceLibrary
    var lastError: String?
    private(set) var syncStatus: PieceSyncStatus = .localOnly

    @ObservationIgnored private let directoryURL: URL?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var syncRepository: (any PieceSyncRepository)?
    @ObservationIgnored private var syncContext: WorkspaceContext?
    @ObservationIgnored private var scheduledSync: Task<Void, Never>?
    @ObservationIgnored private var isSyncing = false
    @ObservationIgnored private var syncRequestedWhileRunning = false

    init(directoryURL: URL?, now: @escaping () -> Date = Date.init) {
        self.directoryURL = directoryURL
        self.now = now
        library = PieceStore.load(from: directoryURL) ?? PieceLibrary()
    }

    convenience init(context: WorkspaceContext) {
        self.init(directoryURL: PieceStore.defaultDirectory(for: context))
    }

    static func defaultDirectory(for context: WorkspaceContext) -> URL? {
        if DebugLaunchConfiguration.isEnabled("MCO_FORCE_FIXTURE_UI") {
            return DebugLaunchConfiguration.fixtureCacheDirectory?
                .appendingPathComponent("Pieces", isDirectory: true)
        }
        guard let root = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        return root
            .appendingPathComponent("CreatorContentOS", isDirectory: true)
            .appendingPathComponent("Pieces", isDirectory: true)
            .appendingPathComponent("\(context.workspaceID.uuidString)-\(context.creatorID.uuidString)", isDirectory: true)
    }

    func piece(_ id: UUID) -> ContentPiece? {
        library.piece(id)
    }

    func pieces(on date: String) -> [ContentPiece] {
        library.pieces(on: date)
    }

    func summary(on date: String) -> PieceDaySummary {
        library.summary(on: date)
    }

    func piece(linkedTo dailyCardID: UUID) -> ContentPiece? {
        library.pieces.first { $0.linkedDailyCardID == dailyCardID }
    }

    @discardableResult
    func update(_ change: (inout PieceLibrary, Date) throws -> Void) -> Bool {
        var next = library
        do {
            try change(&next, now())
        } catch {
            lastError = PieceStore.message(for: error)
            return false
        }
        guard next != library else { return true }
        let previous = Dictionary(uniqueKeysWithValues: library.pieces.map { ($0.id, $0) })
        for piece in next.pieces where previous[piece.id] != piece {
            let revision = next.syncState(for: piece.id)?.revision
            next.setSyncState(PieceSyncState(revision: revision, dirty: true), for: piece.id)
        }
        library = next
        lastError = nil
        save()
        scheduleSync()
        return true
    }

    var hasUnsyncedChanges: Bool {
        syncRepository?.isEnabled == true && library.hasUnsyncedChanges
    }

    func isWaitingToSync(_ id: UUID) -> Bool {
        guard syncRepository?.isEnabled == true else { return false }
        return library.syncState(for: id)?.dirty ?? true
    }

    func configureSync(repository: any PieceSyncRepository, context: WorkspaceContext) {
        syncRepository = repository
        syncContext = context
        guard repository.isEnabled else {
            syncStatus = .localOnly
            return
        }
        syncStatus = .idle
        scheduleSync(after: 0)
    }

    func scheduleSync(after nanoseconds: UInt64 = 1_500_000_000) {
        guard syncRepository?.isEnabled == true else { return }
        scheduledSync?.cancel()
        scheduledSync = Task { @MainActor [weak self] in
            if nanoseconds > 0 {
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    func syncNow() async {
        guard let repository = syncRepository, repository.isEnabled, let context = syncContext else { return }
        guard !isSyncing else {
            syncRequestedWhileRunning = true
            return
        }
        isSyncing = true
        syncStatus = .syncing
        defer { isSyncing = false }
        do {
            try await pull(repository: repository, context: context)
            try await push(repository: repository, context: context)
            syncStatus = .synced(now())
        } catch {
            syncStatus = .failed(error.localizedDescription)
        }
        if syncRequestedWhileRunning {
            syncRequestedWhileRunning = false
            scheduleSync()
        }
    }

    private func pull(repository: any PieceSyncRepository, context: WorkspaceContext) async throws {
        var cursor = library.syncCursor ?? 0
        while true {
            let result = try await repository.pullPieces(since: cursor, context: context)
            var next = library
            for remote in result.pieces {
                try applyRemote(remote, to: &next)
            }
            next.syncCursor = max(result.cursor, cursor)
            commitSynced(next)
            guard result.hasMore, result.cursor > cursor else { break }
            cursor = result.cursor
        }
    }

    private func push(repository: any PieceSyncRepository, context: WorkspaceContext) async throws {
        for _ in 0..<3 {
            let pending = library.pieces.filter { library.syncState(for: $0.id)?.dirty ?? true }
            guard !pending.isEmpty else { return }
            var start = 0
            while start < pending.count {
                let chunk = Array(pending[start..<min(start + 50, pending.count)])
                start += 50
                let uploads = try chunk.map { piece in
                    PieceSyncUpload(
                        id: piece.id,
                        scheduledDate: piece.date,
                        document: try PieceDocumentCoding.document(for: piece),
                        baseRevision: library.syncState(for: piece.id)?.revision,
                        clientUpdatedAt: PieceDocumentCoding.timestamp(piece.updatedAt)
                    )
                }
                let result = try await repository.pushPieces(uploads, context: context)
                var next = library
                let sentByID = Dictionary(uniqueKeysWithValues: uploads.map { ($0.id, $0.document) })
                for accepted in result.accepted {
                    let current = try next.piece(accepted.id).map { try PieceDocumentCoding.document(for: $0) }
                    let changedSinceSend = current != nil && current != sentByID[accepted.id]
                    next.setSyncState(PieceSyncState(revision: accepted.revision, dirty: changedSinceSend), for: accepted.id)
                }
                for conflict in result.conflicts {
                    try applyRemote(conflict, to: &next)
                }
                commitSynced(next)
            }
        }
    }

    private func applyRemote(_ remote: PieceSyncRemote, to next: inout PieceLibrary) throws {
        let remotePiece = try PieceDocumentCoding.piece(from: remote.document)
        guard remotePiece.id == remote.id else { return }
        if let index = next.pieces.firstIndex(where: { $0.id == remote.id }) {
            let local = next.pieces[index]
            let dirty = next.syncState(for: remote.id)?.dirty ?? true
            if dirty {
                let merged = ContentPiece.merged(local, remotePiece)
                next.pieces[index] = merged
                let differs = try PieceDocumentCoding.document(for: merged) != remote.document
                next.setSyncState(PieceSyncState(revision: remote.revision, dirty: differs), for: remote.id)
            } else {
                next.pieces[index] = remotePiece
                next.setSyncState(PieceSyncState(revision: remote.revision, dirty: false), for: remote.id)
            }
            return
        }
        if let linked = remotePiece.linkedDailyCardID,
           let duplicate = next.pieces.firstIndex(where: { candidate in
               candidate.linkedDailyCardID == linked
                   && next.syncState(for: candidate.id)?.revision == nil
                   && candidate.versions.count == 1
                   && candidate.captures.isEmpty
                   && candidate.postings.isEmpty
                   && candidate.markedShotAt == nil
           }) {
            next.syncStates?[next.pieces[duplicate].id.uuidString] = nil
            next.pieces.remove(at: duplicate)
        }
        next.pieces.append(remotePiece)
        next.setSyncState(PieceSyncState(revision: remote.revision, dirty: false), for: remote.id)
    }

    private func commitSynced(_ next: PieceLibrary) {
        guard next != library else { return }
        library = next
        save()
    }

    @discardableResult
    func addPiece(
        date: String,
        content: PieceContent,
        origin: PieceVersionOrigin,
        approved: Bool = false,
        linkedDailyCardID: UUID? = nil,
        basedOnPieceID: UUID? = nil,
        topic: String? = nil
    ) -> ContentPiece {
        var created: ContentPiece?
        update { library, now in
            created = library.addPiece(
                date: date,
                content: content,
                origin: origin,
                approved: approved,
                linkedDailyCardID: linkedDailyCardID,
                basedOnPieceID: basedOnPieceID,
                topic: topic,
                now: now
            )
        }
        return created!
    }

    var mediaDirectoryURL: URL? {
        directoryURL?.appendingPathComponent("Media", isDirectory: true)
    }

    /// Media files stay on the device that added them; synced records on other devices return nil.
    func mediaURL(for fileName: String) -> URL? {
        guard let url = mediaDirectoryURL?.appendingPathComponent(fileName, isDirectory: false),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    func storeMediaFile(from sourceURL: URL, preferredExtension: String) throws -> String {
        guard let mediaDirectoryURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: mediaDirectoryURL, withIntermediateDirectories: true)
        let ext = sourceURL.pathExtension.isEmpty ? preferredExtension : sourceURL.pathExtension
        let fileName = "\(UUID().uuidString).\(ext.lowercased())"
        try FileManager.default.copyItem(at: sourceURL, to: mediaDirectoryURL.appendingPathComponent(fileName))
        return fileName
    }

    func storeMediaData(_ data: Data, fileExtension: String) throws -> String {
        guard let mediaDirectoryURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: mediaDirectoryURL, withIntermediateDirectories: true)
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        try data.write(to: mediaDirectoryURL.appendingPathComponent(fileName), options: [.atomic])
        return fileName
    }

    private func save() {
        guard let directoryURL else { return }
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(library)
            try data.write(to: directoryURL.appendingPathComponent("library.json"), options: [.atomic])
        } catch {
            lastError = "Could not save on this device. \(error.localizedDescription)"
        }
    }

    private static func load(from directoryURL: URL?) -> PieceLibrary? {
        guard let fileURL = directoryURL?.appendingPathComponent("library.json"),
              let data = try? Data(contentsOf: fileURL)
        else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PieceLibrary.self, from: data)
    }

    private static func message(for error: Error) -> String {
        switch error as? PieceLibraryError {
        case .missingPiece: "This piece is no longer available."
        case .nothingToApprove: "There is nothing new to approve."
        case .shotsIncomplete: "Mark every shot captured first."
        case nil: error.localizedDescription
        }
    }
}
