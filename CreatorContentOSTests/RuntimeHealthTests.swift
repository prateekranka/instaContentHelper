import XCTest
@testable import CreatorContentOS

@MainActor
final class RuntimeHealthTests: XCTestCase {
    func testFixtureRuntimeShowsSampleHealthWithoutNetwork() async {
        let services = AppServices.fixtureBacked()
        await services.checkRuntimeHealthImmediately()

        XCTAssertEqual(services.supabaseHealthStatus, .sample)
        XCTAssertEqual(services.geminiHealthStatus, .sample)
        XCTAssertNotNil(services.lastRuntimeHealthCheckedAt)
        XCTAssertNil(services.lastRuntimeHealthError)
    }

    func testLiveHealthProbeMapsOKAndDownStates() async {
        let services = AppServices.fixtureBacked(
            repositories: AppRepositories(
                context: .creatorFixture,
                today: FixtureTodayCardRepository(),
                weeklyPlans: FixtureWeeklyPlanRepository(),
                references: FixtureReferenceRepository(),
                intelligence: FixtureIntelligenceRepository(),
                creatorProfile: FixtureCreatorProfileRepository(),
                archive: FixtureArchiveRepository(),
                runtimeHealth: StubRuntimeHealthRepository(
                    report: RuntimeHealthReport(
                        supabaseOK: true,
                        geminiOK: false,
                        supabaseDetail: nil,
                        geminiDetail: "gemini_api_key_missing",
                        checkedAt: Date(timeIntervalSince1970: 1_753_113_600)
                    )
                )
            ),
            isLiveSupabaseRuntime: true
        )

        await services.checkRuntimeHealthImmediately()

        XCTAssertEqual(services.supabaseHealthStatus, .live)
        XCTAssertEqual(services.geminiHealthStatus, .down("gemini_api_key_missing"))
        XCTAssertEqual(
            services.lastRuntimeHealthCheckedAt,
            Date(timeIntervalSince1970: 1_753_113_600)
        )
    }

    func testRuntimeHealthResponseDecoding() throws {
        let json = """
        {
          "checked_at": "2026-07-21T12:00:00.000Z",
          "supabase": { "ok": true, "latency_ms": 12 },
          "gemini": { "ok": false, "latency_ms": 40, "detail": "gemini_http_401" }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SupabaseRuntimeHealthResponse.self, from: json)
        let report = response.report()

        XCTAssertTrue(report.supabaseOK)
        XCTAssertFalse(report.geminiOK)
        XCTAssertEqual(report.geminiDetail, "gemini_http_401")
    }
}

private struct StubRuntimeHealthRepository: RuntimeHealthRepository {
    let report: RuntimeHealthReport

    func checkHealth(for context: WorkspaceContext) async throws -> RuntimeHealthReport {
        _ = context
        return report
    }
}
