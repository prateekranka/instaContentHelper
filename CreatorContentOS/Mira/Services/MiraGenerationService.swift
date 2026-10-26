import Foundation

protocol MiraGenerationService: Sendable {
    func start(_ job: MiraJob) async throws -> MiraJob
    func status(_ job: MiraJob) async throws -> MiraJob
    func cancel(_ job: MiraJob) async throws -> MiraJob
}
struct MiraSupabaseGenerationService: MiraGenerationService {
    let session: PairedDeviceSession
    private struct Request: Encodable {
        var action: String
        var id: UUID
        var creatorID: UUID
        var inputRevision: Int?
        var input: MiraGenerationInput?
        var consentVersion: Int?
    }
    private struct Response: Decodable { var job: MiraJob }
    func start(_ job: MiraJob) async throws -> MiraJob { try await send("start", job: job) }
    func status(_ job: MiraJob) async throws -> MiraJob { try await send("status", job: job) }
    func cancel(_ job: MiraJob) async throws -> MiraJob { try await send("cancel", job: job) }
    private func send(_ action: String, job: MiraJob) async throws -> MiraJob {
        let url = session.projectURL.appendingPathComponent("functions/v1/mira-generation")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 65
        request.setValue(session.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue(session.deviceToken, forHTTPHeaderField: "x-mco-device-token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            Request(
                action: action, id: job.id, creatorID: session.creatorID,
                inputRevision: action == "start" ? job.inputRevision : nil,
                input: action == "start" ? job.input : nil, consentVersion: action == "start" ? 1 : nil))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MiraError.offline }
        guard (200...299).contains(http.statusCode) else {
            switch http.statusCode {
            case 401, 403:
                throw MiraError.invalid("Your device access expired. Reconnect your account in Profile.")
            case 404:
                throw MiraError.invalid(
                    "The Mira generation endpoint or job is unavailable. Your saved work is safe.")
            case 409, 429:
                throw MiraError.invalid(
                    "Mira is busy or this request conflicts with an earlier job. Wait, then reconnect the saved request."
                )
            default:
                throw MiraError.invalid(
                    "Generation is unavailable (\(http.statusCode)). Your saved work is unchanged.")
            }
        }
        return try JSONDecoder().decode(Response.self, from: data).job
    }
}
struct MiraFixtureGenerationService: MiraGenerationService {
    func start(_ job: MiraJob) async throws -> MiraJob {
        try Task.checkCancellation()
        var result = job
        result.output = MiraFixtures.output(for: job.input)
        result.state = .succeeded
        try MiraValidation.validate(result.output!, for: job.input.operation, input: job.input)
        return result
    }
    func status(_ job: MiraJob) async throws -> MiraJob { try await start(job) }
    func cancel(_ job: MiraJob) async throws -> MiraJob {
        var result = job
        result.state = .cancelled
        return result
    }
}
