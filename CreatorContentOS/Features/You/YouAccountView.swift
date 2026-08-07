import SwiftUI

struct YouAccountView: View {
    let backLabel: String
    let onBack: () -> Void

    var body: some View {
        YouDestinationScaffold(
            title: "Account",
            subtitle: "Signed-in identity, runtime health, and sign-out.",
            backLabel: backLabel,
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
                YouAccountIdentityBlock()
                YouAccountRuntimeStatusBlock()
#if DEBUG
                YouAccountDebugOnboardingResetBlock()
#endif
                YouAccountSignOutButton()
            }
        }
        .accessibilityIdentifier("you.screen.account")
    }
}

struct YouAccountIdentityBlock: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        PocketSheetBlock(header: "Identity") {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                HStack {
                    Text(liveSession == nil ? "Account" : "Signed in with Apple")
                        .font(PocketSheetType.sectionLabel)
                        .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
                    Spacer()
                    PocketSheetChip(
                        text: liveSession?.memberRole.capitalized ?? "Sample",
                        isEmphasized: liveSession != nil
                    )
                }
                .padding(.horizontal, PocketSheetSpace.m)
                .padding(.top, PocketSheetSpace.s)

                if let liveSession {
                    Text(appleIdentityLabel(for: liveSession))
                        .font(PocketSheetType.rowTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .padding(.horizontal, PocketSheetSpace.m)
                        .padding(.bottom, PocketSheetSpace.s)
                        .accessibilityIdentifier("you.account.identity")
                } else {
                    Text("Using sample data")
                        .font(PocketSheetType.rowTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .padding(.horizontal, PocketSheetSpace.m)
                        .padding(.bottom, PocketSheetSpace.s)
                }
            }
        }
    }

    private func appleIdentityLabel(for session: PairedDeviceSession) -> String {
        if let email = session.authenticatedEmail?.nilIfBlank {
            return email
        }
        if let name = session.creatorDisplayName?.nilIfBlank {
            return name
        }
        return "Apple ID"
    }

    private var liveSession: PairedDeviceSession? {
        if case .live(let session) = appState.runtime.mode {
            session
        } else {
            nil
        }
    }
}

struct YouAccountRuntimeStatusBlock: View {
    @Environment(AppState.self) private var appState
    @Environment(AppServices.self) private var services

    var body: some View {
        PocketSheetBlock(header: "Status") {
            VStack(spacing: 0) {
                statusRow(
                    title: "Supabase",
                    value: services.supabaseHealthStatus.chipLabel,
                    kind: healthStatusKind(services.supabaseHealthStatus)
                )
                PocketSheetDivider()
                statusRow(
                    title: "Gemini",
                    value: geminiChipLabel(services.geminiHealthStatus),
                    kind: healthStatusKind(services.geminiHealthStatus)
                )

                HStack(alignment: .center, spacing: PocketSheetSpace.s) {
                    Text(lastCheckedText)
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        .lineLimit(2)
                    Spacer(minLength: PocketSheetSpace.s)
                    refreshButton
                }
                .padding(.horizontal, PocketSheetSpace.m)
                .padding(.vertical, PocketSheetSpace.s)

                if let message = refreshFeedbackMessage {
                    Text(message)
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(refreshFeedbackColor)
                        .padding(.horizontal, PocketSheetSpace.m)
                        .padding(.bottom, PocketSheetSpace.s)
                }
            }
        }
    }

