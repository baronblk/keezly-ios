# Keezly — Roadmap

This roadmap describes the **actual** state of the project, not a wish list
(§130). A milestone is `DONE` only when its acceptance criteria have been met
and verified. Status values: `NOT STARTED`, `IN PROGRESS`, `BLOCKED`, `DONE`.

Operative detail — what works today, what is next — lives in `CURRENT_STATE.md`.

| Milestone | Title | Status |
|---|---|---|
| M0 | Repository & Foundation | **DONE** |
| M1 | GameCore / Rules | **DONE** |
| M2 | Complete Move Engine | **DONE** |
| M3 | AI (Easy / Medium / Hard) | **DONE** |
| M4 | Gameplay UI — iPad / iPhone | IN PROGRESS |
| M5 | Local Multiplayer / Pass & Play | NOT STARTED |
| M6 | Game Center Multiplayer | NOT STARTED |
| M7 | Tutorial / Rulebook / Accessibility | DONE |
| M8 | Brand / App Icon / Audio / Haptics | NOT STARTED |
| M9 | Statistics / Replay / Game Center Meta | NOT STARTED |
| M10 | Localisation | NOT STARTED |
| M11 | CI / QA / Hardening | NOT STARTED |
| M12 | Release Candidate 1.0.0 | NOT STARTED |

---

## M0 — Repository & Foundation — DONE

**Goal.** A repository that any developer or CI system can clone, build and
test reproducibly, with the project memory in place from day one.

| Task | Status |
|---|---|
| M0.1 Git repository, structure, secret-safe `.gitignore` | DONE |
| M0.2 Xcode project via XcodeGen (`project.yml`), shared scheme, committed `.xcodeproj` | DONE |
| M0.3 Bundler + fastlane skeleton with a `tests` lane | DONE |
| M0.4 `ci_scripts/` (`ci_post_clone.sh`, `ci_pre_xcodebuild.sh`, `ci_post_xcodebuild.sh`) | DONE |
| M0.5 SwiftLint / SwiftFormat configuration | DONE — see DEC-016 |
| M0.6 Project memory documents | DONE |
| M0.7 Xcode Cloud compatibility check (no absolute paths, no local-only config) | DONE — see `docs/XCODE_CLOUD_SETUP_CHECKLIST.md` |

**Dependencies.** M0.4 and M0.7 depend on M0.2 (done). Device builds depend on
MAN-03, the signing team decision.

**Acceptance criteria.**
- `xcodegen generate` produces a project that builds for iPhone and iPad.
- The `Keezly` scheme is shared and contains the test targets.
- `bundle exec fastlane tests` runs the rules suite and reports green.
- No absolute developer-machine paths anywhere in the project.
- `PROJECT_HANDOUT.md`, `CURRENT_STATE.md`, `ROADMAP.md`, `DECISIONS.md` exist
  and describe the real state.

**Test requirements.** `swift test` green; a clean-clone build succeeds.

---

## M1 — GameCore / Rules — DONE

**Goal.** A deterministic, UI-independent rules engine for 2–6 seats.

| Task | Status |
|---|---|
| M1.1 Deterministic seeded RNG with serialisable state | DONE |
| M1.2 Parametric `BoardGraph` for 2–6 seats | DONE |
| M1.3 Card, deck and hand model with no suit-dependent rules | DONE |
| M1.4 `RuleSet` with Classic / Tournament / House Rules presets | DONE |
| M1.5 Immutable `GameState`, `GameConfiguration`, team layout | DONE |
| M1.6 Event model (`GameEvent`, `GameTransition`) | DONE |
| M1.7 Board and rule test suites | DONE |

**Acceptance criteria — all met.**
- Board generated, never hard-coded, for every seat count 2–6.
- Every seat's journey is provably the same length; start squares evenly spaced;
  each seat's home entry sits exactly one square before its own start.
- Deck size is 13 × seat count and a 5/4/4 cycle exhausts it exactly.
- No engine code branches on card suit.
- Same seed ⇒ identical deal, verified by test.

**Verification.** `swift test` — 57 tests, 0 failures, at commit `64931ef`.

---

## M2 — Complete Move Engine — DONE

**Goal.** Every card, every blocking rule, every table size, with the forced-move
rule and complete seven-split enumeration.

| Task | Status |
|---|---|
| M2.1 Enter from waiting (Ace / King) incl. capturing a squatter | DONE |
| M2.2 Plain forward moves (2,3,5,6,8,9,10, Queen=12, King=13 option) | DONE |
| M2.3 Four backward, never into or out of home, blockade-aware | DONE |
| M2.4 Seven move generator — all one- and two-leg splits | DONE |
| M2.5 Jack swap incl. partner targets and protection rules | DONE |
| M2.6 Home entry — exact count, no jumping, strict ordering option | DONE |
| M2.7 Team continuation — playing a finished partner's pawns | DONE |
| M2.8 No-legal-move handling — forced move and hand fold | DONE |
| M2.9 Versioned state serialisation (`schemaVersion`, `engineVersion`) | DONE |
| M2.10 Move log / replay record separate from `GameState` | DONE |

