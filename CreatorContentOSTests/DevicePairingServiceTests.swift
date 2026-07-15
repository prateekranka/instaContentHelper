import XCTest
@testable import CreatorContentOS

final class DevicePairingServiceTests: XCTestCase {
    func testPairDeviceRejectsBlankInviteCodeBeforeBootstrap() async {
        let service = DevicePairingService(
            bootstrapConfiguration: nil,
            store: DevicePairingMemoryStore()
        )

        do {
            _ = try await service.pairDevice(inviteCode: "   ")
            XCTFail("Expected blank invite code to fail before bootstrap configuration is checked.")
        } catch {
            XCTAssertEqual(error as? DevicePairingError, .blankInviteCode)
        }
    }

    func testPairDeviceRequiresBootstrapConfiguration() async {
        let service = DevicePairingService(
            bootstrapConfiguration: nil,
            store: DevicePairingMemoryStore()
        )

        do {
            _ = try await service.pairDevice(inviteCode: "INVITE-123")
            XCTFail("Expected missing bootstrap configuration to fail.")
        } catch {
            guard case RuntimeConfigurationError.missingBootstrapConfiguration = error else {
                XCTFail("Expected missing bootstrap configuration, got \(error).")
                return
            }
        }
    }

    func testPairDeviceResponseDecodesSupabaseTimestampString() throws {
        let json = """
        {
          "workspace_id": "11111111-1111-4111-8111-111111111111",
          "workspace_name": "Creator Content OS",
          "creator_id": "33333333-3333-4333-8333-333333333333",
          "creator_display_name": "Creator",
          "member_id": "55555555-5555-4555-8555-555555555551",
          "member_role": "owner",
          "device_installation_id": "66666666-6666-4666-8666-666666666661",
          "device_token": "test-device-token",
          "paired_at": "2026-06-06T04:30:12.123456+00:00"
        }
        """

        let response = try JSONDecoder().decode(
            DevicePairingResponse.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(response.memberRole, "owner")
        XCTAssertEqual(response.creatorDisplayName, "Creator")
        XCTAssertEqual(response.deviceToken, "test-device-token")
        XCTAssertNotNil(response.pairedAt)
    }

    func testPairDeviceResponseAllowsMissingTimestamp() throws {
        let json = """
        {
          "workspace_id": "11111111-1111-4111-8111-111111111111",
          "workspace_name": "Creator Content OS",
          "creator_id": "33333333-3333-4333-8333-333333333333",
          "creator_display_name": "Creator",
          "member_id": "55555555-5555-4555-8555-555555555551",
          "member_role": "owner",
          "device_installation_id": "66666666-6666-4666-8666-666666666661",
          "device_token": "test-device-token"
        }
        """

        let response = try JSONDecoder().decode(
            DevicePairingResponse.self,
            from: Data(json.utf8)
        )

        XCTAssertNil(response.pairedAt)
    }

    func testStoredSessionAndClearPairingUseRuntimeStore() throws {
        let session = makeSession()
        let store = DevicePairingMemoryStore()
        let service = DevicePairingService(
            bootstrapConfiguration: nil,
            store: store
        )

        try store.savePairedSession(session)
        XCTAssertEqual(try service.storedSession(), session)

        try service.clearPairing()
        XCTAssertNil(try service.storedSession())
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
            pairedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
    }
}

private final class DevicePairingMemoryStore: RuntimeConfigurationStoring, @unchecked Sendable {
    private var session: PairedDeviceSession?

    func loadPairedSession() throws -> PairedDeviceSession? {
        session
    }

    func savePairedSession(_ session: PairedDeviceSession) throws {
        self.session = session
    }

    func clearPairedSession() throws {
        session = nil
    }
}
