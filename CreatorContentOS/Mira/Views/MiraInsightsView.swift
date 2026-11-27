import AuthenticationServices
import SwiftUI

/// "How you're doing" — account-level Instagram insights, in Mira's design language.
/// Reuses the shared `InstagramInsightsState` model + OAuth config; renders with
/// MiraPage/MiraTheme. Fixture builds honor `MCO_INSIGHTS_SCENARIO`.
struct MiraInsightsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.webAuthenticationSession) private var webAuth

    @State private var state = MiraInsightsState.unopened

    var body: some View {
        MiraPage {
            MiraSectionTitle(text: "How you're doing")
            switch state {
            case .unopened, .loading:
                ProgressView("Checking your Instagram insights")
            case .connecting:
                ProgressView("Connecting to Instagram")
            case .loaded(let result):
                content(result)
            case .loadFailed(let message, let previous):
                if let previous, previous != .notConnected { content(previous) }
                Text(message).font(.footnote).foregroundStyle(MiraTheme.ink.opacity(0.7))
                Button(state.nextAction.title) { Task { await load() } }
            case .connectionFailed(let message):
                notConnected
                Text(message).font(.footnote).foregroundStyle(MiraTheme.ink.opacity(0.7))
            }
        }
        .navigationTitle("How you're doing")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder private func content(_ result: InstagramInsightsState) -> some View {
        switch result {
        case .notConnected:
            notConnected
        case .connectedPersonal:
            info("Insights need a Professional account", "Switch your Instagram to a Creator or Business account to see your numbers here.")
        case .permissionNeeded:
            info("Permission needed", "Let Mira read your numbers when you connect Instagram.")
        case .noData:
            info("Not available yet", "No insights yet. Check back after your next post goes live.")
        case .ready(let report):
            ready(report)
        }
    }

    private var notConnected: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("See your followers, reach and saves — and what's working — without leaving Mira.")
            Button(state.nextAction.title) {
                Task { await connect() }
            }
            .buttonStyle(MiraPrimaryStyle())
            Text("Log in with Instagram and choose your account. Mira only reads your posts and insights. It never posts for you.")
                .font(.footnote).foregroundStyle(MiraTheme.ink.opacity(0.7))
        }
    }

    private func info(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(detail).foregroundStyle(MiraTheme.ink.opacity(0.7))
        }
    }

    private func ready(_ report: InstagramInsightsReport) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if report.source != .api {
                Text(report.source == .sample ? "Sample data" : "Manually entered")
                    .font(.caption).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(MiraTheme.accent.opacity(0.18), in: Capsule())
            }
            ForEach(report.headline) { metric in
                tile(metric)
            }
            if let nudge = report.nudge?.nilIfBlank {
                Text(nudge)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MiraTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            if !report.detail.isEmpty {
                Divider()
                MiraSectionTitle(text: "More detail")
                ForEach(report.detail) { metric in
                    HStack {
                        Text(metric.label)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(metric.value).fontWeight(.semibold)
                            if let delta = metric.delta {
                                Text(delta).font(.footnote).foregroundStyle(MiraTheme.ink.opacity(0.7))
                            }
                        }
                    }
                }
            }
            Text(footer(report)).font(.footnote).foregroundStyle(MiraTheme.ink.opacity(0.6))
        }
    }

    private func tile(_ metric: InstagramInsightMetric) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.label).font(.subheadline).foregroundStyle(MiraTheme.ink.opacity(0.7))
            Text(metric.value).font(.largeTitle.weight(.semibold))
            if let delta = metric.delta {
                Text(delta).font(.footnote).foregroundStyle(MiraTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(MiraTheme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func footer(_ report: InstagramInsightsReport) -> String {
        let handle = report.username.map { "@\($0)" } ?? "Instagram"
        return "\(handle) · updated \(SupabaseDateFormatting.timeOfDay(from: report.fetchedAt))"
    }

    // MARK: Data

    private var liveSession: PairedDeviceSession? {
        if case .live(let session) = appState.runtime.mode { session } else { nil }
    }

    @discardableResult
    private func transition(_ event: MiraInsightsEvent) -> Bool {
        guard let next = state.handle(event) else { return false }
        state = next
        return true
    }

    private func load() async {
        let attempt = UUID()
        guard transition(.load(attempt)) else { return }
#if DEBUG
        if DebugLaunchFlags.forceFixtureUI {
            transition(.loaded(attempt, InstagramInsightsFixture.state(for: DebugLaunchFlags.insightsScenario)))
            return
        }
#endif
        guard let session = liveSession else {
            transition(.loaded(attempt, .notConnected))
            return
        }
        await fetch(session, attempt: attempt)
    }

    private func fetch(_ session: PairedDeviceSession, attempt: UUID) async {
        do {
            let result = try await MiraSupabaseInsightsService(session: session).fetchInsights()
            try Task.checkCancellation()
            transition(.loaded(attempt, result))
        } catch {
            if Task.isCancelled {
                transition(.cancelled(attempt))
            } else {
                transition(.failed(attempt, error.localizedDescription))
            }
        }
    }

    private func connect() async {
        let attempt = UUID()
        guard transition(.connect(attempt)) else { return }
        let oauthState = attempt.uuidString
        guard InstagramOAuth.isConfigured, let url = InstagramOAuth.authorizeURL(state: oauthState) else {
            transition(.failed(attempt, "Instagram connection isn't configured in this build yet."))
            return
        }
        guard let session = liveSession else {
            transition(.failed(attempt, "Connect your account from Profile first."))
            return
        }
        do {
            let callback = try await webAuth.authenticate(
                using: url, callbackURLScheme: InstagramOAuth.callbackScheme
            )
            guard InstagramOAuth.state(from: callback) == oauthState,
                  let code = InstagramOAuth.authorizationCode(from: callback) else {
                transition(.failed(attempt, "Couldn't read the Instagram response. Try again."))
                return
            }
            try await MiraSupabaseInsightsService(session: session)
                .connect(code: code, redirectURI: InstagramOAuth.redirectURI ?? "")
            guard transition(.connected(attempt)) else { return }
            await fetch(session, attempt: attempt)
        } catch let error as MiraError {
            transition(.failed(attempt, error.localizedDescription))
        } catch {
            transition(.cancelled(attempt))
        }
    }
}
