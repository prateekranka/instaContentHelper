import Foundation
import Observation

protocol MiraGenerationService: Sendable {
    func start(_ job: MiraJob) async throws -> MiraJobResponse
    func status(_ job: MiraJob) async throws -> MiraJobResponse
    func cancel(_ job: MiraJob) async throws -> MiraJobResponse
    func pictureStatus(_ jobID: UUID) async throws -> MiraJobResponse?
}

extension MiraGenerationService {
    func pictureStatus(_ jobID: UUID) async throws -> MiraJobResponse? { nil }
}

@MainActor @Observable
final class MiraStore {
    var document = MiraDocument()
    private(set) var location = MiraLocationState(document: MiraDocument())
    private(set) var library = MiraLibraryState.unopened
    private let repository: any MiraProjectRepository
    private var saveTask: Task<Void, Never>?
    private var wordsStates: [UUID: MiraWordsState] = [:]
    private var requestStates: [UUID: MiraAIRequest] = [:]
    private var generationTasks: [UUID: Task<Void, Never>] = [:]
    private var pictureTasks: [UUID: Task<Void, Never>] = [:]
    private var editingDrafts: [UUID: UUID] = [:]
    private struct WaitingStart {
        var projectID: UUID
        var cardID: UUID?
        var service: any MiraGenerationService
    }
    private var waitingStarts: [UUID: WaitingStart] = [:]
    private var waitingTimer: Task<Void, Never>?
    init(repository: any MiraProjectRepository) { self.repository = repository }
    @discardableResult
    private func transitionLibrary(_ event: MiraLibraryEvent) -> Bool {
        guard let next = library.handle(event) else { return false }
        library = next
        return true
    }

    func load() async {
        guard transitionLibrary(.open) else { return }
        do {
            document = try await repository.load()
            location = MiraLocationState(document: document)
            transitionLibrary(.opened)
        } catch MiraError.newerVersion {
            transitionLibrary(.openFailed(.newerVersion))
        } catch let failure as MiraLibraryOpenFailure {
            transitionLibrary(.openFailed(failure))
        } catch {
            transitionLibrary(.openFailed(.unavailable(error.localizedDescription)))
        }
    }

    func reportError(_ message: String) { transitionLibrary(.reportError(message)) }
    func dismissError() { transitionLibrary(.dismissError) }

    func project(_ id: UUID) -> MiraProject? { document.projects.first { $0.id == id } }
    func requestState(_ job: MiraJob?) -> MiraAIRequest {
        guard let job else { return .idle }
        return requestStates[job.id] ?? MiraAIRequest(saved: job)
    }

    func cardState(_ card: MiraTodayCard, in project: MiraProject) -> MiraTodayCardState {
        MiraTodayCardState.needsUpdate(nil).handle(
            .workChanged(card, requestState(card.job), briefRevision: project.effectiveBriefRevision)
        ) ?? .needsUpdate(card.output)
    }

    @discardableResult
    private func transitionRequest(_ job: MiraJob, _ event: MiraAIRequestEvent) -> MiraAIRequest? {
        transitionRequest(job.id, from: requestState(job), event)
    }

    @discardableResult
    private func transitionRequest(_ jobID: UUID, from state: MiraAIRequest, _ event: MiraAIRequestEvent) -> MiraAIRequest? {
        guard let next = state.handle(event) else { return nil }
        requestStates[jobID] = next
        return next
    }

    func update(
        _ id: UUID, immediate: Bool = true, screen: MiraProjectScreen? = nil,
        _ change: (inout MiraProject) -> Void
    ) {
        guard case .loaded = library, let index = document.projects.firstIndex(where: { $0.id == id }) else { return }
        let oldJob = document.projects[index].job?.id
        change(&document.projects[index])
        if let oldJob, oldJob != document.projects[index].job?.id { requestStates[oldJob] = nil }
        if let screen {
            location = location.handle(.remember(id, screen, makeCurrent: false))
        }
        save(immediate: immediate)
    }

