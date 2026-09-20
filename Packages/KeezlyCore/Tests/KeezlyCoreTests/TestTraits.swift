import Foundation
import Testing

/// Splits the fast suite from the expensive one (§112).
///
/// Large AI simulations take minutes, which is the wrong trade for a test run
/// that should finish in seconds after every edit. They stay in the repository
/// and run on demand:
///
///     KEEZLY_EXTENDED_SIM=1 swift test
///
/// Release and nightly runs set it; ordinary development does not.
extension Trait where Self == ConditionTrait {
    static var extendedSimulation: Self {
        .enabled(
            if: ProcessInfo.processInfo.environment["KEEZLY_EXTENDED_SIM"] == "1",
            "set KEEZLY_EXTENDED_SIM=1 to run extended AI simulations"
        )
    }
}
