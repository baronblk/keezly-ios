# Keezly — Current State

**This file is the operative memory of the project (§128).** It describes what
is true right now, not what is planned. Plans live in `ROADMAP.md`.

---

## Last Verified Commit

```
1a03343  feat(l10n): gate the String Catalog, and say one thing one way per language
```

Verified on **2026-09-22** with Xcode 27.0 / Swift 6.4 on macOS 26 (arm64).

---

## Current Milestone

| Milestone | Status |
|---|---|
| M0 — Repository & Foundation | **DONE** |
| M1 — GameCore / Rules | **DONE** |
| M2 — Complete Move Engine | **DONE** |
| M3 — AI | **DONE** |
| M4 — Gameplay UI (iPad / iPhone) | **DONE** |
| M5 — Local Multiplayer / Pass & Play | **DONE** |
| M6 — Game Center | **IMPLEMENTED, NOT VERIFIED** (MAN-02) |
| M7 — Tutorial / Rulebook / Accessibility | **DONE** |
| M8 — Brand / App Icon / Audio / Haptics | **IMPLEMENTATION COMPLETE** — audio present and measured, **not listening-verified**; icon not **DEVICE VERIFIED** |
| M9 — Statistics / Replay / Game Center Meta | **DONE** — reporting **BLOCKED** (MAN-02) |
| M10 — Localisation | **DONE** |
| **M11 — CI / QA / Hardening** | **NOT STARTED** |

Everything up to and including M3 lives in `KeezlyCore`, which is testable with
`swift test` alone. From M4 on the work is mostly app-layer.

**The game is complete as a game.** Two to six seats, any mix of people and
computers sharing one device, in pairs or everyone for themselves; a match
saves itself after every accepted action, can be picked up again, says who won
and can be watched back afterwards. It teaches itself in ten lessons, answers a
rule question without leaving the board, can be played entirely from a spoken
list of moves, and speaks German, Dutch and English.

What is left before a release is release work: CI, the device gates, and the
App Store Connect record everything online depends on.

### Status vocabulary

Three different questions, never merged into one answer (§167):

| Term | Means |
|---|---|
| **DESIGN IMPLEMENTED** | It exists in code |
| **SIMULATOR VERIFIED** | It was built and tested on a simulator |
| **PHYSICAL DEVICE VERIFIED** | It was built and tested on real hardware |
| **NOT VERIFIED — HARDWARE NOT AVAILABLE** | Built, but the equipment to test it does not exist here. Never counted as a pass |

### Design status (DEC-018, DEC-019)

Visual direction is **tactile digital board game**, material **Classic Wood**:
a maple panel with round milled holes, pawn silhouettes seated in them, and real
playing cards with classic corner indices and traditional pip layouts. The full
design system is in `docs/UI_UX.md`.

Reviewed against the seven design questions on iPad 13" landscape and portrait
and on iPhone — smallest, standard and largest — in both orientations, at four
and six players:

| | |
|---|---|
| Reads as a real board game | **yes** |
| Cards look like real cards | **yes** |
| Card values instantly readable | **yes** — the corner index survives the fan |
| Pieces have enough presence | **yes** |
| Track immediately understandable | **yes** |
| Good enough for App Store screenshots | **yes**, iPad and iPhone |
| iPad uses its area convincingly | **yes in landscape** — the width beside a square board carries the seat panels |
| iPhone is its own layout, not a shrunken iPad | **yes** — compact chips instead of named panels, and a separate short-landscape arrangement |

**The iPhone pass is done.** It found two real defects rather than rough edges:
six seat panels pushed the layout wider than the screen and clipped the board,
and the interface used fixed font sizes throughout, so Dynamic Type had no
effect at all. Both are fixed and captured.

**Animations are event-driven.** A pawn visits every square it passes, and a
capture is drawn after the move that caused it. The presenter holds its own
copy of the positions and cannot reach `GameState`; an interrupted animation
always settles on the true position.

