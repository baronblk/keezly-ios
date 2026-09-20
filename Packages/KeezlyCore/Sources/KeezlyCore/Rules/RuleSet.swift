import Foundation

/// How a King may be used (§18).
public enum KingBehavior: String, Hashable, Sendable, Codable, CaseIterable {
    /// Classic: a King only brings a pawn out of the waiting area.
    case enterOnly
    /// House rule: a King either brings a pawn out *or* advances 13 squares.
    case enterOrAdvance13
}

/// Whether a pawn standing on its own protected start square may itself be
/// the pawn a Jack swaps away (§15, §18).
public enum JackOwnStartPolicy: String, Hashable, Sendable, Codable, CaseIterable {
    /// The protected pawn may initiate a swap (it gives up its protection).
    case mayBeSwapSource
    /// Protection is absolute: the pawn can neither be swapped nor swap.
    case mayNotBeSwapSource
}

/// How a pawn gets into its home lane (§16).
public enum HomeEntryPolicy: String, Hashable, Sendable, Codable, CaseIterable {
    /// Classic: exact count required; a pawn that cannot enter stays put.
    case exactCountOnly
    /// House rule ("speed"): a pawn that overshoots may continue for another
    /// lap instead of the move being illegal.
    case allowExtraLap
}

/// Which home squares a pawn may occupy (§18).
public enum HomeOrderingPolicy: String, Hashable, Sendable, Codable, CaseIterable {
    /// Any home square reachable with an exact count, as long as the pawn does
    /// not jump over a pawn already home.
    case anyReachableWithoutJumping
    /// Strictly fill from the deepest square forward.
    case strictBackToFront
}

/// What happens when a pawn lands on a friendly pawn — its own or a
/// team-mate's (§14, §18).
public enum FriendlyCapturePolicy: String, Hashable, Sendable, Codable, CaseIterable {
    /// Classic Keezen: friendly pawns are captured just like enemies. Combined
    /// with the forced-move rule (§13) this means a player can be compelled to
    /// knock out their own partner.
    case captureAllowed
    /// Landing on a friendly pawn is simply not a legal move.
    case landingForbidden
}

/// Whether a player's own non-protected pawns block the track (§18).
public enum OwnPawnBlockingPolicy: String, Hashable, Sendable, Codable, CaseIterable {
    /// Classic: only protected start squares block; everything else is passable.
    case passable
    /// House rule: a player's own pawns form blockades too.
    case blocking
}

/// The complete, immutable rule configuration of a match.
///
/// Every rule variation lives here as a named option rather than as scattered
/// booleans in the move generator (§18). A match's `RuleSet` is part of its
/// serialised state and must never change mid-match.
public struct RuleSet: Hashable, Sendable, Codable {
    public var preset: RulePreset
    public var king: KingBehavior
    public var jackOwnStart: JackOwnStartPolicy
    public var homeEntry: HomeEntryPolicy
    public var homeOrdering: HomeOrderingPolicy
    public var friendlyCapture: FriendlyCapturePolicy
    public var ownPawnBlocking: OwnPawnBlockingPolicy

    public init(
        preset: RulePreset = .keezlyClassic,
        king: KingBehavior = .enterOnly,
        jackOwnStart: JackOwnStartPolicy = .mayNotBeSwapSource,
        homeEntry: HomeEntryPolicy = .exactCountOnly,
        homeOrdering: HomeOrderingPolicy = .anyReachableWithoutJumping,
        friendlyCapture: FriendlyCapturePolicy = .captureAllowed,
        ownPawnBlocking: OwnPawnBlockingPolicy = .passable
    ) {
        self.preset = preset
        self.king = king
        self.jackOwnStart = jackOwnStart
        self.homeEntry = homeEntry
        self.homeOrdering = homeOrdering
        self.friendlyCapture = friendlyCapture
        self.ownPawnBlocking = ownPawnBlocking
    }
}

public enum RulePreset: String, Hashable, Sendable, Codable, CaseIterable {
    case keezlyClassic
    case tournament
    case houseRules
}

public extension RuleSet {
    /// The default rule set: the traditional family game as described in
    /// §11–§17. See docs/RULE_VARIANTS.md for the full matrix and the
    /// reasoning behind each choice.
    static let keezlyClassic = RuleSet(preset: .keezlyClassic)

    /// Tournament-leaning variant. Deliberately conservative: it currently
    /// differs from Classic only where a difference is actually verified.
    /// Open questions are tracked in docs/RULE_VARIANTS.md rather than guessed.
    static let tournament = RuleSet(
        preset: .tournament,
        king: .enterOnly,
        jackOwnStart: .mayNotBeSwapSource,
        homeEntry: .exactCountOnly,
        homeOrdering: .anyReachableWithoutJumping,
        friendlyCapture: .captureAllowed,
        ownPawnBlocking: .passable
    )

    /// A starting point for user-configured rules; every option is editable.
    static let houseRulesDefault = RuleSet(preset: .houseRules)
}
