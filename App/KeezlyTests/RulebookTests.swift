@testable import Keezly
import KeezlyCore
import Testing

/// §75 — the rulebook has to describe the game the engine actually plays.
///
/// A rulebook is the one part of an app that can quietly go out of date without
/// anything breaking: the code changes, the prose does not, and nobody notices
/// until a player is told a rule that is no longer true. These tests tie the
/// two together so that going out of date is a build failure.
@Suite("Rulebook")
struct RulebookTests {

    /// **Every configurable rule is explained.**
    ///
    /// Read off `RuleSet` by reflection rather than from a list written twice:
    /// adding a seventh option to the engine fails here until a section of the
    /// rulebook covers it.
    @Test("every rule option in the engine has a section explaining it")
    func everyRuleOptionIsDocumented() {
        // `preset` is the name of a bundle of choices, not a choice itself.
        let configurable = Mirror(reflecting: RuleSet.keezlyClassic)
            .children
            .compactMap(\.label)
            .filter { $0 != "preset" }

        #expect(!configurable.isEmpty, "reflection found no rule options at all")
        #expect(
            Set(configurable) == Set(RuleFacet.allCases.map(\.rawValue)),
            """
            the engine and the rulebook disagree about which rules are configurable: \
            undocumented \(Set(configurable).subtracting(RuleFacet.allCases.map(\.rawValue))), \
            described but gone \(Set(RuleFacet.allCases.map(\.rawValue)).subtracting(configurable))
            """
        )
    }

    @Test("every facet reaches the reader through a section")
    func everyFacetHasASection() {
        let covered = Set(Rulebook.sections.compactMap(\.facet))
        #expect(covered == Set(RuleFacet.allCases), "a rule variation has no section to appear in")
    }

    @Test("sections are unique and the book is complete enough to be a rulebook")
    func sectionsAreWellFormed() {
        let ids = Rulebook.sections.map(\.id)
        #expect(Set(ids).count == ids.count, "two sections share an identifier")
        #expect(ids.count >= 20, "a rulebook this short is a summary, not a rulebook")
    }

    // MARK: - What the book says about a table

    @Test("each facet offers every option the engine has, exactly one of them active")
    func optionsMatchTheEngine() {
        for rules in [RuleSet.keezlyClassic, .tournament, .houseRulesDefault, houseRuled] {
            for facet in RuleFacet.allCases {
                let options = facet.options(in: rules)
                #expect(options.count >= 2, "\(facet.rawValue) offered fewer than two readings")
                #expect(options.count(where: \.isActive) == 1, "\(facet.rawValue) has no single active option")
                #expect(options.count(where: \.isClassic) == 1, "\(facet.rawValue) has no single traditional option")
                #expect(Set(options.map(\.id)).count == options.count)
            }
        }
    }

    @Test("the traditional preset is marked as traditional throughout")
    func classicIsClassic() {
        for facet in RuleFacet.allCases {
            let active = facet.options(in: .keezlyClassic).first { $0.isActive }
            #expect(active?.isClassic == true, "\(facet.rawValue) calls the default a house rule")
        }
        #expect(!Rulebook.isHouseRuled(.keezlyClassic))
        #expect(!Rulebook.isHouseRuled(.tournament), "the tournament preset currently equals Classic")
    }

    @Test("a table that changes a rule is announced as such")
    func houseRulesAreAnnounced() {
        #expect(Rulebook.isHouseRuled(houseRuled))
        let king = RuleFacet.king.options(in: houseRuled).first { $0.isActive }
        #expect(king?.isClassic == false)
        #expect(king?.id == "king.enterOrAdvance13")
    }

    private var houseRuled: RuleSet {
        RuleSet(
            preset: .houseRules,
            king: .enterOrAdvance13,
            jackOwnStart: .mayBeSwapSource,
            homeEntry: .allowExtraLap,
            homeOrdering: .strictBackToFront,
            friendlyCapture: .landingForbidden,
            ownPawnBlocking: .blocking
        )
    }

    // MARK: - The words themselves

    /// Every section, chapter and option must show text, not a key.
    ///
    /// Checked through the model's own properties — the exact values the view
    /// puts on screen — rather than by rebuilding the keys here. The first
    /// version of this test rebuilt them, passed, and the rulebook still
    /// displayed `rules.goal.title` to anyone who opened it: the model was
    /// handing SwiftUI a `LocalizedStringKey` built by string interpolation,
    /// which looks up `rules.%@.title` and finds nothing. A test that derives
    /// its own inputs is not testing the thing that ships.
    @Test("every line in the rulebook is text, not a lookup key")
    func nothingFallsBackToItsKey() {
        func check(_ text: String, _ what: String) {
            #expect(!text.hasPrefix("rules."), "\(what) shows its key: \(text)")
            #expect(text.count > 1, "\(what) is empty")
        }

        for preset in RulePreset.allCases {
            check(Rulebook.name(of: preset), "the name of \(preset.rawValue)")
        }
        for chapter in Rulebook.chapters {
            check(chapter.title, "chapter \(chapter.id)")
        }
        for section in Rulebook.sections {
            check(section.title, "the title of \(section.id)")
            check(section.body, "the body of \(section.id)")
            // A stub would pass the key check while saying nothing. Twenty
            // characters is deliberately low: "Zwölf Felder vor, sonst nichts"
            // is the whole rule for a queen, and padding it would be worse.
            #expect(section.body.count > 20, "the body of \(section.id) is too short to explain anything")
            #expect(section.body != section.title)
        }
        for facet in RuleFacet.allCases {
            for option in facet.options(in: .keezlyClassic) {
                check(option.label, "option \(option.id)")
            }
        }
    }
}
