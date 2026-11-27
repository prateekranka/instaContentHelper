import AVFoundation
import SwiftUI
import UIKit

struct MiraRootView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    let dependencies: MiraDependencies
    let colorSchemePreference: ColorScheme?
    private var store: MiraStore { dependencies.store }
    @State private var navigation = MiraNavigation()
    @State private var sheet: MiraSheet?
    @State private var todayRequest = ""
    @State private var todayNeedsAIConsent = false
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
        .tint(MiraTheme.accent)
        .sheet(item: $sheet) { value in
            NavigationStack {
                switch value {
                case .profile:
                    MiraProfileView(
                        store: store,
                        onStepByStep: {
                            sheet = nil
                            open(store.newProject(), tab: .projects)
                        },
                        onDemo: {
                            sheet = nil
                            open(store.addDemo(), tab: .today)
                        })
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
            }
            .tint(MiraTheme.accent)
            .preferredColorScheme(colorSchemePreference)
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
        MiraTodayHome(
            store: store, request: $todayRequest,
            needsAIConsent: todayNeedsAIConsent && services.isLiveSupabaseRuntime && services.aiConsentHasDeclined,
            onMake: makeToday,
            onReviewAIConsent: { services.setAIConsentSheetPresented(true) },
            onContinue: { open($0, tab: .today) },
            onIdeas: { id in
                navigation.tab = .today
                navigation.today = [.todayCards(id)]
            }
        )
        .navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { profileButton } }
    }

    private func makeToday() {
        todayNeedsAIConsent = false
        do {
            let demo = DebugLaunchFlags.forceFixtureUI
            let generation: any MiraGenerationService = demo
                ? MiraFixtureGenerationService(
                    failTodayCard: todayRequest == "Demo card failure",
                    slowTodayCards: todayRequest == "Demo slow cards")
                : try service(nil)
            let id = store.startToday(
                request: todayRequest.trimmingCharacters(in: .whitespacesAndNewlines),
                demo: demo, service: generation)
            todayRequest = ""
            open(id, tab: .today)
        } catch is AIConsentRequired {
            todayNeedsAIConsent = true
        } catch {
            store.error = error.localizedDescription
        }
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
                    if store.makeTodayCard(id, cardID: cardID) { push(.words(id)) }
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
                store: store, projectID: id, onAsk: { shot in sheet = .ask(id, .reviseShot, shot) },
                onDone: { push(.done(id)) }, onWords: { showWords(id) })
        case .words(let id):
            MiraWordsView(
                store: store, projectID: id, onGenerate: generate, onReconnect: reconnect,
                onCancel: cancel, onApproved: { push(.shooting(id)) })
        case .done(let id):
            MiraDoneView(store: store, projectID: id, onWords: { showWords(id) })
        }
    }
    private func push(_ route: MiraRoute) {
        if navigation.tab == .today { navigation.today.append(route) } else { navigation.projects.append(route) }
    }
    private func showWords(_ id: UUID) {
        var path = navigation.tab == .today ? navigation.today : navigation.projects
        while let last = path.last, last == .shooting(id) || last == .done(id) { path.removeLast() }
        if path.last != .words(id) { path.append(.words(id)) }
        if navigation.tab == .today { navigation.today = path } else { navigation.projects = path }
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
                    HStack(spacing: 12) {
                        Button("Rename") {
                            newName = project.title
                            renaming = project.id
                        }
                        Button(archived ? "Unarchive" : "Archive") {
                            store.toggleArchive(project.id)
                        }
                        Spacer()
                        Button("Delete", role: .destructive) { deletion = project.id }
                    }.buttonStyle(.bordered)
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


struct MiraChipFlow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }
    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

struct MiraTodayHome: View {
    let store: MiraStore
    @Binding var request: String
    let needsAIConsent: Bool
    let onMake: () -> Void
    let onReviewAIConsent: () -> Void
    let onContinue: (UUID) -> Void
    let onIdeas: (UUID) -> Void
    @Environment(MiraDependencies.self) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focused: Bool
    @State private var requestFrame = CGRect.null
    @State private var speech: (any MiraSpeechInputService)?
    @State private var spokenBase = ""
    private static let places: [(id: String, label: String, phrase: String)] = [
        ("gym", "Gym", "at the gym"), ("home", "Home", "at home"), ("outside", "Outside", "outside"),
    ]
    private static let times: [(id: String, label: String, phrase: String)] = [
        ("10min", "10 min", "10 minutes"), ("20min", "20 min", "20 minutes"),
    ]

