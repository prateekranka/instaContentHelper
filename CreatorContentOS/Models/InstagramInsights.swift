import Foundation

/// Where a set of insight numbers came from. Drives the "Sample data" label and
/// honors the design rule: never present sample/estimated numbers as real.
enum InstagramInsightsSource: String, Sendable, Codable {
    case api
    case sample
    case manual
}

/// A single display-ready metric (value + optional week-over-week delta already formatted).
struct InstagramInsightMetric: Identifiable, Sendable, Equatable {
    let id: String          // stable key, e.g. "followers"
    let label: String       // "Followers"
    let value: String       // "12,430"
    let delta: String?      // "+38 this week" / "up 22%"

    init(id: String, label: String, value: String, delta: String? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.delta = delta
    }
}

/// The account-level insight report shown on "How you're doing".
struct InstagramInsightsReport: Sendable, Equatable {
    let username: String?
    let source: InstagramInsightsSource
    let headline: [InstagramInsightMetric]   // Followers / Reach / Saves
    let detail: [InstagramInsightMetric]      // richer in-app view
    let nudge: String?
    let fetchedAt: Date
}

/// Every surface state for the insights screen. There is deliberately no
/// "zeros" state — a connected-but-empty account resolves to `.noData`,
/// per flow-and-state-spec "never draw zero metrics".
enum InstagramInsightsState: Sendable, Equatable {
    case notConnected
    case connectedPersonal    // Professional (Creator/Business) account required for insights
    case permissionNeeded     // connected, but insights scope not granted / pending
    case noData               // connected + permitted, nothing to show yet
    case ready(InstagramInsightsReport)
}

/// Sample numbers used both for the "Sample data" fallback (pre-approval / not a
/// test user) and for fixture-driven UI. Mirrors the vision Home card.
enum InstagramInsightsSample {
    static var report: InstagramInsightsReport {
        InstagramInsightsReport(
            username: "mamta",
            source: .sample,
            headline: [
                InstagramInsightMetric(id: "followers", label: "Followers", value: "12,430", delta: "+38 this week"),
                InstagramInsightMetric(id: "reach", label: "Reach", value: "8,214", delta: "up 22%"),
                InstagramInsightMetric(id: "saves", label: "Saves", value: "431", delta: "up 35%")
            ],
            detail: [
                InstagramInsightMetric(id: "profileViews", label: "Profile views", value: "540", delta: "up 12%"),
                InstagramInsightMetric(id: "nonFollowerReach", label: "Reach from non-followers", value: "38%"),
                InstagramInsightMetric(id: "bestDay", label: "Best day to post", value: "Wednesday")
            ],
            nudge: "Your early-morning training Reels reach the most people. Saves jump when you talk to camera.",
            fetchedAt: Date()
        )
    }
}

#if DEBUG
/// Maps a `MCO_INSIGHTS_SCENARIO` launch value to a state for fixture screenshots/QA.
enum InstagramInsightsFixture {
    static func state(for scenario: String?) -> InstagramInsightsState {
        switch scenario {
        case "sample":
            var sample = InstagramInsightsSample.report
            sample = InstagramInsightsReport(
                username: sample.username, source: .sample, headline: sample.headline,
                detail: sample.detail, nudge: sample.nudge, fetchedAt: sample.fetchedAt
            )
            return .ready(sample)
        case "personal":
            return .connectedPersonal
        case "permission":
            return .permissionNeeded
        case "nodata":
            return .noData
        case "notconnected":
            return .notConnected
        case "ready", .none, .some:
            // Default fixture = a connected account with real-looking (api-sourced) numbers.
            let s = InstagramInsightsSample.report
            return .ready(InstagramInsightsReport(
                username: s.username, source: .api, headline: s.headline,
                detail: s.detail, nudge: s.nudge, fetchedAt: s.fetchedAt
            ))
        }
    }
}
#endif