    @discardableResult
    func editBrief(_ id: UUID, _ event: MiraBriefEvent, immediate: Bool = false) -> Bool {
        guard let next = project(id)?.briefState.handle(event) else { return false }
        update(id, immediate: immediate) {
            $0.brief = next.record
            $0.touch()
        }
        return true
    }

    func navigate(_ event: MiraLocationEvent) {
        switch event {
        case .selectTab(let tab) where tab == location.tab: return
        case .setPath(let tab, let path) where path == location.path(tab): return
        default: break
        }
        location = location.handle(event)
        if let current = location.current, let project = project(current.projectID) {
            let screen = current.screen(in: project, remembering: location.rememberedScreen(project.id))
            location = location.handle(.remember(project.id, screen, makeCurrent: true))
        }
        save()
    }

    func open(_ id: UUID, tab: MiraMainTab) {
        guard let project = project(id) else { return }
        let previous = location.rememberedScreen(id)
        let path = tab == .home
            ? project.todayResumePath(remembering: previous)
            : project.resumePath(remembering: previous)
        navigate(.open(tab, path))
    }

    var homeFeed: MiraHomeFeed {
        MiraHomeFeed.empty.handle(.workChanged(document.projects, resume: location.lastProject))
    }

    func continueReel(_ id: UUID) {
        guard let project = project(id), homeFeed.contains(id) else { return }
        let editor: [MiraRoute] = [.project(id)]
        let hasCards = project.todayCards?.isEmpty == false
        let path: [MiraRoute]
        switch project.stage {
        case .choosing:
            path = hasCards ? [.todayCards(id)] : editor
        case .writing:
            path = editor
        case .planning(let hasShots):
            location = location.handle(.remember(id, hasShots ? .shots : .script, makeCurrent: true))
            path = editor
        case .approving:
            path = (hasCards ? [.todayCards(id)] : editor) + [.words(id)]
        case .ready:
            location = location.handle(.remember(id, .shots, makeCurrent: true))
            path = editor
        case .filming:
            path = editor + [.shooting(id)]
        case .complete:
            return
        }
        navigate(.open(.home, path))
    }

    func taskStep(_ location: MiraLocation, in project: MiraProject) -> MiraTaskStep {
        MiraTaskStep.idea.handle(
            .opened(location, editorSection: editorScreen(project), progress: project.stage, approved: project.isApproved))
    }

    func editorScreen(_ project: MiraProject) -> MiraProjectScreen {
        project.editorScreen(remembering: location.rememberedScreen(project.id))
    }

    func visit(_ id: UUID, screen: MiraProjectScreen) {
        location = location.handle(.remember(id, screen, makeCurrent: true))
        save()
    }

    private func encodeLocation() {
        document.navigation = MiraNavigation(
            tab: location.savedTab, today: location.path(.home), projects: location.path(.myBrand))
        for index in document.projects.indices {
            let screen = location.rememberedScreen(document.projects[index].id)
            if document.projects[index].lastScreen != screen {
                document.projects[index].lastScreen = screen
            }
        }
        if let id = location.lastProject, let project = project(id) {
            document.position = MiraPosition(
                projectID: id, screen: location.rememberedScreen(id)?.rawValue ?? "project", shotIndex: project.shotIndex)
        } else {
            document.position = MiraPosition()
        }
    }