**Game Center has a model, a boundary and tests — but no real run (M6,
DEC-024).** There is no online engine: a match across devices is the same
record as one on the sofa. Between the engine and Apple sits `MatchTransport`,
five methods with no GameKit type in them, so every online rule is tested
against a mock with no account, no network and no simulator.

| Part | Status |
|---|---|
| Turn envelope, revisions, idempotency, validation | **MOCK VERIFIED** (29 tests) |
| Two clients exchanging a match over many turns | **MOCK VERIFIED** (12 tests) |
| Participant mapping, teams at 4 and 6 seats, several matches at once | **MOCK VERIFIED** |
| Authentication state machine | **TESTED** as a pure function |
| `GameCenterTransport`, the GameKit adapter | **IMPLEMENTED, NOT VERIFIED** |
| A real match between two Apple Accounts | **BLOCKED** — MAN-02, MAN-05, MAN-11, MAN-12 |
| Hidden information against a modified client | **NOT PROTECTED** — accepted, DEC-025 |

A turn carries its own `moveID`, the revision it was made against and the one
it produces, which gives five distinct answers — accepted, duplicate, stale,
out of order, rejected — each handled separately. A duplicate is recognised by
identity *before* its revision would make it look stale.

Arriving data is never taken as a position. It is decompressed, version- and
checksum-checked, then **replayed through the real engine**, with the revision
required to rise at every action and to land exactly where the sender claimed,
and the resulting board's checksum compared with the one sent.

****A fairness limitation was found and is written down, not argued away
(ISS-015, DEC-025).** Every participant receives the same match data, which
carries the seed and the accepted moves — so every device can reconstruct every
opponent's hand and the order of the undealt deck. A test demonstrates it from
the payload alone, using nothing but the app's own loading path.

It is structural rather than careless: the replay-and-compare check that makes
a remote move trustworthy works *because* the receiver can reproduce the whole
game. Three claims are kept apart, and only the first is made:

| | Claim | Status |
|---|---|---|
| **A** | Keezly does not leak hidden information through its own interface or agents | **Holds**, tested |
| **B** | A modified client cannot learn hidden information | **Does not hold** |
| **C** | Cheating is prevented — server-authoritative, or a multi-party protocol | **Not attempted**; either would work |

Online play in 1.0.0 is friendly play. Online results are therefore not a sound
basis for a competitive leaderboard — a constraint that lands on M9.

**A size problem was found before it could ship.**** A four-hundred-move
six-player match came to **64,384 bytes** of JSON against Game Center's
65,536-byte limit — a full six-player match would not have fitted. Compressing
the canonical bytes brings the same match to **4,173 bytes**. A test holds the
number.

**A match survives the app being closed (M5, DEC-023).** It is stored as its
configuration, its seed and the actions the engine accepted — nothing else, and
certainly no taps, selections or animation progress. Replaying them reproduces
the position exactly.

Written between the engine accepting a move and the board beginning to show it,
atomically, so an interrupted animation can never correspond to half a move on
disk. Coming back runs eight checks in order — wrapper version and checksum,
engine schema, rules and checksum, every action revalidated by the real engine,
the revision rising on each and landing exactly where it was saved, and the
position's own checksum. Any failure is a typed refusal; the file is moved
aside rather than deleted, because it is the only evidence of what went wrong.

**A resumed pass-and-play match comes back covered**, even if a hand was on
screen when the app was closed. Verified by a UI test that really terminates
and relaunches the app, then counts the cards on screen: zero.

**Pass & play works, and keeps its one promise (M5, DEC-022).** Up to six
people share the device. Before each person's turn the board is covered by a
plain opaque screen with their name and one button — no hand, no counts,
nothing that rewards holding on to the device.

The promise is not made by the cover. The hand is *built* only for the seat
that has said it is holding the device, checked where the hand is made as well
as behind the cover, so the cards would not appear even if the cover failed to
draw. A UI test counts the cards on screen while the cover is up and requires
zero, on a table where every seat is a person so that every turn is a handover.

A table with one person never sees any of it: no cover, no extra tap.

