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
                .task(id: appState.runtime.mode) {
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
