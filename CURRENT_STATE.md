# Keezly — Current State

**This file is the operative memory of the project (§128).** It describes what
is true right now, not what is planned. Plans live in `ROADMAP.md`.

---

## Last Verified Commit

```
4eca268  feat(fastlane): wire app store connect api key from outside the repo
```

Everything below was verified against that commit on **2026-09-20** with
Xcode 27.0 / Swift 6.4 on macOS 26 (arm64).

---

## Current Milestone

**M0 — Repository & Foundation**: IN PROGRESS (M0.2 and M0.3 done; ci_scripts and lint config outstanding)
**M1 — GameCore / Rules**: DONE
**M2 — Complete Move Engine**: IN PROGRESS (only M2.10, the replay move log, is left)

M1 was completed ahead of the remaining M0 tooling work, because the rules
engine is testable with `swift test` alone and does not need the Xcode project.

---

## Completed

### Repository and app project (M0, partial)
- Git repository initialised, `main` tracking `origin/main`.
- Secret-safe `.gitignore` (keys, profiles, `.env`, certificates, local signing
  config, local device mapping).
- **Xcode project** generated from `project.yml` via XcodeGen and committed.
  Bundle ids `de.gcng.keezly` / `.tests` / `.uitests`, iOS 17.0 deployment
  target, `MARKETING_VERSION 1.0.0`, iPhone **and** iPad, Stage Manager
  compatible, shared `Keezly` scheme covering app, unit and UI tests.
- **App shell**: `KeezlyApp` + `RootView`. Deliberately inert scaffolding — no
  buttons that do nothing. M4.1 replaces it with the real menu and board.
- **Signing**: `DEVELOPMENT_TEAM` lives only in the git-ignored
  `Config/Local.xcconfig`; `Config/Local.xcconfig.example` documents it.
- **fastlane** via Bundler (Ruby 4.0.5 pinned in `.tool-versions`, fastlane
  2.240.1 pinned in `Gemfile.lock`). Lanes: `tests`, `ui_tests`, `device_smoke`,
  `device_iphone`, `device_ipad`, `device_gate`, `qa`, `release_check`.

### KeezlyCore (M1, M2 partial) — IMPLEMENTED + TESTED
- **Deterministic randomness**: `SeededGenerator` (SplitMix64), serialisable
  single-`UInt64` state, own Fisher–Yates shuffle so deal order does not depend
  on stdlib internals.
- **Parametric board**: `BoardGraph` for 2–6 seats, 16 track squares per seat
  (4 seats → the classic 64+16+16 = 96 positions). Seat-relative *progress*
  coordinate; forward paths, backward paths, home lane.
- **Cards**: 13 ranks × one rank-set per seat (2 seats → 26 cards, 6 → 78).
  Suits exist for display only; no rule reads them.
- **Rules**: `RuleSet` with presets Classic / Tournament / House Rules, and six
  named variant options (see `RULE_VARIANTS.md`).
- **State**: immutable `GameState` with pawns, hands, deck, discard, dealer,
  deal cycle, folded/resigned seats, RNG, revision counter, result.
- **Move engine**: all thirteen cards, including
  - Ace = enter *or* +1, King = enter (or +13 as a house rule), Queen = +12
  - Four = exactly 4 backward, never into or out of home
  - Jack = swap with another seat's unprotected track pawn
  - Seven = every legal one- or two-leg split, including the §17 hand-off where
    the first leg finishes your own pawns and the rest is spent on a partner's
  - protected start squares as absolute blockades
  - exact home entry, no jumping over pawns already home
  - friendly capture (Classic) and its `landingForbidden` alternative
- **Turn flow**: 5/4/4 deal cycle, dealer rotation, forced move, automatic
  folding of dead hands while passing the turn, victory for teams and
  free-for-all, resignation policy (team forfeits / FFA player removed).
- **Generator/reducer parity**: the reducer accepts exactly what the generator
  offers; both go through one `MoveResolver`.
- **Versioned serialisation**: `GameStateEnvelope` carries `schemaVersion`,
  `engineVersion`, `rulesVersion` and an FNV-1a checksum. A payload from a newer
  schema, a damaged payload, or one over a transport limit is refused with a
  typed `SerializationError` — never partially restored. A played-out six-player
  state encodes to **4527 bytes**, about 7 % of Game Center's 64 KiB budget.
- **Byte-stable encoding**: `GameState` has a hand-written `Codable` that sorts
  its seat sets, because Swift's `Set` iteration order is salted per process and
  would otherwise make every checksum comparison unreliable.

---

## In Progress

Nothing is mid-edit. The working tree is clean at the commit above.

---

## Not Implemented Yet

