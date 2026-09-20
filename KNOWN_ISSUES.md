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

### ISS-005 — A cancelled Hard search kept running to the end of its rollout

- **Status:** VERIFIED
- **Severity:** Major (responsiveness)
- **Component:** `KeezlyCore` / AI
- **Description:** `HardAgent` checked `Task.isCancelled` between candidates and
  between samples, but `RolloutPolicy.playOut` — the longest uninterrupted
  stretch of work an agent does — checked nothing. A cancelled search therefore
  finished whatever playout was in flight before noticing.
- **Reproduction:** `HardAgentTests.cancellationIsHonoured` with a deliberately
  oversized search (64 candidates, 100 000 samples, 200 plies): cancelling
  immediately still took **5.2 seconds** to return.
- **Expected:** a cancelled search returns promptly with a legal move (§62).
- **Actual:** it returned only after the current rollout completed.
- **Fix:** check `Task.isCancelled` inside the playout loop, and stop sampling
  after a rollout that was cut short rather than averaging in a truncated
  result.
- **Effect:** the Hard agent suite went from 7.4 s to 1.4 s.
- **Related files:** `Sources/KeezlyCore/AI/RolloutPolicy.swift`,
  `Sources/KeezlyCore/AI/HardAgent.swift`
- **Related tests:** `HardAgentTests.cancellationIsHonoured`,
  `HardAgentTests.budgetIsRespected`
- **Note:** the test passed on an earlier run and failed on a later one — the
  timing depended on how much of the task ran before `cancel()` landed. A
  responsiveness guarantee asserted with a generous bound is worth having
  precisely because it catches this kind of thing eventually.

### ISS-004 — Apple Developer team ids were committed to documentation

- **Status:** FIXED (working tree) — see "remaining exposure" below
- **Severity:** Low
- **Component:** Documentation / process
- **Description:** While recording the signing decision, two Apple Developer
  team ids were written into `CURRENT_STATE.md`, contradicting DEC-013, which
  says account-specific signing configuration never enters the repository.
- **How it was caught:** the repository-wide secret sweep that runs after
  credential work, not by review. The sweep is worth keeping for that reason.
- **Fix:** both ids removed from all tracked files; the team id now exists only
  in the git-ignored `Config/Local.xcconfig`.
- **Remaining exposure:** the ids are still present in pushed history, in
  commit `497accf`. An Apple **Team ID is an identifier, not a credential** — it
  appears in every shipped app's provisioning profile and cannot be used to
  authenticate — so the practical risk is negligible. Removing it entirely would
  need a history rewrite and a force push, which is the repository owner's call.
- **Not affected:** the App Store Connect **key id, issuer id and `.p8` private
  key never entered the repository** at any point. They live outside it, and the
  swept files confirm that.
- **Related files:** `CURRENT_STATE.md`, `Config/Local.xcconfig` (untracked),
  `DECISIONS.md` → DEC-013

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
