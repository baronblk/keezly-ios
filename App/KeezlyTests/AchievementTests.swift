import Foundation
@testable import Keezly
import KeezlyCore
import Testing

/// §M9.4 — an achievement is a fact about a match, worked out from the match.
///
/// Nothing counts an achievement as it happens, and nothing in a view decides
/// whether one was earned: the evaluator replays a finished record and watches
/// the engine's own events. That is what makes these recomputable — the same
/// record always earns the same set, today and in a year.
@Suite("Achievements")
@MainActor
struct AchievementTests {

    /// A match played to the end, or as far as it gets.
    private func played(
        seats: Int = 4,
        teams: Bool = true,
        seed: UInt64,
        limit: Int = 900
    ) -> MatchRecord {
        var record = MatchRecord(
            configuration: GameConfiguration(seatCount: seats, teamMode: teams ? .teamsOfTwo : .freeForAll),
            seed: seed
        )
        var state = record.initialState
        var generator = SeededGenerator(seed: seed &* 13 &+ 1)

        for _ in 0..<limit where state.result == nil {
            let legal = MoveGenerator.legalMoves(in: state, for: state.currentSeat)
            let action: PlayerAction = legal.isEmpty
                ? .foldHand(seat: state.currentSeat)
                : .play(legal[Int.random(in: 0..<legal.count, using: &generator)])
            guard let next = try? GameReducer.apply(action, to: state) else { break }
            state = next.state
            record.append(action)
        }
        record.note(state)
        return record
    }

    // MARK: - The set itself

    @Test("every achievement has an identifier, points and words")
    func achievementsAreWellFormed() {
        let ids = Achievement.allCases.map(\.gameCenterID)
        #expect(Set(ids).count == ids.count, "two achievements share an identifier")

        for achievement in Achievement.allCases {
            #expect(achievement.gameCenterID.hasPrefix("de.gcng.keezly.achievement."))
            #expect(achievement.points > 0 && achievement.points <= 100)
            #expect(!achievement.title.hasPrefix("achievement."), "\(achievement.rawValue) shows its key")
            #expect(!achievement.detail.hasPrefix("achievement."), "\(achievement.rawValue) shows its key")
            #expect(!achievement.detail.isEmpty)
            // Deliberately **not** a length. The bound used to be fifteen
            // characters and it made this test depend on the locale the
            // simulator happened to be running in: "Gewinne eine Partie." is
            // twenty characters and passed, "Win a match." is twelve and did
            // not. It went green on a German desk for weeks and failed the
            // first time Xcode Cloud ran it in English.
            //
            // The sentence is not worse for being short — padding it to reach
            // a number would make it worse — so what is asserted now is that it
            // is a sentence, which is true in every language.
            #expect(achievement.detail.hasSuffix("."), "\(achievement.rawValue) detail is not a sentence")
        }
    }

    /// Game Center allows a thousand points across a game; a hundred is a set
    /// of things worth doing rather than a list worth a point each.
    @Test("the set totals a hundred points")
    func pointsTotal() {
        #expect(Achievement.allCases.reduce(0) { $0 + $1.points } == 100)
    }

    // MARK: - Earned by what happened

    /// **An abandoned match earns nothing.**
    ///
    /// Leaving a game halfway is not an accomplishment, and counting it as one
    /// would make the rest of the set meaningless.
    @Test("an unfinished match earns nothing")
    func unfinishedEarnsNothing() {
        var record = played(seed: 11, limit: 30)
        record.abandon()
        #expect(AchievementEvaluator.unlocked(in: record, for: Seat(0)).isEmpty)
    }

    @Test("finishing a match earns the one for finishing, whoever won")
    func finishingIsEarnedByEverybody() throws {
        let record = played(seed: 2026)
        try #require(record.status == .completed, "the fixture never finished")

        for seat in 0..<4 {
            let earned = AchievementEvaluator.unlocked(in: record, for: Seat(seat))
            #expect(earned.contains(.finished), "seat \(seat) did not get credit for finishing")
        }
    }

    /// **Only the winner is told they won.**
    @Test("winning is earned by the winners and nobody else")
    func winningIsEarnedByTheWinners() throws {
        let record = played(seed: 2026)
        var state = record.initialState
        for action in record.actions {
            state = try GameReducer.apply(action, to: state).state
        }
        let result = try #require(state.result)

        for seat in 0..<4 {
            let earned = AchievementEvaluator.unlocked(in: record, for: Seat(seat))
            let won = result.winningSeats.contains(Seat(seat))
            #expect(earned.contains(.won) == won, "seat \(seat) was told the wrong thing about winning")
            #expect(earned.contains(.partners) == won, "the pair achievement did not follow the win")
        }
    }

