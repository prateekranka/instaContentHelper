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
    init(repository: (any MiraProjectRepository)? = nil) {
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
                ".local/share", isDirectory: true)
        self.repository =
            repository
            ?? MiraFileRepository(
                directory: support.appendingPathComponent("Mira", isDirectory: true))
    }
    func load() async {
        guard !loaded else { return }
        do {
            document = try await repository.load()
            loaded = true
            loadFailed = false
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
        save(immediate: immediate)
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
    func flush() async {
        guard loaded, !loadFailed else { return }
        saveTask?.cancel()
        document.sequence += 1
        do {
            try await repository.save(document)
            saveMessage = nil
        } catch { saveMessage = error.localizedDescription }
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
        save()
    }
    func remember(_ preference: String) {
        document.profile.tone = preference
        save()
    }
    func editScript<T: Equatable>(_ id: UUID, field: WritableKeyPath<MiraScript, T>, value: T) {
        guard var project = project(id), var script = project.script, script[keyPath: field] != value else {
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
            await flush()
            await perform(id, job: job, service: service, start: true)
            generationTasks[id] = nil
        }
    }
    func reconnect(_ id: UUID, service: any MiraGenerationService) {
        guard generationTasks[id] == nil, let job = project(id)?.job, job.state == .working else { return }
        generationTasks[id] = Task {
            await perform(id, job: job, service: service, start: true)
            generationTasks[id] = nil
        }
    }
    private func perform(_ id: UUID, job: MiraJob, service: any MiraGenerationService, start: Bool) async {
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
