import XCTest

final class InstalledContentHelperUITests: XCTestCase {
    private let bundleIdentifier = "com.prateekranka.creatorcontenthelper"

    @MainActor
    func testInstalledSessionExposesManagerAccess() throws {
        let app = launchInstalledApp()
        waitForCreatorRuntime(in: app)
        openProfile(in: app)
        attachScreenshot(named: "10-profile-manager-access-check", app: app)

        let managerAccess = app.buttons["Switch to manager control"]
        XCTAssertTrue(
            managerAccess.waitForExistence(timeout: 10),
            diagnostics("Installed session does not expose manager/admin access. Sign in with an owner/editor account before running manager handover proof.", app: app)
        )
    }

    @MainActor
    func testDebugFixtureManagerUsesDayOnlyNavigation() throws {
        let app = launchInstalledApp(environment: [
            "MCO_FORCE_FIXTURE_UI": "1",
            "MCO_FORCE_APP_MODE": "admin"
        ])

        XCTAssertTrue(
            app.tabBars.buttons["Daily"].waitForExistence(timeout: 20),
            diagnostics("Manager Daily tab is missing", app: app)
        )
        XCTAssertTrue(
            app.staticTexts["Daily Content"].waitForExistence(timeout: 10),
            diagnostics("Manager did not open on daily content generation", app: app)
        )
        XCTAssertTrue(
            app.tabBars.buttons["References"].exists,
            diagnostics("Manager References tab is missing", app: app)
        )
        XCTAssertFalse(
            app.tabBars.buttons["Weekly"].exists,
            diagnostics("Retired Weekly generation tab is still visible", app: app)
        )
    }

    @MainActor
    func testCreatorTodayAndShootFolioAreReachableInInstalledApp() throws {
        let app = launchInstalledApp()
        waitForCreatorRuntime(in: app)
        openTodayIfNeeded(in: app)
        attachScreenshot(named: "01-today", app: app)

        let openShootFolio = app.buttons["Open today's Shoot Folio"]
        XCTAssertTrue(openShootFolio.waitForExistence(timeout: 20), diagnostics("Today card is not available", app: app))
        openShootFolio.tap()

        XCTAssertTrue(app.staticTexts["Shoot Folio"].waitForExistence(timeout: 10), diagnostics("Shoot Folio did not open", app: app))
        attachScreenshot(named: "02-shoot-folio", app: app)

        let scriptTab = app.buttons["Script"]
        if scriptTab.waitForExistence(timeout: 3) {
            scriptTab.tap()
            XCTAssertTrue(app.staticTexts["Script"].waitForExistence(timeout: 5), diagnostics("Script package is missing", app: app))
            attachScreenshot(named: "03-script-copy-package", app: app)
        }

        let captionTab = app.buttons["Caption"]
        if captionTab.waitForExistence(timeout: 3) {
            captionTab.tap()
            XCTAssertTrue(app.staticTexts["Caption"].waitForExistence(timeout: 5), diagnostics("Caption package is missing", app: app))
            attachScreenshot(named: "04-caption-copy-package", app: app)
        }
    }

    @MainActor
    func testCreatorFallbackSheetCanOpenInInstalledApp() throws {
        let app = launchInstalledApp()
        waitForCreatorRuntime(in: app)
        openTodayIfNeeded(in: app)

        let fallbackButton = app.buttons["Give me other ideas"]
        XCTAssertTrue(fallbackButton.waitForExistence(timeout: 10), diagnostics("Fallback entry point is missing", app: app))
        fallbackButton.tap()

        XCTAssertTrue(app.staticTexts["Other ideas"].waitForExistence(timeout: 10), diagnostics("Fallback sheet did not open", app: app))
        XCTAssertTrue(app.buttons["10-second story"].exists || app.staticTexts["10-second story"].exists, diagnostics("Backup story option is missing", app: app))
        XCTAssertTrue(app.buttons["Caption-only post"].exists || app.staticTexts["Caption-only post"].exists, diagnostics("Caption-only option is missing", app: app))
        XCTAssertTrue(app.buttons["Save for tomorrow"].exists || app.staticTexts["Save for tomorrow"].exists, diagnostics("Save for tomorrow option is missing", app: app))
        attachScreenshot(named: "05-fallback-sheet", app: app)
    }