    /// A player cannot be both untouched and resilient: the first means never
    /// knocked back, the second means knocked back and winning anyway.
    @Test("untouched and resilient are opposites, never both")
    func opposingAchievementsExclude() {
        for seed in [UInt64(11), 2026, 4242, 909, 5150] {
            let record = played(seed: seed)
            for seat in 0..<4 {
                let earned = AchievementEvaluator.unlocked(in: record, for: Seat(seat))
                #expect(
                    !(earned.contains(.untouched) && earned.contains(.resilient)),
                    "seat \(seat) was both never knocked back and knocked back"
                )
                // Neither is possible without winning.
                if earned.contains(.untouched) || earned.contains(.resilient) {
                    #expect(earned.contains(.won))
                }
            }
        }
    }

    @Test("a six-player match earns the full-table one, a four-player one does not")
    func tableSizeIsCounted() throws {
        let six = played(seats: 6, seed: 404)
        try #require(six.status == .completed)
        #expect(AchievementEvaluator.unlocked(in: six, for: Seat(0)).contains(.fullTable))

        let four = played(seed: 2026)
        #expect(!AchievementEvaluator.unlocked(in: four, for: Seat(0)).contains(.fullTable))
    }

    /// **Credit goes to the player who did the thing, not to everybody at the
    /// table.**
    @Test("a move earns only for the seat that made it")
    func creditFollowsTheMove() throws {
        // A long match will contain captures, swaps and backward moves. Every
        // one of them belongs to exactly one seat.
        let record = played(seed: 7781)
        try #require(record.status == .completed)

        let perSeat = (0..<4).map { AchievementEvaluator.unlocked(in: record, for: Seat($0)) }
        let anyMoveAchievement: Set<Achievement> = [.split, .swapped, .backwards, .knockout]
        let earnedByAnyone = perSeat.reduce(into: Set<Achievement>()) { $0.formUnion($1) }
        #expect(
            !earnedByAnyone.isDisjoint(with: anyMoveAchievement),
            "a whole match produced no capture, swap, split or backward move"
        )

        // And the same record always gives the same answer.
        for seat in 0..<4 {
            #expect(AchievementEvaluator.unlocked(in: record, for: Seat(seat)) == perSeat[seat])
        }
    }

    /// Free-for-all is not partnership play, whoever wins.
    @Test("the pair achievement needs a pair")
    func partnersNeedsTeams() throws {
        let record = played(seats: 4, teams: false, seed: 6120)
        try #require(record.status == .completed)
        for seat in 0..<4 {
            #expect(!AchievementEvaluator.unlocked(in: record, for: Seat(seat)).contains(.partners))
        }
    }
}

/// Every achievement must be complete in every language Keezly ships.
///
/// Read from the **built bundle**, not from the source catalogue and not
/// through `String(localized:)`.
///
/// Not the source: a test that opens `Localizable.xcstrings` by `#filePath`
/// needs a checkout, and a test runner does not have one — Xcode Cloud hands
/// the test machines a built product and nothing else. That is the same
/// assumption that failed `ci_pre_xcodebuild.sh` this morning, made again.
///
/// Not `String(localized:)`: it resolves against whichever locale the process
/// is running in, so it checks one language and silently ignores the other two.
/// That is exactly how `achievement.won.detail` stayed green on a German desk
/// while being twelve characters in English.
///
/// Reading the shipped `.lproj` bundles tests what a player actually gets,
/// which is stronger than either.
@Suite("Achievement text, in every language")
struct AchievementCatalogueTests {

    /// The three languages Keezly ships, as the bundle holds them.
    ///
    /// `Bundle.main` rather than `Bundle(for:)`: this suite is hosted in the
    /// app, so main *is* the app bundle, and `Bundle(for:)` would hand back the
    /// test bundle — which has no localisations and would make the check pass
    /// or fail for the wrong reason.
    private func bundles() throws -> [(language: String, bundle: Bundle)] {
        let app = Bundle.main
        return try ["de", "nl", "en"].map { language in
            let path = try #require(
                app.path(forResource: language, ofType: "lproj"),
                "the app bundle has no \(language).lproj — is that language still shipped?"
            )
            return (language, try #require(Bundle(path: path)))
        }
    }

    @Test("every achievement has a title and a detail in German, Dutch and English")
    func everyLanguageIsComplete() throws {
        for (language, bundle) in try bundles() {
            for achievement in Achievement.allCases {
                for field in ["title", "detail"] {
                    let key = "achievement.\(achievement.rawValue).\(field)"
                    let text = bundle.localizedString(forKey: key, value: "\u{0}missing", table: nil)
                    #expect(text != "\u{0}missing", "\(key) is missing from \(language)")
                    #expect(!text.isEmpty, "\(key) is empty in \(language)")
                    #expect(text != key, "\(key) shows its own key in \(language)")
                }
            }
        }
    }

    @Test("every achievement detail is a sentence in every language")
    func everyDetailIsASentence() throws {
        for (language, bundle) in try bundles() {
            for achievement in Achievement.allCases {
                let key = "achievement.\(achievement.rawValue).detail"
                let text = bundle.localizedString(forKey: key, value: "", table: nil)
                #expect(text.hasSuffix("."), "\(key) is not a sentence in \(language): \(text)")
            }
        }
    }
}
