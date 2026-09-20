# Keezly

A modern native iOS and iPadOS version of the traditional Dutch board game
**Keezen** — cards instead of dice, four pawns each, two to six players, solo or
in teams.

App Store name: **Keezly: Keezenspel** · Target version **1.0.0**

---

## Status

**In development.** The rules engine is complete and tested; the app itself does
not build yet.

| | |
|---|---|
| Rules engine (`KeezlyCore`) | implemented, 57 tests green |
| App, UI, AI, Game Center, CI | not started |

The authoritative status is always [`CURRENT_STATE.md`](CURRENT_STATE.md).

---

## Getting started

```bash
cd Packages/KeezlyCore && swift test
```

That runs the full rule suite, including 221 complete randomised matches across
every supported table size and rule variant.

Requires Xcode 27 / Swift 6.4.

---

## Where to look

| Document | Purpose |
|---|---|
| [`PROJECT_HANDOUT.md`](PROJECT_HANDOUT.md) | Start here — what Keezly is, how it is built |
| [`CURRENT_STATE.md`](CURRENT_STATE.md) | What works right now, and the next concrete step |
| [`ROADMAP.md`](ROADMAP.md) | Milestones, tasks, acceptance criteria |
| [`DECISIONS.md`](DECISIONS.md) | Why the architecture is the way it is |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Layers, boundaries, data flow |
| [`RULES.md`](RULES.md) | How the game is played |
| [`RULE_VARIANTS.md`](RULE_VARIANTS.md) | Every rule variant, its source and its switch |
| [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md) | Open defects |
| [`CHANGELOG.md`](CHANGELOG.md) | What changed |

---

## Originality

Keezly implements a traditional public-domain game concept. All artwork, card
and board designs, pawn geometry, rule texts, sounds and the app icon are
created for this project. Nothing is taken from any competing product.
