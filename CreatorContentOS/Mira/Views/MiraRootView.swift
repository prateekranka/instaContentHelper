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
    @State private var sheet: MiraSheet?
    @State private var todayRequest = ""
    @State private var todayNeedsAIConsent = false
    @State private var legacyRequest = ""
    @State private var stepByStepProject: UUID?
    @State private var e2EntryTask: Task<Void, Never>?
    @State private var dealNeedsAIConsent = false
    @State private var sharedBriefWaiting = false
    @State private var checkingSharedBriefs = false
    var body: some View {
        libraryContent
        .tint(MiraTheme.accent)
        .environment(\.miraPictureUnavailable, { id, boardID, shotID, url in
            guard let project = store.project(id), let generation = try? service(id) else { return }
            store.refreshPicture(in: project, boardID: boardID, shotID: shotID, url: url, service: generation)
        })
        .sheet(item: $sheet) { value in
            NavigationStack {
                switch value {
                case .profile:
                    MiraProfileView(
                        store: store,
                        onStepByStep: {
                            sheet = nil
                            let id = store.newProject()
                            stepByStepProject = id
                            open(id, tab: .myBrand)
                        },
                        onDemo: {
                            sheet = nil
                            open(store.addDemo(), tab: .home)
                        })
                case .compareIdeas(let id):
                    MiraTodayHome(
                        store: store, request: $legacyRequest, blockedConsent: nil,
                        onMake: { makeLegacyIdeas(id) }, onReviewAIConsent: {},
                        onContinue: { _ in }, legacyEntry: true)
                        .navigationTitle("Compare three ideas").navigationBarTitleDisplayMode(.inline)
                case .instagramResults(let prompt):
                    MiraPage {
                        Text("Use your Instagram results to pick ideas")
                            .font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("mira.instagramResults.question")
                        Text("If you allow this, Mira can share your Instagram results with its AI providers when it makes your brand doc or picks an idea.")
                        Button("Allow") { chooseInstagramResults(true, prompt: prompt) }
                            .buttonStyle(MiraPrimaryStyle())
                            .accessibilityIdentifier("mira.instagramResults.allow")
                        Button("Not now") { chooseInstagramResults(false, prompt: prompt) }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("mira.instagramResults.notNow")
                    }
                case .ask(let id, let operation, let target, let request):
                    MiraAskView(
                        store: store, projectID: id, operation: operation, target: target,
                        onGenerate: generate, initialRequest: request)
                case .adjustIdea(let id, let ideaID):
                    MiraAskView(
                        store: store, projectID: id, operation: .ideas,
                        onGenerate: generate,
                        contextIdea: store.project(id)?.ideas.first { $0.id == ideaID })
                case .askToday(let id, let cardID, let request):
                    if let card = store.project(id)?.todayCards?.first(where: { $0.id == cardID }) {
                        MiraAskView(
                            store: store, projectID: id, operation: .todayIdea,
                            onGenerate: { _, _, request, _, language in
                                let context = card.output?.ideas?.first.map { "Change this idea: \($0.title). " } ?? ""
                                retryCard(id, cardID: cardID, request: context + request, language: language)
                            }, contextIdea: card.output?.ideas?.first, initialRequest: request)
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
                case .dealDraft(let text):
                    MiraDealDraftView(text: text) { request in
                        let id = store.newProject(briefText: request)
                        open(id, tab: .myBrand)
                        sheet = nil
                    }
                case .deal(let id):
                    MiraDealDetailView(store: store, id: id)
                        .toolbar { Button("Close") { sheet = nil } }
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
                get: { store.library.alert != nil }, set: { if !$0 { store.dismissError() } })
        ) {
            Button("OK") { store.dismissError() }
        } message: {
            Text(store.library.alert ?? "")
        }
        .safeAreaInset(edge: .bottom) {
            if case .loaded(let message?, _) = store.library {
                Text(message).font(.callout).padding().frame(maxWidth: .infinity).background(
                    MiraTheme.paper
                )
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .task { await loadLibrary() }
        .onChange(of: liveSession?.deviceToken) { _, _ in
            e2EntryTask?.cancel()
            if case .instagramResults = sheet { sheet = nil }
            store.resetE2Session()
        }
        .onChange(of: scenePhase) { _, phase in
            Task {
                if phase == .active { await checkSharedBriefs(openDeals: true) }
                else { await store.flush() }
            }
        }
    }
    @ViewBuilder private var libraryContent: some View {
        switch store.library {
        case .loaded:
            libraryTabs
        case .unopened, .opening:
            MiraPage {
                Text("Mira").font(.largeTitle)
                ProgressView("Opening your notebook")
            }
        case .openFailed(let failure):
            MiraPage {
                Text("Mira").font(.largeTitle)
                Text(failure.message)
                if failure == .newerVersion {
                    Text(store.library.nextAction.title)
                } else {
                    Button(store.library.nextAction.title) { Task { await loadLibrary() } }
                }
            }
        }
    }

    private var libraryTabs: some View {
        let selection = Binding<MiraMainTab>(
            get: { store.location.tab }, set: { store.navigate(.selectTab($0)) })
        return TabView(selection: selection) {
            NavigationStack(path: tabPath(.home)) {
                home.navigationDestination(for: MiraRoute.self) { destination($0, tab: .home) }
            }.tabItem { Label("Home", systemImage: "house") }.tag(MiraMainTab.home)
            NavigationStack {
                MiraDealsView(
                    store: store, sharedBriefWaiting: sharedBriefWaiting,
                    needsConsent: services.isLiveSupabaseRuntime && services.aiConsent != .allowed
                        && (dealNeedsAIConsent || store.dealBriefState.record?.job != nil),
                    onRead: readDealBrief, onReviewConsent: { services.setAIConsentSheetPresented(true) },
                    onConfirm: confirmDeal, onOpen: { sheet = .deal($0) })
                .navigationTitle("Deals").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { profileButton } }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    askBar("Paste a brand brief", send: { sheet = .dealDraft($0) })
                }
                .modifier(MiraInputScope())
            }.tabItem { Label("Deals", systemImage: "briefcase") }.tag(MiraMainTab.deals)
            NavigationStack(path: tabPath(.myBrand)) {
                MiraMyBrandView(
                    store: store, onProfile: { sheet = .profile }, onBrief: { sheet = .brief($0) },
                    onOpen: { open($0, tab: .myBrand) }, onDelete: delete,
                    onStartBrand: { beginE2(.interview) }, onGenerateBrand: { beginE2(.brandDoc) })
                .navigationDestination(for: MiraRoute.self) { destination($0, tab: .myBrand) }
                .toolbar { ToolbarItem(placement: .topBarTrailing) { profileButton } }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    askBar("Ask Mira for a Reel idea", send: { startFromAsk($0) })
                }
                .modifier(MiraInputScope())
            }.tabItem { Label("My Brand", systemImage: "person.crop.rectangle") }.tag(MiraMainTab.myBrand)
        }
        .environment(\.miraTabBarClearance, 64)
    }

    private func tabPath(_ tab: MiraMainTab) -> Binding<[MiraRoute]> {
        Binding(get: { store.location.path(tab) }, set: { store.navigate(.setPath(tab, $0)) })
    }

    private func askBar(_ placeholder: String, enabled: Bool = true, send: @escaping (String) -> Void) -> some View {
        MiraAskBar(placeholder: placeholder, language: store.document.profile.language, enabled: enabled, onSend: send)
    }

    private func startFromAsk(_ text: String) {
        store.navigate(.open(.home, []))
        todayRequest = text
        beginE2(.pick(text))
    }

    @ViewBuilder private var profileButton: some View {
        let button = Button {
            sheet = .profile
        } label: {
            Label("Profile", systemImage: "person.crop.circle")
        }
        if DebugLaunchFlags.forceFixtureUI, DebugLaunchConfiguration.fixtureSession != nil {
            button.accessibilityIdentifier("mira.fixture.profile")
        } else {
            button
        }
    }
    private var home: some View {
        MiraTodayHome(
            store: store, request: $todayRequest,
            blockedConsent: todayNeedsAIConsent && services.isLiveSupabaseRuntime ? services.aiConsent : nil,
            onMake: { beginE2(.pick(todayRequest)) },
            onReviewAIConsent: { services.setAIConsentSheetPresented(true) },
            onContinue: { store.continueReel($0) },
            onOpenDeal: { id in
                store.navigate(.selectTab(.deals))
                sheet = .deal(id)
            },
            onMakePick: { store.makePick() },
            onAnother: { beginE2(.pick("")) },
            checkingInstagram: e2EntryTask != nil
        )
        .navigationTitle("Home").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { profileButton } }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            askBar("Ask Mira for a Reel idea", send: { startFromAsk($0) })
        }
        .modifier(MiraInputScope())
    }

    private func loadLibrary() async {
        await store.load()
        await checkSharedBriefs(openDeals: true)
    }

    private func checkSharedBriefs(openDeals: Bool) async {
        guard case .loaded = store.library, !checkingSharedBriefs else { return }
        let fixtureText = DebugLaunchConfiguration.value(for: "MCO_QA_SHARE_BRIEF")
        if DebugLaunchFlags.forceFixtureUI && fixtureText == nil { return }
        checkingSharedBriefs = true
        defer { checkingSharedBriefs = false }
        do {
            var items = try MiraSharedBriefInbox.pending(matching: DebugLaunchFlags.forceFixtureUI ? fixtureText : nil)
            let imported = Set(store.deals.map(\.id) + [store.dealBriefState.record?.id].compactMap { $0 })
            let duplicates = items.filter { imported.contains($0.id) }
            if !duplicates.isEmpty, await store.flush() {
                for item in duplicates { try MiraSharedBriefInbox.markImported(item.id) }
            }
            items.removeAll { imported.contains($0.id) }
            guard let next = items.first else {
                sharedBriefWaiting = false
                return
            }
            if openDeals { store.navigate(.selectTab(.deals)) }
            guard store.beginDealBrief(id: next.id, text: next.text) else {
                sharedBriefWaiting = true
                return
            }
            sharedBriefWaiting = items.count > 1
            if await store.flush() { try MiraSharedBriefInbox.markImported(next.id) }
        } catch {
            if store.location.tab == .deals {
                store.reportError("Could not open shared briefs. You can still paste a brief in Deals.")
            }
        }
    }

    private func readDealBrief() {
        dealNeedsAIConsent = false
        do {
            if DebugLaunchFlags.forceFixtureUI, DebugLaunchConfiguration.fixtureSession != nil {
                store.readDealBrief(using: MiraDealFixtureService())
                return
            }
            let reconnecting = store.dealBriefState.record?.job != nil
            guard let generation = try service(nil, requiresConsent: !reconnecting) as? any MiraDealBriefService else {
                throw MiraError.invalid("Mira could not open the brief reader. Your text is still here.")
            }
            store.readDealBrief(using: generation)
        } catch is AIConsentRequired {
            dealNeedsAIConsent = true
        } catch {
            store.reportError(error.localizedDescription)
        }
    }

    private func confirmDeal() {
        guard let id = store.confirmDeal() else { return }
        sheet = .deal(id)
        Task { await checkSharedBriefs(openDeals: false) }
    }

    private var liveSession: PairedDeviceSession? {
        if case .live(let session) = appState.runtime.mode { return session }
        return nil
    }

    private var instagramCreatorID: UUID? {
        DebugLaunchFlags.forceFixtureUI
            ? UUID(uuidString: "E2000000-0000-4000-8000-000000000001")
            : liveSession?.creatorID
    }

    private var instagramPermissionOverride: String? {
        #if DEBUG
        return DebugLaunchConfiguration.value(for: "MCO_QA_INSTAGRAM_RESULTS")
        #else
        return nil
        #endif
    }

    private func instagramPermission(for creatorID: UUID) -> Bool? {
        switch instagramPermissionOverride {
        case "ask": return nil
        case "allow": return true
        case "not-now": return false
        default: break
        }
        guard let permission = store.document.instagramResultsPermission, permission.creatorID == creatorID else {
            return nil
        }
        return permission.allowed
    }

    private func instagramState(session: PairedDeviceSession?) async -> InstagramInsightsState? {
        #if DEBUG
        if DebugLaunchFlags.forceFixtureUI {
            return InstagramInsightsFixture.state(for: DebugLaunchFlags.insightsScenario ?? "notconnected")
        }
        #endif
        guard let session else { return nil }
        return try? await MiraSupabaseInsightsService(session: session).fetchInsights()
    }

    private func beginE2(_ action: MiraE2Action) {
        guard e2EntryTask == nil else { return }
        if case .interview = action {
            guard store.brandInterview == .idle else { return }
        }
        if case .pick = action, case .working = store.pickState { return }
        todayNeedsAIConsent = false
        let session = liveSession
        guard let creatorID = instagramCreatorID else {
            performE2(action, report: nil)
            return
        }
        let permission = instagramPermission(for: creatorID)
        guard permission == true || (permission == nil && action.asksInstagramPermission) else {
            performE2(action, report: nil)
            return
        }
        e2EntryTask = Task {
            defer { e2EntryTask = nil }
            let state = await instagramState(session: session)
            guard !Task.isCancelled, session?.deviceToken == liveSession?.deviceToken else { return }
            let report: InstagramInsightsReport?
            if case .ready(let value) = state, value.source == .api { report = value }
            else { report = nil }
            if permission == nil, let state, state != .notConnected {
                sheet = .instagramResults(.init(action: action, creatorID: creatorID, report: report))
            } else {
                performE2(action, report: permission == true ? report : nil)
            }
        }
    }

    private func chooseInstagramResults(_ allowed: Bool, prompt: MiraInstagramResultsPrompt) {
        sheet = nil
        guard prompt.creatorID == instagramCreatorID else { return }
        if instagramPermissionOverride == nil {
            store.saveInstagramResultsPermission(allowed, creatorID: prompt.creatorID)
        }
        performE2(prompt.action, report: allowed ? prompt.report : nil)
    }

    private func performE2(_ action: MiraE2Action, report: InstagramInsightsReport?) {
        if case .interview = action {
            store.sendBrandInterview(.start)
            return
        }
        do {
            let demo = DebugLaunchFlags.forceFixtureUI
            let fixtureRequest: String
            if case .pick(let text) = action {
                fixtureRequest = text.isEmpty ? store.pickState.request ?? "" : text
            } else {
                fixtureRequest = ""
            }
            let generation: any MiraGenerationService = demo ? fixtureGeneration(fixtureRequest) : try service(nil)
            switch action {
            case .interview: break
            case .brandDoc:
                let followers = report?.headline.first { $0.id == "followers" }.flatMap { metric in
                    Int(metric.value.replacingOccurrences(of: ",", with: ""))
                }
                store.generateBrandDocument(instagram: followers.flatMap { $0 >= 0 ? .init(followers: $0) : nil }, service: generation)
            case .pick(let text):
                let pattern = report?.nudge.map { MiraBrandDocument.trimmed($0) }
                store.startPick(request: MiraBrandDocument.trimmed(text), demo: demo,
                                patterns: pattern.flatMap { MiraBrandDocument.validLine($0) ? [$0] : nil },
                                service: generation)
                todayRequest = ""
            }
        } catch is AIConsentRequired {
            if case .pick = action { todayNeedsAIConsent = true }
            else { services.setAIConsentSheetPresented(true) }
        } catch {
            store.reportError(error.localizedDescription)
        }
    }

    private func makeLegacyIdeas(_ projectID: UUID) {
        do {
            let demo = DebugLaunchFlags.forceFixtureUI
            let request = MiraBrandDocument.trimmed(legacyRequest)
            let generation: any MiraGenerationService = demo ? fixtureGeneration(request) : try service(nil)
            let id = store.startToday(request: request, demo: demo, projectID: projectID, service: generation)
            legacyRequest = ""
            sheet = nil
            open(id, tab: .home)
        } catch is AIConsentRequired {
            sheet = nil
            todayNeedsAIConsent = true
        } catch {
            store.reportError(error.localizedDescription)
        }
    }
    private func fixtureGeneration(_ request: String) -> any MiraGenerationService {
        if let fixture = MiraDependencies.todayFixture(for: request) { return fixture }
        return MiraDependencies.fixtureGeneration(
            failTodayCard: request == "Demo card failure", slowTodayCards: request == "Demo slow cards")
    }
    private func open(_ id: UUID, tab: MiraMainTab) {
        store.open(id, tab: tab)
    }
    @ViewBuilder private func destination(_ route: MiraRoute, tab: MiraMainTab) -> some View {
        switch route {
        case .project(let id):
            MiraProjectView(
                store: store, projectID: id, tab: tab, onSheet: { sheet = $0 }, onGenerate: generate,
                onReconnect: reconnect, onCancel: cancel)
                .task(id: store.project(id)?.storyboard?.id) { watchPictures(id) }
                .toolbar {
                    if stepByStepProject == id, let project = store.project(id),
                        project.ideas.isEmpty, project.todayCards == nil, project.job == nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Compare three ideas", systemImage: "rectangle.on.rectangle") {
                                sheet = .compareIdeas(id)
                            }.accessibilityIdentifier("mira.project.compareIdeas")
                        }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let project = store.project(id) {
                        editorAskBar(project, tab: tab)
                    }
                }
                .modifier(MiraInputScope())
        case .todayCards(let id):
            MiraTodayCardsView(
                store: store, projectID: id,
                onMake: { cardID in
                    if store.makeTodayCard(id, cardID: cardID) { push(.words(id)) }
                },
                onRetry: { retryCard(id, cardID: $0) },
                onChange: { card, request in sheet = .askToday(id, card, note: request) },
                onScript: { sheet = .todayScript(id, $0) },
                onBrief: { sheet = .brief(id) },
                onManual: { sheet = .manualIdea(id) },
                onReconnect: { reconnectCards(id, reportError: true) },
                onCancel: { cardID in
                    do {
                        let generation = try service(id, requiresConsent: false)
                        Task { await store.cancelCard(id, cardID: cardID, service: generation) }
                    } catch { store.reportError(error.localizedDescription) }
                })
                .task { reconnectCards(id, reportError: false) }
        case .shooting(let id):
            MiraShootingView(
                store: store, projectID: id, tab: tab, onAsk: { shot in sheet = .ask(id, .reviseShot, shot) },
                onDone: { push(.done(id)) }, onWords: { showWords(id) })
                .task(id: store.project(id)?.storyboard?.id) { watchPictures(id) }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let project = store.project(id), project.canFilm, let board = project.storyboard, !board.shots.isEmpty {
                        let index = min(max(0, project.shotIndex), board.shots.count - 1)
                        let shot = board.shots[index]
                        askBar("Ask Mira to change a shot") { sheet = .ask(id, .reviseShot, shot.id, note: $0) }
                            .id(shot.id)
                    }
                }
                .modifier(MiraInputScope())
        case .words(let id):
            MiraWordsView(
                store: store, projectID: id,
                onEvent: { event in
                    store.sendWords(id, event, service: { try service(id, requiresConsent: $0) })
                })
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    let state = store.project(id).map { store.wordsState($0) }
                    askBar("Ask Mira to change the words", enabled: state?.handle(.change) != nil
                           || state?.handle(.note("")) != nil) { text in
                        store.sendWords(id, .change, service: { try service(id, requiresConsent: $0) })
                        store.sendWords(id, .note(text), service: { try service(id, requiresConsent: $0) })
                    }
                }
                .modifier(MiraInputScope())
        case .done(let id):
            MiraDoneView(store: store, projectID: id, onWords: { showWords(id) })
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    askBar("Ask Mira to change the plan") { sheet = .ask(id, .reviseStoryboard, nil, note: $0) }
                }
                .modifier(MiraInputScope())
        }
    }
    private func editorAskBar(_ project: MiraProject, tab: MiraMainTab) -> some View {
        let section = store.editorScreen(project, tab: tab)
        let placeholder = section == .shots ? "Ask Mira to change a shot"
            : project.script == nil ? "Ask Mira about this Reel" : "Ask Mira to change the words"
        return askBar(placeholder) { request in
            switch section {
            case .shots:
                sheet = .ask(project.id, .reviseStoryboard, nil, note: request)
            default:
                if project.script != nil {
                    sheet = .ask(project.id, .reviseScript, nil, note: request)
                } else if project.selectedIdeaID != nil {
                    sheet = .ask(project.id, .script, nil, note: request)
                } else {
                    store.update(project.id) {
                        $0.request = request
                        $0.touch()
                    }
                }
            }
        }.id(section)
    }

    private func push(_ route: MiraRoute) {
        store.navigate(.push(MiraLocation(route)))
    }
    private func watchPictures(_ id: UUID) {
        guard let project = store.project(id), let boardID = project.storyboard?.id,
            project.shotPictureSources?[boardID] != nil, let generation = try? service(id)
        else { return }
        store.watchPictures(in: project, boardID: boardID, service: generation)
    }
    private func showWords(_ id: UUID) {
        store.navigate(.showWords(id))
    }
    private func service(_ id: UUID?, requiresConsent: Bool = true) throws -> any MiraGenerationService {
        try dependencies.generationService(
            for: id.flatMap(store.project), appState: appState,
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
        } catch { store.reportError(error.localizedDescription) }
    }
    private func retryCard(_ id: UUID, cardID: UUID, request: String? = nil, language: MiraLanguage? = nil) {
        do {
            store.retryCard(id, cardID: cardID, request: request, language: language,
                            service: try service(id, requiresConsent: false))
        } catch { store.reportError(error.localizedDescription) }
    }
    private func reconnectCards(_ id: UUID, reportError: Bool) {
        guard let project = store.project(id),
            project.hasWorkingCards || project.shotPictureSources?.isEmpty == false
        else { return }
        do { store.reconnectCards(id, service: try service(id, requiresConsent: false)) }
        catch { if reportError { store.reportError(error.localizedDescription) } }
    }
    private func reconnect(_ id: UUID) {
        do { store.reconnect(id, service: try service(id, requiresConsent: false)) } catch {
            store.reportError(error.localizedDescription)
        }
    }
    private func cancel(_ id: UUID) {
        do {
            let value = try service(id, requiresConsent: false)
            Task { await store.cancel(id, service: value) }
        } catch { store.reportError(error.localizedDescription) }
    }
    private func delete(_ id: UUID) {
        guard store.project(id)?.hasWorkingCards != true else {
            store.reportError("Stop the saved idea requests before deleting this project.")
            return
        }
        if !store.requestState(store.project(id)?.job).pending {
            store.delete(id)
            return
        }
        do {
            let value = try service(id, requiresConsent: false)
            Task {
                await store.cancel(id, service: value)
                if !store.requestState(store.project(id)?.job).pending {
                    store.delete(id)
                } else {
                    store.reportError("Cancellation could not be confirmed. The project is kept so you can reconnect its saved request.")
                }
            }
        } catch { store.reportError(error.localizedDescription) }
    }
}

