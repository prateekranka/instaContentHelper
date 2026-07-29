import Foundation
import Supabase
#if canImport(UIKit)
import UIKit
#endif

protocol AuthenticationServicing: Sendable {
    func signInWithApple(idToken: String, fullName: String?) async throws -> PairedDeviceSession
    func restoreSession() async throws -> PairedDeviceSession?
    func signOut(deviceSession: PairedDeviceSession?) async throws
    func authenticationEvents() -> AsyncStream<AuthenticationSessionEvent>
}

enum AuthenticationServiceError: LocalizedError, Equatable {
    case invalidAppleIdentityToken
    case missingBootstrapConfiguration
    case missingAuthSession
    case backend(String)

    var errorDescription: String? {
        switch self {
        case .invalidAppleIdentityToken:
            "Apple sign-in did not return a usable identity token."
        case .missingBootstrapConfiguration:
            "Live Supabase is not configured for this build."
        case .missingAuthSession:
            "Your sign-in session expired. Sign in with Apple again."
        case .backend(let code):
            Self.message(for: code)
        }
    }

    private static func message(for code: String) -> String {
        switch code {
        case "tester_not_approved":
            "This Apple account is not connected to ContentHelper yet."
        case "member_revoked":
            "Access for this account has been revoked."
        case "workspace_unavailable", "creator_unavailable":
            "Your account is not connected to a Creator workspace."
        case "invalid_auth_session":
            "Your sign-in session expired. Sign in with Apple again."
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
        deviceNameProvider: @escaping @Sendable () -> String = CurrentDeviceNameProvider.deviceName
    ) {
        self.bootstrapConfiguration = bootstrapConfiguration
        self.runtimeStore = runtimeStore
        self.deviceNameProvider = deviceNameProvider
        client = bootstrapConfiguration.map {
            SupabaseClientFactory().makeBootstrapClient(configuration: $0)
        }
    }

    func signInWithApple(idToken: String, fullName: String?) async throws -> PairedDeviceSession {
        let idToken = idToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idToken.isEmpty else {
            throw AuthenticationServiceError.invalidAppleIdentityToken
        }

        let client = try configuredClient()
        debugAuthLog("supabase:sign-in-apple:start")
        let session = try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: idToken
            )
        )
        debugAuthLog("supabase:sign-in-apple:done")

        if let fullName, !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = try? await client.auth.update(
                user: UserAttributes(data: ["full_name": .string(fullName)])
            )
        }

        return try await exchangeAuthenticatedSession(email: session.user.email)
    }

    func restoreSession() async throws -> PairedDeviceSession? {
        let client = try configuredClient()
        guard client.auth.currentSession != nil else {
            return nil
        }

        let authSession: Session
        do {
            debugAuthLog("supabase:restore-session:start")
            authSession = try await client.auth.session
            debugAuthLog("supabase:restore-session:done")
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
            debugAuthLog("edge:exchange-auth-session:start")
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
            debugAuthLog("edge:exchange-auth-session:done")
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
        debugAuthLog("keychain:paired-session:saved")
        return session
    }

    private func configuredClient() throws -> SupabaseClient {
        guard bootstrapConfiguration != nil, let client else {
            throw AuthenticationServiceError.missingBootstrapConfiguration
        }
        return client
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

private func debugAuthLog(_ message: String) {
    #if DEBUG
    print("[ContentHelperAuth] \(Date()) \(message)")
    #endif
}

enum CurrentDeviceNameProvider {
    static func deviceName() -> String {
        #if canImport(UIKit)
        if let simulatorName = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] {
            return displayName(from: simulatorName)
        }

        if Thread.isMainThread {
            return displayName(from: MainActor.assumeIsolated { UIDevice.current.name })
        }

        return displayName(from: nil)
        #else
        displayName(from: nil)
        #endif
    }

    static func displayName(from rawValue: String?, fallback: String = "iPhone") -> String {
        rawValue?.nilIfBlank ?? fallback
    }
}
