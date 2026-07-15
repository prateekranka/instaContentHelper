import SwiftUI

@main
@MainActor
struct CreatorContentOSApp: App {
    @State private var appState = AppState.makeLaunchState()

    var body: some Scene {
        WindowGroup {
            CreatorContentOSAppView()
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
#if DEBUG
                    services.applyDebugWeekStartOverrideIfNeeded()
#endif
                }
        }
    }
}

struct CreatorContentOSAppView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
#if DEBUG
            if appState.authenticationPhase == .live,
               let forcedScreen = DebugForcedScreen.current {
                forcedScreen.view
            } else {
                appView
            }
#else
            appView
#endif
        }
        .tint(MCOTheme.Color.oxblood)
    }

    @ViewBuilder
    private var appView: some View {
        Group {
            switch appState.authenticationPhase {
            case .restoring:
                AuthenticationRestoringView()
            case .live:
                switch appState.activeMode {
                case .creator:
                    CreatorShellView()
                case .admin:
                    AdminShellView()
                }
            case .signedOut, .requestingCode, .verifyingCode, .failed:
                SignInView()
            }
        }
    }
}

private extension AppState {
    static func makeLaunchState(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppState {
#if DEBUG
        if environment["MCO_FORCE_SIGN_IN"] == "1" {
            return AppState(authenticationPhase: .signedOut)
        }

        if environment["MCO_FORCE_FIXTURE_UI"] == "1" {
            let mode: AppMode = environment["MCO_FORCE_APP_MODE"] == "admin" ? .admin : .creator
            return AppState(
                activeMode: mode,
                runtime: .fixtures(),
                authenticationPhase: .live
            )
        }
#endif
        return AppState()
    }
}

#if DEBUG
private enum DebugForcedScreen: String {
    case aiRunway = "ai-runway"
    case storyboardCard = "storyboard-card"
    case testerAccess = "tester-access"

    static var current: DebugForcedScreen? {
        guard ProcessInfo.processInfo.environment["MCO_FORCE_FIXTURE_UI"] == "1",
              let rawValue = ProcessInfo.processInfo.environment["MCO_FORCE_SCREEN"]
        else {
            return nil
        }

        return DebugForcedScreen(rawValue: rawValue)
    }

    @ViewBuilder
    var view: some View {
        switch self {
        case .aiRunway:
            AIRunwayView()
        case .storyboardCard:
            DebugStoryboardCardScreen()
        case .testerAccess:
            TesterAccessView()
        }
    }
}

private struct DebugStoryboardCardScreen: View {
    var body: some View {
        NavigationStack {
            ZStack {
                MCOTheme.Color.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: MCOSpace.l) {
                        Text("Storyboard card preview")
                            .font(MCOType.screenTitle)
                            .foregroundStyle(MCOTheme.Color.ink)
                        GeneratedDayPlannedContent(card: .storyboardBreakdownFixture)
                    }
                    .padding(.horizontal, MCOSpace.l)
                    .padding(.top, MCOSpace.l)
                    .padding(.bottom, MCOSpace.xl)
                }
            }
        }
    }
}
#endif

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
