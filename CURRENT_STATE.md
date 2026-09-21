# Keezly — Current State

**This file is the operative memory of the project (§128).** It describes what
is true right now, not what is planned. Plans live in `ROADMAP.md`.

---

## Last Verified Commit

```
bfbac24  feat(pass-and-play): add the privacy handover flow
```

Verified on **2026-09-20** with Xcode 27.0 / Swift 6.4 on macOS 26 (arm64).

---

## Current Milestone

| Milestone | Status |
|---|---|
| M0 — Repository & Foundation | **DONE** |
| M1 — GameCore / Rules | **DONE** |
| M2 — Complete Move Engine | **DONE** |
| M3 — AI | **DONE** |
| **M4 — Gameplay UI (iPad / iPhone)** | **IN PROGRESS** |

Everything up to and including M3 lives in `KeezlyCore`, which is testable with
`swift test` alone. M4 is the first milestone that is mostly app-layer work.

**The game is playable.** One human against three computer opponents, board and
hand on screen, moves applied through the engine, verified end to end by UI
tests rather than by assertion.

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

**The two-player board is solved (ISS-013, DEC-021).** The quiet middle is not
a constant: measured in square pitches it is 0.28 at two seats, 2.42 at three
and 4.56 at four. At two seats the home lanes very nearly meet and there is no
middle at all. Shrinking the cards to fit was tried and made them unreadable,
which is worse than crowding — so a two-player table shows the table's own
cards **beside** the board, in a wooden tray opposite the other player. The
rules and `BoardGraph` are identical for every table size; only the
presentation adapts, and the decision is written as a rule about available
space rather than a special case for two.

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

---

## In Progress

Nothing is mid-edit. The working tree is clean at the commit above.

---

## Not Implemented Yet


- Autosave, resume, statistics, match history, replay playback UI.
- Bespoke dealing, Seven-leg and Jack-swap choreography (the generic move and
  swap animations exist).
- Split View and Stage Manager verification.
- Game Center of any kind.
- Tutorial, rulebook, hints, accessibility work.
- Localisation, audio, haptics, app icon, artwork.
- Screenshot harness; Xcode Cloud workflows.

---

## Tests

`cd Packages/KeezlyCore && swift test` — **137 tests in 12 suites, 0 failures**,
93.7 s, re-run at the commit above.

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

Many are parameterised over seat counts or card ranks, so executed cases exceed
test-function count. The invariant suite alone plays 221 complete matches.

Two gated suites, excluded from the default run on purpose:

| Gate | Command | Why |
|---|---|---|
| Extended simulation | `KEEZLY_EXTENDED_SIM=1 swift test` | Large AI samples and seat-fairness runs take minutes |
| Timing | `KEEZLY_TIMING_TESTS=1 swift test` | Wall-clock bounds measure scheduler queueing under a parallel run (see ISS-005) |

| App-level | Result |
|---|---|
| iPad Pro 13" (M5) simulator, iOS 27.0 | **80 passed, 0 failed, 3 skipped** |
| Physical iPhone 17 Pro, iOS 27.0 | **80 passed, 0 failed, 3 skipped** |
| Physical iPad (A16), iOS 27.0 | **80 passed, 0 failed, 3 skipped** |

The three skips are the keyboard tests, which report honestly that no hardware
keyboard reached the app rather than passing without exercising anything
(ISS-010).

`fastlane` reports 117 for the same run: it counts parameterised cases, the
result bundle counts test functions. Both numbers are true; they answer
different questions.

---

## Device Verification

Recorded per environment; never merged (§167, §175).

| Environment | Status | Last run | Commit |
|---|---|---|---|
| Simulator — iPhone 17, iOS 27.0 | **PASSED** (34/34) | 2026-09-20 | `e4bae0f` |
| Simulator — iPad Pro 13" (M5), iOS 27.0 | **PASSED** (108 passed, 0 failed, 4 skipped) | 2026-09-21 | `bfbac24` |
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

None open. `KNOWN_ISSUES.md` holds five closed entries, including ISS-005,
which records a **misdiagnosis** worth remembering: a green performance test on
a position the code short-circuits out of proves nothing.

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
SwiftFormat allowlists.

---

## Next Steps (concrete)

**M4 continues.** The iPhone pass, the animation pipeline, the screenshot
fixtures, the Dutch ornament pass and **both** hardware gates are done. What is
left, in order:

1. **Main menu and table configuration**, which is what lets a player choose
   2–6 seats, teams and opponents rather than getting the built-in four.
1. **M5 — autosave and resume**, so a match survives the app being closed.
   Pass & play itself is done.

Blocked and not startable: anything behind the App Store Connect record
(MAN-02), and Game Center multi-device (MAN-11/12).

Superseded plan, kept for context:

1. **M4.1 — design system.** Spacing, typography, materials, motion, and
   player identity. Player identity must be colour **plus** a symbol or shape:
   colour alone fails colour-blind players (§42).
2. **M4.2 — board geometry and rendering.** A `BoardLayout` in the app layer
   that maps `BoardPosition` to coordinates. `KeezlyCore` must stay free of
   geometry (DEC-001), so this is a new app-layer type, parametric over
   2–6 seats like the board itself. Verify by screenshotting every seat count
   on an iPad simulator.
3. **M4.6 before M4.5** — the event-driven animation pipeline and input
   locking, because the interaction flow is built on top of it and retrofitting
   the lock is how double-applied moves happen (§63).
4. **M4.5 — card interaction**, including the Jack target picker and the Seven
   sequence builder. The engine already generates only complete, playable
   Seven sequences, so the builder can offer exactly the legal continuations
   and never strand a player mid-split (§38).
5. **M4.3 / M4.4 — adaptive layouts.** iPad landscape first: it is the primary
   product surface, not a scaled-up phone (§4).
6. **M4.7 — pointer, trackpad and keyboard** on iPad.

A `MatchSession` (`@Observable`) is needed early: it owns the `GameState`,
drives AI turns off the main actor, records to `MatchRecord`, and publishes the
event stream the views animate.
