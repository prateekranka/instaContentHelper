import SwiftUI

struct MiraRootView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = MiraStore()
    @State private var todayPath: [MiraRoute] = []
    @State private var projectsPath: [MiraRoute] = []
    @State private var sheet: MiraSheet?
    @ScaledMetric private var bodySize = 18.0
    var body: some View {
        Group {
            if store.loaded {
                TabView {
                    NavigationStack(path: $todayPath) {
                        today.navigationDestination(for: MiraRoute.self, destination: destination)
                    }.tabItem { Label("Today", systemImage: "sun.max") }
                    NavigationStack(path: $projectsPath) {
                        MiraProjectsView(store: store, onDelete: delete).navigationDestination(
                            for: MiraRoute.self, destination: destination
                        )
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { profileButton } }
                    }.tabItem { Label("Projects", systemImage: "book.closed") }
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
                case .brief(let id): MiraBriefView(store: store, projectID: id, onGenerate: generate)
                case .manualIdea(let id): MiraManualIdeaView(store: store, projectID: id)
                }
            }.tint(MiraTheme.olive)
        }
        .aiConsentSheet()
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
                Text(message).font(.callout).padding().frame(maxWidth: .infinity).background(MiraTheme.paper)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .task {
            await store.load()
            if let id = store.document.position.projectID, store.project(id) != nil {
                todayPath = [.project(id)]
                if store.document.position.screen == "shooting" { todayPath.append(.shooting(id)) }
            }
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
                todayPath.append(.project(id))
            }.buttonStyle(MiraPrimaryStyle()).accessibilityIdentifier("mira.new-project")
            if let project = store.document.projects.filter({ !$0.archived && $0.stage != .complete }).sorted(
                by: { $0.updatedAt > $1.updatedAt }).first
            {
                Divider()
                MiraSectionTitle(text: "Pick up where you left off")
                Text(project.title).font(.headline)
                Text("\(project.stage.rawValue) · Next: \(project.nextAction)").foregroundStyle(.secondary)
                NavigationLink("Continue", value: MiraRoute.project(project.id))
            }
            Divider()
            Button {
                let id = store.newProject()
                todayPath.append(.project(id))
                sheet = .ask(id, .ideas, nil)
            } label: {
                Label("Ask Mira", systemImage: "text.bubble")
            }
            Button("Try Mamta’s demo notebook") {
                let id = store.addDemo()
                todayPath.append(.project(id))
            }.font(.callout)
            Text("Demo projects use labelled example content. Your personal profile starts empty.").font(
                .footnote
            ).foregroundStyle(.secondary)
        }.navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { profileButton } }
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
    private func service(_ id: UUID) throws -> any MiraGenerationService {
        if store.project(id)?.isDemo == true { return MiraFixtureGenerationService() }
        guard case .live(let session) = appState.runtime.mode else {
            throw MiraError.invalid(
                "Connect your account from Profile to use live generation. You can still write manually and open saved work."
            )
        }
        try services.requireAIConsent(for: .planIdeas)
        return MiraSupabaseGenerationService(session: session)
    }
    private func generate(
        _ id: UUID, _ operation: MiraOperation, _ request: String, _ target: UUID?, _ language: MiraLanguage?
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
            let value = try service(id)
            Task { await store.cancel(id, service: value) }
        } catch { store.error = error.localizedDescription }
    }
    private func delete(_ id: UUID) {
        if store.project(id)?.job?.state != .working {
            store.delete(id)
            return
        }
        do {
            let value = try service(id)
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
    var onDelete: (UUID) -> Void
    @State private var archived = false
    @State private var deletion: UUID?
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
                    NavigationLink(value: MiraRoute.project(project.id)) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(project.title).font(.headline)
                            Text("\(project.stage.rawValue) · \(project.nextAction)").font(.callout)
                        }
                    }
                    if project.isDemo { Text("Demo example").font(.caption) }
                    HStack {
                        Button(archived ? "Unarchive" : "Archive") {
                            store.update(project.id) {
                                $0.archived.toggle()
                                $0.updatedAt = Date()
                            }
                        }
                        Spacer()
                        Button("Delete", role: .destructive) { deletion = project.id }
                    }
                }
                Divider()
            }
        }.navigationTitle("Projects")
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
