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
    func hasActiveRequest(_ id: UUID) -> Bool {
        guard let job = project(id)?.job else { return false }
        return generationTasks[job.id] != nil
    }
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
            switch route {
            case .shooting, .done: screen = .shooting
            case .words: screen = .words
            case .todayCards: screen = .todayCards
            case .project: screen = project.editorScreen
            }
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
    func approveWords(_ id: UUID) {
        guard let project = project(id), let script = project.script,
            project.approvedScriptID != script.id
        else { return }
        update(id) {
            $0.checkpoint()
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
        if let project = project(id) {
            for job in [project.job].compactMap({ $0 }) + (project.todayCards ?? []).map(\.job) {
                generationTasks[job.id]?.cancel()
            }
        }
        document.projects.removeAll { $0.id == id }
        if document.position.projectID == id { document.position = MiraPosition() }
        if var navigation = document.navigation {
            navigation.today.removeAll { $0.projectID == id }
            navigation.projects.removeAll { $0.projectID == id }
            document.navigation = navigation
        }
        save()
    }
    func setConstraint<T>(_ path: WritableKeyPath<MiraConstraints, T>, to value: T, in id: UUID) {
        guard let project = project(id) else { return }
        if !project.isDemo {
            var defaults = document.defaultConstraints ?? MiraConstraints()
            defaults[keyPath: path] = value
            document.defaultConstraints = defaults
        }
        update(id) {
            $0.constraints[keyPath: path] = value
            $0.touch()
        }
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
        guard let project = project(id), !hasActiveRequest(id) else { return }
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
        run(id, job: job, service: service)
    }
    func reconnect(_ id: UUID, service: any MiraGenerationService) {
        guard let job = project(id)?.job, job.state == .working else { return }
        run(id, job: job, service: service)
    }
    func startToday(request: String, demo: Bool = false, service: any MiraGenerationService) -> UUID {
        let profile = demo ? MiraFixtures.mamta : document.profile
        var project = MiraProject()
        project.isDemo = demo
        project.title = demo ? "Today’s demo Reel" : "Today’s Reel"
        project.request = request
        project.constraints = document.defaultConstraints ?? MiraConstraints()
        project.constraints.populate(from: request)
        let recent = document.projects.filter { $0.isDemo == demo }.flatMap { project in
            project.ideas.map(\.title) + (project.todayCards ?? []).compactMap { $0.output?.ideas?.first?.title }
        }
        let themes = profile.themes.components(separatedBy: CharacterSet(charactersIn: ",;\n/"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let formats = ["A short exercise or skill to demonstrate", "A food idea or simple daily habit", "A personal story or mindset tip"]
        project.todayCards = formats.enumerated().map { index, format in
            let angle = index < themes.count ? "\(format). Theme: \(themes[index])" : format
            let input = MiraGenerationInput(
                operation: .todayIdea, profile: profile, constraints: project.constraints, request: request,
                recentIdeas: Array(recent.prefix(30)), angle: angle)
            return MiraTodayCard(job: MiraJob(inputRevision: project.inputRevision, input: input))
        }
        project.lastScreen = .todayCards
        document.projects.insert(project, at: 0)
        document.position = MiraPosition(projectID: project.id, screen: MiraProjectScreen.todayCards.rawValue)
        save()
        reconnectCards(project.id, service: service)
        return project.id
    }

    func reconnectCards(_ id: UUID, service: any MiraGenerationService) {
        for card in project(id)?.todayCards ?? [] where card.job.state == .working {
            run(id, job: card.job, cardID: card.id, service: service)
        }
    }

    func retryCard(
        _ id: UUID, cardID: UUID, request: String? = nil, language: MiraLanguage? = nil,
        service: any MiraGenerationService
    ) {
        guard let project = project(id), let cards = project.todayCards,
            let index = cards.firstIndex(where: { $0.id == cardID }), cards[index].job.state != .working
        else { return }
        let card = cards[index]
        var input = card.job.input
        if let request {
            input.request = request
            input.idea = card.output?.ideas?.first
            input.constraints.populate(from: request)
        }
        if let language { input.profile.language = language }
        input.brief = project.brief.confirmed ? project.brief : nil
        var recentIdeas = cards.filter { $0.id != cardID }.compactMap { $0.output?.ideas?.first?.title }
        recentIdeas.append(contentsOf: input.recentIdeas)
        input.recentIdeas = Array(recentIdeas.prefix(30))
        let job = MiraJob(inputRevision: project.inputRevision, input: input)
        update(id) {
            $0.todayCards?[index].previousOutput = card.output
            $0.todayCards?[index].job = job
        }
        run(id, job: job, cardID: cardID, service: service)
    }

    func makeTodayCard(_ id: UUID, cardID: UUID) -> Bool {
        guard var project = project(id) else { return false }
        guard project.makeTodayCard(cardID) else {
            error = "This card needs an update before you can film it."
            return false
        }
        update(id) { $0 = project }
        return true
    }

    private func run(_ id: UUID, job: MiraJob, cardID: UUID? = nil, service: any MiraGenerationService) {
        guard generationTasks[job.id] == nil else { return }
        generationTasks[job.id] = Task {
            defer { generationTasks[job.id] = nil }
            guard await flush(), !Task.isCancelled else { return }
            await perform(id, job: job, cardID: cardID, service: service)
        }
    }

    private func currentJob(_ id: UUID, cardID: UUID?, matching jobID: UUID) -> MiraJob? {
        guard let project = project(id) else { return nil }
        let job = cardID.flatMap { id in project.todayCards?.first { $0.id == id }?.job }
            ?? (cardID == nil ? project.job : nil)
        return job?.id == jobID && job?.state == .working ? job : nil
    }

    private func perform(_ id: UUID, job: MiraJob, cardID: UUID?, service: any MiraGenerationService) async {
        do {
            var result = try await service.start(job)
            for _ in 0..<45 {
                try Task.checkCancellation()
                guard currentJob(id, cardID: cardID, matching: job.id) != nil else { return }
                if result.state != .working { break }
                try await Task.sleep(for: .seconds(3))
                result = try await service.status(job)
            }
            try Task.checkCancellation()
            guard let project = project(id), currentJob(id, cardID: cardID, matching: job.id) != nil else { return }
            if let cardID {
                receiveCard(id, cardID: cardID, pending: job, result: result)
                return
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
                    $0.job?.error = "Still working. Reconnect this saved request later; it will keep the same job ID."
                }
            }
        } catch {
            guard !Task.isCancelled, currentJob(id, cardID: cardID, matching: job.id) != nil else { return }
            if let cardID {
                update(id) { project in
                    guard let index = project.todayCards?.firstIndex(where: { $0.id == cardID }) else { return }
                    project.todayCards?[index].job.error = "Could not check this idea. Reconnect to keep your place."
                }
            } else {
                update(id) { $0.job?.error = error.localizedDescription }
                self.error = error.localizedDescription
            }
        }
    }

    private func receiveCard(_ id: UUID, cardID: UUID, pending: MiraJob, result: MiraJob) {
        guard currentJob(id, cardID: cardID, matching: pending.id) != nil,
            let cards = project(id)?.todayCards, let index = cards.firstIndex(where: { $0.id == cardID })
        else { return }
        guard result.id == pending.id, result.inputRevision == pending.inputRevision, result.input == pending.input else {
            update(id) { $0.todayCards?[index].job.error = "Could not match this reply. Reconnect to check this idea." }
            return
        }
        var result = result
        if result.state == .succeeded {
            do {
                guard let output = result.output, let idea = output.ideas?.first else {
                    throw MiraError.invalid("The idea was missing.")
                }
                try MiraValidation.validate(output, for: .todayIdea, input: pending.input)
                let title = idea.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !cards.contains(where: { card in
                    card.id != cardID && card.output?.ideas?.first?.title
                        .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == title
                }) else { throw MiraError.invalid("This idea matches another card.") }
            } catch {
                result.state = .failed
                result.output = nil
            }
        }
        if result.state == .working { result.error = "Still working. Reconnect to check this idea again." }
        update(id) {
            $0.todayCards?[index].job = result
            if result.state == .succeeded { $0.todayCards?[index].previousOutput = nil }
        }
    }

    func cancelCard(_ id: UUID, cardID: UUID, service: any MiraGenerationService) async {
        guard let card = project(id)?.todayCards?.first(where: { $0.id == cardID }),
            card.job.state == .working else { return }
        let job = card.job
        generationTasks[job.id]?.cancel()
        await generationTasks[job.id]?.value
        guard currentJob(id, cardID: cardID, matching: job.id) != nil else { return }
        let cancellation = Task { [self] in
            defer { generationTasks[job.id] = nil }
            do {
                receiveCard(id, cardID: cardID, pending: job, result: try await service.cancel(job))
            } catch {
                update(id) { project in
                    guard let index = project.todayCards?.firstIndex(where: { $0.id == cardID }) else { return }
                    project.todayCards?[index].job.error = "Could not confirm the stop. Reconnect to check this idea."
                }
            }
        }
        generationTasks[job.id] = cancellation
        await cancellation.value
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
        generationTasks[job.id]?.cancel()
        await generationTasks[job.id]?.value
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
