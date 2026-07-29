import SwiftUI

struct CreatorShellView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: CreatorTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView()
                .navigationDestination(for: CreatorRoute.self) { route in
                    switch route {
                    case .shootFolio(let editing):
                        ShootFolioView(startsInEditingMode: editing)
                    case .plan(let selectedDate):
                        PlanHubView(
                            showsModeSwitch: false,
                            initialSelectedDate: selectedDate
                        )
                    }
                }
            }
            .tabItem { Label("Today", systemImage: "sun.min") }
            .tag(CreatorTab.today)

            NavigationStack {
                ArchiveView()
            }
            .tabItem { Label("Archive", systemImage: "archivebox") }
            .tag(CreatorTab.archive)

            NavigationStack {
                ProfileModeView()
            }
            .tabItem { Label("Profile", systemImage: "person.circle") }
            .tag(CreatorTab.profile)
        }
        .background(MCOTheme.Color.paper)
        .onChange(of: appState.pendingCreatorTab) { _, tab in
            guard let tab else { return }
            selectedTab = tab
            appState.pendingCreatorTab = nil
        }
    }
}

struct ProfileModeView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @State private var isSigningOut = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                header
                accountSection
                runtimeStatus
            }
            .padding(.horizontal, MCOSpace.l)
            .padding(.top, MCOSpace.l)
            .padding(.bottom, 112)
        }
        .background(MCOTheme.Color.paper.ignoresSafeArea())
    }

    private var header: some View {
        Text("Profile")
            .font(MCOType.display)
            .foregroundStyle(MCOTheme.Color.ink)
    }

    private var runtimeStatus: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                Text("Status")
                    .font(MCOType.headline)
                    .foregroundStyle(MCOTheme.Color.ink)

                statusRow(
                    title: "Supabase",
                    value: services.supabaseHealthStatus.chipLabel,
                    tone: healthChipTone(services.supabaseHealthStatus)
                )
                statusRow(
                    title: "Gemini",
                    value: geminiChipLabel(services.geminiHealthStatus),
                    tone: healthChipTone(services.geminiHealthStatus)
                )

                HStack(alignment: .center, spacing: MCOSpace.s) {
                    Text(lastCheckedText)
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Spacer(minLength: MCOSpace.s)
                    refreshButton
                }

                if let message = refreshFeedbackMessage {
                    Text(message)
                        .font(MCOType.caption)
                        .foregroundStyle(refreshFeedbackColor)
                        .transition(.opacity)
                }
            }
            .animation(.snappy(duration: 0.2), value: services.isRefreshingRepository)
            .animation(.snappy(duration: 0.2), value: services.isCheckingRuntimeHealth)
            .animation(.snappy(duration: 0.2), value: refreshFeedbackMessage)
        }
    }

    private func healthChipTone(_ status: RuntimeHealthStatus) -> ChipTone {
        switch status {
        case .unknown, .checking:
            .quiet
        case .sample:
            .warning
        case .live:
            .ready
        case .down:
            .danger
        }
    }

    private func geminiChipLabel(_ status: RuntimeHealthStatus) -> String {
        switch status {
        case .sample:
            "Offline"
        case .live:
            "Live"
        case .checking:
            "Checking"
        case .down:
            "Down"
        case .unknown:
            "—"
        }
    }

    private func statusRow(title: String, value: String, tone: ChipTone) -> some View {
        HStack {
            Text(title)
                .font(MCOType.bodySmall)
                .foregroundStyle(MCOTheme.Color.ink)
            Spacer(minLength: MCOSpace.s)
            StatusChip(text: value, tone: tone)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }

    private var refreshButton: some View {
        Button {
            services.refreshFromRepositories()
        } label: {
            ZStack {
                if services.isRefreshingRepository || services.isCheckingRuntimeHealth {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(MCOType.bodyEmphasis)
                }
            }
            .frame(width: 44, height: 44)
            .foregroundStyle(MCOTheme.Color.oxblood)
            .background(MCOTheme.Color.paper.opacity(0.82), in: Circle())
            .overlay {
                Circle().stroke(MCOTheme.Color.hairline, lineWidth: 1)
            }
            .opacity((services.isRefreshingRepository || services.isCheckingRuntimeHealth) ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(services.isRefreshingRepository || services.isCheckingRuntimeHealth)
        .accessibilityLabel(
            (services.isRefreshingRepository || services.isCheckingRuntimeHealth)
                ? "Refreshing"
                : "Refresh profile data"
        )
    }

    private var refreshFeedbackMessage: String? {
        if services.isRefreshingRepository || services.isCheckingRuntimeHealth {
            return "Refreshing…"
        }
        if let healthError = services.lastRuntimeHealthError?.nilIfBlank {
            return "Health check failed: \(healthError)"
        }
        if let error = services.lastRepositoryRefreshError?.nilIfBlank {
            return "Refresh failed: \(error)"
        }
        if let succeeded = services.lastRepositoryRefreshSucceededAt
            ?? services.lastRuntimeHealthCheckedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "Up to date as of \(formatter.string(from: succeeded))."
        }
        return nil
    }

    private var refreshFeedbackColor: Color {
        if services.isRefreshingRepository || services.isCheckingRuntimeHealth {
            return MCOTheme.Color.inkMuted
        }
        if services.lastRuntimeHealthError != nil || services.lastRepositoryRefreshError != nil {
            return MCOTheme.Color.danger
        }
        return MCOTheme.Color.sageDeep
    }

    private var accountSection: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                HStack {
                    Text(liveSession == nil ? "Account" : "Signed in with Apple")
                        .font(MCOType.tinyLabel)
                        .foregroundStyle(MCOTheme.Color.sageDeep)
                    Spacer()
                    StatusChip(
                        text: liveSession?.memberRole.capitalized ?? "Sample",
                        tone: liveSession == nil ? .warning : .ready
                    )
                }

                if let liveSession {
                    Text(appleIdentityLabel(for: liveSession))
                        .font(MCOType.body)
                        .foregroundStyle(MCOTheme.Color.ink)
                        .accessibilityIdentifier("profile.appleIdentity")
                } else {
                    Text("Using sample data")
                        .font(MCOType.body)
                        .foregroundStyle(MCOTheme.Color.ink)
                }

                SecondaryActionButton(title: isSigningOut ? "Signing out" : "Sign out") {
                    signOut()
                }
                .disabled(isSigningOut || liveSession == nil)
                .opacity((isSigningOut || liveSession == nil) ? 0.54 : 1)
            }
        }
    }

    private func appleIdentityLabel(for session: PairedDeviceSession) -> String {
        if let email = session.authenticatedEmail?.nilIfBlank {
            return email
        }
        if let name = session.creatorDisplayName?.nilIfBlank {
            return name
        }
        return "Apple ID"
    }

    private var lastCheckedText: String {
        if let lastCheckedAt = appState.runtime.services.lastRepositoryRefreshAt
            ?? appState.runtime.services.lastRepositoryRefreshAttemptAt {
            return "Last checked at \(lastCheckedAt.formatted(date: .omitted, time: .shortened))"
        }

        return "Checking for updates..."
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
