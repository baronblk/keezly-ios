import Foundation

/// Aggregated results of a simulation batch.
///
/// Used to make claims about relative agent strength that are backed by an
/// actual run rather than by intuition (§25, `AI.md`).
public struct SimulationReport: Sendable {
    public let configuration: GameConfiguration
    public let outcomes: [SimulationOutcome]

    public init(configuration: GameConfiguration, outcomes: [SimulationOutcome]) {
        self.configuration = configuration
        self.outcomes = outcomes
    }

    public var matchCount: Int { outcomes.count }
    public var failures: [SimulationOutcome] { outcomes.filter { $0.failure != nil } }
    public var isClean: Bool { failures.isEmpty }

    /// Seeds of every failed match, so a failure can be replayed exactly.
    public var failingSeeds: [UInt64] { failures.map(\.seed) }

    public var completedMatches: [SimulationOutcome] { outcomes.filter(\.succeeded) }

    /// Wins per seat index.
    public var winsBySeat: [Int: Int] {
        var counts: [Int: Int] = [:]
        for outcome in completedMatches {
            for seat in outcome.result?.winningSeats ?? [] {
                counts[seat.index, default: 0] += 1
            }
        }
        return counts
    }

    /// Wins per team.
    public var winsByTeam: [TeamID: Int] {
        var counts: [TeamID: Int] = [:]
        for outcome in completedMatches {
            guard let team = outcome.result?.winningTeam else { continue }
            counts[team, default: 0] += 1
        }
        return counts
    }

    public var averageActions: Double {
        guard !completedMatches.isEmpty else { return 0 }
        return Double(completedMatches.reduce(0) { $0 + $1.actions }) / Double(completedMatches.count)
    }

    public var longestMatch: Int { completedMatches.map(\.actions).max() ?? 0 }
    public var shortestMatch: Int { completedMatches.map(\.actions).min() ?? 0 }

    /// Total agent thinking time across the batch.
    public var totalDecisionDuration: Duration {
        outcomes.reduce(Duration.zero) { $0 + $1.decisionDuration }
    }

    /// Average thinking time per applied action.
    public var averageDecisionDuration: Duration {
        let actions = outcomes.reduce(0) { $0 + $1.actions }
        guard actions > 0 else { return .zero }
        return totalDecisionDuration / actions
    }

    /// Win rate of a set of seats — the form agent comparisons need.
    public func winRate(ofSeats seats: Set<Int>) -> Double {
        guard !completedMatches.isEmpty else { return 0 }
        let wins = completedMatches.count { outcome in
            (outcome.result?.winningSeats ?? []).contains { seats.contains($0.index) }
        }
        return Double(wins) / Double(completedMatches.count)
    }

    public var summary: String {
        var lines = [
            "matches: \(matchCount)  clean: \(isClean)  completed: \(completedMatches.count)",
            "actions: avg \(String(format: "%.1f", averageActions)), min \(shortestMatch), max \(longestMatch)",
            "thinking: \(averageDecisionDuration) per action",
        ]
        if !isClean {
            lines.append("failing seeds: \(failingSeeds.map(String.init).joined(separator: ", "))")
            for outcome in failures.prefix(3) {
                lines.append("  seed \(outcome.seed): \(outcome.failure!)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
