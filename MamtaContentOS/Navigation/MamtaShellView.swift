import SwiftUI

struct MamtaShellView: View {
    @State private var selectedTab: MamtaTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView()
                    .navigationDestination(for: MamtaRoute.self) { route in
                        switch route {
                        case .shootFolio:
                            ShootFolioView()
                        }
                    }
            }
            .tabItem { Label("Today", systemImage: "sun.min") }
            .tag(MamtaTab.today)

            NavigationStack {
                ShootFolioView()
            }
            .tabItem { Label("Shoot Folio", systemImage: "bookmark") }
            .tag(MamtaTab.shootFolio)

            NavigationStack {
                ArchiveView()
            }
            .tabItem { Label("Archive", systemImage: "archivebox") }
            .tag(MamtaTab.archive)

            NavigationStack {
                ProfileModeView()
            }
            .tabItem { Label("Profile", systemImage: "person.circle") }
            .tag(MamtaTab.profile)
        }
        .background(MCOTheme.Color.paper)
    }
}

struct ProfileModeView: View {
    @Environment(AppState.self) private var appState
    @State private var inviteCode = ""
    @State private var pairingMessage: String?
    @State private var pairingError: String?
    @State private var isPairing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                header
                runtimeStatus
                pairingSection
                SecondaryActionButton(title: "Switch to Prateek Control") {
                    appState.activeMode = .admin
                }
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
            Text("Mamta mode is the daily product. Prateek controls stay tucked away.")
                .font(MCOType.bodySmall)
                .foregroundStyle(MCOTheme.Color.inkMuted)
        }
    }

    private var runtimeStatus: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            HStack {
                Text("Runtime")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                Spacer(minLength: MCOSpace.s)
                StatusChip(
                    text: liveSession == nil ? "Fixtures" : "Live",
                    tone: liveSession == nil ? .warning : .ready
                )
            }

            Text(appState.runtime.mode.label)
                .font(MCOType.body)
                .foregroundStyle(MCOTheme.Color.ink)

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

    @ViewBuilder
    private var pairingSection: some View {
        if let liveSession {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                Text("Device is paired")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.sageDeep)
                Text(liveSession.creatorDisplayName ?? "Mamta")
                    .font(MCOType.cardTitle)
                    .foregroundStyle(MCOTheme.Color.ink)
                SecondaryActionButton(title: "Clear pairing") {
                    clearPairing()
                }
            }
        } else {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                Text("Pair device")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.oxblood)

                VStack(alignment: .leading, spacing: MCOSpace.xs) {
                    Text("Invite code")
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                    HStack(spacing: MCOSpace.s) {
                        TextField("MCO-...", text: $inviteCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .textContentType(.oneTimeCode)
                            .submitLabel(.go)
                            .font(MCOType.body)
                            .foregroundStyle(MCOTheme.Color.ink)
                            .padding(MCOSpace.s)
                            .frame(height: 54)
                            .background(MCOTheme.Color.paperRaised.opacity(0.72))
                            .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                                    .stroke(MCOTheme.Color.hairline, lineWidth: 1)
                            }
                            .onSubmit {
                                pairDevice()
                            }

                        Button {
                            pairDevice()
                        } label: {
                            Image(systemName: isPairing ? "hourglass" : "link")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 54, height: 54)
                                .foregroundStyle(MCOTheme.Color.paperRaised)
                                .background(MCOTheme.Color.oxblood)
                                .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isPairing || trimmedInviteCode.isEmpty)
                        .opacity(isPairing || trimmedInviteCode.isEmpty ? 0.54 : 1)
                        .accessibilityLabel(isPairing ? "Pairing" : "Pair device")
                    }
                }
            }
        }

        if let pairingMessage {
            Text(pairingMessage)
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.sageDeep)
        }

        if let pairingError {
            Text(pairingError)
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.clay)
        }
    }

    private var liveSession: PairedDeviceSession? {
        if case .live(let session) = appState.runtime.mode {
            session
        } else {
            nil
        }
    }

    private var trimmedInviteCode: String {
        inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func pairDevice() {
        let code = trimmedInviteCode
        guard !isPairing, !code.isEmpty else { return }

        isPairing = true
        pairingMessage = nil
        pairingError = nil

        Task { @MainActor in
            defer { isPairing = false }

            do {
                let result = try await DevicePairingService().pairDevice(inviteCode: code)
                let runtime = AppRuntime.live(
                    session: result.session,
                    repositories: result.repositories
                )
                appState.replaceRuntime(runtime)
                inviteCode = ""
                pairingMessage = "Paired to \(result.session.workspaceName ?? "live workspace")."
                await runtime.services.refreshFromRepositoriesImmediately()
                await runtime.services.scheduleTodayNotificationIfNeededImmediately()
            } catch {
                pairingError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func clearPairing() {
        do {
            try DevicePairingService().clearPairing()
            appState.replaceRuntime(.fixtures())
            pairingMessage = "Pairing cleared."
            pairingError = nil
        } catch {
            pairingMessage = nil
            pairingError = error.localizedDescription
        }
    }
}