- Xcode project, app target, shared schemes — the app does not build at all.
- AI of any strength; `PlayerObservation` boundary does not exist.
- All UI, all localisation, all audio/haptics, app icon.
- Game Center, persistence/autosave, statistics, replay, tutorial, rulebook.
- Fastlane, ci_scripts, Xcode Cloud, screenshot harness.

---

## Tests

Run with `cd Packages/KeezlyCore && swift test`.

| Suite | Tests | Status |
|---|---|---|
| BoardGraph | 9 | passed |
| Card rules | 26 | passed |
| Game flow | 16 | passed |
| Invariants | 6 | passed |
| Serialization | 11 | passed |
| **Total** | **68** | **68 passed, 0 failed** — 6.8 s |

App-level tests, run through the Xcode project on a simulator:

| Destination | Tests | Status |
|---|---|---|
| iPhone 17, iOS 27.0 | 7 | **7 passed, 0 failed** |
| iPad Pro 13" (M5), iOS 27.0 | 7 | **7 passed, 0 failed** |

Four Swift Testing functions (engine linked into the app, a full match played
inside the iOS runtime, serialisation round trip, bundle identifiers) plus three
XCUITests (launch, rotation, launch performance). Build is warning-free.

Several tests are parameterised over seat counts 2–6 or over card ranks, so the
number of executed cases is higher than the number of test functions.

The invariant suite plays **221 complete matches** to a finished result:
125 across seat counts 2–6, 32 free-for-all on 4 and 6 seats, and 64 across
eight rule-variant configurations. After every single applied action it asserts
pawn/card conservation, no duplicate occupancy, pawns never leaving home, and
monotonic revisions.

| Other test tracks | Status |
|---|---|
| UI tests | NOT RUN — no app target exists |
| AI simulation harness | NOT RUN — no AI exists |
| Screenshot runs | NOT RUN — no harness exists |
| Xcode Cloud | NOT RUN — not configured |

---

## Device Verification

Recorded per environment; these are never merged into one number (§167, §175).

| Environment | Status | Last run | Commit |
|---|---|---|---|
| Simulator — iPhone 17, iOS 27.0 | **PASSED** (7/7) | 2026-09-20 | `705497c` |
| Simulator — iPad Pro 13" (M5), iOS 27.0 | **PASSED** (7/7) | 2026-09-20 | `705497c` |
| Xcode Cloud | NOT RUN — not configured | — | — |
| Physical iPhone 17 Pro, iOS 27.0 | **PASSED** (11/11) | 2026-09-20 | `705497c` |
| Physical iPad | **BLOCKED** — no iPad paired (MAN-10) | — | — |
| Game Center multi-device | **BLOCKED** — not implemented (M6) | — | — |

### Device availability, checked 2026-09-20

`./scripts/devices.sh list` → exit 0.

| Role | Device | OS | Connection | Developer Mode | Usable |
|---|---|---|---|---|---|
| `PRIMARY_IPHONE` | iPhone 17 Pro (iPhone18,1) | 27.0 (24A437) | wired, tunnel connected | enabled | **yes — build and tests verified** |
| `PRIMARY_IPAD` | — | — | — | — | **none paired** |

An earlier check the same day found no physical devices at all; the iPhone was
connected afterwards. Device availability is therefore re-checked before every
device run rather than trusted from this file (§157).

**Resolved.** Team `KZFCCDV6A8` was chosen by the account owner, device
registration was authorised, and the device build and test run both succeeded:

- `xcodebuild build` for the physical iPhone — **Build Succeeded**, no warnings
- `bundle exec fastlane device_iphone` — **11 tests, 0 failures**, 261 s

The team id lives only in the git-ignored `Config/Local.xcconfig` (DEC-013).

Note for anyone reading `devicectl` output directly: it lists simulators too,
and a booted simulator reports as `connected`. The only reliable discriminator
is `hardwareProperties.reality`, which is what `scripts/devices.sh` filters on.

Simulators available: iOS 27.0, 26.5 and 26.3 runtimes covering iPhone 18 Pro /
18 Pro Max / 17 / 17e / Air / 16e and iPad Pro 13" (M5), iPad Pro 11" (M5),
iPad mini (A17 Pro), iPad Air 13"/11" (M4 and M3), iPad (A16).

Full strategy: `docs/DEVICE_TESTING.md`. Game Center matrix:
`docs/GAME_CENTER_DEVICE_TESTS.md`.

---

## Known Problems

None open. See `KNOWN_ISSUES.md` for the register (currently empty) and for the
two closed items from this session.

---

## Technical Risks

