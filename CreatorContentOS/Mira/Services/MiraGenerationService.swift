import Foundation
import Observation

@MainActor @Observable
final class MiraDependencies {
    let store: MiraStore
    let reelMedia: MiraReelMedia
    let profileRepository: any MiraCreatorProfileRepository
    let makeSpeechInput: @MainActor () -> any MiraSpeechInputService

    init(
        repository: any MiraProjectRepository & MiraCreatorProfileRepository,
        reelMedia: MiraReelMedia,
        makeSpeechInput: @escaping @MainActor () -> any MiraSpeechInputService
    ) {
        store = MiraStore(repository: repository)
        self.reelMedia = reelMedia
        profileRepository = repository
        self.makeSpeechInput = makeSpeechInput
    }

    static func live() -> MiraDependencies {
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let fixtureSession = DebugLaunchFlags.forceFixtureUI ? DebugLaunchConfiguration.fixtureSession : nil
        let library = fixtureSession.map { "Mira-Fixtures-\($0)" } ?? "Mira"
        let directory = support.appendingPathComponent(library, isDirectory: true)
        let repository = MiraFileRepository(
            directory: directory,
            seedDamagedFixture: fixtureSession != nil && DebugLaunchConfiguration.isEnabled("MCO_QA_DAMAGED_LIBRARY"),
            seedDeliveryFixture: fixtureSession != nil && DebugLaunchConfiguration.isEnabled("MCO_QA_E4"))
        return MiraDependencies(repository: repository,
            reelMedia: MiraReelMedia(directory: directory.appendingPathComponent("Media", isDirectory: true)),
            makeSpeechInput: { MiraSpeechInput() })
    }

    func generationService(
        for project: MiraProject?, appState: AppState,
        requiresConsent: Bool = true
    ) throws -> any MiraGenerationService {
        if project?.isDemo == true {
            if let fixture = Self.todayFixture(for: project?.request ?? "") { return fixture }
            return Self.fixtureGeneration(
                slowShotUpdate: DebugLaunchConfiguration.fixtureSession != nil,
                rejectFirstShotUpdate: project?.request == "Demo rejected shot update")
        }
        guard !DebugLaunchFlags.forceFixtureUI, case .live(let session) = appState.runtime.mode else {
            throw MiraError.invalid(
                "Connect your account from Profile to use live generation. You can still write manually and open saved work."
            )
        }
        if requiresConsent { try appState.runtime.services.requireAIConsent() }
        return MiraSupabaseGenerationService(session: session, authorize: { [weak appState] start in
            guard let runtime = appState?.runtime, case .live(let current) = runtime.mode,
                current.creatorID == session.creatorID, current.workspaceID == session.workspaceID,
                current.memberID == session.memberID, current.deviceToken == session.deviceToken
            else { throw MiraError.anotherAccount }
            if start { try runtime.services.requireAIConsent() }
        })
    }

    static func fixtureGeneration(
        failTodayCard: Bool = false, slowTodayCards: Bool = false,
        slowShotUpdate: Bool = false, rejectFirstShotUpdate: Bool = false
    ) -> MiraFixtureGenerationService {
        let isFixtureSession = DebugLaunchFlags.forceFixtureUI && DebugLaunchConfiguration.fixtureSession != nil
        let creatorID = isFixtureSession
            ? DebugLaunchConfiguration.value(for: "MCO_QA_FIXTURE_CREATOR").flatMap { UUID(uuidString: $0) }
            : nil
        return MiraFixtureGenerationService(
            failTodayCard: failTodayCard, slowTodayCards: slowTodayCards, slowShotUpdate: slowShotUpdate,
            rejectFirstShotUpdate: rejectFirstShotUpdate, isFixtureSession: isFixtureSession, creatorID: creatorID)
    }

