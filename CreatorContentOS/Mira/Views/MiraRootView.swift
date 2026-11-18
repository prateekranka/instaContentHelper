import SwiftUI

struct MiraRootView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    let dependencies: MiraDependencies
    private var store: MiraStore { dependencies.store }
    @State private var navigation = MiraNavigation()
    @State private var sheet: MiraSheet?
    @State private var todayRequest = ""
    @FocusState private var isTodayRequestFocused: Bool
    @ScaledMetric private var bodySize = 18.0
    var body: some View {
        Group {
            if store.loaded {
                TabView(selection: $navigation.tab) {
                    NavigationStack(path: $navigation.today) {
                        today.navigationDestination(for: MiraRoute.self, destination: destination)
                    }.tabItem { Label("Today", systemImage: "sun.max") }.tag(MiraTab.today)
                    NavigationStack(path: $navigation.projects) {
                        MiraProjectsView(store: store, onOpen: { open($0, tab: .projects) }, onDelete: delete)
                            .navigationDestination(
                                for: MiraRoute.self, destination: destination
                            )
                            .toolbar { ToolbarItem(placement: .topBarTrailing) { profileButton } }
                    }.tabItem { Label("Projects", systemImage: "book.closed") }.tag(MiraTab.projects)
                }
            } else {
                MiraPage {
                    Text("Mira").font(.largeTitle)
                    if store.loadFailed {
                        Text(store.error ?? "Your library could not be opened.")
                        Button("Try opening saved work again") { Task { await store.load() } }
                    } else {
                        ProgressView("Opening your notebook")
                    }
                }
            }
        }
        .font(.system(size: bodySize)).tint(MiraTheme.olive)
        .sheet(item: $sheet) { value in
            NavigationStack {
                switch value {
                case .profile: MiraProfileView(store: store)
                case .ask(let id, let operation, let target):
                    MiraAskView(
                        store: store, projectID: id, operation: operation, target: target,
                        onGenerate: generate)
                case .adjustIdea(let id, let ideaID):
                    MiraAskView(
                        store: store, projectID: id, operation: .ideas,
                        onGenerate: generate,
                        contextIdea: store.project(id)?.ideas.first { $0.id == ideaID })
                case .askToday(let id, let cardID):
                    if let card = store.project(id)?.todayCards?.first(where: { $0.id == cardID }) {
                        MiraAskView(
                            store: store, projectID: id, operation: .todayIdea,
                            onGenerate: { _, _, request, _, language in
                                let context = card.output?.ideas?.first.map { "Change this idea: \($0.title). " } ?? ""
                                retryCard(id, cardID: cardID, request: context + request, language: language)
                            }, contextIdea: card.output?.ideas?.first)
                    }
                case .todayScript(let id, let cardID):
                    if let script = store.project(id)?.todayCards?.first(where: { $0.id == cardID })?.output?.script {
                        MiraPage {
                            MiraSectionTitle(text: "Hook")
                            Text(script.hook)
                            MiraSectionTitle(text: "Words to say")
                            Text(script.spoken)
                            MiraSectionTitle(text: "Caption")
                            Text(script.caption)
                        }.navigationTitle("Script")
                            .toolbar { Button("Close") { sheet = nil } }
                    }
                case .brief(let id): MiraBriefView(store: store, projectID: id, onGenerate: generate)
                case .manualIdea(let id): MiraManualIdeaView(store: store, projectID: id)
                }
            }.tint(MiraTheme.olive)
        }
        .modifier(MiraConsentPresenter())
        .alert(
            "Mira",
            isPresented: Binding(
                get: { store.error != nil && store.loaded }, set: { if !$0 { store.error = nil } })
        ) {
            Button("OK") { store.error = nil }
        } message: {
            Text(store.error ?? "")
        }
        .safeAreaInset(edge: .bottom) {
            if let message = store.saveMessage {
                Text(message).font(.callout).padding().frame(maxWidth: .infinity).background(
                    MiraTheme.paper
                )
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .task {
            await store.load()
            if store.loaded { navigation = store.document.restoredNavigation() }
        }
        .onChange(of: navigation) { _, value in store.rememberNavigation(value) }
        .onChange(of: store.loaded) { _, loaded in
            if loaded { navigation = store.document.restoredNavigation() }
        }
        .onChange(of: store.document.projects.map(\.id)) { _, _ in
            let ids = Set(store.document.projects.map(\.id))
            navigation.today.removeAll { !ids.contains($0.projectID) }
            navigation.projects.removeAll { !ids.contains($0.projectID) }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { Task { await store.flush() } } }
    }
    private var profileButton: some View {
        Button {
            sheet = .profile
        } label: {
            Label("Profile", systemImage: "person.crop.circle")
        }
    }
    private var today: some View {
        MiraPage {
            if !store.document.profile.name.isEmpty {
                Text("Hello, \(store.document.profile.name).")
                    .font(.largeTitle.bold())
            }
            TextField("Anything for today?", text: $todayRequest)
                .textFieldStyle(.roundedBorder)
                .focused($isTodayRequestFocused)
                .submitLabel(.done)
                .onSubmit { isTodayRequestFocused = false }
                .accessibilityIdentifier("mira.today.request")
            Button("Make today's Reel", action: makeToday)
                .buttonStyle(MiraPrimaryStyle()).accessibilityIdentifier("mira.today.make")
            if let project = store.document.continuationProject {
                Button {
                    open(project.id, tab: .today)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Continue", systemImage: "arrow.right").font(.headline)
                        Text(project.title).font(.body)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.bordered)
            }
            Divider()
            Button("Plan step by step") { open(store.newProject(), tab: .projects) }.font(.callout)
            Button("Try Mamta’s demo notebook") { open(store.addDemo(), tab: .today) }.font(.callout)
        }.navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { profileButton } }
    }
    private func makeToday() {
        do {
            let demo = DebugLaunchFlags.forceFixtureUI
            let generation: any MiraGenerationService = demo
                ? MiraFixtureGenerationService(failTodayCard: todayRequest == "Demo card failure")
                : try service(nil)
            let id = store.startToday(
                request: todayRequest.trimmingCharacters(in: .whitespacesAndNewlines),
                demo: demo, service: generation)
            todayRequest = ""
            open(id, tab: .today)
        } catch { store.error = error.localizedDescription }
    }
    private func open(_ id: UUID, tab: MiraTab) {
        guard let project = store.project(id) else { return }
        navigation.tab = tab
        if tab == .today {
            navigation.today = project.todayResumePath
        } else {
            navigation.projects = project.resumePath
        }
    }
    @ViewBuilder private func destination(_ route: MiraRoute) -> some View {
        switch route {
        case .project(let id):
            MiraProjectView(
                store: store, projectID: id, onSheet: { sheet = $0 }, onGenerate: generate,
                onReconnect: reconnect, onCancel: cancel)
        case .todayCards(let id):
            MiraTodayCardsView(
                store: store, projectID: id,
                onMake: { cardID in
                    if store.makeTodayCard(id, cardID: cardID) {
                        if navigation.tab == .today { navigation.today.append(.shooting(id)) }
                        else { navigation.projects.append(.shooting(id)) }
                    }
                },
                onRetry: { retryCard(id, cardID: $0) },
                onChange: { sheet = .askToday(id, $0) },
                onScript: { sheet = .todayScript(id, $0) },
                onBrief: { sheet = .brief(id) },
                onManual: { sheet = .manualIdea(id) },
                onReconnect: { reconnectCards(id, reportError: true) },
                onCancel: { cardID in
                    do {
                        let generation = try service(id, requiresConsent: false)
                        Task { await store.cancelCard(id, cardID: cardID, service: generation) }
                    } catch { store.error = error.localizedDescription }
                })
                .task { reconnectCards(id, reportError: false) }
        case .shooting(let id):
            MiraShootingView(
                store: store, projectID: id, onAsk: { shot in sheet = .ask(id, .reviseShot, shot) })
        }
    }
    private func service(_ id: UUID?, requiresConsent: Bool = true) throws -> any MiraGenerationService {
        try dependencies.generationService(
            for: id.flatMap(store.project), appState: appState, services: services,
            requiresConsent: requiresConsent)
    }
    private func generate(
        _ id: UUID, _ operation: MiraOperation, _ request: String, _ target: UUID?,
        _ language: MiraLanguage?
    ) {
        do {
            store.generate(
                id, operation: operation, request: request, target: target, language: language,
                service: try service(id))
        } catch { store.error = error.localizedDescription }
    }
    private func retryCard(_ id: UUID, cardID: UUID, request: String? = nil, language: MiraLanguage? = nil) {
        do {
            store.retryCard(id, cardID: cardID, request: request, language: language, service: try service(id))
        } catch { store.error = error.localizedDescription }
    }
    private func reconnectCards(_ id: UUID, reportError: Bool) {
        guard store.project(id)?.hasWorkingCards == true else { return }
        do { store.reconnectCards(id, service: try service(id)) }
        catch { if reportError { store.error = error.localizedDescription } }
    }
    private func reconnect(_ id: UUID) {
        do { store.reconnect(id, service: try service(id)) } catch {
            store.error = error.localizedDescription
        }
    }
    private func cancel(_ id: UUID) {
        do {
            let value = try service(id, requiresConsent: false)
            Task { await store.cancel(id, service: value) }
        } catch { store.error = error.localizedDescription }
    }
    private func delete(_ id: UUID) {
        guard store.project(id)?.hasWorkingCards != true else {
            store.error = "Stop the saved card requests from Today before deleting this project."
            return
        }
        if store.project(id)?.job?.state != .working {
            store.delete(id)
            return
        }
        do {
            let value = try service(id, requiresConsent: false)
            Task {
                await store.cancel(id, service: value)
                if store.project(id)?.job?.state != .working {
                    store.delete(id)
                } else {
                    store.error =
                        "Cancellation could not be confirmed. The project is kept so you can reconnect its saved request."
                }
            }
        } catch { store.error = error.localizedDescription }
    }
}

