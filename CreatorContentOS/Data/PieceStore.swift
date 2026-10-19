import Foundation
import Observation

@MainActor
@Observable
final class PieceStore {
    private(set) var library: PieceLibrary
    var lastError: String?

    @ObservationIgnored private let directoryURL: URL?
    @ObservationIgnored private let now: () -> Date

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
        library = next
        lastError = nil
        save()
        return true
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

    func mediaURL(for fileName: String) -> URL? {
        mediaDirectoryURL?.appendingPathComponent(fileName, isDirectory: false)
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
