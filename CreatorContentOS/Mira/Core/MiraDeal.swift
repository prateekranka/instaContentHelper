import Foundation

struct MiraDealChecklistItem: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case caption, onScreenText, script, shot, other }

    let id: UUID
    let kind: Kind
    let text: String
    let excerpt: String
    let requiredText: String?
}

struct MiraDealChecklist: Codable, Equatable, Sendable {
    let revision: Int
    let items: [MiraDealChecklistItem]

    var validationBrief: MiraBrief {
        let requirements = items.map {
            MiraRequirement(id: $0.id, kind: $0.kind.rawValue, value: $0.requiredText ?? $0.excerpt, excerpt: $0.excerpt)
        }
        return MiraBrief(requirements: requirements, confirmed: true, revision: revision)
    }
}

struct MiraDealTerms: Codable, Equatable, Sendable {
    let brand: String
    let fee: String
    let deadline: String
    let deadlineExcerpt: String
    let checklist: [MiraDealChecklistItem]
    let disclosures: [String]
    let codes: [String]
    let unresolved: [String]

    var title: String { brand.isEmpty ? "Brand to check" : brand }

    func matchesSource(_ source: String) -> Bool {
        let quotes = [brand, fee, deadlineExcerpt].filter { !$0.isEmpty } + disclosures + codes + checklist.map(\.excerpt)
        return quotes.allSatisfy { !$0.isEmpty && source.range(of: $0, options: .literal) != nil }
            && Set(checklist.map(\.id)).count == checklist.count && checklist.count <= 40
            && checklist.allSatisfy { item in
                guard let required = item.requiredText else { return true }
                return !required.isEmpty && item.excerpt.range(of: required, options: .literal) != nil
            }
            && (deadline.isEmpty ? !unresolved.isEmpty : !deadlineExcerpt.isEmpty)
    }
}

struct MiraDeal: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let source: String
    let terms: MiraDealTerms
    let confirmedAt: Date
    var tracker = MiraDealTrackerDates()

    var checklist: MiraDealChecklist? {
        terms.checklist.isEmpty ? nil : MiraDealChecklist(revision: 1, items: terms.checklist)
    }
}

struct MiraDealBriefInput: Codable, Equatable, Sendable {
    let operation: String
    let language: MiraLanguage
    let writingSystem: MiraWritingSystem
    let briefText: String

    init(text: String, profile: MiraProfile) {
        operation = "dealBrief"
        language = profile.language
        writingSystem = profile.writingSystem
        briefText = text
    }

    static func canRead(_ text: String) -> Bool {
        text.utf16.count <= 12_000 && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct MiraDealBriefJob: Codable, Equatable, Sendable {
    let id: UUID
    let input: MiraDealBriefInput
    let creatorID: UUID?
    static let revision = 1
}

struct MiraDealBriefReply: Decodable, Sendable {
    struct Output: Decodable, Sendable { let deal: MiraDealTerms }

    let id: UUID
    let inputRevision: Int
    let input: MiraDealBriefInput
    let state: MiraGenerationState
    var output: Output?
    var error: String?

    func matches(_ job: MiraDealBriefJob) -> Bool {
        id == job.id && inputRevision == MiraDealBriefJob.revision && input == job.input
    }
}

struct MiraDealBriefDraft: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var text: String
    var job: MiraDealBriefJob?
    var terms: MiraDealTerms?
    var issue: String?
}