| Risk | Note |
|---|---|
| Seven-split combinatorics | Generating all split sequences copies the state per candidate leg. Fast enough now, but the Hard AI will call it inside rollouts. Measure before optimising. |
| Rule-source contradictions | Tournament rules are not yet verified against a primary source, so the Tournament preset currently equals Classic. Open questions are listed in `RULE_VARIANTS.md` rather than guessed. |
| `allowExtraLap` semantics | The "extra lap" house rule is implemented as an explicit route choice. This is an interpretation, documented as DEC-005; it needs a play-test before 1.0.0. |
| Two signing teams | The keychain holds certificates for two Apple Developer teams. Picking the wrong one would mean re-provisioning later and could split App Store Connect records. Resolved by MAN-03. |

---

## Manual Actions Required

| # | Action | Status |
|---|---|---|
| MAN-01 | Decide the bundle identifier | **DONE** — `de.gcng.keezly` (DEC-011) |
| MAN-02 | Create the App Store Connect app record for `de.gcng.keezly` | **OPEN — confirmed empirically**: the API lists 14 app records and this bundle id is not among them. Now the top blocker for TestFlight and Game Center. |
| MAN-03 | Apple Developer team for signing | **DONE** — team chosen, recorded in the git-ignored `Config/Local.xcconfig`, device registered, device build verified |
| MAN-04 | Authorise GitHub ↔ Xcode Cloud and enable Xcode Cloud | OPEN |
| MAN-05 | Enable the Game Center capability for the bundle id | OPEN |
| MAN-06 | Create Game Center leaderboards and achievements | OPEN |
| MAN-07 | Configure TestFlight testers | OPEN |
| MAN-08 | App Store Connect API key | **DONE & VERIFIED** — key file and credential env live outside the repository; `bundle exec fastlane asc_check` authenticates successfully |
| MAN-09 | Pair a physical iPhone with this Mac | **DONE** — iPhone 17 Pro, iOS 27.0, wired, Developer Mode enabled (verified 2026-09-20) |
| MAN-10 | Pair a physical iPad, same steps — required for the iPad quality gate | OPEN |
| MAN-11 | Provide a second Apple Account signed into Game Center, for multi-device online tests | OPEN |
| MAN-12 | Pair a second physical device for Game Center multi-device tests (an iPad would cover MAN-10 as well) | OPEN |

None of these can be completed from here. They are not blockers for the work
queued next.

MAN-10 blocks the iPad gate in `RELEASE_CHECKLIST.md`; MAN-10/11/12 block every
case in `docs/GAME_CENTER_DEVICE_TESTS.md`. MAN-02 blocks TestFlight, Game
Center configuration and Xcode Cloud. None of them blocks the next engineering
step (M3.1), but the device gates may not stay `BLOCKED` in a 1.0.0 release
candidate (§178).

---

## Decisions That Must Not Be Re-opened

See `DECISIONS.md` for the reasoning. In short:

- DEC-001 — `KeezlyCore` stays free of SwiftUI, GameKit and persistence.
- DEC-002 — project memory lives at the repository root; `docs/` holds detail.
- DEC-003 — all randomness goes through `SeededGenerator`; no direct stdlib RNG.
- DEC-004 — `MoveGenerator` is the only authority on legality; the reducer
  re-uses it rather than re-checking rules independently.
- DEC-005 — rule variation is expressed as named `RuleSet` options, never as
  ad-hoc booleans inside the generator.
- DEC-007 — the Xcode project is generated by XcodeGen from `project.yml` and
  the generated `.xcodeproj` is committed, so Xcode Cloud can build it.

---

## Relevant Files For The Next Step

- `Packages/KeezlyCore/Sources/KeezlyCore/Serialization/` — empty; the next
  work lands here.
- `Packages/KeezlyCore/Sources/KeezlyCore/Models/GameState.swift` — the type to
  wrap in a versioned envelope.
- `project.yml` — does not exist yet; needed for the app target.

---

## Next Steps (concrete)

1. **M3.1 — `PlayerObservation`.** Define the AI's information boundary before
   writing any agent code, so "the AI cannot cheat" is enforced by the type
   system rather than by discipline. It must expose the acting seat's own hand,
   all pawn positions, the discard pile, per-seat card counts, teams and phase —
   and offer no route whatsoever to another seat's hand or to the deck order.
   This is unblocked and is the next thing to build.
2. **M0.4 — `ci_scripts/`.** `ci_post_clone.sh` (log toolchain versions, set up
   Bundler), `ci_pre_xcodebuild.sh` (derive `CFBundleVersion` from
   `CI_BUILD_NUMBER`), `ci_post_xcodebuild.sh` (collect result bundles). Check
   what Ruby the current Xcode Cloud image ships before writing the first one.
3. **M0.5 — SwiftLint / SwiftFormat configuration**, wired into the `qa` lane.
4. **Once MAN-03 is answered — the physical iPhone gate.** Put the team into
   `Config/Local.xcconfig`, then `bundle exec fastlane device_iphone`. The
   device is already connected and Developer Mode is on, so this should run as
   soon as signing is settled.