typealias MiraGenerateAction = (UUID, MiraOperation, String, UUID?, MiraLanguage?) -> Void

struct MiraMyBrandView: View {
    var store: MiraStore
    var onProfile: () -> Void
    var onBrief: (UUID) -> Void
    var onOpen: (UUID) -> Void
    var onDelete: (UUID) -> Void
    var onStartBrand: () -> Void
    var onGenerateBrand: () -> Void
    @State private var showReels = false
    @State private var archived = false
    @State private var deletion: UUID?
    @State private var renaming: UUID?
    @State private var newName = ""
    var body: some View {
        MiraBrandView(store: store, onStart: onStartBrand, onGenerate: onGenerateBrand) {
            librarySections
        }.navigationTitle("My Brand").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: Binding(
                get: { renaming != nil }, set: { if !$0 { renaming = nil } }
            )) {
                NavigationStack {
                    MiraPage {
                        MiraTextInput(title: "Project name", text: $newName)
                    }.miraBottomAction {
                        Button("Save name") {
                            let title = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let id = renaming, !title.isEmpty { store.rename(id, to: title) }
                            renaming = nil
                        }.buttonStyle(MiraPrimaryStyle())
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .modifier(MiraInputScope())
                    .navigationTitle("Rename project").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { renaming = nil }
                        }
                    }
                }
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
    @ViewBuilder private var librarySections: some View {
        let profile = store.document.profile
        DisclosureGroup("Creator profile") {
            VStack(alignment: .leading, spacing: 10) {
                profileDetail("Name", profile.name)
                profileDetail("Themes", profile.themes)
                profileDetail("Audience", profile.audience)
                profileDetail("Language", profile.language.rawValue)
                profileDetail("Tone", profile.tone)
                profileDetail("Avoid", profile.avoid)
                profileDetail("Examples", profile.samples)
                Button("Edit creator profile", action: onProfile)
            }.padding(.vertical, 8)
        }.font(.headline)
        DisclosureGroup("Brand brief") {
            let briefs = store.document.projects.filter { !$0.brief.original.isEmpty }
                .sorted { $0.updatedAt > $1.updatedAt }
            if briefs.isEmpty {
                Text("No saved brand briefs.")
            }
            ForEach(briefs) { project in
                Button(project.title) { onBrief(project.id) }
                    .padding(.vertical, 6)
            }
        }.font(.headline)
        DisclosureGroup("All Reels", isExpanded: $showReels) {
            VStack(alignment: .leading, spacing: 18) { reels }
                .padding(.vertical, 12)
        }.font(.headline)
    }