**Acceptance criteria.**
- Generator and reducer agree on legality for every generated move. — met
- A seven can finish the player's own pawns and spend the remainder on a
  partner's pawns. — met
- Randomised self-play finishes without corrupting state for every seat count
  and every rule variant. — met (221 matches)
- A saved match survives an engine refactor, or fails loudly with a typed
  version error. — met
- A six-player state fits comfortably within Game Center's payload limit. —
  met (4527 bytes measured)

**Test requirements.** One test per card rank (done); property/fuzz self-play
(done); serialisation round trip, byte stability, version refusal, checksum
integrity and size limits (done); replay fidelity — a replayed match reproduces
every state *and every event* (done).

**Verification.** `swift test` — 133 tests, 0 failures, at commit `f2da1ce`.

---

## M3 — AI — DONE

| Task | Status |
|---|---|
| M3.1 `PlayerObservation` — the AI's information boundary | DONE |
| M3.2 Easy AI — legal moves, weighted random, avoids obvious disasters | DONE |
| M3.3 Medium AI — heuristic state evaluation | DONE |
| M3.4 Hard AI — information-set sampling + time-boxed rollouts | DONE |
| M3.5 Headless simulation harness | DONE |
| M3.6 Cancellation and time budgets under Swift Concurrency | DONE |

**Acceptance criteria.**
- An agent is structurally unable to read another seat's hand or the deck
  order. — met (DEC-014/DEC-015, differential + mutation tested)
- Hard beats Medium beats Easy over a decent sample. — met: Medium 97.5% vs
  Easy, Hard 97.5% vs Easy, Hard 67.5% vs Medium (80/80/40 team matches)
- A move is chosen well under one second. — met on a development Mac
  (~0.3 ms Medium, ~16 ms Hard per action); **not yet measured on device**
- The main thread never blocks. — met: a cancelled search returns a legal move
  promptly, and an exhausted budget falls back to the static evaluation, both
  asserted in `HardAgentTests`

**Verification.** `swift test` — 126 tests, 0 failures, at commit `ad6c2e2`.
Measured results and their sample sizes are in `AI.md`.

**M3.1 is done and verified.** Agents receive a `PlayerObservation` and never a
`GameState`. The guarantee is tested differentially — two states differing only
in opponents' hands, deck order or generator state must produce identical
observations — and the tests were confirmed to bite by deliberately injecting a
leak and watching them fail. See `AI.md`.

---

## M4 — Gameplay UI (iPad / iPhone) — DONE

| Task | Status |
|---|---|
| M4.0 Main menu and table configuration | DONE — 2–6 seats, one to six people sharing the device, partners or everyone alone, three opponent strengths, and the table shown as it will be dealt |
| M5.1 Pass & play with a privacy handover (DEC-022) | DONE — the hand is built only for the seat holding the device; a UI test counts the cards on screen during a handover and requires zero |
| M5.2 Autosave and resume (DEC-023) | DONE — seed plus accepted actions, written atomically before the animation starts; restore revalidates every action and refuses rather than repairs. Verified across 2–6 seats, partners and free-for-all, completed and abandoned matches, corruption, a newer schema and an unknown opponent, and by terminating and relaunching the app |
| M4.1 Design system — spacing, type, materials, motion, player identity | DONE |
| M4.2 Board rendering from `BoardGraph` topology | DONE |
| M4.3 Adaptive layout — iPad landscape/portrait, Split View, Stage Manager | DONE — the layout is chosen by the space actually available rather than by size class, and `PlayLayoutTests` adds the three columns up on every display Keezly runs on. Four clipping defects fixed, the last of them the far seat panel on a portrait iPad. A two-player table has its own presentation (DEC-021). Split View and Stage Manager still untested |
| M4.4 iPhone layout — portrait and both landscape orientations | DONE — phones get their own compact and short-landscape layouts; reviewed on the smallest, standard and largest iPhones, in both orientations, at 4 and 6 seats |
| M4.5 Card interaction flow, Jack targeting, seven sequence builder | DONE — the planner derives every option from complete legal moves, so a Seven cannot strand the player |
| M4.6 Event-driven animation pipeline with input locking | DONE — `BoardPresenter` plays events one at a time, reorders a capture behind the move that caused it, honours Reduce Motion, and settles on the true position on any interruption |
| M4.7 Pointer, trackpad and full keyboard access on iPad | **IMPLEMENTED** — pointer effects, a shared focus model, arrow/return/escape control and a visible focus ring. Logic unit-tested; focus behaviour simulator-verified; key *delivery* NOT VERIFIED, no keyboard available (see CURRENT_STATE) |

