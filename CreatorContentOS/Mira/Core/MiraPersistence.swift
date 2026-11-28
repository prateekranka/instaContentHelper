import Foundation

struct MiraDocument: Codable, Equatable, Sendable {
    var version = 2
    var profile = MiraProfile()
    var projects: [MiraProject] = []
    var position = MiraPosition()
    var navigation: MiraNavigation?
    var defaultConstraints: MiraConstraints?
    var demoMode = false
    var sequence = 0
    var brandDoc: MiraBrandDocument?
    var instagramResultsPermission: MiraInstagramResultsPermission?
    var deals: [MiraDeal]?
    var dealBriefDraft: MiraDealBriefDraft?
    func restoredNavigation() -> MiraNavigation {
        func restored(_ path: [MiraRoute]) -> [MiraRoute] {
            var result: [MiraRoute] = []
            for route in path {
                guard let project = projects.first(where: { $0.id == route.projectID }) else { continue }
                var next = route
                switch route {
                case .todayCards:
                    if project.todayCards?.isEmpty != false { continue }
                case .shooting(let id), .done(let id):
                    if project.storyboard == nil { continue }
                    if !project.isApproved {
                        guard project.script != nil else { continue }
                        next = .words(id)
                    }
                case .project, .words: break
                }
                if result.last != next { result.append(next) }
            }
            return result
        }
        if var navigation {
            navigation.today = restored(navigation.today)
            navigation.projects = restored(navigation.projects)
            return navigation
        }
        guard let id = position.projectID, let project = projects.first(where: { $0.id == id }) else {
            return MiraNavigation()
        }
        var path: [MiraRoute] = [.project(id)]
        if position.screen == "shooting", project.storyboard != nil, project.isApproved {
            path.append(.shooting(id))
        }
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
    private let seedDamagedFixture: Bool

    init(directory: URL, seedDamagedFixture: Bool = false) {
        self.directory = directory
        self.seedDamagedFixture = seedDamagedFixture
    }
    private var file: URL { directory.appendingPathComponent("mira-v2.json") }
    private var backup: URL { directory.appendingPathComponent("mira-backup.json") }
    func load() throws -> MiraDocument {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
#if DEBUG
        if seedDamagedFixture, !manager.fileExists(atPath: file.path), !manager.fileExists(atPath: backup.path) {
            var document = MiraDocument()
            var project = MiraProject()
            project.title = "Recovered sample Reel"
            project.isDemo = true
            document.projects = [project]
            try JSONEncoder().encode(document).write(to: backup, options: .withoutOverwriting)
            try Data("Damaged fixture".utf8).write(to: file, options: .withoutOverwriting)
        }
#endif
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
            throw MiraLibraryOpenFailure.damaged
        }
        try data.write(to: file, options: .atomic)
        latestSequence = document.sequence
        throw MiraLibraryOpenFailure.restored
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
