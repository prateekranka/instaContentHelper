import Foundation

struct MiraSharedBrief: Codable, Identifiable {
    let id: UUID
    let text: String
    let sharedAt: Date
}

enum MiraSharedBriefInbox {
    static func enqueue(_ text: String) throws {
        let inbox = try directory()
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let brief = MiraSharedBrief(id: UUID(), text: text, sharedAt: Date())
        try JSONEncoder().encode(brief).write(
            to: itemURL(brief.id, in: inbox), options: [.atomic, .completeFileProtection])
    }

    static func pending(matching text: String? = nil) throws -> [MiraSharedBrief] {
        let inbox = try directory()
        guard FileManager.default.fileExists(atPath: inbox.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(
            at: inbox, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        return try files.filter { $0.pathExtension == "json" }.map { url in
            try JSONDecoder().decode(MiraSharedBrief.self, from: Data(contentsOf: url))
        }.filter { text == nil || $0.text == text }.sorted {
            if $0.sharedAt == $1.sharedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.sharedAt < $1.sharedAt
        }
    }

    static func markImported(_ id: UUID) throws {
        let inbox = try directory()
        let file = itemURL(id, in: inbox)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let imported = inbox.appendingPathComponent("Imported", isDirectory: true)
        try FileManager.default.createDirectory(at: imported, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: file, to: itemURL(id, in: imported))
    }

    private static func itemURL(_ id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent(id.uuidString + ".json")
    }

    private static func directory() throws -> URL {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.prateekranka.creatorcontenthelper")
        else { throw CocoaError(.fileNoSuchFile) }
        return container.appendingPathComponent("Mira Shared Briefs", isDirectory: true)
    }
}
