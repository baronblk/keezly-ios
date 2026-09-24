import XCTest

/// Quick match, driven on a real device rather than described to somebody.
///
/// These run against physical hardware with a real Game Center account. They
/// are **not** part of the default plan: they need an account, a network and
/// Apple's service, so on a simulator or a signed-out device they report what
/// is missing and stop rather than failing for the wrong reason.
///
/// What they exist for: the owner should not have to tap through an ordinary
/// test step. Everything up to the point where Apple's own system UI takes
/// over is automated here, and the log each run leaves behind is the evidence.
///
/// The one thing no test can do is sign an account in, or pick a friend in
/// Apple's picker. Those are Apple's own surfaces and they are named as owner
/// steps rather than faked.
final class QuickMatchPhysicalTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Launched **without** `-KEEZLY_NO_GAME_CENTER`, unlike every other UI
    /// test: the whole point is to reach the real service.
    ///
    /// State *is* reset, and that is not optional here. These devices are used
    /// for playing as well as testing, so the app resumes whatever match was
    /// left open and never shows the menu at all — which is exactly how this
    /// suite first failed, with "the menu never offered online play" while the
    /// board sat there in the hierarchy.
    ///
    /// Resetting clears what this device remembers locally. It does **not**
    /// touch the online matches: those are kept by Game Center, not in the
    /// local store, which is why an online session is built with no store at
    /// all. So the thing under test survives the reset.
    @MainActor
    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        // **No `-KEEZLY_UI_TESTING`.** That flag sets `ScreenshotMode.isActive`,
        // which boots the app into a deterministic capture match instead of
        // the menu *and* switches Game Center off — so passing it made this
        // suite test a board it had not asked for, with the one service it
        // exists to reach disabled. It was copied from the other UI tests
        // without checking what it does.
        //
        // **No `-KEEZLY_NO_GAME_CENTER` either**, for the same reason in
        // reverse: it is the half of `isRunningTests` that works for UI tests,
        // and it is what every other suite uses to stay away from Apple.
        //
        // So: the real menu, the real Game Center, and a clean device.
        app.launchArguments = ["-KEEZLY_UI_TEST_RESET_STATE", "YES"]
        app.launch()
        return app
    }

    /// The start flow's state, by name. Waiting on this rather than on a
    /// spinner is what makes the test deterministic: a spinner is present in
    /// several different states and absent in two, so it cannot tell them
    /// apart.
    @MainActor
    private func state(in app: XCUIApplication) -> String {
        app.descendants(matching: .any)["online.startState"].label
    }

    /// Everything the gate is decided on, printed into **this** run's output.
    ///
    /// The app logs to the device console; `xcodebuild` captures its own
    /// output and not that. Printing here puts the facts in the one place the
    /// runner is already reading, instead of correlating two channels by
    /// timestamp afterwards.
    @MainActor
    private func report(_ app: XCUIApplication, _ note: String) {
        let probe = app.descendants(matching: .any)["online.probe"].label
        let line = "E2E \(note) state=\(state(in: app)) \(probe)"
        print(line)
        // What the app itself logged. Its console does not reach xcodebuild,
        // so without this every diagnosis is guesswork about a process we
        // cannot hear.
        let log = app.descendants(matching: .any)["keezly.onlineLog"].label
        if !log.isEmpty { print("E2E LOG \(note): \(log)") }
        XCTContext.runActivity(named: line) { _ in }
    }

    @MainActor
    private func waitForState(
        _ wanted: Set<String>,
        in app: XCUIApplication,
        timeout: TimeInterval,
        _ message: String
    ) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let current = state(in: app)
            if wanted.contains(current) { return current }
            // A failure state is an answer too, and waiting out the full
            // timeout for one is just slower.
            if current.hasPrefix("failed.") { return current }
            usleep(400_000)
        }
        XCTFail("\(message) — state stayed at \(state(in: app)) for \(Int(timeout))s")
        return nil
    }

    /// Opens the online screen, or says precisely why it could not.
    ///
    /// Returns nil when this run cannot reach Game Center at all, which is a
    /// skip rather than a failure: a signed-out device has not disproved
    /// anything about matchmaking.
    @MainActor
    private func openOnline(_ app: XCUIApplication) -> Bool {
        let online = app.descendants(matching: .any)["menu.online"]
        guard online.waitForExistence(timeout: 30) else {
            // What was on screen instead. Without this the failure says only
            // that something was missing, which is the least useful thing a
            // test can tell you about a screen it could not read.
            print("E2E HIERARCHY\n\(app.debugDescription)")
            XCTFail("the menu never offered online play — hierarchy printed above")
            return false
        }
        online.tap()

        guard app.descendants(matching: .any)["online.screen"].waitForExistence(timeout: 30) else {
            XCTFail("the online screen never appeared")
            return false
        }

        // Signed out is an owner step, not a defect. Say so and stop.
        if app.descendants(matching: .any)["online.signIn"].waitForExistence(timeout: 5) {
            XCTContext.runActivity(named: "OWNER STEP REQUIRED") { _ in
                XCTFail("""
                    OWNER STEP: this device is not signed in to Game Center. \
                    Settings › Game Center. No conclusion about matchmaking \
                    can be drawn from this run.
                    """)
            }
            return false
        }
        return true
    }

    @MainActor
    private func chooseSeats(_ seats: Int, in app: XCUIApplication) {
        let picker = app.descendants(matching: .any)["online.seats"]
        guard picker.waitForExistence(timeout: 10) else {
            XCTFail("the seat picker never appeared")
            return
        }
        // A segmented control, exactly like the local table's — so the option
        // is a button that can be tapped directly. Tapping the picker first
        // and hunting the popup is what failed on the phone: the option
        // existed and could not be scrolled to.
        let option = picker.buttons[String(seats)]
        guard option.waitForExistence(timeout: 5) else {
            XCTFail("no option for \(seats) seats in the picker")
            return
        }
        option.tap()
        // Asserted rather than hoped: silently leaving the default selected
        // would have this test quietly measure a different table size.
        XCTAssertTrue(option.isSelected, "the picker did not move to \(seats) seats")
    }

    /// Clears this device's own abandoned searches.
    ///
    /// Run on purpose, never as a side effect of another test. Twenty-five
    /// open searches per account is not a neutral background for a matchmaking
    /// test — GameKit has its own limits, and testing against a pile of stale
    /// matches measures the pile as much as the code.
    ///
    /// Only removes matches with nobody else in them and no board dealt, so
    /// nothing anybody is playing can be lost.
    @MainActor
    func testCleanUpOwnAbandonedSearches() throws {
        let app = launched()
        guard openOnline(app) else { return }
        report(app, "before-cleanup")

        let cleanup = app.descendants(matching: .any)["online.cleanup"]
        guard cleanup.waitForExistence(timeout: 10) else {
            // Fewer than three: nothing to tidy, and the button is not shown.
            report(app, "nothing-to-clean")
            return
        }
        cleanup.tap()

        // The list shrinks as they go. Waiting on the count rather than on a
        // fixed delay, because how long it takes depends on how many there are.
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline, cleanup.exists {
            usleep(500_000)
        }
        report(app, "after-cleanup")
    }

    // MARK: - The path the owner reported as broken

    /// Two-player quick match, all the way to whatever it actually does.
    ///
    /// Run this on both devices at once — `scripts/e2e-two-devices.sh` does
    /// that — and compare the two logs. The line that decides it is
    /// `matched id=…`: two devices searching together must land on the same
    /// match id, and if they do not, the fault is in the request or the queue
    /// rather than in anything afterwards.
    @MainActor
    func testQuickMatchTwoPlayers() throws {
        let app = launched()
        guard openOnline(app) else { return }
        report(app, "opened")

        chooseSeats(2, in: app)

        let quick = app.descendants(matching: .any)["online.new"]
        XCTAssertTrue(quick.waitForExistence(timeout: 10), "no quick match button")
        XCTAssertTrue(quick.isEnabled, "quick match was already disabled before it was tapped")
        quick.tap()

        // Every outcome is named. `waitingForPlayers` is a pass for this test:
        // one device cannot fill a two-seat table on its own, and calling that
        // a failure is what the original defect did.
        report(app, "tapped")

        let settled = waitForState(
            ["waitingForPlayers", "loadingMatch", "idle"],
            in: app,
            timeout: 90,
            "quick match never reached a settled state"
        )
        report(app, "settled")

        // Long enough for the other device to start, search, and join — and
        // for this one to be told about it. The question this answers is not
        // "did it settle" but "did it notice somebody arriving afterwards",
        // which is a different thing and the one that was broken.
        for tick in 1...6 {
            Thread.sleep(forTimeInterval: 15)
            report(app, "wait-\(tick * 15)s")
            if state(in: app) == "loadingMatch" || state(in: app) == "idle" { break }
        }

        guard let settled else { return }
        XCTAssertFalse(
            settled.hasPrefix("failed."),
            "quick match failed: \(settled). The device log carries the domain and code."
        )
        XCTAssertNotEqual(
            settled, "idle",
            "quick match returned to idle with nothing to show — the silent failure this test exists for"
        )
    }

    /// Apple's own matchmaker, driven as far as it can be driven.
    ///
    /// The programmatic path — `GKTurnBasedMatch.find` — does not pair two
    /// devices here: each gets its own match, clean accounts or not, staggered
    /// or not, and it creates a new match on every call rather than ever
    /// returning a joinable one. `GKTurnBasedMatchmakerViewController` is the
    /// route Apple actually supports for turn-based matchmaking, and this
    /// finds out whether it behaves differently.
    ///
    /// Apple's sheet is a remote view. Its buttons are sometimes reachable
    /// from a test and sometimes not; when they are not, that is reported as an
    /// owner step rather than a failure, because a sheet this test cannot tap
    /// is not a defect in Keezly.
    @MainActor
    func testAppleMatchmakerSheet() throws {
        let app = launched()
        guard openOnline(app) else { return }
        chooseSeats(2, in: app)

        let invite = app.descendants(matching: .any)["online.invite"]
        XCTAssertTrue(invite.waitForExistence(timeout: 10), "no invite button")
        invite.tap()
        report(app, "invite-tapped")

        // The sheet is GameKit's, so it is looked for by what it shows rather
        // than by an identifier Keezly could have set.
        let arrived = app.staticTexts["Game Center"].waitForExistence(timeout: 20)
            || app.buttons["Auto-Match"].waitForExistence(timeout: 5)
            || app.buttons["Play Now"].waitForExistence(timeout: 5)
            || app.navigationBars.count > 1

        print("E2E MATCHMAKER-SHEET arrived=\(arrived)")
        print("E2E MATCHMAKER-HIERARCHY\n\(app.debugDescription)")

        guard arrived else {
            XCTContext.runActivity(named: "OWNER STEP REQUIRED") { _ in
                XCTFail("""
                    OWNER STEP: Apple's matchmaker sheet did not appear, or is \
                    not readable from a test. Hierarchy printed above.
                    """)
            }
            return
        }
        report(app, "sheet-open")

        for label in ["Auto-Match", "Play Now", "Automatch", "Jetzt spielen"] {
            let button = app.buttons[label]
            if button.exists, button.isHittable {
                button.tap()
                report(app, "sheet-\(label)")
                break
            }
        }

        for tick in 1...6 {
            Thread.sleep(forTimeInterval: 15)
            report(app, "sheet-wait-\(tick * 15)s")
            if state(in: app) == "loadingMatch" { break }
        }
    }

    /// A second tap while a search is running must not start a second search.
    ///
    /// This is what left eleven orphaned matches on one account: every tap
    /// created a match, and nothing stopped the taps.
    @MainActor
    func testQuickMatchCannotBeStartedTwice() throws {
        let app = launched()
        guard openOnline(app) else { return }

        chooseSeats(2, in: app)
        let quick = app.descendants(matching: .any)["online.new"]
        XCTAssertTrue(quick.waitForExistence(timeout: 10))
        quick.tap()

        _ = waitForState(
            ["waitingForPlayers", "loadingMatch", "matchmaking", "openingMatchmaker"],
            in: app,
            timeout: 60,
            "the search never started"
        )

        // While anything is in flight the button must refuse. Once the match
        // is waiting it may be tapped again — that starts a *different* match,
        // which is a choice rather than an accident.
        if state(in: app) == "matchmaking" || state(in: app) == "openingMatchmaker" {
            XCTAssertFalse(quick.isEnabled, "a second quick match could be started while one was running")
        }
    }

    /// Every table size the menu offers must at least be startable.
    ///
    /// Not a matchmaking test — one device cannot fill any of these — but the
    /// crash from build 41 lived exactly here, in the seat/teams combination
    /// handed to the engine before GameKit was ever called.
    @MainActor
    func testEverySeatCountStarts() throws {
        for seats in [2, 3, 4, 5, 6] {
            let app = launched()
            guard openOnline(app) else { return }

            chooseSeats(seats, in: app)
            let quick = app.descendants(matching: .any)["online.new"]
            guard quick.waitForExistence(timeout: 10) else {
                XCTFail("no quick match button at \(seats) seats")
                return
            }
            quick.tap()

            let settled = waitForState(
                ["waitingForPlayers", "loadingMatch", "idle"],
                in: app,
                timeout: 60,
                "\(seats) seats never settled"
            )
            XCTAssertEqual(
                settled?.hasPrefix("failed."), false,
                "\(seats) seats ended at \(settled ?? "nothing")"
            )
            app.terminate()
        }
    }
}
