import XCTest

/// §34 — pass & play, and the one promise it has to keep: at the moment the
/// device changes hands, nobody's cards are on screen.
final class PassAndPlayTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    private func cards(in app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'hand.card.'"))
            .allElementsBoundByIndex
    }

    /// A table where every seat is a person, so every single turn is a
    /// handover and there is no computer to wait for.
    ///
    /// Set up by launch argument rather than by driving the menu, and with a
    /// fixed seed: the privacy guarantee must be checked against a known deal,
    /// not against whatever a random one happens to offer (§87).
    @MainActor
    private func launchedPassAndPlay(seats: Int = 3, seed: Int = 2026) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-KEEZLY_UI_TESTING",
            "-KEEZLY_SEATS", String(seats),
            "-KEEZLY_HUMANS", String(seats),
            "-KEEZLY_SEED", String(seed),
        ]
        app.launch()
        return app
    }

    /// The promise. Nothing else in this suite matters if this fails.
    @MainActor
    func testNoCardsAreVisibleWhileTheDeviceIsBeingPassed() {
        let app = launchedPassAndPlay()

        let cover = app.descendants(matching: .any)["handover"]
        XCTAssertTrue(cover.waitForExistence(timeout: 20), "the first player was never asked to take the device")
        XCTAssertEqual(cards(in: app).count, 0, "a hand was on screen while the device was being passed")
    }

    /// Taking the device shows that player's hand, and only then.
    @MainActor
    func testTakingTheDeviceRevealsThatPlayersHand() {
        let app = launchedPassAndPlay()

        let ready = app.buttons["handover.ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 20), "no way to take the device")
        XCTAssertEqual(cards(in: app).count, 0)

        ready.tap()

        let hand = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'hand.card.'"))
            .firstMatch
        XCTAssertTrue(
            hand.waitForExistence(timeout: 15),
            "the player's hand never appeared after they took the device"
        )
    }

    /// The cover comes back for the next player rather than only once.
    @MainActor
    func testTheCoverReturnsForTheNextPlayer() {
        let app = launchedPassAndPlay()

        let ready = app.buttons["handover.ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 20), "no way to take the device")
        ready.tap()

        let firstHand = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'hand.card.'"))
            .firstMatch
        XCTAssertTrue(firstHand.waitForExistence(timeout: 15))

        // Play something — any card that offers a target — to pass the turn on.
        var played = false
        for card in cards(in: app) {
            card.tap()
            let targets = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'target.'"))
            if let target = targets.allElementsBoundByIndex.first {
                target.tap()
                played = true
                break
            }
            for pawn in app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'pawn.'"))
                .allElementsBoundByIndex where pawn.isHittable {
                pawn.tap()
                if let target = targets.allElementsBoundByIndex.first {
                    target.tap()
                    played = true
                    break
                }
            }
            if played { break }
        }
        XCTAssertTrue(played, "the fixed deal offered no move to pass the turn with")

        let cover = app.descendants(matching: .any)["handover"]
        XCTAssertTrue(cover.waitForExistence(timeout: 20), "the device was not covered before the next player")
        XCTAssertEqual(cards(in: app).count, 0, "the next player's hand was visible before they took the device")
    }

    /// A table with one person never asks anybody to take the device.
    @MainActor
    func testASoloTableNeverCoversTheBoard() {
        let app = XCUIApplication()
        app.launchArguments = ["-KEEZLY_UI_TESTING", "-KEEZLY_SEATS", "4", "-KEEZLY_SEED", "2026"]
        app.launch()

        let hand = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'hand.card.'"))
            .firstMatch
        XCTAssertTrue(hand.waitForExistence(timeout: 20))
        XCTAssertFalse(
            app.descendants(matching: .any)["handover"].exists,
            "a table with one person was asked to pass the device"
        )
    }
}

/// §34, §57 — picking a pass-and-play match up again.
///
/// The app is genuinely relaunched between the two halves of these tests, so
/// what is checked is what a player would meet after closing the app: the
/// match comes back, and it comes back *covered*.
final class PassAndPlayResumeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    private func cards(in app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'hand.card.'"))
            .allElementsBoundByIndex
    }

    /// Starts a three-person match through the menu — the real path, so the
    /// match is written to the real store — and takes the device once.
    @MainActor
    private func startAndAbandon() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["menu.start"].waitForExistence(timeout: 20),
            "the app did not open on the menu"
        )
        app.descendants(matching: .any)["table.players"].buttons["3"].tap()
        app.descendants(matching: .any)["table.people"].buttons["3"].tap()
        app.descendants(matching: .any)["menu.start"].tap()

        let ready = app.buttons["handover.ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 20), "the first player was never offered the device")
        ready.tap()
        XCTAssertTrue(
            cards(in: app).first?.waitForExistence(timeout: 15) ?? false,
            "the hand never appeared before the app was closed"
        )
        return app
    }

    /// Closed with a hand on screen, reopened — and the hand is not there.
    ///
    /// This is the case the whole design turns on: safety before convenience.
    /// Whoever picks the device up next may not be the person who put it down.
    @MainActor
    func testAResumedMatchComesBackCovered() {
        let app = startAndAbandon()
        app.terminate()

        app.launchArguments = []
        app.launch()

        let resume = app.descendants(matching: .any)["menu.continue"]
        XCTAssertTrue(resume.waitForExistence(timeout: 20), "the match was not offered to be continued")
        resume.tap()

        XCTAssertTrue(
            app.buttons["handover.ready"].waitForExistence(timeout: 20),
            "a resumed pass-and-play match did not ask who is holding the device"
        )
        XCTAssertEqual(cards(in: app).count, 0, "a hand was on screen before anybody took the device")
    }

    /// And after taking it, the match really is the one that was saved.
    @MainActor
    func testAResumedMatchCarriesOn() {
        let app = startAndAbandon()
        app.terminate()

        app.launchArguments = []
        app.launch()
        let resume = app.descendants(matching: .any)["menu.continue"]
        XCTAssertTrue(resume.waitForExistence(timeout: 20))
        resume.tap()

        let ready = app.buttons["handover.ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 20))
        ready.tap()

        // Five cards is the opening deal, which is where this match was left.
        let dealt = NSPredicate(format: "count == 5")
        let query = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'hand.card.'"))
        expectation(for: dealt, evaluatedWith: query)
        waitForExpectations(timeout: 20)
    }
}
