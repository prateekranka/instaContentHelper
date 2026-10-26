import Foundation

enum MiraLanguage: String, Codable, CaseIterable, Sendable {
    case english = "English"
    case hindi = "Hindi"
    case hinglish = "Hinglish"
}
enum MiraWritingSystem: String, Codable, CaseIterable, Sendable {
    case devanagari = "Devanagari"
    case romanised = "Romanised"
}
enum MiraStyle: String, Codable, CaseIterable, Sendable {
    case talking = "Talking to camera"
    case voiceover = "Voiceover"
    case either = "Either"
}
struct MiraProfile: Codable, Equatable, Sendable {
    var name = ""
    var themes = ""
    var audience = ""
    var language: MiraLanguage = .english
    var writingSystem: MiraWritingSystem = .romanised
    var tone = "Conversational, everyday"
    var avoid = ""
    var samples = ""
    var solo = true
}
struct MiraConstraints: Codable, Equatable, Sendable {
    var filmingMinutes = 20
    var location = "Home"
    var style: MiraStyle = .either
    var reelSeconds = 30
    var equipment = "Phone; no tripod assumed"
    mutating func populate(from text: String) {
        let lower = text.lowercased()
        if let match = lower.range(of: #"\b\d{1,3}\s*(minutes?|mins?|मिनट)"#, options: .regularExpression),
            let number = Int(lower[match].prefix(while: { $0.isNumber })), (1...180).contains(number)
        {
            filmingMinutes = number
        }
        if lower.contains("ghar") || lower.contains("home") || lower.contains("घर") { location = "Home" }
        if lower.contains("kitchen") || lower.contains("रसोई") { location = "Kitchen at home" }
        if lower.contains("gym") && !lower.contains("cannot") && !lower.contains("can't") { location = "Gym" }
        if lower.contains("no tripod") || lower.contains("tripod nahi") {
            equipment = "Phone on a stable shelf or table; no tripod"
        }
    }
}
struct MiraIdea: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var hook: String
    var visual: String
    var fit: String
    var filmingMinutes: Int
    var setup: String
}
struct MiraScript: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var hook: String
    var spoken: String
    var caption: String
    var durationSeconds: Int
    var language: String
}
struct MiraShot: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var purpose: String
    var editedSeconds: Int
    var recordingSeconds: Int
    var location: String
    var props: String
    var placement: String
    var action: String
    var words: String
    var voiceover: Bool
    var onScreenText: String
    var simplerAlternative: String
    func sameContent(as other: MiraShot) -> Bool {
        var copy = self
        copy.id = other.id
        return copy == other
    }
}
struct MiraRequirement: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var kind: String
    var value: String
    var excerpt: String
}
struct MiraBrief: Codable, Equatable, Sendable {
    var original = ""
    var requirements: [MiraRequirement] = []
    var unresolved: [String] = []
    var confirmed = false
    var revision = 0
}
struct MiraRequirementMapping: Codable, Equatable, Sendable {
    var requirementID: UUID
    var shotIDs: [UUID]
    var scriptExcerpt: String
}
struct MiraStoryboard: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var sourceScriptID: UUID
    var requirementsRevision: Int
    var shots: [MiraShot]
    var mappings: [MiraRequirementMapping]
}
enum MiraStage: String, Codable, Sendable {
    case choosing = "Choosing an idea"
    case writing = "Writing the script"
    case planning = "Planning shots"
    case ready = "Ready to film"
    case filming = "Filming"
    case complete = "Filming complete"
}
enum MiraOperation: String, Codable, Sendable {
    case ideas, script, storyboard, reviseScript, reviseShot, reviseStoryboard, requirements
}
enum MiraGenerationState: String, Codable, Sendable { case idle, working, failed, cancelled, succeeded }
struct MiraGenerationInput: Codable, Equatable, Sendable {
    var operation: MiraOperation
    var profile: MiraProfile
    var constraints: MiraConstraints
    var request: String
    var recentIdeas: [String]
    var idea: MiraIdea?
    var script: MiraScript?
    var storyboard: MiraStoryboard?
    var brief: MiraBrief?
    var targetShotID: UUID?
}
struct MiraOutput: Codable, Equatable, Sendable {
    var ideas: [MiraIdea]?
    var script: MiraScript?
    var storyboard: MiraStoryboard?
    var brief: MiraBrief?
    var conflicts: [String] = []
}
struct MiraJob: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var inputRevision: Int
    var input: MiraGenerationInput
    var state: MiraGenerationState = .working
    var output: MiraOutput?
    var error: String?
}
struct MiraPosition: Codable, Equatable, Sendable {
    var projectID: UUID?
    var screen = "project"
    var shotIndex = 0
}
struct MiraUndo: Codable, Equatable, Sendable {
    var scriptID: UUID?
    var storyboardID: UUID?
    var brief: MiraBrief
    var filmed: [UUID]
    var review: [UUID]
}
struct MiraProject: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var title = "Untitled Reel"
    var createdAt = Date()
    var updatedAt = Date()
    var archived = false
    var request = ""
    var constraints = MiraConstraints()
    var ideas: [MiraIdea] = []
    var selectedIdeaID: UUID?
    var scripts: [MiraScript] = []
    var activeScriptID: UUID?
    var approvedScriptID: UUID?
    var storyboards: [MiraStoryboard] = []
    var activeStoryboardID: UUID?
    var brief = MiraBrief()
    var filmed: [UUID] = []
    var needsReview: [UUID] = []
    var shotIndex = 0
    var startedFilming = false
    var inputRevision = 0
    var job: MiraJob?
    var undo: [MiraUndo] = []
    var isDemo = false
    var script: MiraScript? { scripts.first { $0.id == activeScriptID } }
    var storyboard: MiraStoryboard? { storyboards.first { $0.id == activeStoryboardID } }
    var idea: MiraIdea? { ideas.first { $0.id == selectedIdeaID } }
    var effectiveBriefRevision: Int { brief.confirmed ? brief.revision : 0 }
    var storyboardIsStale: Bool {
        guard let board = storyboard else { return false }
        return board.sourceScriptID != activeScriptID || board.requirementsRevision != effectiveBriefRevision
    }
    var stage: MiraStage {
        guard selectedIdeaID != nil else { return .choosing }
        guard script != nil else { return .writing }
        guard let board = storyboard, !storyboardIsStale else { return .planning }
        if !board.shots.isEmpty
            && board.shots.allSatisfy({ filmed.contains($0.id) && !needsReview.contains($0.id) })
        {
            return .complete
        }
        return startedFilming ? .filming : .ready
    }
    var nextAction: String {
        switch stage {
        case .choosing: "Choose an idea"
        case .writing: "Write your script"
        case .planning: storyboard == nil ? "Make your shot list" : "Update shot list"
        case .ready: "Start filming"
        case .filming: "Continue filming"
        case .complete: "Review your filming plan"
        }
    }
    mutating func touch() {
        updatedAt = Date()
        inputRevision += 1
    }
    mutating func receive(_ result: MiraJob) throws -> Bool {
        guard let pending = job, pending.id == result.id, pending.state != .cancelled else { return false }
        guard result.inputRevision == pending.inputRevision, result.input == pending.input else {
            throw MiraError.invalid("Generation result does not match the saved request.")
        }
        if result.state == .succeeded && result.output == nil {
            throw MiraError.invalid("Generation finished without an artifact. Your saved work is unchanged.")
        }
        if let output = result.output {
            try MiraValidation.validate(output, for: pending.input.operation, input: pending.input)
        }
        job = result
        return result.state == .succeeded && result.inputRevision == inputRevision
    }
    mutating func select(_ idea: MiraIdea) {
        if selectedIdeaID != idea.id {
            activeScriptID = nil
            approvedScriptID = nil
            activeStoryboardID = nil
            startedFilming = false
        }
        selectedIdeaID = idea.id
        title = idea.title
        touch()
    }
    mutating func editScript(_ value: MiraScript) {
        guard value != script else { return }
        checkpoint()
        var revised = value
        revised.id = UUID()
        scripts.append(revised)
        activeScriptID = revised.id
        approvedScriptID = nil
        touch()
    }
    mutating func checkpoint() {
        undo.append(
            MiraUndo(
                scriptID: activeScriptID, storyboardID: activeStoryboardID, brief: brief, filmed: filmed,
                review: needsReview))
        if undo.count > 30 { undo.removeFirst() }
    }
    mutating func undoLastChange() {
        guard let old = undo.popLast() else { return }
        activeScriptID = old.scriptID
        activeStoryboardID = old.storyboardID
        brief = old.brief
        filmed = old.filmed
        needsReview = old.review
        approvedScriptID = nil
        touch()
    }
    mutating func apply(_ output: MiraOutput, operation: MiraOperation) throws {
        try MiraValidation.validate(output, for: operation, input: job?.input)
        guard output.conflicts.isEmpty else {
            throw MiraError.invalid("Resolve the proposed conflicts before applying this plan.")
        }
        if let board = output.storyboard {
            guard let current = script, board.sourceScriptID == current.id,
                board.requirementsRevision == effectiveBriefRevision
            else {
                throw MiraError.invalid(
                    "Shot list belongs to an older script or brief. Generate an updated proposal.")
            }
        }
        checkpoint()
        if let options = output.ideas {
            for var idea in options {
                if ideas.contains(where: { $0.id == idea.id }) { idea.id = UUID() }
                ideas.append(idea)
            }
        }
        if var script = output.script {
            script.id = UUID()
            scripts.append(script)
            activeScriptID = script.id
            approvedScriptID = nil
        }
        if var board = output.storyboard {
            guard let current = script, board.sourceScriptID == current.id,
                board.requirementsRevision == effectiveBriefRevision
            else {
                throw MiraError.invalid(
                    "Shot list belongs to an older script or brief. Generate an updated proposal.")
            }
            let old = storyboard
            var preserved: [UUID] = []
            var review: [UUID] = []
            for index in board.shots.indices {
                let shot = board.shots[index]
                if let unchanged = old?.shots.first(where: { $0.sameContent(as: shot) }) {
                    let generatedID = board.shots[index].id
                    board.shots[index].id = unchanged.id
                    for m in board.mappings.indices {
                        board.mappings[m].shotIDs = board.mappings[m].shotIDs.map {
                            $0 == generatedID ? unchanged.id : $0
                        }
                    }
                    if filmed.contains(unchanged.id) { preserved.append(unchanged.id) }
                    if needsReview.contains(unchanged.id) { review.append(unchanged.id) }
                } else if old != nil {
                    review.append(shot.id)
                }
            }
            board.id = UUID()
            storyboards.append(board)
            activeStoryboardID = board.id
            filmed = preserved
            needsReview = review
            shotIndex = min(shotIndex, max(0, board.shots.count - 1))
        }
        if var brief = output.brief {
            brief.confirmed = false
            brief.revision = self.brief.revision + 1
            self.brief = brief
        }
        touch()
    }
}
enum MiraError: Error, LocalizedError, Equatable {
    case invalid(String)
    case storage(String)
    case offline, newerVersion
    var errorDescription: String? {
        switch self {
        case .invalid(let text), .storage(let text): text
        case .offline: "New generation needs a connection. Your saved work is still available."
        case .newerVersion: "This library was saved by a newer Mira version. It has not been changed."
        }
    }
}
