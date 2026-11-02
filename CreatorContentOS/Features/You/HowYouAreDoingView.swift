import SwiftUI

/// "How you're doing" — account-level Instagram insights (Followers / Reach / Saves
/// with week-over-week deltas, one actionable nudge, and a richer in-app detail view).
///
/// This is the UI layer. It renders a resolved `InstagramInsightsState`. Wiring the
/// real connection + fetch (edge functions `instagram-connect` / `instagram-insights`)
/// is a separate increment; until then live builds show `.notConnected` and fixture
/// builds honor `MCO_INSIGHTS_SCENARIO`.
struct HowYouAreDoingView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.webAuthenticationSession) private var webAuthSession
    let backLabel: String
    let onBack: () -> Void

    @State private var connectError: String?

    var body: some View {
        YouDestinationScaffold(
            title: "How you're doing",
            subtitle: subtitle,
            backLabel: backLabel,
            onBack: onBack
        ) {
            content
        }
        .accessibilityIdentifier("you.screen.insights")
        .task { await loadIfLive() }
    }

    private var subtitle: String {
        switch state {
        case .ready: "Your Instagram at a glance."
        default: "Connect Instagram to see your numbers."
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .notConnected:
            notConnectedBlock
        case .connectedPersonal:
            messageBlock(
                status: "Professional account needed",
                kind: .issue,
                detail: "Switch your Instagram to a Creator or Business account to see insights here."
            )
        case .permissionNeeded:
            messageBlock(
                status: "Permission needed",
                kind: .issue,
                detail: "Allow insights access when connecting Instagram to see your numbers."
            )
        case .noData:
            messageBlock(
                status: "Not available",
                kind: .pending,
                detail: "No insights yet. Check back after your next post goes live."
            )
        case .ready(let report):
            reportContent(report)
        }
    }

    // MARK: States

    private var notConnectedBlock: some View {
        PocketSheetBlock(header: "How you're doing") {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                Text("See your followers, reach and saves — and what's working — without leaving the app.")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                PocketSheetFeedbackBanner(message: notConnectedBanner, kind: .pending)

                PocketSheetPrimaryAction(
                    title: services.isConnectingInstagram ? "Connecting…" : "Connect Instagram",
                    systemImage: "link"
                ) {
                    Task { await connect() }
                }
                .disabled(services.isConnectingInstagram)
                .accessibilityIdentifier("you.insights.connect")

                Text("We only read your insights. We never post for you, and your password stays with Instagram.")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(PocketSheetSpace.l)
        }
        .padding(.horizontal, PocketSheetSpace.l)
    }

    private func messageBlock(status: String, kind: PocketSheetStatusKind, detail: String) -> some View {
        PocketSheetBlock(header: "How you're doing") {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                PocketSheetStatus(text: status, kind: kind)
                    .accessibilityIdentifier("you.insights.status")
                Text(detail)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(PocketSheetSpace.l)
        }
        .padding(.horizontal, PocketSheetSpace.l)
    }

    // MARK: Ready

    @ViewBuilder
    private func reportContent(_ report: InstagramInsightsReport) -> some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.section) {
            if report.source != .api {
                HStack {
                    PocketSheetChip(text: report.source == .sample ? "Sample data" : "Manually entered")
                        .accessibilityIdentifier("you.insights.sourceLabel")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, PocketSheetSpace.l)
            }

            headlineTiles(report.headline)

            if let nudge = report.nudge?.nilIfBlank {
                PocketSheetFeedbackBanner(message: nudge, kind: .ready)
                    .padding(.horizontal, PocketSheetSpace.l)
                    .accessibilityIdentifier("you.insights.nudge")
            }

            if !report.detail.isEmpty {
                detailBlock(report.detail)
            }

            Text(footerText(report))
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                .padding(.horizontal, PocketSheetSpace.l)
                .accessibilityIdentifier("you.insights.footer")
        }
    }

    private func headlineTiles(_ metrics: [InstagramInsightMetric]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: PocketSheetSpace.s),
                GridItem(.flexible(), spacing: PocketSheetSpace.s)
            ],
            spacing: PocketSheetSpace.s
        ) {
            ForEach(metrics) { metric in
                StatTile(label: metric.label, value: metric.value, delta: metric.delta)
                    .accessibilityIdentifier("you.insights.tile.\(metric.id)")
            }
        }
        .padding(.horizontal, PocketSheetSpace.l)
    }

    private func detailBlock(_ metrics: [InstagramInsightMetric]) -> some View {
        PocketSheetBlock(header: "More detail") {
            VStack(spacing: 0) {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                    HStack(alignment: .firstTextBaseline, spacing: PocketSheetSpace.s) {
                        Text(metric.label)
                            .font(PocketSheetType.rowTitle)
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                        Spacer(minLength: PocketSheetSpace.s)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(metric.value)
                                .font(PocketSheetType.rowTitle)
                                .foregroundStyle(PocketSheetTheme.Color.ink)
                            if let delta = metric.delta {
                                Text(delta)
                                    .font(PocketSheetType.rowSubtitle)
                                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                            }
                        }
                    }
                    .frame(minHeight: 44)
                    .padding(.horizontal, PocketSheetSpace.l)
                    .padding(.vertical, PocketSheetSpace.s)
                    .accessibilityElement(children: .combine)

                    if index < metrics.count - 1 {
                        PocketSheetDivider()
                    }
                }
            }
        }
        .padding(.horizontal, PocketSheetSpace.l)
    }

    private func footerText(_ report: InstagramInsightsReport) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let when = formatter.string(from: report.fetchedAt)
        let handle = report.username.map { "@\($0)" } ?? "Instagram"
        return "\(handle) · updated \(when)"
    }

    // MARK: State resolution

    private var state: InstagramInsightsState {
#if DEBUG
        if DebugLaunchFlags.forceFixtureUI {
            return InstagramInsightsFixture.state(for: DebugLaunchFlags.insightsScenario)
        }
#endif
        return services.instagramInsights
    }

    private var notConnectedBanner: String? {
        connectError ?? services.lastInstagramInsightsError
    }

    // MARK: Actions

    @MainActor
    private func loadIfLive() async {
#if DEBUG
        if DebugLaunchFlags.forceFixtureUI { return }
#endif
        await services.refreshInstagramInsightsImmediately()
    }

    @MainActor
    private func connect() async {
        connectError = nil
        guard InstagramOAuth.isConfigured, let url = InstagramOAuth.authorizeURL() else {
            connectError = "Instagram connection isn't configured in this build yet."
            return
        }
        do {
            let callback = try await webAuthSession.authenticate(
                using: url,
                callbackURLScheme: InstagramOAuth.callbackScheme
            )
            guard let code = InstagramOAuth.authorizationCode(from: callback) else {
                connectError = "Couldn't read the Instagram response. Try again."
                return
            }
            await services.connectInstagram(code: code, redirectURI: InstagramOAuth.redirectURI ?? "")
        } catch {
            // User dismissed the sheet or cancelled sign-in; leave the CTA in place.
        }
    }
}
