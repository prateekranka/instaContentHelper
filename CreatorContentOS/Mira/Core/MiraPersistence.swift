import Foundation

struct MiraDocument: Codable, Equatable, Sendable {
    var version = 2
    var profile = MiraProfile()
    var projects: [MiraProject] = []
    var position = MiraPosition()
    var demoMode = false
    var sequence = 0
}
protocol MiraProjectRepository: Sendable {
    func load() async throws -> MiraDocument
    func save(_ document: MiraDocument) async throws
}
protocol MiraCreatorProfileRepository: Sendable {
    func loadProfile() async throws -> MiraProfile
    func saveProfile(_ profile: MiraProfile) async throws
}
actor MiraFileRepository: MiraProjectRepository, MiraCreatorProfileRepository {
    let directory: URL
    private var latestSequence = -1
    init(directory: URL) { self.directory = directory }
    private var file: URL { directory.appendingPathComponent("mira-v2.json") }
    private var backup: URL { directory.appendingPathComponent("mira-backup.json") }
    func load() throws -> MiraDocument {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        if !manager.fileExists(atPath: file.path) { return MiraDocument() }
        do {
            let doc = try decode(Data(contentsOf: file))
            latestSequence = doc.sequence
            return doc
        } catch {
            if let error = error as? MiraError, error == .newerVersion { throw error }
            let quarantined = directory.appendingPathComponent("mira-corrupt-\(UUID().uuidString).json")
            try manager.copyItem(at: file, to: quarantined)
            if let doc = try? decode(Data(contentsOf: backup)) {
                try Data(contentsOf: backup).write(to: file, options: .atomic)
                latestSequence = doc.sequence
                throw MiraError.storage(
                    "Recovered your last safe save. Reopen Mira to load it. The damaged document is kept for recovery."
                )
            }
            throw MiraError.storage(
                "Saved work could not be read. It has been preserved for recovery. Mira will not replace it with an empty document."
            )
        }
    }
    private func decode(_ data: Data) throws -> MiraDocument {
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let version = raw?["version"] as? Int ?? 1
        guard version <= 2 else { throw MiraError.newerVersion }
        var migrated = raw ?? [:]
        if version == 1 {
            migrated["version"] = 2
            migrated["sequence"] = migrated["sequence"] ?? 0
            migrated["demoMode"] = migrated["demoMode"] ?? false
            migrated["position"] = migrated["position"] ?? ["screen": "project", "shotIndex": 0]
        }
        return try JSONDecoder().decode(
            MiraDocument.self, from: JSONSerialization.data(withJSONObject: migrated))
    }
    func save(_ document: MiraDocument) throws {
        guard document.sequence > latestSequence else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        if FileManager.default.fileExists(atPath: file.path) {
            let old = try Data(contentsOf: file)
            let stored = try decode(old)
            if document.sequence <= stored.sequence {
                latestSequence = max(latestSequence, stored.sequence)
                return
            }
            try old.write(to: backup, options: .atomic)
        }
        try data.write(to: file, options: .atomic)
        latestSequence = document.sequence
    }
    func loadProfile() throws -> MiraProfile { try load().profile }
    func saveProfile(_ profile: MiraProfile) throws {
        var document = try load()
        document.profile = profile
        document.sequence += 1
        try save(document)
    }
}