    private func statusRow(title: String, value: String, kind: PocketSheetStatusKind) -> some View {
        HStack {
            Text(title)
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.ink)
            Spacer(minLength: PocketSheetSpace.s)
            PocketSheetStatus(text: value, kind: kind)
        }
        .padding(.horizontal, PocketSheetSpace.m)
        .padding(.vertical, PocketSheetSpace.s)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }

    private func healthStatusKind(_ status: RuntimeHealthStatus) -> PocketSheetStatusKind {
        switch status {
        case .unknown, .checking:
            .pending
        case .sample:
            .neutral
        case .live:
            .ready
        case .down:
            .issue
        }
    }

    private func geminiChipLabel(_ status: RuntimeHealthStatus) -> String {
        switch status {
        case .sample: "Offline"
        case .live: "Live"
        case .checking: "Checking"
        case .down: "Down"
        case .unknown: "—"
        }
    }

    private var refreshButton: some View {
        Button {
            services.refreshFromRepositories()
        } label: {
            ZStack {
                if services.isRefreshingRepository || services.isCheckingRuntimeHealth {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(width: 44, height: 44)
            .foregroundStyle(PocketSheetTheme.Color.ink)
            .background(PocketSheetTheme.Color.paperRaised, in: Circle())
            .overlay {
                Circle().stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
            }
            .opacity((services.isRefreshingRepository || services.isCheckingRuntimeHealth) ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(services.isRefreshingRepository || services.isCheckingRuntimeHealth)
    }

    private var refreshFeedbackMessage: String? {
        if services.isRefreshingRepository || services.isCheckingRuntimeHealth {
            return "Refreshing…"
        }
        if let healthError = services.lastRuntimeHealthError?.nilIfBlank {
            return "Health check failed: \(healthError)"
        }
        if let error = services.lastRepositoryRefreshError?.nilIfBlank {
            return "Refresh failed: \(error)"
        }
        if let succeeded = services.lastRepositoryRefreshSucceededAt
            ?? services.lastRuntimeHealthCheckedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "Up to date as of \(formatter.string(from: succeeded))."
        }
        return nil
    }

    private var refreshFeedbackColor: Color {
        if services.isRefreshingRepository || services.isCheckingRuntimeHealth {
            return PocketSheetTheme.Color.inkMuted
        }
        if services.lastRuntimeHealthError != nil || services.lastRepositoryRefreshError != nil {
            return PocketSheetTheme.Color.ink
        }
        return PocketSheetTheme.Color.inkMuted
    }

    private var lastCheckedText: String {
        if let lastCheckedAt = appState.runtime.services.lastRepositoryRefreshAt
            ?? appState.runtime.services.lastRepositoryRefreshAttemptAt {
            return "Last checked at \(lastCheckedAt.formatted(date: .omitted, time: .shortened))"
        }
        return "Checking for updates..."
    }
}

#if DEBUG
struct YouAccountDebugOnboardingResetBlock: View {
    @State private var didReset = false

    var body: some View {
        PocketSheetBlock(header: "Debug") {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                Text("Clears onboarding progress and completion flags for QA reruns.")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .padding(.horizontal, PocketSheetSpace.m)
                    .padding(.top, PocketSheetSpace.s)

                PocketSheetSecondaryAction(title: didReset ? "Onboarding reset" : "Reset onboarding") {
                    UserDefaultsOnboardingStore().resetAll()
                    didReset = true
                }
                .accessibilityIdentifier("you.account.debug.resetOnboarding")
                .padding(.horizontal, PocketSheetSpace.m)
                .padding(.bottom, PocketSheetSpace.s)
            }
        }
    }
}
#endif

struct YouAccountSignOutButton: View {
    @Environment(AppState.self) private var appState
    @State private var isSigningOut = false

    var body: some View {
        PocketSheetSecondaryAction(title: isSigningOut ? "Signing out" : "Sign out") {
            signOut()
        }
        .disabled(isSigningOut || liveSession == nil)
        .opacity((isSigningOut || liveSession == nil) ? 0.54 : 1)
        .accessibilityIdentifier("you.account.signOut")
    }

    private var liveSession: PairedDeviceSession? {
        if case .live(let session) = appState.runtime.mode {
            session
        } else {
            nil
        }
    }

    @MainActor
    private func signOut() {
        guard !isSigningOut else { return }
        isSigningOut = true
        Task { @MainActor in
            await appState.signOut()
            isSigningOut = false
        }
    }
}
