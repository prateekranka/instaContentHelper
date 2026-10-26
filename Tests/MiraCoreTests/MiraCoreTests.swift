import Foundation
import Testing

@testable import MiraCore

struct MiraCoreTests {
    func input(_ operation: MiraOperation = .ideas) -> MiraGenerationInput {
        MiraGenerationInput(
            operation: operation, profile: MiraFixtures.mamta, constraints: MiraConstraints(),
            request: "15 minutes at home", recentIdeas: [], idea: nil, script: nil, storyboard: nil,
            brief: nil, targetShotID: nil)
    }
    @Test func constraintsAreCorrectableAndLanguageIsExplicit() throws {
        var constraints = MiraConstraints()
        constraints.populate(from: "Aaj 15 minutes hain. Ghar pe simple shoot, no tripod.")
        #expect(constraints.filmingMinutes == 15)
        #expect(constraints.location == "Home")
        #expect(constraints.reelSeconds == 30)
        var request = input(.script)
        request.profile.language = .english
        let output = MiraFixtures.output(for: request)
        #expect(output.script?.language == "English")
        try MiraValidation.validate(output, for: .script, input: request)
    }
    @Test func workflowPreservesRevisionsAndMarksChangedScriptStale() throws {
        var project = MiraProject()
        let ideas = MiraFixtures.output(for: input())
        try project.apply(ideas, operation: .ideas)
        project.select(project.ideas[0])
        var request = input(.script)
        try project.apply(MiraFixtures.output(for: request), operation: .script)
        request.operation = .storyboard
        request.script = project.script
        project.job = MiraJob(inputRevision: project.inputRevision, input: request)
        try project.apply(MiraFixtures.output(for: request), operation: .storyboard)
        #expect(project.stage == .ready)
        let old = project.script!.id
        var edited = project.script!
        edited.spoken = "Different words for today."
        project.editScript(edited)
        #expect(project.storyboardIsStale)
        #expect(project.scripts.contains { $0.id == old })
        #expect(project.stage == .planning)
        project.undoLastChange()
        #expect(project.activeScriptID == old)
        #expect(!project.storyboardIsStale)
    }
    @Test func unchangedShotsRetainFilmedStatusButChangedShotsNeedReview() throws {
        var project = MiraProject()
        project.ideas = MiraFixtures.output(for: input()).ideas!
        project.select(project.ideas[0])
        try project.apply(MiraFixtures.output(for: input(.script)), operation: .script)
        var request = input(.storyboard)
        request.script = project.script
        project.job = MiraJob(inputRevision: project.inputRevision, input: request)
        let first = MiraFixtures.output(for: request)
        try project.apply(first, operation: .storyboard)
        let original = project.storyboard!
        project.filmed = [original.shots[0].id, original.shots[1].id]
        var replacement = original
        replacement.id = UUID()
        replacement.shots[1].action = "A changed action"
        replacement.shots[1].id = UUID()
        try project.apply(MiraOutput(storyboard: replacement), operation: .reviseStoryboard)
        #expect(project.filmed == [original.shots[0].id])
        #expect(project.needsReview.contains(replacement.shots[1].id))
        #expect(project.storyboards.count == 2)
    }
    @Test func invalidDurationsAndInventedBriefExcerptAreRejected() throws {
        var request = input(.script)
        var output = MiraFixtures.output(for: request)
        output.script!.durationSeconds = 0
        #expect(throws: MiraError.self) { try MiraValidation.validate(output, for: .script, input: request) }
        request.operation = .requirements
        request.brief = MiraBrief(original: "Code: HELLO")
        let bad = MiraBrief(
            original: "Code: HELLO",
            requirements: [MiraRequirement(kind: "deadline", value: "Tomorrow", excerpt: "Tomorrow")])
        #expect(throws: MiraError.self) {
            try MiraValidation.validate(MiraOutput(brief: bad), for: .requirements, input: request)
        }
    }
    @Test func atomicSaveReopenAndSequenceRejectStaleWrites() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repository = MiraFileRepository(directory: folder)
        var document = MiraDocument()
        document.profile.name = "Saved"
        document.sequence = 2
        try await repository.save(document)
        var older = document
        older.sequence = 1
        older.profile.name = "Stale"
        try await repository.save(older)
        let reloaded = try await MiraFileRepository(directory: folder).load()
        #expect(reloaded.profile.name == "Saved")
    }
    @Test func corruptionDoesNotSilentlyEraseWork() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repository = MiraFileRepository(directory: folder)
        var document = MiraDocument()
        document.sequence = 1
        document.profile.name = "Backup"
        try await repository.save(document)
        document.sequence = 2
        document.profile.name = "Latest"
        try await repository.save(document)
        try Data("not-json".utf8).write(to: folder.appendingPathComponent("mira-v2.json"))
        do {
            _ = try await MiraFileRepository(directory: folder).load()
            Issue.record("Recovery must notify the caller")
        } catch {}
        let restored = try await MiraFileRepository(directory: folder).load()
        #expect(restored.profile.name == "Backup")
    }
    @Test func lateOrCancelledResponsesNeverOverwriteNewerWork() throws {
        var project = MiraProject()
        let request = input()
        let pending = MiraJob(inputRevision: project.inputRevision, input: request)
        project.job = pending
        var response = pending
        response.state = .succeeded
        response.output = MiraFixtures.output(for: request)
        project.request = "Newer manual input"
        project.touch()
        #expect(try !project.receive(response))
        #expect(project.job?.output != nil)
        #expect(project.ideas.isEmpty)
        project.job?.state = .cancelled
        #expect(try !project.receive(response))
        #expect(project.job?.state == .cancelled)
        var alien = response
        alien.id = UUID()
        #expect(try !project.receive(alien))
    }
    @Test func migrationAndFutureVersionsPreserveDocuments() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("mira-v2.json")
        var raw =
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(MiraDocument())) as! [String: Any]
        raw["version"] = 1
        raw.removeValue(forKey: "sequence")
        raw.removeValue(forKey: "demoMode")
        raw.removeValue(forKey: "position")
        try JSONSerialization.data(withJSONObject: raw).write(to: file)
        let migrated = try await MiraFileRepository(directory: folder).load()
        #expect(migrated.version == 2)
        raw["version"] = 99
        let future = try JSONSerialization.data(withJSONObject: raw)
        try future.write(to: file)
        do {
            _ = try await MiraFileRepository(directory: folder).load()
            Issue.record("Future versions must not be opened")
        } catch { #expect(error as? MiraError == .newerVersion) }
        #expect(try Data(contentsOf: file) == future)
    }
}
