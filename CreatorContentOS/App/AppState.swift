import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var runtime: AppRuntime
    var authenticationPhase: AuthenticationPhase
    var authenticationError: String?

    private let authenticationService: any AuthenticationServicing
    private let liveRuntimeBuilder: @MainActor (PairedDeviceSession) -> AppRuntime

    init(
        runtime: AppRuntime? = nil,
        authenticationPhase: AuthenticationPhase? = nil,
        authenticationService: any AuthenticationServicing = SupabaseAuthenticationService(),
        liveRuntimeBuilder: @escaping @MainActor (PairedDeviceSession) -> AppRuntime = {
            AppRuntime.live(session: $0)
        }
    ) {
        let initialRuntime = runtime ?? AppRuntime.makeAuthenticationShellRuntime()
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

    static func makeLaunchState(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> AppState {
#if DEBUG
        if DebugLaunchConfiguration.isEnabled(
            "MCO_FORCE_FIXTURE_UI", environment: environment, arguments: arguments
        ) {
            return AppState(runtime: .fixtures(), authenticationPhase: .signedOut)
        }
#endif
        return AppState()
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

    func signInWithApple(idToken: String, fullName: String? = nil) async {
        guard authenticationPhase != .signingIn else { return }

        authenticationPhase = .signingIn
        authenticationError = nil
        do {
            debugAuthLog("apple:sign-in:start")
            let session = try await authenticationService.signInWithApple(
                idToken: idToken,
                fullName: fullName
            )
            debugAuthLog("apple:sign-in:session-ready")
            await activate(session: session)
            debugAuthLog("apple:sign-in:activated")
        } catch {
            authenticationError = error.localizedDescription
            authenticationPhase = .failed
            debugAuthLog("apple:sign-in:failed \(error.localizedDescription)")
        }
    }

    func failSignIn(message: String) async {
        authenticationError = message
        authenticationPhase = .failed
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
        authenticationError = nil
        authenticationPhase = .live
    }

    private func finishLocalSignOut() {
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
    case signingIn
    case live
    case failed
}

private extension AppRuntimeMode {
    var liveSession: PairedDeviceSession? {
        guard case .live(let session) = self else { return nil }
        return session
    }
}