**The app opens on a menu (M4.0).** Two to six players, partners or everyone
for themselves, three opponent strengths, and the seats shown as they will be
dealt — choosing a table shows what the table will look like rather than only
setting a number. Partners are offered only where they mean something: at two
seats the engine would pair a seat with itself, so a two-player table is always
everyone alone, and the control says so rather than accepting a choice it would
then ignore.

Nothing else is on the menu. There is no rulebook, tutorial or online button,
because a menu item that does nothing is worse than a missing one (§36).

**Screenshot orientation is fixed (ISS-009).** Landscape captures come out
landscape-shaped and upright, and every capture now asserts its own shape, so
the defect cannot return unnoticed. The cause was the platform: every XCUITest
screenshot API returns the physical framebuffer, which stays portrait however
the app is rotated. A separate defect remains — the captures carry a 25% black
margin (ISS-012), measured at exactly 516 of 2064 rows on every landscape
capture and none on any portrait one. It is a capture artefact, not something
wrong with the interface, and it is settled in M11 where the captures move to
files.

**The board's middle is solved on every table and every screen (ISS-013,
DEC-021).** The quiet middle is not a constant: measured in square pitches it
is 1.2 at two seats, 2.7 at three and 4.9 at four. At two seats the home lanes
very nearly meet, so they are set side by side rather than nose to nose — which
is what gives that board a middle at all — and even then there is not room for
a pile and a played card, so a two-player table shows the table's own cards
**beside** the board, in a wooden tray opposite the other player. Shrinking
them to fit was tried and made them unreadable, which is worse than crowding.

What is drawn in the middle is now sized against the **middle**, measured, and
not against the view: the two stopped being the same thing when the board's
bounds grew to hold the panel, its shadow and the air around it. And a board
too small to draw its two text labels at their designed size keeps the piles
and moves the labels to a line beneath it — a phone's board is about a hundred
points across the middle, where an eleven-point floor makes the turn pill half
again the size it was drawn to be. The rules and `BoardGraph` are identical for
every table size; only the presentation adapts, and every decision is written
as a rule about available space rather than a special case for a seat count or
a device.

**A polish pass across the board (DEC-021).** Deeper holes so the track reads,
stronger but still restrained player colours, a modelled edge with a contact
shadow, a quieter medallion behind the cards, seat panels made of the board's
own wood instead of grey system material, and a finer card stock. No redesign —
the Classic Wood direction and the Dutch ornament are unchanged.

Reviewing the captures found three clipping defects that no test had: the board
could be drawn wider than the screen, the far seat panel hung off the right
edge, and two cards were cut off at the edges of a phone. All three are fixed.

**Pointer and keyboard are implemented (M4.7, DEC-020).** Cards lift under the
pointer, squares highlight, arrows walk the hand and the board, return acts and
escape cancels — with a focus ring drawn in black and white so it does not
depend on colour. What can be verified here has been:

| Claim | Status |
|---|---|
| The keyboard's decision logic | **TESTED** — 16 unit tests, including that every legal move is reachable |
| Focus lands on a playable card, ring is visible, touch players see no ring | **SIMULATOR VERIFIED** |
| Pointer effects are attached only to live elements | IMPLEMENTED — a pointer is needed to see them |
| A key press actually arrives | **NOT VERIFIED — HARDWARE NOT AVAILABLE** |

The last row is the honest one. iOS hands a view focus only when a hardware
keyboard or Full Keyboard Access is present; a simulator booted by `xcodebuild`
has neither, and this Xcode installation ships no `Simulator.app` to attach one
to. The three UI tests that need real keys **skip** rather than pass
(`KeyboardPlayTests`), so the gap is visible in every test run instead of being
papered over.

**The board carries a quiet Dutch identity (DEC-019).** A running border of
tulips and lozenges engraved into the rim, a medallion framing the cards, a
chevron at the end of each home lane, and exactly one small orange detail. All
of it is Keezly's own geometry, all of it ton-in-ton, and none of it is drawn
where it could be confused with a playing square — which is tested, not
assumed.

