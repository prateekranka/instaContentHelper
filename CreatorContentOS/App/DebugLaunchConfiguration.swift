import Foundation
import CryptoKit

/// DEBUG-only launch controls for native e2e runs.
///
/// Native mobile runners pass `-MCO_KEY VALUE` pairs because launch
/// environments are not available on every device runner. Process environment
/// values keep precedence for local scripts and existing XCTest callers.
#if DEBUG
enum DebugLaunchConfiguration {
    private static let allowedKeys: Set<String> = [
        "MCO_FORCE_FIXTURE_UI",
        "MCO_INSIGHTS_SCENARIO",
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
        guard let defaults = UserDefaults(suiteName: name) else {
            preconditionFailure("Cannot open fixture session defaults")
        }
        return defaults
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
}
#endif

private extension String {
    var fixtureNamespaceComponent: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalarString = unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        let trimmed = String(scalarString.prefix(80))
        if trimmed == self, !trimmed.isEmpty { return trimmed }
        let digest = SHA256.hash(data: Data(utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(trimmed.isEmpty ? "default" : trimmed)-\(digest)"
    }
}
