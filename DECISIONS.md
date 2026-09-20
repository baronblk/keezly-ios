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
- **Status:** ACCEPTED (executed 2026-09-20 — M0.2 done)

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

---

## DEC-011 — Bundle identifier `de.gcng.keezly`

- **Date:** 2026-09-20
- **Topic:** Product identity
- **Status:** ACCEPTED

**Decision.** The canonical bundle identifier is **`de.gcng.keezly`**, with
`de.gcng.keezly.tests` for unit tests and `de.gcng.keezly.uitests` for UI tests.

It is used consistently for the Xcode project, signing, Apple Developer, App
Store Connect, Game Center, Xcode Cloud and everything derived from them. No
alternative identifier is used in parallel.

**Reasoning.** Reverse-DNS on a domain the owner controls, which keeps the
identifier stable regardless of account names. Chosen by the product owner.

**Consequences.** Any App Store Connect record, Game Center configuration and
provisioning profile must be created against exactly this identifier. Changing
it later would mean a new App Store record, so it is treated as fixed.

---

## DEC-012 — fastlane through Bundler, Ruby pinned declaratively

- **Date:** 2026-09-20
- **Topic:** Build toolchain
- **Status:** ACCEPTED

**Context.** macOS system Ruby is 2.6.10, far too old for a current fastlane.
Homebrew already provides Ruby 4.0.5, and `mise` is installed but has no Ruby
built — installing one would mean compiling from source.

**Decision.** Pin the Ruby version declaratively in `.tool-versions` and
`.ruby-version` (4.0.5), which `mise`, `asdf` and `rbenv` all understand, but do
**not** make a version manager a prerequisite. Homebrew's `ruby` satisfies the
pin today. fastlane is always run through Bundler, with its exact version fixed
by a committed `Gemfile.lock`.

**Reasoning.** The reproducibility that matters is "everyone runs the same
fastlane", which `Gemfile.lock` guarantees. Forcing a source compile of Ruby on
every machine and CI image buys little and costs minutes per clean build.

**Alternatives rejected.** Requiring `mise install ruby` (slow, and the Xcode
Cloud image ships its own Ruby anyway); a globally installed fastlane
(unpinned, drifts between machines).

**Consequences.** `ci_post_clone.sh` must check what Ruby the Xcode Cloud image
actually provides rather than assuming this version (M0.4).

---

## DEC-013 — The signing team never enters the repository

- **Date:** 2026-09-20
- **Topic:** Signing configuration
- **Status:** ACCEPTED

**Context.** A device build needs `DEVELOPMENT_TEAM`. Committing it hard-codes
one developer's account into a shared project, and the project rules forbid
guessing a signing team at all.

**Decision.** `Config/Keezly.xcconfig` is committed and contains nothing but an
*optional* include of `Config/Local.xcconfig`, which is git-ignored.
`Config/Local.xcconfig.example` documents what to put there. Simulator builds
and `swift test` work with no local file present.

**Reasoning.** It keeps device signing working per-developer without a
machine-specific value ever being tracked, and it degrades gracefully: a missing
optional include is not an error.

**Alternatives rejected.** `DEVELOPMENT_TEAM` in `project.yml` (tracked,
account-specific); passing it on every command line (easy to forget, and it
would end up pasted into documentation).

**Consequences.** A fresh clone cannot build to a device until the developer
creates `Config/Local.xcconfig`. That is documented in `PROJECT_HANDOUT.md` and
is the intended trade-off.

---

## DEC-014 — Agents receive an observation, never the game state

- **Date:** 2026-09-20
- **Topic:** AI honesty
- **Status:** ACCEPTED

**Context.** §21 requires that no difficulty level is achieved by cheating: a
computer opponent must not see another player's hand or the order of the deck.
Stating that as a rule for implementers to follow is not enough — the first
agent that takes a shortcut inside a rollout breaks it silently, and nothing
fails.

