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
                ShootFolioView()
            }
            .tabItem { Label("Shoot Folio", systemImage: "bookmark") }
            .tag(CreatorTab.shootFolio)

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
    @State private var isSigningOut = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                header
                runtimeStatus
                accountSection
                if canAccessAdmin {
                    SecondaryActionButton(title: "Switch to Admin control") {
                        appState.activeMode = .admin
                    }
                }
                Hairline()
                    .padding(.vertical, MCOSpace.m)
                ArchiveSection()
            }
            .padding(.horizontal, MCOSpace.l)
            .padding(.top, MCOSpace.l)
            .padding(.bottom, 112)
        }
        .background(MCOTheme.Color.paper.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xxs) {
            Text("Profile")
                .font(MCOType.screenTitle)
                .foregroundStyle(MCOTheme.Color.ink)
            Text("This page has the creator's profile and archive details. Clicking them will show you more details.")
                .font(MCOType.bodySmall)
                .foregroundStyle(MCOTheme.Color.inkMuted)
        }
    }

    private var runtimeStatus: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            HStack {
                Text("Data source")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                Spacer(minLength: MCOSpace.s)
                StatusChip(
                    text: liveSession == nil ? "Sample" : "Live",
                    tone: liveSession == nil ? .warning : .ready
                )
            }

            Text(liveSession == nil ? "Sample app data" : "Supabase")
                .font(MCOType.body)
                .foregroundStyle(MCOTheme.Color.ink)

            if let lastCheckedAt = appState.runtime.services.lastRepositoryRefreshAt {
                Text("Last checked at \(lastCheckedAt.formatted(date: .omitted, time: .shortened))")
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            } else {
                Text("Checking for updates...")
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }

            if let liveSession {
                VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                    if let workspaceName = liveSession.workspaceName {
                        Text(workspaceName)
                    }
                    Text("\(liveSession.memberRole.capitalized) access")
                }
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.inkMuted)
            }
        }
        .padding(MCOSpace.s)
        .background(MCOTheme.Color.paperRaised.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                .stroke(MCOTheme.Color.hairline, lineWidth: 1)
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            Text("Signed in")
                .font(MCOType.tinyLabel)
                .foregroundStyle(MCOTheme.Color.sageDeep)

            if let liveSession {
                if let email = liveSession.authenticatedEmail {
                    Text(email)
                        .font(MCOType.body)
                        .foregroundStyle(MCOTheme.Color.ink)
                }
                Text(liveSession.creatorDisplayName ?? "Creator")
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }

            SecondaryActionButton(title: isSigningOut ? "Signing out" : "Sign out") {
                signOut()
            }
            .disabled(isSigningOut)
            .opacity(isSigningOut ? 0.54 : 1)
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
