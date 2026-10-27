import Foundation
import Testing

@testable import MiraCore

struct MiraPriorityTests {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    private func project() throws -> MiraProject {
        var project = MiraProject()
        var input = MiraGenerationInput(
            operation: .ideas, profile: MiraProfile(), constraints: project.constraints,
            request: "A simple routine at home", recentIdeas: [])
        try project.apply(MiraFixtures.output(for: input), operation: .ideas)
        project.select(project.ideas[0])
        input.operation = .script
        input.idea = project.idea
        try project.apply(MiraFixtures.output(for: input), operation: .script)
        input.operation = .storyboard
        input.script = project.script
        project.job = MiraJob(inputRevision: project.inputRevision, input: input)
        try project.apply(MiraFixtures.output(for: input), operation: .storyboard)
        project.job = nil
        return project
    }

    @MainActor @Test func reopenRestoresIndependentTabsAndSelectedEditor() async throws {
        let repository = MiraFileRepository(directory: folder())
        var first = try project()
        first.lastScreen = .shooting
        first.shotIndex = 1
        var second = try project()
        second.lastScreen = .script
        var document = MiraDocument()
        document.sequence = 1
        document.projects = [first, second]
        document.navigation = MiraNavigation(
            tab: .projects, today: first.resumePath, projects: second.resumePath)
        try await repository.save(document)
        let store = MiraStore(repository: repository)
        await store.load()
        let navigation = store.document.restoredNavigation()
        #expect(navigation == document.navigation)
        store.rememberNavigation(navigation)
        #expect(store.project(second.id)?.editorScreen == .script)
        store.visit(second.id, screen: .shots)
        #expect(await store.flush())
        let reopened = try await repository.load()
        #expect(reopened.projects[1].editorScreen == .shots)
        #expect(reopened.position.screen == "shots")
        #expect(reopened.navigation?.today == first.resumePath)
        #expect(reopened.navigation?.tab == .projects)
    }

    @MainActor @Test func legacyNavigationAndDeletedProjectsRemainRecoverable() async throws {
        var project = try project()
        project.lastScreen = nil
        var document = MiraDocument()
        document.projects = [project]
        document.position = MiraPosition(projectID: project.id, screen: "shooting", shotIndex: 1)
        let legacy = try JSONDecoder().decode(MiraDocument.self, from: JSONEncoder().encode(document))
        #expect(legacy.restoredNavigation().today == [.project(project.id), .shooting(project.id)])
        #expect(legacy.projects[0].editorScreen == .shots)
        document.sequence = 1
        document.navigation = MiraNavigation(
            tab: .projects, today: [.project(UUID())], projects: [.project(project.id)])
        let repository = MiraFileRepository(directory: folder())
        try await repository.save(document)
        let store = MiraStore(repository: repository)
        await store.load()
        #expect(store.document.restoredNavigation().today.isEmpty)
        store.delete(project.id)
        #expect(await store.flush())
        let reopened = try await repository.load()
        #expect(reopened.projects.isEmpty)
        #expect(reopened.navigation?.projects.isEmpty == true)
        #expect(reopened.position.projectID == nil)
    }

    @MainActor @Test func missingPrimaryRecoversBackupWithAnExplicitNotice() async throws {
        let directory = folder()
        let repository = MiraFileRepository(directory: directory)
        var document = MiraDocument()
        document.sequence = 1
        document.projects = [try project()]
        try await repository.save(document)
        document.sequence = 2
        document.profile.name = "Newer save"
        try await repository.save(document)
        let backup = try Data(contentsOf: directory.appendingPathComponent("mira-backup.json"))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("mira-v2.json"))
        let store = MiraStore(repository: repository)
        await store.load()
        #expect(!store.loaded)
        #expect(store.loadFailed)
        #expect(store.error != nil)
        await store.load()
        #expect(store.loaded)
        #expect(!store.loadFailed)
        #expect(store.error == nil)
        let recovered = store.document
        #expect(recovered.projects.count == 1)
        #expect(recovered.profile.name.isEmpty)
        #expect(try Data(contentsOf: directory.appendingPathComponent("mira-backup.json")) == backup)
    }

    @Test func unreadableOrFutureBackupCannotBecomeAnEmptyLibrary() async throws {
        let directory = folder()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let backup = directory.appendingPathComponent("mira-backup.json")
        try Data("damaged backup".utf8).write(to: backup)
        do {
            _ = try await MiraFileRepository(directory: directory).load()
            Issue.record("A damaged backup must not be treated as a new library")
        } catch { #expect(error is MiraError) }
        #expect(
            !FileManager.default.fileExists(atPath: directory.appendingPathComponent("mira-v2.json").path)
        )
        var future = MiraDocument()
        future.version = 99
        let bytes = try JSONEncoder().encode(future)
        try bytes.write(to: backup)
        do {
            _ = try await MiraFileRepository(directory: directory).load()
            Issue.record("A future backup must not be downgraded")
        } catch { #expect(error as? MiraError == .newerVersion) }
        #expect(try Data(contentsOf: backup) == bytes)
    }

    @Test func repeatedShotContentCannotDuplicateIdentityOrFilmedCredit() throws {
        var project = try project()
        let original = project.storyboard!
        project.filmed = [original.shots[0].id]
        var replacement = original
        replacement.shots[1] = replacement.shots[0]
        replacement.shots[1].id = UUID()
        try project.apply(MiraOutput(storyboard: replacement), operation: .reviseStoryboard)
        let applied = project.storyboard!
        #expect(Set(applied.shots.map(\.id)).count == applied.shots.count)
        #expect(project.filmed == [original.shots[0].id])
        #expect(project.needsReview.contains(applied.shots[1].id))
    }

    @Test func swappedGeneratedIDsKeepMappingsWithTheirOriginalShots() throws {
        var project = try project()
        let original = project.storyboard!
        let requirement = MiraRequirement(kind: "visual", value: "plate", excerpt: "plate")
        var replacement = original
        replacement.shots[0].id = original.shots[1].id
        replacement.shots[1].id = original.shots[0].id
        replacement.mappings = [
            MiraRequirementMapping(
                requirementID: requirement.id, shotIDs: [replacement.shots[0].id], scriptExcerpt: "")
        ]
        try project.apply(MiraOutput(storyboard: replacement), operation: .reviseStoryboard)
        #expect(project.storyboard?.mappings[0].shotIDs == [original.shots[0].id])
    }

    @Test func undoRestoresPositionAndApprovalAfterAShorterShotList() throws {
        var project = try project()
        project.shotIndex = 2
        project.startedFilming = true
        project.approvedScriptID = project.activeScriptID
        var replacement = project.storyboard!
        replacement.shots.removeLast()
        for index in replacement.shots.indices {
            replacement.shots[index].editedSeconds = 15
            replacement.shots[index].recordingSeconds = 30
        }
        try project.apply(MiraOutput(storyboard: replacement), operation: .reviseStoryboard)
        #expect(project.shotIndex == 1)
        project.undoLastChange()
        #expect(project.shotIndex == 2)
        #expect(project.startedFilming)
        #expect(project.approvedScriptID == project.activeScriptID)
    }
}