typealias MiraGenerateAction = (UUID, MiraOperation, String, UUID?, MiraLanguage?) -> Void

struct MiraProjectsView: View {
    var store: MiraStore
    var onOpen: (UUID) -> Void
    var onDelete: (UUID) -> Void
    @State private var archived = false
    @State private var deletion: UUID?
    @State private var renaming: UUID?
    @State private var newName = ""
    var body: some View {
        MiraPage {
            Toggle("Show archived projects", isOn: $archived)
            let projects = store.document.projects.filter { $0.archived == archived }.sorted {
                $0.updatedAt > $1.updatedAt
            }
            if projects.isEmpty {
                Text(
                    archived
                        ? "No archived projects." : "Your projects will be here. Start an idea from Today."
                ).foregroundStyle(.secondary)
            }
            ForEach(projects) { project in
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        onOpen(project.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(project.title).font(.headline)
                            Text("\(project.stage.rawValue) · \(project.nextAction)").font(.callout)
                        }
                    }
                    if project.isDemo { Text("Demo example").font(.caption) }
                    Button("Rename") {
                        newName = project.title
                        renaming = project.id
                    }
                    HStack {
                        Button(archived ? "Unarchive" : "Archive") {
                            store.toggleArchive(project.id)
                        }
                        Spacer()
                        Button("Delete", role: .destructive) { deletion = project.id }
                    }
                }
                Divider()
            }
        }.navigationTitle("Projects")
            .alert(
                "Rename project",
                isPresented: Binding(
                    get: { renaming != nil }, set: { if !$0 { renaming = nil } }
                )
            ) {
                TextField("Project name", text: $newName)
                Button("Save name") {
                    let title = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let id = renaming, !title.isEmpty {
                        store.rename(id, to: title)
                    }
                    renaming = nil
                }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .confirmationDialog(
                "Delete this project and its saved revisions?",
                isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete project", role: .destructive) {
                    if let id = deletion { onDelete(id) }
                    deletion = nil
                }
            }
    }
}

