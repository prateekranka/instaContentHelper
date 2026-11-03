import SwiftUI

/// "How you're doing" — account-level Instagram insights, in Mira's design language.
/// Reuses the shared `InstagramInsightsState` model + OAuth config; renders with
/// MiraPage/MiraTheme. Fixture builds honor `MCO_INSIGHTS_SCENARIO`.
struct MiraInsightsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.webAuthenticationSession) private var webAuth

    @State private var state: InstagramInsightsState = .notConnected
    @State private var isLoading = false
    @State private var isConnecting = false
    @State private var message: String?

    var body: some View {
        MiraPage {
            MiraSectionTitle(text: "How you're doing")
            switch state {
            case .notConnected:
                notConnected
            case .connectedPersonal:
                info("Insights need a Professional account", "Switch your Instagram to a Creator or Business account to see your numbers here.")
            case .permissionNeeded:
                info("Permission needed", "Allow insights access when connecting Instagram to see your numbers.")
            case .noData:
                info("Not available yet", "No insights yet. Check back after your next post goes live.")
            case .ready(let report):
                ready(report)
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(MiraTheme.ink.opacity(0.7))
            }
        }
        .navigationTitle("How you're doing")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: States

    private var notConnected: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("See your followers, reach and saves — and what's working — without leaving Mira.")
            Button(isConnecting ? "Connecting…" : "Connect Instagram") {
                Task { await connect() }
            }
            .buttonStyle(MiraPrimaryStyle())
            .disabled(isConnecting)
            Text("We only read your insights. Mira never posts for you, and your password stays with Instagram.")
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
                    .background(MiraTheme.olive.opacity(0.18), in: Capsule())
            }
            ForEach(report.headline) { metric in
                tile(metric)
            }
            if let nudge = report.nudge?.nilIfBlank {
                Text(nudge)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MiraTheme.olive.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
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
                Text(delta).font(.footnote).foregroundStyle(MiraTheme.olive)
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

    private func load() async {
#if DEBUG
        if DebugLaunchFlags.forceFixtureUI {
            state = InstagramInsightsFixture.state(for: DebugLaunchFlags.insightsScenario)
            return
        }
#endif
        guard let session = liveSession else { state = .notConnected; return }
        isLoading = true
        defer { isLoading = false }
        do {
            state = try await MiraSupabaseInsightsService(session: session).fetchInsights()
            message = nil
        } catch {
            message = (error as? MiraError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func connect() async {
        message = nil
        guard InstagramOAuth.isConfigured, let url = InstagramOAuth.authorizeURL() else {
            message = "Instagram connection isn't configured in this build yet."
            return
        }
        guard let session = liveSession else {
            message = "Connect your account from Profile first."
            return
        }
        isConnecting = true
        defer { isConnecting = false }
        do {
            let callback = try await webAuth.authenticate(
                using: url, callbackURLScheme: InstagramOAuth.callbackScheme
            )
            guard let code = InstagramOAuth.authorizationCode(from: callback) else {
                message = "Couldn't read the Instagram response. Try again."
                return
            }
            try await MiraSupabaseInsightsService(session: session)
                .connect(code: code, redirectURI: InstagramOAuth.redirectURI ?? "")
            await load()
        } catch {
            // User dismissed the sheet or cancelled; leave the CTA in place.
        }
    }
}
