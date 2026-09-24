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

    /// The match this run is bound to, if one was named.
    ///
    /// Passed as `TEST_RUNNER_KEEZLY_MATCH=<id>` on the `xcodebuild` command.
    private var targetMatch: String? {
        let value = ProcessInfo.processInfo.environment["KEEZLY_MATCH"]
        return (value?.isEmpty ?? true) ? nil : value
    }

    /// Opens the match this run is about.
    ///
    /// **Never substitutes.** When a match is named and cannot be found, the
    /// run fails and says so rather than opening a different one. A result from
    /// some other match is not a result about the one under test, and a device
    /// carrying several would otherwise report a pass for the wrong game.
    ///
    /// Only when no match is named does it take the first that opens onto a
    /// board; a row without one is a search, not a game.
    @MainActor
    private func openAMatch(_ app: XCUIApplication) -> Bool {
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'online.match.'"))
        guard rows.firstMatch.waitForExistence(timeout: 20) else {
            XCTFail("no online match on this device to open")
            return false
        }

        if let targetMatch {
            let wanted = rows.allElementsBoundByIndex.first { $0.identifier.hasSuffix(targetMatch) }
            guard let wanted else {
                let found = rows.allElementsBoundByIndex.map(\.identifier).joined(separator: ", ")
                XCTFail("the match under test is not here: " + targetMatch
                    + ". Rows: [" + found + "]. Not substituting another match.")
                return false
            }
            print("TURN TARGET " + wanted.identifier)
            wanted.tap()
            guard app.descendants(matching: .any)["board.status"].waitForExistence(timeout: 30) else {
                XCTFail("the match under test did not open onto a board")
                return false
            }
            return true
        }

        for row in rows.allElementsBoundByIndex where row.isHittable {
            row.tap()
            if app.descendants(matching: .any)["board.status"].waitForExistence(timeout: 25) {
                return true
            }
            if app.descendants(matching: .any)["online.screen"].exists { continue }
        }
        XCTFail("no row opened onto a board")
        return false
    }

    // MARK: - Taking stock

    /// Lists what this device holds, without opening anything.
    ///
    /// Used to find the match an invitation created: it is the one that appears
    /// on **both** devices with two of two seats filled. Identifying it that way
    /// needs no snapshot taken beforehand, and cannot be confused with the
    /// three-seat table or with any of the one-seat searches.
    @MainActor
    func testListMatches() throws {
        let app = launched()
        guard openOnline(app) else { return }
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'online.match.'"))
        _ = rows.firstMatch.waitForExistence(timeout: 20)
        for row in rows.allElementsBoundByIndex {
            print("TURN ROW " + row.identifier + " :: " + row.label)
        }
        log(app, "inventory")
    }

    /// Every card in the hand, by identifier.
    @MainActor
    private func cardIdentifiers(in app: XCUIApplication) -> [String] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'hand.card.'"))
            .allElementsBoundByIndex
            .map(\.identifier)
    }

    /// Where every piece is drawn, by identifier.
    ///
    /// Read from the screen rather than from the model on purpose: the defect
    /// was that the model moved and the screen did not, so a check that asked
    /// the model would have passed while the board sat there unchanged.
    @MainActor
    private func pawnPositions(in app: XCUIApplication) -> [String: CGRect] {
        var positions: [String: CGRect] = [:]
        for pawn in app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'pawn.'"))
            .allElementsBoundByIndex where pawn.exists {
            positions[pawn.identifier] = pawn.frame
        }
        return positions
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
        // Recorded before the move so the two can be compared afterwards.
        let handBefore = cardIdentifiers(in: app)
        let pawnsBefore = pawnPositions(in: app)

        var didPlay = false
        let cards = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'hand.card.'"))
            .allElementsBoundByIndex

        for card in cards where !didPlay {
            card.tap()
            let targets = app.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH 'target.' AND NOT identifier BEGINSWITH 'target.leg.'"
            ))
            if let target = targets.allElementsBoundByIndex.first {
                target.tap()
                didPlay = true
                break
            }
            for pawn in app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'pawn.'"))
                .allElementsBoundByIndex where pawn.isHittable && !didPlay {
                pawn.tap()
                if let target = targets.allElementsBoundByIndex.first {
                    target.tap()
                    didPlay = true
                }
            }
        }

        XCTAssertTrue(didPlay, "this hand offered no move at all, which a forced-move rule forbids")

        // The defect this run exists to disprove: the card leaves the hand and
        // the piece stays where it was. Both halves are checked, because only
        // checking the card is what let it ship.
        let handAfter = cardIdentifiers(in: app)
        XCTAssertLessThan(
            handAfter.count, handBefore.count,
            "the card was never taken out of the hand"
        )
        let pawnsAfter = pawnPositions(in: app)
        XCTAssertNotEqual(
            pawnsAfter, pawnsBefore,
            "the card went but every piece stayed exactly where it was — the card/pawn desync"
        )
        // Exactly which card, and exactly which piece. Reported rather than
        // summarised, because coverage that is claimed instead of observed is
        // worth nothing — an online deal cannot be contrived, so whatever this
        // hand happened to hold is all that was really tested.
        let played = Set(handBefore).subtracting(handAfter)
        let moved = pawnsAfter.filter { pawnsBefore[$0.key] != $0.value }
        print("TURN CARD \(played.sorted().joined(separator: ","))")
        for (pawn, frame) in moved.sorted(by: { $0.key < $1.key }) {
            let was = pawnsBefore[pawn].map { "\(Int($0.midX)),\(Int($0.midY))" } ?? "?"
            print("TURN PAWN \(pawn) from=\(was) to=\(Int(frame.midX)),\(Int(frame.midY))")
        }
        print("TURN PAWNS moved=\(moved.count)")
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
