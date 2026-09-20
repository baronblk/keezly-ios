# Keezly — Computer Opponents

**Implementation status: the boundary exists, the agents do not.**

| Part | Status |
|---|---|
| `PlayerObservation` — the information boundary | **IMPLEMENTED + TESTED** |
| Move previews inside the boundary (DEC-015) | **IMPLEMENTED + TESTED** |
| `AIAgent` protocol and `AIBudget` | **IMPLEMENTED** |
| Easy agent | **IMPLEMENTED + TESTED** |
| Medium agent + `PositionEvaluator` | **IMPLEMENTED + TESTED** |
| Hard agent — determinization + rollouts | **IMPLEMENTED + TESTED** |
| Headless simulation harness | **IMPLEMENTED + TESTED** |

Tracked as M3 in `ROADMAP.md`.

---

## The one non-negotiable rule

**The AI does not cheat.** It never sees another player's hand, never sees the
order of the deck, and never sees anything a human player at the table could not
work out for themselves.

This must be structural, not a promise. Agents will not receive a `GameState`
at all. They receive a `PlayerObservation`, a value type that simply does not
contain the hidden information, so there is no path from an agent to another
seat's cards even by mistake.

### `PlayerObservation` — permitted contents

Implemented in `Sources/KeezlyCore/AI/PlayerObservation.swift`. Its initialiser
is the single chokepoint where hidden information is dropped.

- the agent's own hand
- every pawn's position (public — it is on the board)
- the discard pile, i.e. every card already played this cycle
- how many cards each other seat is still holding
- which seats have folded or resigned
- team composition, the dealer, the deal round, the rule set
- the legal moves available to the agent

### Explicitly excluded

- the concrete cards in any other hand
- the order of the remaining deck
- the RNG state
- anything about future deals

A card-counting deduction — "all four Aces have been played, so nobody can bring
a pawn out" — is legitimate and expected, because a human can do the same. It
comes from the discard pile, which is public, and is exposed as
`observation.unseenCards`: the full deck minus your own cards minus everything
played. It says which cards are still hidden, never *where* they are.

### How the guarantee is tested

Not by inspecting the agent's behaviour — by differential testing of the type.
Two game states that differ only in something an agent must not know must
produce **identical** observations:

| Differs only in | Observations must be |
|---|---|
| opponents' hands | equal |
| draw-pile order | equal |
| random generator state | equal |
| any pawn position, or the discard pile | **different** |

The last row matters as much as the others: a boundary so tight that the agent
cannot see the board would be equally useless.

These tests were verified to actually bite. Injecting `state.hands` into
`PlayerObservation` makes `opponentHandsDoNotLeak` fail, which is the evidence
that the suite is not passing vacuously. A full six-player match is also played
out while asserting, after every action, that no other seat's card is ever
visible to the observer.

---

## Difficulty levels

Three genuinely different agents. None of them is made stronger by being given
extra information or a rigged deal; strength comes only from search and
evaluation quality (§21).

### Easy — implemented

`EasyAgent` draws from the legal moves with a **weighted** random choice, not a
uniform one. Five features and nothing more: take a capture, bring a pawn out,
reach home, keep your start blockade, and a strong aversion to hitting your own
side. Weights live in the type and are listed below; a wide jitter (×0.7…1.3)
keeps it inconsistent.

| Feature | Weight |
|---|---|
| base | 1.00 |
| captures an opponent | +2.00 |
| brings a pawn out | +1.20 |
| reaches home | +3.00 |
| captures its own or its partner's pawn | −6.00 |
| gives up its own start square while pawns still wait | −0.60 |
| floor (so a forced move stays reachable) | 0.02 |

The small feature set is the design, not a shortcut: a beginner who never
blunders is not a beginner. Measured behaviour: it takes an available capture
in ~75% of positions offering one, and hits its own partner in under 8% of
positions where an alternative exists — the residual is the floor doing its job
when the forced-move rule leaves no choice.

### Medium — implemented

`MediumAgent` previews every legal move and scores the **resulting position**
with `PositionEvaluator`. It plans exactly one move ahead and does not search;
that is the honest ceiling of a heuristic agent and is the gap Hard fills.

The design rule is that a move is never pattern-matched. A Jack that throws a
pawn thirty squares forward and a Ten that advances it ten are the same kind of
thing — progress — and both fall out of the position score with no special
case. Only effects genuinely invisible in the resulting position get their own
term, which in practice means captures: once a pawn is back in its waiting
area, the position no longer records how far it had come.

All weights live in `HeuristicWeights`, one reviewable table. Factors:

- own and partner progress toward home; opponent progress
- pawns still waiting versus pawns in play
- creating or holding a protected start blockade
- capturing an opponent, especially one close to home
- exposing own or partner pawns to likely capture
- reaching home
- value of a Jack swap and of a backward Four as a shortcut to the home entry
- quality of a Seven split
- card-availability inferences from the discard pile

Weights live in `HeuristicWeights` and are documented there whenever they
change. No undocumented tuning (§146).

**Card counting is real, not decorative.** The risk term asks, for each of the
agent's exposed pawns: how far behind it is each opponent pawn, and how likely
is that opponent to still hold a card covering exactly that distance? The
probability comes from `unseenCards`. Consequences that fall out for free:

- a distance of **eleven is never threatening** — no card travels eleven squares,
  since the Jack swaps rather than lands;
- a distance of **four is only reachable by a split Seven**, because the Four
  moves backward;
- an opponent sitting **four squares ahead** is dangerous, for the same reason;
- once **all four Queens have been played**, a pawn twelve squares in front of
  an opponent stops reading as exposed. This is asserted directly by
  `MediumAgentTests.cardCountingLowersRisk`.

### Hard — implemented

`HardAgent` starts from the Medium evaluation and then asks what Medium cannot:
how does this tend to turn out? Information-set sampling:

1. enumerate the legal moves
2. sample plausible opponent hands **only from the cards that could still be
   there**, given the discard pile and each seat's known card count
3. simulate several continuations per candidate move
4. combine the heuristic score with the sampled outcome
5. play the best candidate

The agent still never knows a real opponent card; it reasons about a
distribution. It must not "signal" a partner through anything but public play.

---

## Performance requirements

- Fully on device. No server, no cloud inference, no network dependency.
- Search runs in a cancellable `Task` with an explicit time budget.
- The main actor is never blocked.
- Target: a move chosen in well under one second. A small deliberate "thinking"
  pause is allowed for feel, but not long waits.

---

## Simulation harness (M3.5)

A headless runner able to play thousands of matches and report:

- Easy vs Easy, Medium vs Easy, Hard vs Easy, Hard vs Medium
- all team combinations, seat counts 2 through 6

It must detect deadlocks, infinite loops, illegal moves, corrupted state,
unfair information access and implausible match lengths.

The engine is already suitable for this: `InvariantTests` plays 221 complete
randomised matches today and checks invariants after every action.

---

## Results

No simulations have been run. This section will hold measured win rates, match
lengths and known weaknesses once the agents exist. Until then it stays empty
rather than holding estimates (§151).
