import SwiftUI
import BackgroundTasks

@main
@MainActor
struct CreatorContentOSApp: App {
    @State private var appState = AppState.makeLaunchState()

    init() {
        // Register before the app finishes launching so background benchmark
        // launches can continue the run loop.
        BenchmarkBackgroundTask.register()
    }

    var body: some Scene {
        WindowGroup {
            CreatorContentOSAppView()
                .environment(appState)
                .environment(appState.runtime.services)
                .task {
                    await appState.restoreAuthentication()
                }
                .task {
                    await appState.observeAuthenticationChanges()
                }
                .task(id: appState.runtime.mode) {
                    guard appState.authenticationPhase == .live else { return }
                    let services = appState.runtime.services
                    if services.loadTodayFromCache() {
                        await services.scheduleTodayNotificationIfNeededImmediately()
                    }
                    await services.refreshFromRepositoriesImmediately()
#if DEBUG
                    services.applyDebugWeekStartOverrideIfNeeded()
#endif
                }
        }
    }
}

struct CreatorContentOSAppView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services
    @State private var onboardingModel = OnboardingViewModel(
        store: UserDefaultsOnboardingStore(
            defaults: DebugLaunchConfiguration.onboardingDefaults
        )
    )

    var body: some View {
        Group {
#if DEBUG
            if appState.authenticationPhase == .live,
               let forcedScreen = DebugForcedScreen.current {
                forcedScreen.view
                    .tint(PocketSheetTheme.Color.ink)
            } else if shouldShowDebugAdminShell {
                // DEBUG-only: Admin/Manager TabView (Daily / Weekly / References).
                // Not reachable from the live Creator product path.
                AdminShellView()
            } else {
                appView
            }
#else
            appView
#endif
        }
        .aiConsentSheet()
        .task(id: workspaceOnboardingScope) {
            guard appState.authenticationPhase == .live else { return }
            let scopedStore = WorkspaceScopedOnboardingStore(
                workspaceID: services.context.workspaceID,
                creatorID: services.context.creatorID,
                defaults: DebugLaunchConfiguration.onboardingDefaults
            )
            onboardingModel = OnboardingViewModel(store: scopedStore)
        }
        .modifier(DebugLaunchEnvironmentModifier())
    }

    private var workspaceOnboardingScope: String {
        "\(services.context.workspaceID.uuidString)-\(services.context.creatorID.uuidString)"
    }

    private var shouldShowLiveOnboarding: Bool {
        guard appState.authenticationPhase == .live else { return false }
        if onboardingModel.shouldKeepOnboardingFlowVisible { return true }
        guard !onboardingModel.onboardingCompletedThisSession else { return false }
        return OnboardingPresentationPolicy.shouldPresent(
            presentation: services.creatorOnboardingPresentation,
            sessionDismissed: onboardingModel.sessionDismissed
        )
    }

    /// Live product always uses the Creator shell. `AppMode.admin` is ignored here.
    @ViewBuilder
    private var appView: some View {
        Group {
            switch appState.authenticationPhase {
            case .restoring:
                AuthenticationRestoringView()
            case .live:
                if shouldShowLiveOnboarding {
                    OnboardingFlowView(
                        model: onboardingModel,
                        onSoftSkip: {},
                        onHandoffComplete: handleOnboardingHandoff
                    )
                    .tint(PocketSheetTheme.Color.ink)
                    .pocketSheetChromePalette()
                } else {
                    CreatorShellView()
                        .tint(PocketSheetTheme.Color.ink)
                }
            case .signedOut, .signingIn, .failed:
                SignInView()
            }
        }
        // Pocket uses fixed paper surfaces. Keep system controls in the same
        // appearance so toolbar text does not turn white on these surfaces.
        .preferredColorScheme(.light)
    }

    private func handleOnboardingHandoff(
        _ result: OnboardingFirstIdeaHandoffResult,
        handoff: OnboardingFirstDayHandoff
    ) {
        onboardingModel.sessionDismissed = false
        switch result {
        case .completed, .skippedExistingReady:
            appState.handoffFirstDayFromOnboarding(handoff)
        case .persistFailed, .generationFailed:
            break
        }
    }

