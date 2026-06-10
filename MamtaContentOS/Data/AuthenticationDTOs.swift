import Foundation

struct AuthenticationSessionExchangeRequest: Encodable, Sendable {
    var deviceName: String
    var platform: String
    var deviceInstallationID: UUID

    enum CodingKeys: String, CodingKey {
        case deviceName = "device_name"
        case platform
        case deviceInstallationID = "device_installation_id"
    }
}

struct AuthenticationSessionExchangeResponse: Decodable, Hashable, Sendable {
    var workspaceID: UUID
    var workspaceName: String?
    var creatorID: UUID
    var creatorDisplayName: String?
    var memberID: UUID
    var memberRole: String
    var memberEmail: String?
    var deviceInstallationID: UUID
    var deviceToken: String
    var pairedAt: String?

    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case workspaceName = "workspace_name"
        case creatorID = "creator_id"
        case creatorDisplayName = "creator_display_name"
        case memberID = "member_id"
        case memberRole = "member_role"
        case memberEmail = "member_email"
        case deviceInstallationID = "device_installation_id"
        case deviceToken = "device_token"
        case pairedAt = "paired_at"
    }
}

struct RevokeDeviceSessionRequest: Encodable, Sendable {
    var deviceInstallationID: UUID

    enum CodingKeys: String, CodingKey {
        case deviceInstallationID = "device_installation_id"
    }
}

struct AuthenticationFunctionErrorResponse: Decodable, Sendable {
    var error: String?
    var code: String?
    var message: String?

    var stableCode: String? {
        code?.nilIfBlank ?? error?.nilIfBlank
    }
}

struct TesterAccessRecord: Decodable, Identifiable, Hashable, Sendable {
    var id: UUID
    var email: String
    var displayName: String?
    var role: String
    var status: String
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case role
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ManageTesterRequest: Encodable, Sendable {
    var action: String
    var email: String?
    var memberID: UUID?
    var displayName: String?

    enum CodingKeys: String, CodingKey {
        case action
        case email
        case memberID = "member_id"
        case displayName = "display_name"
    }
}

struct ManageTesterListResponse: Decodable, Sendable {
    var testers: [TesterAccessRecord]
}

struct ManageTesterMutationResponse: Decodable, Sendable {
    var tester: TesterAccessRecord
    var otpSent: Bool?
    var accessRevoked: Bool?

    enum CodingKeys: String, CodingKey {
        case tester
        case otpSent = "otp_sent"
        case accessRevoked = "access_revoked"
    }
}

enum AuthenticationSessionEvent: Sendable {
    case signedOut
    case userDeleted
}
