import XCTest

/// §34, §36 — the menu is where a match begins, and the table it sets up has
/// to be the table that is actually played.
final class MenuFlowTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// A plain launch, with none of the deterministic test arguments, so the
    /// app does what it does for a player.
    @MainActor
    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["menu.start"].waitForExistence(timeout: 20),
            "the app did not open on the menu"
        )
        return app
    }

    @MainActor
    private func waitingAreas(in app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'pawn.'"))
            .allElementsBoundByIndex
    }

    /// The board only appears once a table has been started. A game that began
    /// on its own would leave the player no way to choose one.
    @MainActor
    func testTheAppOpensOnTheMenu() {
        let app = launched()
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'hand.card.'"))
                .firstMatch.exists,
            "a hand was dealt before any table was chosen"
        )
    }

    /// The whole point of the screen: choose a table, get that table.
    @MainActor
    func testStartingASixPlayerTableDealsSixSeats() {
        let app = launched()

        let players = app.descendants(matching: .any)["table.players"]
        XCTAssertTrue(players.exists, "no way to choose how many players")
        players.buttons["6"].tap()

        app.descendants(matching: .any)["menu.start"].tap()

        let hand = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'hand.card.'"))
            .firstMatch
        XCTAssertTrue(hand.waitForExistence(timeout: 20), "the table was never dealt")

        // Four pawns a seat, so six seats is twenty-four pieces on the board.
        XCTAssertEqual(waitingAreas(in: app).count, 24, "a six-player table has twenty-four pieces")
    }

    @MainActor
    func testStartingATwoPlayerTableDealsTwoSeats() {
        let app = launched()
        app.descendants(matching: .any)["table.players"].buttons["2"].tap()
        app.descendants(matching: .any)["menu.start"].tap()

        let hand = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'hand.card.'"))
            .firstMatch
        XCTAssertTrue(hand.waitForExistence(timeout: 20))
        XCTAssertEqual(waitingAreas(in: app).count, 8, "a two-player table has eight pieces")

        // A two-seat board has no middle, so the cards sit beside it (ISS-013).
        XCTAssertTrue(
            app.descendants(matching: .any)["table.tray"].exists,
            "the two-player table showed no tray beside the board"
        )
    }

    /// Partners are impossible at three seats, and the control says so rather
    /// than accepting a choice it would then ignore.
    @MainActor
    func testPartnersCannotBeChosenAtAnOddTable() {
        let app = launched()
        let sides = app.descendants(matching: .any)["table.sides"]
        XCTAssertTrue(sides.isEnabled, "partners should be available at the default four-player table")

        app.descendants(matching: .any)["table.players"].buttons["3"].tap()
        XCTAssertFalse(sides.isEnabled, "three players cannot be partners, so the control must not offer it")
    }
}
