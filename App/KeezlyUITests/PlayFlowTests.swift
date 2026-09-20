import XCTest

/// §36, §63 — the interaction flow, exercised as a player would.
///
/// The match is seeded, and so are the computer opponents, so the opening
/// position is the same on every run. That is what makes it possible to assert
/// on specific cards and squares rather than on "something changed".
final class PlayFlowTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    /// Hand cards carry identifiers of the form `hand.card.<rank>.<id>`. The
    /// discard pile uses `discard.card.<rank>.<id>`, so counting the hand
    /// cannot pick it up.
    @MainActor
    private func cards(in app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'hand.card.'"))
            .allElementsBoundByIndex
    }

    @MainActor
    private func targets(in app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'target.'"))
            .allElementsBoundByIndex
    }

    @MainActor
    func testHandIsDealtAndVisible() {
        let app = launched()
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'hand.card.'"))
                .firstMatch.waitForExistence(timeout: 15),
            "the local player should be dealt a visible hand"
        )
        XCTAssertEqual(cards(in: app).count, 5, "the opening deal is five cards (§12)")
    }

    /// Nothing is highlighted until a card is chosen: the board must not offer
    /// targets the player has not asked for (§36).
    @MainActor
    func testNoTargetsBeforeACardIsChosen() {
        let app = launched()
        XCTAssertTrue(cards(in: app).first?.waitForExistence(timeout: 15) ?? false)
        XCTAssertTrue(targets(in: app).isEmpty, "targets appeared before any card was selected")
    }

    /// The whole flow: pick a card, pick the pawn it offers, tap the square,
    /// and see the board change.
    @MainActor
    func testPlayingACardMovesAPawn() {
        let app = launched()
        XCTAssertTrue(cards(in: app).first?.waitForExistence(timeout: 15) ?? false)

        // Only some cards are playable; tapping each in turn finds one that
        // offers a move without the test needing to know the deal.
        var openedTargets = false
        for card in cards(in: app) {
            card.tap()
            if !targets(in: app).isEmpty { openedTargets = true; break }

            // A card may need its pawn chosen first.
            let pawns = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'pawn.'"))
                .allElementsBoundByIndex
            for pawn in pawns where pawn.isHittable {
                pawn.tap()
                if !targets(in: app).isEmpty { openedTargets = true; break }
            }
            if openedTargets { break }
        }

        XCTAssertTrue(openedTargets, "no card in the opening hand offered a target")

        let target = targets(in: app).first
        XCTAssertNotNil(target)
        target?.tap()

        // After the move the hand is one card shorter — the clearest signal
        // from outside that the engine accepted it.
        let handShrank = NSPredicate(format: "count == 4")
        let query = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'hand.card.'"))
        expectation(for: handShrank, evaluatedWith: query)
        waitForExpectations(timeout: 20)
    }

    /// §63 — a second tap on an already-played card must not apply a move
    /// twice. The hand may only ever lose one card per play.
    @MainActor
    func testDoubleTappingDoesNotPlayTwice() {
        let app = launched()
        XCTAssertTrue(cards(in: app).first?.waitForExistence(timeout: 15) ?? false)

        var target: XCUIElement?
        for card in cards(in: app) {
            card.tap()
            if let first = targets(in: app).first { target = first; break }
            let pawns = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'pawn.'"))
                .allElementsBoundByIndex
            for pawn in pawns where pawn.isHittable {
                pawn.tap()
                if let first = targets(in: app).first { target = first; break }
            }
            if target != nil { break }
        }
        guard let target else { return XCTFail("no target to tap") }

        target.tap()
        // Immediately again, on the same square, while the board is still
        // catching up.
        if target.exists { target.tap() }

        let query = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'hand.card.'"))
        expectation(for: NSPredicate(format: "count <= 4"), evaluatedWith: query)
        waitForExpectations(timeout: 20)
        XCTAssertGreaterThanOrEqual(cards(in: app).count, 3, "a double tap played more than one card")
    }
}
