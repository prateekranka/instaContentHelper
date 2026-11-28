import Foundation

struct MiraClip: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let fileExtension: String
    let sourceID: String?
    let name: String
    let seconds: Double
    let createdAt: Date?
    let bytes: Int64

    var filename: String { "\(id.uuidString).\(fileExtension)" }
}

struct MiraClipPlan: Codable, Equatable, Sendable {
    var assignments: [UUID: UUID] = [:]
    var extraText: String?
    var export: MiraReelExport?
}

struct MiraRenderRecipe: Codable, Equatable, Sendable {
    struct Cut: Codable, Equatable, Sendable {
        let clip: MiraClip
        let seconds: Int
        let text: String
    }

    let cuts: [Cut]
    let hook: String
    let extraText: String

    var visibleText: String {
        ([hook] + cuts.map(\.text) + [extraText]).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

struct MiraReelExport: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let recipe: MiraRenderRecipe
    let bytes: Int64
    var filename: String { "\(id.uuidString).mp4" }
}

struct MiraDelivery: Codable, Equatable, Sendable {
    var clips: [MiraClip] = []
    var plans: [UUID: MiraClipPlan] = [:]
    var briefReview: MiraDeliveryReview?
    var caption: String?
    var post: MiraPostedReel?
    var sharedAt: Date?
    var sharedExportID: UUID?
    var brandNote: MiraBrandMessage?
}

struct MiraBriefCheckInput: Codable, Equatable, Sendable {
    let operation: String
    let language: MiraLanguage
    let writingSystem: MiraWritingSystem
    let checklist: [MiraDealChecklistItem]
    let caption: String
    let onScreenText: String
    let script: String
    let shots: [String]

    init(profile: MiraProfile, checklist: [MiraDealChecklistItem], caption: String, recipe: MiraRenderRecipe,
         script: String, shots: [MiraShot]) {
        operation = "briefCheck"
        language = profile.language
        writingSystem = profile.writingSystem
        self.checklist = checklist
        self.caption = Self.limit(caption, 4400)
        onScreenText = Self.limit(recipe.visibleText, 6000)
        self.script = Self.limit(script, 6000)
        self.shots = shots.prefix(24).enumerated().map { index, shot in
            Self.line("Shot \(index + 1) plan: \(shot.action)")
        }
    }

    static func limit(_ text: String, _ length: Int) -> String {
        String(decoding: text.utf16.prefix(length), as: UTF16.self)
    }

    static func line(_ text: String) -> String {
        limit(text.split(whereSeparator: \.isNewline).joined(separator: " "), 240)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MiraBriefCheck: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        case met, missing, canFix = "can-fix"

        var title: String {
            switch self {
            case .met: "Met"
            case .missing: "Missing"
            case .canFix: "Can fix"
            }
        }
    }

    struct TextValue: Codable, Equatable, Sendable {
        let field: MiraDealChecklistItem.Kind
        let excerpt: String?
        let text: String?
    }

    let itemID: UUID
    let status: Status
    var evidence: TextValue?
    var fix: TextValue?
    var id: UUID { itemID }

    func validated(for item: MiraDealChecklistItem, input: MiraBriefCheckInput) -> Self {
        let missing = Self(itemID: itemID, status: .missing)
        switch status {
        case .met:
            guard let excerpt = evidence?.excerpt, let required = item.requiredText,
                evidence?.field == item.kind, excerpt.contains(required) else { return missing }
            let field: String
            switch item.kind {
            case .caption: field = input.caption
            case .onScreenText: field = input.onScreenText
            case .script: field = input.script
            case .shot, .other: return missing
            }
            return field.contains(excerpt) ? self : missing
        case .canFix:
            guard let text = fix?.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                text.utf16.count <= 1000, fix?.field == item.kind,
                item.kind == .caption || item.kind == .onScreenText,
                item.requiredText.map({ text.contains($0) }) ?? true else { return missing }
            return self
        case .missing:
            return missing
        }
    }
}

struct MiraDeliveryJob<Input: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    var id = UUID()
    let creatorID: UUID?
    let input: Input
    var revision: Int { 1 }
}

struct MiraDeliveryReply<Input: Codable & Equatable & Sendable, Output: Decodable & Sendable>: Decodable, Sendable {
    let id: UUID
    let inputRevision: Int
    let input: Input
    let state: MiraGenerationState
    let output: Output?

    func matches(_ job: MiraDeliveryJob<Input>) -> Bool {
        id == job.id && inputRevision == job.revision && input == job.input
    }
}