    @ViewBuilder private func profileDetail(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            LabeledContent(label, value: value).font(.body)
        }
    }

    @ViewBuilder private var reels: some View {
        Toggle("Show archived projects", isOn: $archived)
        let projects = store.document.projects.filter { $0.archived == archived }.sorted {
            $0.updatedAt > $1.updatedAt
        }
        if projects.isEmpty {
            Text(
                archived
                    ? "No archived projects." : "Your projects will be here. Start an idea from Home."
            ).foregroundStyle(.secondary)
        }
        ForEach(projects) { project in
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    onOpen(project.id)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(project.title).font(.headline)
                        Text("\(project.stage.title) · \(project.nextAction)").font(.callout)
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
    let blockedConsent: MiraAIConsentState?
    let onMake: () -> Void
    let onReviewAIConsent: () -> Void
    let onContinue: (UUID) -> Void
    var onOpenDeal: (UUID) -> Void = { _ in }
    var onMakePick: () -> Void = {}
    var onAnother: () -> Void = {}
    var checkingInstagram = false
    var legacyEntry = false
    @Environment(MiraDependencies.self) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
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
            if legacyEntry {
                MiraSectionTitle(text: "What can you film today?")
                ideaRequest
                MiraInlineAction { makeButton }
            } else {
                homeContent
            }
        }.miraBottomAction(whileEditing: true) {
            if legacyEntry {
                makeButton
            } else if case .empty = store.homeFeed, store.pickState == .idle {
                makeButton
            }
        }
        .onAppear { if speech == nil { speech = dependencies.makeSpeechInput() } }
        .onDisappear { speech?.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                speech?.refreshPermissions()
            } else if phase == .background || speech?.state.isRecording == true {
                speech?.stop()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
            speech?.stop()
        }
        .onChange(of: speech?.transcript ?? "") { _, spoken in
            guard !spoken.isEmpty else { return }
            request = joined(spokenBase, spoken)
        }
    }

    @ViewBuilder private var homeContent: some View {
        if store.pickState != .idle {
            MiraHomePickCard(state: store.pickState, onMake: onMakePick, onAnother: onAnother)
                .disabled(checkingInstagram)
        }
        switch store.homeFeed {
        case .empty:
            if store.pickState == .idle {
                Text("Nothing planned today.").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                MiraFeedCard {
                    MiraSectionTitle(text: "Nothing planned today. Want an idea?")
                    ideaRequest
                    MiraInlineAction { makeButton }
                }.accessibilityIdentifier("mira.home.idea")
            }
        case .deals(let deals):
            Text(deals.count == 1 ? "You have one open deal." : "You have \(deals.count) open deals.")
                .font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            dealCards(deals)
        case .continuing(let reels, let deals):
            Text(reels.count == 1 ? "You have one Reel in progress." : "You have \(reels.count) Reels in progress.")
                .font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            ForEach(reels) { reel in
                MiraFeedCard {
                    Text("Continue").font(.subheadline).foregroundStyle(MiraTheme.secondaryInk)
                    MiraSectionTitle(text: reel.title)
                    ProgressView(value: Double(reel.completedSteps), total: Double(MiraTaskStep.total))
                        .accessibilityLabel("Reel progress")
                        .accessibilityValue("\(reel.completedSteps) of \(MiraTaskStep.total) steps complete")
                    Button(reel.nextAction.title) { onContinue(reel.id) }
                        .buttonStyle(MiraPrimaryStyle())
                        .accessibilityIdentifier("mira.today.continue")
                }
            }
            dealCards(deals)
        }
        consentRecovery
        MiraInsightsView(compact: true)
    }

    private func dealCards(_ deals: [MiraDeal]) -> some View {
        ForEach(deals) { deal in
            MiraDealSummary(deal: deal) { onOpenDeal(deal.id) }
        }
    }

    @ViewBuilder private var ideaRequest: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                MiraTextInput(
                    title: "For example: at the gym, sled push", text: $request, axis: .vertical
                )
                .lineLimit(2...4).font(.title3)
                .accessibilityLabel("What can you film today?")
                .accessibilityIdentifier("mira.today.request")
                microphone
            }
            if let message = speech?.state.message {
                Text(message).font(.subheadline).monospacedDigit()
                    .accessibilityAddTraits(.updatesFrequently)
            }
            MiraChipFlow(spacing: 8) {
                ForEach(Self.places, id: \.id) { chip($0, group: Self.places) }
                ForEach(Self.times, id: \.id) { chip($0, group: Self.times) }
            }
        }
    }

    private var makeButton: some View {
        Button(MiraNextAction.makeToday.title) {
            speech?.stop()
            onMake()
        }
        .buttonStyle(MiraPrimaryStyle())
        .disabled(speech?.state.isRecording == true || checkingInstagram)
        .accessibilityIdentifier("mira.today.make")
    }

    @ViewBuilder private var consentRecovery: some View {
        if let blockedConsent, blockedConsent == .declined || blockedConsent == .outOfDate {
            VStack(alignment: .leading, spacing: 8) {
                Text(blockedConsent == .outOfDate ? "Review AI permission again to write ideas." : "Allow AI to write ideas first.")
                    .accessibilityIdentifier("mira.today.aiPermissionNeeded")
                Button(blockedConsent.nextAction.title, action: onReviewAIConsent)
                    .buttonStyle(.bordered).controlSize(.large)
            }
        }
    }

    @ViewBuilder private var microphone: some View {
        if let speech {
            let locale = store.document.profile.language == .english ? "en-IN" : "hi-IN"
            MiraVoiceButton(speech: speech, locale: locale, compact: true) { spokenBase = request }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mira.today.mic")
        }
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
        .disabled(speech?.state.isRecording == true)
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
    let onChange: (UUID, String) -> Void
    let onScript: (UUID) -> Void
    let onBrief: () -> Void
    let onManual: () -> Void
    let onReconnect: () -> Void
    let onCancel: (UUID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.miraTabBarClearance) private var tabBarClearance
    @State private var position: Int? = 0
    @State private var hasShownFirstCard = false
    @State private var firstIdeaHaptic = false

    var body: some View {
        if let project = store.project(projectID), let cards = project.todayCards, !cards.isEmpty {
            let current = min(max(position ?? 0, 0), cards.count - 1)
            VStack(spacing: 12) {
                MiraTaskHeading(step: store.taskStep(.todayCards(projectID), in: project))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24)
                pager(cards, in: project, current: current)
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
                            .contentMargins(.bottom, tabBarClearance, for: .scrollContent)
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
                        Button("Brand requirements", action: onBrief)
                        Button("Add my own idea", action: onManual)
                        NavigationLink("More ideas", value: MiraRoute.project(projectID))
                        if store.cardState(card, in: project).pending {
                            Button("Reconnect", action: onReconnect)
                            Button("Stop this idea") { onCancel(card.id) }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                let card = cards[current]
                MiraAskBar(
                    placeholder: "Ask Mira to change this idea", language: store.document.profile.language,
                    enabled: !store.cardState(card, in: project).pending,
                    onSend: { onChange(card.id, $0) })
                .id(card.id)
            }
            .modifier(MiraInputScope())
            .sensoryFeedback(.success, trigger: firstIdeaHaptic)
            .onChange(of: cards.contains { store.cardState($0, in: project).ideaReady }) { _, ready in
                if ready { firstIdeaHaptic = true }
            }
            .onChange(of: cards.map(\.ready), initial: true) { _, ready in
                guard !hasShownFirstCard, let first = ready.firstIndex(of: true) else { return }
                hasShownFirstCard = true
                if store.cardState(cards[current], in: project).pending { go(to: first) }
            }
        }
    }

    private func go(to index: Int) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1)) { position = index }
    }

    private func status(_ state: MiraTodayCardState) -> (symbol: String, word: String) {
        switch state {
        case .ready: ("checkmark.circle.fill", "ready")
        case .waiting: ("clock", "waiting to start")
        case .waitingToRetry: ("clock", MiraAIRequest.retryMessage)
        case .making, .reconnect: ("hourglass", "Mira is making it")
        case .failed: ("exclamationmark.circle", "did not load")
        case .needsUpdate: ("checkmark.circle", "needs an update")
        }
    }

    private func pager(_ cards: [MiraTodayCard], in project: MiraProject, current: Int) -> some View {
        VStack(spacing: 8) {
            MiraChipFlow(spacing: 8) {
                ForEach(cards.indices, id: \.self) { index in
                    let selected = current == index
                    let state = status(store.cardState(cards[index], in: project))
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
                if cards.contains(where: {
                    if case .making = store.cardState($0, in: project) { return true }
                    return false
                }) {
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
        let state = store.cardState(card, in: project)
        if let output = state.output, let idea = output.ideas?.first, let board = output.storyboard,
            let script = output.script {
            Text(idea.title).font(.title.bold()).accessibilityAddTraits(.isHeader)
            Text(idea.hook).font(.title3)
            ViewThatFits(in: .horizontal) {
                pictures(board, project: project)
                ScrollView(.horizontal) { pictures(board, project: project) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("About \(idea.filmingMinutes) min to film", systemImage: "clock")
                Label(board.shots.first?.location ?? card.job.input.constraints.location, systemImage: "location")
                Label("\(script.durationSeconds) sec Reel", systemImage: "play.rectangle")
            }.font(.body).monospacedDigit()
            if case .ready = state {
                Button(state.nextAction.title) { onMake(card.id) }.buttonStyle(MiraPrimaryStyle())
                    .accessibilityIdentifier("mira.today.makeCard.\(index + 1)")
            }
        } else if case .making(_, let progress) = state {
            placeholder(index: index, count: count, progress: progress)
        }
        switch state {
        case .waiting:
            Text("Waiting to start…").font(.title2.weight(.semibold))
                .accessibilityIdentifier("mira.today.waiting.\(index + 1)")
            Text("Mira starts this idea when another one is done.").font(.title3)
        case .waitingToRetry:
            Text(MiraAIRequest.retryMessage).font(.title2.weight(.semibold))
        case .reconnect(_, let reason):
            Text(reason ?? "Reconnect to check this idea.").font(.title3)
            Button(state.nextAction.title, action: onReconnect).buttonStyle(MiraPrimaryStyle())
        case .making(let previous, _):
            if previous != nil { Text("Mira is making a new version. About 1 minute.").font(.title3) }
        case .failed(_, let stopped):
            Text(stopped ? "This idea was stopped." : "This idea did not load.").font(.title3)
            if let reason = card.job.error { Text(reason).font(.callout) }
            Button(state.nextAction.title) { onRetry(card.id) }.buttonStyle(MiraPrimaryStyle())
        case .needsUpdate:
            Button(state.nextAction.title) { onRetry(card.id) }.buttonStyle(MiraPrimaryStyle())
            Button("Change something") { onChange(card.id, "") }.buttonStyle(.bordered).controlSize(.large)
        case .ready:
            Button("Change something") { onChange(card.id, "") }.buttonStyle(.bordered).controlSize(.large)
        }
    }

    private func placeholder(index: Int, count: Int, progress: MiraGenerationStep?) -> some View {
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
            if let progress {
                VStack(alignment: .leading, spacing: 12) {
                    step("Finding an idea", state: .done)
                    step("Writing your words", state: progress == .ideaReady ? .now : .done)
                    let planning: WaitStep = switch progress {
                    case .ideaReady: .next
                    case .scriptReady: .now
                    case .storyboardReady: .done
                    }
                    step("Planning 3 shots", state: planning)
                }
            }
            Text("About 1 minute. You can wait here or look at the other ideas.")
                .font(.subheadline).foregroundStyle(MiraTheme.secondaryInk)
        }
    }

    private enum WaitStep: String {
        case done, now, next

        var symbol: String {
            switch self {
            case .done: "checkmark.circle.fill"
            case .now: "arrow.right.circle.fill"
            case .next: "circle"
            }
        }
    }

    private func step(_ title: String, state: WaitStep) -> some View {
        Label(title, systemImage: state.symbol).font(.title3.weight(state == .now ? .semibold : .regular))
            .foregroundStyle(state == .next ? MiraTheme.secondaryInk : MiraTheme.ink)
            .accessibilityLabel("\(title), \(state.rawValue)")
    }

    private func pictures(_ board: MiraStoryboard, project: MiraProject) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(board.shots.enumerated()), id: \.element.id) { index, shot in
                MiraShotPicture(
                    shot: shot, number: index + 1, showSeconds: true,
                    picture: store.picture(in: project, boardID: board.id, shotID: shot.id),
                    source: (project.id, board.id))
            }
        }.fixedSize(horizontal: true, vertical: false)
    }
}
