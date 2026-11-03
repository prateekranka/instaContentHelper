import Foundation

// Request/response DTOs for the instagram-connect / instagram-insights /
// instagram-disconnect edge functions, plus mapping of the insights response
// into the UI-facing `InstagramInsightsState`.

struct InstagramConnectRequest: Encodable, Sendable {
    let creatorID: UUID
    let code: String
    let redirectURI: String

    enum CodingKeys: String, CodingKey {
        case creatorID = "creator_id"
        case code
        case redirectURI = "redirect_uri"
    }
}

struct InstagramConnectResponse: Decodable, Hashable, Sendable {
    var connected: Bool?
    var username: String?
    var accountType: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case connected
        case username
        case accountType = "account_type"
        case error
    }
}

struct InstagramInsightsRequest: Encodable, Sendable {
    let creatorID: UUID

    enum CodingKeys: String, CodingKey {
        case creatorID = "creator_id"
    }
}

struct InstagramDisconnectRequest: Encodable, Sendable {
    let creatorID: UUID

    enum CodingKeys: String, CodingKey {
        case creatorID = "creator_id"
    }
}

struct InstagramDisconnectResponse: Decodable, Hashable, Sendable {
    var connected: Bool?
    var error: String?
}

struct InstagramInsightMetricDTO: Decodable, Hashable, Sendable {
    var id: String
    var label: String
    var value: String
    var delta: String?
}

struct InstagramInsightsResponse: Decodable, Hashable, Sendable {
    var connected: Bool?
    var accountType: String?
    var source: String?
    var state: String?
    var username: String?
    var metrics: [InstagramInsightMetricDTO]?
    var detail: [InstagramInsightMetricDTO]?
    var nudge: String?
    var fetchedAt: String?
    var dataQuality: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case connected
        case accountType = "account_type"
        case source
        case state
        case username
        case metrics
        case detail
        case nudge
        case fetchedAt = "fetched_at"
        case dataQuality = "data_quality"
        case error
    }
}

extension InstagramInsightsResponse {
    /// Maps the edge-function response into the UI state. Unknown states and
    /// `ready` with no metrics both collapse to `.noData` so the screen never
    /// renders zeros.
    func toState() -> InstagramInsightsState {
        switch state {
        case "not_connected":
            return .notConnected
        case "connected_personal":
            return .connectedPersonal
        case "permission_needed":
            return .permissionNeeded
        case "no_data":
            return .noData
        case "ready":
            let headline = (metrics ?? []).map(\.model)
            guard !headline.isEmpty else { return .noData }
            return .ready(InstagramInsightsReport(
                username: username,
                source: InstagramInsightsSource(rawValue: source ?? "api") ?? .api,
                headline: headline,
                detail: (detail ?? []).map(\.model),
                nudge: nudge,
                fetchedAt: Self.parseDate(fetchedAt)
            ))
        default:
            return .notConnected
        }
    }

    private static func parseDate(_ iso: String?) -> Date {
        guard let iso else { return Date() }
        return SupabaseDateFormatting.timestamp(from: iso) ?? Date()
    }
}

private extension InstagramInsightMetricDTO {
    var model: InstagramInsightMetric {
        InstagramInsightMetric(id: id, label: label, value: value, delta: delta)
    }
}
