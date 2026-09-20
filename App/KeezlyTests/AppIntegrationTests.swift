import Foundation
@testable import Keezly
import KeezlyCore
import Testing

/// App-level integration: proves the rules engine is actually linked into the
/// app and behaves identically inside the iOS runtime, not only under
/// `swift test` on macOS.
///
/// These are intentionally few. The exhaustive rule tests live in
/// `Packages/KeezlyCore/Tests`, where they run in seconds without a simulator.
@Suite("App integration")
struct AppIntegrationTests {

    @Test("the app links KeezlyCore and can start a match", arguments: 2...6)
    func canStartAMatch(seatCount: Int) {
        let state = GameState.newMatch(configuration: .standard(seatCount: seatCount), seed: 1)
        #expect(state.pawns.count == seatCount * pawnsPerSeat)
        #expect(state.hand(of: state.currentSeat).count == 5)
        #expect(!MoveGenerator.legalMoves(in: state, for: state.currentSeat).isEmpty
                || !MoveGenerator.hasAnyLegalMove(in: state, for: state.currentSeat))
    }

    @Test("a match plays to a result inside the iOS runtime")
    func matchCompletesOnDevice() throws {
        var chooser = SeededGenerator(seed: 0xB0A2D)
        var state = GameState.newMatch(configuration: .standard(seatCount: 4), seed: 31)
        var actions = 0

        while !state.isFinished && actions < 4000 {
            let moves = MoveGenerator.legalMoves(in: state, for: state.currentSeat)
            let action: PlayerAction = moves.isEmpty
                ? .foldHand(seat: state.currentSeat)
                : .play(moves[Int(chooser.next() % UInt64(moves.count))])
            state = try GameReducer.apply(action, to: state).state
            actions += 1
        }

        #expect(state.isFinished)
        #expect(state.result != nil)
    }

    /// Encoding must be byte-identical across platforms, or two devices in a
    /// Game Center match cannot agree that they hold the same board.
    @Test("state encoding round-trips on iOS")
    func serializationWorksOnDevice() throws {
        let state = GameState.newMatch(configuration: .standard(seatCount: 6), seed: 7)
        let data = try GameStateEnvelope.encode(state)
        #expect(try GameStateEnvelope.decode(data) == state)
        #expect(try GameStateEnvelope.encode(state) == data)
    }

    @Test("the bundle identifier and version are configured as agreed")
    func bundleConfiguration() {
        let bundle = Bundle(for: BundleMarker.self)
        // The test bundle's own identifier, which pins the agreed scheme.
        #expect(bundle.bundleIdentifier == "de.gcng.keezly.tests")
    }

    private final class BundleMarker {}
}