Still open: no bespoke choreography for dealing, the Seven's legs or the Jack
swap; no haptics or audio; Dark Graphite is not offered in Settings; Split View
and Stage Manager are untested.

---

## Completed

### Repository and app project (M0)
- Xcode project generated from `project.yml` via XcodeGen and committed.
  Bundle ids `de.gcng.keezly` / `.tests` / `.uitests`, iOS 17.0 target,
  iPhone **and** iPad, Stage Manager compatible, shared `Keezly` scheme.
- App shell (`KeezlyApp`, `RootView`) — deliberately inert scaffolding, no
  buttons that do nothing. M4.1 replaces it.
- Versioning lives in `Config/Keezly.xcconfig`, **not** `project.yml`: a build
  setting on the project overrides any xcconfig and would silently defeat the
  CI build-number override.
- Signing team only in the git-ignored `Config/Local.xcconfig` (DEC-013).
- fastlane via Bundler (Ruby 4.0.5 pinned, fastlane 2.240.1 via `Gemfile.lock`).
  Lanes: `tests`, `ui_tests`, `lint`, `qa`, `release_check`, `asc_check`,
  `device_smoke`, `device_iphone`, `device_ipad`, `device_gate`.
- `ci_scripts/` for Xcode Cloud; the build-number override is verified end to
  end (`CI_BUILD_NUMBER=42` → `CFBundleVersion 42`; absent → 1).
- SwiftLint is the enforced gate (clean under `--strict`); SwiftFormat runs an
  allowlist (DEC-016).

### Rules engine (M1, M2)
- Deterministic `SeededGenerator` (SplitMix64), state inside `GameState`.
- Parametric `BoardGraph` for 2–6 seats; 4 seats → the classic 64+16+16.
- 13 ranks × one rank-set per seat; no rule reads a suit.
- All thirteen cards including complete Seven-split enumeration and the §17
  partner hand-off; protected start squares; exact home entry; friendly fire.
- 5/4/4 deal cycle, dealer rotation, forced move, automatic folding of dead
  hands, team and free-for-all victory, resignation policy.
- `GameStateEnvelope`: schema/engine/rules versions plus an FNV-1a checksum;
  refuses a newer schema, a damaged payload or an oversized one with typed
  errors. Byte-stable encoding (hand-written `Codable`, DEC-009).
  A six-player state is **4527 bytes** — ~7% of Game Center's 64 KiB budget.
- `MatchRecord` / `MatchRecorder`: a match is its seed plus its actions, so
  replay reproduces every state **and every event**. A 765-action six-player
  record is 122 KB.

### AI (M3)
- `PlayerObservation` is the only thing an agent receives (DEC-014), extended
  with move previews and a stable key (DEC-015). Differential + mutation tested.
- `EasyAgent` — weighted random over five features, wide jitter.
- `MediumAgent` + `PositionEvaluator` — scores the resulting position; the risk
  term uses card counting from the public discard pile.
- `HardAgent` — information-set sampling from `unseenCards` plus time-boxed,
  cancellable rollouts.
- `MatchSimulator` + `GameStateInvariant` — headless matches, every action
  checked, failures carry their seed for exact replay.

Measured results and sample sizes: `AI.md`.

### Playing screen (M4)
- Board drawn from `BoardGraph` in two layers: a static `Canvas` for the panel,
  ordinary views for the pawns, so there is no render loop (§62).
- Classic Wood with milled holes and a Dutch engraved border, medallion and
  home-lane chevrons (DEC-018, DEC-019).
- Three layouts, chosen by the space actually available rather than by size
  class: a phone stack, a short-landscape row, and a board flanked by seat
  panels where the width can hold one. The arithmetic is in `PlayLayout` and
  `StackedLayout`, swept by test across **every width from 320 to 1400** in
  both orientations — Split View panes and Stage Manager windows included —
  and it is continuous, so a resize drag never makes the board jump.
  `scripts/pane-review.sh` renders the real views at those sizes.
  **iPadOS's own multitasking mechanism is not exercised**: only the app's
  response to the sizes it produces.
