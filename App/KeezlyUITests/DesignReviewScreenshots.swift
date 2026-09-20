import XCTest

/// Captures the screens a design review needs, in the orientations that matter.
///
/// The beginning of the screenshot harness (§86): the app is launched in a
/// deterministic mode with a fixed seed and seat count, so the same board comes
/// out every run. Attached to the result bundle rather than written to disk, so
/// a CI run keeps them as artefacts.
///
/// Not part of the default test matrix — it is run deliberately:
///
///     xcodebuild test -only-testing:KeezlyUITests/DesignReviewScreenshots
final class DesignReviewScreenshots: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    private func capture(
        name: String,
        seats: Int,
        seed: Int,
        orientation: UIDeviceOrientation
    ) {
        let app = XCUIApplication()
        app.launchArguments = [
            "-KEEZLY_UI_TESTING",
            "-KEEZLY_SEATS", String(seats),
            "-KEEZLY_SEED", String(seed),
        ]
        XCUIDevice.shared.orientation = orientation
        app.launch()

        // Wait until the deal has actually happened, so a screenshot never
        // catches an empty table.
        let hand = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'hand.card.'"))
            .firstMatch
        XCTAssertTrue(hand.waitForExistence(timeout: 20), "\(name): no hand was dealt")

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

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
}
