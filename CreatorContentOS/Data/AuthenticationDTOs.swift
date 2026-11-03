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

enum AuthenticationSessionEvent: Sendable {
    case signedOut
    case userDeleted
}