    func moveShot(_ id: UUID, to index: Int) {
        guard let project = project(id), let board = project.storyboard else { return }
        update(id, screen: .shooting) {
            $0.shotIndex = min(max(0, index), max(0, board.shots.count - 1))
        }
    }
    func startFilming(_ id: UUID) {
        guard let project = project(id), project.canFilm else { return }
        update(id) { $0.startedFilming = true }
        visit(id, screen: .shooting)
    }
    func toggleFilmed(_ id: UUID, shotID: UUID) {
        guard let project = project(id), project.canFilm,
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
    func wordsState(_ project: MiraProject) -> MiraWordsState {
        (wordsStates[project.id] ?? .reviewing).presentation(for: project, request: requestState(project.job))
    }

    func sendWords(
        _ id: UUID, _ event: MiraWordsEvent, service: (Bool) throws -> any MiraGenerationService
    ) {
        guard let project = project(id), project.script != nil else { return }
        let current = wordsStates[id] ?? .reviewing
        if case .appeared = event {
            if let (next, _) = current.handle(event) { wordsStates[id] = next }
            if case .needsReconnect = requestState(project.job) {
                sendWords(id, .reconnect, service: service)
            }
            advanceWordsIfVisible(id)
            return
        }
        guard let (next, effect) = wordsState(project).handle(event) else { return }
        wordsStates[id] = next
        do {
            switch effect {
            case .approve:
                guard !project.isApproved else { return }
                update(id) {
                    $0.checkpoint()
                    $0.approvedScriptID = $0.activeScriptID
                    $0.touch()
                }
                if project.storyboard != nil, project.storyboardIsStale {
                    sendWords(id, .retry, service: service)
                } else {
                    sendWords(id, .reviewPlan, service: service)
                }
            case .generate(let operation, let text, let target, let language):
                generate(id, operation: operation, request: text, target: target, language: language,
                         service: try service(true))
                if requestState(self.project(id)?.job).pending, let (settled, _) = next.handle(.requestStarted) {
                    wordsStates[id] = settled
                }
            case .openPlan:
                guard project.isApproved else { wordsStates[id] = current; return }
                navigate(.showPlan(id))
            case .applyWords:
                applyProposal(id, keepWordsScreen: true)
            case .clearProposal:
                update(id) { $0.job = nil }
            case .reconnect:
                reconnect(id, service: try service(true))
            case .stop:
                let generation = try service(false)
                Task { await cancel(id, service: generation) }
            case .applyShots, nil: break
            }
        } catch { reportError(error.localizedDescription) }
    }

    private func advanceWordsIfVisible(_ id: UUID) {
        guard location.current == .words(id), let project = project(id),
            let (next, effect) = wordsState(project).handle(.received),
            case .applyShots = effect
        else { return }
        wordsStates[id] = next
        applyProposal(id, keepWordsScreen: true)
        if let updated = self.project(id), updated.job == nil, !updated.storyboardIsStale,
            let (opening, _) = next.handle(.shotsApplied) {
            wordsStates[id] = opening
            navigate(.showPlan(id))
        } else if let (failed, _) = next.handle(.shotsRejected) {
            wordsStates[id] = failed
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
        update(id, screen: .script) { $0.select(idea) }
    }
    func chooseAnotherIdea(_ id: UUID) {
        update(id, screen: .ideas) {
            $0.selectedIdeaID = nil
            $0.touch()
        }
    }
    func writeScriptManually(_ id: UUID) {
        guard let project = project(id), project.idea != nil, project.script == nil else { return }
        let language = project.isDemo ? MiraFixtures.mamta.language : document.profile.language
        update(id, screen: .script) {
            let script = MiraScript(
                hook: $0.idea?.hook ?? "", spoken: "", caption: "",
                durationSeconds: $0.constraints.reelSeconds, language: language.rawValue)
            $0.scripts.append(script)
            $0.activeScriptID = script.id
            $0.touch()
        }
    }
    func restoreScript(_ id: UUID, revisionID: UUID) {
        guard project(id)?.scripts.contains(where: { $0.id == revisionID }) == true else { return }
        update(id, screen: .script) {
            $0.checkpoint()
            $0.activeScriptID = revisionID
            $0.approvedScriptID = nil
            $0.touch()
        }
    }
    func save(immediate: Bool = true) {
        guard case .loaded = library else { return }
        encodeLocation()
        document.sequence += 1
        let snapshot = document
        saveTask?.cancel()
        saveTask = Task {
            if !immediate { do { try await Task.sleep(for: .milliseconds(450)) } catch { return } }
            do {
                try await repository.save(snapshot)
                if document.sequence == snapshot.sequence { transitionLibrary(.saved) }
            } catch {
                if document.sequence == snapshot.sequence {
                    transitionLibrary(.saveFailed("Changes are in memory but could not be saved. \(error.localizedDescription)"))
                }
            }
        }
    }
    @discardableResult func flush() async -> Bool {
        guard case .loaded = library else { return false }
        saveTask?.cancel()
        encodeLocation()
        document.sequence += 1
        let snapshot = document
        do {
            try await repository.save(snapshot)
            if document.sequence == snapshot.sequence { transitionLibrary(.saved) }
            return true
        } catch {
            if document.sequence == snapshot.sequence { transitionLibrary(.saveFailed(error.localizedDescription)) }
            return false
        }
    }
    func newProject(briefText: String = "") -> UUID {
        var project = MiraProject()
        if let brief = project.briefState.handle(.textChanged(briefText)), !briefText.isEmpty {
            project.brief = brief.record
        }
        document.projects.insert(project, at: 0)
        location = location.handle(.remember(project.id, nil, makeCurrent: true))
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
        location = location.handle(.remember(project.id, nil, makeCurrent: true))
        save()
        return project.id
    }
    func delete(_ id: UUID) {
        if let project = project(id) {
            for job in [project.job].compactMap({ $0 }) + (project.todayCards ?? []).map(\.job) {
                generationTasks[job.id]?.cancel()
                requestStates[job.id] = nil
                waitingStarts[job.id] = nil
            }
        }
        document.projects.removeAll { $0.id == id }
        wordsStates[id] = nil
        navigate(.remove(id))
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
        guard let project = project(id) else { return }
        if requestState(project.job).pending {
            reportError("A saved request is already running. Reconnect or cancel it first.")
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
            reportError("Choose a script first.")
            return
        }
        if operation == .script && project.idea == nil {
            reportError("Choose an idea before generating a script.")
            return
        }
        if operation == .requirements
            && project.brief.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            reportError("Paste the original brand requirements first.")
            return
        }
        if operation == .reviseShot && project.storyboardIsStale {
            reportError("Update the full shot list to your current script before changing one shot.")
            return
        }
        let input = MiraGenerationInput(
            operation: operation, profile: profile, constraints: project.constraints,
            request: request.isEmpty ? project.request : request,
            recentIdeas: Array(project.ideas.suffix(30).map(\.title)), idea: project.idea,
            script: project.script, storyboard: project.storyboard,
            brief: operation == .requirements ? project.brief : project.briefState.confirmedRecord,
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
        document.projects.insert(project, at: 0)
        location = location.handle(.remember(project.id, .todayCards, makeCurrent: true))
        save()
        reconnectCards(project.id, service: service)
        return project.id
    }

    func reconnectCards(_ id: UUID, service: any MiraGenerationService) {
        guard let project = project(id) else { return }
        for card in project.todayCards ?? [] {
            if card.job.state == .working {
                run(id, job: card.job, cardID: card.id, service: service)
            }
            if let board = card.output?.storyboard {
                watchPictures(in: project, boardID: board.id, service: service)
            }
        }
    }

    func watchPictures(in project: MiraProject, boardID: UUID, service: any MiraGenerationService) {
        guard let jobID = project.shotPictureSources?[boardID]?.jobID,
            pictureRequest(jobID).pictures.isEmpty || picturesNeedStatus(jobID)
        else { return }
        pollPictures(jobID, service: service)
    }

    func picture(in project: MiraProject, boardID: UUID, shotID: UUID) -> MiraShotPictureState? {
        guard let source = project.shotPictureSources?[boardID], let originalID = source.shotIDs[shotID] else {
            return nil
        }
        return pictureRequest(source.jobID).pictures[originalID]
    }

    func refreshPicture(
        in project: MiraProject, boardID: UUID, shotID: UUID, url: URL, service: any MiraGenerationService
    ) {
        guard let source = project.shotPictureSources?[boardID], let originalID = source.shotIDs[shotID],
            transitionRequest(source.jobID, from: pictureRequest(source.jobID), .pictureLoadFailed(originalID, url, at: Date())) != nil
        else { return }
        if picturesNeedStatus(source.jobID) { pollPictures(source.jobID, service: service) }
    }

    private func pictureRequest(_ jobID: UUID) -> MiraAIRequest {
        requestStates[jobID] ?? .done(pictures: [:])
    }

    private func picturesNeedStatus(_ jobID: UUID) -> Bool {
        pictureRequest(jobID).pictures.values.contains {
            switch $0 {
            case .pending, .refreshing: true
            case .ready, .failed: false
            }
        }
    }

    private func pollPictures(_ jobID: UUID, service: any MiraGenerationService) {
        guard pictureTasks[jobID] == nil else { return }
        pictureTasks[jobID] = Task {
            defer { pictureTasks[jobID] = nil }
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(300))
            var misses = 0
            repeat {
                do {
                    guard let response = try await service.pictureStatus(jobID) else { return }
                    if response.job.id == jobID, response.job.state == .succeeded, let pictures = response.pictures,
                        transitionRequest(jobID, from: pictureRequest(jobID), .picturesReceived(pictures)) != nil
                    {
                        misses = 0
                        if !picturesNeedStatus(jobID) { return }
                    } else {
                        misses += 1
                    }
                } catch {
                    misses += 1
                }
                guard misses < 3 else { return }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            } while clock.now < deadline
        }
    }

    func retryCard(
        _ id: UUID, cardID: UUID, request: String? = nil, language: MiraLanguage? = nil,
        service: any MiraGenerationService
    ) {
        guard let project = project(id), let cards = project.todayCards,
            let index = cards.firstIndex(where: { $0.id == cardID }),
            cardState(cards[index], in: project).handle(.retry) != nil
        else { return }
        let card = cards[index]
        requestStates[card.job.id] = nil
        var input = card.job.input
        if let request {
            input.request = request
            input.idea = card.output?.ideas?.first
            input.constraints.populate(from: request)
        }
        if let language { input.profile.language = language }
        input.brief = project.briefState.confirmedRecord
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
        guard let card = project.todayCards?.first(where: { $0.id == cardID }),
            cardState(card, in: project).handle(.make) != nil, project.makeTodayCard(cardID)
        else {
            reportError("This card needs an update before you can film it.")
            return false
        }
        update(id, screen: .words) { $0 = project }
        return true
    }

    private func run(_ id: UUID, job: MiraJob, cardID: UUID? = nil, service: any MiraGenerationService) {
        guard generationTasks[job.id] == nil, transitionRequest(job, .send) != nil else { return }
        generationTasks[job.id] = Task {
            defer { generationTasks[job.id] = nil }
            guard await flush(), !Task.isCancelled else {
                guard !Task.isCancelled else { return }
                if waitingStarts[job.id] != nil {
                    wait(id, job: job, cardID: cardID, service: service)
                } else {
                    transitionRequest(job, .saveFailed)
                }
                return
            }
            await perform(id, job: job, cardID: cardID, service: service)
        }
    }

    private func currentJob(_ id: UUID, cardID: UUID?, matching jobID: UUID) -> MiraJob? {
        guard let project = project(id) else { return nil }
        let job = cardID.flatMap { id in project.todayCards?.first { $0.id == id }?.job }
            ?? (cardID == nil ? project.job : nil)
        return job?.id == jobID && job?.state == .working ? job : nil
    }

    private func validateReply(_ reply: MiraJob, for job: MiraJob) throws {
        guard reply.id == job.id, reply.inputRevision == job.inputRevision, reply.input == job.input else {
            throw MiraError.invalid("Could not match this reply.")
        }
    }

    private func perform(_ id: UUID, job: MiraJob, cardID: UUID?, service: any MiraGenerationService) async {
        do {
            var response: MiraJobResponse
            do {
                response = try await service.start(job)
            } catch MiraError.busy {
                guard !Task.isCancelled, currentJob(id, cardID: cardID, matching: job.id) != nil else { return }
                wait(id, job: job, cardID: cardID, service: service)
                return
            }
            try Task.checkCancellation()
            try validateReply(response.job, for: job)
            guard currentJob(id, cardID: cardID, matching: job.id) != nil,
                transitionRequest(job, .accepted(response)) != nil
            else { return }
            waitingStarts[job.id] = nil
            for _ in 0..<45 {
                try Task.checkCancellation()
                guard currentJob(id, cardID: cardID, matching: job.id) != nil else { return }
                if response.job.state != .working { break }
                try await Task.sleep(for: .seconds(3))
                response = try await service.status(job)
                try Task.checkCancellation()
                try validateReply(response.job, for: job)
                guard currentJob(id, cardID: cardID, matching: job.id) != nil,
                    transitionRequest(job, .progress(response)) != nil else { return }
            }
            try Task.checkCancellation()
            var result = response.job
            guard let project = project(id), currentJob(id, cardID: cardID, matching: job.id) != nil else { return }
            if let cardID {
                receiveCard(id, cardID: cardID, pending: job, result: result)
                if let project = self.project(id),
                    let board = project.todayCards?.first(where: { $0.id == cardID && $0.job.id == job.id })?.job.output?.storyboard {
                    watchPictures(in: project, boardID: board.id, service: service)
                }
            } else {
                if result.state == .working {
                    result.error = "Still working. Reconnect this saved request later; it will keep the same job ID."
                }
                var reconciled = project
                _ = try reconciled.receive(result)
                transitionRequest(job, .received(result))
                update(id) { $0 = reconciled }
                if result.state == .succeeded, result.output?.conflicts.isEmpty == true,
                    project.inputRevision == job.inputRevision
                {
                    let initial =
                        job.input.operation == .ideas || (job.input.operation == .script && project.script == nil)
                        || (job.input.operation == .storyboard && project.storyboard == nil)
                    if initial { applyProposal(id) }
                }
                advanceWordsIfVisible(id)
            }
            if result.state != .working { sendWaiting() }
        } catch {
            guard !Task.isCancelled, currentJob(id, cardID: cardID, matching: job.id) != nil else { return }
            waitingStarts[job.id] = nil
            let message = cardID == nil ? error.localizedDescription
                : "Could not check this idea. Reconnect to keep your place."
            needsReconnect(id, cardID: cardID, job: job, message: message)
            if cardID == nil { reportError(message) }
        }
    }

    private func needsReconnect(_ id: UUID, cardID: UUID?, job: MiraJob, message: String) {
        transitionRequest(job, .reconnect(message))
        update(id) { project in
            if let cardID, let index = project.todayCards?.firstIndex(where: { $0.id == cardID && $0.job.id == job.id }) {
                project.todayCards?[index].job.error = message
            } else if cardID == nil, project.job?.id == job.id {
                project.job?.error = message
            }
        }
    }

    private func wait(_ id: UUID, job: MiraJob, cardID: UUID?, service: any MiraGenerationService) {
        switch transitionRequest(job, .refused) {
        case .waitingToStart:
            waitingStarts[job.id] = WaitingStart(projectID: id, cardID: cardID, service: service)
            scheduleWaiting()
        case .needsReconnect(let reason):
            waitingStarts[job.id] = nil
            if let reason { needsReconnect(id, cardID: cardID, job: job, message: reason) }
        default: break
        }
    }

    private func scheduleWaiting() {
        guard waitingTimer == nil else { return }
        waitingTimer = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            self?.waitingTimer = nil
            self?.sendWaiting()
        }
    }

