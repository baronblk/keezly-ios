import Foundation
@testable import Keezly
import KeezlyCore
import Testing

/// Der Absturz, den die Geräte-QA an Build 41 gefunden hat.
///
/// Der Online-Bildschirm merkte sich „mit Partner" über einen Wechsel der
/// Sitzzahl hinweg. Bei drei oder fünf Sitzen verschwand nur der Schalter, der
/// Wert blieb stehen — und `GameConfiguration(seatCount: 3, teamMode:
/// .teamsOfTwo)` bricht mit einer precondition. Die App beendete sich beim
/// Tippen auf „Neue Onlinepartie", noch bevor GameKit überhaupt gerufen wurde.
///
/// Die Ursache war eine **zweite Fassung einer Regel, die es schon gab**:
/// `seats % 2 == 0` statt `TableConfiguration.allowsTeams(seatCount:)`.
/// Diese Suite prüft die Regel selbst, damit keine dritte Fassung entsteht.
@Suite("Online-Tischkonfiguration")
struct OnlineConfigurationTests {

    /// Genau die Rechnung, die `OnlinePlay.startMatch` anstellt.
    private func teamMode(seats: Int, prefersTeams: Bool) -> TeamMode {
        TableConfiguration.allowsTeams(seatCount: seats) && prefersTeams ? .teamsOfTwo : .freeForAll
    }

    @Test("eine ungerade Sitzzahl ergibt nie ein Teamspiel, auch wenn Teams gewählt bleiben",
          arguments: [3, 5])
    func oddSeatsNeverProduceTeams(seats: Int) {
        #expect(teamMode(seats: seats, prefersTeams: true) == .freeForAll)
    }

    @Test("zwei Sitze ergeben nie ein Teamspiel")
    func twoSeatsNeverProduceTeams() {
        // Nicht bloß „gerade": bei zwei Sitzen stünden beide Spieler auf
        // derselben Seite, weil die Engine Sitz i mit i + seatCount/2 paart.
        #expect(teamMode(seats: 2, prefersTeams: true) == .freeForAll)
    }

    @Test("vier und sechs Sitze dürfen Teams bilden", arguments: [4, 6])
    func evenLargeSeatsAllowTeams(seats: Int) {
        #expect(teamMode(seats: seats, prefersTeams: true) == .teamsOfTwo)
        #expect(teamMode(seats: seats, prefersTeams: false) == .freeForAll)
    }

    /// Der eigentliche Regressionstest: jede Kombination, die der
    /// Online-Bildschirm anbieten kann, muss eine baubare Konfiguration
    /// ergeben. Vorher stürzte genau das ab.
    @Test("jede vom Online-Bildschirm anbietbare Kombination ist baubar")
    func everyOfferedCombinationBuilds() {
        for seats in TableConfiguration.seatCounts {
            for prefersTeams in [true, false] {
                let mode = teamMode(seats: seats, prefersTeams: prefersTeams)
                // Baut die Konfiguration wirklich — eine verletzte precondition
                // würde den Testlauf beenden, was genau der Befund wäre.
                let configuration = GameConfiguration(seatCount: seats, teamMode: mode)
                #expect(configuration.seatCount == seats)
                if mode == .teamsOfTwo {
                    #expect(seats >= 4 && seats.isMultiple(of: 2),
                            "\(seats) Sitze wurden als Teamspiel gebaut")
                }
            }
        }
    }

    @Test("die Regel steht nur an einer Stelle")
    func theRuleExistsOnlyOnce() {
        // Der lokale Tisch und der Online-Bildschirm müssen dieselbe Antwort
        // geben. Solange beide `TableConfiguration.allowsTeams` benutzen, kann
        // das nicht auseinanderlaufen.
        for seats in TableConfiguration.seatCounts {
            var table = TableConfiguration()
            table.seatCount = seats
            table.prefersTeams = true
            #expect(
                table.teamMode == teamMode(seats: seats, prefersTeams: true),
                "\(seats) Sitze: lokaler Tisch und Online widersprechen sich"
            )
        }
    }
}
