import Foundation
import Security

struct PairedDeviceSession: Codable, Hashable, Sendable {
    var projectURL: URL
    var publishableKey: String
    var workspaceID: UUID
    var creatorID: UUID
    var memberID: UUID
    var deviceInstallationID: UUID
    var deviceToken: String
    var workspaceName: String?
    var creatorDisplayName: String?
    var memberRole: String
    var pairedAt: Date
    var authenticatedEmail: String? = nil

    var context: WorkspaceContext {
        WorkspaceContext(
            workspaceID: workspaceID,
            creatorID: creatorID,
            memberID: memberID
        )
    }

    var runtimeConfiguration: SupabaseRuntimeConfiguration {
        SupabaseRuntimeConfiguration(
            projectURL: projectURL,
            publishableKey: publishableKey,
            deviceToken: deviceToken
        )
    }

    func withAuthenticatedEmail(_ email: String?) -> PairedDeviceSession {
        var copy = self
        copy.authenticatedEmail = email?.nilIfBlank ?? authenticatedEmail
        return copy
    }
}

struct SupabaseBootstrapConfiguration: Hashable, Sendable {
    var projectURL: URL
    var publishableKey: String

    static func fromInfoDictionary(
        _ bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SupabaseBootstrapConfiguration? {
        let rawURL = environment["MCO_SUPABASE_URL"]
            ?? bundle.object(forInfoDictionaryKey: "MCO_SUPABASE_URL") as? String
        let rawKey = environment["MCO_SUPABASE_PUBLISHABLE_KEY"]
            ?? bundle.object(forInfoDictionaryKey: "MCO_SUPABASE_PUBLISHABLE_KEY") as? String

        guard
            let rawURL = rawURL?.nilIfBlank,
            !rawURL.hasPrefix("$("),
            let projectURL = URL(string: rawURL),
            let rawKey = rawKey?.nilIfBlank,
            !rawKey.hasPrefix("$(")
        else {
            return nil
        }

        return SupabaseBootstrapConfiguration(
            projectURL: projectURL,
            publishableKey: rawKey
        )
    }

    var runtimeConfiguration: SupabaseRuntimeConfiguration {
        SupabaseRuntimeConfiguration(
            projectURL: projectURL,
            publishableKey: publishableKey,
            deviceToken: nil
        )
    }
}

enum RuntimeConfigurationError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case keychainStatus(OSStatus)
    case missingBootstrapConfiguration
    case missingPairedSession

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "Could not encode runtime configuration."
        case .decodingFailed:
            "Could not decode runtime configuration."
        case .keychainStatus(let status):
            "Keychain operation failed with status \(status)."
        case .missingBootstrapConfiguration:
            "Supabase bootstrap URL/key are not configured."
        case .missingPairedSession:
            "No paired device session is stored."
        }
    }
}

protocol RuntimeConfigurationStoring: Sendable {
    func loadPairedSession() throws -> PairedDeviceSession?
    func savePairedSession(_ session: PairedDeviceSession) throws
    func clearPairedSession() throws
}

struct RuntimeConfigurationStore: RuntimeConfigurationStoring {
    private let keychain: KeychainStoring

    init(keychain: KeychainStoring = KeychainStore()) {
        self.keychain = keychain
    }

    func loadPairedSession() throws -> PairedDeviceSession? {
        guard let data = try keychain.data(for: RuntimeKeychainKey.pairedDeviceSession) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(PairedDeviceSession.self, from: data)
        } catch {
            throw RuntimeConfigurationError.decodingFailed
        }
    }

    func savePairedSession(_ session: PairedDeviceSession) throws {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(session)
            try keychain.save(data, for: RuntimeKeychainKey.pairedDeviceSession)
        } catch let error as RuntimeConfigurationError {
            throw error
        } catch {
            throw RuntimeConfigurationError.encodingFailed
        }
    }

    func clearPairedSession() throws {
        try keychain.deleteData(for: RuntimeKeychainKey.pairedDeviceSession)
    }
}

enum RuntimeKeychainKey {
    static let pairedDeviceSession = "paired-device-session"
}

protocol KeychainStoring: Sendable {
    func data(for account: String) throws -> Data?
    func save(_ data: Data, for account: String) throws
    func deleteData(for account: String) throws
}

struct KeychainStore: KeychainStoring {
    private let service: String

    init(service: String = "com.creatorcontenthelper.runtime") {
        self.service = service
    }

    func data(for account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw RuntimeConfigurationError.keychainStatus(status)
        }
    }

    func save(_ data: Data, for account: String) throws {
        var query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            attributes.forEach { query[$0.key] = $0.value }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw RuntimeConfigurationError.keychainStatus(addStatus)
            }
        default:
            throw RuntimeConfigurationError.keychainStatus(updateStatus)
        }
    }

    func deleteData(for account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw RuntimeConfigurationError.keychainStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
