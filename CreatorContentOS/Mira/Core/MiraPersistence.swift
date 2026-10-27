import Foundation

struct MiraDocument: Codable, Equatable, Sendable {
    var version = 2
    var profile = MiraProfile()
    var projects: [MiraProject] = []
    var position = MiraPosition()
    var navigation: MiraNavigation?
    var demoMode = false
    var sequence = 0
    var continuationProject: MiraProject? {
        let unfinished = projects.filter { !$0.archived && $0.stage != .complete }
        return unfinished.first { $0.id == position.projectID }
            ?? unfinished.max { $0.updatedAt < $1.updatedAt }
    }
    func restoredNavigation() -> MiraNavigation {
        func valid(_ route: MiraRoute) -> Bool {
            guard let project = projects.first(where: { $0.id == route.projectID }) else { return false }
            if case .shooting = route { return project.storyboard != nil }
            return true
        }
        if var navigation {
            navigation.today = navigation.today.filter(valid)
            navigation.projects = navigation.projects.filter(valid)
            return navigation
        }
        guard let id = position.projectID, let project = projects.first(where: { $0.id == id }) else {
            return MiraNavigation()
        }
        var path: [MiraRoute] = [.project(id)]
        if position.screen == "shooting", project.storyboard != nil { path.append(.shooting(id)) }
        return MiraNavigation(today: path)
    }
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
        if !manager.fileExists(atPath: file.path) {
            if manager.fileExists(atPath: backup.path) { try restoreBackup() }
            return MiraDocument()
        }
        do {
            let doc = try decode(Data(contentsOf: file))
            latestSequence = doc.sequence
            return doc
        } catch {
            if let error = error as? MiraError, error == .newerVersion { throw error }
            let quarantined = directory.appendingPathComponent("mira-corrupt-\(UUID().uuidString).json")
            try manager.copyItem(at: file, to: quarantined)
            try restoreBackup()
        }
    }
    private func restoreBackup() throws -> Never {
        let data: Data
        let document: MiraDocument
        do {
            data = try Data(contentsOf: backup)
            document = try decode(data)
        } catch {
            if let error = error as? MiraError, error == .newerVersion { throw error }
            throw MiraError.storage(
                "Saved work could not be read. It has been preserved for recovery. Mira will not replace it with an empty document."
            )
        }
        try data.write(to: file, options: .atomic)
        latestSequence = document.sequence
        throw MiraError.storage(
            "Recovered your last safe save. Try opening saved work again. Any damaged document is kept for recovery."
        )
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
