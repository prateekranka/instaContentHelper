import Foundation
import Observation

@MainActor @Observable
final class MiraDependencies {
    let store: MiraStore
    let profileRepository: any MiraCreatorProfileRepository
    let makeSpeechInput: @MainActor () -> any MiraSpeechInputService
    private let makeLiveGeneration: @MainActor (PairedDeviceSession) -> any MiraGenerationService

    init(
        repository: any MiraProjectRepository & MiraCreatorProfileRepository,
        makeSpeechInput: @escaping @MainActor () -> any MiraSpeechInputService,
        makeLiveGeneration: @escaping @MainActor (PairedDeviceSession) -> any MiraGenerationService
    ) {
        store = MiraStore(repository: repository)
        profileRepository = repository
        self.makeSpeechInput = makeSpeechInput
        self.makeLiveGeneration = makeLiveGeneration
    }

    static func live() -> MiraDependencies {
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let fixtureSession = DebugLaunchFlags.forceFixtureUI ? DebugLaunchConfiguration.fixtureSession : nil
        let library = fixtureSession.map { "Mira-Fixtures-\($0)" } ?? "Mira"
        let repository = MiraFileRepository(
            directory: support.appendingPathComponent(library, isDirectory: true),
            seedDamagedFixture: fixtureSession != nil && DebugLaunchConfiguration.isEnabled("MCO_QA_DAMAGED_LIBRARY"))
        return MiraDependencies(
            repository: repository, makeSpeechInput: { MiraSpeechInput() },
            makeLiveGeneration: { MiraSupabaseGenerationService(session: $0) })
    }

    func generationService(
        for project: MiraProject?, appState: AppState, services: AppServices,
        requiresConsent: Bool = true
    ) throws -> any MiraGenerationService {
        if project?.isDemo == true {
            if let fixture = Self.todayFixture(for: project?.request ?? "") { return fixture }
            return MiraFixtureGenerationService(slowShotUpdate: DebugLaunchConfiguration.fixtureSession != nil)
        }
        guard case .live(let session) = appState.runtime.mode else {
            throw MiraError.invalid(
                "Connect your account from Profile to use live generation. You can still write manually and open saved work."
            )
        }
        if requiresConsent { try services.requireAIConsent() }
        return makeLiveGeneration(session)
    }

    static func todayFixture(for request: String) -> MiraSupabaseGenerationService? {
        #if DEBUG
        guard DebugLaunchFlags.forceFixtureUI, DebugLaunchConfiguration.fixtureSession != nil,
            ["Demo D2 steps", "Demo D2 legacy", "Demo D2 pictures", "Demo D2 transport"].contains(request),
            let endpoint = DebugLaunchConfiguration.value(for: "MCO_QA_D2_ENDPOINT"),
            let url = URL(string: endpoint), url.scheme == "https", url.host != nil
        else { return nil }
        let id = UUID()
        return MiraSupabaseGenerationService(session: PairedDeviceSession(
            projectURL: url, publishableKey: "fixture", workspaceID: id, creatorID: id, memberID: id,
            deviceInstallationID: id, deviceToken: "fixture", memberRole: "fixture", pairedAt: Date()))
        #else
        return nil
        #endif
    }
}

struct MiraSupabaseGenerationService: MiraGenerationService {
    let session: PairedDeviceSession
    var urlSession: URLSession = .shared
    private struct Request: Encodable {
        var action: String
        var id: UUID
        var creatorID: UUID
        var inputRevision: Int?
        var input: MiraGenerationInput?
        var consentVersion: Int?
        var pictures: Bool?
    }
    private struct Response: Decodable { var job: MiraJobResponse }
    private struct Failure: Decodable { var error: String? }
    func start(_ job: MiraJob) async throws -> MiraJobResponse { try await send("start", id: job.id, start: job) }
    func status(_ job: MiraJob) async throws -> MiraJobResponse { try await send("status", id: job.id) }
    func cancel(_ job: MiraJob) async throws -> MiraJobResponse { try await send("cancel", id: job.id) }
    func pictureStatus(_ jobID: UUID) async throws -> MiraJobResponse? {
        try await send("status", id: jobID, pictures: true)
    }

    private func send(
        _ action: String, id: UUID, start: MiraJob? = nil, pictures: Bool? = nil
    ) async throws -> MiraJobResponse {
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
                action: action, id: id, creatorID: session.creatorID, inputRevision: start?.inputRevision,
                input: start?.input, consentVersion: start == nil ? nil : 1, pictures: pictures))
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch let error as URLError where error.code == .networkConnectionLost && action != "cancel" {
            try Task.checkCancellation()
            (data, response) = try await urlSession.data(for: request)
        }
        guard let http = response as? HTTPURLResponse else { throw MiraError.offline }
        guard (200...299).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(Failure.self, from: data))?.error
            switch http.statusCode {
            case 401, 403:
                throw MiraError.invalid("Your device access expired. Reconnect your account in Profile.")
            case 404 where code == "not_found":
                throw MiraError.notFound
            case 404:
                throw MiraError.invalid(
                    "The Mira generation endpoint or job is unavailable. Your saved work is safe.")
            case 409 where code == "rate_limited", 429:
                throw MiraError.busy
            case 409:
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
