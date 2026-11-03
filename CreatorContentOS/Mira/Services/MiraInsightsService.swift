import Foundation

/// Reads the creator's Instagram account insights (and manages the connection)
/// for Mira's "How you're doing" surface. Mirrors `MiraSupabaseGenerationService`:
/// session-based direct calls to the edge functions, no Supabase SDK.
protocol MiraInsightsService: Sendable {
    func fetchInsights() async throws -> InstagramInsightsState
    func connect(code: String, redirectURI: String) async throws
    func disconnect() async throws
}

struct MiraSupabaseInsightsService: MiraInsightsService {
    let session: PairedDeviceSession
    var urlSession: URLSession = .shared

    func fetchInsights() async throws -> InstagramInsightsState {
        let response: InstagramInsightsResponse = try await post(
            "instagram-insights",
            body: InstagramInsightsRequest(creatorID: session.creatorID)
        )
        if let error = response.error?.nilIfBlank {
            throw MiraError.invalid(error)
        }
        return response.toState()
    }

    func connect(code: String, redirectURI: String) async throws {
        let response: InstagramConnectResponse = try await post(
            "instagram-connect",
            body: InstagramConnectRequest(
                creatorID: session.creatorID, code: code, redirectURI: redirectURI
            )
        )
        if let error = response.error?.nilIfBlank {
            throw MiraError.invalid(Self.connectMessage(for: error))
        }
    }

    private static func connectMessage(for code: String) -> String {
        switch code {
        case "instagram_account_not_linked":
            "We couldn't find an Instagram Creator or Business account. Connect again and choose your Instagram account when asked."
        case "instagram_permission_denied":
            "Mira needs permission to read your Instagram insights. Try connecting again and allow access."
        default:
            "Instagram didn't connect. Try again in a moment."
        }
    }

    func disconnect() async throws {
        let _: InstagramDisconnectResponse = try await post(
            "instagram-disconnect",
            body: InstagramDisconnectRequest(creatorID: session.creatorID)
        )
    }

    private func post<B: Encodable, R: Decodable>(_ function: String, body: B) async throws -> R {
        let url = session.projectURL.appendingPathComponent("functions/v1/\(function)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(session.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue(session.deviceToken, forHTTPHeaderField: "x-mco-device-token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MiraError.offline }
        guard (200...299).contains(http.statusCode) else {
            switch http.statusCode {
            case 401, 403:
                throw MiraError.invalid("Your device access expired. Reconnect your account in Profile.")
            default:
                throw MiraError.invalid("Insights are unavailable right now (\(http.statusCode)). Your saved work is unchanged.")
            }
        }
        return try JSONDecoder().decode(R.self, from: data)
    }
}
