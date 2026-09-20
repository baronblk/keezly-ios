# Keezly — Roadmap

This roadmap describes the **actual** state of the project, not a wish list
(§130). A milestone is `DONE` only when its acceptance criteria have been met
and verified. Status values: `NOT STARTED`, `IN PROGRESS`, `BLOCKED`, `DONE`.

Operative detail — what works today, what is next — lives in `CURRENT_STATE.md`.

| Milestone | Title | Status |
|---|---|---|
| M0 | Repository & Foundation | IN PROGRESS |
| M1 | GameCore / Rules | **DONE** |
| M2 | Complete Move Engine | IN PROGRESS |
| M3 | AI (Easy / Medium / Hard) | IN PROGRESS |
| M4 | Gameplay UI — iPad / iPhone | NOT STARTED |
| M5 | Local Multiplayer / Pass & Play | NOT STARTED |
| M6 | Game Center Multiplayer | NOT STARTED |
| M7 | Tutorial / Rulebook / Accessibility | NOT STARTED |
| M8 | Brand / App Icon / Audio / Haptics | NOT STARTED |
| M9 | Statistics / Replay / Game Center Meta | NOT STARTED |
| M10 | Localisation | NOT STARTED |
| M11 | CI / QA / Hardening | NOT STARTED |
| M12 | Release Candidate 1.0.0 | NOT STARTED |

---

## M0 — Repository & Foundation — IN PROGRESS

**Goal.** A repository that any developer or CI system can clone, build and
test reproducibly, with the project memory in place from day one.

| Task | Status |
|---|---|
| M0.1 Git repository, structure, secret-safe `.gitignore` | DONE |
| M0.2 Xcode project via XcodeGen (`project.yml`), shared scheme, committed `.xcodeproj` | DONE |
| M0.3 Bundler + fastlane skeleton with a `tests` lane | DONE |
| M0.4 `ci_scripts/` (`ci_post_clone.sh`, `ci_pre_xcodebuild.sh`, `ci_post_xcodebuild.sh`) | NOT STARTED |
| M0.5 SwiftLint / SwiftFormat configuration | NOT STARTED |
| M0.6 Project memory documents | DONE |
| M0.7 Xcode Cloud compatibility check (no absolute paths, no local-only config) | NOT STARTED |

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

## M2 — Complete Move Engine — IN PROGRESS

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
| M2.10 Move log / replay record separate from `GameState` | NOT STARTED |

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
integrity and size limits (done). Remaining: a replay move log (M2.10).

---

## M3 — AI — IN PROGRESS

| Task | Status |
|---|---|
| M3.1 `PlayerObservation` — the AI's information boundary | DONE |
| M3.2 Easy AI — legal moves, weighted random, avoids obvious disasters | DONE |
| M3.3 Medium AI — heuristic state evaluation | DONE |
| M3.4 Hard AI — information-set sampling + time-boxed rollouts | IN PROGRESS — implemented and measured; search size being tuned |
| M3.5 Headless simulation harness | DONE |
| M3.6 Cancellation and time budgets under Swift Concurrency | IN PROGRESS — `AIBudget` and `Task.isCancelled` are wired into Hard; a cancellation test is outstanding |

**Acceptance criteria.**
- An agent is structurally unable to read another seat's hand or the deck
  order. — met (DEC-014/DEC-015, differential + mutation tested)
- Hard beats Medium beats Easy over a decent sample. — met: Medium 97.5% vs
  Easy, Hard 97.5% vs Easy, Hard 67.5% vs Medium (80/80/40 team matches)
- A move is chosen well under one second. — met on a development Mac
  (~0.3 ms Medium, ~16 ms Hard per action); **not yet measured on device**
- The main thread never blocks. — by construction; not yet demonstrated by a
  cancellation test (M3.6)

**M3.1 is done and verified.** Agents receive a `PlayerObservation` and never a
`GameState`. The guarantee is tested differentially — two states differing only
in opponents' hands, deck order or generator state must produce identical
observations — and the tests were confirmed to bite by deliberately injecting a
leak and watching them fail. See `AI.md`.

---

## M4 — Gameplay UI (iPad / iPhone) — NOT STARTED

| Task | Status |
|---|---|
| M4.1 Design system — spacing, type, materials, motion, player identity | NOT STARTED |
| M4.2 Board rendering from `BoardGraph` topology | NOT STARTED |
| M4.3 Adaptive layout — iPad landscape/portrait, Split View, Stage Manager | NOT STARTED |
| M4.4 iPhone layout — portrait and both landscape orientations | NOT STARTED |
| M4.5 Card interaction flow, Jack targeting, seven sequence builder | NOT STARTED |
| M4.6 Event-driven animation pipeline with input locking | NOT STARTED |
| M4.7 Pointer, trackpad and full keyboard access on iPad | NOT STARTED |

**Acceptance criteria.** The iPad layout is designed for the large display, not
scaled up; a pawn can never appear to move on its own or a move be applied
twice; animations visualise events and never drive state.

---

## M5 — Local Multiplayer / Pass & Play — NOT STARTED

| Task | Status |
|---|---|
| M5.1 Mixed human/AI seat configuration for 2–6 players | NOT STARTED |
| M5.2 Privacy hand-off screen between human players | NOT STARTED |
| M5.3 Autosave after every completed action, off the main thread | NOT STARTED |
| M5.4 Resume-after-crash flow | NOT STARTED |

---

## M6 — Game Center Multiplayer — NOT STARTED

| Task | Status |
|---|---|
| M6.1 Authentication and graceful degradation without Game Center | NOT STARTED |
| M6.2 Protocol-based service abstraction over GameKit (for test doubles) | NOT STARTED |
| M6.3 Turn-based match lifecycle: create, invite, automatch, resume, rematch | NOT STARTED |
| M6.4 `OnlineMatchEnvelope` with revision guards and size checking | NOT STARTED |
| M6.5 Idempotent turn submission (duplicate/stale callback handling) | NOT STARTED |
| M6.6 Resignation policy incl. team forfeit | NOT STARTED |
| M6.7 Error-case matrix (offline, signed out, match gone, backgrounded upload) | NOT STARTED |

**Blocked externally by** MAN-04, MAN-05 for real verification; implementation
and mocked tests can proceed without them (§142).

---

## M7 — Tutorial / Rulebook / Accessibility — NOT STARTED

| Task | Status |
|---|---|
| M7.1 Onboarding (few screens, straight to play) | NOT STARTED |
| M7.2 Interactive tutorial driven by the real engine | NOT STARTED |
| M7.3 In-app rulebook with the active rule set highlighted | NOT STARTED |
| M7.4 In-game card help | NOT STARTED |
| M7.5 Hint system using AI evaluation, disabled in competitive online play | NOT STARTED |
| M7.6 VoiceOver, Dynamic Type, Reduce Motion, contrast, keyboard access | NOT STARTED |
| M7.7 Alternative list-of-legal-actions input | NOT STARTED |

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
| M9.3 Replay (play/pause/step/speed) built on the event stream | NOT STARTED |
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
| M11.11 Physical iPhone quality gate | PARTIAL — build, install, launch, rotation verified on an iPhone 17 Pro; gameplay items wait on M4 |
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
