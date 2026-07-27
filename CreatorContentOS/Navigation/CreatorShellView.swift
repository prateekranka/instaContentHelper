import SwiftUI

struct CreatorShellView: View {
    @State private var selectedTab: CreatorTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView {
                    selectedTab = .profile
                }
                    .navigationDestination(for: CreatorRoute.self) { route in
                        switch route {
                        case .shootFolio:
                            ShootFolioView()
                        }
                    }
            }
            .tabItem { Label("Today", systemImage: "sun.min") }
            .tag(CreatorTab.today)

            NavigationStack {
                ProfileModeView()
            }
            .tabItem { Label("Profile", systemImage: "person.circle") }
            .tag(CreatorTab.profile)
        }
        .background(MCOTheme.Color.paper)
    }
}

struct ProfileModeView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSigningOut = false
    @State private var isCreatorProfileExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                header
                accountSection
                if canAccessAdmin {
                    managerAccessSection
                }
                creatorProfileSection
                Hairline()
                    .padding(.vertical, MCOSpace.s)
                ArchiveSection()
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
            .font(MCOType.screenTitle)
            .tracking(MCOType.screenTitleTracking)
            .foregroundStyle(MCOTheme.Color.ink)
    }

    private var runtimeStatus: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                Text(liveSession == nil ? "Database" : "Supabase")
                    .font(MCOType.headline)
                    .foregroundStyle(MCOTheme.Color.ink)

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
            .animation(MCOMotion.easeOut(duration: 0.18), value: services.isRefreshingRepository)
            .animation(MCOMotion.easeOut(duration: 0.18), value: refreshFeedbackMessage)
        }
    }

    private var refreshButton: some View {
        Button {
            services.refreshFromRepositories()
        } label: {
            ZStack {
                if services.isRefreshingRepository {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(width: 44, height: 44)
            .foregroundStyle(MCOTheme.Color.oxblood)
            .background(MCOTheme.Color.paper.opacity(0.82), in: Circle())
            .overlay {
                Circle().stroke(MCOTheme.Color.hairline, lineWidth: 1)
            }
            .opacity(services.isRefreshingRepository ? 0.6 : 1)
        }
        .buttonStyle(.pressable(scale: 0.96))
        .disabled(services.isRefreshingRepository)
        .accessibilityLabel(services.isRefreshingRepository ? "Refreshing" : "Refresh profile data")
    }

    private var refreshFeedbackMessage: String? {
        if services.isRefreshingRepository {
            return "Refreshing…"
        }
        if let error = services.lastRepositoryRefreshError?.nilIfBlank {
            return "Refresh failed: \(error)"
        }
        if let succeeded = services.lastRepositoryRefreshSucceededAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "Up to date as of \(formatter.string(from: succeeded))."
        }
        return nil
    }

    private var refreshFeedbackColor: Color {
        if services.isRefreshingRepository {
            return MCOTheme.Color.inkMuted
        }
        if services.lastRepositoryRefreshError != nil {
            return MCOTheme.Color.danger
        }
        return MCOTheme.Color.sageDeep
    }

    private var accountSection: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                HStack {
                    Text(liveSession == nil ? "Account" : "Signed in")
                        .font(MCOType.tinyLabel)
                        .foregroundStyle(MCOTheme.Color.sageDeep)
                    Spacer()
                    StatusChip(text: liveSession?.memberRole.capitalized ?? "Sample", tone: liveSession == nil ? .warning : .ready)
                }

                if let liveSession {
                    if let email = liveSession.authenticatedEmail {
                        Text(email)
                            .font(MCOType.body)
                            .foregroundStyle(MCOTheme.Color.ink)
                    }
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

    private var creatorProfileSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(MCOMotion.preferential(reduceMotion, MCOMotion.easeOut(duration: 0.2))) {
                    isCreatorProfileExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: MCOSpace.m) {
                    Image(systemName: "person.crop.rectangle")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(MCOTheme.Color.brass)
                        .frame(width: 34)

                    Text("Creator Profile")
                        .font(MCOType.headline)
                        .foregroundStyle(MCOTheme.Color.ink)

                    Spacer(minLength: MCOSpace.s)
                    Image(systemName: isCreatorProfileExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                }
                .padding(.vertical, MCOSpace.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable(scale: 0.99))
            .accessibilityLabel(isCreatorProfileExpanded ? "Close Creator Profile" : "Open Creator Profile")

            if isCreatorProfileExpanded {
                VStack(alignment: .leading, spacing: MCOSpace.s) {
                    Text(services.creatorProfileSummary.positioning)
                        .font(MCOType.bodySmall)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    if !services.creatorProfileSummary.noGoTopics.isEmpty {
                        HStack(spacing: MCOSpace.xs) {
                            ForEach(services.creatorProfileSummary.noGoTopics.prefix(3), id: \.self) { topic in
                                StatusChip(text: topic, tone: .warning)
                            }
                        }
                    }

                    NavigationLink {
                        CreatorProfileAdminView()
                    } label: {
                        Text("Edit profile")
                            .font(MCOType.caption)
                            .foregroundStyle(MCOTheme.Color.oxblood)
                    }
                    .buttonStyle(.pressable(scale: 0.98))
                    .accessibilityLabel("Edit creator profile")
                }
                .padding(.bottom, MCOSpace.s)
                // Accordion: opacity only under reduced motion; otherwise light collapse feel.
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
    }

    private var lastCheckedText: String {
        if let lastCheckedAt = appState.runtime.services.lastRepositoryRefreshAt
            ?? appState.runtime.services.lastRepositoryRefreshAttemptAt {
            return "Last checked at \(lastCheckedAt.formatted(date: .omitted, time: .shortened))"
        }

        return "Checking for updates..."
    }

    private var managerAccessSection: some View {
        JournalBlock {
            HStack(spacing: MCOSpace.m) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(MCOTheme.Color.oxblood)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                    Text("Manager tools")
                        .font(MCOType.headline)
                        .foregroundStyle(MCOTheme.Color.ink)
                    Text("Create daily content, review references, and manage testers.")
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                }
                Spacer()
                Button {
                    appState.activeMode = .admin
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .foregroundStyle(MCOTheme.Color.paperRaised)
                .background(MCOTheme.Color.oxblood, in: Circle())
                .accessibilityLabel("Switch to manager control")
            }
        }
    }

    private var liveSession: PairedDeviceSession? {
        if case .live(let session) = appState.runtime.mode {
            session
        } else {
            nil
        }
    }

    private var canAccessAdmin: Bool {
        guard let role = liveSession?.memberRole.lowercased() else { return false }
        return role == "owner" || role == "editor"
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