**Decision.** `AIAgent.chooseAction` takes a `PlayerObservation` and nothing
else. `PlayerObservation` has exactly one initialiser, `init(of:for:)`, which
copies the observer's own hand, all pawn positions, the discard pile, per-seat
card *counts*, teams, phase and the legal moves — and drops the deck, the RNG
and every other hand.

**Reasoning.** An agent cannot read what it was never handed. Reviewing one
initialiser is tractable; auditing every agent for discipline is not.

**How it is enforced beyond the type.** Differential tests: two states that
differ only in opponents' hands, deck order or generator state must produce
equal observations, and states differing in public information must not. The
tests were verified to fail when a leak is deliberately injected, so they are
known to be load-bearing rather than vacuous.

**Alternatives rejected.** Passing `GameState` with a convention not to touch
hidden fields (unenforceable, and a rollout is exactly where the shortcut is
tempting); marking hidden fields `internal` (the agents live in the same module,
so it would not help at all).

**Consequences.** If an agent needs a fact it cannot see, the fact is added to
`PlayerObservation` deliberately and the differential tests re-run — widening
the boundary is a visible, reviewed act. Hard AI's information-set sampling must
draw only from `unseenCards`.

---

## DEC-015 — Move previews widen the AI boundary, deliberately

- **Date:** 2026-09-20
- **Topic:** AI honesty
- **Status:** ACCEPTED
- **Extends:** DEC-014

**Context.** The first real agent exposed a gap: `PlayerObservation` told an
agent which moves were legal but not what any of them would *do*. Without that,
an agent cannot tell a capture from a shuffle and there is nothing to weigh.

The tempting fix — hand the agent a `GameState` so it can apply moves itself —
would have destroyed DEC-014 entirely.

**Decision.** `PlayerObservation` gained `preview(_:)` and `previewAll()`,
returning the board transition a move would produce. The implementation builds
a *shadow state* from observation fields alone — the observer's own hand, the
pawns, the discard pile, no draw pile, no other hands — and reuses
`GameReducer.performAction` on it. The shadow is private; agents see only the
resulting `MovePreview`.

**Reasoning.** A human at the table can see exactly this: the board is open and
the rules are known, so working out "that Seven lands me there and knocks his
pawn out" is ordinary play. Reusing the real move mechanics also means a
preview cannot drift away from what the reducer actually does, which is
asserted directly over 150 random moves.

**How it was verified.** The differential tests were extended to previews —
two states differing only in opponents' hands, deck order or generator state
must produce identical previews — and the mutation test was repeated: injecting
`state.hands` into the observation now fails *two* tests rather than one.

**Consequences.** This is the pattern for every future widening: check that a
real player would have the information, add it at the one chokepoint, extend
the differential tests, re-run the mutation, and record it here. `stableKey`
was added under the same reasoning, and is derived purely from observation
fields so agents can seed themselves reproducibly from a position.

---

## DEC-016 — SwiftFormat runs an allowlist, SwiftLint is the gate

- **Date:** 2026-09-20
- **Topic:** Static checks
- **Status:** ACCEPTED

**Context.** Adopting SwiftFormat with its default rule set wanted to rewrite
41 of 48 files. Inspecting the diff showed the changes were not improvements:
`hoistPatternLet` turns `case .advance(let pawn, let steps, let route)` into
`case let .advance(pawn, steps, route)`, hiding which bindings a case
introduces; `consecutiveSpaces` flattens the aligned trailing comments that
explain the rules; `wrapPropertyBodies` expands one-line computed properties.

**Decision.** SwiftFormat runs an explicit **allowlist** — import order and
whitespace hygiene — via `--rules`. SwiftLint is the enforced gate, configured
to catch things that cause bugs rather than to impose a house style:
force-unwrapping, implicitly unwrapped optionals, complexity and length limits.
Both run in the `lint` lane and inside `qa`; `release_check` runs SwiftLint with
`--strict`, so warnings fail a release candidate.

