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
        store: RuntimeConfigurationStoring = RuntimeConfigurationStore(),
        todayCache: any TodayCacheStoring = FileTodayCacheStore(),
        notifications: any TodayNotificationScheduling = LocalTodayNotificationScheduler()
    ) -> AppRuntime {
        do {
            if let session = try store.loadPairedSession() {
                let repositories = SupabaseRepositoryBundleFactory().makeRepositories(
                    context: session.context,
                    configuration: session.runtimeConfiguration
                )
                return AppRuntime(
                    mode: .live(session),
                    services: AppServices.fixtureBacked(
                        repositories: repositories,
                        todayCache: todayCache,
                        notifications: notifications
                    )
                )
            }
        } catch {
            return AppRuntime(
                mode: .fixtures,
                services: AppServices.fixtureBacked(
                    todayCache: todayCache,
                    notifications: notifications
                )
            )
        }

        return AppRuntime(
            mode: .fixtures,
            services: AppServices.fixtureBacked(
                todayCache: todayCache,
                notifications: notifications
            )
        )
    }
}
