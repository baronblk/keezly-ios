# Keezly — Project Handout

> **Before modifying the project, read:**
> 1. `PROJECT_HANDOUT.md` (this file)
> 2. `CURRENT_STATE.md` — what actually works right now
> 3. `ROADMAP.md` — what is planned, and what "done" means
> 4. `DECISIONS.md` — decisions that must not be silently reversed

---

## What is Keezly?

Keezly is a native Apple board-game app: a modern digital take on the
traditional Dutch card-driven board game **Keezen**.

| | |
|---|---|
| App name | Keezly |
| App Store name | Keezly: Keezenspel |
| Target version | 1.0.0 |
| Platforms | iPhone and iPad (iPad is a first-class platform, not a scaled-up phone layout) |
| Bundle identifier | **not yet decided** — see `CURRENT_STATE.md` → Manual Actions |
| Repository | https://github.com/baronblk/keezly-ios |

Players race four pawns each around a shared track and into their own home
lane. Movement is driven by playing cards rather than rolling dice. Version
1.0.0 supports 2–6 players, free-for-all and team play, local pass-and-play,
AI opponents at three strengths, and Game Center turn-based online matches.

The 1.0.0 scope is a finished, shippable product — not an MVP. The full
specification lives in the project brief; `ROADMAP.md` tracks it as milestones.

---

## Technology

| Area | Choice |
|---|---|
| Language | Swift 6 (language mode v6, strict concurrency) |
| UI | SwiftUI + Observation |
| Concurrency | Swift Concurrency |
| Game rules | `KeezlyCore` — a plain Swift package, no UI/GameKit/persistence dependencies |
| Online play | GameKit turn-based multiplayer |
| Persistence | SwiftData / `Codable` snapshots (not yet implemented) |
| Minimum OS | iOS / iPadOS 17.0 |
| Built with | Xcode 27.0, Swift 6.4, iOS 27.0 SDK |

No third-party runtime dependencies. Build-time tooling (XcodeGen, SwiftLint,
fastlane) is developer tooling, not shipped code.

---

## Architecture in one paragraph

`KeezlyCore` owns the rules and is the single source of truth. A `GameState`
is an immutable value; the only way to change it is `GameReducer.apply(_:to:)`,
which validates an action, returns a new state, and emits `GameEvent`s
describing what happened. Views animate those events — they never move a pawn
themselves. `MoveGenerator` decides what is legal; the reducer accepts exactly
what the generator offers, so the UI and the rules can never disagree.
Randomness runs through a serialisable `SeededGenerator`, which makes every
match reproducible. Full detail: `ARCHITECTURE.md`.

---

## Repository layout

```
Packages/KeezlyCore/     Rules engine + AI. Pure Swift, headless-testable.
  Sources/KeezlyCore/
    Board/               BoardGraph, BoardPosition — topology, never geometry
    Cards/               Card, Deck, Hand
    Models/              GameState, GameConfiguration, identifiers
    Rules/               RuleSet and its presets
    Moves/               Move, CardAction, PlayerAction, MoveError
    Engine/              MoveResolver, MoveGenerator, GameReducer
    Events/              GameEvent, GameTransition
    Random/              SeededGenerator
  Tests/KeezlyCoreTests/
App/Keezly/              App target sources          (not created yet)
App/KeezlyUITests/       XCUITest + screenshot harness (not created yet)
fastlane/                Lanes, Snapfile, metadata   (not created yet)
ci_scripts/              Xcode Cloud hooks           (not created yet)
Brand/AppIcon/           Icon source, previews, final (not created yet)
docs/                    Detailed documentation
```

Root-level Markdown files are the **project memory** (§127) and are kept
current continuously. `docs/` holds longer-form detail.

---

## How do I build and test?

### Rules engine (fast, no Xcode project needed)

```bash
cd Packages/KeezlyCore && swift test
```

This is the main development loop today. It runs the whole rule suite
including randomised self-play in a few seconds.

```bash
cd Packages/KeezlyCore && swift build
```

### App

Not yet buildable — the Xcode project does not exist. See `ROADMAP.md` → M0.

### Fastlane / screenshots / CI

Not yet set up. See `CI_CD.md`, `FASTLANE.md`, `XCODE_CLOUD.md`, which
currently state honestly that these are NOT STARTED.

---

## Which rules does the engine implement?

The playing rules are described in `RULES.md`. Every point where Keezen has
regional or family variation is a named option in `RuleSet`, catalogued with
its reasoning in `RULE_VARIANTS.md`. Three presets exist: **Keezly Classic**
(the default), **Tournament**, and **House Rules** (user-configurable).

Key rules that surprise newcomers:

- **Forced move** — if any legal move exists, you must play one, even a bad one.
  Only a completely dead hand may be thrown in.
- **Friendly fire** — under Classic rules, landing on your own or your
  partner's pawn captures it. The forced-move rule means this can be unavoidable.
- **Protected start** — a pawn on its own start square cannot be captured,
  passed, or swapped. It is a real blockade.
- **Exact home entry** — a pawn enters home only with an exact count, and never
  jumps over a pawn already home.

---

## Game Center

Designed but not implemented. The plan is GameKit turn-based multiplayer with a
compact versioned state envelope; see `GAME_CENTER.md` and `DECISIONS.md`
(DEC-006). Nothing is configured in App Store Connect yet.

---

## Where is the current status?

`CURRENT_STATE.md`. It names the active milestone, what is implemented vs.
tested vs. verified, the last verified commit, known problems, and the concrete
next step. It is updated at the end of every working session (§150).

---

## Working agreements

- **Commits**: Conventional Commits, English, imperative, lower-case, no
  trailing period, atomic, pushed immediately. No AI attribution anywhere.
- **Documentation is part of the work.** A feature is finished only when it is
  implemented, tested, and the project memory is updated (§155).
- **Say what is true.** `IMPLEMENTED` ≠ `TESTED` ≠ `VERIFIED` (§138). Never
  mark an external manual step as done without confirmation.
- **No secrets in the repository**, ever. `.gitignore` guards the usual
  suspects; release checks add a secret scan.
