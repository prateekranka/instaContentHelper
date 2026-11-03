import SwiftUI

@main
@MainActor
struct CreatorContentOSApp: App {
    @State private var appState = AppState.makeLaunchState()
    @State private var miraDependencies = MiraDependencies.live()

    var body: some Scene {
        WindowGroup {
            MiraRootView(dependencies: miraDependencies)
                .environment(appState)
                .environment(appState.runtime.services)
                .environment(miraDependencies)
                .task {
                    await appState.restoreAuthentication()
                }
                .task {
                    await appState.observeAuthenticationChanges()
                }
        }
    }
}
