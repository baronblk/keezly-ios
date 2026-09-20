# Keezly — Decision Log

Architecture and product decisions, kept permanently (§133). A decision is
never deleted: if it is replaced, its status becomes `SUPERSEDED` and a new
entry explains why (§134).

Read this before making structural changes.

Status values: `ACCEPTED`, `SUPERSEDED`, `PROPOSED`.

---

## DEC-001 — GameCore is framework-free

- **Date:** 2026-09-20
- **Topic:** Module boundaries
- **Status:** ACCEPTED

**Context.** The rules of Keezen are intricate (forced moves, seven splits,
blockades, team hand-off). They need thousands of fast, headless test runs, and
they must behave identically in a SwiftUI view, in an AI rollout, and when
replaying a Game Center match.

**Decision.** `KeezlyCore` is a plain Swift package that imports nothing but
`Foundation`. No SwiftUI, no GameKit, no SwiftData, no UIKit.

**Reasoning.** It makes the rules testable with `swift test` in seconds without
a simulator, keeps AI simulation cheap, and prevents rules from leaking into
views. It also means the engine can be exercised by CI long before an app
target exists — which is exactly what happened in this first session.

**Alternatives rejected.** A single app target with the rules in view models
(untestable at scale, invites rule logic in views).

**Consequences.** Anything platform-specific — persistence, Game Center,
haptics — lives in the app layer and talks to the core through value types.

---

## DEC-002 — Project memory at the repository root, detail in `docs/`

- **Date:** 2026-09-20
- **Topic:** Documentation layout
- **Status:** ACCEPTED

**Context.** The specification refers to some documents bare (`APP_ICON.md`)
and to others with a path (`docs/APP_ICON.md`), which would place the same file
in two locations.

**Decision.** The fifteen project-memory files named in §127 live at the
repository root. Everything longer-form lives in `docs/`, including
`docs/APP_ICON.md`, `docs/PRIVACY.md`, `docs/GAME_CENTER_ACHIEVEMENTS.md`,
`docs/GAME_CENTER_LEADERBOARDS.md`, `docs/SCREENSHOTS.md`,
`docs/XCODE_CLOUD_SETUP_CHECKLIST.md`, `docs/UI_UX.md`,
`docs/ACCESSIBILITY.md`, `docs/TEST_PLAN.md`, `docs/APP_STORE.md`.

**Reasoning.** The memory files are read at the start of every session; keeping
them at the root makes them impossible to miss. Duplicating a document in two
places guarantees the two copies will disagree.

**Consequences.** Cross-references, not copies (§153).

---

## DEC-003 — All randomness flows through a serialisable seeded generator

- **Date:** 2026-09-20
- **Topic:** Determinism
- **Status:** ACCEPTED

**Decision.** `SeededGenerator` (SplitMix64) is the only source of randomness in
the engine. Its entire state is one `UInt64` and is part of `GameState`. Real
matches seed it from the system CSPRNG, and that seed is recorded.

**Reasoning.** Replay, Game Center synchronisation, AI simulation, and bug
reproduction all require that the same inputs produce the same match. Shuffling
is implemented as an explicit Fisher–Yates rather than `shuffled(using:)`,
because the standard library does not document its algorithm — relying on it
would make the guarantee depend on a Swift runtime implementation detail.

**Alternatives rejected.** `SystemRandomNumberGenerator` directly (not
reproducible); `arc4random` (no serialisable state).

**Consequences.** Any future non-determinism (for example a concurrent AI that
races) would be a bug, not a design trade-off.

---

## DEC-004 — The move generator is the single authority on legality

- **Date:** 2026-09-20
- **Topic:** Rule enforcement
- **Status:** ACCEPTED

**Context.** A board-game engine typically drifts when the UI filters moves one
way and the reducer validates them another.

**Decision.** `MoveGenerator` enumerates legal moves.
`GameReducer.applyMove` validates by asking whether the generator would have
produced that exact move. Both call one `MoveResolver` for the elementary
mechanics (blocking, landing, capture).

**Reasoning.** "The generator offered it" and "the reducer accepts it" become
the same statement, and the property is testable directly — which the
`generatorAndReducerAgree` test does.

**Consequences.** Move generation must stay fast enough to run inside
validation. If profiling ever shows this is too slow, the fix is caching, not a
second rule implementation.

---

## DEC-005 — Rule variation is expressed as named options, not scattered flags

- **Date:** 2026-09-20
- **Topic:** Rule variants
- **Status:** ACCEPTED

**Context.** Keezen has strong regional and family variation. §18 explicitly
forbids handling this with booleans sprinkled through the move generator.

**Decision.** Every variation point is a named enum on `RuleSet`
(`KingBehavior`, `JackOwnStartPolicy`, `HomeEntryPolicy`, `HomeOrderingPolicy`,
`FriendlyCapturePolicy`, `OwnPawnBlockingPolicy`). The `RuleSet` is part of
`GameConfiguration` and therefore of the serialised match, and never changes
mid-match.

**Sub-decision — `allowExtraLap` semantics.** The "extra lap" house rule is
modelled as an explicit `AdvanceRoute` on the move: when both are legal, the
player is offered *both* turning into home and riding past their own entry.
This is an interpretation of an under-specified variant; it needs a play-test
before 1.0.0 and is recorded as RULE-005 in `RULE_VARIANTS.md`.

