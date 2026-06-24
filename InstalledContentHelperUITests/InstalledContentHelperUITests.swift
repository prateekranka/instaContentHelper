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
    func testInstalledManagerGenerateReviewPublishAndCreatorToday() throws {
        let startedAt = Date()
        let app = launchInstalledApp()
        waitForCreatorRuntime(in: app)
        openProfile(in: app)

        let managerAccess = app.buttons["Switch to manager control"]
        XCTAssertTrue(managerAccess.waitForExistence(timeout: 15), diagnostics("Manager access is not available for the installed session", app: app))
        managerAccess.tap()

        XCTAssertTrue(
            app.staticTexts["Manager Weekly Control"].waitForExistence(timeout: 30) || app.tabBars.buttons["Weekly"].waitForExistence(timeout: 5),
            diagnostics("Manager Weekly screen did not open", app: app)
        )
        let weeklyTab = app.tabBars.buttons["Weekly"]
        if weeklyTab.exists && weeklyTab.isHittable {
            weeklyTab.tap()
        }
        attachScreenshot(named: "20-manager-weekly-before-generation", app: app)

        let generateButton = firstExistingButton(
            in: app,
            labels: ["Generate", "Regenerate", "Generate draft week again", "Regenerate draft week"],
            timeout: 15
        )
        XCTAssertNotNil(generateButton, diagnostics("No Generate or Regenerate action is available on manager Weekly", app: app))
        generateButton?.tap()

        XCTAssertTrue(app.staticTexts["Generation Status"].waitForExistence(timeout: 30), diagnostics("Generation status panel did not appear", app: app))
        XCTAssertTrue(app.staticTexts["Day progress"].waitForExistence(timeout: 90), diagnostics("Live day progress did not appear", app: app))
        attachScreenshot(named: "21-manager-day-progress-started", app: app)

        if let retryButton = waitForFirstButtonMatchingPrefix(in: app, prefix: "Retry ", timeout: 10) {
            retryButton.tap()
            attachScreenshot(named: "22-manager-retry-day-tapped", app: app)
        } else {
            attachScreenshot(named: "22-manager-retry-day-not-available", app: app)
        }

        let reviewButton = waitForFirstExistingButton(
            in: app,
            labels: ["Review generated day cards", "Review"],
            timeout: 900
        )
        XCTAssertNotNil(reviewButton, diagnostics("Generated week did not become reviewable before timeout", app: app))
        let elapsed = Date().timeIntervalSince(startedAt)
        print("MANAGER_GENERATION_REVIEW_READY_SECONDS=\(String(format: "%.1f", elapsed))")
        attachScreenshot(named: "23-manager-generation-ready-for-review", app: app)

        reviewButton?.tap()
        XCTAssertTrue(
            app.staticTexts["Generated Week"].waitForExistence(timeout: 15) ||
                app.staticTexts["Review"].waitForExistence(timeout: 15) ||
                app.staticTexts["Draft week generated"].waitForExistence(timeout: 15),
            diagnostics("Generated review surface did not open", app: app)
        )
        attachScreenshot(named: "24-manager-review-surface", app: app)
        dismissPresentedSurfaceIfNeeded(in: app)

        let publishButton = waitForFirstExistingButton(in: app, labels: ["Publish week"], timeout: 30)
        XCTAssertNotNil(publishButton, diagnostics("Publish week is not available after review", app: app))
        publishButton?.tap()

        XCTAssertTrue(
            app.buttons["Published"].waitForExistence(timeout: 120) ||
                app.staticTexts["Published"].waitForExistence(timeout: 120) ||
                app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Published")).firstMatch.waitForExistence(timeout: 5),
            diagnostics("Week did not publish successfully", app: app)
        )
        attachScreenshot(named: "25-manager-week-published", app: app)

        let backToCreator = app.buttons["Back to Creator Mode"]
        if backToCreator.waitForExistence(timeout: 10) {
            backToCreator.tap()
        } else if let creatorMode = firstExistingButton(in: app, labels: ["Go back to Creator Mode"], timeout: 3) {
            creatorMode.tap()
        }
        openTodayIfNeeded(in: app)
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 30), diagnostics("Creator Today did not open after publishing", app: app))
        XCTAssertTrue(app.buttons["Open today's Shoot Folio"].waitForExistence(timeout: 30), diagnostics("Creator Today did not show a published card after manager publish", app: app))
        attachScreenshot(named: "26-creator-today-after-manager-publish", app: app)
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
    private func launchInstalledApp() -> XCUIApplication {
        continueAfterFailure = false

        let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
        app.launchArguments.append("ui-proof-installed-testflight")

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

    @MainActor
    private func firstExistingButton(
        in app: XCUIApplication,
        labels: [String],
        timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for label in labels {
                let button = app.buttons[label]
                if button.exists && button.isHittable {
                    return button
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < deadline
        return nil
    }

    @MainActor
    private func waitForFirstExistingButton(
        in app: XCUIApplication,
        labels: [String],
        timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for label in labels {
                let button = app.buttons[label]
                if button.exists {
                    return button
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        } while Date() < deadline
        return nil
    }

    @MainActor
    private func waitForFirstButtonMatchingPrefix(
        in app: XCUIApplication,
        prefix: String,
        timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let buttons = app.buttons.allElementsBoundByIndex
            if let match = buttons.first(where: { $0.label.hasPrefix(prefix) && $0.exists }) {
                return match
            }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        } while Date() < deadline
        return nil
    }

    @MainActor
    private func dismissPresentedSurfaceIfNeeded(in app: XCUIApplication) {
        let done = app.buttons["Done"]
        if done.waitForExistence(timeout: 3) {
            done.tap()
            return
        }

        let close = app.buttons["Close"]
        if close.waitForExistence(timeout: 3) {
            close.tap()
            return
        }

        let cancel = app.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 3) {
            cancel.tap()
        }
    }

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
