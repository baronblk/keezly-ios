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
- **Pass & play**: up to six people sharing one device. Before each person's
  turn the board is covered by a plain screen with their name and one button,
  and the cards are drawn only for whoever has said they are holding the
  device — so nobody sees anybody else's hand, even for an instant.
- **A menu to set up the table**: two to six players, partners or everyone for
  themselves, and opponents at three strengths. The seats are shown as they
  will be dealt, so choosing a table shows what the table will look like rather
  than only setting a number. Partners are offered only where they mean
  something — never at two players, where the engine would otherwise put both
  players on the same side.
- **A playable game on iPad and iPhone.** One player against three computer
  opponents: a wooden board with milled holes and seated pieces, real playing
  cards with classic corner indices, and the flow card → pawn → square. Illegal
  targets are never offered, and a Seven can only be started in a way that can
  be finished.
- **Its own layout on each device.** The iPad puts the width beside a square
  board to work with seat status panels; the iPhone uses compact seat chips and
  switches to a short-and-wide arrangement in landscape rather than shrinking
  the board. Verified on the smallest, standard and largest iPhones.
- **Animation that follows the game.** A piece walks the squares it passes, a
  capture is shown after the move that took it, and a swap moves both pieces at
  once. Interrupting an animation — leaving the app, closing the screen — always
  leaves the board on the true position. Reduce Motion lands moves instead.
- **Deterministic screenshot mode** with a fixed seed and seat count, so a
  design review and the App Store captures show the same board every run. It
  can also fast-forward a match to a situation worth photographing — a playable
  Jack, a Seven halfway through its split — which the opening deal can never
  show, because those cards need pieces already on the track.
- **Pointer and keyboard control on iPad.** Cards lift under the pointer,
  squares highlight, and the whole game can be driven from the keyboard: arrows
  move, return plays, escape cancels. The focus ring is drawn in black and
  white so it never depends on colour. Touch is unchanged and remains complete
  on its own.
- **Depth and balance across the board**: holes that read as drilled rather
  than drawn, player colours with more presence but no less restraint, a
  modelled edge that sets the board on a dark table, a calmer middle where the
  cards are what you see first, and seat panels made of the same wood as the
  board rather than grey system chrome.
- **A quiet Dutch identity on the board**: a tulip-and-lozenge border engraved
  into the rim, a medallion framing the cards, a chevron at the end of each home
  lane, and a single orange keystone. Ornament, not illustration — from playing
  distance it reads as a well-made board, and only up close does the detail
  appear.
- **Device testing tooling**: `scripts/devices.sh` finds the physical iPhones
  and iPads paired with the development Mac and maps them onto stable roles,
  without ever storing a device name or identifier in the repository.
- **Test suite**: covering the board for every seat count, one test per
  card rank, game flow, serialisation, the AI information boundary, and
  randomised self-play that plays 221 complete matches while asserting state
  invariants after every single action.
- **Project memory**: `PROJECT_HANDOUT.md`, `CURRENT_STATE.md`, `ROADMAP.md`,
  `DECISIONS.md`, `ARCHITECTURE.md`, `RULES.md`, `RULE_VARIANTS.md`,
  `KNOWN_ISSUES.md` and this changelog.
- **Main menu and table configuration** — two to six seats, partners or
  everyone for themselves, one to six people sharing the device, three opponent
  strengths, and the table shown as it will be dealt.
- **Pass and play** — the device goes round the table behind a handover screen.
  The hand is built only for the seat holding the device, so the cards are not
  merely covered during a handover; they are not there.
- **Autosave and resume** — a match is its seed and its accepted actions,
  written atomically after every accepted action and before the animation
  starts. Restoring replays every action through the engine and refuses rather
  than repairs; a save that will not open is quarantined, never deleted.
- **Game Center groundwork** — a versioned turn envelope over a transport
  protocol with no GameKit types in it, explicit seat-to-participant mapping,
  idempotent turns, and a two-client test harness whose clients share no
  session state. Not verified end to end: that needs the App Store Connect
  record.
- **A list of every legal move**, spoken and playable. It is the same moves as
  the board — the same `MoveGenerator`, asserted by a test comparing the two
  sets — so a player who cannot use the board is not playing a lesser game.
- **The board in words** — every pawn named with where it stands and how far it
  has left to go, every destination with what is already on it, and the start of
  your turn announced rather than left to be discovered. Narrated from the same
  information an AI agent gets and no more.
- **An in-app rulebook** in Keezly's own words, with the rules *this table* is
  playing marked and both readings shown wherever tables disagree.
- **A tutorial of ten lessons**, each an ordinary match on the real engine.
  Nothing is scripted: the lesson watches the board before and after your move,
  so it cannot congratulate you for a move you did not make.
- **A way out and a way to look things up** from inside a match, and an ending:
  a finished match now says who won and offers the way back to the menu.

### Fixed

- A two-player board had no room in the middle for the draw pile and the played
  card, which were drawn across the home lanes. Two players now have the cards
  beside the board instead.
- The board could be drawn wider than the screen in portrait and was clipped.
- The far seat panel hung off the right edge of an iPad.
- The outermost two cards of a hand were cut off at the edges of a phone.
- The far seat panel was drawn past the right edge of a portrait iPad. The
  arithmetic had been reviewed twice, in landscape, where it happens to fit; it
  is now a tested calculation rather than a judgement about screenshots.
- The rulebook showed its lookup keys instead of its text for one build. A
  string literal with an interpolation in it takes `LocalizedStringKey`'s
  *interpolating* initialiser, which looked up `rules.%@.title` and found
  nothing.

- Landscape screenshots came out on their side and could not have been
  submitted to the App Store.
- The cards in the middle of the board were sized from the screen rather than
  from the board, so on a two- or three-player table they were drawn across the
  home lanes.

- Six players on an iPhone pushed the layout wider than the screen and clipped
  the board.
- An iPhone in landscape could report a regular width, which left the board at
  149 points on a 393-point screen.
- The interface used fixed font sizes throughout, so Dynamic Type had no effect
  at all. Chrome text now follows the reader's setting; card ranks and pips
  stay proportional to the card, because a rank that outgrew its card would be
  less readable, not more.
- Labels in the middle of the board truncated at large text sizes instead of
  wrapping.

### Security

- `.gitignore` blocks signing keys, provisioning profiles, certificates, App
  Store Connect API keys and `.env` files from ever being committed.

---

## Not yet in this changelog

No onboarding screens, in-game card help or hints. No statistics, match history
or replay playback. No audio, haptics or app icon. Game Center is implemented
but has never been run against a real match. Xcode Cloud is prepared but not
configured. See `CURRENT_STATE.md` for exactly what exists and what has been
verified where.
