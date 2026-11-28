import Foundation

struct MiraInstagramResultsPermission: Codable, Equatable, Sendable {
    let creatorID: UUID
    let allowed: Bool
}

struct MiraInstagramSummary: Codable, Equatable, Sendable {
    let followers: Int
}

struct MiraBrandJobInput: Codable, Equatable, Sendable {
    let operation: MiraOperation
    let language: MiraLanguage
    let writingSystem: MiraWritingSystem
    let answers: String
    let instagramSummary: MiraInstagramSummary?
}

struct MiraDealChecklist: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        let id: UUID
        let kind: String
        let text: String
        let excerpt: String
        let requiredText: String?
    }

    let revision: Int
    let items: [Item]

    init?(_ brief: MiraBrief) {
        guard brief.confirmed, (1...40).contains(brief.requirements.count),
            Set(brief.requirements.map(\.id)).count == brief.requirements.count,
            brief.requirements.allSatisfy({
                MiraBrandDocument.validLine(MiraBrandDocument.trimmed($0.value))
                    && !MiraBrandDocument.trimmed($0.excerpt).isEmpty && $0.excerpt.utf16.count <= 1000
            })
        else { return nil }
        revision = brief.revision
        items = brief.requirements.map { requirement in
            let kind: String
            switch requirement.kind.lowercased() {
            case "caption": kind = "caption"
            case "onscreentext", "on-screen text", "on-screen": kind = "onScreenText"
            case "script", "spoken": kind = "script"
            case "shot", "visual": kind = "shot"
            default: kind = "other"
            }
            return Item(id: requirement.id, kind: kind, text: MiraBrandDocument.trimmed(requirement.value),
                        excerpt: requirement.excerpt, requiredText: nil)
        }
    }

    var validationBrief: MiraBrief {
        MiraBrief(requirements: items.map { .init(id: $0.id, kind: $0.kind, value: $0.text, excerpt: $0.excerpt) },
                  confirmed: true, revision: revision)
    }
}

extension MiraGenerationInput {
    static func interview(
        profile: MiraProfile, answers: MiraInterviewAnswers, instagram: MiraInstagramSummary?
    ) -> Self {
        .init(brandInput: MiraBrandJobInput(operation: .brandDoc, language: profile.language,
                                           writingSystem: profile.writingSystem, answers: answers.transcript,
                                           instagramSummary: instagram))
    }

    private init(brandInput: MiraBrandJobInput) {
        var profile = MiraProfile()
        profile.language = brandInput.language
        profile.writingSystem = brandInput.writingSystem
        self.init(operation: .brandDoc, profile: profile, constraints: MiraConstraints(), request: "", recentIdeas: [],
                  brandInput: brandInput)
    }

    private enum CodingKeys: String, CodingKey {
        case operation, profile, constraints, request, recentIdeas, idea, script, storyboard
        case brief, targetShotID, angle, brandDoc, bestPostPatterns, dealChecklist, avoid
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let operation = try values.decode(MiraOperation.self, forKey: .operation)
        if operation == .brandDoc {
            self.init(brandInput: try MiraBrandJobInput(from: decoder))
            return
        }
        try self.init(
            operation: operation, profile: values.decode(MiraProfile.self, forKey: .profile),
            constraints: values.decode(MiraConstraints.self, forKey: .constraints),
            request: values.decode(String.self, forKey: .request),
            recentIdeas: values.decode([String].self, forKey: .recentIdeas),
            idea: values.decodeIfPresent(MiraIdea.self, forKey: .idea),
            script: values.decodeIfPresent(MiraScript.self, forKey: .script),
            storyboard: values.decodeIfPresent(MiraStoryboard.self, forKey: .storyboard),
            brief: values.decodeIfPresent(MiraBrief.self, forKey: .brief),
            targetShotID: values.decodeIfPresent(UUID.self, forKey: .targetShotID),
            angle: values.decodeIfPresent(String.self, forKey: .angle),
            brandDoc: values.decodeIfPresent(MiraBrandDocument.self, forKey: .brandDoc),
            bestPostPatterns: values.decodeIfPresent([String].self, forKey: .bestPostPatterns),
            dealChecklist: values.decodeIfPresent(MiraDealChecklist.self, forKey: .dealChecklist),
            avoid: values.decodeIfPresent([String].self, forKey: .avoid))
    }

    func encode(to encoder: any Encoder) throws {
        if let brandInput {
            try brandInput.encode(to: encoder)
            return
        }
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(operation, forKey: .operation)
        try values.encode(profile, forKey: .profile)
        try values.encode(constraints, forKey: .constraints)
        try values.encode(request, forKey: .request)
        try values.encode(recentIdeas, forKey: .recentIdeas)
        try values.encodeIfPresent(angle, forKey: .angle)
        if operation == .pickIdea {
            try values.encodeIfPresent(brandDoc, forKey: .brandDoc)
            try values.encodeIfPresent(bestPostPatterns, forKey: .bestPostPatterns)
            try values.encodeIfPresent(dealChecklist, forKey: .dealChecklist)
            try values.encode(avoid ?? [], forKey: .avoid)
        } else {
            try values.encodeIfPresent(idea, forKey: .idea)
            try values.encodeIfPresent(script, forKey: .script)
            try values.encodeIfPresent(storyboard, forKey: .storyboard)
            try values.encodeIfPresent(brief, forKey: .brief)
            try values.encodeIfPresent(targetShotID, forKey: .targetShotID)
        }
    }
}
