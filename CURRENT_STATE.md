# Keezly — Current State

**This file is the operative memory of the project (§128).** It describes what
is true right now, not what is planned. Plans live in `ROADMAP.md`.

---

## Last Verified Commit

```
5d9fbf4  docs: correct the cancellation diagnosis and separate average from worst case
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
| **M4 — Gameplay UI (iPad / iPhone)** | **NEXT — not started** |

Everything up to and including M3 lives in `KeezlyCore`, which is testable with
`swift test` alone. M4 is the first milestone that is mostly app-layer work.

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

- **All gameplay UI** — the app builds and launches but cannot play a game.
- Pass & play, autosave, statistics, match history, replay playback UI.
- Game Center of any kind.
- Tutorial, rulebook, hints, accessibility work.
- Localisation, audio, haptics, app icon, artwork.
- Screenshot harness; Xcode Cloud workflows.

---

## Tests

`cd Packages/KeezlyCore && swift test` — **136 tests, 0 failures**, ~90 s.

| Suite | Tests |
|---|---|
| BoardGraph | 9 |
| Card rules | 26 |
| Game flow | 16 |
| Invariants | 6 |
| Serialization | 11 |
| Match record | 7 |
| AI observation boundary | 15 |
| Easy agent | 7 |
| Medium agent | 9 |
| Hard agent | 12 |
| AI strength | 8 |
| Simulation harness | 10 |

Many are parameterised over seat counts or card ranks, so executed cases exceed
test-function count. The invariant suite alone plays 221 complete matches.

Two gated suites, excluded from the default run on purpose:

| Gate | Command | Why |
|---|---|---|
| Extended simulation | `KEEZLY_EXTENDED_SIM=1 swift test` | Large AI samples and seat-fairness runs take minutes |
| Timing | `KEEZLY_TIMING_TESTS=1 swift test` | Wall-clock bounds measure scheduler queueing under a parallel run (see ISS-005) |

| App-level | Result |
|---|---|
| iPhone 17 simulator, iOS 27.0 | 7/7 |
| iPad Pro 13" (M5) simulator, iOS 27.0 | 7/7 |
| Physical iPhone 17 Pro, iOS 27.0 | 11/11 |

---

## Device Verification

Recorded per environment; never merged (§167, §175).

| Environment | Status | Last run | Commit |
|---|---|---|---|
| Simulator — iPhone 17, iOS 27.0 | **PASSED** (7/7) | 2026-09-20 | `705497c` |
| Simulator — iPad Pro 13" (M5), iOS 27.0 | **PASSED** (7/7) | 2026-09-20 | `705497c` |
| Physical iPhone 17 Pro, iOS 27.0 | **PASSED** (11/11) | 2026-09-20 | `705497c` |
| Physical iPad | **BLOCKED** — none paired (MAN-10) | — | — |
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
| MAN-10 | Pair a physical iPad | OPEN — blocks the iPad gate |
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

**M4 — Gameplay UI.** The first milestone whose work is mostly outside
`KeezlyCore`. Order matters here, because each step is verifiable on its own:

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
