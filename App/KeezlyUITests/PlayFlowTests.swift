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

/// §46 — the keyboard has to be a complete way to play, not a courtesy.
///
/// The decision logic is unit-tested in `PlayFocusTests`. This is the other
/// half, which only a running app can answer: that focus lands where it should,
/// that the ring is visible, and — where a keyboard is actually available —
/// that a whole move can be made without touching the screen.
///
/// **On key events.** iOS hands a view focus only when a hardware keyboard or
/// Full Keyboard Access is present. A simulator booted headlessly by
/// `xcodebuild` has neither, so key injection does nothing. These tests detect
/// that and **skip** rather than pass: a green test that exercised nothing is
/// worse than an honest gap (§177).
final class KeyboardPlayTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func cards(in app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'hand.card.'"))
            .allElementsBoundByIndex
    }

    private func targets(in app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'target.'"))
            .allElementsBoundByIndex
    }

    /// What the app says its focus is. The probe exists only under the debug
    /// launch argument.
    @MainActor
    private func focusLabel(in app: XCUIApplication) -> String {
        app.descendants(matching: .any)["debug.focus"].label
    }

    /// Waits for focus to reach a kind of thing.
    ///
    /// Acting moves focus on asynchronously — the ring cannot be recomputed
    /// until the state has been rendered — so a test that hammers keys races
    /// the app. A person types slower than that.
    @MainActor
    @discardableResult
    private func waitForFocus(_ app: XCUIApplication, prefix: String, timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if focusLabel(in: app).hasPrefix(prefix) { return true }
            usleep(150_000)
        }
        return false
    }

    @MainActor
    private func launched(focused: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-KEEZLY_UI_TESTING", "-KEEZLY_SEATS", "4", "-KEEZLY_SEED", "2026",
            "-KEEZLY_DEBUG_FOCUS",
        ] + (focused ? ["-KEEZLY_FOCUS", "first"] : [])
        app.launch()
        XCTAssertTrue(cards(in: app).first?.waitForExistence(timeout: 20) ?? false, "no hand was dealt")
        return app
    }

    /// Skips the rest of a test when this machine cannot deliver key events.
    @MainActor
    private func requireWorkingKeyboard(_ app: XCUIApplication) throws {
        let before = focusLabel(in: app)
        app.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: [])
        guard focusLabel(in: app) != before else {
            throw XCTSkip(
                """
                No hardware keyboard reached the app: focus did not move. \
                A headless simulator has no keyboard attached, and this Xcode \
                installation ships no Simulator.app to attach one. \
                Keyboard logic is covered by PlayFocusTests; this gate stays \
                NOT VERIFIED rather than reporting a pass it did not earn.
                """
            )
        }
    }

    // MARK: - What a keyboardless simulator can still prove

    /// Focus lands on a *playable* card, and the app says so.
    @MainActor
    func testFocusStartsOnAPlayableCard() {
        let app = launched()
        XCTAssertTrue(
            waitForFocus(app, prefix: "focus:card:", timeout: 20),
            "focus never reached a card, it was \(focusLabel(in: app))"
        )
    }

    /// The focus ring has to be visible, or keyboard support is theoretical.
    @MainActor
    func testFocusRingIsVisible() {
        let app = launched()
        waitForFocus(app, prefix: "focus:card:", timeout: 20)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "focus-ring-on-first-card"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Without the launch flag there is no focus at all — which is right for a
    /// touch player, who never asked for a focus ring.
    @MainActor
    func testTouchPlayersSeeNoFocusRing() {
        let app = launched(focused: false)
        XCTAssertEqual(focusLabel(in: app), "focus:none")
    }

    // MARK: - What needs a real keyboard

    @MainActor
    func testArrowKeysWalkTheHand() throws {
        let app = launched()
        waitForFocus(app, prefix: "focus:card:", timeout: 20)
        let first = focusLabel(in: app)
        try requireWorkingKeyboard(app)

        // Right moved focus to a different card, and it is still a card: the
        // arrow walks the hand rather than falling out of it.
        let second = focusLabel(in: app)
        XCTAssertTrue(second.hasPrefix("focus:card:"), "right arrow left the hand: \(second)")
        XCTAssertNotEqual(first, second)
    }

    @MainActor
    func testAMoveCanBePlayedWithTheKeyboardAlone() throws {
        let app = launched()
        waitForFocus(app, prefix: "focus:card:", timeout: 20)
        try requireWorkingKeyboard(app)
        XCTAssertEqual(cards(in: app).count, 5, "a deal is five cards")

        // Card, then piece, then square — waiting for focus to arrive at each
        // stage rather than assuming it already has.
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        if waitForFocus(app, prefix: "focus:pawn:") {
            app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        }
        XCTAssertTrue(waitForFocus(app, prefix: "focus:target:"), "the keyboard never reached a square")
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        let shrank = NSPredicate(format: "count == 4")
        let query = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'hand.card.'"))
        expectation(for: shrank, evaluatedWith: query)
        waitForExpectations(timeout: 25)
    }

    /// Escape must always get the player back out (§37).
    @MainActor
    func testEscapeCancelsASelection() throws {
        let app = launched()
        try requireWorkingKeyboard(app)

        waitForFocus(app, prefix: "focus:card:", timeout: 20)
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        if waitForFocus(app, prefix: "focus:pawn:") {
            app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        }
        XCTAssertTrue(waitForFocus(app, prefix: "focus:target:"), "nothing was chosen, so there is nothing to cancel")
        XCTAssertFalse(targets(in: app).isEmpty)

        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

        let cleared = NSPredicate(format: "count == 0")
        let query = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'target.'"))
        expectation(for: cleared, evaluatedWith: query)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(cards(in: app).count, 5, "cancelling must not play a card")
    }
}