struct MiraTodayCardsView: View {
    let store: MiraStore
    let projectID: UUID
    let onMake: (UUID) -> Void
    let onRetry: (UUID) -> Void
    let onChange: (UUID) -> Void
    let onScript: (UUID) -> Void
    let onBrief: () -> Void
    let onManual: () -> Void
    let onReconnect: () -> Void
    let onCancel: (UUID) -> Void
    @State private var page = 0
    @State private var hasShownFirstCard = false

    var body: some View {
        if let project = store.project(projectID), let cards = project.todayCards, !cards.isEmpty {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        MiraPage { cardContent(card, project: project) }.tag(index)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
                HStack(spacing: 10) {
                    ForEach(cards.indices, id: \.self) { index in
                        Button { page = index } label: {
                            Circle().fill(page == index ? MiraTheme.ink : .clear)
                                .overlay { Circle().strokeBorder(MiraTheme.ink, lineWidth: 1.5) }
                                .frame(width: 9, height: 9).frame(width: 44, height: 44)
                        }.buttonStyle(.plain)
                            .accessibilityLabel("Idea \(index + 1) of \(cards.count)")
                            .accessibilityIdentifier("mira.today.page.\(index + 1)")
                            .accessibilityAddTraits(page == index ? .isSelected : [])
                    }
                }
            }
            .background(MiraTheme.paper)
            .navigationTitle("Today's ideas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("More") {
                        let card = cards[page]
                        if card.output?.script != nil { Button("Read script") { onScript(card.id) } }
                        if card.job.state != .working { Button("Ask Mira") { onChange(card.id) } }
                        Button("Brand requirements", action: onBrief)
                        Button("Add my own idea", action: onManual)
                        NavigationLink("More ideas", value: MiraRoute.project(projectID))
                        if card.job.state == .working {
                            Button("Reconnect", action: onReconnect)
                            Button("Stop this idea") { onCancel(card.id) }
                        }
                    }
                }
            }
            .onChange(of: cards.map(\.ready), initial: true) { _, ready in
                guard !hasShownFirstCard, let first = ready.firstIndex(of: true) else { return }
                hasShownFirstCard = true
                if cards[page].job.state == .working { page = first }
            }
        }
    }

    @ViewBuilder private func cardContent(_ card: MiraTodayCard, project: MiraProject) -> some View {
        if let output = card.output, let idea = output.ideas?.first, let board = output.storyboard,
            let script = output.script {
            Text(idea.title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Text(idea.hook).font(.title3)
            ViewThatFits(in: .horizontal) {
                pictures(board)
                ScrollView(.horizontal) { pictures(board) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("About \(idea.filmingMinutes) min to film", systemImage: "clock")
                Label(board.shots.first?.location ?? card.job.input.constraints.location, systemImage: "location")
                Label("\(script.durationSeconds) sec Reel", systemImage: "play.rectangle")
            }.font(.body)
            if card.ready && board.requirementsRevision == project.effectiveBriefRevision {
                Button("Make this one") { onMake(card.id) }.buttonStyle(MiraPrimaryStyle())
            }
        }
        switch card.job.state {
        case .working:
            if let error = card.job.error {
                Text(error).font(.title3)
                Button("Reconnect", action: onReconnect).buttonStyle(MiraPrimaryStyle())
            } else {
                ProgressView("Making this idea…").font(.title3)
            }
        case .failed, .cancelled, .idle:
            Text(card.job.state == .cancelled ? "This idea was stopped." : "This idea did not load.")
                .font(.title3)
            Button("Try again") { onRetry(card.id) }.buttonStyle(MiraPrimaryStyle())
        case .succeeded:
            if card.output?.storyboard?.requirementsRevision != project.effectiveBriefRevision {
                Button("Update this idea") { onRetry(card.id) }.buttonStyle(MiraPrimaryStyle())
            }
            Button("Change something") { onChange(card.id) }.font(.body)
                .frame(minHeight: 44)
        }
    }

    private func pictures(_ board: MiraStoryboard) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(board.shots.enumerated()), id: \.element.id) { index, shot in
                MiraShotPicture(shot: shot, number: index + 1, showSeconds: true)
            }
        }.fixedSize(horizontal: true, vertical: false)
    }
}
