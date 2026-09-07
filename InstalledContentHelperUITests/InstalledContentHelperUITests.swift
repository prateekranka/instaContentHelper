import XCTest

final class InstalledContentHelperUITests: XCTestCase {
    private let bundleIdentifier = "com.prateekranka.creatorcontenthelper"

    @MainActor
    func testCreatorTodayInlinePackageIsReachableInInstalledApp() throws {
        let app = launchInstalledApp()
        waitForCreatorRuntime(in: app)
        openTodayIfNeeded(in: app)
        attachScreenshot(named: "01-today", app: app)

        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 20), diagnostics("Today screen did not load", app: app))

        let hasInlinePackage = app.otherElements["today.package.content"].waitForExistence(timeout: 10)
            || app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Storyboard")).firstMatch.waitForExistence(timeout: 5)
            || app.buttons["Give me other ideas"].waitForExistence(timeout: 5)
            || app.buttons["Plan today’s content"].waitForExistence(timeout: 3)

        XCTAssertTrue(
            hasInlinePackage,
            diagnostics("Today did not show inline package, empty state, or fallback entry", app: app)
        )
        attachScreenshot(named: "02-today-inline-package", app: app)
    }

    @MainActor
    func testCreatorTodayAndShootFolioAreReachableInInstalledApp() throws {
        throw XCTSkip("Retired Folio-first Today path (ticket 09 slice 6); use testCreatorTodayInlinePackageIsReachableInInstalledApp.")
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
    func testDebugFixtureManagerCanReachAndPublishWeeklyButton() throws {
        // DEBUG-only Admin shell (`MCO_FORCE_APP_MODE=admin`). Not a product path after ticket 07.
        let app = launchInstalledApp(environment: [
            "MCO_FORCE_FIXTURE_UI": "1",
            "MCO_FORCE_APP_MODE": "admin"
        ])

        XCTAssertTrue(
            app.staticTexts["Generate a Week"].waitForExistence(timeout: 20) ||
                app.staticTexts["Manager Weekly Control"].waitForExistence(timeout: 20),
            diagnostics("Debug fixture manager Weekly screen did not open", app: app)
        )
        approveGeneratedWeekDays(in: app)

        let publishButton = waitForPublishButton(in: app, timeout: 20)
        XCTAssertNotNil(publishButton, diagnostics("Fixture Publish week button is not enabled after approval", app: app))
        app.swipeUp()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        tapWhenHittableOrVisibleCenter(publishButton, in: app, timeout: 3)

        XCTAssertTrue(
            app.buttons["Published"].waitForExistence(timeout: 20) ||
                app.staticTexts["Published"].waitForExistence(timeout: 20),
            diagnostics("Fixture manager publish did not complete after tapping Publish week", app: app)
        )
        attachScreenshot(named: "50-debug-fixture-weekly-published", app: app)
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

        openArchive(in: app)
        attachScreenshot(named: "07b-archive-after-backup", app: app)

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

        let signInButton = app.buttons["sign-in-with-apple"]
        if signInButton.exists {
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
    private func openYou(in app: XCUIApplication) {
        let youTab = app.tabBars.buttons["You"]
        XCTAssertTrue(youTab.waitForExistence(timeout: 10), diagnostics("You tab is not available", app: app))
        youTab.tap()
        XCTAssertTrue(
            app.staticTexts["You"].waitForExistence(timeout: 10),
            diagnostics("You screen did not open", app: app)
        )
    }

    @MainActor
    private func openArchive(in app: XCUIApplication) {
        openYou(in: app)
        let seeMore = app.buttons["you.archive.seeMore"]
        if seeMore.waitForExistence(timeout: 5) {
            seeMore.tap()
        } else {
            let archiveRow = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "See more")).firstMatch
            XCTAssertTrue(archiveRow.waitForExistence(timeout: 5), diagnostics("Archive entry is not available under You", app: app))
            archiveRow.tap()
        }
        XCTAssertTrue(
            app.staticTexts["Archive"].waitForExistence(timeout: 10),
            diagnostics("Archive screen did not open", app: app)
        )
    }

    // MARK: - Identifier-based helpers

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

    /// Scrolls down until an element with the given identifier becomes visible.
    @MainActor
    private func scrollToElement(
        identifier: String,
        in app: XCUIApplication,
        maxSwipes: Int = 8
    ) -> XCUIElement? {
        for _ in 0..<maxSwipes {
            let element = app.buttons[identifier]
            if element.exists && element.isHittable {
                return element
            }
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return app.buttons[identifier].exists ? app.buttons[identifier] : nil
    }

    // MARK: - Weekly approval flow (identifier-primary, label-fallback)

    private struct WeeklyApprovalTarget {
        let code: String
        let name: String
    }

    @MainActor
    private func approveGeneratedWeekDays(in app: XCUIApplication) {
        ensureWeeklyRowsAreVisible(in: app)

        let weekdays = [
            WeeklyApprovalTarget(code: "MON", name: "Monday"),
            WeeklyApprovalTarget(code: "TUE", name: "Tuesday"),
            WeeklyApprovalTarget(code: "WED", name: "Wednesday"),
            WeeklyApprovalTarget(code: "THU", name: "Thursday"),
            WeeklyApprovalTarget(code: "FRI", name: "Friday"),
            WeeklyApprovalTarget(code: "SAT", name: "Saturday"),
            WeeklyApprovalTarget(code: "SUN", name: "Sunday")
        ]
        for weekday in weekdays {
            XCTAssertTrue(openWeeklyDay(weekday, in: app), diagnostics("Could not open \(weekday.name) weekly day for approval", app: app))

            let readyButton = waitForReadyButton(for: weekday, in: app, timeout: 10)
            XCTAssertNotNil(readyButton, diagnostics("Ready approval action is missing for \(weekday.name)", app: app))
            XCTAssertTrue(readyButton?.isEnabled ?? false, diagnostics("Ready approval action is disabled for \(weekday.name)", app: app))
            readyButton?.tap()

            XCTAssertTrue(waitForWeeklyDayReady(weekday, in: app, timeout: 15), diagnostics("\(weekday.name) did not show Ready after approval", app: app))
        }
    }

    @MainActor
    private func openWeeklyDay(_ weekday: WeeklyApprovalTarget, in app: XCUIApplication) -> Bool {
        // Primary: use stable accessibility identifier
        if let dayButton = scrollToElement(identifier: "weekly.day.\(weekday.code)", in: app, maxSwipes: 8) {
            dayButton.tap()
            if app.staticTexts["Confirm status"].waitForExistence(timeout: 5) {
                return true
            }
        }

        // Fallback: dynamic label predicate (TestFlight builds without identifier)
        for _ in 0..<8 {
            let dayButton = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", weekday.code, "Open planned content")
            ).firstMatch
            if dayButton.exists && dayButton.isHittable {
                dayButton.tap()
                return app.staticTexts["Confirm status"].waitForExistence(timeout: 5)
            }
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return false
    }

    @MainActor
    private func waitForReadyButton(
        for weekday: WeeklyApprovalTarget,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> XCUIElement? {
        // Primary: use identifier
        let readyIdentifier = "weekly.day.\(weekday.code).ready"
        let readyById = app.buttons[readyIdentifier]
        if readyById.waitForExistence(timeout: timeout) {
            return readyById
        }

        // Fallback: label "Ready"
        let readyByLabel = app.buttons["Ready"]
        if readyByLabel.waitForExistence(timeout: timeout) {
            return readyByLabel
        }
        return nil
    }

    @MainActor
    private func waitForWeeklyDayReady(
        _ weekday: WeeklyApprovalTarget,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let statusIdentifier = "weekly.day.\(weekday.code).status.ready"
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            // Primary: check for dedicated status identifier element
            let statusElement = app.descendants(matching: .any)[statusIdentifier]
            if statusElement.exists {
                return true
            }

            // Secondary: check if the day row button's label contains "Ready"
            let dayButton = app.descendants(matching: .any)["weekly.day.\(weekday.code)"]
            if dayButton.exists && dayButton.label.contains("Ready") {
                return true
            }

            // Fallback: predicate-based ready row detection
            let readyDay = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", weekday.code, "Ready")
            ).firstMatch
            if readyDay.exists {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < deadline
        return false
    }

    // MARK: - Weekly row visibility (identifier-primary)

    @MainActor
    private func isWeeklyRowVisible(in app: XCUIApplication) -> Bool {
        // Primary: identifier
        if app.buttons["weekly.day.MON"].exists {
            return true
        }
        // Fallback: predicate
        return app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "MON", "Open planned content")
        ).firstMatch.exists
    }

    @MainActor
    private func areWeeklyRowsInteractable(in app: XCUIApplication) -> Bool {
        // Primary: identifier
        let row = app.buttons["weekly.day.MON"]
        if row.exists && row.isHittable {
            return true
        }
        // Fallback: predicate
        let fallbackRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "MON", "Open planned content")
        ).firstMatch
        return fallbackRow.exists && fallbackRow.isHittable
    }

    @MainActor
    private func waitForWeeklyRowsToBeInteractable(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if areWeeklyRowsInteractable(in: app) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < deadline
        return false
    }

    @MainActor
    private func ensureWeeklyRowsAreVisible(in app: XCUIApplication) {
        dismissPresentedSurfaceIfNeeded(in: app)
        if areWeeklyRowsInteractable(in: app) {
            return
        }

        let weeklyTab = app.tabBars.buttons["Weekly"]
        if weeklyTab.waitForExistence(timeout: 3) {
            weeklyTab.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }
    }

    // MARK: - Review / Publish button (identifier-primary)

    @MainActor
    private func waitForPublishButton(in app: XCUIApplication, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            // Primary: identifier
            let publishById = app.buttons["weekly.publish"]
            if publishById.exists && publishById.isEnabled {
                return publishById
            }
            // Fallback: label "Publish week"
            let publishByLabel = app.buttons["Publish week"]
            if publishByLabel.exists && publishByLabel.isEnabled {
                return publishByLabel
            }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        } while Date() < deadline
        return nil
    }

    // MARK: - Surface dismissal (identifier-primary)

    @MainActor
    private func dismissPresentedSurfaceIfNeeded(in app: XCUIApplication) {
        // Primary: identifier-based dismissal (Done in generated review = weekly.generatedReview.done)
        let doneById = app.buttons["weekly.generatedReview.done"]
        if doneById.exists {
            if doneById.isHittable {
                doneById.tap()
            }
            // Even if we couldn't tap, treat as dismissed for Save edits case
            if waitForWeeklyRowsToBeInteractable(in: app, timeout: 15) {
                return
            }
        }

        // Fallback: label-based dismissal
        if tapFirstExistingButton(in: app, labels: ["Done", "Save edits", "Close", "Cancel"]) {
            if waitForWeeklyRowsToBeInteractable(in: app, timeout: 15) {
                return
            }
        }

        // Swipe down to dismiss sheets
        for _ in 0..<4 {
            if areWeeklyRowsInteractable(in: app) {
                return
            }

            app.swipeDown()
            if waitForWeeklyRowsToBeInteractable(in: app, timeout: 3) {
                return
            }
        }
    }

    @MainActor
    private func tapFirstExistingButton(in app: XCUIApplication, labels: [String]) -> Bool {
        for label in labels {
            let button = app.buttons[label]
            if button.exists {
                if button.isHittable {
                    button.tap()
                } else if label == "Save edits" {
                    // The editor surface dismissed but the button reference
            // still resolves - treat as a clean dismissal.
                    return true
                } else {
                    tapWhenHittableOrVisibleCenter(button, in: app, timeout: 3)
                }
                return true
            }
        }
        return false
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
