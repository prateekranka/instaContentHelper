import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var activeMode: AppMode
    var runtime: AppRuntime
    var authenticationPhase: AuthenticationPhase
    var authenticationError: String?
    /// Consumed by `CreatorShellView` to switch tabs (e.g. Available on Today → Today).
    var pendingCreatorTab: CreatorTab?
    /// Consumed by `PlanHubView` to preselect a calendar date (Edit / ⋯ / empty Today CTA).
    var planSelectedDate: String?

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

    func requestCreatorTab(_ tab: CreatorTab) {
        pendingCreatorTab = tab
    }

    /// Preselects a Plan calendar date (`yyyy-MM-dd`) before opening Plan.
    func preparePlan(selecting date: String?) {
        planSelectedDate = date?.nilIfBlank
    }

    /// Returns and clears a pending Plan date selection.
    func consumePlanSelectedDate() -> String? {
        let date = planSelectedDate
        planSelectedDate = nil
        return date
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
        activeMode = .creator
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

enum AppMode: String, CaseIterable, Codable, Hashable {
    case creator
    case admin
}
