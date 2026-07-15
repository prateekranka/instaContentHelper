import XCTest
@testable import CreatorContentOS

final class RuntimeConfigurationTests: XCTestCase {
    func testBootstrapConfigurationAcceptsValidBundleValues() throws {
        let bundle = try makeBundle(
            info: [
                "MCO_SUPABASE_URL": "https://zogvvrxhiwozjmufvddu.supabase.co",
                "MCO_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_test_key_12345"
            ]
        )

        let configuration = try XCTUnwrap(
            SupabaseBootstrapConfiguration.fromInfoDictionary(bundle, environment: [:])
        )

        XCTAssertEqual(configuration.projectURL.absoluteString, "https://zogvvrxhiwozjmufvddu.supabase.co")
        XCTAssertEqual(configuration.publishableKey, "sb_publishable_test_key_12345")
        XCTAssertEqual(configuration.runtimeConfiguration.projectURL, configuration.projectURL)
        XCTAssertEqual(configuration.runtimeConfiguration.publishableKey, configuration.publishableKey)
        XCTAssertNil(configuration.runtimeConfiguration.deviceToken)
    }

    func testBootstrapConfigurationRejectsUnresolvedBuildSettingPlaceholders() throws {
        let bundle = try makeBundle(
            info: [
                "MCO_SUPABASE_URL": "$(MCO_SUPABASE_URL)",
                "MCO_SUPABASE_PUBLISHABLE_KEY": "$(MCO_SUPABASE_PUBLISHABLE_KEY)"
            ]
        )

        XCTAssertNil(SupabaseBootstrapConfiguration.fromInfoDictionary(bundle, environment: [:]))
    }

    func testBootstrapConfigurationRejectsBlankBundleURL() throws {
        let bundle = try makeBundle(
            info: [
                "MCO_SUPABASE_URL": " ",
                "MCO_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_test_key_12345"
            ]
        )

        XCTAssertNil(SupabaseBootstrapConfiguration.fromInfoDictionary(bundle, environment: [:]))
    }

    func testBootstrapConfigurationRejectsBlankPublishableKey() throws {
        let bundle = try makeBundle(
            info: [
                "MCO_SUPABASE_URL": "https://zogvvrxhiwozjmufvddu.supabase.co",
                "MCO_SUPABASE_PUBLISHABLE_KEY": " "
            ]
        )

        XCTAssertNil(SupabaseBootstrapConfiguration.fromInfoDictionary(bundle, environment: [:]))
    }

    func testBootstrapConfigurationEnvironmentOverridesBundleValues() throws {
        let bundle = try makeBundle(
            info: [
                "MCO_SUPABASE_URL": "$(MCO_SUPABASE_URL)",
                "MCO_SUPABASE_PUBLISHABLE_KEY": "$(MCO_SUPABASE_PUBLISHABLE_KEY)"
            ]
        )

        let configuration = try XCTUnwrap(
            SupabaseBootstrapConfiguration.fromInfoDictionary(
                bundle,
                environment: [
                    "MCO_SUPABASE_URL": "https://override.supabase.co",
                    "MCO_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_override_key_12345"
                ]
            )
        )

        XCTAssertEqual(configuration.projectURL.absoluteString, "https://override.supabase.co")
        XCTAssertEqual(configuration.publishableKey, "sb_publishable_override_key_12345")
    }

    func testRuntimeStoreRoundTripsPairedSession() throws {
        let keychain = RuntimeConfigurationMemoryKeychain()
        let store = RuntimeConfigurationStore(keychain: keychain)
        let session = makeSession()

        try store.savePairedSession(session)
        let restored = try store.loadPairedSession()

        XCTAssertEqual(restored, session)
    }

    func testRuntimeStoreReturnsNilWhenSessionMissing() throws {
        let store = RuntimeConfigurationStore(keychain: RuntimeConfigurationMemoryKeychain())

        XCTAssertNil(try store.loadPairedSession())
    }

