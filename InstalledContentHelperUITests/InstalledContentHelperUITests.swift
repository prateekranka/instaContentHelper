import XCTest

final class InstalledContentHelperUITests: XCTestCase {
    private let bundleIdentifier = "com.prateekranka.creatorcontenthelper"
    private let generationActionLabels = ["Generate", "Regenerate", "Generate draft week again", "Regenerate draft week"]

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

        let reviewButton = waitForReviewButton(in: app, timeout: 900)
        XCTAssertNotNil(reviewButton, diagnostics("Generated week did not become reviewable before timeout", app: app))
        let elapsed = Date().timeIntervalSince(startedAt)
        print("MANAGER_GENERATION_REVIEW_READY_SECONDS=\(String(format: "%.1f", elapsed))")
        attachScreenshot(named: "23-manager-generation-ready-for-review", app: app)

        reviewButton?.tap()
        XCTAssertTrue(
            app.staticTexts["Generated Week"].waitForExistence(timeout: 15) ||
                app.staticTexts["Review"].waitForExistence(timeout: 15) ||
                app.staticTexts["Draft ready for review"].waitForExistence(timeout: 15),
            diagnostics("Generated review surface did not open", app: app)
        )
        attachScreenshot(named: "24-manager-review-surface", app: app)
        dismissPresentedSurfaceIfNeeded(in: app)

        approveGeneratedWeekDays(in: app)
        attachScreenshot(named: "25-manager-week-approved-for-publish", app: app)

        let publishButton = waitForPublishButton(in: app, timeout: 60)
        XCTAssertNotNil(publishButton, diagnostics("Publish week is not enabled after reviewing and approving all seven days", app: app))
        tapWhenHittableOrVisibleCenter(publishButton, in: app, timeout: 5)

        XCTAssertTrue(
            app.buttons["Published"].waitForExistence(timeout: 120) ||
                app.staticTexts["Published"].waitForExistence(timeout: 120) ||
                app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Published")).firstMatch.waitForExistence(timeout: 5),
            diagnostics("Week did not publish successfully", app: app)
        )
        attachScreenshot(named: "26-manager-week-published", app: app)

