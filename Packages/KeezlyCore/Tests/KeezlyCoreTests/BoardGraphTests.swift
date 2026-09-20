import Testing
@testable import KeezlyCore

/// §9 — the parametric board must be fair and closed for every table size.
@Suite("BoardGraph")
struct BoardGraphTests {

    @Test("main track scales at 16 squares per seat", arguments: 2...6)
    func trackLength(seatCount: Int) {
        let board = BoardGraph(seatCount: seatCount)
        #expect(board.mainTrackCount == seatCount * 16)
    }

    @Test("the classic four-player board has 96 positions")
    func classicBoardSize() {
        let board = BoardGraph(seatCount: 4)
        #expect(board.mainTrackCount == 64)
        #expect(board.positionCount == 96)   // 64 track + 16 waiting + 16 home
    }

    @Test("start squares are spread evenly around the track", arguments: 2...6)
    func startSquaresEvenlySpaced(seatCount: Int) {
        let board = BoardGraph(seatCount: seatCount)
        let starts = board.seats.map(board.startIndex(for:))
        #expect(Set(starts).count == seatCount)
        for (a, b) in zip(starts, starts.dropFirst()) {
            #expect(b - a == BoardGraph.squaresPerSeatSegment)
        }
    }

    @Test("every seat travels exactly the same distance", arguments: 2...6)
    func journeyLengthIsIdenticalPerSeat(seatCount: Int) {
        let board = BoardGraph(seatCount: seatCount)
        for seat in board.seats {
            let start = board.startIndex(for: seat)
            #expect(board.progress(ofTrackIndex: start, for: seat) == 0)
            #expect(board.progress(ofTrackIndex: board.homeEntryIndex(for: seat), for: seat) == board.lapLength)
            #expect(board.fullJourneyLength == board.mainTrackCount - 1 + pawnsPerSeat)
        }
    }

    @Test("home entry sits one square before the seat's own start", arguments: 2...6)
    func homeEntryIsJustBeforeStart(seatCount: Int) {
        let board = BoardGraph(seatCount: seatCount)
        for seat in board.seats {
            let entry = board.homeEntryIndex(for: seat)
            let next = (entry + 1) % board.mainTrackCount
            #expect(next == board.startIndex(for: seat))
        }
    }

    @Test("walking the full journey visits every track square then all of home", arguments: 2...6)
    func fullJourneyIsClosed(seatCount: Int) {
        let board = BoardGraph(seatCount: seatCount)
        for seat in board.seats {
            var visitedTrack: [Int] = []
            var visitedHome: [Int] = []
            for step in 0...board.fullJourneyLength {
                guard let position = board.position(atProgress: step, for: seat) else {
                    Issue.record("progress \(step) produced no position for \(seat)")
                    continue
                }
                switch position {
                case .track(let index): visitedTrack.append(index)
                case .home(let homeSeat, let slot):
                    #expect(homeSeat == seat)
                    visitedHome.append(slot)
                case .waiting:
                    Issue.record("a journey must never lead back into the waiting area")
                }
            }
            // Every shared square exactly once, then home 0...3 in order.
            #expect(visitedTrack.count == board.mainTrackCount)
            #expect(Set(visitedTrack).count == board.mainTrackCount)
            #expect(visitedHome == Array(0..<pawnsPerSeat))
        }
    }

    @Test("progress and trackIndex are exact inverses", arguments: 2...6)
    func progressRoundTrips(seatCount: Int) {
        let board = BoardGraph(seatCount: seatCount)
        for seat in board.seats {
            for index in 0..<board.mainTrackCount {
                let p = board.progress(ofTrackIndex: index, for: seat)
                #expect(board.trackIndex(atProgress: p, for: seat) == index)
            }
        }
    }

    @Test("a forward move that would overshoot home is not a move at all")
    func overshootingHomeIsNotAPath() {
        let board = BoardGraph(seatCount: 4)
        let seat = Seat(0)
        // One square short of the deepest home square.
        let deepest = BoardPosition.home(seat: seat, slot: 2)
        #expect(board.forwardPath(from: deepest, steps: 1, for: seat) != nil)
        #expect(board.forwardPath(from: deepest, steps: 2, for: seat) == nil)
    }

    @Test("backward paths stay on the shared track and wrap cleanly")
    func backwardWrapsWithoutEnteringHome() {
        let board = BoardGraph(seatCount: 4)
        // Two squares past seat 0's start, moving four back, wraps to 62.
        let path = board.backwardPath(from: .track(index: 2), steps: 4)
        #expect(path == [.track(index: 1), .track(index: 0), .track(index: 63), .track(index: 62)])
        // Home and waiting pawns have no backward path at all (§16).
        #expect(board.backwardPath(from: .home(seat: Seat(0), slot: 1), steps: 4) == nil)
        #expect(board.backwardPath(from: .waiting(seat: Seat(0), slot: 0), steps: 4) == nil)
    }
}
