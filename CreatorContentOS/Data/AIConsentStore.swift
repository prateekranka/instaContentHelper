import Foundation

enum AIConsentDecision: String, Codable, Equatable, Sendable {
    case accepted
    case declined
}

struct AIConsentRecord: Codable, Equatable, Sendable {
    var consentVersion: String
    var decision: AIConsentDecision
    var decidedAt: String
    var destinationsAcknowledged: [String]
}

enum AIConsentPolicy {
    static let currentVersion = "contenthelper-ai-consent-v1"
    static let destinations = ["deepseek", "openai", "gemini"]

    static func allowsOutbound(
        _ record: AIConsentRecord?,
        currentVersion: String = currentVersion
    ) -> Bool {
        guard let record else { return false }
        return record.consentVersion == currentVersion && record.decision == .accepted
    }

    static func hasDeclinedCurrent(
        _ record: AIConsentRecord?,
        currentVersion: String = currentVersion
    ) -> Bool {
        guard let record else { return false }
        return record.consentVersion == currentVersion && record.decision == .declined
    }
}

protocol AIConsentStoring: Sendable {
    func load() -> AIConsentRecord?
    func save(_ record: AIConsentRecord)
    func clear()
}

struct UserDefaultsAIConsentStore: AIConsentStoring, @unchecked Sendable {
    let workspaceID: UUID
    let creatorID: UUID
    private let defaults: UserDefaults

    init(
        workspaceID: UUID,
        creatorID: UUID,
        defaults: UserDefaults = .standard
    ) {
        self.workspaceID = workspaceID
        self.creatorID = creatorID
        self.defaults = defaults
    }

    private var key: String {
        "ch-ai-consent.\(workspaceID.uuidString).\(creatorID.uuidString)"
    }

    func load() -> AIConsentRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AIConsentRecord.self, from: data)
    }

    func save(_ record: AIConsentRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

final class InMemoryAIConsentStore: AIConsentStoring, @unchecked Sendable {
    private var record: AIConsentRecord?

    init(record: AIConsentRecord? = nil) {
        self.record = record
    }

    func load() -> AIConsentRecord? {
        record
    }

    func save(_ record: AIConsentRecord) {
        self.record = record
    }

    func clear() {
        record = nil
    }
}
