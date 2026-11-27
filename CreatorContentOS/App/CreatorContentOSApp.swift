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
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState = AppState.makeLaunchState()
    @State private var miraDependencies = MiraDependencies.live()
    private let problemReports = MiraProblemReports()

    init() {
        problemReports.start()
        #if DEBUG
        if let value = DebugLaunchConfiguration.value(for: "MCO_APPEARANCE"),
           let launchLook = MiraLook(rawValue: value) {
            look = launchLook
        }
        if DebugLaunchConfiguration.isEnabled("MCO_DEBUG_CRASH") {
            Task {
                do {
                    try await Task.sleep(for: .seconds(3))
                } catch {
                    return
                }
                fatalError("Mira debug crash")
            }
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
                .environment(problemReports)
                .task {
                    await appState.restoreAuthentication()
                }
                .task {
                    await appState.observeAuthenticationChanges()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            problemReports.setRunning(phase != .background)
        }
    }
}
