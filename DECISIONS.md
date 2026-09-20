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