    @MainActor
    func testCreatorBackupDecisionAppearsInArchiveInInstalledApp() throws {
        let app = launchInstalledApp()
        waitForCreatorRuntime(in: app)
        openTodayIfNeeded(in: app)

        let fallbackButton = app.buttons["Give me other ideas"]
        XCTAssertTrue(fallbackButton.waitForExistence(timeout: 10), diagnostics("Fallback entry point is missing", app: app))
        fallbackButton.tap()

        XCTAssertTrue(app.staticTexts["Other ideas"].waitForExistence(timeout: 10), diagnostics("Fallback sheet did not open", app: app))

        let backupOption = app.buttons["10-second story"]
        if !backupOption.exists {
            let backupStatic = app.staticTexts["10-second story"]
            if backupStatic.exists {
                tapWhenHittableOrVisibleCenter(backupStatic, in: app, timeout: 3)
            }
        } else {
            tapWhenHittableOrVisibleCenter(backupOption, in: app, timeout: 3)
        }

        let detailTitle = app.staticTexts["10-second story"]
        XCTAssertTrue(
            detailTitle.waitForExistence(timeout: 10),
            diagnostics("Backup detail sheet did not open for 10-second story", app: app)
        )

        let useBackupButton = app.buttons["Use backup"]
        XCTAssertTrue(
            useBackupButton.waitForExistence(timeout: 5) || useBackupButton.exists,
            diagnostics("Backup detail missing 'Use backup' action button", app: app)
        )

        // App renders these section headers in uppercase
        XCTAssertTrue(
            app.staticTexts["BACKUP STORY"].waitForExistence(timeout: 5) ||
                app.staticTexts["BACKUP STORY"].exists,
            diagnostics("Backup detail missing 'BACKUP STORY' content label", app: app)
        )
        XCTAssertTrue(
            app.staticTexts["VISUAL DIRECTION"].waitForExistence(timeout: 5) ||
                app.staticTexts["VISUAL DIRECTION"].exists,
            diagnostics("Backup detail missing 'VISUAL DIRECTION' content label", app: app)
        )
        attachScreenshot(named: "06-backup-detail-sheet", app: app)

        XCTAssertTrue(
            useBackupButton.waitForExistence(timeout: 5),
            diagnostics("'Use backup' button did not become available", app: app)
        )
        useBackupButton.tap()

        // The detail sheet must dismiss after tapping Use backup.
        // If Cancel is still visible, the backup action did not complete.
        let cancelInSheet = app.buttons["Cancel"]
        XCTAssertFalse(
            cancelInSheet.waitForExistence(timeout: 5),
            diagnostics("Backup detail sheet did not dismiss after tapping 'Use backup'; Cancel is still visible", app: app)
        )
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        attachScreenshot(named: "07-after-tap-use-backup", app: app)

        openProfile(in: app)
        attachScreenshot(named: "07b-profile-after-backup", app: app)

        //    ArchiveSection is embedded inline in Profile; an explicit Archive button
        //    may not exist. Tap it if present, otherwise proceed to Backups directly.
        let archiveButton = app.buttons["Archive"]
        if archiveButton.waitForExistence(timeout: 10) {
            archiveButton.tap()
            _ = app.staticTexts["Archive"].waitForExistence(timeout: 10)
        }

        let backupsFilter = app.buttons["Backups"]
        XCTAssertTrue(backupsFilter.waitForExistence(timeout: 10), diagnostics("Backups filter not found", app: app))
        backupsFilter.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        let usedBackupLine = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Used backup")
        ).firstMatch
        XCTAssertTrue(
            usedBackupLine.waitForExistence(timeout: 10),
            diagnostics("Archive Backups does not show any 'Used backup' outcome", app: app)
        )
        attachScreenshot(named: "08-archive-backups-result", app: app)
    }

    // MARK: - App Launch

    @MainActor
    private func launchInstalledApp(environment: [String: String] = [:]) -> XCUIApplication {
        continueAfterFailure = false

        let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
        app.launchArguments.append("ui-proof-installed-testflight")
        for (key, value) in environment {
            app.launchEnvironment[key] = value
        }

        app.terminate()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            let allow = alert.buttons["Allow"]
            if allow.exists {
                allow.tap()
                return true
            }

            let ok = alert.buttons["OK"]
            if ok.exists {
                ok.tap()
                return true
            }

            return false
        }
        app.launch()
        return app
    }

    // MARK: - Navigation

    @MainActor
    private func waitForCreatorRuntime(in app: XCUIApplication) {
        let todayTitle = app.staticTexts["Today"]
        if todayTitle.waitForExistence(timeout: 30) {
            return
        }

        let signInField = app.textFields["sign-in-email"]
        if signInField.exists {
            XCTFail("Installed app is on the sign-in screen, not the creator runtime.")
            return
        }

        XCTFail(diagnostics("Creator Today did not load", app: app))
    }

    @MainActor
    private func openTodayIfNeeded(in app: XCUIApplication) {
        let todayTab = app.tabBars.buttons["Today"]
        if todayTab.exists && todayTab.isHittable {
            todayTab.tap()
        }
    }

    @MainActor
    private func openProfile(in app: XCUIApplication) {
        let profileTab = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 10), diagnostics("Profile tab is not available", app: app))
        profileTab.tap()
    }

    // MARK: - Interaction helpers

    /// Taps an element by identifier, scrolling to it if needed.
    @MainActor
    private func tapWhenHittableOrVisibleCenter(
        _ element: XCUIElement?,
        in app: XCUIApplication,
        timeout: TimeInterval = 5
    ) {
        guard let element else { return }
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists {
                let frame = element.frame
                let visibleBottom = app.frame.maxY - 110
                if frame.maxY > visibleBottom {
                    app.swipeUp()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                    continue
                }
                let coordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                    .withOffset(CGVector(dx: frame.midX, dy: min(frame.midY, visibleBottom - 24)))
                coordinate.tap()
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < deadline
    }

    // MARK: - Screenshot / Diagnostics

    @MainActor
    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func diagnostics(_ message: String, app: XCUIApplication) -> String {
        "\(message)\n\nVisible UI:\n\(app.debugDescription)"
    }
}