#if DEBUG
    /// Fixture-only Manager shell when `MCO_FORCE_FIXTURE_UI=1` and `MCO_FORCE_APP_MODE=admin`.
    /// Setting `activeMode = .creator` (Admin chrome “Creator mode”) exits back to CreatorShellView.
    private var shouldShowDebugAdminShell: Bool {
        DebugLaunchFlags.forceFixtureUI
            && DebugLaunchFlags.forceAppMode == "admin"
            && appState.activeMode == .admin
    }
#endif
}

private extension AppState {
    static func makeLaunchState(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> AppState {
#if DEBUG
        if DebugLaunchConfiguration.isEnabled(
            "MCO_RESET_ONBOARDING",
            environment: environment,
            arguments: arguments
        ) {
            WorkspaceScopedOnboardingStore.resetFixtureScopedKeys(
                defaults: DebugLaunchConfiguration.onboardingDefaults
            )
            UserDefaultsOnboardingStore.resetLegacyGlobalKeys(
                defaults: DebugLaunchConfiguration.onboardingDefaults
            )
        }

        if DebugLaunchConfiguration.isEnabled(
            "MCO_FORCE_SIGN_IN",
            environment: environment,
            arguments: arguments
        ) {
            return AppState(authenticationPhase: .signedOut)
        }

        if DebugLaunchConfiguration.isEnabled(
            "MCO_FORCE_FIXTURE_UI",
            environment: environment,
            arguments: arguments
        ) {
            // `.admin` only affects DEBUG AdminShellView routing above — never the Release live path.
            let mode: AppMode = DebugLaunchConfiguration.value(
                for: "MCO_FORCE_APP_MODE",
                environment: environment,
                arguments: arguments
            ) == "admin" ? .admin : .creator
            return AppState(
                activeMode: mode,
                runtime: .fixtures(),
                authenticationPhase: .live
            )
        }
#endif
        return AppState()
    }
}

#if DEBUG
/// Screens kept for fixture / QA launches only — not product navigation.
private enum DebugForcedScreen: String {
    case aiRunway = "ai-runway"
    case storyboardCard = "storyboard-card"
    case testerAccess = "tester-access"
    /// Alias for Admin shell without relying on `MCO_FORCE_APP_MODE`.
    case adminShell = "admin"

    static var current: DebugForcedScreen? {
        guard DebugLaunchFlags.forceFixtureUI,
              let rawValue = DebugLaunchFlags.forceScreen
        else {
            return nil
        }

        return DebugForcedScreen(rawValue: rawValue)
    }

    @ViewBuilder
    var view: some View {
        switch self {
        case .aiRunway:
            AIRunwayView()
        case .storyboardCard:
            DebugStoryboardCardScreen()
        case .testerAccess:
            TesterAccessView()
        case .adminShell:
            AdminShellView()
        }
    }
}

private struct DebugStoryboardCardScreen: View {
    var body: some View {
        NavigationStack {
            ZStack {
                PocketSheetTheme.Color.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
                        Text("Storyboard card preview")
                            .font(PocketSheetType.screenTitle)
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                        GeneratedDayPlannedContent(
                            card: DebugLaunchFlags.longContent
                                ? GeneratedDailyCardDraft.storyboardBreakdownFixture.withLongContent
                                : .storyboardBreakdownFixture
                        )
                    }
                    .padding(.horizontal, PocketSheetSpace.l)
                    .padding(.top, PocketSheetSpace.l)
                    .padding(.bottom, PocketSheetSpace.xl)
                }
            }
        }
        .pocketSheetChromePalette()
    }
}
#endif

#if DEBUG
private struct DebugLaunchEnvironmentModifier: ViewModifier {
    func body(content: Content) -> some View {
        if DebugLaunchFlags.forceNarrowFixtureContainer {
            configuredContent(content)
                .frame(width: 320)
                .frame(maxWidth: .infinity)
        } else {
            configuredContent(content)
        }
    }

    @ViewBuilder
    private func configuredContent(_ content: Content) -> some View {
        if DebugLaunchFlags.forceAccessibility5 {
            content.environment(\.dynamicTypeSize, .accessibility5)
        } else {
            content
        }
    }
}
#else
private struct DebugLaunchEnvironmentModifier: ViewModifier {
    func body(content: Content) -> some View { content }
}
#endif

private struct AuthenticationRestoringView: View {
    var body: some View {
        ZStack {
            PocketSheetTheme.Color.paper.ignoresSafeArea()
            ProgressView("Checking your session")
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                .tint(PocketSheetTheme.Color.ink)
        }
        .accessibilityIdentifier("authentication-restoring")
    }
}