- A two-seat table puts the draw pile beside the board rather than shrinking it
  past reading (DEC-021).
- `BoardPresenter` plays events one at a time, reorders a capture behind the
  move that caused it, honours Reduce Motion and settles on the true position
  on any interruption.
- Pointer, trackpad and full keyboard access (DEC-020). Key *delivery* is still
  **NOT VERIFIED — HARDWARE NOT AVAILABLE**.
- Main menu and table configuration; a finished match reports its result.

### Pass and play (M5)
- One device round a table, 2–6 seats, people and computers mixed (DEC-022).
  The hand is *built* only for the seat holding the device, so privacy is a
  property of the construction rather than of a cover that might fail to draw.
- Autosave and resume (DEC-023): seed plus accepted actions, written atomically
  before the animation starts. Restore replays every action through the engine
  and refuses rather than repairs; a refused save is quarantined, never deleted.

### Game Center (M6) — IMPLEMENTED, NOT VERIFIED
- One game model. `KeezlyCore` does not import GameKit; exactly one app file
  does (DEC-024).
- Versioned turn envelope, explicit seat↔participant mapping, `moveID` +
  `expectedRevision` idempotency, and a replay-and-compare `load` that refuses
  a board it cannot reproduce.
- A two-client harness where the clients share no session state, and a
  deterministic in-memory transport.
- The payload compresses from 64,384 bytes to 4,173 — measured, not assumed.
- **Hidden information is not protected against a modified client (DEC-025)**,
  demonstrated by `OnlineHiddenInformationTests` rather than assumed either way.

### Learning and accessibility (M7, in progress)
- **Action list (M7.7):** every legal move as a sentence, playable. It comes
  from the same `MoveGenerator` as the board, and `ActionListTests` asserts the
  two move *sets* are equal across two-, four- and six-seat walks.
- **Narration (M7.6):** pawns, squares and moves put into words from a
  `PlayerObservation` and never a `GameState`, so the spoken channel obeys the
  same boundary an AI agent does (DEC-014).
- **Rulebook (M7.3):** the rules in Keezly's own words, with the rules *this
  table* plays marked, both readings shown where tables disagree. `RuleFacet`
  is held against `RuleSet` by reflection, so a new rule option cannot reach
  the engine undocumented.
- **Tutorial (M7.2):** ten lessons, each an ordinary match on the real engine.
  A lesson reads the board before and after a move rather than the tap, so it
  cannot congratulate a player for something that did not happen; every seed is
  played through in the tests.

### Brand and feedback (M8)
- The app icon is **code**: `AppIconArtwork` draws it, three concepts were
  compared at every size an icon is drawn at, and `table` was chosen (DEC-026).
  `scripts/icon-check.sh` fails if the committed PNGs stop matching the source.
  **GENERATED**, **INTEGRATED & VERIFIED** — `assetutil` reports all three
  appearances in the built `Assets.car`, and the icon is on the iPad and iPhone
  simulator home screens after a clean install — but **not DEVICE VERIFIED**:
  it is installed on the physical iPad and that home screen has not been looked
  at from here. Three separate questions, kept separate (`APP_ICON.md`).
- Seven haptic cues derived from `GameEvent`, so a computer opponent's capture
  lands like the player's and a refused tap produces nothing. Runs collapse: a
  Seven split over seven squares is one knock.
- Sound is **ASSET PRESENT, NOT LISTENING-VERIFIED.** Seven cues ship, and
  they are *generated*, not sourced: `Tools/soundforge.py` synthesises them by
  modal synthesis — decaying sinusoids at the inharmonic ratios a small struck
  wooden body rings at, over a contact transient — so the provenance of the
  audio is the source code that made it and there is no third-party licence to
  resolve (§77, DEC-027).
  `Tools/soundcheck.py` measures what a machine can: no cue clips, none carries
  a DC offset, all seven decay like something struck, and each is short enough
  to hear two hundred times. It caught the capture cue coming out *brighter*
  than the gentle swap — the sound of a slap rather than a knock — now 980 Hz
  against 1887 Hz.
  What no test here establishes is whether they **sound good**, which needs
  ears in a quiet room on real hardware. Until that has happened M8 is not
  VERIFIED, and the release checklist says so in those words rather than
  counting the files and calling it done.

