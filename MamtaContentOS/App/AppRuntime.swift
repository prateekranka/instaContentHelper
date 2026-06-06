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

    static func fixtures(
        todayCache: any TodayCacheStoring = FileTodayCacheStore(),
        notifications: any TodayNotificationScheduling = LocalTodayNotificationScheduler()
    ) -> AppRuntime {
        AppRuntime(
            mode: .fixtures,
            services: AppServices.fixtureBacked(
                todayCache: todayCache,
                notifications: notifications
            )
        )
    }

    static func live(
        session: PairedDeviceSession,
        repositories: AppRepositories? = nil,
        todayCache: any TodayCacheStoring = FileTodayCacheStore(),
        notifications: any TodayNotificationScheduling = LocalTodayNotificationScheduler()
    ) -> AppRuntime {
        let repositories = repositories ?? SupabaseRepositoryBundleFactory().makeRepositories(
            context: session.context,
            configuration: session.runtimeConfiguration
        )
        return AppRuntime(
            mode: .live(session),
            services: AppServices.fixtureBacked(
                repositories: repositories,
                isLiveSupabaseRuntime: true,
                todayCache: todayCache,
                notifications: notifications
            )
        )
    }

    static func makeInitialRuntime(
        store: RuntimeConfigurationStoring = RuntimeConfigurationStore(),
        todayCache: any TodayCacheStoring = FileTodayCacheStore(),
        notifications: any TodayNotificationScheduling = LocalTodayNotificationScheduler()
    ) -> AppRuntime {
        do {
            if let session = try store.loadPairedSession() {
                return live(
                    session: session,
                    todayCache: todayCache,
                    notifications: notifications
                )
            }

            if let session = PairedDeviceSession.debugEnvironmentSession() {
                return live(
                    session: session,
                    todayCache: todayCache,
                    notifications: notifications
                )
            }
        } catch {
            return fixtures(
                todayCache: todayCache,
                notifications: notifications
            )
        }

        return fixtures(
            todayCache: todayCache,
            notifications: notifications
        )
    }
}

private extension PairedDeviceSession {
    static func debugEnvironmentSession(environment: [String: String] = ProcessInfo.processInfo.environment) -> PairedDeviceSession? {
        guard
            let rawURL = environment["MCO_SUPABASE_URL"],
            let projectURL = URL(string: rawURL),
            let publishableKey = environment["MCO_SUPABASE_PUBLISHABLE_KEY"]?.nilIfBlank,
            let workspaceID = UUID(uuidString: environment["MCO_DEBUG_PAIRED_WORKSPACE_ID"] ?? ""),
            let creatorID = UUID(uuidString: environment["MCO_DEBUG_PAIRED_CREATOR_ID"] ?? ""),
            let memberID = UUID(uuidString: environment["MCO_DEBUG_PAIRED_MEMBER_ID"] ?? ""),
            let deviceInstallationID = UUID(uuidString: environment["MCO_DEBUG_PAIRED_DEVICE_INSTALLATION_ID"] ?? ""),
            let deviceToken = environment["MCO_DEBUG_PAIRED_DEVICE_TOKEN"]?.nilIfBlank
        else {
            return nil
        }

        return PairedDeviceSession(
            projectURL: projectURL,
            publishableKey: publishableKey,
            workspaceID: workspaceID,
            creatorID: creatorID,
            memberID: memberID,
            deviceInstallationID: deviceInstallationID,
            deviceToken: deviceToken,
            workspaceName: environment["MCO_DEBUG_PAIRED_WORKSPACE_NAME"]?.nilIfBlank ?? "Local Workspace",
            creatorDisplayName: environment["MCO_DEBUG_PAIRED_CREATOR_DISPLAY_NAME"]?.nilIfBlank ?? "Mamta",
            memberRole: environment["MCO_DEBUG_PAIRED_MEMBER_ROLE"]?.nilIfBlank ?? "owner",
            pairedAt: Date()
        )
    }
}
