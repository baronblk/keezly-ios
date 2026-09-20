# Keezly — Computer Opponents

**Implementation status: NOT STARTED.** Nothing in this document exists as code
yet. It records the design so it does not have to be re-derived, and so that the
information boundary is settled *before* the first agent is written (§146).

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
comes from the discard pile, which is public.

---

## Difficulty levels

Three genuinely different agents. None of them is made stronger by being given
extra information or a rigged deal; strength comes only from search and
evaluation quality (§21).

### Easy

Picks from the legal moves with a weighted random choice. Avoids the obviously
catastrophic — knocking out its own partner when an alternative exists, or
giving up a home-lane pawn — but is deliberately suboptimal and slightly
inconsistent, so it feels like a beginner rather than a broken expert.

### Medium

Applies each candidate move and scores the **resulting state**, rather than
matching moves against a tree of special cases. Factors to weigh:

- own and partner progress toward home; opponent progress
- pawns still waiting versus pawns in play
- creating or holding a protected start blockade
- capturing an opponent, especially one close to home
- exposing own or partner pawns to likely capture
- reaching home
- value of a Jack swap and of a backward Four as a shortcut to the home entry
- quality of a Seven split
- card-availability inferences from the discard pile

Weights live in one table and are documented here whenever they change. No
undocumented tuning (§146).

### Hard

Builds on the Medium evaluation and adds information-set sampling:

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
