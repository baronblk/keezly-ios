import XCTest

/// Launch-level UI tests.
///
/// The screenshot harness and the real gameplay UI tests arrive with M4/M11.4.
/// Until then these prove the far more basic thing that the build, install and
/// launch path works on a simulator or a real device — which is what the
/// physical-device smoke gate depends on (§170).
///
/// The test methods are `@MainActor` because `XCUIApplication` and `XCUIDevice`
/// are main-actor isolated under Swift 6. `setUp` deliberately is not: it only
/// touches `XCTestCase` state, and isolating it would not match the override.
final class LaunchTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The clearest sign the app is up and a match is running: the local
    /// player has been dealt a hand.
    @MainActor
    private func handAppeared(in app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'hand.card.'"))
            .firstMatch
            .waitForExistence(timeout: timeout)
    }

    /// Launched onto a fixed table, because a plain launch now opens the menu
    /// — which `MenuFlowTests` covers.
    @MainActor
    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-KEEZLY_UI_TEST_RESET_STATE", "YES",
            "-KEEZLY_UI_TESTING", "-KEEZLY_SEATS", "4", "-KEEZLY_SEED", "2026",
        ]
        app.launch()
        return app
    }

    @MainActor
    func testAppLaunches() {
        let app = launched()
        XCTAssertTrue(handAppeared(in: app), "the app should deal a hand within fifteen seconds")
    }

    @MainActor
    func testAppSurvivesRotation() {
        let app = launched()
        XCTAssertTrue(handAppeared(in: app))

        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait, .landscapeRight, .portrait] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(
                handAppeared(in: app, timeout: 8),
                "the board should survive rotation to \(orientation.rawValue)"
            )
        }
    }

    @MainActor
    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
