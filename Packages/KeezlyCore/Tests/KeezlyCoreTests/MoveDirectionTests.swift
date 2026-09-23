@testable import KeezlyCore
import Testing

/// Die Richtung jeder Bewegung, für jeden Sitz und jede Tischgröße.
///
/// Gemessen wird **semantisch**: die Differenz im spielerrelativen `progress`,
/// nicht im globalen Feldindex und erst recht nicht auf dem Bildschirm. Auf
/// einem Ring liegt ein kleinerer Index nicht „hinter" einer Figur — deshalb
/// ist der globale Index als Richtungsmaß wertlos.
///
/// Anlass: auf echter Hardware wurden bei normalen Zügen rückwärts gerichtete
/// Bewegungen beobachtet. Diese Suite prüft die Regel, die das ausschließt:
/// **nur die Vier bewegt rückwärts.**
@Suite("Bewegungsrichtung")
struct MoveDirectionTests {

    /// Der erwartete Schrittwert einer Karte, oder `nil` wenn die Karte keine
    /// gewöhnliche Streckenbewegung erzeugt.
    private func expectedSteps(_ rank: CardRank) -> Int? {
        switch rank {
        case .ace: 1
        case .two: 2
        case .three: 3
        case .four: -4
        case .five: 5
        case .six: 6
        case .seven: nil     // Split, eigene Suite unten
        case .eight: 8
        case .nine: 9
        case .ten: 10
        case .jack: nil      // Tausch
        case .queen: 12
        case .king: nil      // Eintritt, +13 nur wenn das Ruleset es erlaubt
        }
    }

    /// Alle gewöhnlichen Streckenbewegungen, die eine Karte für einen Sitz
    /// erzeugt, als Differenz im spielerrelativen Fortschritt.
    private func progressDeltas(
        rank: CardRank,
        seatCount: Int,
        seat: Int,
        startProgress: Int
    ) -> [Int] {
        let board = BoardGraph(seatCount: seatCount)
        let s = Seat(seat)
        guard let start = board.position(atProgress: startProgress, for: s) else { return [] }

        let state = Fixture.state(
            seatCount: seatCount,
            pawns: [Fixture.pawn(seat, 0): start],
            hands: [seat: [rank]],
            currentSeat: seat
        )

        var deltas: [Int] = []
        for move in MoveGenerator.legalMoves(in: state, for: s) {
            // Einsetzen aus dem Wartebereich hat keinen sinnvollen
            // Fortschritts-Delta: die Figur kommt von außerhalb der Strecke.
            // Solche Züge bewegen ausserdem eine *andere* Figur, weshalb ein
            // naiver Vergleich für Figur 0 fälschlich 0 liefert — genau das
            // hat die erste Fassung dieses Tests getan und 93 Scheinbefunde
            // erzeugt.
            if case .enterFromWaiting = move.action { continue }
            guard let preview = try? GameReducer.apply(.play(move), to: state) else { continue }

            // Jede Figur prüfen, die sich tatsächlich bewegt hat.
            for slot in 0..<pawnsPerSeat {
                let id = Fixture.pawn(seat, slot)
                let before = state.pawn(id).position
                let after = preview.state.pawn(id).position
                guard before != after,
                      let from = board.progress(of: before, for: s),
                      let to = board.progress(of: after, for: s)
                else { continue }
                deltas.append(to - from)
            }
        }
        return deltas
    }

    // MARK: - Nur die Vier geht rückwärts

