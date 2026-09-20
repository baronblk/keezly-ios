# Keezly — Architecture

This document describes stable structure: layers, ownership, data flow and the
boundaries that must not be crossed (§145). It does not describe every type.
When a boundary changes, this file and `DECISIONS.md` change together.

---

## Layers

```
┌──────────────────────────────────────────────────────────────┐
│  App layer (SwiftUI)                                         │
│  Views · Scenes · Design System · Animation · Haptics · Audio │
└───────────────▲──────────────────────────────┬───────────────┘
                │ GameEvent stream             │ PlayerAction
┌───────────────┴──────────────────────────────▼───────────────┐
│  Session layer (@Observable)                                 │
│  MatchSession · AI driver · autosave · turn orchestration     │
└───────────────▲──────────────────────────────┬───────────────┘
                │                              │
     ┌──────────┴──────────┐        ┌──────────▼──────────┐
     │  Services            │        │  KeezlyCore         │
     │  GameCenterService   │        │  rules · board      │
     │  PersistenceService  │        │  cards · moves      │
     │  StatisticsService   │        │  AI agents          │
     │  (protocol-based)    │        │  Foundation only    │
     └──────────────────────┘        └─────────────────────┘
```

Only the outer two layers exist as a plan. Today **only `KeezlyCore` is built**.

---

## Ownership

| Concern | Owner | Never touches it |
|---|---|---|
| Rules, legality, state transitions | `KeezlyCore` | Views, services |
| What a move looks like on screen | App layer | `KeezlyCore` |
| Board coordinates, sizes, angles | App layer | `KeezlyCore` |
| Match lifecycle, AI scheduling | Session layer | `KeezlyCore` |
| Network, disk, Game Center | Services | `KeezlyCore` |

`KeezlyCore` imports only `Foundation` (DEC-001). It has no notion of pixels,
players' names, devices, or time.

---

## Data flow

Every change follows one path (§19):

```
PlayerAction (or AI decision)
      │
      ▼
GameReducer.apply(_:to:)
      │  ├─ validate: is this exactly a move MoveGenerator would offer?
      │  ├─ MoveResolver: resolve blocking, landing, capture
      │  ├─ mutate a copy of the state
      │  └─ evaluate victory, pass the turn, redeal if needed
      ▼
GameTransition { newState, [GameEvent] }
      │
      ├─────────────▶ new GameState  (immediately authoritative)
      └─────────────▶ events          (the UI animates these, afterwards)
```

Two properties fall out of this and are non-negotiable:

1. **Views never mutate the board.** A view sends a `PlayerAction` and receives
   a new state plus events. An animation visualises history; it never *is* the
   move. This is what stops pawns appearing to jump on their own (§68).
2. **`GameState` is authoritative the instant the reducer returns.** Input is
   locked while the event stream plays out, but the state is already final, so
   a double tap cannot apply a move twice.

---

## KeezlyCore module map

| Folder | Contents | Notes |
|---|---|---|
| `Random/` | `SeededGenerator` | SplitMix64; whole state is one `UInt64` |
| `Board/` | `BoardGraph`, `BoardPosition`, `PawnState` | Topology only |
| `Cards/` | `Card`, `CardRank`, `CardSuit`, `Deck`, `Hand` | Suits are decorative |
| `Models/` | `GameState`, `GameConfiguration`, `Seat`, `PawnID`, `TeamID`, `DealState`, `GameResult` | |
| `Rules/` | `RuleSet` and its option enums | Presets: Classic, Tournament, House |
| `Moves/` | `Move`, `CardAction`, `SplitStep`, `PlayerAction`, `MoveError` | |
| `Engine/` | `MoveResolver`, `MoveGenerator`, `GameReducer` | |
| `Events/` | `GameEvent`, `GameTransition` | The animation contract |
| `Serialization/` | *(empty — M2.9)* | Versioned envelope goes here |

### The board is a graph, not a picture

`BoardGraph` is generated from one rule: each seat contributes 16 squares to the
shared track. It answers *"which square is seven steps ahead of this pawn"* and
*"which squares does that cross"*. It never answers *"where on screen"*.

The key abstraction is **progress**: a seat-relative coordinate where 0 is that
seat's start square and `lapLength` is its home entry. Forward movement is
arithmetic on progress; backward movement is arithmetic on raw track indices,
which is precisely why a Four can never wander into a home lane.

### One resolver, two callers

`MoveResolver` implements the elementary mechanics — can this pawn pass that
square, can it land there, whom does it capture. `MoveGenerator` calls it to
enumerate; `GameReducer` calls it to apply. Neither re-implements a rule
(DEC-004).

---

## State management

- `GameState` is a `Hashable`, `Codable`, `Sendable` value type.
- Mutating helpers on `GameState` are `internal`, so only the engine can use
  them; the public surface is read-only plus `GameReducer.apply`.
- A `revision` counter increments on every applied action. It is the basis for
  idempotent online turn submission (§28) and for rejecting stale updates.
- The RNG state travels inside `GameState`, so a snapshot fully determines the
  future of the match.

### Persistence and versioning (planned, M2.9)

`GameState` currently round-trips through `Codable`, but carries **no version
field**. Before any match is saved or sent over Game Center, it must be wrapped
in an envelope holding `schemaVersion`, `engineVersion`, `rulesVersion` and a
checksum, with a decoder that fails loudly and typed on an unknown newer
schema rather than silently mis-decoding.

---

## AI boundary (planned, M3)

AI agents live inside `KeezlyCore` but must not receive a `GameState`. They
receive a `PlayerObservation` containing only public information: their own
hand, pawn positions, the discard pile, how many cards each other seat holds,
teams, and the phase. There is deliberately no path from an observation back to
another seat's hand — "the AI does not cheat" is meant to be a property of the
type system, not a promise in a comment (§21). See `AI.md`.

---

## Service boundaries (planned)

Game Center, persistence and statistics are reached through protocols so tests
can substitute doubles (§66). GameKit types never appear in `KeezlyCore` and
never appear in view code either; they are confined to one adapter.

---

## Concurrency

- `KeezlyCore` is synchronous and `Sendable`. It does no I/O and spawns no tasks.
- AI search will run in a detached, cancellable `Task` with a time budget; the
  main actor is never blocked (§62).
- Because the engine is pure, an AI rollout is just repeated calls on a value
  copy — no locking, no shared mutable state.

---

## Test strategy

| Level | What it proves | Where |
|---|---|---|
| Board tests | The board is fair and closed for 2–6 seats | `BoardGraphTests` |
| Card rule tests | Each of the thirteen cards behaves as specified | `CardRuleTests` |
| Flow tests | Dealing, forced moves, victory, resignation, turn integrity | `GameFlowTests` |
| Invariant / fuzz | The engine cannot reach an impossible state | `InvariantTests` |
| UI tests | Layout, readability, targets, localisation | *(not yet)* |
| Simulation | AI strength ordering, no deadlocks at scale | *(not yet)* |

The invariant suite plays complete randomised matches and re-checks pawn and
card conservation after *every* action, which is what catches the class of bug
that unit tests structurally cannot.
