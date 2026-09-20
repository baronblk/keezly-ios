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

/// Gates wall-clock timing assertions.
///
/// A parallel test run saturates the machine, so a wall-clock bound measures
/// how long the runner took to schedule the work as much as how long the work
/// took. Such a test goes red for reasons that have nothing to do with the
/// code, which is the fastest way to train a team to ignore red.
///
/// Timing assertions therefore run deliberately, on an otherwise idle machine:
///
///     KEEZLY_TIMING_TESTS=1 swift test --filter <name>
///
/// The default suite keeps the *correctness* half of the same guarantees — a
/// cancelled or budget-exhausted search still returns a legal move — because
/// that part is not timing-sensitive at all.
extension Trait where Self == ConditionTrait {
    static var timingSensitive: Self {
        .enabled(
            if: ProcessInfo.processInfo.environment["KEEZLY_TIMING_TESTS"] == "1",
            "set KEEZLY_TIMING_TESTS=1 to run wall-clock timing assertions"
        )
    }
}
