import Foundation
import Supabase

protocol AuthenticationServicing: Sendable {
    func requestEmailOTP(email: String) async throws
    func verifyEmailOTP(email: String, token: String) async throws -> PairedDeviceSession
    func restoreSession() async throws -> PairedDeviceSession?
    func signOut(deviceSession: PairedDeviceSession?) async throws
    func authenticationEvents() -> AsyncStream<AuthenticationSessionEvent>
}

enum AuthenticationServiceError: LocalizedError, Equatable {
    case invalidEmail
    case invalidOTP
    case missingBootstrapConfiguration
    case missingAuthSession
    case backend(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            "Enter a valid approved email address."
        case .invalidOTP:
            "Enter the six-digit code from your email."
        case .missingBootstrapConfiguration:
            "Live Supabase is not configured for this build."
        case .missingAuthSession:
            "Your sign-in session expired. Request a new code."
        case .backend(let code):
            Self.message(for: code)
        }
    }

    private static func message(for code: String) -> String {
        switch code {
        case "tester_not_approved":
            "This email has not been approved for testing."
        case "member_revoked":
            "Access for this tester has been revoked."
        case "workspace_unavailable", "creator_unavailable":
            "Your tester account is not connected to the Mamta workspace."
        case "invalid_auth_session":
            "Your sign-in session expired. Request a new code."
        case "device_session_failed":
            "Signed in, but device access could not be created. Try again."
        case "session_revoke_failed":
            "The server could not revoke this device session."
        default:
            "Authentication failed. Try again."
        }
    }
}

final class SupabaseAuthenticationService: AuthenticationServicing, @unchecked Sendable {
    private let bootstrapConfiguration: SupabaseBootstrapConfiguration?
    private let runtimeStore: RuntimeConfigurationStoring
    private let client: SupabaseClient?
    private let deviceNameProvider: @Sendable () -> String

    init(
        bootstrapConfiguration: SupabaseBootstrapConfiguration? = .fromInfoDictionary(),
        runtimeStore: RuntimeConfigurationStoring = RuntimeConfigurationStore(),
        deviceNameProvider: @escaping @Sendable () -> String = { "iPhone" }
    ) {
        self.bootstrapConfiguration = bootstrapConfiguration
        self.runtimeStore = runtimeStore
        self.deviceNameProvider = deviceNameProvider
        client = bootstrapConfiguration.map {
            SupabaseClientFactory().makeBootstrapClient(configuration: $0)
        }
    }

    func requestEmailOTP(email: String) async throws {
        let email = try normalizedEmail(email)
        let client = try configuredClient()
        try await client.auth.signInWithOTP(email: email, shouldCreateUser: false)
    }

    func verifyEmailOTP(email: String, token: String) async throws -> PairedDeviceSession {
        let email = try normalizedEmail(email)
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count == 6, token.allSatisfy(\.isNumber) else {
            throw AuthenticationServiceError.invalidOTP
        }

        let client = try configuredClient()
        let response = try await client.auth.verifyOTP(
            email: email,
            token: token,
            type: .email
        )
        guard response.session != nil else {
            throw AuthenticationServiceError.missingAuthSession
        }
        return try await exchangeAuthenticatedSession(email: response.user.email ?? email)
    }

    func restoreSession() async throws -> PairedDeviceSession? {
        let client = try configuredClient()
        guard client.auth.currentSession != nil else {
            return nil
        }

        let authSession: Session
        do {
            authSession = try await client.auth.session
        } catch {
            try? runtimeStore.clearPairedSession()
            try? await client.auth.signOut(scope: .local)
            return nil
        }

        if let storedSession = try runtimeStore.loadPairedSession() {
            return storedSession.withAuthenticatedEmail(authSession.user.email)
        }
        return try await exchangeAuthenticatedSession(email: authSession.user.email)
    }

    func signOut(deviceSession: PairedDeviceSession?) async throws {
        let client: SupabaseClient
        do {
            client = try configuredClient()
        } catch {
            try? runtimeStore.clearPairedSession()
            throw error
        }
        var revokeError: Error?

        if let deviceSession, client.auth.currentSession != nil {
            do {
                try await client.functions.invoke(
                    "revoke-device-session",
                    options: FunctionInvokeOptions(
                        headers: ["x-mco-device-token": deviceSession.deviceToken],
                        body: RevokeDeviceSessionRequest(
                            deviceInstallationID: deviceSession.deviceInstallationID
                        )
                    )
                )
            } catch {
                revokeError = mappedFunctionError(error)
            }
        }

        try? runtimeStore.clearPairedSession()
        try await client.auth.signOut(scope: .local)

        if let revokeError {
            throw revokeError
        }
    }

    func authenticationEvents() -> AsyncStream<AuthenticationSessionEvent> {
        guard let client else {
            return AsyncStream { $0.finish() }
        }

        return AsyncStream { continuation in
            let task = Task {
                for await change in client.auth.authStateChanges {
                    switch change.event {
                    case .signedOut:
                        continuation.yield(.signedOut)
                    case .userDeleted:
                        continuation.yield(.userDeleted)
                    default:
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func exchangeAuthenticatedSession(email: String?) async throws -> PairedDeviceSession {
        guard let bootstrapConfiguration else {
            throw AuthenticationServiceError.missingBootstrapConfiguration
        }
        let client = try configuredClient()
        let existingInstallationID = try? runtimeStore.loadPairedSession()?.deviceInstallationID
        let response: AuthenticationSessionExchangeResponse

        do {
            response = try await client.functions.invoke(
                "exchange-auth-session",
                options: FunctionInvokeOptions(
                    body: AuthenticationSessionExchangeRequest(
                        deviceName: deviceNameProvider(),
                        platform: "ios",
                        deviceInstallationID: existingInstallationID ?? UUID()
                    )
                )
            )
        } catch {
            throw mappedFunctionError(error)
        }

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
            pairedAt: response.pairedAt.flatMap(SupabaseTimestampParser.date(from:)) ?? Date(),
            authenticatedEmail: response.memberEmail ?? email
        )
        try runtimeStore.savePairedSession(session)
        return session
    }

    private func configuredClient() throws -> SupabaseClient {
        guard bootstrapConfiguration != nil, let client else {
            throw AuthenticationServiceError.missingBootstrapConfiguration
        }
        return client
    }

    private func normalizedEmail(_ rawValue: String) throws -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.contains("@"), value.contains("."), !value.contains(" ") else {
            throw AuthenticationServiceError.invalidEmail
        }
        return value
    }

    private func mappedFunctionError(_ error: Error) -> Error {
        guard case FunctionsError.httpError(_, let data) = error,
              let response = try? JSONDecoder().decode(AuthenticationFunctionErrorResponse.self, from: data),
              let code = response.stableCode
        else {
            return error
        }
        return AuthenticationServiceError.backend(code)
    }
}
