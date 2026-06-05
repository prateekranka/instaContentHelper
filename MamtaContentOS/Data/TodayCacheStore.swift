import Foundation

struct CachedTodaySnapshot: Codable, Hashable, Sendable {
    var todayCard: DailyCard
    var weekCards: [DailyCard]
    var cachedAt: Date
    var source: String
}

protocol TodayCacheStoring {
    func loadSnapshot(for context: WorkspaceContext) throws -> CachedTodaySnapshot?
    func saveSnapshot(_ snapshot: CachedTodaySnapshot, for context: WorkspaceContext) throws
    func clearSnapshot(for context: WorkspaceContext) throws
}

struct FileTodayCacheStore: TodayCacheStoring {
    private let baseDirectory: URL?

    init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory
    }

    func loadSnapshot(for context: WorkspaceContext) throws -> CachedTodaySnapshot? {
        let fileURL = try fileURL(for: context)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CachedTodaySnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: CachedTodaySnapshot, for context: WorkspaceContext) throws {
        let directoryURL = try directoryURL()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL(for: context), options: [.atomic])
    }

    func clearSnapshot(for context: WorkspaceContext) throws {
        let fileURL = try fileURL(for: context)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: fileURL)
    }

    private func fileURL(for context: WorkspaceContext) throws -> URL {
        let filename = "today-\(context.workspaceID.uuidString)-\(context.creatorID.uuidString).json"
        return try directoryURL().appendingPathComponent(filename, isDirectory: false)
    }

    private func directoryURL() throws -> URL {
        if let baseDirectory {
            return baseDirectory
        }

        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return root
            .appendingPathComponent("MamtaContentOS", isDirectory: true)
            .appendingPathComponent("TodayCache", isDirectory: true)
    }
}