| M4.8 Centre of the board — draw pile, discard, turn and deal status | DONE |
| M4.9 Classic Wood material, round milled holes, pawn silhouettes, real playing cards (DEC-018) | DONE |
| M4.13 Polish pass — hole depth, player colours, board edge, quieter middle, panels in board material, card finish (DEC-021) | DONE — reviewed on iPad at 2, 4 and 6 seats and on iPhone |
| M4.10 Seat status panels using the spare landscape width (§35) | DONE |
| M4.11 Deterministic screenshot mode and design-review captures (§87) | DONE — plus fixtures that fast-forward to a playable Jack, a Seven mid-split, a free-for-all table and a mid-match phone |
| M4.12 Dutch ornament on the Classic Wood board (DEC-019) | DONE — engraved border, centre medallion, home-lane chevrons, one orange detail |

**Acceptance criteria.** The iPad layout is designed for the large display, not
scaled up; a pawn can never appear to move on its own or a move be applied
twice; animations visualise events and never drive state.

**Board form.** A squared ring with straight runs and soft corners, generated
from our own curve — the traditional shape, not anyone's artwork (DEC-017).
Verified visually on an iPad simulator in light and dark appearance.

---

## M5 — Local Multiplayer / Pass & Play — DONE

| Task | Status |
|---|---|
| M5.1 Mixed human/AI seat configuration for 2–6 players | NOT STARTED |
| M5.2 Privacy hand-off screen between human players | NOT STARTED |
| M5.3 Autosave after every completed action, off the main thread | NOT STARTED |
| M5.4 Resume-after-crash flow | NOT STARTED |

---

## M6 — Game Center Multiplayer — IMPLEMENTED, NOT VERIFIED

| Task | Status |
|---|---|
| M6.1 Authentication and graceful degradation without Game Center | NOT STARTED |
| M6.2 Protocol-based service abstraction over GameKit (for test doubles) | NOT STARTED |
| M6.3 Turn-based match lifecycle: create, invite, automatch, resume, rematch | NOT STARTED |
| M6.4 `OnlineMatchEnvelope` with revision guards and size checking | NOT STARTED |
| M6.5 Idempotent turn submission (duplicate/stale callback handling) | **MOCK VERIFIED** — moveID, expectedRevision and resultingRevision give five distinct outcomes; duplicates are recognised by identity before revision |
| M6.9 Online hidden-information threat model (DEC-025) | DONE — demonstrated by test that a participant can reconstruct every hand and the deck; limitation accepted and documented, not claimed away |
| M6.6 Resignation policy incl. team forfeit | NOT STARTED |
| M6.7 Error-case matrix (offline, signed out, match gone, backgrounded upload) | NOT STARTED |

**Blocked externally by** MAN-04, MAN-05 for real verification; implementation
and mocked tests can proceed without them (§142).

---

## M7 — Tutorial / Rulebook / Accessibility — DONE

| Task | Status |
|---|---|
| M7.1 Onboarding (few screens, straight to play) | DONE — as one line and one button rather than screens. Until a first match or lesson has been started, learning the game is the loudest thing on the menu; afterwards it goes quiet and stays quiet. A board game somebody has to swipe through three screens to reach is one they open once (§36) |
| M7.2 Interactive tutorial driven by the real engine | DONE — ten lessons, each an ordinary match on the real engine. A lesson reads the board before and after a move rather than the tap, so it cannot credit a move that was not made; every lesson's seed is played through in the tests |
| M7.3 In-app rulebook with the active rule set highlighted | DONE — ~26 sections in Keezly's own words, both readings shown where tables disagree, the table's own rules marked. `RuleFacet` is checked against `RuleSet` by reflection |
| M7.4 In-game card help | DONE — a long press on a card opens the rulebook's own words about it, playable or not, because "why can I not play this one?" is the same question |
| M7.5 Hint system using AI evaluation, disabled in competitive online play | DONE — the hint is a computer opponent handed the player's own `PlayerObservation`, so it cannot see a card the player cannot see. `MatchSession.allowsHints` is where a competitive online match would turn it off (DEC-025) |
| M7.6 VoiceOver, Dynamic Type, Reduce Motion, contrast, keyboard access | DONE — narration from a `PlayerObservation`, announced turns, Reduce Motion honoured, the keyboard model complete. Reviewed at the largest accessibility text size on a real simulator, which turned up three defects (segmented pickers that cap their growth, a seat preview that piles up, a hand pushed off the bottom of the screen), all fixed. Contrast is now measured by `ContrastTests` rather than judged: the secondary ink went from 2.88:1 to over 4.5:1, and the one shortfall that cannot be fixed without darkening the board is recorded as ISS-016 |
| M7.7 Alternative list-of-legal-actions input | DONE — the same `MoveGenerator` as the board, with a test asserting the two move sets are *equal* rather than overlapping |

