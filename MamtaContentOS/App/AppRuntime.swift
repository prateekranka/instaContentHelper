import Foundation

enum AppRuntimeMode: Hashable, Sendable {
    case fixtures
    case live(PairedDeviceSession)

    var label: String {
        switch self {
        case .fixtures:
            "Fixtures"
        case .live(let session):
            "Live Supabase - \(session.creatorDisplayName ?? "Creator")"
        }
    }
}

@MainActor
struct AppRuntime {
    let mode: AppRuntimeMode
    let services: AppServices

    static func makeInitialRuntime(
        store: RuntimeConfigurationStoring = RuntimeConfigurationStore()
    ) -> AppRuntime {
        do {
            if let session = try store.loadPairedSession() {
                let repositories = SupabaseRepositoryBundleFactory().makeRepositories(
                    context: session.context,
                    configuration: session.runtimeConfiguration
                )
                return AppRuntime(
                    mode: .live(session),
                    services: AppServices.fixtureBacked(repositories: repositories)
                )
            }
        } catch {
            return AppRuntime(mode: .fixtures, services: AppServices.preview)
        }

        return AppRuntime(mode: .fixtures, services: AppServices.preview)
    }
}
