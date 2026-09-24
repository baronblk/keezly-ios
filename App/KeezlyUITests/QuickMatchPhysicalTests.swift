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
    @MainActor
    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-KEEZLY_UI_TESTING"]
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
            XCTFail("the menu never offered online play")
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
        picker.tap()
        // The picker presents its options; pick the one for this many seats.
        let option = app.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", String(seats))
        ).firstMatch
        if option.waitForExistence(timeout: 5) { option.tap() }
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

        chooseSeats(2, in: app)

        let quick = app.descendants(matching: .any)["online.new"]
        XCTAssertTrue(quick.waitForExistence(timeout: 10), "no quick match button")
        XCTAssertTrue(quick.isEnabled, "quick match was already disabled before it was tapped")
        quick.tap()

        // Every outcome is named. `waitingForPlayers` is a pass for this test:
        // one device cannot fill a two-seat table on its own, and calling that
        // a failure is what the original defect did.
        let settled = waitForState(
            ["waitingForPlayers", "loadingMatch", "idle"],
            in: app,
            timeout: 90,
            "quick match never reached a settled state"
        )

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