### History, replay and achievements (M9)
- Every saved match is listed, newest first, each already replayed and verified
  by the store before it appears. A finished match opens in the replay; an
  unfinished one is picked up.
- **Replay** is the seed and the accepted actions — the same two things a save
  is. Play, pause, step either way, scrub, three speeds. `ReplayRun` holds no
  store, so watching a match cannot change it.
- Statistics are **derived** from the saved matches, never kept beside them.
- Ten achievements, worked out by replaying a finished record and reading the
  engine's own events. Nothing reports them anywhere: that needs MAN-02.
- **No leaderboards**, deliberately: online results cannot be ranked honestly
  while a modified client can read every hand (DEC-025).

### Localisation (M10)
- German, Dutch and English, 283 keys, every one translated.
- `scripts/strings-check.sh` gates the catalogue without a simulator: missing
  or untranslated entries, keys the code asks for that do not exist, and
  placeholders that do not match the English. It found a string consuming two
  arguments where the call site passes one.
- One word per thing, per language, enforced by the same script.

---

## In Progress

Nothing is mid-edit. The working tree is clean at the commit above.

---

## Not Implemented Yet

- Reporting achievements to Game Center (M9.4) — blocked on MAN-02.
- Bespoke dealing, Seven-leg and Jack-swap choreography; the generic move and
  swap animations exist.
- Split View and Stage Manager verification.
- Screenshot harness and Xcode Cloud workflows (M11).

---

## Tests

`cd Packages/KeezlyCore && swift test` — **171 tests in 15 suites, 0 failures**,
94 s, re-run at the commit above.

| Suite | Tests |
|---|---|
| BoardGraph | 9 |
| Card rules | 26 |
| Game flow | 16 |
| Invariants | 6 |
| Serialization | 11 |
| Match record | 7 |
| AI observation boundary | 16 |
| Easy agent | 7 |
| Medium agent | 9 |
| Hard agent | 13 |
| AI strength | 8 |
| Simulation harness | 9 |
| Online match | 17 |
| Two clients | 12 |
| Online hidden information | 5 |

Many are parameterised over seat counts or card ranks, so executed cases exceed
test-function count. The invariant suite alone plays 221 complete matches.

Two gated suites, excluded from the default run on purpose:

| Gate | Command | Why |
|---|---|---|
| Extended simulation | `KEEZLY_EXTENDED_SIM=1 swift test` | Large AI samples and seat-fairness runs take minutes |
| Timing | `KEEZLY_TIMING_TESTS=1 swift test` | Wall-clock bounds measure scheduler queueing under a parallel run (see ISS-005) |

App-level, on the iPad Pro 13" (M5) simulator, iOS 27.0:

| Target | Result |
|---|---|
| `KeezlyTests` | **199 passed in 25 suites, 0 failed** |
| `KeezlyUITests` | **37 passed, 0 failed, 3 skipped** |

The three skips are the keyboard tests, which report honestly that no hardware
keyboard reached the app rather than passing without exercising anything
(ISS-010).

Several of the app suites exist to stop a specific kind of lie:

| Suite | What it refuses to let pass |
|---|---|
| `ActionListTests` | An accessible move list that offers fewer moves than the engine |
| `RulebookTests` | A rule option the engine has that no section explains, and a line that shows its lookup key instead of its text |
| `TutorialTests` | A lesson whose position cannot be reached, or that counts a move it did not ask for |
| `HintTests` | A hint that names a card the player is not holding |
| `ContrastTests` | Text below the contrast floor, measured rather than judged |
| `PlayLayoutTests` | A layout that does not add up on a display Keezly runs on |
| `ReplayTests` | A replay that writes to the record, or disagrees with itself between routes |
| `AchievementTests` | An achievement earned by the wrong seat, or by an abandoned match |
| `AppIconTests` | An icon concept that flattens at 29 points or loses its shape as a mask |

