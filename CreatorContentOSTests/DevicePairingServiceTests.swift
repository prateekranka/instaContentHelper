import XCTest
@testable import CreatorContentOS

final class DevicePairingServiceTests: XCTestCase {
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
}
