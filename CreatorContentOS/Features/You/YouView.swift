import SwiftUI

/// You hub: Account, generation inputs, Archive entry, and sign-out.
struct YouView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @State private var navigationPath = NavigationPath()
    @State private var isSigningOut = false
    @State private var isPreferencesExpanded = false
    @Environment(\.pocketReduceMotion) private var reduceMotion
#if DEBUG
    @State private var showBenchmark = false
    @State private var uiFixtureData = DebugLaunchFlags.uiFixtureData
#endif

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSheetSpace.xl) {
                    Text("You")
                        .font(PocketSheetType.screenTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .padding(.horizontal, PocketSheetSpace.l)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("you.title")

                    accountBlock
                    generationInputsBlock
                    archiveBlock
#if DEBUG
                    devBlock
#endif
                    signOutBlock
                }
                .padding(.top, PocketSheetSpace.xs)
                .padding(.bottom, PocketSheetSpace.xl)
            }
            .background(PocketSheetTheme.Color.paper.ignoresSafeArea())
            .navigationDestination(for: YouRoute.self) { route in
                YouRouteView(route: route, navigationPath: $navigationPath)
            }
        }
        .onAppear(perform: consumePendingNavigation)
        .onChange(of: appState.pendingYouNavigation?.destination) { _, _ in
            consumePendingNavigation()
        }
#if DEBUG
        .sheet(isPresented: $showBenchmark) {
            DayGenerationBenchmarkView()
        }
#endif
    }