Three checks run without a simulator and can gate a pull request:

| Script | What it checks |
|---|---|
| `scripts/strings-check.sh` | Every key translated in all three languages, no key the code asks for that is missing, placeholders matching the English, and one word per thing per language |
| `scripts/icon-check.sh` | The committed app icon is still what its source renders |
| `scripts/icon-sheet.sh` | Produces the comparison sheet a decision was made from |

---

## Device Verification

Recorded per environment; never merged (§167, §175).

| Environment | Status | Last run | Commit |
|---|---|---|---|
| Simulator — iPhone 17, iOS 27.0 | **PASSED** (34/34) | 2026-09-20 | `e4bae0f` |
| Simulator — iPad Pro 13" (M5), iOS 27.0 | **PASSED** (132 passed, 0 failed, 3 skipped) | 2026-09-21 | `820b7d5` |
| Physical iPhone 17 Pro, iOS 27.0 | **PASSED** (80 passed, 3 skipped) | 2026-09-20 | `9a2d4e3` |
| Physical iPhone — re-run on the polish | **BLOCKED** — device left the wired connection mid-run (ISS-014) | 2026-09-21 | — |
| Physical iPad (A16), iOS 27.0 | **PASSED** (80 passed, 3 skipped) | 2026-09-20 | `9a2d4e3` |
| Physical iPad — re-run on the polish | **BLOCKED** — the test runner will not start (ISS-014) | 2026-09-21 | — |
| Xcode Cloud | **PREPARED, not CONFIGURED, not VERIFIED** | — | — |
| Game Center multi-device | **BLOCKED** — not implemented (M6) | — | — |

Device availability is re-checked with `./scripts/devices.sh` before every
device run, never trusted from this file — it changed mid-session once already.

`devicectl` lists simulators too, and a booted simulator reports as
`connected`; the only reliable discriminator is `hardwareProperties.reality`.

---

## Known Problems

`KNOWN_ISSUES.md` holds the detail. One new entry, accepted with its numbers
rather than papered over:

- **ISS-016** — a seat colour does not reach 3:1 against the board. Amber is
  the weakest at 1.23:1 and nothing in the palette reaches the bar without
  darkening the board, which is settled (DEC-018). What carries a seat's
  identity is the mark on the piece, the narration and the action list, not the
  hue. Guarded against getting worse.

Defects found and closed during M7–M10, each worth keeping in mind because each
one passed a review that was looking at the wrong thing:

- The playing screen drew the far seat panel past the right edge on a portrait
  iPad. The arithmetic had been reviewed twice — in landscape, where it fits.
  It is now `PlayLayout`, with a test across every display size.
- The rulebook shipped its lookup keys to the screen for one build:
  `LocalizedStringKey("rules.\(id).title")` takes the *interpolating*
  initialiser. The test meant to catch it rebuilt the keys itself and so tested
  nothing; it now reads the model's own properties.
- `Keezly.Palette.secondaryText` was `Color.secondary`, which follows the
  system appearance while the wood it sits on does not: **2.88:1** in light
  mode. Now a fixed ink above 4.5:1 everywhere, measured by a test.
- At the largest accessibility text size the segmented pickers stopped growing,
  the seat preview piled up, and the hand was pushed off the bottom of the
  screen. Found by turning the setting on rather than by reading the code.
- `card.number.spoken` consumed two arguments where the call site passes one.
  Found by the String Catalog check, not by reading the string.

---

## Technical Risks

| Risk | Note |
|---|---|
| Tournament preset unverified | It currently equals Classic because no primary rule source has been checked. Open questions listed in `RULE_VARIANTS.md` rather than guessed. |
| `allowExtraLap` interpretation | Implemented as an explicit route choice (DEC-005); needs a play-test before 1.0.0. |
| Match record size | 122 KB per six-player match. Fine individually; `MATCH HISTORY` (M9.2) needs a retention policy or a more compact encoding. |
| Hard search size unproven | Three configurations were indistinguishable at 30 matches each. The smallest ships; settling it needs a few hundred matches per configuration. |
| Default suite runtime | ~90 s and growing. If it passes a couple of minutes, split the AI strength runs out of the default run. |