**Reasoning.** A formatter earns its place by ending style arguments, not by
starting one with the existing code. Restricting it to the uncontested rules
keeps that benefit at zero readability cost. Adopting three rules that are
already satisfied everywhere is better than adopting thirty that require a
500-file diff nobody will review.

**What it caught immediately.** Three force-unwraps in shipping code
(`MediumAgent`, `RolloutPolicy`, `SimulationReport`) and two in tests, all
fixed rather than suppressed.

**Consequences.** `swiftlint lint --strict` must stay clean. If a rule becomes
more trouble than it is worth, it is disabled here with a reason rather than
silenced inline.

---

## DEC-017 — The board is a squared ring, drawn from our own curve

- **Date:** 2026-09-20
- **Topic:** Board form
- **Status:** ACCEPTED

**Context.** The first board rendering placed the track on a gentle superellipse
(exponent 4), which read as a circle. A reference photograph of a physical
Keezen board — a commercial product — was supplied for inspiration, and it makes
the traditional form plain: a **square** ring with straight runs of holes and
corners, home lanes running perpendicular inward, and the cards played in the
centre.

**The line between the two.** The traditional *form* of a Keezen board belongs
to the game and to nobody in particular: a square track, four-square home lanes,
waiting areas beside each seat. A specific publisher's **artwork** — their board
graphics, colours, hole rendering, card faces, logo — does not, and §76 forbids
reproducing it.

**Decision.** Keep the parametric superellipse, but raise its exponent to 8. The
sides become straight runs of squares with softly rounded corners: the shape
players expect, generated from our own curve, at any seat count from two to six.
Nothing is traced, measured or copied from the reference. The centre of the
board is reserved for the draw and discard piles, which is where the cards go on
a physical board and where the eye looks for them.

**Reasoning.** A round track is a wheel; a square one is a board. Matching the
familiar form costs nothing in originality — the visual language (colours,
materials, pawn geometry, card design, the marks on the pieces) is entirely ours
— and it saves every player the moment of "what am I looking at".

**Rejected.** Reproducing the reference's layout square for square; adding
imitation wood grain (§43 asks for restrained materiality, not skeuomorphism).

**Consequences.** `BoardLayout.ringExponent` is the single knob for this. The
layout tests already bound how far seat-to-seat geometry may diverge, and they
gate any future change to it.

---

## DEC-018 — Tactile Digital Board Game, in Classic Wood

- **Date:** 2026-09-20
- **Topic:** Visual direction
- **Status:** ACCEPTED
- **Supersedes the material choices in:** the first board rendering

**Context.** The first playable board used grey rounded rectangles on a flat
surface. It worked and it was legible, but it read as a prototype: flat
business UI wearing a board game's rules. The product owner corrected the
direction explicitly.

**Decision.** The visual language is **tactile digital board game**, with
**Classic Wood** as the default and the quality bar for 1.0.0:

- a light maple panel with milled, *round* holes — a dark floor, a shadow under
  the upper rim and a lit lower lip, which together read as carved;
- pieces as classic pawn silhouettes with weight and a contact shadow, not flat
  markers;
- cards as real playing cards — cream faces, classic corner indices, traditional
  pip layouts, drawn suits;
- the centre of the board kept quiet, because a board should look like a board
  and not like a dashboard.

`BoardTheme` carries the material as a value, so Dark Graphite can follow
without touching the renderer. A theme is not an appearance: Classic Wood is the
same board in light and dark mode, dimmed rather than recoloured.

**The originality line.** A photograph of a commercial Keezen board was supplied
as a reference. What is taken from it is materiality and the traditional *form*
of the game — a square track, holes, home lanes, cards in the middle — which
belong to the game and to nobody in particular. Every graphic in Keezly is
drawn from our own geometry: the superellipse ring, the pawn silhouette, the
suit paths, the court emblems, the card back. Nothing is traced, measured or
sampled from the reference (§76).

**Reasoning.** §80 asks one question of every decision: would this be credible
in a high-quality iPad board game? Grey rectangles were not. The change is
purely presentational — `GameCore`, the rules, the AI and determinism are
untouched, and no rule is coupled to a visual component.

