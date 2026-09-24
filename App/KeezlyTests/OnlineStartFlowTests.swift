@testable import Keezly
import Testing

/// The stretch between tapping "New online match" and having one.
///
/// This suite exists because of a P0 found on real hardware: the button was
/// tapped, a spinner ran for about two seconds, and then nothing at all
/// happened — no match, no matchmaker, no message, nothing to retry. Two
/// separate defects produced that single symptom, and both are pinned here.
///
/// 1. The whole flow was one `Bool`. A boolean cannot tell "Game Center is
///    opening" from "waiting for a second player" from "that did not work", so
///    the screen could not draw the difference and the player was shown a bare
///    spinner for all three.
/// 2. The error was discarded by its own `catch`, and the recovery call then
///    cleared the only field a message could have appeared in.
///
/// Everything here runs without GameKit, an account, a second player or a
/// network, which is the point: these are the cases that are hardest to reach
/// on a device and easiest to get wrong.
@Suite("Online start flow")
struct OnlineStartFlowTests {

    private func next(_ state: OnlineStartState, _ event: OnlineStartEvent) -> OnlineStartState {
        OnlineStartFlow.next(from: state, on: event)
    }

    // MARK: - The happy path

    @Test("tapping while signed in opens the matchmaker")
    func tapOpensMatchmaker() {
        #expect(next(.idle, .tapped(isAuthenticated: true)) == .openingMatchmaker)
    }

    @Test("the full path ends with a board and an idle screen")
    func fullPath() {
        var state = OnlineStartState.idle
        state = next(state, .tapped(isAuthenticated: true))
        #expect(state == .openingMatchmaker)
        state = next(state, .matchmakerShown)
        #expect(state == .matchmaking)
        state = next(state, .matchArrived(filled: 4, of: 4))
        #expect(state == .loadingMatch)
        state = next(state, .matchOpened)
        #expect(state == .idle)
    }

    // MARK: - The defect: nothing visible ever happens

    /// The heart of it. Every state that is not `idle` owes the player a
    /// sentence; a spinner on its own is what made this defect invisible.
    @Test("every busy state has something to say")
    func everyBusyStateSaysSomething() {
        let busy: [OnlineStartState] = [
            .authenticating, .openingMatchmaker, .matchmaking,
            .waitingForPlayers(filled: 1, of: 4), .loadingMatch,
        ]
        for state in busy {
            #expect(state.progressKey != nil, "\(state) would show a spinner with no explanation")
        }
    }

    @Test("a failure always carries a message")
    func everyFailureHasAMessage() {
        let failures: [OnlineStartFailure] = [
            .notSignedIn, .unavailable, .cancelled, .matchmakingFailed,
            .couldNotCreate, .couldNotLoad, .network,
        ]
        for failure in failures {
            #expect(failure.messageKey.hasPrefix("online.fail."))
            #expect(!failure.messageKey.isEmpty)
        }
    }

    /// A failure must never land back on `idle` looking like nothing happened.
    /// That is precisely what the old code did.
    @Test("a failure worth showing is shown, not swallowed")
    func failuresAreNotSwallowed() {
        let shown: [OnlineStartFailure] = [
            .notSignedIn, .unavailable, .matchmakingFailed,
            .couldNotCreate, .couldNotLoad, .network,
        ]
        for failure in shown {
            #expect(next(.matchmaking, .failed(failure)) == .failed(failure))
            #expect(next(.loadingMatch, .failed(failure)) == .failed(failure))
        }
    }

    @Test("tapping while not signed in says so instead of spinning")
    func notSignedInIsVisible() {
        #expect(next(.idle, .tapped(isAuthenticated: false)) == .failed(.notSignedIn))
    }

    // MARK: - Cancelling is not a failure

    @Test("cancelling the matchmaker returns to idle without an error")
    func cancellingIsQuiet() {
        #expect(next(.matchmaking, .matchmakerCancelled) == .idle)
        #expect(next(.openingMatchmaker, .matchmakerCancelled) == .idle)
        #expect(next(.matchmaking, .failed(.cancelled)) == .idle)
        #expect(OnlineStartFailure.cancelled.isWorthShowing == false)
    }

