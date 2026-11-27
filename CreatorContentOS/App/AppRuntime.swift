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

    static func fixtures() -> AppRuntime {
        let context = WorkspaceContext.creatorFixture
        return AppRuntime(
            mode: .fixtures,
            services: AppServices(
                isLiveSupabaseRuntime: false,
                aiConsentStore: UserDefaultsAIConsentStore(
                    workspaceID: context.workspaceID,
                    creatorID: context.creatorID,
                    defaults: DebugLaunchConfiguration.fixtureDefaults)))
    }

    static func live(session: PairedDeviceSession) -> AppRuntime {
        AppRuntime(
            mode: .live(session),
            services: AppServices(
                isLiveSupabaseRuntime: true,
                aiConsentStore: liveConsentStore(session: session)))
    }

    private static func liveConsentStore(session: PairedDeviceSession) -> any AIConsentStoring {
        #if DEBUG
        if let override = LaunchAIConsentStore() { return override }
        #endif
        return UserDefaultsAIConsentStore(workspaceID: session.workspaceID, creatorID: session.creatorID)
    }

    static func makeAuthenticationShellRuntime(
        debugEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppRuntime {
        if let session = PairedDeviceSession.debugEnvironmentSession(environment: debugEnvironment) {
            return live(session: session)
        }
        return fixtures()
    }
}

#if DEBUG
private struct LaunchAIConsentStore: AIConsentStoring {
    private let record: AIConsentRecord?

    init?() {
        switch DebugLaunchConfiguration.value(for: "MCO_AI_CONSENT_OVERRIDE") {
        case "unknown":
            record = nil
        case "declined":
            record = AIConsentRecord(
                consentVersion: AIConsentPolicy.currentVersion,
                decision: .declined,
                decidedAt: SupabaseDateFormatting.isoTimestampString(),
                destinationsAcknowledged: AIConsentPolicy.destinations)
        default:
            return nil
        }
    }

    func load() -> AIConsentRecord? { record }
    func save(_ record: AIConsentRecord) {}
    func clear() {}
}
#endif

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

enum DebugLaunchFlags {
    static var forceFixtureUI: Bool {
        DebugLaunchConfiguration.isEnabled("MCO_FORCE_FIXTURE_UI")
    }

    static var insightsScenario: String? {
        DebugLaunchConfiguration.value(for: "MCO_INSIGHTS_SCENARIO")
    }
}
