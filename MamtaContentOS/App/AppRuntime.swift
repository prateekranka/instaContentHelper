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
            services: AppServices(
                repositories: repositories,
                isLiveSupabaseRuntime: true,
                memberRole: session.memberRole,
                todayCache: todayCache,
                notifications: notifications,
                todayCard: .liveLoadingPlaceholder,
                archiveEntries: [],
                weeklyPlan: .liveLoadingPlaceholder,
                weeklyIdeas: [],
                intelligenceHome: .liveLoadingPlaceholder,
                creatorProfileSummary: .liveLoadingPlaceholder,
                weekCards: []
            )
        )
    }

    static func makeInitialRuntime(
        store: RuntimeConfigurationStoring = RuntimeConfigurationStore(),
        todayCache: any TodayCacheStoring = FileTodayCacheStore(),
        notifications: any TodayNotificationScheduling = LocalTodayNotificationScheduler(),
        debugEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppRuntime {
        if let session = PairedDeviceSession.debugEnvironmentSession(
            environment: debugEnvironment
        ) {
            return live(
                session: session,
                todayCache: todayCache,
                notifications: notifications
            )
        }

        do {
            if let session = try store.loadPairedSession() {
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

    static func makeAuthenticationShellRuntime(
        todayCache: any TodayCacheStoring = FileTodayCacheStore(),
        notifications: any TodayNotificationScheduling = LocalTodayNotificationScheduler(),
        debugEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppRuntime {
        guard let session = PairedDeviceSession.debugEnvironmentSession(
            environment: debugEnvironment
        ) else {
            return fixtures(
                todayCache: todayCache,
                notifications: notifications
            )
        }

        return live(
            session: session,
            todayCache: todayCache,
            notifications: notifications
        )
    }
}

private extension DailyCard {
    static let liveLoadingPlaceholder = DailyCard(
        title: "Loading today's card",
        context: "Live Supabase",
        effortLabel: "Checking",
        whyToday: "Fetching the latest published content.",
        scenes: []
    )
}

private extension WeeklyPlan {
    static let liveLoadingPlaceholder = WeeklyPlan(
        title: "Loading week",
        eyebrow: "LIVE SUPABASE",
        weekRange: "Checking for updates",
        readinessLine: "Loading",
        isSoftLocked: false,
        days: [],
        setupSections: []
    )
}

private extension IntelligenceHome {
    static let liveLoadingPlaceholder = IntelligenceHome(
        sourcePulse: SourcePulseSummary(
            title: "Loading sources",
            subtitle: "Checking Supabase",
            references: []
        ),
        readyForThisWeek: [],
        needsReview: [],
        ideaCandidates: [],
        recentlyUsed: [],
        librarySections: []
    )
}

private extension CreatorProfileSummary {
    static let liveLoadingPlaceholder = CreatorProfileSummary(
        displayName: "Loading",
        positioning: "Fetching the creator profile from Supabase.",
        voiceLine: "",
        noGoTopics: []
    )
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
