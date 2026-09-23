import CoreImage
import UIKit
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

    /// Puts the device back the way it was found.
    ///
    /// `XCUIDevice.shared.orientation` is **global to the test run**, not to
    /// the test that set it, and this suite rotates for most of its captures.
    /// Leaving it rotated hands whatever runs next a device on its side — and
    /// on a small phone that is not a cosmetic difference, it is a different
    /// layout with the hand beside the board rather than beneath it.
    ///
    /// This is not known to cause ISS-020; running a landscape capture
    /// immediately before the test that fails does not reproduce it. It is
    /// here because a suite that leaves global state behind is wrong whether
    /// or not it is today's culprit, and because ruling it out cost a run that
    /// this would have made unnecessary.
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
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
            "-KEEZLY_UI_TEST_RESET_STATE", "YES",
            "-KEEZLY_UI_TESTING",
            "-KEEZLY_SEATS", String(seats),
            "-KEEZLY_SEED", String(seed),
        ] + extra
        // Set before launching, which is what actually rotates this app.
        // Assigning it to an already-running app was tried and does nothing
        // here, and `app.frame` reports the rotation either way, so it cannot
        // be used to tell whether one happened.
        XCUIDevice.shared.orientation = orientation
        app.launch()
        return app
    }

    /// Captures the app the right way up, and checks that it is.
    ///
    /// **ISS-009 and ISS-012.** The two capture sources do *not* behave the
    /// same way, which is what both defects came down to. Measured on a
    /// rotated iPad, with `app.frame` reporting 1376×1032:
    ///
    /// | Source | Result |
    /// |---|---|
    /// | `app.screenshot()` | 2064×2752 — portrait, and a quarter of it black |
    /// | `XCUIScreen.main.screenshot()` | 2752×2064 — landscape, complete |
    ///
    /// **That second row no longer holds on this toolchain.** Measured again
    /// on a rotated iPad Pro 13-inch: the screen capture now comes back
    /// 2064×2752 as well — the whole landscape screen, complete, but stored in
    /// the unrotated framebuffer and so lying on its side. The app really is
    /// laid out in landscape in it; only the frame is the wrong way round.
    ///
    /// Which is exactly what the turn below is for, and why it was kept as a
    /// guard rather than deleted when it stopped firing.
    ///
    /// The application element's capture is the region of the *unrotated*
    /// framebuffer that the element claims, so on a rotated device it comes
    /// back on its side with the remainder filled in black. The screen's
    /// capture is the screen. So the screen is what is used.
    ///
    /// The turn below is kept as a guard rather than deleted: if a capture ever
    /// disagrees with the orientation that was asked for it is corrected, and
    /// the assertions fail loudly if it cannot be. That is what stops ISS-009
    /// returning unnoticed.
    @MainActor
    private func attach(_ name: String, from _: XCUIApplication, orientation: UIDeviceOrientation) {
        let raw = Self.flattened(XCUIScreen.main.screenshot())
        let needsTurning = orientation.isLandscape && raw.size.width < raw.size.height
        let image = needsTurning ? Self.turned(raw, clockwise: orientation == .landscapeLeft) : raw
        let size = image.size

        if needsTurning {
            XCTAssertNotEqual(
                size, raw.size,
                "\(name): the capture could not be turned and is still on its side (ISS-009)"
            )
        }
        if orientation.isLandscape {
            XCTAssertGreaterThan(
                size.width, size.height,
                "\(name): a landscape capture must be wider than it is tall — got \(size) (ISS-009)"
            )
        } else if orientation.isPortrait {
            XCTAssertGreaterThan(
                size.height, size.width,
                "\(name): a portrait capture must be taller than it is wide — got \(size)"
            )
        }

        // **The turned image's own PNG bytes, not the `UIImage`.**
        //
        // `XCTAttachment(image:)` does not carry what was handed to it here:
        // every capture in a whole exported set came out 2064x2752 — the raw
        // portrait framebuffer — including the ones this function had just
        // asserted were landscape. The assertions passed, because they measure
        // the image in memory, and the file that a reviewer or App Store
        // Connect would actually see was the uncorrected one.
        //
        // That is worth stating plainly: an in-test assertion about a capture
        // proves nothing about the capture that ships. It is the whole reason
        // the set is now exported to files and checked as files
        // (`scripts/screenshots-verify.py`), and the reason this line encodes
        // the bytes itself.
        guard let png = image.pngData() else {
            XCTFail("\(name): the capture could not be encoded as PNG")
            return
        }

        // **Measured after encoding, on the bytes themselves.**
        //
        // Everything above this line measures a `UIImage`, and a `UIImage` can
        // report one size while its bytes carry another — orientation is
        // metadata. Every assertion in this function passed while the exported
        // file was the uncorrected portrait capture, so the only measurement
        // worth making is the one on what is actually written.
        let encoded = UIImage(data: png)?.size ?? .zero
        XCTAssertEqual(
            encoded, size,
            "\(name): the attached bytes are \(encoded) but the image was \(size) — "
                + "the correction did not survive encoding (ISS-012)"
        )

        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A screenshot as an image whose **pixels** are what its size says.
    ///
    /// Two separate traps, and the second one is the expensive one.
    ///
    /// `XCUIScreenshot.image` can arrive without a `cgImage`, which made every
    /// attempt to turn it quietly return the original. Decoding the API's own
    /// PNG gives a bitmap-backed image.
    ///
    /// **And that decoded image lies about its shape.** On a rotated iPad its
    /// `size` reports 2752×2064 — landscape, correct — while the bytes behind
    /// it are 2064×2752 portrait plus an orientation tag. UIKit honours the
    /// tag, so every measurement inside this file agreed the capture was
    /// landscape. Nothing else honours it: `Pillow` reads the exported file as
    /// portrait, and so would App Store Connect.
    ///
    /// The evidence was a file of **2,550,479 bytes** that the test measured as
    /// 2752×2064 and the disk measured as 2064×2752 — the same bytes, read two
    /// ways. `scripts/screenshots-verify.py` is what made that visible, and it
    /// is the argument for checking captures as files in one line.
    ///
    /// So an image that is not already upright is redrawn, which puts the
    /// orientation into the pixels and leaves nothing for a reader to
    /// interpret.
    private static func flattened(_ screenshot: XCUIScreenshot) -> UIImage {
        let decoded = UIImage(data: screenshot.pngRepresentation) ?? screenshot.image
        guard decoded.imageOrientation != .up || decoded.cgImage == nil else { return decoded }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = decoded.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: decoded.size, format: format).image { _ in
            decoded.draw(in: CGRect(origin: .zero, size: decoded.size))
        }
    }

    /// Turns an image a quarter turn, moving the pixels.
    ///
    /// `clockwise` describes the device orientation being corrected for, not
    /// the direction of the transform below — see the note inside.
    ///
    /// Three other routes were tried first and every one failed *silently*,
    /// returning the original image: `UIImage.draw(in:)` inside a rotated
    /// context (its own flip cancels the rotation), a `CGContext` built from
    /// the screenshot's bitmap description (would not create), and Core Image
    /// (`createCGImage` returned nil in the test process). `UIImage.pngData()`
    /// does not bake an orientation in either. That is why the assertion in
    /// `attach` checks the size actually changed.
    ///
    /// Tagging an orientation would not be enough in any case: a tag survives
    /// `UIImage` and nothing else, so the PNG reaching a reviewer or App Store
    /// Connect would still be on its side.
    ///
    /// Only `.landscapeLeft` is verified, because it is the only landscape the
    /// harness uses.
    private static func turned(_ image: UIImage, clockwise: Bool) -> UIImage {
        guard let source = image.cgImage else { return image }

        // Re-encoding through PNG is what actually moves the pixels.
        // `UIImage.pngData()` writes the image as its orientation says it
        // should be seen, so decoding that data gives a plain upright bitmap.
        // Three other routes were tried first and all failed silently: a
        // rotated graphics context (cancelled by the flip `draw(in:)` applies),
        // a hand-built `CGContext` (would not create), and Core Image
        // (`createCGImage` returned nil in the test process).
        let target = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true

        return UIGraphicsImageRenderer(size: target, format: format).image { rendered in
            let context = rendered.cgContext
            context.translateBy(x: target.width / 2, y: target.height / 2)
            context.rotate(by: clockwise ? -.pi / 2 : .pi / 2)
            // The vertical flip is not a mistake. `CGContext.draw` applies its
            // own inversion inside a `UIGraphicsImageRenderer`, and this
            // cancels it. The pair was settled by rendering all four
            // quarter-turn combinations and looking at them, rather than by
            // reasoning about three stacked coordinate systems — the other
            // three come out upside down or mirrored.
            context.scaleBy(x: 1, y: -1)
            context.draw(
                source,
                in: CGRect(
                    x: -image.size.width / 2, y: -image.size.height / 2,
                    width: image.size.width, height: image.size.height
                )
            )
        }
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
        // A rotation is not instant, and a capture taken while one is in
        // flight catches the app still laid out for the old size.
        Thread.sleep(forTimeInterval: 1.5)
        attach(name, from: app, orientation: orientation)
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

    /// Two seats is the table with no quiet centre: the home lanes run almost
    /// to the middle and the medallion is deliberately absent (ISS-008). It
    /// needs looking at as a board in its own right, not as a smaller four.
    @MainActor
    func testTwoPlayerLandscape() {
        capture(name: "two-players-landscape", seats: 2, seed: 11, orientation: .landscapeLeft)
    }

    @MainActor
    func testTwoPlayerPortrait() {
        capture(name: "two-players-portrait", seats: 2, seed: 11, orientation: .portrait)
    }

    // MARK: - The menu

    /// Where a player actually starts, so it is reviewed like any other screen.
    @MainActor
    func testMenu() {
        let name = "menu"
        let app = XCUIApplication()
        app.launchArguments = ["-KEEZLY_UI_TEST_RESET_STATE", "YES"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["menu.start"].waitForExistence(timeout: 20),
            "\(name): the menu never appeared"
        )
        attach(name, from: app, orientation: .landscapeLeft)
    }

    /// The online screen, which is a shipping feature and therefore reviewed.
    ///
    /// Captured in the signed-out state on purpose. A deterministic run never
    /// authenticates — a Game Center sheet over the board would fail the run
    /// and, worse, be shipped to the App Store — so what this shows is exactly
    /// what a player sees before they sign in, which is a real screen and not
    /// a mock-up. No invented match data, because there is none.
    @MainActor
    func testOnlineMenu() {
        let name = "online-menu"
        let app = XCUIApplication()
        app.launchArguments = ["-KEEZLY_UI_TEST_RESET_STATE", "YES"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()

        let online = app.descendants(matching: .any)["menu.online"]
        XCTAssertTrue(online.waitForExistence(timeout: 20), "\(name): the menu never appeared")
        online.tap()

        // Any of the screen's own controls will do. Which one is on screen
        // depends on what Game Center says, and a deterministic run must not
        // depend on that answer — it only has to be the online screen.
        let anything = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'online.'"))
            .firstMatch
        XCTAssertTrue(
            anything.waitForExistence(timeout: 15),
            "\(name): the online screen never appeared"
        )
        attach(name, from: app, orientation: .landscapeLeft)
    }

    /// The rulebook on a large display, for the iPad series.
    ///
    /// The phone gets its own portrait capture of the same screen. Both exist
    /// because the two store series are one orientation each: a sequence that
    /// flips halfway looks like a mistake even when every image in it is right.
    @MainActor
    func testRulebookLandscape() {
        let name = "rulebook-landscape"
        let app = XCUIApplication()
        app.launchArguments = ["-KEEZLY_UI_TEST_RESET_STATE", "YES"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()

        let rules = app.descendants(matching: .any)["menu.rules"]
        XCTAssertTrue(rules.waitForExistence(timeout: 20), "\(name): the menu never appeared")
        rules.tap()

        let sheet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'rulebook'"))
            .firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 15), "\(name): the rulebook never appeared")
        attach(name, from: app, orientation: .landscapeLeft)
    }

    // MARK: - Portrait, for the phone series

    /// Five scenes that only existed in landscape, captured again in portrait.
    ///
    /// The App Store series for a phone must be one orientation throughout. A
    /// sequence that flips between portrait and landscape looks like a mistake
    /// even when every image in it is right, and a phone is held upright — so
    /// these five exist for the iPhone series, and the landscape originals stay
    /// for the iPad one. Both are real captures of the same screens; neither is
    /// a crop of the other.
    @MainActor
    func testMenuPortrait() {
        let name = "phone-menu-portrait"
        let app = XCUIApplication()
        app.launchArguments = ["-KEEZLY_UI_TEST_RESET_STATE", "YES"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["menu.start"].waitForExistence(timeout: 20),
            "\(name): the menu never appeared"
        )
        attach(name, from: app, orientation: .portrait)
    }

    @MainActor
    func testOnlineMenuPortrait() {
        let name = "phone-online-menu-portrait"
        let app = XCUIApplication()
        app.launchArguments = ["-KEEZLY_UI_TEST_RESET_STATE", "YES"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()

        let online = app.descendants(matching: .any)["menu.online"]
        XCTAssertTrue(online.waitForExistence(timeout: 20), "\(name): the menu never appeared")
        online.tap()

        let anything = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'online.'"))
            .firstMatch
        XCTAssertTrue(anything.waitForExistence(timeout: 15), "\(name): the online screen never appeared")
        attach(name, from: app, orientation: .portrait)
    }

    @MainActor
    func testFreeForAllPortrait() {
        capture(
            name: "phone-free-for-all-portrait",
            seats: 4,
            seed: 2026,
            orientation: .portrait,
            extra: ["-KEEZLY_TEAMS", "free"]
        )
    }

    @MainActor
    func testJackTargetsPortrait() {
        let name = "phone-jack-swap-portrait"
        let app = launch(seats: 4, seed: 2026, orientation: .portrait, extra: ["-KEEZLY_OPENING", "jack"])
        waitForDeal(app, name)

        let jack = elements(app, prefix: "hand.card.J.").first
        XCTAssertNotNil(jack, "\(name): the fixture did not produce a Jack in hand")
        jack?.tap()

        // A Jack needs its own pawn chosen before the swap targets appear —
        // the same two-step the landscape capture does, and the same one
        // ISS-020 turned on. Omitting it is why this failed the first time.
        for pawn in elements(app, prefix: "pawn.") where pawn.isHittable {
            pawn.tap()
            if !elements(app, prefix: "target.").isEmpty { break }
        }

        XCTAssertFalse(elements(app, prefix: "target.").isEmpty, "\(name): no swap target was offered")
        attach(name, from: app, orientation: .portrait)
    }

    @MainActor
    func testSevenMidSplitPortrait() {
        let name = "phone-seven-split-portrait"
        let app = launch(seats: 4, seed: 2026, orientation: .portrait, extra: ["-KEEZLY_OPENING", "seven"])
        waitForDeal(app, name)

        let seven = elements(app, prefix: "hand.card.7.").first
        XCTAssertNotNil(seven, "\(name): the fixture did not produce a Seven in hand")
        seven?.tap()

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
        attach(name, from: app, orientation: .portrait)
    }

    /// The rulebook, which is half of why the app exists.
    ///
    /// Keezen is a game people learn from each other, and the argument usually
    /// starts before the first card. A series that never shows the rules is
    /// missing the answer to "but how do you actually play it".
    @MainActor
    func testRulebookPortrait() {
        let name = "phone-rulebook-portrait"
        let app = XCUIApplication()
        app.launchArguments = ["-KEEZLY_UI_TEST_RESET_STATE", "YES"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()

        let rules = app.descendants(matching: .any)["menu.rules"]
        XCTAssertTrue(rules.waitForExistence(timeout: 20), "\(name): the menu never appeared")
        rules.tap()

        let sheet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'rulebook'"))
            .firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 15), "\(name): the rulebook never appeared")
        attach(name, from: app, orientation: .portrait)
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
        attach(name, from: app, orientation: .landscapeLeft)
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
        attach(name, from: app, orientation: .landscapeLeft)
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
