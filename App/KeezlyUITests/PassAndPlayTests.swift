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
    @MainActor
    private func launchedPassAndPlay(seats: Int = 3) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["menu.start"].waitForExistence(timeout: 20),
            "the app did not open on the menu"
        )
        app.descendants(matching: .any)["table.players"].buttons["\(seats)"].tap()
        app.descendants(matching: .any)["table.people"].buttons["\(seats)"].tap()
        app.descendants(matching: .any)["menu.start"].tap()
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
    func testTheCoverReturnsForTheNextPlayer() throws {
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
        try XCTSkipUnless(played, "this deal offered no single-tap move to pass the turn with")

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