**Consequences.** Materials are drawn, never photographed: a photographic wood
texture at board scale reads as a cheap tiling artefact. The renderer stays a
single `Canvas` for everything static, because a turn-based board game must not
run a render loop (§62).

---

## DEC-019 — A quiet Dutch identity, as ornament rather than illustration

- **Date:** 2026-09-20
- **Topic:** Visual direction
- **Status:** ACCEPTED
- **Extends:** DEC-018

**Context.** Keezen is a Dutch game. The board said nothing about that. The
obvious way to fix it is also the wrong one: windmills, clogs, tulip fields and
flags would turn a premium board into an airport souvenir, and the product
owner ruled that out explicitly.

**Decision.** Dutch origin is expressed as **ornament, never illustration**,
and always in the material rather than on top of it:

- a running border engraved into the rim — an abstracted tulip alternating with
  a concave lozenge, between two fine incised lines;
- a medallion framing the cards in the middle, with one petal in each gap
  between the home lanes;
- a small chevron engraved where each home lane ends, pointing the way the
  pawns travel;
- **Delft blue** as a secondary accent at low opacity, never as a player colour;
- **exactly one** orange detail on the whole board — a keystone at the top of
  the medallion.

Everything is drawn the way the milled holes are drawn: a lit lip under a dark
incision. That is what makes it part of the board rather than a decal.

**The originality line, again.** No Delft tile pattern, border or board graphic
is traced or reproduced. The motifs are built from Keezly's own proportions —
a leaf of one construction used at three sizes, and a lozenge of one
construction. The tradition is the inspiration; the geometry is ours.

**Three constraints that shaped it.**

1. **Ornament must never be mistakable for a playing square.** Tested, not
   assumed: every motif keeps a measured clearance from every square, at every
   seat count. The first attempt failed this test against the waiting trays, so
   the board's rim was widened rather than the ornament squeezed in.
2. **It must survive being small.** The first tulip, a bud with curling strokes
   and a stem, read as a stray squiggle at the size it is actually drawn. Three
   symmetric leaves survive. Below roughly nine points per square the motifs are
   dropped entirely and only the border lines remain — a phone gets the frame,
   not the detail.
3. **It must fit every table.** The medallion is measured against the board's
   own inner field, not in square widths. At two seats there is no quiet centre
   at all, and it is simply not drawn (ISS-008).

**Consequence.** The board's rim is wider than before, so the playing area is
about six percent smaller in the same space. That is the price of a frame that
can hold a border, and it was paid deliberately.

---

## DEC-020 — The keyboard is decided in pure logic, not in the view

- **Date:** 2026-09-20
- **Topic:** iPad input
- **Status:** ACCEPTED

**Context.** M4.7 asks for pointer, trackpad and full keyboard access. The
obvious implementation scatters `onKeyPress` handlers through the view tree,
where none of it can be tested — and a hardware keyboard turns out to be the
one input this project cannot reproduce automatically at all.

**Decision.** The entire keyboard contract lives in two pure types:

- `FocusRing` — everything reachable right now, in bands (hand, pieces,
  squares), built from the same facts `PlayPlanner` works from.
- `PlayKeyboard` — a function from (key, focus, ring) to an intent.

The view holds a `@FocusState` and does nothing but apply intents. Every rule
worth having — that unplayable cards are skipped, that squares are walked in a
stable order, that stale focus recovers, that escape always works, that every
legal move is reachable — is a unit test.

**Focus is not selection.** Selection is a choice the engine will act on; focus
is where the keyboard happens to be. Keeping them separate is what stops
keyboard support from quietly changing the game.

**The consequence we accepted.** Because the logic is pure, the untestable part
shrinks to one question: does iOS deliver the key press? That question is left
explicitly unanswered rather than assumed — the UI tests that need real keys
**skip**, and `RELEASE_CHECKLIST.md` carries the hardware gate as NOT VERIFIED.
A green test that exercised nothing would be worse than a recorded gap (§177).