        let backToCreator = app.buttons["Back to Creator Mode"]
        if backToCreator.waitForExistence(timeout: 10) {
            backToCreator.tap()
        } else if let creatorMode = firstExistingButton(in: app, labels: ["Go back to Creator Mode"], timeout: 3) {
            creatorMode.tap()
        }
        openTodayIfNeeded(in: app)
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 30), diagnostics("Creator Today did not open after publishing", app: app))
        XCTAssertTrue(app.buttons["Open today's Shoot Folio"].waitForExistence(timeout: 30), diagnostics("Creator Today did not show a published card after manager publish", app: app))
        attachScreenshot(named: "27-creator-today-after-manager-publish", app: app)
    }

    @MainActor
    func testInstalledManagerGenerateReviewSurfaceWithoutPublishing() throws {
        // Guard: this proof must never run with fixture or mock environment.
        // These checks read the XCTest process environment only - they do not
        // pass any secrets into the app under test.
        let blockedEnvVars = ["MCO_FORCE_FIXTURE_UI", "MCO_QA_GENERATE_MOCK", "MCO_AI_MOCK"]
        for key in blockedEnvVars {
            if ProcessInfo.processInfo.environment[key] != nil {
                XCTFail("MANAGER_GENERATION_PROOF_BLOCKED: \(key) is set in the XCTest process environment. This proof requires live backend generation and must not run under fixture or mock flags.")
                return
            }
        }

        let startedAt = Date()
        let app = launchInstalledApp()
        waitForCreatorRuntime(in: app)
        openProfile(in: app)
        openManagerWeekly(in: app)

        // Wait for live weekly data to finish loading before looking for Generate.
        // This avoids the known failure where the test proceeds while "Loading week"
        // is still visible and no Generate / Regenerate button exists.
        let dataLoaded = waitForWeeklyDataToLoad(in: app, timeout: 45)
        print("MANAGER_GENERATION_PROOF_WEEKLY_DATA_LOADED=\(dataLoaded)")
        if !dataLoaded {
            maybeRefreshWeekly(in: app)
            XCTAssertTrue(
                waitForWeeklyDataToLoad(in: app, timeout: 60),
                diagnostics("Manager Weekly data did not finish loading", app: app)
            )
        }
        selectCurrentWeekStart(in: app)
        attachScreenshot(named: "59-manager-week-start-selected", app: app)
        if waitForReviewButton(in: app, timeout: 3) == nil,
           firstExistingButton(in: app, labels: generationActionLabels, timeout: 3) == nil {
            ensureWeeklyBriefAllowsGeneration(in: app)
        }
        attachScreenshot(named: "60-manager-weekly-before-generation", app: app)

        let generateButton = firstExistingButton(in: app, labels: generationActionLabels, timeout: 30)
        XCTAssertNotNil(
            generateButton,
            diagnostics("No Generate or Regenerate action is available on manager Weekly. A fresh generation is required for this proof - pre-existing drafts must not satisfy it.", app: app)
        )
        let generationActionLabel = generateButton?.label ?? "Generate"
        tapWhenHittableOrVisibleCenter(generateButton, in: app, timeout: 5)
        print("MANAGER_GENERATION_PROOF_FRESH_DRAFT: tapped \(generationActionLabel), starting fresh generation")

        XCTAssertTrue(
            app.staticTexts["Generation Status"].waitForExistence(timeout: 30),
            diagnostics("Generation status panel did not appear", app: app)
        )
        XCTAssertTrue(
            app.staticTexts["Day progress"].waitForExistence(timeout: 90),
            diagnostics("Live day progress did not appear", app: app)
        )
        attachScreenshot(named: "61-manager-day-progress-started", app: app)

        var reviewButton = waitForReviewButton(in: app, timeout: 900)
        if reviewButton == nil {
            reviewButton = retryVisibleFailedDayAndWaitForReview(in: app)
        }
        XCTAssertNotNil(reviewButton, diagnostics("Generated week did not become reviewable before timeout or failed-day retry", app: app))
        let elapsed = Date().timeIntervalSince(startedAt)
        print("MANAGER_GENERATION_REVIEW_READY_SECONDS=\(String(format: "%.1f", elapsed))")
        attachScreenshot(named: "62-manager-generation-ready-for-review", app: app)

        reviewButton?.tap()
        XCTAssertTrue(
            app.staticTexts["Generated week"].waitForExistence(timeout: 15) ||
                app.staticTexts["Generated Week"].waitForExistence(timeout: 15) ||
                app.staticTexts["Review"].waitForExistence(timeout: 15) ||
                app.staticTexts["Draft ready for review"].waitForExistence(timeout: 15),
            diagnostics("Generated review surface did not open", app: app)
        )
        attachScreenshot(named: "63-manager-review-surface", app: app)

        print("MANAGER_GENERATION_REVIEW_TEXT_BEGIN")
        printReviewSurfaceContent(in: app)
        print("MANAGER_GENERATION_REVIEW_TEXT_END")

        let publishDraftButton = app.buttons["weekly.generatedReview.publishDraft"]
        let publishWeekButton = app.buttons["Publish week"]
        if publishDraftButton.exists || publishWeekButton.exists {
            print("MANAGER_GENERATION_PROOF_PUBLISH_PRESENT: Publish draft is available (publishing intentionally skipped - proof test only)")
        }

        dismissPresentedSurfaceIfNeeded(in: app)
        attachScreenshot(named: "64-manager-review-dismissed", app: app)
    }

    @MainActor
    func testInstalledManagerRetriesFailedDay() throws {
        let app = launchInstalledApp()
        waitForCreatorRuntime(in: app)
        openProfile(in: app)
        openManagerWeekly(in: app)

        XCTAssertTrue(
            app.staticTexts["Generation Status"].waitForExistence(timeout: 30) ||
                app.buttons["weekly.reviewGenerated"].waitForExistence(timeout: 5),
            diagnostics("Generation or generated draft panel did not appear", app: app)
        )
        attachScreenshot(named: "30-manager-day-progress-before-retry", app: app)

        let reviewButton = retryVisibleFailedDayAndWaitForReview(in: app)
        XCTAssertNotNil(reviewButton, diagnostics("Retried failed day did not make the generated week reviewable", app: app))
        attachScreenshot(named: "32-manager-day-retry-review-ready", app: app)
    }

    @MainActor
    func testInstalledManagerPublishesExistingGeneratedWeekAndCreatorToday() throws {
        let app = launchInstalledApp()
        waitForCreatorRuntime(in: app)
        openProfile(in: app)
        openManagerWeekly(in: app)
        attachScreenshot(named: "40-manager-existing-generated-week", app: app)

        let reviewButton = waitForReviewButton(in: app, timeout: 60)
        XCTAssertNotNil(reviewButton, diagnostics("No review action is available for the existing generated week", app: app))
        reviewButton?.tap()
        XCTAssertTrue(
            app.staticTexts["Generated Week"].waitForExistence(timeout: 15) ||
                app.staticTexts["Review"].waitForExistence(timeout: 15) ||
                app.staticTexts["Draft ready for review"].waitForExistence(timeout: 15),
            diagnostics("Generated review surface did not open", app: app)
        )
        attachScreenshot(named: "41-manager-existing-review-surface", app: app)
        dismissPresentedSurfaceIfNeeded(in: app)

        approveGeneratedWeekDays(in: app)
        attachScreenshot(named: "42-manager-existing-week-approved", app: app)

        let publishButton = waitForPublishButton(in: app, timeout: 60)
        XCTAssertNotNil(publishButton, diagnostics("Publish week is not enabled for existing generated week after approval", app: app))
        tapWhenHittableOrVisibleCenter(publishButton, in: app, timeout: 5)

        XCTAssertTrue(
            app.buttons["Published"].waitForExistence(timeout: 120) ||
                app.staticTexts["Published"].waitForExistence(timeout: 120) ||
                app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Published")).firstMatch.waitForExistence(timeout: 5),
            diagnostics("Existing generated week did not publish successfully", app: app)
        )
        attachScreenshot(named: "43-manager-existing-week-published", app: app)

        let backToCreator = app.buttons["Back to Creator Mode"]
        if backToCreator.waitForExistence(timeout: 10) {
            backToCreator.tap()
        } else if let creatorMode = firstExistingButton(in: app, labels: ["Go back to Creator Mode"], timeout: 3) {
            creatorMode.tap()
        }
        openTodayIfNeeded(in: app)
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 30), diagnostics("Creator Today did not open after publishing existing generated week", app: app))
        XCTAssertTrue(app.buttons["Open today's Shoot Folio"].waitForExistence(timeout: 30), diagnostics("Creator Today did not show a published card after existing generated week publish", app: app))
        attachScreenshot(named: "44-creator-today-after-existing-week-publish", app: app)
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
    func testDebugFixtureManagerCanReachAndPublishWeeklyButton() throws {
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

    @MainActor
    func testManagerWeekStartMenuExcludesPastDates() throws {
        let app = launchInstalledApp()
        waitForCreatorRuntime(in: app)
        openProfile(in: app)
        openManagerWeekly(in: app)

        let dataLoaded = waitForWeeklyDataToLoad(in: app, timeout: 45)
        print("WEEK_START_MENU_PROOF_WEEKLY_DATA_LOADED=\(dataLoaded)")
        if !dataLoaded {
            maybeRefreshWeekly(in: app)
            XCTAssertTrue(
                waitForWeeklyDataToLoad(in: app, timeout: 60),
                diagnostics("Manager Weekly data did not finish loading", app: app)
            )
        }
        attachScreenshot(named: "70-week-start-menu-before", app: app)

        let weekStartSelector = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Week starts ")
        ).firstMatch
        XCTAssertTrue(
            weekStartSelector.waitForExistence(timeout: 10),
            diagnostics("Week-start selector ('Week starts …') is not visible on manager Weekly", app: app)
        )
        let menuTrigger = weekStartSelector.buttons.firstMatch
        XCTAssertTrue(
            menuTrigger.exists,
            diagnostics("Week-start selector does not expose its nested date menu button", app: app)
        )
        menuTrigger.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "dd MMM"
        let todayLabel = fmt.string(from: Date())
        let yesterdayLabel = fmt.string(
            from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        )

        // Menu options use identifier "calendar"; the selector trigger can reuse
        // the same date label for the currently selected week.
        let todayPred = NSPredicate(
            format: "label == %@ AND identifier == %@ AND NOT label BEGINSWITH %@",
            todayLabel, "calendar", "Week starts "
        )
        let yesterdayPred = NSPredicate(
            format: "label == %@ AND identifier == %@ AND NOT label BEGINSWITH %@",
            yesterdayLabel, "calendar", "Week starts "
        )

        let todayOption = app.buttons.matching(todayPred).firstMatch
        let yesterdayOption = app.buttons.matching(yesterdayPred).firstMatch

        XCTAssertTrue(
            todayOption.waitForExistence(timeout: 5),
            diagnostics("Week-start menu should include today (\(todayLabel))", app: app)
        )
        XCTAssertFalse(
            yesterdayOption.exists,
            diagnostics("Week-start menu should exclude yesterday (\(yesterdayLabel))", app: app)
        )

        attachScreenshot(named: "71-week-start-menu-open", app: app)

        // Dismiss without selecting a date — tap near the top of the screen
        // to close the popup menu.
        let topCoord = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        topCoord.tap()
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

    @MainActor
    private func openManagerWeekly(in app: XCUIApplication) {
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
    }

    // MARK: - Legacy label helpers (unchanged for TestFlight compatibility)

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
    private func scrollToFirstButtonMatchingPrefix(
        in app: XCUIApplication,
        prefix: String,
        maxSwipes: Int = 8
    ) -> XCUIElement? {
        for _ in 0..<maxSwipes {
            if let match = app.buttons.allElementsBoundByIndex.first(where: { $0.exists && $0.label.hasPrefix(prefix) }) {
                return match
            }
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }

        for _ in 0..<maxSwipes {
            if let match = app.buttons.allElementsBoundByIndex.first(where: { $0.exists && $0.label.hasPrefix(prefix) }) {
                return match
            }
            app.swipeDown()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }

        return nil
    }

    // MARK: - Identifier-based helpers

    /// Waits for an element with the given accessibility identifier to exist.
    @MainActor
    private func waitForElement(
        identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 10
    ) -> XCUIElement? {
        let element = app.buttons[identifier]
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists {
                return element
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < deadline
        return nil
    }

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
    private func waitForReviewButton(in app: XCUIApplication, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            // Primary: identifier (full-week review)
            let reviewById = app.buttons["weekly.reviewGenerated"]
            if reviewById.exists {
                return reviewById
            }
            // Fallback: label-based lookup for full-week review
            for label in ["Review generated day cards", "Review"] {
                let button = app.buttons[label]
                if button.exists {
                    return button
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        } while Date() < deadline

        // On timeout: print visible generation-status labels/buttons for diagnostics
        print("MANAGER_GENERATION_PROOF_TIMEOUT: No review button found after \(timeout)s")
        for button in app.buttons.allElementsBoundByIndex where button.exists {
            if button.label.contains("Review") || button.label.contains("generated") || button.label.contains("Generation") {
                print("MANAGER_GENERATION_PROOF_VISIBLE_BUTTON=\(button.label)")
            }
        }
        for text in app.staticTexts.allElementsBoundByIndex where text.exists {
            if text.label.contains("generation") || text.label.contains("Generation") || text.label.contains("Status") {
                print("MANAGER_GENERATION_PROOF_VISIBLE_LABEL=\(text.label)")
            }
        }
        return nil
    }

    @MainActor
    private func retryVisibleFailedDayAndWaitForReview(in app: XCUIApplication) -> XCUIElement? {
        guard let retryButton = waitForFirstButtonMatchingPrefix(in: app, prefix: "Retry ", timeout: 30) ??
            scrollToFirstButtonMatchingPrefix(in: app, prefix: "Retry ", maxSwipes: 8) else {
            print("MANAGER_GENERATION_PROOF_RETRY_AVAILABLE=false")
            return nil
        }

        let retryLabel = retryButton.label
        let shortDay = retryLabel
            .replacingOccurrences(of: "Retry ", with: "")
            .replacingOccurrences(of: " generation", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        print("MANAGER_GENERATION_PROOF_RETRY_AVAILABLE=true")
        print("MANAGER_GENERATION_PROOF_RETRY_LABEL=\(retryLabel)")
        print("MANAGER_GENERATION_PROOF_RETRY_SHORT_DAY=\(shortDay)")

        guard !shortDay.isEmpty else {
            XCTFail("Could not derive the failed weekday from '\(retryLabel)'")
            return nil
        }

        tapWhenHittableOrVisibleCenter(retryButton, in: app, timeout: 5)
        attachScreenshot(named: "62b-manager-retry-day-tapped", app: app)

        let generatedLabel = "\(shortDay): Generated"
        let retryingLabel = "\(shortDay): Retrying"
        let retryingOrGenerated = waitForAnyStaticText(
            in: app,
            labels: [retryingLabel, generatedLabel],
            timeout: 10
        )
        print("MANAGER_GENERATION_PROOF_DAY_RETRYING_OR_GENERATED=\(retryingOrGenerated ?? "none")")
        XCTAssertNotNil(
            retryingOrGenerated,
            diagnostics("Retried day '\(shortDay)' did not show '\(retryingLabel)' or '\(generatedLabel)' within 10s", app: app)
        )
        attachScreenshot(named: "62bb-manager-retry-day-retrying", app: app)

        let dayGenerated = app.staticTexts[generatedLabel].waitForExistence(timeout: 600)
        print("MANAGER_GENERATION_PROOF_DAY_GENERATED=\(dayGenerated)")
        XCTAssertTrue(dayGenerated, diagnostics("Retried day '\(shortDay)' did not show '\(generatedLabel)' within 600s", app: app))
        attachScreenshot(named: "62c-manager-retry-day-generated", app: app)

        let reviewButton = waitForReviewButton(in: app, timeout: 900)
        print("MANAGER_GENERATION_PROOF_REVIEW_AFTER_RETRY=\(reviewButton != nil)")
        return reviewButton
    }

    @MainActor
    private func waitForAnyStaticText(
        in app: XCUIApplication,
        labels: [String],
        timeout: TimeInterval
    ) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for label in labels where app.staticTexts[label].exists {
                return label
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < deadline
        return nil
    }

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

    // MARK: - Generation proof helpers

    /// Waits for the manager Weekly screen to finish loading live data.
    /// Returns true when "Loading week" is gone and actionable UI is present,
    /// or when weekly day rows / generate / review controls are visible.
    @MainActor
    private func waitForWeeklyDataToLoad(in app: XCUIApplication, timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let loadingLabel = app.staticTexts["Loading week"]
            if !loadingLabel.exists {
                if app.buttons["Generate"].exists || app.buttons["Regenerate"].exists ||
                    app.buttons["weekly.reviewGenerated"].exists || app.buttons["Review"].exists ||
                    app.buttons["weekly.day.MON"].exists {
                    return true
                }
                let monFallback = app.buttons.matching(
                    NSPredicate(format: "label BEGINSWITH %@", "MON")
                ).firstMatch
                if monFallback.exists {
                    return true
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        } while Date() < deadline

        if app.staticTexts["Loading week"].exists {
            print("MANAGER_GENERATION_PROOF_WARNING: Loading week still visible after \(timeout)s")
        }
        return false
    }

    /// Opens the Weekly options menu and taps Refresh, then waits briefly.
    @MainActor
    private func maybeRefreshWeekly(in app: XCUIApplication) {
        let optionsButton = app.buttons["Weekly options"]
        guard optionsButton.exists, optionsButton.isHittable else { return }
        optionsButton.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        let refreshButton = app.buttons["Refresh"]
        if refreshButton.exists, refreshButton.isHittable {
            refreshButton.tap()
            print("MANAGER_GENERATION_PROOF_INFO: Tapped Refresh in Weekly options menu")
            RunLoop.current.run(until: Date().addingTimeInterval(2))
        }
    }

    /// Reuses the nested week-start Menu targeting from testManagerWeekStartMenuExcludesPastDates.
    /// Opens the week-start popup, selects today's date, and waits for weekly data to reload.
    @MainActor
    private func selectCurrentWeekStart(in app: XCUIApplication) {
        let weekStartSelector = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Week starts ")
        ).firstMatch
        guard weekStartSelector.waitForExistence(timeout: 10) else {
            XCTFail(diagnostics("Week-start selector is required before live generation", app: app))
            return
        }
        let menuTrigger = weekStartSelector.buttons.firstMatch
        guard menuTrigger.exists else {
            XCTFail(diagnostics("Week-start selector does not expose its date menu button", app: app))
            return
        }
        menuTrigger.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "dd MMM"
        let todayLabel = fmt.string(from: Date())

        let todayPred = NSPredicate(
            format: "label == %@ AND NOT label BEGINSWITH %@",
            todayLabel, "Week starts "
        )
        let todayOption = app.buttons.matching(todayPred).firstMatch
        guard todayOption.waitForExistence(timeout: 5) else {
            XCTFail(diagnostics("Today (\(todayLabel)) is missing from the week-start menu", app: app))
            return
        }
        todayOption.tap()
        print("MANAGER_GENERATION_PROOF_INFO: Selected today's week (\(todayLabel)) as generation week start")
        XCTAssertTrue(
            waitForWeeklyDataToLoad(in: app, timeout: 30),
            diagnostics("Weekly data did not reload after selecting today", app: app)
        )
    }

    @MainActor
    private func ensureWeeklyBriefAllowsGeneration(in app: XCUIApplication) {
        print("MANAGER_GENERATION_PROOF_INFO: Generate unavailable; setting a short weekly brief for proof run")
        let openBrief = app.buttons["Open Weekly Brief editor"]
        if openBrief.exists {
            tapWhenHittableOrVisibleCenter(openBrief, in: app, timeout: 5)
        }

        let textView = app.textViews.firstMatch
        if textView.waitForExistence(timeout: 10) {
            tapWhenHittableOrVisibleCenter(textView, in: app, timeout: 5)
            textView.typeText(
                "Weekly routine: proof run for creator generation. Focus on real training, food, recovery, family life, and warm witty voice."
            )
        } else {
            for label in ["Weekly routine", "Coming up", "Family"] {
                let suggestion = app.buttons[label]
                if suggestion.exists && suggestion.isHittable {
                    suggestion.tap()
                }
            }
        }

        dismissKeyboardIfPresent(in: app)
        let generationAction = saveWeeklyBriefAndWaitForGenerationAction(in: app, below: textView)
        XCTAssertNotNil(
            generationAction,
            diagnostics("Generate did not become available after saving a weekly brief", app: app)
        )
    }

    @MainActor
    private func dismissKeyboardIfPresent(in app: XCUIApplication) {
        for label in ["Done", "Return"] {
            let button = app.buttons[label]
            if button.exists && button.isHittable {
                button.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                return
            }
        }
    }

    @MainActor
    private func tapWeeklyBriefSave(in app: XCUIApplication, below textView: XCUIElement) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        repeat {
            let saveButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Save"))
            for index in 0..<saveButtons.count {
                let button = saveButtons.element(boundBy: index)
                guard button.exists else { continue }
                if button.frame.minY > textView.frame.maxY - 4 {
                    tapWhenHittableOrVisibleCenter(button, in: app, timeout: 3)
                    RunLoop.current.run(until: Date().addingTimeInterval(1))
                    return true
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < deadline
        return false
    }

    @MainActor
    private func saveWeeklyBriefAndWaitForGenerationAction(
        in app: XCUIApplication,
        below textView: XCUIElement
    ) -> XCUIElement? {
        for attempt in 1...3 {
            let saved = tapWeeklyBriefSave(in: app, below: textView)
            if !saved {
                return nil
            }

            if let action = firstExistingButton(in: app, labels: generationActionLabels, timeout: 15) {
                return action
            }

            let networkLost = app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS[c] %@", "network connection was lost")
            ).firstMatch
            if networkLost.exists, attempt < 3 {
                print("MANAGER_GENERATION_PROOF_WEEKLY_BRIEF_SAVE_RETRY=\(attempt)")
                RunLoop.current.run(until: Date().addingTimeInterval(Double(attempt)))
                continue
            }
        }

        return firstExistingButton(in: app, labels: generationActionLabels, timeout: 5)
    }

    /// Prints visible static text, text field values, and text view values from the
    /// generated review surface for human verification. Expands ONE "Full generated card"
    /// DisclosureGroup — the live app then exposes all 7 day cards' content at once
    /// (21 text fields: 7 cards × title/why/effort) plus 28 text views.
    /// Emits one observed/expected count marker without asserting exact counts
    /// (accessibility versions vary). Stops without selecting Publish.
    @MainActor
    private func printReviewSurfaceContent(in app: XCUIApplication) {
        printVisibleStaticTexts(in: app, prefix: "MANAGER_GENERATION_REVIEW_LABEL")
        printVisibleTextFieldAndTextViewValues(in: app, prefix: "MANAGER_GENERATION_REVIEW_FIELD")

        // Expand exactly one "Full generated card" DisclosureGroup.
        // Live evidence: expanding one card reveals all 7 day cards —
        // 21 text fields (7 × title/why/effort) and 28 text views (7 × script/backup/caption/cta).
        let matchingCards = app.buttons.matching(
            NSPredicate(format: "label ==[c] %@", "Full generated card")
        )
        var fullCard: XCUIElement?
        for i in 0..<matchingCards.count {
            let btn = matchingCards.element(boundBy: i)
            if btn.exists && btn.isHittable {
                fullCard = btn
                break
            }
        }
        if fullCard == nil, matchingCards.firstMatch.exists {
            fullCard = matchingCards.firstMatch
        }
        if let card = fullCard {
            tapWhenHittableOrVisibleCenter(card, in: app, timeout: 5)
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            print("MANAGER_GENERATION_REVIEW_FULL_CARD_EXPANDED")
        }

        // Let expanded content settle, then print the collection once.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        printVisibleStaticTexts(in: app, prefix: "MANAGER_GENERATION_REVIEW_EXPANDED_LABEL")
        printVisibleTextFieldAndTextViewValues(in: app, prefix: "MANAGER_GENERATION_REVIEW_EXPANDED_FIELD")

        // Emit observed vs expected counts. Do NOT assert exact values —
        // accessibility element representation varies across OS and device versions.
        let observedTextFieldCount = app.textFields.allElementsBoundByIndex.count
        let observedTextViewCount = app.textViews.allElementsBoundByIndex.count
        print("MANAGER_GENERATION_REVIEW_COUNT_MARKER text-fields(observed)=\(observedTextFieldCount) text-fields(expected)=21 text-views(observed)=\(observedTextViewCount) text-views(expected)=28")

        let keyLabels = ["Generated Week", "Draft ready for review", "MANAGER AI REVIEW"]
        for label in keyLabels {
            let element = app.staticTexts[label]
            if element.exists {
                print("MANAGER_GENERATION_REVIEW_KEY_LABEL[\(label)]=\(element.label)")
            }
        }
    }

    @MainActor
    private func printVisibleStaticTexts(in app: XCUIApplication, prefix: String) {
        for (index, text) in app.staticTexts.allElementsBoundByIndex.enumerated()
            where text.exists && !text.label.isEmpty {
            print("\(prefix)[\(index)]=\(text.label)")
        }
    }

    @MainActor
    private func printVisibleTextFieldAndTextViewValues(in app: XCUIApplication, prefix: String) {
        for (index, field) in app.textFields.allElementsBoundByIndex.enumerated() where field.exists {
            let value = field.value as? String ?? ""
            guard !field.label.isEmpty || !value.isEmpty else { continue }
            print("\(prefix)_TEXTFIELD[\(index)] label=\(field.label) value=\(value)")
        }
        for (index, view) in app.textViews.allElementsBoundByIndex.enumerated() where view.exists {
            let value = view.value as? String ?? ""
            guard !view.label.isEmpty || !value.isEmpty else { continue }
            print("\(prefix)_TEXTVIEW[\(index)] label=\(view.label) value=\(value)")
        }
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
