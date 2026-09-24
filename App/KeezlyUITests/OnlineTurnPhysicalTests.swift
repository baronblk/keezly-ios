import XCTest

/// Playing a real online match, on real hardware, against a real opponent.
///
/// Runs **after** a match exists — created through Apple's matchmaker, which
/// needs one human tap to pick somebody. Everything from there is automated:
/// open the match, take a turn, and report the position by its checksum so the
/// two devices can be compared.
///
/// Deliberately not a two-device-at-once test. A turn-based match does not need
/// both devices awake at the same moment — that is the whole point of it — so
/// these run on one device at a time, alternately, which is also how anybody
/// actually plays.
final class OnlineTurnPhysicalTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The real menu and the real Game Center. **No `-KEEZLY_UI_TESTING`** —
    /// that switches Game Center off and boots a fixture board instead of the
    /// menu — and **no state reset**, because the match under test is the one
    /// already on this device.
    @MainActor
    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        return app
    }

    @MainActor
    private func log(_ app: XCUIApplication, _ note: String) {
        let probe = app.descendants(matching: .any)["online.probe"].label
        print("TURN \(note) \(probe)")
        let diagnostics = app.descendants(matching: .any)["keezly.onlineLog"].label
        if !diagnostics.isEmpty { print("TURN LOG \(note): \(diagnostics)") }
    }

    @MainActor
    private func openOnline(_ app: XCUIApplication) -> Bool {
        let online = app.descendants(matching: .any)["menu.online"]
        guard online.waitForExistence(timeout: 30) else {
            print("TURN HIERARCHY\n\(app.debugDescription)")
            XCTFail("the menu never offered online play")
            return false
        }
        online.tap()
        guard app.descendants(matching: .any)["online.screen"].waitForExistence(timeout: 30) else {
            XCTFail("the online screen never appeared")
            return false
        }
        if app.descendants(matching: .any)["online.signIn"].waitForExistence(timeout: 4) {
            XCTFail("OWNER STEP: not signed in to Game Center on this device")
            return false
        }
        return true
    }

    /// Opens the first match that has a board, whoever is on turn.
    ///
    /// A row without a board is a search, not a game — those are what the
    /// twenty-six orphans were — so they are skipped rather than tapped.
    @MainActor
    private func openAMatch(_ app: XCUIApplication) -> Bool {
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'online.match.'"))
        guard rows.firstMatch.waitForExistence(timeout: 20) else {
            XCTFail("no online match on this device to open")
            return false
        }

        for row in rows.allElementsBoundByIndex where row.isHittable {
            row.tap()
            // The board arrives, or this was a search and the screen stays.
            if app.descendants(matching: .any)["board.status"].waitForExistence(timeout: 25) {
                return true
            }
            if app.descendants(matching: .any)["online.screen"].exists { continue }
        }
        XCTFail("no row opened onto a board")
        return false
    }

    // MARK: - One turn

    /// Opens a match and, if it is this device's turn, plays one legal move.
    ///
    /// Reports either way. "Not my turn" is a pass: it means the opponent has
    /// the move, which is exactly what should be true after the other device
    /// has played.
    @MainActor
    func testTakeOneTurn() throws {
        let app = launched()
        guard openOnline(app) else { return }
        log(app, "lobby")
        guard openAMatch(app) else { return }
        log(app, "board-open")

        let yourTurn = app.descendants(matching: .any)["online.yourTurn"]
        let waiting = app.descendants(matching: .any)["online.waiting"]
        let finished = app.descendants(matching: .any)["online.result"]

        if finished.waitForExistence(timeout: 3) {
            print("TURN RESULT match is over")
            log(app, "finished")
            return
        }
        guard yourTurn.waitForExistence(timeout: 10) else {
            XCTAssertTrue(waiting.exists, "the board showed neither turn nor wait")
            print("TURN RESULT not my turn — the opponent has the move")
            log(app, "their-turn")
            return
        }

        // A card, then a square it may go to. The same shape the pass-and-play
        // suite uses, and deliberately not `target.leg.` — tapping one leg of a
        // Seven commits half a move and leaves the turn open.
        var played = false
        let cards = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'hand.card.'"))
            .allElementsBoundByIndex

        for card in cards where !played {
            card.tap()
            let targets = app.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH 'target.' AND NOT identifier BEGINSWITH 'target.leg.'"
            ))
            if let target = targets.allElementsBoundByIndex.first {
                target.tap()
                played = true
                break
            }
            for pawn in app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'pawn.'"))
                .allElementsBoundByIndex where pawn.isHittable && !played {
                pawn.tap()
                if let target = targets.allElementsBoundByIndex.first {
                    target.tap()
                    played = true
                }
            }
        }

        XCTAssertTrue(played, "this hand offered no move at all, which a forced-move rule forbids")
        log(app, "played")

        // The move has to leave the device, not merely be accepted locally.
        let sent = waiting.waitForExistence(timeout: 45)
            || app.descendants(matching: .any)["online.result"].waitForExistence(timeout: 5)
        XCTAssertTrue(sent, "the move was played but the turn never passed on")
        log(app, "sent")
        print("TURN RESULT played and sent")
    }

    /// Kill and resume, on the match this device holds.
    @MainActor
    func testResumeAfterKill() throws {
        let app = launched()
        guard openOnline(app) else { return }
        guard openAMatch(app) else { return }
        log(app, "before-kill")

        app.terminate()
        app.launchArguments = []
        app.launch()

        guard openOnline(app) else { return }
        guard openAMatch(app) else { return }
        log(app, "after-resume")
        XCTAssertTrue(
            app.descendants(matching: .any)["board.status"].exists,
            "the match did not come back after the app was killed"
        )
        print("TURN RESULT resumed")
    }
}
