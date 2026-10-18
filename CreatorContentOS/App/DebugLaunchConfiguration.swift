import Foundation

/// DEBUG-only launch controls for native e2e runs.
///
/// Native mobile runners pass `-MCO_KEY VALUE` pairs because launch
/// environments are not available on every device runner. Process environment
/// values keep precedence for local scripts and existing XCTest callers.
#if DEBUG
enum DebugLaunchConfiguration {
    private static let allowedKeys: Set<String> = [
        "MCO_FORCE_FIXTURE_UI",
        "MCO_FORCE_APP_MODE",
        "MCO_FORCE_SIGN_IN",
        "MCO_FORCE_SCREEN",
        "MCO_RESET_ONBOARDING",
        "MCO_FORCE_ONBOARDING",
        "MCO_FORCE_EMPTY_TODAY",
        "MCO_SLOW_FIRST_IDEA",
        "MCO_FAIL_FIRST_IDEA",
        "MCO_FAIL_FIRST_IDEA_ONCE",
        "MCO_FAIL_TODAY_DECISION_SYNC_ONCE",
        "MCO_LONG_CONTENT",
        "MCO_BREAK_UI_DATA",
        "MCO_BREAK_UI_320",
        "MCO_DYNAMIC_TYPE_ACCESSIBILITY5",
        "MCO_REDUCED_MOTION",
        "MCO_QA_SESSION"
    ]

    static func value(
        for key: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> String? {
        guard allowedKeys.contains(key) else { return nil }
        if let environmentValue = environment[key] {
            return environmentValue.nilIfBlank
        }

        for index in arguments.indices {
            let argument = arguments[index]
            guard argument == "-\(key)" else { continue }
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { return nil }
            let value = arguments[valueIndex]
            guard !value.hasPrefix("-") else { return nil }
            return value.nilIfBlank
        }

        return nil
    }

    static func isEnabled(
        _ key: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        value(for: key, environment: environment, arguments: arguments) == "1"
    }

    /// Optional e2e namespace. The namespace never uses the app's standard
    /// defaults suite, so fixture state cannot overwrite a creator's state.
    static var fixtureSession: String? {
        value(for: "MCO_QA_SESSION")?.fixtureNamespaceComponent
    }

    static var fixtureDefaults: UserDefaults {
        let name = "com.contenthelper.fixture.\(fixtureSession ?? "default")"
        return UserDefaults(suiteName: name) ?? .standard
    }

    static var onboardingDefaults: UserDefaults {
        DebugLaunchConfiguration.isEnabled("MCO_FORCE_FIXTURE_UI")
            ? fixtureDefaults
            : .standard
    }

    static var fixtureCacheDirectory: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        return base
            .appendingPathComponent("CreatorContentOS", isDirectory: true)
            .appendingPathComponent("FixtureQA", isDirectory: true)
            .appendingPathComponent(fixtureSession ?? "default", isDirectory: true)
    }
}
#else
enum DebugLaunchConfiguration {
    static func value(
        for key: String,
        environment: [String: String] = [:],
        arguments: [String] = []
    ) -> String? { nil }

    static func isEnabled(
        _ key: String,
        environment: [String: String] = [:],
        arguments: [String] = []
    ) -> Bool { false }

    static var fixtureSession: String? { nil }
    static var fixtureDefaults: UserDefaults { .standard }
    static var onboardingDefaults: UserDefaults { .standard }
    static var fixtureCacheDirectory: URL? { nil }
}
#endif

private extension String {
    var fixtureNamespaceComponent: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalarString = unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        let trimmed = String(scalarString.prefix(80))
        return trimmed.isEmpty ? "default" : trimmed
    }
}
