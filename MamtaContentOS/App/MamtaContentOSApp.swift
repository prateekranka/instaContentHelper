import SwiftUI

@main
@MainActor
struct MamtaContentOSApp: App {
    @State private var appState = AppState()
    @State private var runtime = AppRuntime.makeInitialRuntime()

    var body: some Scene {
        WindowGroup {
            MamtaContentOSAppView()
                .environment(appState)
                .environment(runtime.services)
                .task {
                    if runtime.services.loadTodayFromCache() {
                        await runtime.services.scheduleTodayNotificationIfNeededImmediately()
                    }
                    await runtime.services.refreshFromRepositoriesImmediately()
                }
        }
    }
}

struct MamtaContentOSAppView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.activeMode {
            case .mamta:
                MamtaShellView()
            case .admin:
                AdminShellView()
            }
        }
        .tint(MCOTheme.Color.oxblood)
    }
}
