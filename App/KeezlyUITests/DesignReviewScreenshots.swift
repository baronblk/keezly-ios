import XCTest

/// Captures the screens a design review needs, in the orientations that matter.
///
/// The screenshot harness (§86, §87): the app is launched in a deterministic
/// mode with a fixed seed, seat count and opening situation, so the same board
/// comes out every run. Attached to the result bundle rather than written to
/// disk, so a CI run keeps them as artefacts.
///
/// Not part of the default test matrix — it is run deliberately:
///
///     xcodebuild test -only-testing:KeezlyUITests/DesignReviewScreenshots
final class DesignReviewScreenshots: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Harness

    @MainActor
    private func launch(
        seats: Int,
        seed: Int,
        orientation: UIDeviceOrientation,
        extra: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-KEEZLY_UI_TESTING",
            "-KEEZLY_SEATS", String(seats),
            "-KEEZLY_SEED", String(seed),
        ] + extra
        XCUIDevice.shared.orientation = orientation
        app.launch()
        return app
    }

    @MainActor
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func elements(_ app: XCUIApplication, prefix: String) -> [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .allElementsBoundByIndex
    }

    /// Waits for the deal, so a capture never catches an empty table.
    @MainActor
    private func waitForDeal(_ app: XCUIApplication, _ name: String) {
        let hand = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'hand.card.'"))
            .firstMatch
        XCTAssertTrue(hand.waitForExistence(timeout: 20), "\(name): no hand was dealt")
    }

    @MainActor
    private func capture(
        name: String,
        seats: Int,
        seed: Int,
        orientation: UIDeviceOrientation,
        extra: [String] = []
    ) {
        let app = launch(seats: seats, seed: seed, orientation: orientation, extra: extra)
        waitForDeal(app, name)
        attach(name)
    }

    // MARK: - iPad

    @MainActor
    func testFourPlayerLandscape() {
        capture(name: "four-players-landscape", seats: 4, seed: 2026, orientation: .landscapeLeft)
    }

    @MainActor
    func testSixPlayerLandscape() {
        capture(name: "six-players-landscape", seats: 6, seed: 77, orientation: .landscapeLeft)
    }

    @MainActor
    func testFourPlayerPortrait() {
        capture(name: "four-players-portrait", seats: 4, seed: 2026, orientation: .portrait)
    }

    /// A four-seat table is partners by default, so nothing captured so far
    /// shows a board *without* a partner. The seat panels differ — this is the
    /// screen that proves it.
    @MainActor
    func testFreeForAllTable() {
        capture(
            name: "four-players-free-for-all",
            seats: 4,
            seed: 2026,
            orientation: .landscapeLeft,
            extra: ["-KEEZLY_TEAMS", "free"]
        )
    }

    /// An odd table is free-for-all by definition, and five seats is the
    /// geometry least like the classic board.
    @MainActor
    func testFivePlayerLandscape() {
        capture(name: "five-players-landscape", seats: 5, seed: 404, orientation: .landscapeLeft)
    }

    // MARK: - Mid-match interfaces

    /// The Jack, with its swap targets showing.
    ///
    /// Impossible at the opening deal — a swap needs two pawns already on the
    /// track — so the match is fast-forwarded to a position where the local
    /// seat holds a playable Jack (§87).
    @MainActor
    func testJackTargets() {
        let name = "jack-swap-targets"
        let app = launch(
            seats: 4,
            seed: 2026,
            orientation: .landscapeLeft,
            extra: ["-KEEZLY_OPENING", "jack"]
        )
        waitForDeal(app, name)

        let jack = elements(app, prefix: "hand.card.J.").first
        XCTAssertNotNil(jack, "\(name): the fixture did not produce a Jack in hand")
        jack?.tap()

        // A Jack needs its own pawn chosen before the swap targets appear.
        for pawn in elements(app, prefix: "pawn.") where pawn.isHittable {
            pawn.tap()
            if !elements(app, prefix: "target.").isEmpty { break }
        }

        XCTAssertFalse(elements(app, prefix: "target.").isEmpty, "\(name): no swap target was offered")
        attach(name)
    }

    /// A Seven halfway through its split, with the progress row showing how
    /// much is left to spend (§38).
    @MainActor
    func testSevenMidSplit() {
        let name = "seven-mid-split"
        let app = launch(
            seats: 4,
            seed: 2026,
            orientation: .landscapeLeft,
            extra: ["-KEEZLY_OPENING", "seven"]
        )
        waitForDeal(app, name)

        let seven = elements(app, prefix: "hand.card.7.").first
        XCTAssertNotNil(seven, "\(name): the fixture did not produce a Seven in hand")
        seven?.tap()

        // Only a leg-committing square leaves the split half-spent; a square
        // that would finish the move takes the board straight past the state
        // this screenshot is about.
        var legs = elements(app, prefix: "target.leg.")
        if legs.isEmpty {
            for pawn in elements(app, prefix: "pawn.") where pawn.isHittable {
                pawn.tap()
                legs = elements(app, prefix: "target.leg.")
                if !legs.isEmpty { break }
            }
        }
        XCTAssertFalse(legs.isEmpty, "\(name): no square offered to commit a leg")
        legs.first?.tap()

        let progress = app.descendants(matching: .any)["seven.progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10), "\(name): the split did not stay open")
        attach(name)
    }

    // MARK: - Phone

    @MainActor
    func testPhonePortrait() {
        capture(name: "phone-four-players-portrait", seats: 4, seed: 2026, orientation: .portrait)
    }

    @MainActor
    func testPhoneLandscape() {
        capture(name: "phone-four-players-landscape", seats: 4, seed: 2026, orientation: .landscapeLeft)
    }

    @MainActor
    func testPhoneSixPlayers() {
        capture(name: "phone-six-players-portrait", seats: 6, seed: 77, orientation: .portrait)
    }

    /// The phone mid-match, where the hand is fanned and the board is busy —
    /// the state an App Store screenshot actually needs (§88).
    @MainActor
    func testPhoneMidMatch() {
        capture(
            name: "phone-mid-match-portrait",
            seats: 4,
            seed: 2026,
            orientation: .portrait,
            extra: ["-KEEZLY_OPENING_MOVES", "24"]
        )
    }
}
