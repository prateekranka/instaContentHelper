import Foundation
import Supabase

struct DevicePairingRequest: Encodable, Sendable {
    var inviteCode: String
    var deviceName: String
    var platform: String

    enum CodingKeys: String, CodingKey {
        case inviteCode = "invite_code"
        case deviceName = "device_name"
        case platform
    }
}

struct DevicePairingResponse: Decodable, Hashable, Sendable {
    var workspaceID: UUID
    var workspaceName: String?
    var creatorID: UUID
    var creatorDisplayName: String?
    var memberID: UUID
    var memberRole: String
    var deviceInstallationID: UUID
    var deviceToken: String
    var pairedAt: Date?

    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case workspaceName = "workspace_name"
        case creatorID = "creator_id"
        case creatorDisplayName = "creator_display_name"
        case memberID = "member_id"
        case memberRole = "member_role"
        case deviceInstallationID = "device_installation_id"
        case deviceToken = "device_token"
        case pairedAt = "paired_at"
    }

    init(
        workspaceID: UUID,
        workspaceName: String?,
        creatorID: UUID,
        creatorDisplayName: String?,
        memberID: UUID,
        memberRole: String,
        deviceInstallationID: UUID,
        deviceToken: String,
        pairedAt: Date?
    ) {
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
        self.creatorID = creatorID
        self.creatorDisplayName = creatorDisplayName
        self.memberID = memberID
        self.memberRole = memberRole
        self.deviceInstallationID = deviceInstallationID
        self.deviceToken = deviceToken
        self.pairedAt = pairedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaceID = try container.decode(UUID.self, forKey: .workspaceID)
        workspaceName = try container.decodeIfPresent(String.self, forKey: .workspaceName)
        creatorID = try container.decode(UUID.self, forKey: .creatorID)
        creatorDisplayName = try container.decodeIfPresent(String.self, forKey: .creatorDisplayName)
        memberID = try container.decode(UUID.self, forKey: .memberID)
        memberRole = try container.decode(String.self, forKey: .memberRole)
        deviceInstallationID = try container.decode(UUID.self, forKey: .deviceInstallationID)
        deviceToken = try container.decode(String.self, forKey: .deviceToken)

        if let rawPairedAt = try container.decodeIfPresent(String.self, forKey: .pairedAt) {
            pairedAt = SupabaseTimestampParser.date(from: rawPairedAt)
        } else {
            pairedAt = nil
        }
    }
}

enum SupabaseTimestampParser {
    static func date(from rawValue: String) -> Date? {
        let rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else { return nil }

        for formatter in makeISOFormatters() {
            if let date = formatter.date(from: rawValue) {
                return date
            }
        }

        for dateFormat in dateFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = dateFormat
            if let date = formatter.date(from: rawValue) {
                return date
            }
        }

        return nil
    }

    private static func makeISOFormatters() -> [ISO8601DateFormatter] {
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return [fractional, standard]
    }

    private static let dateFormats = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ssXXXXX"
    ]
}

struct DevicePairingResult: Sendable {
    var session: PairedDeviceSession
    var repositories: AppRepositories
}

enum DevicePairingError: LocalizedError {
    case blankInviteCode

    var errorDescription: String? {
        switch self {
        case .blankInviteCode:
            "Invite code cannot be blank."
        }
    }
}

struct DevicePairingService {
    private let bootstrapConfiguration: SupabaseBootstrapConfiguration?
    private let store: RuntimeConfigurationStoring
    private let deviceNameProvider: @Sendable () -> String

    init(
        bootstrapConfiguration: SupabaseBootstrapConfiguration? = .fromInfoDictionary(),
        store: RuntimeConfigurationStoring = RuntimeConfigurationStore(),
        deviceNameProvider: @escaping @Sendable () -> String = { "iPhone" }
    ) {
        self.bootstrapConfiguration = bootstrapConfiguration
        self.store = store
        self.deviceNameProvider = deviceNameProvider
    }

    func pairDevice(inviteCode: String) async throws -> DevicePairingResult {
        let trimmedCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            throw DevicePairingError.blankInviteCode
        }

        guard let bootstrapConfiguration else {
            throw RuntimeConfigurationError.missingBootstrapConfiguration
        }

        let client = SupabaseClientFactory().makeClient(
            configuration: bootstrapConfiguration.runtimeConfiguration
        )

        let response: DevicePairingResponse = try await client.functions.invoke(
            "pair-device",
            options: FunctionInvokeOptions(
                body: DevicePairingRequest(
                    inviteCode: trimmedCode,
                    deviceName: deviceNameProvider(),
                    platform: "ios"
                )
            )
        )

        let session = PairedDeviceSession(
            projectURL: bootstrapConfiguration.projectURL,
            publishableKey: bootstrapConfiguration.publishableKey,
            workspaceID: response.workspaceID,
            creatorID: response.creatorID,
            memberID: response.memberID,
            deviceInstallationID: response.deviceInstallationID,
            deviceToken: response.deviceToken,
            workspaceName: response.workspaceName,
            creatorDisplayName: response.creatorDisplayName,
            memberRole: response.memberRole,
            pairedAt: response.pairedAt ?? Date()
        )

        try store.savePairedSession(session)

        let repositories = SupabaseRepositoryBundleFactory().makeRepositories(
            context: session.context,
            configuration: session.runtimeConfiguration
        )

        return DevicePairingResult(session: session, repositories: repositories)
    }

    func clearPairing() throws {
        try store.clearPairedSession()
    }

    func storedSession() throws -> PairedDeviceSession? {
        try store.loadPairedSession()
    }
}