    var body: some View {
        MiraPage {
            VStack(alignment: .leading, spacing: 8) {
                Text(greeting).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                Text("What can you film today?").font(.title2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    TextField(
                        "For example: at the gym, sled push", text: requestInput, axis: .vertical
                    )
                    .lineLimit(2...4).font(.title3)
                    .submitLabel(.done)
                    .onSubmit { focused = false }
                    .focused($focused)
                    .miraFieldBox()
                    .onGeometryChange(for: CGRect.self) { geometry in
                        geometry.frame(in: .named("mira.today.page"))
                    } action: { requestFrame = $0 }
                    .accessibilityLabel("What can you film today?")
                    .accessibilityIdentifier("mira.today.request")
                    microphone
                }
                if let speech, speech.recording {
                    Text("Listening · \(speech.elapsed) of 60 seconds. Tap stop when you finish.")
                        .font(.subheadline).monospacedDigit()
                        .accessibilityAddTraits(.updatesFrequently)
                } else if let error = speech?.error {
                    Text(error).font(.subheadline)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }.buttonStyle(.bordered)
                }
                MiraChipFlow(spacing: 8) {
                    ForEach(Self.places, id: \.id) { chip($0, group: Self.places) }
                    ForEach(Self.times, id: \.id) { chip($0, group: Self.times) }
                }
            }
            if let batch = workingBatch {
                Text("Mira is still making today's ideas.").font(.title3)
                Button("See today's ideas") {
                    speech?.stop()
                    focused = false
                    onIdeas(batch.id)
                }
                .buttonStyle(MiraPrimaryStyle())
                .accessibilityIdentifier("mira.today.open")
            } else {
                Button("Make today's Reel") {
                    speech?.stop()
                    focused = false
                    onMake()
                }
                .buttonStyle(MiraPrimaryStyle())
                .disabled(speech?.recording == true)
                .accessibilityIdentifier("mira.today.make")
            }
            if needsAIConsent {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Allow AI to write ideas first.")
                        .accessibilityIdentifier("mira.today.aiPermissionNeeded")
                    Button("Review AI permission", action: onReviewAIConsent)
                        .buttonStyle(.bordered).controlSize(.large)
                }
            }
            if let project = store.document.continuationProject, project.id != workingBatch?.id {
                Button {
                    onContinue(project.id)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Continue").font(.subheadline).foregroundStyle(MiraTheme.secondaryInk)
                            Text(project.idea?.title ?? project.title).font(.headline)
                                .multilineTextAlignment(.leading)
                            Text(project.nextAction).font(.subheadline)
                                .foregroundStyle(MiraTheme.secondaryInk)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(MiraTheme.ink)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(MiraTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MiraTheme.edge, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mira.today.continue")
            }
        }
        .contentShape(Rectangle())
        .coordinateSpace(.named("mira.today.page"))
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .named("mira.today.page")).onEnded { tap in
                if !requestFrame.contains(tap.location) { focused = false }
            },
            isEnabled: focused)
        .onAppear { if speech == nil { speech = dependencies.makeSpeechInput() } }
        .onDisappear {
            speech?.stop()
            focused = false
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { speech?.stop() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
            speech?.stop()
        }
        .onChange(of: speech?.transcript ?? "") { _, spoken in
            guard speech?.recording == true else { return }
            request = joined(spokenBase, spoken)
        }
    }

    private var requestInput: Binding<String> {
        Binding(get: { request }, set: { value in
            if focused, value.contains("\n") {
                let insertions = value.difference(from: request).insertions
                if insertions.count == 1, case .insert(_, "\n", _)? = insertions.first {
                    focused = false
                    return
                }
            }
            request = value
        })
    }

    private var workingBatch: MiraProject? {
        store.document.projects.first { !$0.archived && $0.hasWorkingCards }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        let name = store.document.profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "\(part)." : "\(part), \(name)."
    }

    private var microphone: some View {
        let recording = speech?.recording == true
        return Button {
            guard let speech else { return }
            if speech.recording {
                speech.stop()
            } else {
                focused = false
                spokenBase = request
                let locale = store.document.profile.language == .english ? "en-IN" : "hi-IN"
                Task { await speech.start(locale: locale) }
            }
        } label: {
            Image(systemName: recording ? "stop.fill" : "mic.fill")
                .font(.title2.weight(.semibold))
                .frame(width: 60, height: 60)
                .foregroundStyle(MiraTheme.paper)
                .background(MiraTheme.accent, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(speech?.requesting == true)
        .accessibilityLabel(recording ? "Stop listening" : "Speak instead of typing")
        .accessibilityIdentifier("mira.today.mic")
    }

    private func chip(
        _ item: (id: String, label: String, phrase: String),
        group: [(id: String, label: String, phrase: String)]
    ) -> some View {
        let selected = contains(item.phrase)
        return Button {
            toggle(item.phrase, group: group.map(\.phrase))
        } label: {
            Text(item.label).font(.body.weight(.semibold))
                .padding(.horizontal, 16).frame(minHeight: 44)
                .foregroundStyle(selected ? MiraTheme.paper : MiraTheme.ink)
                .background(selected ? MiraTheme.ink : MiraTheme.field, in: Capsule())
                .overlay(Capsule().strokeBorder(MiraTheme.edge, lineWidth: selected ? 0 : 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(speech?.recording == true)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("mira.today.chip.\(item.id)")
    }

    private func contains(_ phrase: String) -> Bool {
        request.range(of: phrase, options: .caseInsensitive) != nil
    }

    private func toggle(_ phrase: String, group: [String]) {
        let wasOn = contains(phrase)
        var text = request
        for item in group { text = removing(item, from: text) }
        if !wasOn { text = joined(text, phrase) }
        request = text
    }

    private func removing(_ phrase: String, from text: String) -> String {
        var value = text
        for pattern in [", " + phrase, phrase + ", ", phrase] {
            if let range = value.range(of: pattern, options: .caseInsensitive) {
                value.removeSubrange(range)
                break
            }
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
    }

    private func joined(_ base: String, _ addition: String) -> String {
        let start = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = addition.trimmingCharacters(in: .whitespacesAndNewlines)
        if start.isEmpty { return end.prefix(1).uppercased() + end.dropFirst() }
        if end.isEmpty { return start }
        let separator = start.hasSuffix(".") || start.hasSuffix(",") ? " " : ", "
        return start + separator + end
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: Int? = 0
    @State private var hasShownFirstCard = false

    var body: some View {
        if let project = store.project(projectID), let cards = project.todayCards, !cards.isEmpty {
            let current = min(max(position ?? 0, 0), cards.count - 1)
            VStack(spacing: 12) {
                pager(cards, current: current)
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 20) {
                                    cardContent(card, project: project, index: index, count: cards.count)
                                }
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .scrollIndicators(.hidden)
                            .background(MiraTheme.surface, in: RoundedRectangle(cornerRadius: 24))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24).strokeBorder(MiraTheme.edge, lineWidth: 1)
                            )
                            .containerRelativeFrame(.horizontal) { width, _ in min(width - 56, 640) }
                            .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $position)
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollIndicators(.hidden)
            }
            .padding(.vertical, 12)
            .background(MiraTheme.paper)
            .foregroundStyle(MiraTheme.ink)
            .navigationTitle("Today's ideas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("More") {
                        let card = cards[current]
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
            .sensoryFeedback(.success, trigger: cards.contains(where: \.ready)) { old, new in !old && new }
            .onChange(of: cards.map(\.ready), initial: true) { _, ready in
                guard !hasShownFirstCard, let first = ready.firstIndex(of: true) else { return }
                hasShownFirstCard = true
                if cards[current].job.state == .working { go(to: first) }
            }
        }
    }

    private func go(to index: Int) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1)) { position = index }
    }

    private func status(_ card: MiraTodayCard) -> (symbol: String, word: String) {
        switch card.job.state {
        case .succeeded where card.ready: ("checkmark.circle.fill", "ready")
        case .working where store.isWaitingToStart(card.job.id): ("clock", "waiting to start")
        case .working: ("hourglass", "Mira is making it")
        case .failed, .cancelled, .idle: ("exclamationmark.circle", "did not load")
        case .succeeded: ("checkmark.circle", "needs an update")
        }
    }

    private func pager(_ cards: [MiraTodayCard], current: Int) -> some View {
        VStack(spacing: 8) {
            MiraChipFlow(spacing: 8) {
                ForEach(cards.indices, id: \.self) { index in
                    let selected = current == index
                    let state = status(cards[index])
                    Button {
                        go(to: index)
                    } label: {
                        Label("Idea \(index + 1)", systemImage: state.symbol)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .foregroundStyle(selected ? MiraTheme.paper : MiraTheme.ink)
                            .background(selected ? MiraTheme.ink : MiraTheme.field, in: Capsule())
                            .overlay(Capsule().strokeBorder(MiraTheme.edge, lineWidth: selected ? 0 : 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Idea \(index + 1) of \(cards.count), \(state.word)")
                    .accessibilityIdentifier("mira.today.page.\(index + 1)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            HStack(spacing: 6) {
                Text("\(current + 1) of \(cards.count)").monospacedDigit()
                if cards.contains(where: { $0.job.state == .working && !store.isWaitingToStart($0.job.id) }) {
                    Text("·").accessibilityHidden(true)
                    Text("About 1 minute")
                }
            }
            .font(.subheadline).foregroundStyle(MiraTheme.secondaryInk)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private func cardContent(
        _ card: MiraTodayCard, project: MiraProject, index: Int, count: Int
    ) -> some View {
        if let output = card.output, let idea = output.ideas?.first, let board = output.storyboard,
            let script = output.script {
            Text(idea.title).font(.title.bold()).accessibilityAddTraits(.isHeader)
            Text(idea.hook).font(.title3)
            ViewThatFits(in: .horizontal) {
                pictures(board)
                ScrollView(.horizontal) { pictures(board) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("About \(idea.filmingMinutes) min to film", systemImage: "clock")
                Label(board.shots.first?.location ?? card.job.input.constraints.location, systemImage: "location")
                Label("\(script.durationSeconds) sec Reel", systemImage: "play.rectangle")
            }.font(.body).monospacedDigit()
            if card.ready && board.requirementsRevision == project.effectiveBriefRevision {
                Button("Make this one") { onMake(card.id) }.buttonStyle(MiraPrimaryStyle())
                    .accessibilityIdentifier("mira.today.makeCard.\(index + 1)")
            }
        } else if card.job.state == .working && card.job.error == nil && !store.isWaitingToStart(card.job.id) {
            placeholder(index: index, count: count)
        }
        switch card.job.state {
        case .working:
            if store.isWaitingToStart(card.job.id) {
                Text("Waiting to start…").font(.title2.weight(.semibold))
                    .accessibilityIdentifier("mira.today.waiting.\(index + 1)")
                Text("Mira starts this idea when another one is done.").font(.title3)
            } else if let error = card.job.error {
                Text(error).font(.title3)
                Button("Reconnect", action: onReconnect).buttonStyle(MiraPrimaryStyle())
            } else if card.output != nil {
                Text("Mira is making a new version. About 1 minute.").font(.title3)
            }
        case .failed, .cancelled, .idle:
            Text(card.job.state == .cancelled ? "This idea was stopped." : "This idea did not load.")
                .font(.title3)
            Button("Try again") { onRetry(card.id) }.buttonStyle(MiraPrimaryStyle())
        case .succeeded:
            if card.output?.storyboard?.requirementsRevision != project.effectiveBriefRevision {
                Button("Update this idea") { onRetry(card.id) }.buttonStyle(MiraPrimaryStyle())
            }
            Button("Change something") { onChange(card.id) }
                .buttonStyle(.bordered).controlSize(.large)
        }
    }

    private func placeholder(index: Int, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Mira is making idea \(index + 1) of \(count)").font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 8).fill(MiraTheme.edge.opacity(0.25))
                    .frame(height: 30).frame(maxWidth: 260)
                RoundedRectangle(cornerRadius: 8).fill(MiraTheme.edge.opacity(0.18)).frame(height: 18)
                RoundedRectangle(cornerRadius: 8).fill(MiraTheme.edge.opacity(0.18))
                    .frame(height: 18).frame(maxWidth: 200)
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12).fill(MiraTheme.edge.opacity(0.15))
                            .frame(width: 84, height: 120)
                    }
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                step("Finding an idea", symbol: "arrow.right.circle.fill", state: "now")
                step("Writing your words", symbol: "circle", state: "next")
                step("Planning 3 shots", symbol: "circle", state: "next")
            }
            Text("About 1 minute. You can wait here or look at the other ideas.")
                .font(.subheadline).foregroundStyle(MiraTheme.secondaryInk)
        }
    }

    private func step(_ title: String, symbol: String, state: String) -> some View {
        Label(title, systemImage: symbol).font(.body.weight(state == "now" ? .semibold : .regular))
            .foregroundStyle(state == "now" ? MiraTheme.ink : MiraTheme.secondaryInk)
            .accessibilityLabel("\(title), \(state)")
    }

    private func pictures(_ board: MiraStoryboard) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(board.shots.enumerated()), id: \.element.id) { index, shot in
                MiraShotPicture(shot: shot, number: index + 1, showSeconds: true)
            }
        }.fixedSize(horizontal: true, vertical: false)
    }
}
