import Foundation

/// Remembers which finished matches have already been accounted for.
///
/// An online match is not reported the way a local one is. A local match
/// finishes *while this device is watching*, once, so the moment it ends is an
/// edge and reporting on that edge cannot repeat. An online match arrives
/// already finished: the opponent plays the winning move while the app is
/// closed, and the match is then handed to this device again every time the
/// screen opens, every time the app comes back to the foreground, and every
/// time a refresh lands. There is no edge to hang anything on — only a
/// position that is over, over and over.
///
/// So the online path is level-triggered and this is what stops it repeating.
/// It survives a relaunch on purpose: resuming a match the player finished
/// yesterday must not hand them the same set of achievements again (§57).
///
/// Game Center also ignores a repeat — `GKAchievement` keeps the first
/// completion date — so this is the second of two defences rather than the
/// only one. It exists because "Apple probably de-duplicates" is not something
/// to build a promise on.
protocol AchievementLedger: Sendable {
    @MainActor func hasAccountedFor(matchID: String) -> Bool
    @MainActor func markAccountedFor(matchID: String)
}

/// The real one, on disk.
///
/// Holds the most recent `limit` match identifiers and no more. An unbounded
/// list would grow for the lifetime of the installation to guard against
/// something that cannot happen — a match falls out only after the player has
/// finished `limit` further ones, and at that point re-reporting it would be
/// ignored by Game Center anyway.
@MainActor
struct StoredAchievementLedger: AchievementLedger {
    static let key = "keezly.achievements.reportedMatches"
    static let limit = 200

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var reported: [String] {
        defaults.stringArray(forKey: Self.key) ?? []
    }

    func hasAccountedFor(matchID: String) -> Bool {
        reported.contains(matchID)
    }

    func markAccountedFor(matchID: String) {
        var ids = reported
        guard !ids.contains(matchID) else { return }
        ids.append(matchID)
        if ids.count > Self.limit {
            ids.removeFirst(ids.count - Self.limit)
        }
        defaults.set(ids, forKey: Self.key)
    }
}

/// For tests and for any session that must not write to the device.
@MainActor
final class InMemoryAchievementLedger: AchievementLedger {
    private var reported: Set<String> = []

    init() {}

    func hasAccountedFor(matchID: String) -> Bool { reported.contains(matchID) }
    func markAccountedFor(matchID: String) { reported.insert(matchID) }
}
