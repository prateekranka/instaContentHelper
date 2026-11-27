import SwiftUI

enum MiraLook: String, CaseIterable {
    case system
    case light
    case dark

    static let defaultsKey = "mira.look"

    var title: String {
        switch self {
        case .system: "Same as phone"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@main
@MainActor
struct CreatorContentOSApp: App {
    @AppStorage(MiraLook.defaultsKey) private var look: MiraLook = .system
    @State private var appState = AppState.makeLaunchState()
    @State private var miraDependencies = MiraDependencies.live()

    init() {
        #if DEBUG
        if let value = DebugLaunchConfiguration.value(for: "MCO_APPEARANCE"),
           let launchLook = MiraLook(rawValue: value) {
            look = launchLook
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MiraRootView(dependencies: miraDependencies, colorSchemePreference: look.colorScheme)
                .preferredColorScheme(look.colorScheme)
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
