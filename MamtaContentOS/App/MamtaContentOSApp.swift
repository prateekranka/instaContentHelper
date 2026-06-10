import SwiftUI

@main
@MainActor
struct MamtaContentOSApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MamtaContentOSAppView()
                .environment(appState)
                .environment(appState.runtime.services)
                .task {
                    await appState.restoreAuthentication()
                }
                .task {
                    await appState.observeAuthenticationChanges()
                }
                .task(id: appState.runtime.mode) {
                    guard appState.authenticationPhase == .live else { return }
                    let services = appState.runtime.services
                    if services.loadTodayFromCache() {
                        await services.scheduleTodayNotificationIfNeededImmediately()
                    }
                    await services.refreshFromRepositoriesImmediately()
                }
        }
    }
}

struct MamtaContentOSAppView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.authenticationPhase {
            case .restoring:
                AuthenticationRestoringView()
            case .live:
                switch appState.activeMode {
                case .mamta:
                    MamtaShellView()
                case .admin:
                    AdminShellView()
                }
            case .signedOut, .requestingCode, .verifyingCode, .failed:
                SignInView()
            }
        }
        .tint(MCOTheme.Color.oxblood)
    }
}

private struct AuthenticationRestoringView: View {
    var body: some View {
        ZStack {
            MCOTheme.Color.paper.ignoresSafeArea()
            ProgressView("Checking your session")
                .font(MCOType.body)
                .foregroundStyle(MCOTheme.Color.inkMuted)
                .tint(MCOTheme.Color.oxblood)
        }
        .accessibilityIdentifier("authentication-restoring")
    }
}
