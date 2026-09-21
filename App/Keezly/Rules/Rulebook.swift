import KeezlyCore
import SwiftUI

/// A rule that tables genuinely disagree about (§75).
///
/// One case per configurable option in `RuleSet`. `RulebookTests` holds the two
/// lists against each other, so a seventh rule option cannot be added to the
/// engine without a section of the rulebook explaining it — which is the only
/// way a settings screen and a rulebook stay in step for longer than a month.
enum RuleFacet: String, CaseIterable, Identifiable, Hashable {
    case king
    case jackOwnStart
    case homeEntry
    case homeOrdering
    case friendlyCapture
    case ownPawnBlocking

    var id: String { rawValue }

    /// The choices, in a fixed order, each marked with whether this table uses
    /// it and whether it is the traditional reading.
    ///
    /// "Classic" is not written down twice: it is read off `RuleSet.keezlyClassic`,
    /// so the badge in the rulebook cannot drift away from the preset it names.
    func options(in rules: RuleSet) -> [RuleOption] {
        switch self {
        case .king:
            return build(KingBehavior.allCases, active: rules.king, classic: RuleSet.keezlyClassic.king)
        case .jackOwnStart:
            return build(
                JackOwnStartPolicy.allCases,
                active: rules.jackOwnStart,
                classic: RuleSet.keezlyClassic.jackOwnStart
            )
        case .homeEntry:
            return build(HomeEntryPolicy.allCases, active: rules.homeEntry, classic: RuleSet.keezlyClassic.homeEntry)
        case .homeOrdering:
            return build(
                HomeOrderingPolicy.allCases,
                active: rules.homeOrdering,
                classic: RuleSet.keezlyClassic.homeOrdering
            )
        case .friendlyCapture:
            return build(
                FriendlyCapturePolicy.allCases,
                active: rules.friendlyCapture,
                classic: RuleSet.keezlyClassic.friendlyCapture
            )
        case .ownPawnBlocking:
            return build(
                OwnPawnBlockingPolicy.allCases,
                active: rules.ownPawnBlocking,
                classic: RuleSet.keezlyClassic.ownPawnBlocking
            )
        }
    }

    private func build<Option: RawRepresentable & Equatable>(
        _ all: [Option],
        active: Option,
        classic: Option
    ) -> [RuleOption] where Option.RawValue == String {
        all
            .map {
                RuleOption(
                    id: "\(rawValue).\($0.rawValue)",
                    isActive: $0 == active,
                    isClassic: $0 == classic
                )
            }
            // The traditional reading first, whatever order the enum happens
            // to declare its cases in. A reader comparing six sections should
            // find them laid out the same way each time.
            .sorted { $0.isClassic && !$1.isClassic }
    }
}

/// One way a rule can be played.
struct RuleOption: Identifiable, Hashable {
    let id: String
    /// Whether this is what the match being played actually does.
    let isActive: Bool
    /// Whether this is the traditional reading rather than a house rule.
    let isClassic: Bool

    var label: String { Rulebook.text("rules.option.\(id)") }
}

/// One thing the rulebook explains.
struct RuleSection: Identifiable, Hashable {
    let id: String
    /// The rule variation this section is about, when it is about one.
    let facet: RuleFacet?

    init(_ id: String, facet: RuleFacet? = nil) {
        self.id = id
        self.facet = facet
    }

    var title: String { Rulebook.text("rules.\(id).title") }
    var body: String { Rulebook.text("rules.\(id).body") }
}

/// A run of sections that belong together.
struct RuleChapter: Identifiable, Hashable {
    let id: String
    let sections: [RuleSection]

    var title: String { Rulebook.text("rules.chapter.\(id)") }
}

/// The rules of Keezen as Keezly plays them.
///
/// Written for this app in its own words, from `RULES.md` and the variant
/// matrix — no rule text is taken from another publisher (§76). It is a
/// reference, not a tutorial: somebody halfway through a match looking up what
/// a Four does should find it in one tap and one sentence.
///
/// Pure data, so what the rulebook claims can be tested against what the engine
/// does rather than proof-read.
enum Rulebook {
    static let chapters: [RuleChapter] = [
        RuleChapter(id: "game", sections: [
            RuleSection("goal"),
            RuleSection("table"),
            RuleSection("teams"),
        ]),
        RuleChapter(id: "cards", sections: [
            RuleSection("deck"),
            RuleSection("deal"),
            RuleSection("turnOrder"),
            RuleSection("forcedMove"),
            RuleSection("fold"),
        ]),
        RuleChapter(id: "moving", sections: [
            RuleSection("entering"),
            RuleSection("start"),
            RuleSection("moving"),
            RuleSection("capture"),
            RuleSection("friendlyCapture", facet: .friendlyCapture),
            RuleSection("blocking", facet: .ownPawnBlocking),
        ]),
        RuleChapter(id: "special", sections: [
            RuleSection("ace"),
            RuleSection("king", facet: .king),
            RuleSection("queen"),
            RuleSection("jack"),
            RuleSection("jackOwnStart", facet: .jackOwnStart),
            RuleSection("four"),
            RuleSection("seven"),
        ]),
        RuleChapter(id: "home", sections: [
            RuleSection("homeEntry", facet: .homeEntry),
            RuleSection("homeOrdering", facet: .homeOrdering),
            RuleSection("homeSafety"),
        ]),
        RuleChapter(id: "ending", sections: [
            RuleSection("winning"),
            RuleSection("leaving"),
        ]),
    ]

    static var sections: [RuleSection] { chapters.flatMap(\.sections) }

    /// The name of a preset, for the line that says which rules are in play.
    static func name(of preset: RulePreset) -> String {
        text("rules.preset.\(preset.rawValue)")
    }

    /// Looks up a key that was built at runtime.
    ///
    /// The key arrives as a `String` parameter, and that is the whole point.
    /// Written inline — `String(localized: "rules.\\(id).title")` — Swift picks
    /// the *interpolating* initialiser of `LocalizationValue`, looks up
    /// `rules.%@.title`, finds nothing and puts the raw key on screen. The same
    /// trap is waiting in `LocalizedStringKey`. Passing a variable takes
    /// `init(_ value: String)` instead, which is the literal lookup this needs.
    ///
    /// Only for keys assembled from data. A key known at compile time belongs
    /// in the view as a literal, where the String Catalog can find it.
    static func text(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    /// Whether a table is playing anything other than the traditional rules.
    ///
    /// Used to say so once at the top rather than making a reader compare six
    /// sections against their memory of the default.
    static func isHouseRuled(_ rules: RuleSet) -> Bool {
        RuleFacet.allCases.contains { facet in
            facet.options(in: rules).contains { $0.isActive && !$0.isClassic }
        }
    }
}
