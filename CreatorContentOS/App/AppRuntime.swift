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
        todayCache: any TodayCacheStoring = DebugLaunchConfiguration.fixtureTodayCache,
        notifications: any TodayNotificationScheduling = LocalTodayNotificationScheduler()
    ) -> AppRuntime {
        let services = AppServices.fixtureBacked(
            todayCache: todayCache,
            notifications: notifications,
            acceptedGenerationStore: UserDefaultsAcceptedDayGenerationStore(defaults: DebugLaunchConfiguration.fixtureDefaults),
            aiConsentStore: UserDefaultsAIConsentStore(
                workspaceID: WorkspaceContext.creatorFixture.workspaceID,
                creatorID: WorkspaceContext.creatorFixture.creatorID,
                defaults: DebugLaunchConfiguration.fixtureDefaults
            )
        )
#if DEBUG
        if !DebugLaunchFlags.forceEmptyToday {
            // Seed the same generated package used by Plan into Today. The
            // package keeps one ID and one date across the native e2e relaunch.
            var draft = services.loadTodayFromCache()
                ? GeneratedDailyCardDraft(fromPublishedCard: services.todayCard)
                : DebugLaunchFlags.fixtureDailyCardDraft
            if DebugLaunchFlags.uiFixtureData != .demo {
                draft = DebugLaunchFlags.uiFixtureData.applying(to: draft)
            }
            draft.scheduledDate = services.currentTodayDateString
            draft.status = "ready"
            services.dayBriefGeneratedCards[services.currentTodayDateString] = draft
            services.todayCard = draft.dailyCard(completionState: services.todayCard.completionState)
            services.weekCards = services.weekCards.map { card in
                guard card.scheduledDate == services.currentTodayDateString else { return card }
                return services.todayCard
            }
        }
#endif
        return AppRuntime(
            mode: .fixtures,
            services: services
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
            configuration: session.runtimeConfiguration,
            creatorDisplayName: session.creatorDisplayName ?? "Creator"
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
                weekCards: [],
                todayContentState: .loading
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
        title: "Loading daily content",
        eyebrow: "LIVE SUPABASE",
        weekRange: "Checking for updates",
        readinessLine: "Loading",
        isSoftLocked: false,
        days: [],
        weeklyBriefText: "",
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
    static let liveLoadingPlaceholder = CreatorProfileSummary.emptyLiveFallback(displayName: "Loading")
}

private extension PairedDeviceSession {
    static func debugEnvironmentSession(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> PairedDeviceSession? {
        func value(_ key: String) -> String? {
            if let environmentValue = environment[key]?.nilIfBlank {
                return environmentValue
            }
            guard let bundleValue = bundle.object(forInfoDictionaryKey: key) as? String else {
                return nil
            }
            return bundleValue.nilIfBlank?.hasPrefix("$(") == true ? nil : bundleValue.nilIfBlank
        }

        guard
            let rawURL = value("MCO_SUPABASE_URL"),
            let projectURL = URL(string: rawURL),
            let publishableKey = value("MCO_SUPABASE_PUBLISHABLE_KEY"),
            let workspaceID = UUID(uuidString: value("MCO_DEBUG_PAIRED_WORKSPACE_ID") ?? ""),
            let creatorID = UUID(uuidString: value("MCO_DEBUG_PAIRED_CREATOR_ID") ?? ""),
            let memberID = UUID(uuidString: value("MCO_DEBUG_PAIRED_MEMBER_ID") ?? ""),
            let deviceInstallationID = UUID(uuidString: value("MCO_DEBUG_PAIRED_DEVICE_INSTALLATION_ID") ?? ""),
            let deviceToken = value("MCO_DEBUG_PAIRED_DEVICE_TOKEN")
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
            workspaceName: value("MCO_DEBUG_PAIRED_WORKSPACE_NAME") ?? "Local Workspace",
            creatorDisplayName: value("MCO_DEBUG_PAIRED_CREATOR_DISPLAY_NAME") ?? "Creator",
            memberRole: value("MCO_DEBUG_PAIRED_MEMBER_ROLE") ?? "owner",
            pairedAt: Date()
        )
    }
}

#if DEBUG
enum DebugLaunchFlags {
    static var forceFixtureUI: Bool {
        DebugLaunchConfiguration.isEnabled("MCO_FORCE_FIXTURE_UI")
    }

    static var forceAppMode: String? {
        DebugLaunchConfiguration.value(for: "MCO_FORCE_APP_MODE")
    }

    static var forceScreen: String? {
        DebugLaunchConfiguration.value(for: "MCO_FORCE_SCREEN")
    }

    private static func isEnabled(_ key: String) -> Bool {
        DebugLaunchConfiguration.isEnabled(key)
    }

    /// Start fixture Today empty so first-idea confirm runs generate + makeDayAvailable.
    static var forceEmptyToday: Bool {
        isEnabled("MCO_FORCE_EMPTY_TODAY")
    }

    /// Slow fixture first-idea generation for screenshot capture only.
    static var slowFirstIdea: Bool {
        isEnabled("MCO_SLOW_FIRST_IDEA")
    }

    /// Fail fixture first-idea generation with a recoverable error for QA.
    static var failFirstIdea: Bool {
        isEnabled("MCO_FAIL_FIRST_IDEA")
    }

    /// Fail the first fixture generation call, then allow the retry.
    static var failFirstIdeaOnce: Bool {
        isEnabled("MCO_FAIL_FIRST_IDEA_ONCE")
    }

    /// Fail the first fixture Today decision sync call, then allow the retry.
    static var failTodayDecisionSyncOnce: Bool {
        isEnabled("MCO_FAIL_TODAY_DECISION_SYNC_ONCE")
    }

    static var longContent: Bool {
        isEnabled("MCO_LONG_CONTENT")
    }

    static var uiFixtureData: PocketUIFixtureData {
        PocketUIFixtureData(rawValue: DebugLaunchConfiguration.fixtureDefaults.string(forKey: "break-ui-data")
            ?? DebugLaunchConfiguration.value(for: "MCO_BREAK_UI_DATA") ?? "demo") ?? .demo
    }

    static var forceAccessibility5: Bool {
        isEnabled("MCO_DYNAMIC_TYPE_ACCESSIBILITY5")
    }

    static var forceNarrowFixtureContainer: Bool {
        forceFixtureUI && isEnabled("MCO_BREAK_UI_320")
    }

    static var forceReducedMotion: Bool {
        isEnabled("MCO_REDUCED_MOTION")
    }

    static var fixtureDailyCardDraft: GeneratedDailyCardDraft {
        var draft = GeneratedDailyCardDraft.storyboardBreakdownFixture
        draft.sceneList = draft.sceneList.enumerated().map { index, scene in
            ShotScene(
                id: UUID(uuidString: String(format: "1407E44A-1F70-4B96-8EE2-%012d", index + 1))!,
                number: scene.number, title: scene.title, duration: scene.duration, symbol: scene.symbol
            )
        }
        return uiFixtureData.applying(to: longContent ? draft.withLongContent : draft)
    }

    static var fixtureFirstIdeaDelayNanoseconds: UInt64 {
        slowFirstIdea ? 20_000_000_000 : 450_000_000
    }
}
#else
enum DebugLaunchFlags {
    static var forceFixtureUI: Bool { false }
    static var forceAppMode: String? { nil }
    static var forceScreen: String? { nil }
    static var forceEmptyToday: Bool { false }
    static var slowFirstIdea: Bool { false }
    static var failFirstIdea: Bool { false }
    static var failFirstIdeaOnce: Bool { false }
    static var failTodayDecisionSyncOnce: Bool { false }
    static var longContent: Bool { false }
    static var forceAccessibility5: Bool { false }
    static var forceReducedMotion: Bool { false }
    static var fixtureFirstIdeaDelayNanoseconds: UInt64 { 450_000_000 }
}
#endif

private extension DebugLaunchConfiguration {
    static var fixtureTodayCache: any TodayCacheStoring {
#if DEBUG
        FileTodayCacheStore(baseDirectory: fixtureCacheDirectory)
#else
        FileTodayCacheStore()
#endif
    }
}
