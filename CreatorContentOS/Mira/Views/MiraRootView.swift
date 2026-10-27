import SwiftUI

struct MiraRootView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    let dependencies: MiraDependencies
    private var store: MiraStore { dependencies.store }
    @State private var navigation = MiraNavigation()
    @State private var sheet: MiraSheet?
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
            Text(
                store.document.profile.name.isEmpty
                    ? "A little space to create." : "Hello, \(store.document.profile.name)."
            ).font(.system(.largeTitle, design: .serif))
            Text("An idea that feels like you. Words you can say. A plan you can film yourself.")
            Button("What should I post today?") {
                let id = store.newProject()
                open(id, tab: .today)
            }.buttonStyle(MiraPrimaryStyle()).accessibilityIdentifier("mira.new-project")
            if let project = store.document.continuationProject {
                Divider()
                MiraSectionTitle(text: "Pick up where you left off")
                Text(project.title).font(.headline)
                Text("\(project.stage.rawValue) · Next: \(project.nextAction)").foregroundStyle(.secondary)
                Button("Continue") { open(project.id, tab: .today) }
            }
            Divider()
            Button {
                let id = store.newProject()
                open(id, tab: .today)
                sheet = .ask(id, .ideas, nil)
            } label: {
                Label("Ask Mira", systemImage: "text.bubble")
            }
            Button("Try Mamta’s demo notebook") {
                let id = store.addDemo()
                open(id, tab: .today)
            }.font(.callout)
            Text("Demo projects use labelled example content. Your personal profile starts empty.").font(
                .footnote
            ).foregroundStyle(.secondary)
        }.navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { profileButton } }
    }
    private func open(_ id: UUID, tab: MiraTab) {
        guard let project = store.project(id) else { return }
        navigation.tab = tab
        if tab == .today {
            navigation.today = project.resumePath
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
        case .shooting(let id):
            MiraShootingView(
                store: store, projectID: id, onAsk: { shot in sheet = .ask(id, .reviseShot, shot) })
        }
    }
    private func service(_ id: UUID, requiresConsent: Bool = true) throws -> any MiraGenerationService {
        try dependencies.generationService(
            for: store.project(id), appState: appState, services: services,
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