**Consequences.** Adding a variant means adding an enum and a test, not
touching branching logic in five places.

---

## DEC-006 — Game Center online play uses turn-based GameKit

- **Date:** 2026-09-20
- **Topic:** Online multiplayer architecture
- **Status:** ACCEPTED (design only — nothing implemented yet)

**Decision.** Online matches use the current GameKit turn-based multiplayer
API, not real-time `GKMatch`.

**Reasoning.** Keezly is turn-based, matches must survive app restarts and days
of inactivity, several matches run in parallel, and no continuous connection is
needed or wanted.

**Alternatives rejected.** Real-time `GKMatch` as the primary system; a custom
server (adds privacy surface, cost, and an account system the product does not
want).

**Consequences.** `GameState` needs a compact versioned serialisation that fits
`matchDataMaximumSize`, and every turn submission must be idempotent with
revision guards. Tracked as M2.9 and M6.4/M6.5.

---

## DEC-007 — The Xcode project is generated by XcodeGen and committed

- **Date:** 2026-09-20
- **Topic:** Project file management
- **Status:** ACCEPTED (not yet executed — M0.2)

**Context.** Xcode Cloud needs a real `.xcodeproj` in the repository. Hand-edited
`project.pbxproj` files are merge-hostile and cannot be reviewed meaningfully.

**Decision.** `project.yml` is the source of truth; `xcodegen generate` produces
`Keezly.xcodeproj`, and the generated project **is committed**.

**Reasoning.** The reviewable diff lives in `project.yml`, while Xcode Cloud and
a plain `git clone` still get a working project without extra tooling.

**Alternatives rejected.** Tuist (heavier, not installed); committing only
`project.yml` and generating in `ci_post_clone.sh` (adds a hard tooling
dependency to every clean build, and a generation failure then breaks CI in a
confusing way).

**Consequences.** After editing `project.yml`, regenerate and commit both.
A CI check should verify the committed project matches the manifest.

---

## DEC-008 — Xcode Cloud owns archiving and TestFlight; fastlane owns local automation

- **Date:** 2026-09-20
- **Topic:** CI/CD responsibility split
- **Status:** ACCEPTED (design only)

**Decision.** Xcode Cloud performs the official build, test, analyze, archive,
signing and TestFlight distribution. fastlane provides reproducible local
automation: test lanes, screenshot generation, metadata, and the release gate.
fastlane does not produce a second archive or a parallel TestFlight upload of
the same build.

**Reasoning.** Two pipelines producing the same artifact is how build
provenance becomes ambiguous. Apple's hosted pipeline handles signing best;
fastlane is better at repeatable local QA and the screenshot matrix.

**Consequences.** A developer can still build, test, screenshot and QA entirely
locally without Xcode Cloud — that is a requirement, not a side effect.

---

## DEC-009 — `GameState` has a hand-written, byte-stable `Codable`

- **Date:** 2026-09-20
- **Topic:** Serialisation determinism
- **Status:** ACCEPTED

**Context.** Saved matches and Game Center payloads are checksummed so a
damaged or mismatched state is caught rather than silently used. A checksum is
only meaningful if encoding the same state always produces the same bytes.

Swift's synthesised `Codable` does not give that here: `GameState` holds
`Set<Seat>` for folded and resigned seats, and `Set` iteration order is salted
per process. Two launches of the same build would have produced different bytes
and therefore different checksums for an identical board.

**Decision.** `GameState` implements `encode(to:)` and `init(from:)` by hand,
writing both seat sets as sorted arrays. The shared encoder uses `.sortedKeys`.
`GameStateCoding` is the single entry point, so nothing can accidentally encode
with a differently configured encoder.

**Reasoning.** It makes "the same state ⇒ the same bytes" a property we test
directly, which in turn makes the checksum, online state comparison and replay
verification trustworthy.

**Alternatives rejected.** Storing the sets as sorted arrays in the type itself
(loses set semantics at every use site, and the ordering guarantee would then
depend on every mutation site being careful); checksumming a normalised
projection instead of the real encoding (two representations to keep in sync).

**Consequences.** Any new stored property on `GameState` must be added to the
hand-written coder, and anything order-dependent must be sorted there.
`SerializationTests.setsEncodeDeterministically` fails loudly if this is missed.

---

## DEC-010 — Three independent version numbers, and decoding refuses rather than guesses

- **Date:** 2026-09-20
- **Topic:** Save/transport compatibility
- **Status:** ACCEPTED

**Decision.** `GameStateEnvelope` carries `schemaVersion` (stored shape),
`engineVersion` (informational, for diagnostics) and `rulesVersion` (semantics
that affect which moves are legal). Decoding a payload whose `schemaVersion` is
newer than this build understands throws
`SerializationError.unsupportedSchemaVersion` instead of decoding on a
best-effort basis.

**Reasoning.** Partially understanding a newer match is how a board silently
ends up wrong — the single worst failure mode for a turn-based game synced
across devices. A refusal is recoverable and explainable to the player; a
quietly mis-read board is not.

The three numbers are separate because they change for different reasons: a
pure refactor bumps none, a stored-shape change bumps the schema, and a rule
change bumps the rules version because an old client replaying a new match
would compute a different board even from correctly decoded data.

**Consequences.** Every error case needs a player-readable message; the UI must
handle "this match was saved by a newer version of Keezly" without losing the
user's other matches.