    @Test("keine Karte außer der Vier erzeugt eine rückwärts gerichtete Bewegung",
          arguments: [2, 3, 4, 5, 6])
    func onlyTheFourMovesBackward(seatCount: Int) {
        let forwardRanks: [CardRank] = [.ace, .two, .three, .five, .six, .eight, .nine, .ten, .queen]
        for seat in 0..<seatCount {
            for rank in forwardRanks {
                // Mehrere Startpunkte, damit Wrap-around und Heimnähe mit
                // abgedeckt sind statt nur der bequeme Fall.
                for startProgress in [1, 5, 20, 40, 55] {
                    for delta in progressDeltas(rank: rank, seatCount: seatCount, seat: seat, startProgress: startProgress) {
                        #expect(
                            delta > 0,
                            "\(seatCount) Sitze, Sitz \(seat), \(rank) ab Fortschritt \(startProgress): Bewegung um \(delta)"
                        )
                    }
                }
            }
        }
    }

    @Test("die Vier bewegt exakt vier Felder rückwärts", arguments: [2, 3, 4, 5, 6])
    func theFourMovesExactlyFourBackward(seatCount: Int) {
        for seat in 0..<seatCount {
            for startProgress in [5, 20, 40, 55] {
                for delta in progressDeltas(rank: .four, seatCount: seatCount, seat: seat, startProgress: startProgress) {
                    #expect(
                        delta == -4,
                        "\(seatCount) Sitze, Sitz \(seat), Vier ab \(startProgress): Bewegung um \(delta) statt -4"
                    )
                }
            }
        }
    }

    @Test("jede Zahlenkarte bewegt genau um ihren Wert", arguments: [2, 3, 4, 5, 6])
    func numberCardsMoveTheirValue(seatCount: Int) {
        for seat in 0..<seatCount {
            for rank in [CardRank.two, .three, .five, .six, .eight, .nine, .ten, .queen] {
                guard let want = expectedSteps(rank) else { continue }
                for startProgress in [1, 5, 20] {
                    for delta in progressDeltas(rank: rank, seatCount: seatCount, seat: seat, startProgress: startProgress) {
                        #expect(
                            delta == want,
                            "\(seatCount) Sitze, Sitz \(seat), \(rank) ab \(startProgress): \(delta) statt \(want)"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Die kritische Zone: Wrap, Start, Heimeinfahrt

    /// Genau dort, wo Richtung subtil wird.
    ///
    /// `lapLength` ist der Fortschritt der Heimeinfahrt; dahinter liegt die
    /// Zielgerade. Ein Feld mit kleinerem globalen Index ist auf dem Ring nicht
    /// „hinter" der Figur — deshalb wird auch hier ausschließlich der
    /// spielerrelative Fortschritt gemessen.
    @Test("auch nahe Start, Wrap und Heimeinfahrt geht nur die Vier rückwärts",
          arguments: [2, 3, 4, 5, 6])
    func directionHoldsInTheAwkwardZone(seatCount: Int) {
        let board = BoardGraph(seatCount: seatCount)
        let lap = board.lapLength
        // Kurz vor dem eigenen Start, über den Wrap, unmittelbar vor der
        // Heimeinfahrt und mitten in der Zielgeraden.
        let interesting = [0, 1, 2, lap - 12, lap - 4, lap - 1, lap, lap + 1]
            .filter { $0 >= 0 && $0 < board.fullJourneyLength }

        let forwardRanks: [CardRank] = [.ace, .two, .three, .five, .six, .eight, .nine, .ten, .queen]
        for seat in 0..<seatCount {
            for rank in forwardRanks {
                for startProgress in interesting {
                    for delta in progressDeltas(rank: rank, seatCount: seatCount, seat: seat, startProgress: startProgress) {
                        #expect(
                            delta > 0,
                            "\(seatCount) Sitze, Sitz \(seat), \(rank) ab Fortschritt \(startProgress) (lap=\(lap)): \(delta)"
                        )
                    }
                }
            }
        }
    }

    /// Der Core muss einen manuell gebauten Rückwärtszug auch dann ablehnen,
    /// wenn ihn kein Generator angeboten hat. Sonst schützt nur die UI.
    @Test("ein konstruierter Rückwärtszug wird vom Core abgelehnt",
          arguments: [2, 3, 4, 5, 6])
    func handBuiltBackwardMoveIsRefused(seatCount: Int) {
        let board = BoardGraph(seatCount: seatCount)
        for seat in 0..<seatCount {
            guard let start = board.position(atProgress: 20, for: Seat(seat)) else { continue }
            let state = Fixture.state(
                seatCount: seatCount,
                pawns: [Fixture.pawn(seat, 0): start],
                hands: [seat: [.five]],
                currentSeat: seat
            )
            // Eine Fünf, die rückwärts ziehen soll — nie vom Generator geliefert.
            let illegal = Move(
                seat: Seat(seat),
                card: Card(rank: .five, deckCopy: seat),
                action: .moveBackward(pawn: Fixture.pawn(seat, 0), steps: 5)
            )
            #expect(throws: (any Error).self, "\(seatCount) Sitze, Sitz \(seat): Rückwärtszug mit einer Fünf wurde angenommen") {
                try GameReducer.apply(.play(illegal), to: state)
            }
        }
    }

    // MARK: - Der Bube tauscht, er zieht nicht

    @Test("der Bube erzeugt ausschließlich Tauschaktionen", arguments: [2, 3, 4, 5, 6])
    func jackOnlySwaps(seatCount: Int) {
        let board = BoardGraph(seatCount: seatCount)
        for seat in 0..<seatCount {
            let other = (seat + 1) % seatCount
            guard let mine = board.position(atProgress: 10, for: Seat(seat)),
                  let theirs = board.position(atProgress: 10, for: Seat(other))
            else { continue }

            let state = Fixture.state(
                seatCount: seatCount,
                pawns: [Fixture.pawn(seat, 0): mine, Fixture.pawn(other, 0): theirs],
                hands: [seat: [.jack]],
                currentSeat: seat
            )
            for move in MoveGenerator.legalMoves(in: state, for: Seat(seat)) {
                guard case .swap = move.action else {
                    Issue.record("\(seatCount) Sitze, Sitz \(seat): Bube erzeugte \(move.action) statt eines Tauschs")
                    continue
                }
            }
        }
    }

    // MARK: - Die Sieben teilt vorwärts

    @Test("jeder Teilschritt der Sieben geht vorwärts und die Summe ist sieben",
          arguments: [2, 3, 4, 5, 6])
    func sevenSplitsForwardAndSumsToSeven(seatCount: Int) {
        let board = BoardGraph(seatCount: seatCount)
        for seat in 0..<seatCount {
            guard let a = board.position(atProgress: 8, for: Seat(seat)),
                  let b = board.position(atProgress: 20, for: Seat(seat))
            else { continue }

            let state = Fixture.state(
                seatCount: seatCount,
                pawns: [Fixture.pawn(seat, 0): a, Fixture.pawn(seat, 1): b],
                hands: [seat: [.seven]],
                currentSeat: seat
            )
            for move in MoveGenerator.legalMoves(in: state, for: Seat(seat)) {
                guard case .split(let steps) = move.action else {
                    Issue.record("\(seatCount) Sitze, Sitz \(seat): Sieben erzeugte \(move.action) statt eines Splits")
                    continue
                }
                for leg in steps {
                    #expect(leg.steps > 0, "\(seatCount) Sitze, Sitz \(seat): Teilschritt \(leg.steps) ist nicht vorwärts")
                }
                #expect(
                    steps.reduce(0) { $0 + $1.steps } == 7,
                    "\(seatCount) Sitze, Sitz \(seat): Summe \(steps.reduce(0) { $0 + $1.steps }) statt 7"
                )
            }
        }
    }
}
