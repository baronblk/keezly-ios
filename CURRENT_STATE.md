# Keezly — Current State

**This file is the operative memory of the project (§128).** It describes what
is true right now, not what is planned. Plans live in `ROADMAP.md`.

---

## Last Verified Commit

```
1bb9109  test(core): cover serialization round trip, versioning and size limits
```

Everything below was verified against that commit on **2026-09-20** with
Xcode 27.0 / Swift 6.4 on macOS 26 (arm64).

---

## Current Milestone

**M0 — Repository & Foundation**: IN PROGRESS
**M1 — GameCore / Rules**: DONE
**M2 — Complete Move Engine**: IN PROGRESS (only M2.10, the replay move log, is left)

M1 was completed ahead of the remaining M0 tooling work, because the rules
engine is testable with `swift test` alone and does not need the Xcode project.

---

## Completed

### Repository (M0, partial)
- Git repository initialised, `main` tracking `origin/main`.
- Secret-safe `.gitignore` (keys, profiles, `.env`, certificates).
- Directory skeleton for app, package, fastlane, ci_scripts, docs, brand assets.

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
| Simulator — iPhone | NOT RUN — no app target exists | — | — |
| Simulator — iPad | NOT RUN — no app target exists | — | — |
| Xcode Cloud | NOT RUN — not configured | — | — |
| Physical iPhone | **BLOCKED** — no device paired | — | — |
| Physical iPad | **BLOCKED** — no device paired | — | — |
| Game Center multi-device | **BLOCKED** — no devices, no implementation | — | — |

### Device availability, checked 2026-09-20

`./scripts/devices.sh list` → exit 3, **no physical iPhone or iPad is paired
with this Mac.** Verified three ways rather than assumed (§157):

- `xcrun devicectl list devices` → 7 entries, every one
  `hardwareProperties.reality = "simulated"`
- `xcrun xctrace list devices` → only the host Mac under "Devices"
- `~/Library/MobileDevice/Provisioning Profiles/` → empty

This is a device-availability state, **not a Keezly defect** (§166). Everything
not blocked by it continues (§142).

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
| Ruby version for fastlane | System Ruby is 2.6.10, too old for a modern Bundler-based fastlane. Homebrew `ruby@4.0` and `mise` are available; the choice is not made yet. |

---

## Manual Actions Required

| # | Action | Status |
|---|---|---|
| MAN-01 | Decide the bundle identifier | OPEN |
| MAN-02 | Create the App Store Connect app record | OPEN |
| MAN-03 | Select the Apple Developer team for signing | OPEN |
| MAN-04 | Authorise GitHub ↔ Xcode Cloud and enable Xcode Cloud | OPEN |
| MAN-05 | Enable the Game Center capability for the bundle id | OPEN |
| MAN-06 | Create Game Center leaderboards and achievements | OPEN |
| MAN-07 | Configure TestFlight testers | OPEN |
| MAN-08 | Provide an App Store Connect API key (outside the repo) | OPEN |
| MAN-09 | Pair a physical iPhone with this Mac (cable or wireless), unlock it, trust the computer, enable Developer Mode | OPEN |
| MAN-10 | Pair a physical iPad, same steps — required for the iPad quality gate | OPEN |
| MAN-11 | Provide a second Apple Account signed into Game Center, for multi-device online tests | OPEN |

None of these can be completed from here. They are not blockers for the work
queued next.

MAN-09 and MAN-10 block the physical-device gates in `RELEASE_CHECKLIST.md` and
every case in `docs/GAME_CENTER_DEVICE_TESTS.md`. Since no app target exists
yet, they are not blocking today's work either — but they must be resolved
before a 1.0.0 release candidate, because those gates may not stay `BLOCKED`
(§178).

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

1. **M0.2 — Xcode project.** Write `project.yml` for an app target `Keezly`
   (iPhone + iPad, iOS 17 deployment target, `MARKETING_VERSION = 1.0.0`)
   depending on the local `KeezlyCore` package, generate with `xcodegen`, mark
   the scheme shared, and commit the generated `.xcodeproj`.
2. **M0.3 — fastlane skeleton.** Decide the Ruby toolchain first (see Risks),
   then `Gemfile` + `fastlane/Fastfile` with the `tests` lane wrapping
   `swift test`, so there is a single reproducible command before any UI exists.
3. **M3.1 — `PlayerObservation`.** Define the AI's information boundary before
   writing any AI, so no agent can ever read another seat's hand.
