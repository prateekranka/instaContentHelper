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
        activeMode: AppMode = .creator,
        runtime: AppRuntime? = nil,
        authenticationPhase: AuthenticationPhase? = nil,
        authenticationService: any AuthenticationServicing = SupabaseAuthenticationService(),
        liveRuntimeBuilder: @escaping @MainActor (PairedDeviceSession) -> AppRuntime = {
            AppRuntime.live(session: $0)
        }
    ) {
        let initialRuntime = runtime ?? AppRuntime.makeAuthenticationShellRuntime()
        self.activeMode = activeMode
        self.runtime = initialRuntime
        self.authenticationService = authenticationService
        self.liveRuntimeBuilder = liveRuntimeBuilder
        if let authenticationPhase {
            self.authenticationPhase = authenticationPhase
        } else if runtime != nil {
            self.authenticationPhase = .live
        } else if case .live = initialRuntime.mode {
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
        debugAuthLog("restore:start")

        if case .live = runtime.mode {
            await activate(runtime: runtime)
            debugAuthLog("restore:already-live")
            return
        }

        do {
            guard let session = try await authenticationService.restoreSession() else {
                authenticationPhase = .signedOut
                debugAuthLog("restore:signed-out")
                return
            }
            await activate(session: session)
            debugAuthLog("restore:activated")
        } catch {
            authenticationError = error.localizedDescription
            authenticationPhase = .failed
            debugAuthLog("restore:failed \(error.localizedDescription)")
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
            debugAuthLog("otp:verify:start")
            let session = try await authenticationService.verifyEmailOTP(
                email: pendingEmail,
                token: token
            )
            debugAuthLog("otp:verify:session-ready")
            await activate(session: session)
            debugAuthLog("otp:verify:activated")
        } catch {
            authenticationError = error.localizedDescription
            authenticationPhase = .failed
            debugAuthLog("otp:verify:failed \(error.localizedDescription)")
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
        debugAuthLog("activate:set-live")
        self.runtime = runtime
        activeMode = .creator
        pendingEmail = nil
        authenticationError = nil
        authenticationPhase = .live

        Task { @MainActor in
            debugAuthLog("activate:refresh:start")
            await runtime.services.refreshFromRepositoriesImmediately()
            debugAuthLog("activate:refresh:done")
        }
    }

    private func finishLocalSignOut() {
        activeMode = .creator
        pendingEmail = nil
        runtime = .fixtures()
        authenticationPhase = .signedOut
    }

    private func debugAuthLog(_ message: String) {
        #if DEBUG
        print("[ContentHelperAuth] \(Date()) \(message)")
        #endif
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
    case creator
    case admin
}
