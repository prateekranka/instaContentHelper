import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var activeMode: AppMode
    var runtime: AppRuntime
    var authenticationPhase: AuthenticationPhase
    var pendingEmail: String?
    var authenticationError: String?

    private let authenticationService: any AuthenticationServicing
    private let liveRuntimeBuilder: @MainActor (PairedDeviceSession) -> AppRuntime

    init(
        activeMode: AppMode = .mamta,
        runtime: AppRuntime? = nil,
        authenticationPhase: AuthenticationPhase? = nil,
        authenticationService: any AuthenticationServicing = SupabaseAuthenticationService(),
        liveRuntimeBuilder: @escaping @MainActor (PairedDeviceSession) -> AppRuntime = {
            AppRuntime.live(session: $0)
        }
    ) {
        self.activeMode = activeMode
        self.runtime = runtime ?? AppRuntime.makeAuthenticationShellRuntime()
        self.authenticationService = authenticationService
        self.liveRuntimeBuilder = liveRuntimeBuilder
        if let authenticationPhase {
            self.authenticationPhase = authenticationPhase
        } else if runtime != nil {
            self.authenticationPhase = .live
        } else {
            self.authenticationPhase = .restoring
        }
    }

    func replaceRuntime(_ runtime: AppRuntime) {
        self.runtime = runtime
    }

    func restoreAuthentication() async {
        guard authenticationPhase == .restoring else { return }

        if case .live = runtime.mode {
            await activate(runtime: runtime)
            return
        }

        do {
            guard let session = try await authenticationService.restoreSession() else {
                authenticationPhase = .signedOut
                return
            }
            await activate(session: session)
        } catch {
            authenticationError = error.localizedDescription
            authenticationPhase = .failed
        }
    }

    func requestEmailOTP(_ email: String) async {
        guard authenticationPhase != .requestingCode,
              authenticationPhase != .verifyingCode
        else { return }

        authenticationPhase = .requestingCode
        authenticationError = nil
        do {
            try await authenticationService.requestEmailOTP(email: email)
            pendingEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            authenticationPhase = .signedOut
        } catch {
            authenticationError = error.localizedDescription
            authenticationPhase = .failed
        }
    }

    func verifyEmailOTP(_ token: String) async {
        guard let pendingEmail else {
            authenticationError = "Request a new code first."
            authenticationPhase = .failed
            return
        }

        authenticationPhase = .verifyingCode
        authenticationError = nil
        do {
            let session = try await authenticationService.verifyEmailOTP(
                email: pendingEmail,
                token: token
            )
            await activate(session: session)
        } catch {
            authenticationError = error.localizedDescription
            authenticationPhase = .failed
        }
    }

    func resetSignIn() {
        pendingEmail = nil
        authenticationError = nil
        authenticationPhase = .signedOut
    }

    func signOut() async {
        let session = runtime.mode.liveSession
        authenticationError = nil
        do {
            try await authenticationService.signOut(deviceSession: session)
        } catch {
            authenticationError = error.localizedDescription
        }
        finishLocalSignOut()
    }

    func observeAuthenticationChanges() async {
        for await event in authenticationService.authenticationEvents() {
            switch event {
            case .signedOut, .userDeleted:
                finishLocalSignOut()
            }
        }
    }

    private func activate(session: PairedDeviceSession) async {
        await activate(runtime: liveRuntimeBuilder(session))
    }

    private func activate(runtime: AppRuntime) async {
        await runtime.services.refreshFromRepositoriesImmediately()
        guard runtime.services.lastRepositoryError == nil else {
            authenticationError = runtime.services.lastRepositoryError
            authenticationPhase = .failed
            return
        }

        self.runtime = runtime
        activeMode = .mamta
        pendingEmail = nil
        authenticationError = nil
        authenticationPhase = .live
        await runtime.services.scheduleTodayNotificationIfNeededImmediately()
    }

    private func finishLocalSignOut() {
        activeMode = .mamta
        pendingEmail = nil
        runtime = .fixtures()
        authenticationPhase = .signedOut
    }
}

enum AuthenticationPhase: Hashable, Sendable {
    case restoring
    case signedOut
    case requestingCode
    case verifyingCode
    case live
    case failed
}

private extension AppRuntimeMode {
    var liveSession: PairedDeviceSession? {
        guard case .live(let session) = self else { return nil }
        return session
    }
}

enum AppMode: String, CaseIterable, Codable, Hashable {
    case mamta
    case admin
}
