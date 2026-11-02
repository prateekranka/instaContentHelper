import Foundation
import Observation

protocol MiraGenerationService: Sendable {
    func start(_ job: MiraJob) async throws -> MiraJob
    func status(_ job: MiraJob) async throws -> MiraJob
    func cancel(_ job: MiraJob) async throws -> MiraJob
}

@MainActor @Observable
final class MiraStore {
    var document = MiraDocument()
    var loaded = false
    var loadFailed = false
    var error: String?
    var saveMessage: String?
    private let repository: any MiraProjectRepository
    private var saveTask: Task<Void, Never>?
    private var generationTasks: [UUID: Task<Void, Never>] = [:]
    private var editingDrafts: [UUID: UUID] = [:]
    init(repository: any MiraProjectRepository) { self.repository = repository }
    func load() async {
        guard !loaded else { return }
        do {
            document = try await repository.load()
            loaded = true
            loadFailed = false
            error = nil
        } catch {
            self.error = error.localizedDescription
            loadFailed = true
        }
    }
    func project(_ id: UUID) -> MiraProject? { document.projects.first { $0.id == id } }
    func hasActiveRequest(_ id: UUID) -> Bool { generationTasks[id] != nil }
    func update(_ id: UUID, immediate: Bool = true, _ change: (inout MiraProject) -> Void) {
        guard loaded, let index = document.projects.firstIndex(where: { $0.id == id }) else { return }
        change(&document.projects[index])
        if document.position.projectID == id {
            document.position.screen = document.projects[index].lastScreen?.rawValue ?? "project"
            document.position.shotIndex = document.projects[index].shotIndex
        }
        save(immediate: immediate)
    }
    func rememberNavigation(_ navigation: MiraNavigation) {
        document.navigation = navigation
        if let route = navigation.activePath.last, let project = project(route.projectID) {
            let screen: MiraProjectScreen
            if case .shooting = route { screen = .shooting } else { screen = project.editorScreen }
            visit(project.id, screen: screen)
        } else {
            save()
        }
    }
    func visit(_ id: UUID, screen: MiraProjectScreen) {
        guard let index = document.projects.firstIndex(where: { $0.id == id }) else { return }
        document.projects[index].lastScreen = screen
        document.position = MiraPosition(
            projectID: id, screen: screen.rawValue, shotIndex: document.projects[index].shotIndex)
        save()
    }
    func moveShot(_ id: UUID, to index: Int) {
        guard let project = project(id), let board = project.storyboard else { return }
        update(id) {
            $0.shotIndex = min(max(0, index), max(0, board.shots.count - 1))
            $0.lastScreen = .shooting
        }
    }
    func startFilming(_ id: UUID) {
        guard let project = project(id), project.storyboard != nil, !project.storyboardIsStale else {
            return
        }
        update(id) { $0.startedFilming = true }
        visit(id, screen: .shooting)
    }
    func toggleFilmed(_ id: UUID, shotID: UUID) {
        guard let project = project(id), !project.storyboardIsStale,
            project.storyboard?.shots.contains(where: { $0.id == shotID }) == true
        else { return }
        update(id) {
            if $0.filmed.contains(shotID) {
                $0.filmed.removeAll { $0 == shotID }
            } else {
                $0.filmed.append(shotID)
                $0.needsReview.removeAll { $0 == shotID }
            }
            $0.updatedAt = Date()
        }
    }
    func approveScript(_ id: UUID) {
        guard project(id)?.script != nil else { return }
        update(id) {
            $0.approvedScriptID = $0.activeScriptID
            $0.touch()
        }
    }
    func rename(_ id: UUID, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        update(id) {
            $0.title = title
            $0.updatedAt = Date()
        }
    }
    func toggleArchive(_ id: UUID) {
        update(id) {
            $0.archived.toggle()
            $0.updatedAt = Date()
        }
    }
    func chooseIdea(_ id: UUID, ideaID: UUID) {
        guard let idea = project(id)?.ideas.first(where: { $0.id == ideaID }) else { return }
        update(id) { $0.select(idea) }
    }
    func chooseAnotherIdea(_ id: UUID) {
        update(id) {
            $0.selectedIdeaID = nil
            $0.lastScreen = .ideas
            $0.touch()
        }
    }
    func writeScriptManually(_ id: UUID) {
        guard let project = project(id), project.idea != nil, project.script == nil else { return }
        let language = project.isDemo ? MiraFixtures.mamta.language : document.profile.language
        update(id) {
            let script = MiraScript(
                hook: $0.idea?.hook ?? "", spoken: "", caption: "",
                durationSeconds: $0.constraints.reelSeconds, language: language.rawValue)
            $0.scripts.append(script)
            $0.activeScriptID = script.id
            $0.lastScreen = .script
            $0.touch()
        }
    }
    func restoreScript(_ id: UUID, revisionID: UUID) {
        guard project(id)?.scripts.contains(where: { $0.id == revisionID }) == true else { return }
        update(id) {
            $0.checkpoint()
            $0.activeScriptID = revisionID
            $0.approvedScriptID = nil
            $0.lastScreen = .script
            $0.touch()
        }
    }
    func save(immediate: Bool = true) {
        guard loaded, !loadFailed else { return }
        document.sequence += 1
        let snapshot = document
        saveTask?.cancel()
        saveTask = Task {
            if !immediate { do { try await Task.sleep(for: .milliseconds(450)) } catch { return } }
            do {
                try await repository.save(snapshot)
                saveMessage = nil
            } catch {
                saveMessage = "Changes are in memory but could not be saved. \(error.localizedDescription)"
            }
        }
    }
    @discardableResult func flush() async -> Bool {
        guard loaded, !loadFailed else { return false }
        saveTask?.cancel()
        document.sequence += 1
        do {
            try await repository.save(document)
            saveMessage = nil
            return true
        } catch {
            saveMessage = error.localizedDescription
            return false
        }
    }
    func newProject() -> UUID {
        let project = MiraProject()
        document.projects.insert(project, at: 0)
        document.position = MiraPosition(projectID: project.id)
        save()
        return project.id
    }
    func addDemo() -> UUID {
        var project = MiraProject()
        project.isDemo = true
        project.title = "Mamta — demo Reel"
        project.request = "Aaj 15 minutes hain. Ghar pe kuch simple shoot karna hai."
        project.constraints.filmingMinutes = 15
        document.projects.insert(project, at: 0)
        document.position = MiraPosition(projectID: project.id)
        save()
        return project.id
    }
    func delete(_ id: UUID) {
        generationTasks[id]?.cancel()
        generationTasks[id] = nil
        document.projects.removeAll { $0.id == id }
        if document.position.projectID == id { document.position = MiraPosition() }
        if var navigation = document.navigation {
            navigation.today.removeAll { $0.projectID == id }
            navigation.projects.removeAll { $0.projectID == id }
            document.navigation = navigation
        }
        save()
    }
    func remember(_ preference: String) {
        document.profile.tone = preference
        save()
    }
    func editScript<T: Equatable>(_ id: UUID, field: WritableKeyPath<MiraScript, T>, value: T) {
        guard var project = project(id), var script = project.script, script[keyPath: field] != value
        else {
            return
        }
        if editingDrafts[id] != script.id || project.approvedScriptID == script.id
            || project.storyboard?.sourceScriptID == script.id
        {
            project.checkpoint()
            script.id = UUID()
            project.scripts.append(script)
            project.activeScriptID = script.id
            editingDrafts[id] = script.id
        }
        script[keyPath: field] = value
        if let index = project.scripts.firstIndex(where: { $0.id == script.id }) {
            project.scripts[index] = script
        }
        project.approvedScriptID = nil
        project.touch()
        update(id, immediate: false) { $0 = project }
    }
    func generate(
        _ id: UUID, operation: MiraOperation, request: String = "", target: UUID? = nil,
        language: MiraLanguage? = nil, service: any MiraGenerationService
    ) {
        guard let project = project(id), generationTasks[id] == nil else { return }
        if project.job?.state == .working {
            error = "A saved request is already running. Reconnect or cancel it first."
            return
        }
        var profile = project.isDemo ? MiraFixtures.mamta : document.profile
        if operation != .ideas && operation != .script,
            let currentLanguage = project.script.flatMap({ MiraLanguage(rawValue: $0.language) })
        {
            profile.language = currentLanguage
        }
        if let language { profile.language = language }
        if [.storyboard, .reviseShot, .reviseStoryboard].contains(operation), project.script == nil {
            error = "Choose a script first."
            return
        }
        if operation == .script && project.idea == nil {
            error = "Choose an idea before generating a script."
            return
        }
        if operation == .requirements
            && project.brief.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            error = "Paste the original brand requirements first."
            return
        }
        if operation == .reviseShot && project.storyboardIsStale {
            error = "Update the full shot list to your current script before changing one shot."
            return
        }
        let input = MiraGenerationInput(
            operation: operation, profile: profile, constraints: project.constraints,
            request: request.isEmpty ? project.request : request,
            recentIdeas: Array(project.ideas.suffix(30).map(\.title)), idea: project.idea,
            script: project.script, storyboard: project.storyboard,
            brief: operation == .requirements || project.brief.confirmed ? project.brief : nil,
            targetShotID: target)
        let job = MiraJob(inputRevision: project.inputRevision, input: input)
        update(id) { $0.job = job }
        generationTasks[id] = Task {
            guard await flush() else {
                generationTasks[id] = nil
                return
            }
            await perform(id, job: job, service: service, start: true)
            generationTasks[id] = nil
        }
    }
    func reconnect(_ id: UUID, service: any MiraGenerationService) {
        guard generationTasks[id] == nil, let job = project(id)?.job, job.state == .working else {
            return
        }
        generationTasks[id] = Task {
            guard await flush() else {
                generationTasks[id] = nil
                return
            }
            await perform(id, job: job, service: service, start: true)
            generationTasks[id] = nil
        }
    }
    private func perform(_ id: UUID, job: MiraJob, service: any MiraGenerationService, start: Bool)
        async
    {
        do {
            var result = start ? try await service.start(job) : try await service.status(job)
            for _ in 0..<45 {
                try Task.checkCancellation()
                guard let current = project(id), current.job?.id == job.id, current.job?.state != .cancelled
                else { return }
                if result.state != .working { break }
                update(id) { $0.job?.error = nil }
                try await Task.sleep(for: .seconds(3))
                result = try await service.status(job)
            }
            guard let project = project(id), project.job?.id == job.id, project.job?.state != .cancelled
            else { return }
            if let output = result.output {
                try MiraValidation.validate(output, for: job.input.operation, input: job.input)
            }
            var reconciled = project
            _ = try reconciled.receive(result)
            update(id) { $0 = reconciled }
            if result.state == .succeeded, result.output?.conflicts.isEmpty == true,
                project.inputRevision == job.inputRevision
            {
                let initial =
                    job.input.operation == .ideas || (job.input.operation == .script && project.script == nil)
                    || (job.input.operation == .storyboard && project.storyboard == nil)
                if initial { applyProposal(id) }
            }
            if result.state == .working {
                update(id) {
                    $0.job?.error =
                        "Still working. Reconnect this saved request later; it will keep the same job ID."
                }
            }
        } catch is CancellationError {} catch {
            update(id) { $0.job?.error = error.localizedDescription }
            self.error = error.localizedDescription
        }
    }
    func applyProposal(_ id: UUID) {
        guard let project = project(id), let job = project.job, let output = job.output else { return }
        guard project.inputRevision == job.inputRevision else {
            error =
                "Your work changed while Mira was generating. The proposal is preserved. Generate a new proposal from your current work."
            return
        }
        do {
            var copy = project
            try copy.apply(output, operation: job.input.operation)
            copy.job = nil
            update(id) { $0 = copy }
        } catch { self.error = error.localizedDescription }
    }
    func cancel(_ id: UUID, service: any MiraGenerationService) async {
        guard let job = project(id)?.job else { return }
        generationTasks[id]?.cancel()
        generationTasks[id] = nil
        do {
            let result = try await service.cancel(job)
            update(id) { $0.job = result }
        } catch {
            update(id) {
                $0.job?.error = "Cancellation is not confirmed. Reconnect to reconcile the saved request."
            }
            self.error = error.localizedDescription
        }
    }
}
