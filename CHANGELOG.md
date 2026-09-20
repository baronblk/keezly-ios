# Changelog

All notable changes to Keezly. Kept continuously, not reconstructed at release
time (§136). Format follows Keep a Changelog; versions follow Semantic
Versioning.

---

## [Unreleased]

### Added

- **KeezlyCore rules engine** — a framework-free Swift package holding the
  complete Keezen rule set, testable headlessly with `swift test`.
- **Parametric board** for 2 to 6 players, generated from a single rule rather
  than hard-coded per player count. Four players produce the classic 64-square
  track with 16 waiting and 16 home squares.
- **Full card set**: Ace (enter or +1), King (enter), Queen (+12), Jack (swap),
  Four (four backward), Seven (split across one or two pawns), and the plain
  number cards.
- **Seven-split generator** that enumerates only complete, playable sequences —
  including the team hand-off where the first leg finishes your own pawns and the
  rest is spent on a partner's.
- **Blocking and capture rules**: protected start squares as absolute
  blockades, exact home entry, no jumping over pawns already home, and classic
  friendly fire.
- **Forced-move rule**: a legal move must be played; a completely dead hand is
  thrown in and that seat sits out the rest of the deal round.
- **5/4/4 deal cycle** with dealer rotation and reshuffle.
- **Team and free-for-all play**, partner continuation once a player finishes,
  and the resignation policy for both modes.
- **Rule variants** as named options with three presets (Keezly Classic,
  Tournament, House Rules): King behaviour, Jack from a protected start, home
  entry, home ordering, friendly capture, and own-pawn blocking.
- **Determinism**: all randomness runs through a serialisable SplitMix64
  generator whose state lives inside the game state, so any match is reproducible.
- **Versioned save format**: matches are wrapped in a `GameStateEnvelope`
  carrying a schema version, engine version, rules version and checksum. A match
  saved by a newer version of Keezly, a damaged save, or one too large for its
  transport is reported clearly instead of being partly restored.
- **Byte-stable encoding** so two devices can prove they hold the same board.
- **Xcode project** for iPhone and iPad, generated from `project.yml` and
  committed, with a shared scheme covering the app, unit tests and UI tests.
- **fastlane** through Bundler with lanes for tests, QA, the release gate, and
  the physical-device gates.
- **AI information boundary**: computer opponents receive only a
  `PlayerObservation` — their own cards, the open board, the cards already
  played and how many cards each opponent holds. There is no route from an
  agent to another player's hand or to the shuffled deck, so a computer
  opponent cannot cheat even by accident.
- **Computer opponents** at three genuinely different strengths. Easy plays
  plausibly but improvably; Medium weighs each move by the position it produces
  and keeps track of which cards have been played; Hard additionally imagines
  many plausible deals and prefers the move that tends to end well. None of
  them can see another player's cards.
- **Replay**: finished matches can be played back exactly, move by move,
  because the engine is deterministic.
- **Device testing tooling**: `scripts/devices.sh` finds the physical iPhones
  and iPads paired with the development Mac and maps them onto stable roles,
  without ever storing a device name or identifier in the repository.
- **Test suite**: 79 tests covering the board for every seat count, one test per
  card rank, game flow, serialisation, the AI information boundary, and
  randomised self-play that plays 221 complete matches while asserting state
  invariants after every single action.
- **Project memory**: `PROJECT_HANDOUT.md`, `CURRENT_STATE.md`, `ROADMAP.md`,
  `DECISIONS.md`, `ARCHITECTURE.md`, `RULES.md`, `RULE_VARIANTS.md`,
  `KNOWN_ISSUES.md` and this changelog.

### Security

- `.gitignore` blocks signing keys, provisioning profiles, certificates, App
  Store Connect API keys and `.env` files from ever being committed.

---

## Not yet in this changelog

The app itself does not build yet — there is no Xcode project, no UI, no AI, no
Game Center integration and no CI. See `CURRENT_STATE.md` for exactly what
exists and `ROADMAP.md` for what is planned.