    private func sendWaiting() {
        for (jobID, waiting) in waitingStarts {
            guard let job = currentJob(waiting.projectID, cardID: waiting.cardID, matching: jobID) else {
                waitingStarts[jobID] = nil
                continue
            }
            run(waiting.projectID, job: job, cardID: waiting.cardID, service: waiting.service)
        }
    }

    private func stopped(_ id: UUID, cardID: UUID?, job: MiraJob) {
        var result = job
        result.state = .cancelled
        result.error = nil
        finishStop(id, cardID: cardID, pending: job, result: result)
    }

    private func finishStop(_ id: UUID, cardID: UUID?, pending: MiraJob, result: MiraJob) {
        guard currentJob(id, cardID: cardID, matching: pending.id) != nil else { return }
        if let cardID {
            receiveCard(id, cardID: cardID, pending: pending, result: result)
        } else {
            transitionRequest(pending, .received(result))
            update(id) { $0.job = result }
            advanceWordsIfVisible(id)
        }
        sendWaiting()
    }

    private func receiveCard(_ id: UUID, cardID: UUID, pending: MiraJob, result: MiraJob) {
        guard currentJob(id, cardID: cardID, matching: pending.id) != nil,
            let cards = project(id)?.todayCards, let index = cards.firstIndex(where: { $0.id == cardID })
        else { return }
        guard result.id == pending.id, result.inputRevision == pending.inputRevision, result.input == pending.input else {
            needsReconnect(id, cardID: cardID, job: pending,
                           message: "Could not match this reply. Reconnect to check this idea.")
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
        transitionRequest(pending, .received(result))
        update(id) {
            $0.todayCards?[index].job = result
            if result.state == .succeeded, let board = result.output?.storyboard {
                let shotIDs = Dictionary(uniqueKeysWithValues: board.shots.map { ($0.id, $0.id) })
                var sources = $0.shotPictureSources ?? [:]
                sources[board.id] = MiraShotPictureSource(jobID: result.id, shotIDs: shotIDs)
                $0.shotPictureSources = sources
                $0.todayCards?[index].previousOutput = nil
            }
        }
    }

    func cancelCard(_ id: UUID, cardID: UUID, service: any MiraGenerationService) async {
        guard let card = project(id)?.todayCards?.first(where: { $0.id == cardID }) else { return }
        await stop(id, cardID: cardID, job: card.job, service: service)
    }

    private func stop(_ id: UUID, cardID: UUID?, job: MiraJob, service: any MiraGenerationService) async {
        guard transitionRequest(job, .stop) != nil else { return }
        waitingStarts[job.id] = nil
        generationTasks[job.id]?.cancel()
        await generationTasks[job.id]?.value
        guard currentJob(id, cardID: cardID, matching: job.id) != nil else { return }
        do {
            let result = try await service.cancel(job).job
            try validateReply(result, for: job)
            finishStop(id, cardID: cardID, pending: job, result: result)
        } catch MiraError.notFound {
            stopped(id, cardID: cardID, job: job)
        } catch {
            guard currentJob(id, cardID: cardID, matching: job.id) != nil else { return }
            let message = cardID == nil
                ? "Cancellation is not confirmed. Reconnect to reconcile the saved request."
                : "Could not confirm the stop. Reconnect to check this idea."
            needsReconnect(id, cardID: cardID, job: job, message: message)
            if cardID == nil { reportError(error.localizedDescription) }
        }
    }

    func applyProposal(_ id: UUID, keepWordsScreen: Bool = false) {
        guard let project = project(id), let job = project.job, let output = job.output else { return }
        guard project.inputRevision == job.inputRevision else {
            reportError("Your work changed while Mira was generating. The proposal is preserved. Generate a new proposal from your current work.")
            return
        }
        do {
            var copy = project
            try copy.apply(output, operation: job.input.operation)
            copy.job = nil
            let screen: MiraProjectScreen?
            if keepWordsScreen { screen = .words }
            else if output.storyboard != nil { screen = .shots }
            else { screen = output.script != nil ? .script : nil }
            update(id, screen: screen) { $0 = copy }
        } catch { reportError(error.localizedDescription) }
    }
    func cancel(_ id: UUID, service: any MiraGenerationService) async {
        guard let job = project(id)?.job else { return }
        await stop(id, cardID: nil, job: job, service: service)
    }
}
