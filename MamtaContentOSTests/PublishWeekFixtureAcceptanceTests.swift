import XCTest
@testable import MamtaContentOS

@MainActor
final class PublishWeekFixtureAcceptanceTests: XCTestCase {
    func testPrateekPublishesFixtureWeekAndMamtaTodayReadsPublishedCard() async throws {
        let services = AppServices.preview

        XCTAssertFalse(services.weeklyPlan.isSoftLocked)
        XCTAssertEqual(services.weeklyPlan.days.count, 7)
        XCTAssertEqual(services.weekCards.count, 7)
        XCTAssertNil(services.lastRepositoryError)

        await services.publishCurrentWeekImmediately()

        XCTAssertTrue(services.weeklyPlan.isSoftLocked)
        XCTAssertTrue(services.weeklyPlan.days.allSatisfy(\.isSoftLocked))
        XCTAssertEqual(services.weekCards.count, 7)
        XCTAssertEqual(services.todayCard.title, "Race week has entered the house")
        XCTAssertEqual(services.todayCard.scheduledDate, "2026-06-05")
        XCTAssertEqual(services.lastPublishSummary, "Published 7 cards to Mamta Today.")
        XCTAssertNil(services.lastRepositoryError)
    }

    func testInitialRuntimeFallsBackToFixturesWithoutPairedSession() {
        let runtime = AppRuntime.makeInitialRuntime(store: EmptyRuntimeConfigurationStore())

        XCTAssertEqual(runtime.mode, .fixtures)
        XCTAssertEqual(runtime.services.todayCard.title, DailyCard.raceWeekToday.title)
    }
}

private struct EmptyRuntimeConfigurationStore: RuntimeConfigurationStoring {
    func loadPairedSession() throws -> PairedDeviceSession? {
        nil
    }

    func savePairedSession(_ session: PairedDeviceSession) throws {}

    func clearPairedSession() throws {}
}