#if DEBUG
    private var devBlock: some View {
        PocketSheetBlock(header: "Dev") {
            if DebugLaunchFlags.forceFixtureUI {
                VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                    Text("UI test data")
                        .font(PocketSheetType.rowTitle)
                    Picker("UI test data", selection: $uiFixtureData) {
                        ForEach(PocketUIFixtureData.allCases) { data in
                            Text(data.label).tag(data)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("you.dev.fixtureData")
                    Text("Demo data / Worst case, plus empty, one, and large collections. Changes the sample Today package.")
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                }
                .padding(PocketSheetSpace.m)
                .onChange(of: uiFixtureData) { _, data in
                    DebugLaunchConfiguration.fixtureDefaults.set(data.rawValue, forKey: "break-ui-data")
                    var draft = data.applying(to: GeneratedDailyCardDraft.storyboardBreakdownFixture)
                    draft.scheduledDate = services.currentTodayDateString
                    draft.status = "ready"
                    services.todayCard = draft.dailyCard(completionState: nil)
                    services.todayContentState = .ready
                }
            }
            Button {
                showBenchmark = true
            } label: {
                PocketSheetRow(
                    title: "Run generation benchmark",
                    subtitle: "N real generations through the live runtime — p95 gate"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("you.dev.benchmark")
        }
        .padding(.horizontal, PocketSheetSpace.l)
    }
#endif

    private var accountBlock: some View {
        PocketSheetBlock(header: "Account") {
            Button {
                open(.account, from: .you)
            } label: {
                PocketSheetRow(
                    title: accountTitle,
                    subtitle: accountSubtitle
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("you.row.account")
        }
        .padding(.horizontal, PocketSheetSpace.l)
    }

    private var generationInputsBlock: some View {
        PocketSheetBlock {
            VStack(spacing: 0) {
                Button {
                    if reduceMotion {
                        isPreferencesExpanded.toggle()
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPreferencesExpanded.toggle()
                        }
                    }
                } label: {
                    HStack(alignment: .center, spacing: PocketSheetSpace.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Idea settings")
                                .font(PocketSheetType.rowTitle)
                                .foregroundStyle(PocketSheetTheme.Color.ink)
                            Text(isPreferencesExpanded ? "Edit how your ideas are shaped" : "Optional preferences for future ideas")
                                .font(PocketSheetType.rowSubtitle)
                                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        }
                        Spacer(minLength: PocketSheetSpace.s)
                        Image(systemName: isPreferencesExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .padding(.horizontal, PocketSheetSpace.m)
                }
                .buttonStyle(.plain)
                .accessibilityValue(isPreferencesExpanded ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("you.preferences.toggle")

                if isPreferencesExpanded {
                    PocketSheetDivider()
                    VStack(spacing: 0) {
                        setupRow(.contentCategories, title: "Interests & style", subtitle: interestsSubtitle)
                        PocketSheetDivider()
                        setupRow(.productionPreferences, title: "Content preferences", subtitle: productionSubtitle)
                        PocketSheetDivider()
                        setupRow(.currentContext, title: "Current reads & watches", subtitle: contextSubtitle)
                        PocketSheetDivider()
                        setupRow(.creatorVoice, title: "Creator voice", subtitle: voiceSubtitle)
                        PocketSheetDivider()
                        setupRow(.references, title: "References", subtitle: referencesSubtitle)
                    }
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, PocketSheetSpace.l)
    }

    private var archiveBlock: some View {
        PocketSheetBlock(header: "Archive") {
            YouArchivePreview(onSeeMore: { open(.archive, from: .you) })
        }
        .padding(.horizontal, PocketSheetSpace.l)
    }

    private var signOutBlock: some View {
        PocketSheetSecondaryAction(title: isSigningOut ? "Signing out" : "Sign out") {
            signOut()
        }
        .disabled(isSigningOut || liveSession == nil)
        .opacity((isSigningOut || liveSession == nil) ? 0.54 : 1)
        .padding(.horizontal, PocketSheetSpace.l)
        .accessibilityIdentifier("you.account.signOut")
    }

    private func setupRow(_ route: YouRoute, title: String, subtitle: String) -> some View {
        Button {
            open(route, from: .you)
        } label: {
            PocketSheetRow(title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("you.row.\(accessibilitySuffix(for: route))")
    }

    private func open(_ route: YouRoute, from origin: YouNavigationOrigin) {
        appState.recordYouNavigationOrigin(origin)
        navigationPath.append(route)
    }

    private func consumePendingNavigation() {
        guard let intent = appState.consumeYouNavigation() else { return }
        appState.recordYouNavigationOrigin(intent.origin)
        switch intent.origin {
        case .plan:
            navigationPath = NavigationPath([intent.destination])
        case .you:
            navigationPath.append(intent.destination)
        }
    }

    private var interestsSubtitle: String {
        YouInterestsSelection.from(profile: services.creatorProfileSummary).summarySubtitle
    }

    private var productionSubtitle: String {
        YouProductionSelection.from(profile: services.creatorProfileSummary).summarySubtitle
    }

    private var contextSubtitle: String {
        YouContextSelection.from(profile: services.creatorProfileSummary).summarySubtitle
    }

    private var voiceSubtitle: String {
        YouSetupMeta.voiceSubtitle(profile: services.creatorProfileSummary)
    }

    private var referencesSubtitle: String {
        YouSetupMeta.referencesSubtitle(home: services.intelligenceHome)
    }

    private var accountTitle: String {
        if let email = liveSession?.authenticatedEmail?.nilIfBlank {
            return email
        }
        if let name = liveSession?.creatorDisplayName?.nilIfBlank {
            return name
        }
        return liveSession == nil ? "Sample account" : "Apple ID"
    }

    private var accountSubtitle: String {
        var parts = [liveSession == nil ? "Using sample data" : "Signed in with Apple"]
        if let checkedAt = services.lastRepositoryRefreshAt ?? services.lastRepositoryRefreshAttemptAt {
            parts.append("checked \(checkedAt.formatted(date: .omitted, time: .shortened))")
        }
        return parts.joined(separator: " · ")
    }

    private func accessibilitySuffix(for route: YouRoute) -> String {
        switch route {
        case .contentCategories: "interests"
        case .productionPreferences: "production"
        case .currentContext: "context"
        case .creatorVoice: "voice"
        case .references: "references"
        case .account: "account"
        case .archive: "archive"
        }
    }

    private var liveSession: PairedDeviceSession? {
        if case .live(let session) = appState.runtime.mode {
            session
        } else {
            nil
        }
    }

    @MainActor
    private func signOut() {
        guard !isSigningOut else { return }
        isSigningOut = true
        Task { @MainActor in
            await appState.signOut()
            isSigningOut = false
        }
    }
}

struct YouRouteView: View {
    @Environment(AppState.self) private var appState
    let route: YouRoute
    @Binding var navigationPath: NavigationPath

    var body: some View {
        Group {
            switch route {
            case .contentCategories:
                YouContentCategoriesView(backLabel: backLabel, onBack: handleBack)
            case .productionPreferences:
                YouProductionPreferencesView(backLabel: backLabel, onBack: handleBack)
            case .currentContext:
                YouCurrentContextView(backLabel: backLabel, onBack: handleBack)
            case .creatorVoice:
                YouCreatorVoiceView(backLabel: backLabel, onBack: handleBack)
            case .references:
                YouReferencesView(backLabel: backLabel, onBack: handleBack)
            case .account:
                YouAccountView(backLabel: backLabel, onBack: handleBack)
            case .archive:
                YouArchiveDestinationView(backLabel: backLabel, onBack: handleBack)
            }
        }
        .navigationBarHidden(true)
    }

    private var backLabel: String {
        switch appState.youNavigationOrigin {
        case .plan:
            "Plan"
        case .you, .none:
            "You"
        }
    }

    private func handleBack() {
        switch appState.youNavigationOrigin {
        case .plan(let selectedDate):
            appState.returnToPlan(fromYouDestination: selectedDate)
            navigationPath = NavigationPath()
        case .you, .none:
            if navigationPath.isEmpty {
                navigationPath = NavigationPath()
            } else {
                navigationPath.removeLast()
            }
        }
    }
}

struct YouArchivePreview: View {
    @Environment(AppServices.self) private var services
    let onSeeMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
            if previewEntries.isEmpty {
                Text("Nothing posted yet.")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .padding(.horizontal, PocketSheetSpace.m)
                    .padding(.vertical, PocketSheetSpace.s)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(previewEntries.enumerated()), id: \.element.id) { index, entry in
                        ArchiveTimelineRow(entry: entry)
                            .padding(.horizontal, PocketSheetSpace.m)
                            .padding(.vertical, PocketSheetSpace.s)
                        if index < previewEntries.count - 1 {
                            PocketSheetDivider()
                        }
                    }
                }
            }

            if services.archiveEntries.count > 5 {
                Button(action: onSeeMore) {
                    Text("See more")
                        .font(PocketSheetType.rowTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, PocketSheetSpace.m)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("you.archive.seeMore")
            }
        }
    }

    private var previewEntries: [ArchiveEntry] {
        Array(services.archiveEntries.prefix(5))
    }
}

struct YouArchiveDestinationView: View {
    let backLabel: String
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            YouBackHeader(backLabel: backLabel, action: onBack)
                .padding(.horizontal, PocketSheetSpace.l)
                .padding(.top, PocketSheetSpace.xs)
            ArchiveView()
        }
        .background(PocketSheetTheme.Color.paper.ignoresSafeArea())
    }
}