struct MiraBriefCheckOutput: Decodable, Sendable {
    let checks: [MiraBriefCheck]
}

struct MiraDeliveryReview: Codable, Equatable, Sendable {
    let dealID: UUID
    let job: MiraDeliveryJob<MiraBriefCheckInput>
    var checks: [MiraBriefCheck]?
    var issue: String?
}

struct MiraPostedReel: Codable, Equatable, Sendable {
    let date: Date
    let dealID: UUID?
    let exportID: UUID
    let link: URL?
}

struct MiraBrandNoteInput: Codable, Equatable, Sendable {
    let operation: String
    let language: MiraLanguage
    let writingSystem: MiraWritingSystem
    let brand: String
    let itemsDone: [String]
    let postLink: URL?

    init(profile: MiraProfile, deal: MiraDeal, post: MiraPostedReel, review: MiraDeliveryReview?) {
        operation = "brandNote"
        language = profile.language
        writingSystem = profile.writingSystem
        brand = MiraBriefCheckInput.line(deal.terms.title)
        let met = Set((review?.checks ?? []).filter { $0.status == .met }.map(\.itemID))
        let completed = deal.terms.checklist.filter {
            met.contains($0.id) && ($0.kind == .caption || $0.kind == .onScreenText)
        }.map { MiraBriefCheckInput.line($0.text) }.filter { !$0.isEmpty }
        itemsDone = ["Published the Reel"] + Array(completed.prefix(39))
        postLink = post.link
    }
}

struct MiraBrandNoteOutput: Decodable, Sendable {
    let message: String
}

struct MiraBrandMessage: Codable, Equatable, Sendable {
    let dealID: UUID
    let job: MiraDeliveryJob<MiraBrandNoteInput>
    var message: String?
    var issue: String?
    var handoffAt: Date?
    var sentAt: Date?
}

extension MiraProject {
    func deliveryDeal(in deals: [MiraDeal]) -> MiraDeal? {
        if let id = dealID ?? delivery?.post?.dealID { return deals.first { $0.id == id } }
        guard brief.confirmed, !brief.requirements.isEmpty else { return nil }
        let ids = Set(brief.requirements.map(\.id))
        let matching = deals.filter { $0.source == brief.original && Set($0.terms.checklist.map(\.id)) == ids }
        return matching.count == 1 ? matching.first : nil
    }

    var deliveryRecord: MiraDelivery { delivery ?? MiraDelivery() }
    var deliveryCaption: String { delivery?.caption ?? script?.caption ?? "" }

    func deliveryRecipe(extraText: String? = nil) -> MiraRenderRecipe? {
        guard canFilm, let board = storyboard, let plan = delivery?.plans[board.id],
            !board.shots.isEmpty else { return nil }
        let cuts = board.shots.compactMap { shot -> MiraRenderRecipe.Cut? in
            guard let id = plan.assignments[shot.id], let clip = delivery?.clips.first(where: { $0.id == id }),
                shot.editedSeconds > 0, clip.seconds + 0.05 >= Double(shot.editedSeconds) else { return nil }
            return .init(clip: clip, seconds: shot.editedSeconds, text: shot.onScreenText)
        }
        guard cuts.count == board.shots.count else { return nil }
        return MiraRenderRecipe(cuts: cuts, hook: script?.hook ?? "",
            extraText: extraText ?? plan.extraText ?? "")
    }

    func deliveryNextAction(deal: MiraDeal?) -> MiraNextAction? {
        if let post = delivery?.post {
            guard let dealID = post.dealID, deal?.tracker.brandToldAt == nil, delivery?.brandNote?.sentAt == nil,
                deal?.id == dealID else { return nil }
            return MiraTellBrandState(note: delivery?.brandNote, running: false).nextAction
        }
        if let export = currentReelExport {
            if delivery?.sharedExportID == export.id { return .confirmReelPost }
            if let deal, !deal.terms.checklist.isEmpty, delivery?.briefReview?.dealID != deal.id
                || delivery?.briefReview?.checks == nil {
                return .checkReelBrief
            }
            return .shareReel
        }
        if deliveryRecipe() != nil { return .joinReel }
        return stage == .complete || delivery != nil ? .prepareClips : nil
    }

    var currentReelExport: MiraReelExport? {
        guard let board = storyboard, let export = delivery?.plans[board.id]?.export,
            export.recipe == deliveryRecipe() else { return nil }
        return export
    }
}
