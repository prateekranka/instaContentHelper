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
        let session = makeSession(email: "creator@example.com")
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

    func testRestoreForcesCreatorModeEvenWhenStartedAsAdmin() async {
        let session = makeSession(email: "creator@example.com", role: "creator")
        let authentication = AuthenticationServiceStub(restoredSession: session)
        let state = AppState(
            activeMode: .admin,
            authenticationService: authentication,
            liveRuntimeBuilder: { session in
                Self.fixtureLiveRuntime(session)
            }
        )

        await state.restoreAuthentication()

        XCTAssertEqual(state.authenticationPhase, AuthenticationPhase.live)
        XCTAssertEqual(state.activeMode, AppMode.creator)
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

    func testAppleSignInActivatesLiveRuntime() async throws {
        let session = makeSession(email: "creator@example.com", role: "creator")
        let authentication = AuthenticationServiceStub(appleSession: session)
        let state = AppState(
            authenticationService: authentication,
            liveRuntimeBuilder: { session in
                Self.fixtureLiveRuntime(session)
            }
        )
        state.authenticationPhase = AuthenticationPhase.signedOut

        await state.signInWithApple(idToken: "stub-apple-id-token", fullName: "Creator Name")

        XCTAssertEqual(state.authenticationPhase, AuthenticationPhase.live)
        XCTAssertEqual(state.runtime.mode, AppRuntimeMode.live(session))
        XCTAssertEqual(state.activeMode, AppMode.creator)
        XCTAssertNil(state.authenticationError)
        XCTAssertEqual(authentication.appleIDToken, "stub-apple-id-token")
        XCTAssertEqual(authentication.appleFullName, "Creator Name")
    }

    func testFirstLaunchAppleSignInUsesAutoProvisionedCreatorSession() async throws {
        let session = makeSession(email: "new-creator@example.com", role: "creator")
        let authentication = AuthenticationServiceStub(appleSession: session)
        let state = AppState(
            authenticationService: authentication,
            liveRuntimeBuilder: { session in
                Self.fixtureLiveRuntime(session)
            }
        )
        state.authenticationPhase = AuthenticationPhase.signedOut

        await state.signInWithApple(idToken: "first-launch-apple-token")

        XCTAssertEqual(state.authenticationPhase, AuthenticationPhase.live)
        XCTAssertEqual(state.runtime.mode, AppRuntimeMode.live(session))
        if case .live(let liveSession) = state.runtime.mode {
            XCTAssertEqual(liveSession.memberRole, "creator")
            XCTAssertEqual(liveSession.authenticatedEmail, "new-creator@example.com")
        } else {
            XCTFail("Expected live runtime after first-launch Apple sign-in.")
        }
        XCTAssertEqual(authentication.appleSignInCallCount, 1)
    }

    func testAppleSignInStaysLiveWhenTodayCardIsMissing() async throws {
        let session = makeSession(email: "creator@example.com", role: "creator")
        let authentication = AuthenticationServiceStub(appleSession: session)
        let state = AppState(
            authenticationService: authentication,
            liveRuntimeBuilder: { session in
                Self.runtimeWithMissingTodayCard(session)
            }
        )
        state.authenticationPhase = AuthenticationPhase.signedOut

        await state.signInWithApple(idToken: "stub-apple-id-token")
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

    func testAppleSignInFailureSurfacesStableMessage() async {
        let authentication = AuthenticationServiceStub(
            appleError: AuthenticationServiceError.backend("device_session_failed")
        )
        let state = AppState(
            authenticationService: authentication,
            liveRuntimeBuilder: { session in
                Self.fixtureLiveRuntime(session)
            }
        )
        state.authenticationPhase = AuthenticationPhase.signedOut

        await state.signInWithApple(idToken: "stub-apple-id-token")

        XCTAssertEqual(state.authenticationPhase, AuthenticationPhase.failed)
        XCTAssertEqual(
            state.authenticationError,
            "Signed in, but device access could not be created. Try again."
        )
    }

    func testFailSignInSurfacesCredentialErrorWithoutCallingService() async {
        let authentication = AuthenticationServiceStub()
        let state = AppState(
            authenticationService: authentication,
            liveRuntimeBuilder: { session in
                Self.fixtureLiveRuntime(session)
            }
        )
        state.authenticationPhase = AuthenticationPhase.signedOut

        await state.failSignIn(message: "Apple did not return a usable identity token.")

        XCTAssertEqual(state.authenticationPhase, AuthenticationPhase.failed)
        XCTAssertEqual(
            state.authenticationError,
            "Apple did not return a usable identity token."
        )
        XCTAssertEqual(authentication.appleSignInCallCount, 0)
    }

    func testSupabaseAuthenticationServiceRejectsEmptyAppleTokenBeforeBootstrap() async {
        let authentication = SupabaseAuthenticationService(bootstrapConfiguration: nil)

        do {
            _ = try await authentication.signInWithApple(idToken: "   ", fullName: nil)
            XCTFail("Expected empty Apple identity token validation to throw.")
        } catch {
            XCTAssertEqual(error as? AuthenticationServiceError, .invalidAppleIdentityToken)
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
        let session = makeSession(email: "creator@example.com")
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
        let session = makeSession(email: "creator@example.com")
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
        let session = makeSession(email: "creator@example.com")
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
    }

    func testRemoteUserDeletedEventReturnsToSignedOutShell() async {
        let session = makeSession(email: "creator@example.com")
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

        authentication.emit(.userDeleted)
        await Task.yield()
        authentication.finishEvents()
        await observation.value

        XCTAssertEqual(state.authenticationPhase, AuthenticationPhase.signedOut)
        XCTAssertEqual(state.activeMode, AppMode.creator)
        XCTAssertEqual(state.runtime.mode, AppRuntimeMode.fixtures)
    }

    func testLiveRuntimeStartsWithoutCreatorFixtureContent() throws {
        let runtime = Self.fixtureLiveRuntime(makeSession(email: "creator@example.com"))

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
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository(),
                testerAccess: FixtureTesterAccessRepository()
            ),
            todayCache: MemoryAuthenticationTodayCache(),
            notifications: NoopTodayNotificationScheduler()
        )
    }

    private func makeSession(email: String, role: String = "editor") -> PairedDeviceSession {
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
            memberRole: role,
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
    var appleSession: PairedDeviceSession?
    var appleError: Error?
    var signOutError: Error?
    private let eventStream: AsyncStream<AuthenticationSessionEvent>
    private let eventContinuation: AsyncStream<AuthenticationSessionEvent>.Continuation

    private(set) var restoreCallCount = 0
    private(set) var appleSignInCallCount = 0
    private(set) var appleIDToken: String?
    private(set) var appleFullName: String?
    private(set) var signedOutSession: PairedDeviceSession?

    init(
        restoredSession: PairedDeviceSession? = nil,
        appleSession: PairedDeviceSession? = nil,
        appleError: Error? = nil,
        signOutError: Error? = nil
    ) {
        self.restoredSession = restoredSession
        self.appleSession = appleSession
        self.appleError = appleError
        self.signOutError = signOutError
        let pair = AsyncStream<AuthenticationSessionEvent>.makeStream()
        self.eventStream = pair.stream
        self.eventContinuation = pair.continuation
    }

    func signInWithApple(idToken: String, fullName: String?) async throws -> PairedDeviceSession {
        appleSignInCallCount += 1
        appleIDToken = idToken
        appleFullName = fullName
        if let appleError { throw appleError }
        return try XCTUnwrap(appleSession)
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