---

## Manual Actions Required

| # | Action | Status |
|---|---|---|
| MAN-01 | Bundle identifier | **DONE** — `de.gcng.keezly` (DEC-011) |
| MAN-02 | App Store Connect app record for `de.gcng.keezly` | **OPEN — top blocker.** Confirmed empirically: the API lists 14 records and this bundle id is not among them |
| MAN-03 | Apple Developer signing team | **DONE** — in the git-ignored `Config/Local.xcconfig`, device build verified |
| MAN-04 | Authorise GitHub ↔ Xcode Cloud, enable Xcode Cloud | OPEN — depends on MAN-02 |
| MAN-05 | Enable Game Center for the bundle id | OPEN — depends on MAN-02 |
| MAN-06 | Create Game Center leaderboards and achievements | OPEN |
| MAN-07 | Configure TestFlight testers | OPEN |
| MAN-08 | App Store Connect API key | **DONE & VERIFIED** — outside the repo; `fastlane asc_check` authenticates |
| MAN-09 | Pair a physical iPhone | **DONE** — iPhone 17 Pro, Developer Mode on |
| MAN-10 | Pair a physical iPad | **DONE & VERIFIED** — iPad (A16), iOS 27.0, gate green 2026-09-20 |
| MAN-11 | Second Apple Account in Game Center | OPEN |
| MAN-12 | Second physical device for Game Center tests | OPEN |

MAN-02 blocks TestFlight, Game Center configuration and Xcode Cloud. It blocks
none of the work queued next.

---

## Decisions That Must Not Be Re-opened

`DECISIONS.md` has the reasoning. In short: DEC-001 `KeezlyCore` stays
framework-free · DEC-002 memory at the root · DEC-003 all randomness seeded ·
DEC-004 the generator is the only authority on legality · DEC-005 rule variants
as named options · DEC-006 turn-based GameKit · DEC-007 XcodeGen, project
committed · DEC-008 Xcode Cloud archives, fastlane automates locally ·
DEC-009 byte-stable `Codable` · DEC-010 three version numbers, decoding refuses
· DEC-011 `de.gcng.keezly` · DEC-012 Bundler-pinned fastlane · DEC-013 signing
team never committed · DEC-014 agents get an observation, never the state ·
DEC-015 previews widen the boundary deliberately · DEC-016 SwiftLint gates,
SwiftFormat allowlists · DEC-017 our own board curve · DEC-018 Classic Wood ·
DEC-019 Dutch ornament, not Dutch souvenir · DEC-020 keyboard logic pure and
testable · DEC-021 a two-seat table gets its own presentation · DEC-022 privacy
by construction, not by cover · DEC-023 a save is a seed plus its actions ·
DEC-024 Game Center is transport, not a second game · DEC-025 friendly online
play, no anti-cheat claim.

---

## Next Steps (concrete)

M0 to M10 are done. What is left is release work.

1. **M11 — CI / QA / Hardening.** The Xcode Cloud workflows, the screenshot
   harness, and ISS-012 fixed at the cause in the capture pipeline rather than
   by cropping. The three simulator-free scripts above are ready to be gates.
2. **Device gates.** Both physical devices are paired and both passed before
   M7; ISS-014 has blocked re-running them since. They need re-running against
   this work before anything is called verified on hardware.
3. **M12 — Release candidate.** Blocked on MAN-02, which also blocks
   TestFlight, Game Center configuration and Xcode Cloud.

Two things will stay honestly incomplete until somebody unblocks them:

| | Why |
|---|---|
| Sound | **ASSET PRESENT, NOT LISTENING-VERIFIED.** Synthesised from source in this repository (§77) |
| Game Center, end to end | **BLOCKED** on MAN-02. Implemented and tested against a mock two-client harness; never run against a real match |