    /// A late cancellation callback must not throw away a match that has
    /// already arrived. GameKit can deliver the two in either order.
    @Test("a cancellation arriving after the match does not discard it")
    func lateCancellationDoesNotDiscardTheMatch() {
        #expect(next(.loadingMatch, .matchmakerCancelled) == .loadingMatch)
        #expect(next(.waitingForPlayers(filled: 1, of: 4), .matchmakerCancelled)
                == .waitingForPlayers(filled: 1, of: 4))
    }

    @Test("a late matchmaker failure does not discard a match either")
    func lateFailureDoesNotDiscardTheMatch() {
        #expect(next(.loadingMatch, .matchmakerFailed) == .loadingMatch)
    }

    // MARK: - A match that is not full yet

    /// The second defect, as a rule. `GKTurnBasedMatch` hands back a match
    /// whose empty seats have no player in them, and the old code treated that
    /// as an error and threw. It is not an error: it is how a turn-based game
    /// works, and the honest answer is to say the match is waiting.
    @Test("a half-full match is a waiting state, not a failure")
    func halfFullIsNotAFailure() {
        let state = next(.matchmaking, .matchArrived(filled: 1, of: 4))
        #expect(state == .waitingForPlayers(filled: 1, of: 4))
        if case .failed = state { Issue.record("waiting for players was reported as a failure") }
    }

    @Test("waiting for players leaves the screen usable")
    func waitingIsNotBusy() {
        let state = OnlineStartState.waitingForPlayers(filled: 1, of: 4)
        #expect(state.isBusy == false, "the player must be able to do something else")
        #expect(state.progressKey != nil)
    }

    @Test("a full match loads instead of waiting", arguments: [2, 3, 4, 5, 6])
    func fullMatchLoads(seats: Int) {
        #expect(next(.matchmaking, .matchArrived(filled: seats, of: seats)) == .loadingMatch)
    }

    @Test("every partly filled table waits rather than failing", arguments: [2, 3, 4, 5, 6])
    func partiallyFilledWaits(seats: Int) {
        for filled in 1..<seats {
            #expect(next(.matchmaking, .matchArrived(filled: filled, of: seats))
                    == .waitingForPlayers(filled: filled, of: seats))
        }
    }

    // MARK: - Retrying

    @Test("retry is offered only where it could help")
    func retryWhereItHelps() {
        #expect(OnlineStartFailure.network.isWorthRetrying)
        #expect(OnlineStartFailure.matchmakingFailed.isWorthRetrying)
        #expect(OnlineStartFailure.couldNotCreate.isWorthRetrying)
        #expect(OnlineStartFailure.couldNotLoad.isWorthRetrying)
        // One is fixed in Settings, the other cannot be fixed at all.
        #expect(OnlineStartFailure.notSignedIn.isWorthRetrying == false)
        #expect(OnlineStartFailure.unavailable.isWorthRetrying == false)
    }

    @Test("a failed state can be left by tapping again")
    func failureIsRecoverable() {
        #expect(next(.failed(.network), .tapped(isAuthenticated: true)) == .openingMatchmaker)
        #expect(OnlineStartState.failed(.network).isBusy == false)
    }

    // MARK: - Nothing runs twice

    @Test("a second tap while busy changes nothing")
    func noDoubleStart() {
        for state in [OnlineStartState.openingMatchmaker, .matchmaking, .loadingMatch, .authenticating] {
            #expect(next(state, .tapped(isAuthenticated: true)) == state,
                    "\(state) started a second match")
        }
    }

    @Test("closing the screen always returns to idle")
    func dismissAlwaysResets() {
        for state in [OnlineStartState.openingMatchmaker, .matchmaking, .loadingMatch,
                      .failed(.network), .waitingForPlayers(filled: 1, of: 4)] {
            #expect(next(state, .dismissed) == .idle)
        }
    }

    // MARK: - A second player joining

    /// The transition the whole feature turns on, and the one that was broken
    /// for a different reason: `waitingForPlayers` must be a step, not a dead
    /// end. A match that fills up has to become a board.
    @Test("a two-seat table that fills up moves on to loading")
    func twoSeatTableFills() {
        var state = next(.matchmaking, .matchArrived(filled: 1, of: 2))
        #expect(state == .waitingForPlayers(filled: 1, of: 2))
        state = next(state, .matchArrived(filled: 2, of: 2))
        #expect(state == .loadingMatch, "the second player joined and nothing happened")
    }

    /// Three seats fill one at a time, and only the last one starts anything.
    @Test("a three-seat table waits through the middle and moves on at the end")
    func threeSeatTableFillsInSteps() {
        var state = next(.matchmaking, .matchArrived(filled: 1, of: 3))
        #expect(state == .waitingForPlayers(filled: 1, of: 3))

        state = next(state, .matchArrived(filled: 2, of: 3))
        #expect(state == .waitingForPlayers(filled: 2, of: 3), "two of three is still waiting")

        state = next(state, .matchArrived(filled: 3, of: 3))
        #expect(state == .loadingMatch)
    }

    @Test("every seat count fills the same way", arguments: [2, 3, 4, 5, 6])
    func everySeatCountFills(seats: Int) {
        var state = OnlineStartState.matchmaking
        for filled in 1..<seats {
            state = next(state, .matchArrived(filled: filled, of: seats))
            #expect(state == .waitingForPlayers(filled: filled, of: seats))
        }
        state = next(state, .matchArrived(filled: seats, of: seats))
        #expect(state == .loadingMatch)
    }

    /// GameKit re-delivers events. The same one twice must not undo anything.
    @Test("a duplicate event changes nothing")
    func duplicateEvent() {
        var state = next(.matchmaking, .matchArrived(filled: 1, of: 2))
        let afterFirst = state
        state = next(state, .matchArrived(filled: 1, of: 2))
        #expect(state == afterFirst)

        state = next(state, .matchArrived(filled: 2, of: 2))
        let loading = state
        state = next(state, .matchArrived(filled: 2, of: 2))
        #expect(state == loading, "a repeated full event restarted the load")
    }

    /// Events can arrive out of order. An older count must not drag a match
    /// that is already loading back to waiting.
    @Test("a stale event does not pull a loading match back to waiting")
    func staleEventDoesNotRegress() {
        var state = next(.matchmaking, .matchArrived(filled: 2, of: 2))
        #expect(state == .loadingMatch)
        state = next(state, .matchArrived(filled: 1, of: 2))
        #expect(state == .loadingMatch, "an out-of-order event undid a completed table")
    }

    /// Somebody declined or walked away, so the table will never fill. The
    /// count going down is real and is shown, rather than the screen claiming
    /// progress that has been lost.
    @Test("a participant leaving is reflected rather than hidden")
    func participantLeft() {
        var state = next(.matchmaking, .matchArrived(filled: 2, of: 3))
        #expect(state == .waitingForPlayers(filled: 2, of: 3))
        state = next(state, .matchArrived(filled: 1, of: 3))
        #expect(state == .waitingForPlayers(filled: 1, of: 3))
    }

    /// Once the board is open the screen is idle, and a turn event for some
    /// other match — an opponent moving in a different game — must not put a
    /// loading state behind it.
    @Test("a match that opened is not reopened by a later event")
    func openedStaysOpen() {
        var state = next(.matchmaking, .matchArrived(filled: 2, of: 2))
        state = next(state, .matchOpened)
        #expect(state == .idle)
        #expect(next(state, .matchArrived(filled: 2, of: 2)) == .idle)
    }

    @Test("an event arriving while an error is shown does not replace it")
    func eventDoesNotClearAnError() {
        #expect(next(.failed(.network), .matchArrived(filled: 2, of: 2)) == .failed(.network))
    }

    @Test("only what is actually in progress can be cancelled")
    func cancellableStates() {
        #expect(OnlineStartState.openingMatchmaker.isCancellable)
        #expect(OnlineStartState.matchmaking.isCancellable)
        #expect(OnlineStartState.loadingMatch.isCancellable)
        #expect(OnlineStartState.idle.isCancellable == false)
        #expect(OnlineStartState.failed(.network).isCancellable == false)
        // Nothing to cancel: the match exists and is simply waiting.
        #expect(OnlineStartState.waitingForPlayers(filled: 1, of: 4).isCancellable == false)
    }
}
