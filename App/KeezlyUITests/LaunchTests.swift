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

    @MainActor
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.staticTexts["KEEZLY"].waitForExistence(timeout: 10),
            "the app should present its root scene within ten seconds"
        )
    }

    @MainActor
    func testAppSurvivesRotation() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["KEEZLY"].waitForExistence(timeout: 10))

        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait, .landscapeRight, .portrait] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(
                app.staticTexts["KEEZLY"].waitForExistence(timeout: 5),
                "the root scene should survive rotation to \(orientation.rawValue)"
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