    static func todayFixture(for request: String) -> MiraSupabaseGenerationService? {
        #if DEBUG
        guard DebugLaunchFlags.forceFixtureUI, DebugLaunchConfiguration.fixtureSession != nil,
            ["Demo D2 steps", "Demo D2 legacy", "Demo D2 pictures", "Demo D2 transport", "Demo E2 pick", "Demo E5 note"].contains(request),
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

struct MiraSupabaseGenerationService: MiraGenerationService, MiraDealBriefService, MiraDeliveryService, MiraDailyNoteService {
    let session: PairedDeviceSession
    var urlSession: URLSession = .shared
    var authorize: (@MainActor @Sendable (Bool) throws -> Void)?
    var creatorID: UUID? { authorize == nil ? nil : session.creatorID }
    private struct Request<Input: Encodable>: Encodable {
        var action: String
        var id: UUID
        var creatorID: UUID
        var inputRevision: Int?
        var input: Input?
        var consentVersion: Int?
        var pictures: Bool?
    }
    private struct Response<Reply: Decodable>: Decodable { var job: Reply }
    private struct Failure: Decodable { var error: String? }
    func start(_ job: MiraJob) async throws -> MiraJobResponse {
        try checkOwner(job)
        if creatorID != nil, job.creatorID == nil { throw MiraError.unknownAccount }
        return try await send("start", id: job.id, start: job)
    }
    func status(_ job: MiraJob) async throws -> MiraJobResponse {
        try checkOwner(job)
        return try await send("status", id: job.id)
    }
    func cancel(_ job: MiraJob) async throws -> MiraJobResponse {
        try checkOwner(job)
        return try await send("cancel", id: job.id)
    }
    private func checkOwner(_ job: MiraJob) throws {
        if let owner = job.creatorID, owner != creatorID { throw MiraError.anotherAccount }
    }
    func pictureStatus(_ jobID: UUID) async throws -> MiraJobResponse? {
        try await send("status", id: jobID, pictures: true)
    }

    private func send(
        _ action: String, id: UUID, start: MiraJob? = nil, pictures: Bool? = nil
    ) async throws -> MiraJobResponse {
        try await send(Request(
            action: action, id: id, creatorID: session.creatorID, inputRevision: start?.inputRevision,
            input: start?.input, consentVersion: start == nil ? nil : 1, pictures: pictures))
    }

    func readDealBrief(_ job: MiraDealBriefJob, start: Bool) async throws -> MiraDealBriefReply {
        guard job.creatorID == creatorID else { throw MiraError.anotherAccount }
        return try await send(Request(
            action: start ? "start" : "status", id: job.id, creatorID: session.creatorID,
            inputRevision: start ? MiraDealBriefJob.revision : nil, input: start ? job.input : nil,
            consentVersion: start ? 1 : nil))
    }

    func briefCheck(_ job: MiraDeliveryJob<MiraBriefCheckInput>, start: Bool) async throws
        -> MiraDeliveryReply<MiraBriefCheckInput, MiraBriefCheckOutput> {
        try await sendDelivery(job, start: start)
    }

    func brandNote(_ job: MiraDeliveryJob<MiraBrandNoteInput>, start: Bool) async throws
        -> MiraDeliveryReply<MiraBrandNoteInput, MiraBrandNoteOutput> {
        try await sendDelivery(job, start: start)
    }

    private func sendDelivery<Input, Output>(_ job: MiraDeliveryJob<Input>, start: Bool) async throws
        -> MiraDeliveryReply<Input, Output> {
        guard job.creatorID == creatorID else { throw MiraError.anotherAccount }
        return try await send(Request(
            action: start ? "start" : "status", id: job.id, creatorID: session.creatorID,
            inputRevision: start ? job.revision : nil, input: start ? job.input : nil,
            consentVersion: start ? 1 : nil))
    }

    func dailyNote(id: UUID, input: MiraDailyNoteInput?) async throws -> MiraDailyNoteReply {
        try await send(Request(action: input == nil ? "status" : "start", id: id, creatorID: session.creatorID,
                               inputRevision: input == nil ? nil : 0, input: input,
                               consentVersion: input == nil ? nil : 1))
    }

    private func send<Input: Encodable, Reply: Decodable>(_ body: Request<Input>) async throws -> Reply {
        let needsConsent = body.action == "start" || body.pictures == true
        let url = session.projectURL.appendingPathComponent("functions/v1/mira-generation")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 65
        request.setValue(session.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue(session.deviceToken, forHTTPHeaderField: "x-mco-device-token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response): (Data, URLResponse)
        do {
            try await authorize?(needsConsent)
            try Task.checkCancellation()
            (data, response) = try await urlSession.data(for: request)
        } catch let error as URLError where error.code == .networkConnectionLost && body.action != "cancel" {
            try Task.checkCancellation()
            do {
                try await authorize?(needsConsent)
            } catch let consent as AIConsentRequired {
                guard body.action == "start" else { throw consent }
                do {
                    return try await send(Request<Input>(action: "status", id: body.id, creatorID: body.creatorID))
                } catch MiraError.notFound {
                    throw consent
                }
            }
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
            case 429 where code == "operation_daily_cap_reached" && Input.self == MiraDealBriefInput.self:
                throw MiraError.invalid("Mira has reached today's limit for reading briefs. Try again tomorrow.")
            case 429 where code == "operation_daily_cap_reached":
                throw MiraError.invalid("Mira reached today’s limit for this request. Try again tomorrow.")
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
        return try JSONDecoder().decode(Response<Reply>.self, from: data).job
    }
}

#if DEBUG
extension MiraDeliveryFixture {
    static var isEnabled: Bool {
        DebugLaunchFlags.forceFixtureUI && DebugLaunchConfiguration.fixtureSession != nil
            && DebugLaunchConfiguration.isEnabled("MCO_QA_E4")
    }
}
#endif