    func testRuntimeStoreReportsDecodingFailureForCorruptSessionData() throws {
        let keychain = RuntimeConfigurationMemoryKeychain()
        try keychain.save(Data("not-json".utf8), for: RuntimeKeychainKey.pairedDeviceSession)
        let store = RuntimeConfigurationStore(keychain: keychain)

        do {
            _ = try store.loadPairedSession()
            XCTFail("Expected corrupt stored session data to throw.")
        } catch {
            guard case RuntimeConfigurationError.decodingFailed = error else {
                XCTFail("Expected decodingFailed, got \(error).")
                return
            }
        }
    }

    func testRuntimeStorePreservesKeychainFailures() throws {
        let keychain = RuntimeConfigurationMemoryKeychain(
            dataError: RuntimeConfigurationError.keychainStatus(-25300),
            saveError: RuntimeConfigurationError.keychainStatus(-34018),
            deleteError: RuntimeConfigurationError.keychainStatus(-25299)
        )
        let store = RuntimeConfigurationStore(keychain: keychain)
        let session = makeSession()

        do {
            _ = try store.loadPairedSession()
            XCTFail("Expected load keychain failure.")
        } catch {
            guard case RuntimeConfigurationError.keychainStatus(-25300) = error else {
                XCTFail("Expected load keychain status, got \(error).")
                return
            }
        }

        do {
            try store.savePairedSession(session)
            XCTFail("Expected save keychain failure.")
        } catch {
            guard case RuntimeConfigurationError.keychainStatus(-34018) = error else {
                XCTFail("Expected save keychain status, got \(error).")
                return
            }
        }

        do {
            try store.clearPairedSession()
            XCTFail("Expected clear keychain failure.")
        } catch {
            guard case RuntimeConfigurationError.keychainStatus(-25299) = error else {
                XCTFail("Expected clear keychain status, got \(error).")
                return
            }
        }
    }

    private func makeBundle(info: [String: String]) throws -> Bundle {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("bundle")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        var plist: [String: Any] = [
            "CFBundleIdentifier": "com.creatorcontenthelper.tests.\(UUID().uuidString)",
            "CFBundleName": "RuntimeConfigurationTestBundle",
            "CFBundlePackageType": "BNDL",
            "CFBundleVersion": "1"
        ]
        info.forEach { plist[$0.key] = $0.value }

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: bundleURL.appendingPathComponent("Info.plist"))

        return try XCTUnwrap(Bundle(url: bundleURL))
    }

    private func makeSession() -> PairedDeviceSession {
        PairedDeviceSession(
            projectURL: URL(string: "https://example.supabase.co")!,
            publishableKey: "sb_publishable_test_key",
            workspaceID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            creatorID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            memberID: UUID(uuidString: "55555555-5555-4555-8555-555555555551")!,
            deviceInstallationID: UUID(uuidString: "66666666-6666-4666-8666-666666666661")!,
            deviceToken: "test-device-token",
            workspaceName: "Creator Content OS",
            creatorDisplayName: "Creator",
            memberRole: "owner",
            pairedAt: Date(timeIntervalSince1970: 1_780_000_000),
            authenticatedEmail: "tester@example.com"
        )
    }
}

private final class RuntimeConfigurationMemoryKeychain: KeychainStoring, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let dataError: Error?
    private let saveError: Error?
    private let deleteError: Error?

    init(
        dataError: Error? = nil,
        saveError: Error? = nil,
        deleteError: Error? = nil
    ) {
        self.dataError = dataError
        self.saveError = saveError
        self.deleteError = deleteError
    }

    func data(for account: String) throws -> Data? {
        if let dataError {
            throw dataError
        }
        return values[account]
    }

    func save(_ data: Data, for account: String) throws {
        if let saveError {
            throw saveError
        }
        values[account] = data
    }

    func deleteData(for account: String) throws {
        if let deleteError {
            throw deleteError
        }
        values[account] = nil
    }
}
