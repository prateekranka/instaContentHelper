import XCTest
@testable import CreatorContentOS

@MainActor
final class AuthenticationRuntimeTests: XCTestCase {
    func testExchangeResponseDecodesBackendContract() throws {
        let data = Data(
            """
            {
              "workspace_id": "11111111-1111-4111-8111-111111111111",
              "workspace_name": "Creator Content OS",
              "creator_id": "22222222-2222-4222-8222-222222222222",
              "creator_display_name": "Creator",
              "member_id": "33333333-3333-4333-8333-333333333333",
              "member_role": "editor",
              "member_email": "tester@example.com",
              "device_installation_id": "44444444-4444-4444-8444-444444444444",
              "device_token": "device-token",
              "paired_at": "2026-06-10T12:30:00.000Z"
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(
            AuthenticationSessionExchangeResponse.self,
            from: data
        )

        XCTAssertEqual(response.memberRole, "editor")
        XCTAssertEqual(response.memberEmail, "tester@example.com")
        XCTAssertEqual(response.creatorDisplayName, "Creator")
    }

    func testTodayReadResponseDecodesMissingPublishedStatus() throws {
        let data = Data(
            """
            {
              "today_card": null,
              "today_date": "2026-06-14",
              "today_status": "missing_published_card",
              "week_cards": []
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(SupabaseTodayReadResponse.self, from: data)

        XCTAssertNil(response.todayCard)
        XCTAssertEqual(response.todayDate, "2026-06-14")
        XCTAssertEqual(response.todayStatus, "missing_published_card")
        XCTAssertTrue(response.weekCards.isEmpty)
    }

    func testMissingSessionRestoresSignedOutState() async {
        let authentication = AuthenticationServiceStub(restoredSession: nil)
        let state = AppState(
            authenticationService: authentication,
            liveRuntimeBuilder: { session in
                Self.fixtureLiveRuntime(session)
            }
        )

        await state.restoreAuthentication()

        XCTAssertEqual(state.authenticationPhase, AuthenticationPhase.signedOut)
        XCTAssertEqual(authentication.restoreCallCount, 1)
    }

    func testStoredLiveSessionRestoresLiveRuntime() async {
        let session = makeSession(email: "tester@example.com")
        let authentication = AuthenticationServiceStub(restoredSession: session)
        let state = AppState(
            authenticationService: authentication,
            liveRuntimeBuilder: { session in
                Self.fixtureLiveRuntime(session)
            }
        )

        await state.restoreAuthentication()

        XCTAssertEqual(state.authenticationPhase, AuthenticationPhase.live)
        XCTAssertEqual(state.runtime.mode, AppRuntimeMode.live(session))
        XCTAssertEqual(state.activeMode, AppMode.creator)
        XCTAssertEqual(authentication.restoreCallCount, 1)
    }

    func testMissingLiveBootstrapConfigurationRestoresStableError() async {
        let state = AppState(
            authenticationService: SupabaseAuthenticationService(bootstrapConfiguration: nil),
            liveRuntimeBuilder: { session in
                Self.fixtureLiveRuntime(session)
            }
        )

        await state.restoreAuthentication()

        XCTAssertEqual(state.authenticationPhase, AuthenticationPhase.failed)
        XCTAssertEqual(state.authenticationError, "Live Supabase is not configured for this build.")
        XCTAssertEqual(state.runtime.mode, AppRuntimeMode.fixtures)
    }

    func testAuthenticationShellDoesNotTrustLegacyPairedSessionAtStartup() {
        let runtime = AppRuntime.makeAuthenticationShellRuntime(
            todayCache: MemoryAuthenticationTodayCache(),
            notifications: NoopTodayNotificationScheduler(),
            debugEnvironment: [:]
        )

        XCTAssertEqual(runtime.mode, AppRuntimeMode.fixtures)
    }

    func testOTPRequestAndVerificationActivateLiveRuntime() async throws {
        let session = makeSession(email: "tester@example.com")
        let authentication = AuthenticationServiceStub(verifiedSession: session)
        let state = AppState(
            authenticationService: authentication,
            liveRuntimeBuilder: { session in
                Self.fixtureLiveRuntime(session)
            }
        )
        state.authenticationPhase = AuthenticationPhase.signedOut

        await state.requestEmailOTP(" Tester@Example.com ")
        XCTAssertEqual(state.pendingEmail, "tester@example.com")
        XCTAssertEqual(authentication.requestedEmail, " Tester@Example.com ")

        await state.verifyEmailOTP("123456")

        XCTAssertEqual(state.authenticationPhase, AuthenticationPhase.live)
        XCTAssertEqual(state.runtime.mode, AppRuntimeMode.live(session))
        XCTAssertNil(state.pendingEmail)
        XCTAssertEqual(authentication.verifiedEmail, "tester@example.com")
        XCTAssertEqual(authentication.verifiedToken, "123456")
    }

    func testResetSignInClearsPendingEmailAndError() async {
        let authentication = AuthenticationServiceStub(
            requestError: AuthenticationServiceError.backend("tester_not_approved")
        )
        let state = AppState(
            authenticationService: authentication,
            liveRuntimeBuilder: { session in
                Self.fixtureLiveRuntime(session)
            }
        )
        state.authenticationPhase = AuthenticationPhase.signedOut

        await state.requestEmailOTP("unknown@example.com")
        XCTAssertEqual(state.authenticationPhase, AuthenticationPhase.failed)
        XCTAssertNotNil(state.authenticationError)

        state.pendingEmail = "unknown@example.com"
        state.resetSignIn()

        XCTAssertEqual(state.authenticationPhase, AuthenticationPhase.signedOut)
        XCTAssertNil(state.pendingEmail)
        XCTAssertNil(state.authenticationError)
    }

    func testVerifyWithoutPendingEmailShowsStableRecoveryError() async {
        let authentication = AuthenticationServiceStub()
        let state = AppState(
            authenticationService: authentication,
            liveRuntimeBuilder: { session in
                Self.fixtureLiveRuntime(session)
            }
        )
        state.authenticationPhase = AuthenticationPhase.signedOut

        await state.verifyEmailOTP("123456")

        XCTAssertEqual(state.authenticationPhase, AuthenticationPhase.failed)
        XCTAssertEqual(state.authenticationError, "Request a new code first.")
        XCTAssertNil(authentication.verifiedEmail)
    }

    func testOTPVerificationStaysLiveWhenTodayCardIsMissing() async throws {
        let session = makeSession(email: "tester@example.com")
        let authentication = AuthenticationServiceStub(verifiedSession: session)
        let state = AppState(
            authenticationService: authentication,
            liveRuntimeBuilder: { session in
                Self.runtimeWithMissingTodayCard(session)
            }
        )
        state.authenticationPhase = AuthenticationPhase.signedOut

        await state.requestEmailOTP("tester@example.com")
        await state.verifyEmailOTP("123456")
        await waitForTodayContentState(
            in: state,
            toBecome: TodayContentState.missingPublishedCard(date: "2026-06-14")
        )

        XCTAssertEqual(state.authenticationPhase, AuthenticationPhase.live)
        XCTAssertEqual(state.runtime.mode, AppRuntimeMode.live(session))
        XCTAssertNil(state.authenticationError)
        XCTAssertEqual(
            state.runtime.services.todayContentState,
            TodayContentState.missingPublishedCard(date: "2026-06-14")
        )
        XCTAssertNil(state.runtime.services.lastRepositoryError)
    }

    func testAuthenticationFailureSurfacesStableMessage() async {
        let authentication = AuthenticationServiceStub(
            requestError: AuthenticationServiceError.backend("tester_not_approved")
        )
        let state = AppState(
            authenticationService: authentication,
            liveRuntimeBuilder: { session in
                Self.fixtureLiveRuntime(session)
            }
        )
        state.authenticationPhase = AuthenticationPhase.signedOut

        await state.requestEmailOTP("unknown@example.com")

        XCTAssertEqual(state.authenticationPhase, AuthenticationPhase.failed)
        XCTAssertEqual(
            state.authenticationError,
            "This email has not been approved for testing."
        )
    }

    func testSupabaseAuthenticationServiceRejectsInvalidEmailBeforeBootstrap() async {
        let authentication = SupabaseAuthenticationService(bootstrapConfiguration: nil)

        do {
            try await authentication.requestEmailOTP(email: "not-an-email")
            XCTFail("Expected invalid email validation to throw.")
        } catch {
            XCTAssertEqual(error as? AuthenticationServiceError, .invalidEmail)
        }
    }

    func testSupabaseAuthenticationServiceRejectsInvalidOTPBeforeBootstrap() async {
        let authentication = SupabaseAuthenticationService(bootstrapConfiguration: nil)

        do {
            _ = try await authentication.verifyEmailOTP(email: "tester@example.com", token: "12ab")
            XCTFail("Expected invalid OTP validation to throw.")
        } catch {
            XCTAssertEqual(error as? AuthenticationServiceError, .invalidOTP)
        }
    }

    func testCurrentDeviceNameProviderUsesTrimmedNameOrFallback() {
        XCTAssertEqual(
            CurrentDeviceNameProvider.displayName(from: " ContentHelper QA iPhone "),
            "ContentHelper QA iPhone"
        )
        XCTAssertEqual(CurrentDeviceNameProvider.displayName(from: "  "), "iPhone")
        XCTAssertEqual(CurrentDeviceNameProvider.displayName(from: nil), "iPhone")
        XCTAssertFalse(CurrentDeviceNameProvider.deviceName().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testSignOutRevokesSessionAndReturnsToSignedOutShell() async throws {
        let session = makeSession(email: "tester@example.com")
        let authentication = AuthenticationServiceStub()
        let state = AppState(
            runtime: Self.fixtureLiveRuntime(session),
            authenticationPhase: AuthenticationPhase.live,
            authenticationService: authentication,
            liveRuntimeBuilder: { session in
                Self.fixtureLiveRuntime(session)
            }
        )

        await state.signOut()

        XCTAssertEqual(authentication.signedOutSession, session)
        XCTAssertEqual(state.authenticationPhase, AuthenticationPhase.signedOut)
        XCTAssertEqual(state.activeMode, AppMode.creator)
        XCTAssertEqual(state.runtime.mode, AppRuntimeMode.fixtures)
    }

    func testSignOutRevokeFailureStillClearsLocalSession() async throws {
        let session = makeSession(email: "tester@example.com")
        let authentication = AuthenticationServiceStub(
            signOutError: AuthenticationServiceError.backend("session_revoke_failed")
        )
        let state = AppState(
            runtime: Self.fixtureLiveRuntime(session),
            authenticationPhase: AuthenticationPhase.live,
            authenticationService: authentication,
            liveRuntimeBuilder: { session in
                Self.fixtureLiveRuntime(session)
            }
        )

        await state.signOut()

        XCTAssertEqual(authentication.signedOutSession, session)
        XCTAssertEqual(state.authenticationError, "The server could not revoke this device session.")
        XCTAssertEqual(state.authenticationPhase, AuthenticationPhase.signedOut)
        XCTAssertEqual(state.activeMode, AppMode.creator)
        XCTAssertEqual(state.runtime.mode, AppRuntimeMode.fixtures)
    }

    func testRemoteSignedOutEventReturnsToSignedOutShell() async {
        let session = makeSession(email: "tester@example.com")
        let authentication = AuthenticationServiceStub()
        let state = AppState(
            activeMode: .admin,
            runtime: Self.fixtureLiveRuntime(session),
            authenticationPhase: AuthenticationPhase.live,
            authenticationService: authentication,
            liveRuntimeBuilder: { session in
                Self.fixtureLiveRuntime(session)
            }
        )

        let observation = Task { @MainActor in
            await state.observeAuthenticationChanges()
        }
        await Task.yield()

        authentication.emit(.signedOut)
        await Task.yield()
        authentication.finishEvents()
        await observation.value

        XCTAssertEqual(state.authenticationPhase, AuthenticationPhase.signedOut)
        XCTAssertEqual(state.activeMode, AppMode.creator)
        XCTAssertEqual(state.runtime.mode, AppRuntimeMode.fixtures)
        XCTAssertNil(state.pendingEmail)
    }

    func testRemoteUserDeletedEventReturnsToSignedOutShell() async {
        let session = makeSession(email: "tester@example.com")
        let authentication = AuthenticationServiceStub()
        let state = AppState(
            activeMode: .admin,
            runtime: Self.fixtureLiveRuntime(session),
            authenticationPhase: AuthenticationPhase.live,
            authenticationService: authentication,
            liveRuntimeBuilder: { session in
                Self.fixtureLiveRuntime(session)
            }
        )
        state.pendingEmail = "tester@example.com"

        let observation = Task { @MainActor in
            await state.observeAuthenticationChanges()
        }
        await Task.yield()

        authentication.emit(.userDeleted)
        await Task.yield()
        authentication.finishEvents()
        await observation.value

        XCTAssertEqual(state.authenticationPhase, AuthenticationPhase.signedOut)
        XCTAssertEqual(state.activeMode, AppMode.creator)
        XCTAssertEqual(state.runtime.mode, AppRuntimeMode.fixtures)
        XCTAssertNil(state.pendingEmail)
    }

    func testLiveRuntimeStartsWithoutCreatorFixtureContent() throws {
        let runtime = Self.fixtureLiveRuntime(makeSession(email: "tester@example.com"))

        XCTAssertEqual(runtime.services.todayCard.title, "Loading today's card")
        XCTAssertTrue(runtime.services.archiveEntries.isEmpty)
        XCTAssertTrue(runtime.services.weekCards.isEmpty)
        XCTAssertTrue(runtime.services.weeklyPlan.days.isEmpty)
    }

    private static func fixtureLiveRuntime(_ session: PairedDeviceSession) -> AppRuntime {
        AppRuntime.live(
            session: session,
            repositories: .fixture,
            todayCache: MemoryAuthenticationTodayCache(),
            notifications: NoopTodayNotificationScheduler()
        )
    }

    private static func runtimeWithMissingTodayCard(_ session: PairedDeviceSession) -> AppRuntime {
        AppRuntime.live(
            session: session,
            repositories: AppRepositories(
                context: session.context,
                today: MissingTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                referenceImport: FixtureReferenceImportRepository(),
                weeklyGeneration: TestWeeklyGenerationRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository(),
                testerAccess: FixtureTesterAccessRepository()
            ),
            todayCache: MemoryAuthenticationTodayCache(),
            notifications: NoopTodayNotificationScheduler()
        )
    }

    private func makeSession(email: String) -> PairedDeviceSession {
        PairedDeviceSession(
            projectURL: URL(string: "http://127.0.0.1:54321")!,
            publishableKey: "publishable-test-key",
            workspaceID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            creatorID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            memberID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            deviceInstallationID: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
            deviceToken: "device-token",
            workspaceName: "Creator Content OS",
            creatorDisplayName: "Creator",
            memberRole: "editor",
            pairedAt: Date(timeIntervalSince1970: 1_780_000_000),
            authenticatedEmail: email
        )
    }

    private func waitForTodayContentState(
        in state: AppState,
        toBecome expectedState: TodayContentState,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async {
        let intervalNanoseconds: UInt64 = 20_000_000
        var elapsedNanoseconds: UInt64 = 0

        while state.runtime.services.todayContentState != expectedState,
              elapsedNanoseconds < timeoutNanoseconds {
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
            elapsedNanoseconds += intervalNanoseconds
        }
    }

}

private final class AuthenticationServiceStub: AuthenticationServicing, @unchecked Sendable {
    var restoredSession: PairedDeviceSession?
    var verifiedSession: PairedDeviceSession?
    var requestError: Error?
    var verifyError: Error?
    var signOutError: Error?
    private let eventStream: AsyncStream<AuthenticationSessionEvent>
    private let eventContinuation: AsyncStream<AuthenticationSessionEvent>.Continuation

    private(set) var restoreCallCount = 0
    private(set) var requestedEmail: String?
    private(set) var verifiedEmail: String?
    private(set) var verifiedToken: String?
    private(set) var signedOutSession: PairedDeviceSession?

    init(
        restoredSession: PairedDeviceSession? = nil,
        verifiedSession: PairedDeviceSession? = nil,
        requestError: Error? = nil,
        verifyError: Error? = nil,
        signOutError: Error? = nil
    ) {
        self.restoredSession = restoredSession
        self.verifiedSession = verifiedSession
        self.requestError = requestError
        self.verifyError = verifyError
        self.signOutError = signOutError
        let pair = AsyncStream<AuthenticationSessionEvent>.makeStream()
        self.eventStream = pair.stream
        self.eventContinuation = pair.continuation
    }

    func requestEmailOTP(email: String) async throws {
        requestedEmail = email
        if let requestError { throw requestError }
    }

    func verifyEmailOTP(email: String, token: String) async throws -> PairedDeviceSession {
        verifiedEmail = email
        verifiedToken = token
        if let verifyError { throw verifyError }
        return try XCTUnwrap(verifiedSession)
    }

    func restoreSession() async throws -> PairedDeviceSession? {
        restoreCallCount += 1
        return restoredSession
    }

    func signOut(deviceSession: PairedDeviceSession?) async throws {
        signedOutSession = deviceSession
        if let signOutError { throw signOutError }
    }

    func authenticationEvents() -> AsyncStream<AuthenticationSessionEvent> {
        eventStream
    }

    func emit(_ event: AuthenticationSessionEvent) {
        eventContinuation.yield(event)
    }

    func finishEvents() {
        eventContinuation.finish()
    }
}

private final class MemoryAuthenticationTodayCache: TodayCacheStoring {
    private var snapshots: [WorkspaceContext: CachedTodaySnapshot] = [:]

    func loadSnapshot(for context: WorkspaceContext) throws -> CachedTodaySnapshot? {
        snapshots[context]
    }

    func saveSnapshot(_ snapshot: CachedTodaySnapshot, for context: WorkspaceContext) throws {
        snapshots[context] = snapshot
    }

    func clearSnapshot(for context: WorkspaceContext) throws {
        snapshots[context] = nil
    }
}

private struct MissingTodayCardRepository: TodayCardRepository {
    func todayCard(for context: WorkspaceContext) async throws -> DailyCard {
        throw RepositoryError.noPublishedTodayCard(date: "2026-06-14")
    }

    func weekCards(for context: WorkspaceContext) async throws -> [DailyCard] {
        []
    }

    func completeToday(
        card: DailyCard,
        decision: DailyDecision,
        context: WorkspaceContext
    ) async throws -> ArchiveEntry {
        throw RepositoryError.noPublishedTodayCard(date: "2026-06-14")
    }
}