---

## M8 — Brand / App Icon / Audio / Haptics — NOT STARTED

| Task | Status |
|---|---|
| M8.1 Three icon concepts, comparison sheet, decision | NOT STARTED |
| M8.2 Final 1024px master, dark/tinted variants, editable sources | NOT STARTED |
| M8.3 Icon preview page at 1024/180/120/60/40/29 px | NOT STARTED |
| M8.4 Original board, pawn and card artwork | NOT STARTED |
| M8.5 Original sound set, fully disableable | NOT STARTED |
| M8.6 Haptics, fully disableable | NOT STARTED |

---

## M9 — Statistics / Replay / Game Center Meta — NOT STARTED

| Task | Status |
|---|---|
| M9.1 Local statistics | NOT STARTED |
| M9.2 Match history with sensible bounds | NOT STARTED |
| M9.3 Replay (play/pause/step/speed) built on the event stream | PARTIAL — the engine side is done (`MatchRecord`); the playback UI waits on M4 |
| M9.4 Achievements (`docs/GAME_CENTER_ACHIEVEMENTS.md`) | NOT STARTED |
| M9.5 Leaderboards (`docs/GAME_CENTER_LEADERBOARDS.md`) | NOT STARTED |

**Depends on** M2.10 (move log) for replay.

---

## M10 — Localisation — NOT STARTED

| Task | Status |
|---|---|
| M10.1 String Catalog, no hardcoded visible strings | NOT STARTED |
| M10.2 Dutch (nl-NL) | NOT STARTED |
| M10.3 German (de-DE) | NOT STARTED |
| M10.4 English (en) | NOT STARTED |
| M10.5 Terminology review per language | NOT STARTED |

---

## M11 — CI / QA / Hardening — NOT STARTED

| Task | Status |
|---|---|
| M11.1 Xcode Cloud "Keezly CI" workflow (PR: build + test) | NOT STARTED |
| M11.2 Xcode Cloud "Keezly Main" workflow (build + test + analyze) | NOT STARTED |
| M11.3 Xcode Cloud "Keezly Release" workflow (+ archive + TestFlight) | NOT STARTED |
| M11.4 Screenshot harness, fixtures and deterministic screenshot mode | NOT STARTED |
| M11.5 `fastlane screenshots` / `screenshots_verify` | NOT STARTED |
| M11.6 `fastlane qa` and `fastlane release_check` | NOT STARTED |
| M11.7 Large-scale AI simulation in CI | NOT STARTED |
| M11.8 Simulator/orientation/localisation UI test matrix | NOT STARTED |
| M11.9 Role-based physical device discovery (`scripts/devices.sh`) | DONE |
| M11.10 fastlane device lanes (`device_smoke`, `device_iphone`, `device_ipad`, `device_gate`) | DONE |
| M11.11 Physical iPhone quality gate | PARTIAL — 58/58 on an iPhone 17 Pro (iOS 27.0); haptics, audio and Game Center items wait on those features |
| M11.12 Physical iPad quality gate | BLOCKED — no iPad paired (MAN-10) |
| M11.13 Game Center multi-device verification | BLOCKED — MAN-10/11 + M6 |
| M11.14 Real-hardware performance and long-run test | BLOCKED — needs gameplay (M4) |

**Device testing is part of the strategy, not an optional manual extra** (§156,
§180). `scripts/devices.sh` addresses devices by role and never persists a name
or UDID. Full plan: `docs/DEVICE_TESTING.md` and
`docs/GAME_CENTER_DEVICE_TESTS.md`.

**Note.** §119 asks for the first real Xcode Cloud run no later than after M1.
That is currently **not possible**: there is no Xcode project yet (M0.2) and
Xcode Cloud has not been authorised (MAN-04). This is tracked, not hidden.

---

## M12 — Release Candidate 1.0.0 — NOT STARTED

| Task | Status |
|---|---|
| M12.1 `RELEASE_CHECKLIST.md` fully ticked with evidence | NOT STARTED |
| M12.2 App Store metadata in nl-NL, de-DE, en | NOT STARTED |
| M12.3 Screenshot sets (iPad 13" landscape first) | NOT STARTED |
| M12.4 Privacy manifest and App Store privacy answers | NOT STARTED |
| M12.5 TestFlight build verified | NOT STARTED |

---

## Changes to this roadmap

Any task added or removed during implementation is recorded here immediately
(§132). If a plan is dropped because it turned out to be technically wrong, the
reason goes into `DECISIONS.md`.
