# Keezly — Known Issues

Register of reproducible technical problems (§137). Status values:
`OPEN`, `INVESTIGATING`, `FIXED`, `VERIFIED`. An issue only becomes `VERIFIED`
after a test has actually been run and passed.

Open work that is not a defect belongs in `ROADMAP.md`, not here (§141).

---

## Open

*None.*

---

## Closed

### ISS-001 — Move generator failed to compile due to name shadowing

- **Status:** VERIFIED
- **Severity:** Blocker (build)
- **Component:** `KeezlyCore` / Engine
- **Description:** A local variable `moves` shadowed the private
  `moves(in:seat:card:)` function, so the recursive call was parsed as a
  subscript on an array.
- **Reproduction:** `swift build` at the time of writing `MoveGenerator.swift`.
- **Expected:** Compiles.
- **Actual:** `error: cannot call value of non-function type '[Move]'`.
- **Fix:** Renamed the function to `generateMoves(in:seat:card:)`.
- **Related files:** `Packages/KeezlyCore/Sources/KeezlyCore/Engine/MoveGenerator.swift`
- **Verified by:** `swift build` and the full suite at commit `64931ef`.

### ISS-002 — Jack could target a seat with no pawns of its own on the track

- **Status:** VERIFIED
- **Severity:** Major (rule correctness)
- **Component:** `KeezlyCore` / Engine
- **Description:** `swapActions` excluded swap targets by comparing against the
  acting player's pawns *that were currently on the track*, rather than against
  the set of seats the player controls. When a controlled seat had no pawn on
  the track, that seat's own pawns became valid swap targets.
- **Reproduction:** Found by inspection before it reached a test run; would have
  surfaced as a finished player being able to swap their partner's pawns against
  each other.
- **Expected:** A Jack always trades one of your pawns for a *different* seat's.
- **Actual:** Could have targeted a controlled seat's own pawn.
- **Fix:** Exclude targets by `controllableSeats(for:)` instead.
- **Related files:** `Packages/KeezlyCore/Sources/KeezlyCore/Engine/MoveGenerator.swift`
- **Related tests:** `CardRuleTests.jackMayTargetPartner`,
  `CardRuleTests.jackRespectsProtectionAndHome`
- **Verified by:** full suite at commit `64931ef`.

### ISS-003 — Degenerate test fixture masked correct redeal behaviour

- **Status:** VERIFIED
- **Severity:** Minor (test only, not a product defect)
- **Component:** Tests
- **Description:** `foldingIsAllowedWhenNothingIsPlayable` built a state where
  *every* seat had an unplayable or empty hand. The engine correctly concluded
  that the deal round was over and started a new one, which clears the folded
  set by design — so the assertion on `foldedSeats` failed.
- **Expected:** The test asserts the fold, not the redeal.
- **Actual:** The fixture forced an immediate redeal.
- **Fix:** Give a second seat a playable card so the round continues. The engine
  was not changed; it was already right.
- **Related files:** `Packages/KeezlyCore/Tests/KeezlyCoreTests/GameFlowTests.swift`
- **Verified by:** full suite at commit `64931ef`.
