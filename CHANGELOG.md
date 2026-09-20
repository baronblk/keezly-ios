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
- **Test suite**: 57 tests covering the board for every seat count, one test per
  card rank, game flow, and randomised self-play that plays 221 complete matches
  while asserting state invariants after every single action.
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
